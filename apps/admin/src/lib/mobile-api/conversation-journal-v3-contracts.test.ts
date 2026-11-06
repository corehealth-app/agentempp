import { describe, expect, it } from 'vitest'
import { threadDescriptor, threadPage, threadReport } from './__fixtures__/conversation-thread-page'
import { bindConversationIntake } from './conversation-intake-contracts'
import {
  decodeConversationJournalV3Cursor,
  encodeConversationJournalV3Cursor,
  parseConversationJournalV3Page,
} from './conversation-journal-v3-contracts'
import { bindConversationWorkoutCommand, workoutDigest } from './conversation-workout-contracts'
import actual from './testing/conversation-journal-v3-pg-golden.json'

// Synthetic boundary inputs only. Actual PostgreSQL qualification is separate.
const owner = 'c1450000-0000-4000-8000-000000000001',
  epoch = 'c1450000-0000-4000-8000-000000000002',
  intakeId = 'c1450000-0000-4000-8000-000000000003',
  admitted = '2026-11-05T12:00:00.000001Z',
  observed = '2026-11-05T12:00:01.000001Z',
  input = {
    intake_protocol: 'conversation.intake.v1',
    intake_id: intakeId,
    source: { channel: 'text', text: 'Fiz 30 minutos de caminhada.' },
  },
  bound = bindConversationIntake(owner, `cintake1:${intakeId}`, input),
  binding = {
    owner_id: owner,
    intake_id: intakeId,
    input_hash: bound.inputHash,
    epoch,
    admitted_at: admitted,
  },
  query = { ownerId: owner, epoch, limit: 10, cursor: null }

function page() {
  return {
    action: 'available',
    schema: 'conversation.journal-page-private.v3',
    owner_id: owner,
    epoch,
    observed_at: observed,
    intakes: [
      {
        action: 'available',
        intake: binding,
        source_input: input,
        source_hash: null,
        claimed: false,
        selection: null,
      },
    ],
    workouts: [],
    meal_page: {
      action: 'available',
      schema: 'conversation.journal-page-private.v2',
      owner_id: owner,
      epoch,
      observed_at: observed,
      threads: [],
      items: [],
      has_more: false,
      next_cursor: null,
    },
    items: [{ kind: 'intake', event_id: `intake/${intakeId}`, at: admitted, intake_id: intakeId }],
    has_more: false,
    next_cursor: null,
  }
}

function neutralMealPage() {
  const thread = threadDescriptor(),
    body = {
      intake_protocol: 'conversation.intake.v1',
      intake_id: intakeId,
      meal_type_hint: 'almoco',
      source: { channel: 'text', text: 'Comi leite' },
    },
    original = bindConversationIntake(thread.parent_binding.owner_id, `cintake1:${intakeId}`, body),
    b = {
      ...binding,
      owner_id: original.ownerId,
      input_hash: original.inputHash,
      epoch: thread.parent_binding.epoch,
      admitted_at: '2026-11-04T11:59:59.000001Z',
    },
    decision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'meal.report',
      reason: 'performed_meal',
    },
    raw = page(),
    fragment = { ...threadPage(), items: [threadReport()] }
  return {
    ...raw,
    owner_id: original.ownerId,
    epoch: b.epoch,
    observed_at: fragment.observed_at,
    intakes: [
      {
        action: 'available',
        intake: b,
        source_input: body,
        source_hash: 'a'.repeat(64),
        claimed: true,
        selection: {
          schema: 'conversation.intake-selection.v1',
          intake: b,
          source_hash: 'a'.repeat(64),
          decision_hash: workoutDigest(decision),
          decision,
          selected_at: '2026-11-04T12:00:00.000002Z',
          command: {
            kind: 'meal.report',
            owner_id: original.ownerId,
            command_id: thread.thread_id,
            input_hash: thread.parent_binding.input_hash,
            epoch: b.epoch,
            admitted_at: thread.parent_binding.admitted_at,
            input: thread.original_command,
          },
        },
      },
    ],
    meal_page: fragment,
    items: [
      { kind: 'intake', event_id: `intake/${intakeId}`, at: b.admitted_at, intake_id: intakeId },
    ],
  }
}

function neutralWorkoutPage() {
  const raw = page(),
    id = 'c1450000-0000-4000-8000-000000000004',
    body = {
      command_protocol: 'conversation.command.v1',
      command_id: id,
      kind: 'workout.report',
      source: input.source,
    },
    command = bindConversationWorkoutCommand(owner, `cmsg1:${id}`, body),
    b = {
      owner_id: owner,
      command_id: id,
      input_hash: command.inputHash,
      epoch,
      admitted_at: '2026-11-05T12:00:00.000002Z',
    },
    decision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'workout.report',
      reason: 'performed_activity',
    }
  return {
    ...raw,
    intakes: [
      {
        ...raw.intakes[0],
        source_hash: 'a'.repeat(64),
        claimed: true,
        selection: {
          schema: 'conversation.intake-selection.v1',
          intake: binding,
          source_hash: 'a'.repeat(64),
          decision_hash: workoutDigest(decision),
          decision,
          selected_at: '2026-11-05T12:00:00.000003Z',
          command: { ...b, kind: 'workout.report', input: body },
        },
      },
    ],
    workouts: [{ binding: b, source_input: body }],
  }
}

describe('actual rollback SQL mixed timeline codec', () => {
  for (const row of actual.cases)
    it(row.label, () => {
      const result = parseConversationJournalV3Page(row.page, {
        ownerId: row.page.owner_id,
        epoch: row.page.epoch,
        limit: 25,
        cursor: null,
      })
      expect(result.action).toBe('available')
      if (result.action !== 'available') throw new Error('Actual closed page required')
      expect(result.items).toHaveLength(row.page.items.length)
      expect(result.intakes).toHaveLength(row.page.intakes.length)
      expect(result.workouts).toHaveLength(row.page.workouts.length)
    })
})
describe('closed private journal v3 page', () => {
  it.each([
    'absent',
    'stale_epoch',
    'cursor_conflict',
    'event_conflict',
  ] as const)('keeps the exact action-only refusal %s', (action) => {
    expect(parseConversationJournalV3Page({ action }, query)).toEqual({ action })
    expect(() => parseConversationJournalV3Page({ action, source_input: input }, query)).toThrow()
  })
  it.each([
    ['owner', (p: ReturnType<typeof page>) => ({ ...p, owner_id: epoch })],
    ['current epoch', (p: ReturnType<typeof page>) => ({ ...p, epoch: owner })],
    [
      'original hash',
      (p: ReturnType<typeof page>) => ({
        ...p,
        intakes: [{ ...p.intakes[0], intake: { ...binding, input_hash: '0'.repeat(64) } }],
      }),
    ],
    [
      'original owner',
      (p: ReturnType<typeof page>) => ({
        ...p,
        intakes: [{ ...p.intakes[0], intake: { ...binding, owner_id: epoch } }],
      }),
    ],
    [
      'original epoch',
      (p: ReturnType<typeof page>) => ({
        ...p,
        intakes: [{ ...p.intakes[0], intake: { ...binding, epoch: owner } }],
      }),
    ],
    [
      'claimed without source',
      (p: ReturnType<typeof page>) => ({ ...p, intakes: [{ ...p.intakes[0], claimed: true }] }),
    ],
    [
      'unexpected original metadata',
      (p: ReturnType<typeof page>) => ({ ...p, intakes: [{ ...p.intakes[0], claim_id: owner }] }),
    ],
    [
      'duplicate original',
      (p: ReturnType<typeof page>) => ({ ...p, intakes: [...p.intakes, ...p.intakes] }),
    ],
    ['missing original', (p: ReturnType<typeof page>) => ({ ...p, intakes: [] })],
    [
      'duplicate event',
      (p: ReturnType<typeof page>) => ({ ...p, items: [...p.items, ...p.items] }),
    ],
    [
      'event identity',
      (p: ReturnType<typeof page>) => ({
        ...p,
        items: [{ ...p.items[0], event_id: `intake/${owner}` }],
      }),
    ],
    [
      'event admission clock',
      (p: ReturnType<typeof page>) => ({
        ...p,
        items: [{ ...p.items[0], at: '2026-11-05T12:00:00.000002Z' }],
      }),
    ],
    [
      'future event',
      (p: ReturnType<typeof page>) => ({ ...p, observed_at: '2026-11-04T12:00:00.000000Z' }),
    ],
    [
      'meal owner',
      (p: ReturnType<typeof page>) => ({ ...p, meal_page: { ...p.meal_page, owner_id: epoch } }),
    ],
    [
      'meal observation clock',
      (p: ReturnType<typeof page>) => ({
        ...p,
        meal_page: { ...p.meal_page, observed_at: '2026-11-05T12:00:01.000002Z' },
      }),
    ],
    [
      'false continuation cursor',
      (p: ReturnType<typeof page>) => ({
        ...p,
        has_more: true,
        next_cursor: { at: admitted, id: `intake/${intakeId}` },
      }),
    ],
    ['unexpected retry body', (p: ReturnType<typeof page>) => ({ ...p, command: input })],
  ] as const)('refuses the closed page violation: %s', (_label, change) => {
    expect(() => parseConversationJournalV3Page(change(page()), query)).toThrow()
  })
  it('reuses the complete genuine meal descriptor for a selected neutral root without a second report', () => {
    const raw = neutralMealPage(),
      value = parseConversationJournalV3Page(raw, {
        ...query,
        ownerId: raw.owner_id,
        epoch: raw.epoch,
      })
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Missing selected meal page')
    expect(value.items).toEqual(raw.items)
    expect(value.mealPage.items).toHaveLength(1)
    expect(value.intakes[0]?.selection?.command?.kind).toBe('meal.report')
  })
  it('retains a genuine workout child as a linked effect rather than another original user post', () => {
    const raw = neutralWorkoutPage(),
      value = parseConversationJournalV3Page(raw, query)
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Missing selected workout page')
    expect(value.items).toHaveLength(1)
    expect(value.workouts[0]?.bound.command).toEqual(raw.workouts[0]?.source_input)
    const child = raw.workouts[0]
    if (!child) throw new Error('Missing actual synthetic child')
    expect(() =>
      parseConversationJournalV3Page(
        {
          ...raw,
          items: [
            {
              kind: 'workout',
              event_id: `workout/${child.binding.command_id}`,
              command_id: child.binding.command_id,
              at: child.binding.admitted_at,
            },
            ...raw.items,
          ],
        },
        query,
      ),
    ).toThrow()
  })
  it('retains two equal legitimate workout reports with their distinct original identities', () => {
    const selected = neutralWorkoutPage(),
      first = selected.workouts[0]
    if (!first) throw new Error('Missing synthetic workout')
    const id = 'c1450000-0000-4000-8000-000000000005',
      body = { ...first.source_input, command_id: id },
      second = {
        source_input: body,
        binding: { ...first.binding, command_id: id, input_hash: workoutDigest(body) },
      },
      raw = {
        ...page(),
        intakes: [],
        workouts: [first, second],
        items: [second, first].map((w) => ({
          kind: 'workout',
          event_id: `workout/${w.binding.command_id}`,
          command_id: w.binding.command_id,
          at: w.binding.admitted_at,
        })),
      },
      value = parseConversationJournalV3Page(raw, query)
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Missing original workouts')
    expect(value.items).toHaveLength(2)
    expect(value.workouts.map((w) => w.bound.command.source)).toEqual([
      first.source_input.source,
      first.source_input.source,
    ])
  })
  it('binds an actual original neutral input without fabricating a typed command', () => {
    const value = parseConversationJournalV3Page(page(), query)
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Missing original page')
    expect(value.intakes[0]?.bound).toEqual(bound)
    expect(value.intakes[0]?.binding).toEqual(binding)
    expect(value.intakes[0]?.selection).toBeNull()
    expect(value.items).toEqual(page().items)
    expect(Object.isFrozen(value)).toBe(true)
    expect(Object.isFrozen(value.intakes[0]?.bound.input)).toBe(true)
  })

  it('gives v3 its own canonical cursor and preserves the SQL microsecond literal', () => {
    const anchor = { at: admitted, id: `intake/${intakeId}` },
      encoded = encodeConversationJournalV3Cursor(owner, epoch, anchor)
    expect(JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'))).toEqual({
      v: 3,
      owner_id: owner,
      epoch,
      ...anchor,
    })
    expect(decodeConversationJournalV3Cursor(encoded, owner, epoch)).toEqual(anchor)
    expect(() => decodeConversationJournalV3Cursor(encoded, epoch, epoch)).toThrow(
      expect.objectContaining({ status: 409 }),
    )
    expect(() => decodeConversationJournalV3Cursor(encoded, owner, owner)).toThrow(
      expect.objectContaining({ status: 409 }),
    )
    for (const v of [1, 2]) {
      const old = Buffer.from(JSON.stringify({ v, owner_id: owner, epoch, ...anchor })).toString(
        'base64url',
      )
      expect(() => decodeConversationJournalV3Cursor(old, owner, epoch)).toThrow()
    }
  })
})
