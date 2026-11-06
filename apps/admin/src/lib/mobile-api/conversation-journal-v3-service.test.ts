import {
  parseFeedbackV3Registration,
  prepareRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { journalAuth, journalClinical, journalCommand } from './__fixtures__/conversation-journal'
import {
  threadDescriptor,
  threadEdit,
  threadGoldenPage,
  threadReport,
  threadSavedReport,
} from './__fixtures__/conversation-thread-page'
import { bindConversationIntake } from './conversation-intake-contracts'
import { createConversationJournalV3Service } from './conversation-journal-v3-service'
import { workoutDigest, workoutUUID } from './conversation-workout-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { readCurrentClinicalState } from './current-clinical-state'
import actualJournal from './testing/conversation-journal-v3-pg-golden.json'
import actualWorkout from './testing/conversation-workout-reconcile-pg-golden.json'

function setup() {
  const auth = journalAuth(),
    who = {
      ...auth,
      identity: { ...auth.identity, email: 'synthetic-journal-v3@example.invalid' },
    },
    epoch = workoutUUID.parse(journalClinical().epoch),
    at = '2026-11-04T12:02:00.000002Z'
  let readCompleted = false
  const raw = {
      action: 'available',
      schema: 'conversation.journal-page-private.v3',
      owner_id: who.userId,
      epoch,
      observed_at: at,
      intakes: [],
      workouts: [],
      items: [],
      has_more: false,
      next_cursor: null,
      meal_page: {
        action: 'available',
        schema: 'conversation.journal-page-private.v2',
        owner_id: who.userId,
        epoch,
        observed_at: at,
        threads: [],
        items: [],
        has_more: false,
        next_cursor: null,
      },
    },
    rpc = vi.fn(async (name: string, _args: unknown): Promise<unknown> => {
      if (name !== 'read_conversation_journal_page_v3')
        throw new Error('No other domain or provider call for empty history')
      readCompleted = true
      return { data: raw, error: null }
    }),
    from = vi.fn(() => {
      throw new Error('Auth dependencies are explicitly supplied; no bootstrap/table write')
    }),
    currentAuth = {
      verifyAccessToken: vi.fn(async () => who.identity),
      loadPatient: vi.fn(async () => who.patient),
      isAdmin: vi.fn(async () => false),
    },
    capture = vi.fn(async () =>
      journalClinical(
        readCompleted ? '2026-11-04T12:03:00.000001Z' : '2026-11-04T12:01:00.000001Z',
      ),
    ),
    db = { rpc, from } as unknown as ServiceClient,
    service = createConversationJournalV3Service(db, { auth: currentAuth, clinical: { capture } })
  return { who, epoch, raw, rpc, from, currentAuth, capture, service }
}
describe('actual persisted SQL page through the default historical domain services', () => {
  for (const row of actualJournal.cases)
    it(row.label, async () => {
      // Exact PG page/reconcile envelopes; Auth/current profile here are explicit
      // unit ports. This proves decoder/composition, not live HTTP or session QA.
      const original = journalAuth(),
        who = {
          ...original,
          userId: row.page.owner_id,
          identity: { ...original.identity, email: 'synthetic-journal-pg@example.invalid' },
          patient: { ...original.patient, id: row.page.owner_id },
        },
        state = journalClinical(row.page.observed_at)
      state.user_id = state.health_state.user_id = who.userId
      state.epoch = row.page.epoch
      const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
          if (name === 'read_conversation_journal_page_v3') return { data: row.page, error: null }
          if (name === 'reconcile_conversation_workout') {
            const actual = row.reconciles.find((r) => r.binding.command_id === args.p_command_id)
            if (!actual) throw new Error('No fabricated workout reconcile')
            return { data: actual.response, error: null }
          }
          if (
            [
              'read_mobile_registration_feedback_v3',
              'capture_mobile_registration_feedback_v3',
              'read_conversation_meal_feedback_source',
              'read_conversation_meal_feedback_v2',
            ].includes(name)
          )
            return { data: null, error: { code: 'SYNTHETIC_OPTIONAL_RECEIPT_ABSENT' } }
          throw new Error('GET cannot invoke any other domain/source/provider writer')
        }),
        service = createConversationJournalV3Service(
          { rpc, from: vi.fn() } as unknown as ServiceClient,
          {
            auth: {
              verifyAccessToken: async () => who.identity,
              loadPatient: async () => who.patient,
              isAdmin: async () => false,
            },
            clinical: { capture: async () => state },
          },
        ),
        value = await service.read(who, { epoch: row.page.epoch, limit: 25, cursor: null })
      expect(value.items).toHaveLength(row.page.items.length)
      expect(value.mode).toBe('historical')
      expect(
        rpc.mock.calls.filter(([name]) => name === 'read_conversation_journal_page_v3'),
      ).toHaveLength(1)
      for (const key of [
        'source_input',
        'input_hash',
        'command_protocol',
        'intake_origin',
        'claim_id',
        'processing_result',
        'question_key',
        'expected_revision',
        'undo_expires_at',
        'child_binding',
      ])
        expect(JSON.stringify(value)).not.toContain(`"${key}"`)
      if (row.label === 'meal_photo')
        expect(value.items[0]?.input).toEqual({ channel: 'media', caption: 'Comi arroz' })
      if (row.label === 'audio_note')
        expect(value.items[0]?.input).toEqual({ channel: 'media', caption: null })
    })
})
describe('real readonly journal v3 composition', () => {
  it.each([
    0, 1, 2,
  ])('reads actual SQL workout case %s through the real typed reader, including nullable energy', async (caseIndex) => {
    const index = caseIndex === 2 ? 0 : caseIndex,
      revoke = caseIndex === 2
    // The workout envelope is an unchanged actual PostgreSQL golden. The
    // journal page/current Auth are synthetic boundary fixtures, not PG/E2E.
    const row = structuredClone(actualWorkout.workout_reconcile_actual_golden[index])
    if (!row?.response.source || !row.response.preparation || !row.response.effect)
      throw new Error('Missing actual workout SQL piece')
    const captured = readCurrentClinicalState(
        row.response.source.context.clinical,
        row.bound_command.ownerId,
      ),
      originalAuth = journalAuth(),
      who = {
        ...originalAuth,
        userId: row.bound_command.ownerId,
        identity: { ...originalAuth.identity, email: 'synthetic-v3-workout@example.invalid' },
        patient: { ...originalAuth.patient, id: row.bound_command.ownerId },
      },
      sqlClock = (ms: number) => new Date(ms).toISOString().replace(/\.(\d{3})Z$/u, '.$1000Z'),
      base = new Date(row.response.effect.receipt.committed_at).getTime(),
      at = sqlClock(base + 2000),
      before = sqlClock(base + 1000),
      after = sqlClock(base + 3000),
      typedBinding = {
        owner_id: who.userId,
        command_id: row.bound_command.commandId,
        input_hash: row.bound_command.inputHash,
        epoch: row.epoch,
        admitted_at: row.response.source.context.admitted_at,
      },
      intakeId = 'c1450000-0000-4000-8000-000000000015',
      neutral = bindConversationIntake(who.userId, `cintake1:${intakeId}`, {
        intake_protocol: 'conversation.intake.v1',
        intake_id: intakeId,
        source: row.bound_command.command.source,
      }),
      binding = {
        owner_id: who.userId,
        intake_id: intakeId,
        input_hash: neutral.inputHash,
        epoch: row.epoch,
        admitted_at: typedBinding.admitted_at,
      },
      decision = {
        schema: 'conversation.intake-routing.v1',
        kind: 'workout.report',
        reason: 'performed_activity',
      },
      selection = {
        schema: 'conversation.intake-selection.v1',
        intake: binding,
        source_hash: 'a'.repeat(64),
        decision_hash: workoutDigest(decision),
        decision,
        selected_at: row.response.effect.receipt.committed_at,
        command: { ...typedBinding, kind: 'workout.report', input: row.bound_command.command },
      },
      page = {
        action: 'available',
        schema: 'conversation.journal-page-private.v3',
        owner_id: who.userId,
        epoch: row.epoch,
        observed_at: at,
        intakes: [
          {
            action: 'available',
            intake: binding,
            source_input: neutral.input,
            source_hash: selection.source_hash,
            claimed: true,
            selection,
          },
        ],
        workouts: [{ binding: typedBinding, source_input: row.bound_command.command }],
        meal_page: {
          action: 'available',
          schema: 'conversation.journal-page-private.v2',
          owner_id: who.userId,
          epoch: row.epoch,
          observed_at: at,
          threads: [],
          items: [],
          has_more: false,
          next_cursor: null,
        },
        items: [
          {
            kind: 'intake',
            event_id: `intake/${intakeId}`,
            at: binding.admitted_at,
            intake_id: intakeId,
          },
        ],
        has_more: false,
        next_cursor: null,
      }
    const canonical = prepareRegistrationFeedbackV3({
      registrationId: row.response.effect.receipt.registration_id,
      localDate: row.response.effect.receipt.local_date,
      locale: 'pt-BR',
      registration: parseFeedbackV3Registration({
        kind: 'workout',
        log_id: row.response.effect.receipt.workout_id,
        ...row.response.effect.receipt.activity,
      }),
      officialDay: null,
      policy: projectCurrentClinicalPublicPolicy(captured),
      educationAvailable: false,
    })
    let pageRead = false,
      revoked = false
    const rpc = vi.fn(async (name: string) => {
        if (name === 'read_conversation_journal_page_v3') {
          pageRead = true
          return { data: page, error: null }
        }
        if (name === 'reconcile_conversation_workout') return { data: row.response, error: null }
        if (name === 'read_mobile_registration_feedback_v3' && index === 0) {
          if (revoke) revoked = true
          return { data: { action: 'available', feedback: canonical }, error: null }
        }
        if (
          name === 'capture_mobile_registration_feedback_v3' ||
          name === 'read_mobile_registration_feedback_v3'
        )
          return { data: null, error: { code: 'SYNTHETIC_CANONICAL_NOT_AVAILABLE' } }
        throw new Error(
          'A GET cannot admit, capture a performed source, prepare, classify or write',
        )
      }),
      service = createConversationJournalV3Service(
        { rpc, from: vi.fn() } as unknown as ServiceClient,
        {
          auth: {
            verifyAccessToken: async () => who.identity,
            loadPatient: async () => who.patient,
            isAdmin: async () => revoked,
          },
          clinical: {
            capture: async () => ({
              ...captured,
              observed_at: pageRead ? after : before,
              safety:
                captured.safety === null
                  ? null
                  : { ...captured.safety, observed_at: pageRead ? after : before },
            }),
          },
        },
      )
    const request = { epoch: workoutUUID.parse(row.epoch), limit: 10, cursor: null }
    if (revoke) {
      await expect(service.read(who, request)).rejects.toBeDefined()
      revoked = false
      await expect(service.read(who, request)).rejects.toBeDefined()
      expect(
        rpc.mock.calls.filter(([name]) => name === 'read_mobile_registration_feedback_v3'),
      ).toHaveLength(1)
      expect(
        rpc.mock.calls.some(([name]) => name.startsWith('commit_') || name.startsWith('ensure_')),
      ).toBe(false)
      return
    }
    const value = await service.read(who, request)
    expect(value.items).toHaveLength(1)
    expect(value.items[0]).toMatchObject({
      thread_id: intakeId,
      lineage: {
        intake_id: intakeId,
        command_id: row.bound_command.commandId,
        origin_epoch: row.epoch,
      },
      outcome: {
        status: 'registered',
        record: { kind: 'workout', activity: row.response.effect.receipt.activity },
      },
    })
    if (index === 0) {
      const feedback = value.items[0]?.outcome.feedback
      expect(feedback?.schema).toBe('conversation.feedback-presentation.v2')
      if (feedback?.schema !== 'conversation.feedback-presentation.v2')
        throw new Error('Actual six-section wrapper required')
      expect(feedback.sections).toHaveLength(6)
    } else expect(value.items[0]?.outcome.feedback).toBeNull()
    expect(
      rpc.mock.calls.filter(([name]) => name === 'read_conversation_journal_page_v3'),
    ).toHaveLength(1)
    expect(
      rpc.mock.calls.filter(([name]) => name === 'reconcile_conversation_workout'),
    ).toHaveLength(1)
    for (const token of [
      'source_input',
      'command_protocol',
      'claim_id',
      'processing_result',
      'conversation.workout-command-result.v1',
    ])
      expect(JSON.stringify(value)).not.toContain(token)
  })
  it('projects actual legacy meal descendants once as observations, without retry or Undo authority', async () => {
    const h = setup(),
      meal = threadGoldenPage()
    Object.assign(h.raw, {
      meal_page: meal,
      items: meal.items.map((e) => ({
        kind: 'meal',
        event_id: e.event_id,
        at: e.at,
        intake_id: null,
      })),
    })
    // Optional historical enrichment is unavailable; saved facts still remain.
    h.rpc.mockImplementation(async (name) => {
      if (name === 'read_conversation_journal_page_v3') return { data: h.raw, error: null }
      return { data: null, error: { code: 'SYNTHETIC_OPTIONAL_FEEDBACK_UNAVAILABLE' } }
    })
    h.capture.mockImplementation(async () => journalClinical('2026-11-04T12:03:00.000001Z'))
    // Page observation remains genuinely bracketed in this boundary fixture.
    h.raw.observed_at = '2026-11-04T12:03:00.000001Z'
    meal.observed_at = h.raw.observed_at
    const value = await h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null })
    expect(value.items.map((e) => e.kind)).toEqual([
      'edit',
      'fulfillment',
      'reply_result',
      'reply',
      'report',
    ])
    expect(value.items[0]?.outcome.record).toMatchObject({
      kind: 'meal_edit',
      change: 'saved',
      revision: 1,
    })
    expect(value.items[1]?.outcome).toMatchObject({
      status: 'registered',
      record: { kind: 'meal' },
    })
    expect(value.items[3]?.input).toEqual({
      channel: 'structured',
      answer: { kind: 'quantity', food_index: 0, amount: 200, unit: 'mL' },
    })
    expect(value.items[4]?.outcome.status).toBe('not_recorded')
    for (const token of [
      'source_input',
      'command_protocol',
      'expected_revision',
      'question_key',
      'undo_expires_at',
      'prepared_hash',
      'effect_binding',
      'child_binding',
    ])
      expect(JSON.stringify(value)).not.toContain(token)
  })
  it('preserves root-edit lineage without inventing a self-parent', async () => {
    const h = setup(),
      root = threadSavedReport(journalCommand('registered')),
      edit = threadEdit()
    edit.thread_id = root.descriptor.thread_id
    edit.effect_binding = { ...root.descriptor.parent_binding }
    edit.event_id = `edit/${root.descriptor.thread_id}/${edit.receipt.operation_id}`
    edit.receipt.command_id = root.descriptor.thread_id
    Object.assign(h.raw, {
      meal_page: { ...h.raw.meal_page, threads: [root.descriptor], items: [edit, root.event] },
      items: [edit, root.event].map((e) => ({
        kind: 'meal',
        event_id: e.event_id,
        at: e.at,
        intake_id: null,
      })),
    })
    const value = await h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null })
    expect(value.items[0]?.lineage).toMatchObject({
      kind: 'meal.edit',
      command_id: root.descriptor.thread_id,
      parent_command_id: null,
      intake_id: null,
    })
    expect(value.items[0]?.outcome.record).toMatchObject({ kind: 'meal_edit', change: 'saved' })
  })
  it('uses the selected neutral meal original and keeps the typed report private', async () => {
    const h = setup(),
      t = threadDescriptor(),
      intakeId = 'c1450000-0000-4000-8000-000000000016',
      neutral = bindConversationIntake(h.who.userId, `cintake1:${intakeId}`, {
        intake_protocol: 'conversation.intake.v1',
        intake_id: intakeId,
        source: t.original_command.source,
        meal_type_hint: 'almoco',
      }),
      b = {
        owner_id: h.who.userId,
        intake_id: intakeId,
        input_hash: neutral.inputHash,
        epoch: h.epoch,
        admitted_at: '2026-11-04T11:59:59.000001Z',
      },
      decision = {
        schema: 'conversation.intake-routing.v1',
        kind: 'meal.report',
        reason: 'performed_meal',
      },
      selection = {
        schema: 'conversation.intake-selection.v1',
        intake: b,
        source_hash: 'a'.repeat(64),
        decision_hash: workoutDigest(decision),
        decision,
        selected_at: '2026-11-04T12:00:00.000002Z',
        command: {
          kind: 'meal.report',
          owner_id: h.who.userId,
          command_id: t.thread_id,
          input_hash: t.parent_binding.input_hash,
          epoch: h.epoch,
          admitted_at: t.parent_binding.admitted_at,
          input: t.original_command,
        },
      },
      meal = { ...h.raw.meal_page, threads: [t], items: [threadReport()] }
    Object.assign(h.raw, {
      intakes: [
        {
          action: 'available',
          intake: b,
          source_input: neutral.input,
          source_hash: selection.source_hash,
          claimed: true,
          selection,
        },
      ],
      meal_page: meal,
      items: [
        { kind: 'intake', event_id: `intake/${intakeId}`, at: b.admitted_at, intake_id: intakeId },
      ],
    })
    const value = await h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null })
    expect(value.items).toHaveLength(1)
    expect(value.items[0]).toMatchObject({
      kind: 'intake',
      thread_id: intakeId,
      input: { channel: 'text', text: 'Comi leite' },
      lineage: { intake_id: intakeId, command_id: t.thread_id },
      outcome: { status: 'not_recorded', reason: 'missing_quantity' },
    })
    expect(JSON.stringify(value)).not.toContain(`command/${t.thread_id}`)
  })
  it.each([
    'auth',
    'mapping',
    'admin',
    'epoch',
    'scope_throw',
  ] as const)('fails closed on actual current %s before the page RPC and never heals', async (kind) => {
    const h = setup()
    if (kind === 'auth')
      h.currentAuth.verifyAccessToken.mockResolvedValueOnce({ ...h.who.identity, id: h.who.userId })
    if (kind === 'mapping')
      h.currentAuth.loadPatient.mockResolvedValueOnce({ ...h.who.patient, id: h.who.authUserId })
    if (kind === 'admin') h.currentAuth.isAdmin.mockResolvedValueOnce(true)
    if (kind === 'epoch')
      h.capture.mockResolvedValueOnce({ ...journalClinical(), epoch: h.who.authUserId })
    if (kind === 'scope_throw')
      h.currentAuth.loadPatient.mockRejectedValueOnce(
        new Error('Original mapping temporarily unavailable'),
      )
    await expect(
      h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null }),
    ).rejects.toBeDefined()
    await expect(
      h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null }),
    ).rejects.toBeDefined()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it.each([
    false,
    true,
  ])('latches revocation around the physical SDK result, including throw=%s', async (throws) => {
    const h = setup(),
      original = h.rpc.getMockImplementation()
    h.rpc.mockImplementationOnce(async (name, args) => {
      const result = await original?.(name, args)
      h.currentAuth.isAdmin.mockResolvedValue(true)
      if (throws) throw new Error('SDK result lost after revocation')
      return result
    })
    await expect(
      h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null }),
    ).rejects.toBeDefined()
    h.currentAuth.isAdmin.mockResolvedValue(false)
    await expect(
      h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null }),
    ).rejects.toBeDefined()
    expect(h.rpc).toHaveBeenCalledOnce()
  })
  it('detaches the actual SDK page before post-await current-scope callbacks can mutate aliases', async () => {
    const h = setup(),
      original = h.capture.getMockImplementation()
    h.capture.mockImplementation(async () => {
      if (h.rpc.mock.calls.length) h.raw.owner_id = h.who.authUserId
      if (!original) throw new Error('Original capture required')
      return original()
    })
    const value = await h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null })
    expect(value.owner_id).toBe(h.who.userId)
    expect(h.raw.owner_id).toBe(h.who.authUserId)
  })
  it('reads the mixed SQL page once through genuine v2 projection and fresh original Auth', async () => {
    const h = setup(),
      value = await h.service.read(h.who, { epoch: h.epoch, limit: 10, cursor: null })
    expect(value).toMatchObject({
      schema: 'conversation.journal-page.v3',
      auth_user_id: h.who.authUserId,
      owner_id: h.who.userId,
      epoch: h.epoch,
      items: [],
      has_more: false,
      next_cursor: null,
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['read_conversation_journal_page_v3'])
    expect(h.currentAuth.verifyAccessToken).toHaveBeenCalled()
    expect(h.currentAuth.loadPatient).toHaveBeenCalled()
    expect(h.currentAuth.isAdmin).toHaveBeenCalled()
    expect(h.from).not.toHaveBeenCalled()
    expect(JSON.stringify(value)).not.toContain('source_input')
  })
})
