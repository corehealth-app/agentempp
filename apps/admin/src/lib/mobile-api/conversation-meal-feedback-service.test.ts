import {
  prepareRegistrationFeedbackV2,
  renderRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  auth,
  context,
  day,
  legacyFeedback,
  logId,
  other,
  owner,
  registrationId,
} from './__fixtures__/feedback-v2-source'
import { bindConversationCommand } from './conversation-command-contracts'
import { createSupabaseConversationMealFeedbackService } from './conversation-meal-feedback-service'
import type {
  ConversationMealFeedbackRead,
  ConversationMealFeedbackStore,
} from './conversation-meal-feedback-store'
import {
  type CurrentClinicalReaderSources,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import { loadFeedbackV2ClinicalContext } from './registration-feedback-v2-clinical'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

const commandId = '10000000-0000-4000-8000-000000000009'
const provider = `conversation.meal/${owner}/${commandId}`
function command() {
  return bindConversationCommand(owner, `cmsg1:${commandId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
    kind: 'meal.report',
    meal_type: 'cafe',
    source: { channel: 'text', text: 'leite integral206g' },
  })
}
function original() {
  const c = context()
  Object.assign(c.confirmed.proposal, {
    source_provider_message_id: provider,
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
  })
  for (const log of c.logs) log.raw_provider_message_id = provider
  return c
}
function receipt() {
  return {
    schema: 'conversation.meal-effect.v1' as const,
    owner_id: owner,
    command_id: commandId,
    input_hash: command().inputHash,
    registration_id: registrationId,
    provider_key: provider,
    meal_type: 'cafe' as const,
    local_date: '2026-11-03',
    timezone: 'UTC',
    consumed_at: '2026-11-03T11:00:00Z',
    log_ids: [logId],
    effect_version: `cmeal1:${'a'.repeat(64)}`,
  }
}
const identity = { userId: owner, registrationId, kind: 'meal' as const }
function input() {
  return { auth: structuredClone(auth), command: structuredClone(command()), receipt: receipt() }
}
function harness(raw = original()) {
  const observation = parseFeedbackV2Capture(raw, identity),
    events: string[] = []
  const clinical = {
    policy: projectCurrentClinicalPublicPolicy(observation.clinical),
    officialDay: day(),
  }
  const loadClinical = vi.fn<typeof loadFeedbackV2ClinicalContext>(async () => {
    events.push('clinical')
    return clinical
  })
  const store: ConversationMealFeedbackStore = {
    readReceipt: vi.fn(async (): Promise<ConversationMealFeedbackRead> => {
      events.push('read')
      return { action: 'absent' }
    }),
    readSource: vi.fn(async () => {
      events.push('source')
      return { action: 'available' as const, receipt: receipt(), originalObservation: observation }
    }),
    commit: vi.fn(async (value) => {
      events.push('commit')
      return {
        action: 'committed' as const,
        feedback: value.feedback as ReturnType<typeof prepareRegistrationFeedbackV2>,
      }
    }),
  }
  const rpc = vi.fn(async () => {
      throw new Error('unexpected realRPC')
    }),
    from = vi.fn(() => {
      throw new Error('domain/analytics/livehistory forbidden')
    })
  const db = { rpc, from } as unknown as ServiceClient
  const expected = prepareRegistrationFeedbackV2({
    registrationId,
    localDate: observation.facts.localDate,
    locale: 'pt-BR',
    registration: observation.facts.registration,
    policy: clinical.policy,
    officialDay: clinical.officialDay,
    preferencesKnown: false,
  })
  const service = createSupabaseConversationMealFeedbackService(db, { store, loadClinical })
  return {
    raw,
    observation,
    events,
    clinical,
    loadClinical,
    store,
    rpc,
    from,
    db,
    expected,
    service,
  }
}
describe('optional original command feedback service', () => {
  it('reads first then seals all six sections from original saved facts exactly once', async () => {
    const h = harness()
    expect(h.events).toEqual([])
    const result = await h.service.ensureOriginal(input())
    expect(result).toEqual(h.expected)
    expect(h.events).toEqual(['read', 'source', 'clinical', 'commit'])
    if (!result || result.schema !== 'registration.feedback.v2') throw new Error('fixture')
    expect(renderRegistrationFeedbackV2(result).map((s) => s.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    expect(result.registration).toMatchObject({
      items: [{ log_id: logId, kcal: 126.12 }],
      totals: { kcal: 126.1 },
    })
    expect(result.day).toMatchObject({
      targets: { calories_kcal: 1900, protein_g: 120 },
      remaining_food_kcal: 1774,
    })
    expect(result.block.status).toBe('available')
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.from).not.toHaveBeenCalled()
  })
  it.each([
    'v1',
    'v2',
  ])('preserves firstwinner%s without source/clinical/newseal', async (version) => {
    const h = harness(),
      saved = version === 'v1' ? parseRegistrationFeedback(legacyFeedback(), identity) : h.expected
    vi.mocked(h.store.readReceipt).mockResolvedValueOnce(
      version === 'v1'
        ? { action: 'legacy', feedback: parseRegistrationFeedback(legacyFeedback(), identity) }
        : { action: 'available', feedback: h.expected },
    )
    expect(await h.service.ensureOriginal(input())).toEqual(saved)
    expect(h.store.readSource).not.toHaveBeenCalled()
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
  })
  it('readOriginal is immutable receipt-only even when absent', async () => {
    const h = harness()
    expect(await h.service.readOriginal(input())).toBeNull()
    expect(h.events).toEqual(['read'])
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
    vi.mocked(h.store.readReceipt).mockResolvedValueOnce({
      action: 'available',
      feedback: h.expected,
    })
    const result = await h.service.readOriginal(input())
    expect(result).toEqual(h.expected)
    expect(Object.isFrozen(result)).toBe(true)
  })
  it('never recaptures NULL original context, leaving the saved factual result untouched', async () => {
    const h = harness(),
      request = input(),
      before = structuredClone(request.receipt)
    vi.mocked(h.store.readSource).mockResolvedValueOnce({
      action: 'unavailable',
      reason: 'original_context_unavailable',
      receipt: receipt(),
    })
    expect(await h.service.ensureOriginal(request)).toBeNull()
    expect(request.receipt).toEqual(before)
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it.each(['stale_epoch', 'event_conflict'] as const)('stops%s at firstread', async (action) => {
    const h = harness()
    vi.mocked(h.store.readReceipt).mockResolvedValueOnce({ action })
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.store.readSource).not.toHaveBeenCalled()
  })
  it('resolves lost commit through exactly one immutable read and never re-seals/reloads', async () => {
    const h = harness()
    vi.mocked(h.store.commit).mockRejectedValueOnce(new Error('private-health-sentinel'))
    vi.mocked(h.store.readReceipt)
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce({ action: 'available', feedback: h.expected })
    expect(await h.service.ensureOriginal(input())).toEqual(h.expected)
    expect(h.store.readReceipt).toHaveBeenCalledTimes(2)
    expect(h.store.readSource).toHaveBeenCalledTimes(1)
    expect(h.loadClinical).toHaveBeenCalledTimes(1)
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('returnsnull on failed reconciliation, preserving optional-failure isolation', async () => {
    const h = harness()
    vi.mocked(h.store.commit).mockRejectedValueOnce(new Error('secret'))
    vi.mocked(h.store.readReceipt)
      .mockResolvedValueOnce({ action: 'absent' })
      .mockRejectedValueOnce(new Error('private'))
    const log = vi.spyOn(console, 'error')
    try {
      expect(await h.service.ensureOriginal(input())).toBeNull()
      expect(log).not.toHaveBeenCalled()
    } finally {
      log.mockRestore()
    }
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('withholds day after currentC11 drift while sealing original policy/facts only', async () => {
    const h = harness()
    h.loadClinical.mockRejectedValueOnce(new Error('private C11 changed'))
    const result = await h.service.ensureOriginal(input())
    expect(result).toMatchObject({
      schema: 'registration.feedback.v2',
      guidance: 'available',
      day: null,
      block: { status: 'unavailable' },
      registration: { items: [{ log_id: logId, kcal: 126.12 }] },
    })
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('does not trust a substituted policy or incompatible numeric day from injected callbacks', async () => {
    const h = harness()
    h.clinical.officialDay.consumed.protein_g = 999
    expect(await h.service.ensureOriginal(input())).toMatchObject({
      day: null,
      block: { status: 'unavailable' },
    })
    const other = harness()
    other.loadClinical.mockResolvedValueOnce({
      ...other.clinical,
      policy: { ...other.clinical.policy, pause_weight_loss_guidance: true },
    })
    expect(await other.service.ensureOriginal(input())).toMatchObject({
      guidance: 'available',
      day: null,
    })
  })
  it.each([
    'pt-BR',
    'en-US',
    'invalid',
    'en-private',
  ])('uses original locale%s rather than mutable clientsettings', async (locale) => {
    const raw = original()
    raw.clinical.body.locale = locale
    const h = harness(raw),
      request = input()
    request.auth.patient.locale = locale === 'en-US' ? 'pt-BR' : 'en-US'
    expect(await h.service.ensureOriginal(request)).toMatchObject({
      locale: locale === 'en-US' ? 'en' : 'pt-BR',
    })
  })
  it('retains original clinical pause and protects targets/block', async () => {
    const raw = original()
    raw.clinical.body.body_fat_percent = 10
    raw.clinical.safety.loss_guard = true
    const h = harness(raw),
      result = await h.service.ensureOriginal(input())
    expect(result).toMatchObject({
      guidance: 'paused',
      day: { targets: { calories_kcal: null, protein_g: null }, current_protocol: null },
      block: { status: 'protected' },
      education: { provenance: { template_id: 'clinical_pause' } },
    })
  })
  it('does not promote calculated profile targets when original snapshot goals are missing', async () => {
    const raw = original()
    Object.assign(raw.snapshot, { calories_target: null, protein_target: null })
    const h = harness(raw)
    Object.assign(h.clinical.officialDay.targets, {
      calories_kcal: 9999,
      protein_g: 999,
      calories_source: 'profile_calculation',
      protein_source: 'profile_calculation',
    })
    const result = await h.service.ensureOriginal(input())
    expect(result).toMatchObject({
      day: {
        targets: { calories_kcal: null, protein_g: null },
        calorie_percentage: null,
        protein_percentage: null,
        remaining_food_kcal: null,
      },
    })
  })
  it.each([
    'auth',
    'owner',
    'log',
    'date',
    'kind',
  ] as const)('refuses bindinggap%s beforeoptionalreads', async (change) => {
    const h = harness(),
      request = input()
    if (change === 'auth') request.auth.userId = other
    if (change === 'owner') request.receipt.owner_id = other
    if (change === 'log') request.receipt.log_ids = [logId, logId]
    if (change === 'date') request.receipt.local_date = '2026-11-04'
    if (change === 'kind') Object.assign(request.command.command, { kind: 'workout.report' })
    expect(await h.service.ensureOriginal(request)).toBeNull()
    expect(h.store.readReceipt).not.toHaveBeenCalled()
  })
  it('refuses swapped source mandatoryreceipt and changed original facts', async () => {
    const h = harness()
    vi.mocked(h.store.readSource).mockResolvedValueOnce({
      action: 'available',
      receipt: { ...receipt(), log_ids: [other] },
      originalObservation: h.observation,
    } as Awaited<ReturnType<ConversationMealFeedbackStore['readSource']>>)
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
  })
  it('detaches auth/binding and captures callbacks before firstawait', async () => {
    const h = harness(),
      request = input()
    let release!: (value: ConversationMealFeedbackRead) => void
    vi.mocked(h.store.readReceipt).mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = resolve
        }),
    )
    const pending = h.service.ensureOriginal(request)
    request.auth.patient.locale = 'en-US'
    request.auth.userId = other
    request.receipt.log_ids = [other]
    const replacement = vi.fn()
    Object.assign(h.store, { readSource: replacement, commit: replacement })
    release({ action: 'absent' })
    expect(await pending).toEqual(h.expected)
    expect(replacement).not.toHaveBeenCalled()
  })
  it('uses the real default store and default clinical loader without genericrecapture or domain writes', async () => {
    const raw = original()
    raw.clinical.date = raw.clinical.safety.date = '2026-11-04'
    raw.clinical.observed_at = raw.clinical.safety.observed_at = '2026-11-04T12:00:00.000001Z'
    const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
        if (name === 'read_conversation_meal_feedback_v2')
          return { data: { action: 'absent' }, error: null }
        if (name === 'read_conversation_meal_feedback_source')
          return { data: { action: 'available', receipt: receipt(), context: raw }, error: null }
        if (name === 'commit_conversation_meal_feedback_v2')
          return { data: { action: 'committed', feedback: args.p_feedback }, error: null }
        throw new Error(`unexpected RPC${name}`)
      }),
      from = vi.fn(() => {
        throw new Error('effects forbidden')
      }),
      db = { rpc, from } as unknown as ServiceClient
    expect(() => parseFeedbackV2Capture(raw, identity)).not.toThrow()
    const service = createSupabaseConversationMealFeedbackService(db)
    expect(rpc).not.toHaveBeenCalled()
    const result = await service.ensureOriginal(input())
    expect(rpc.mock.calls.map((c) => c[0])).toEqual([
      'read_conversation_meal_feedback_v2',
      'read_conversation_meal_feedback_source',
      'commit_conversation_meal_feedback_v2',
    ])
    expect(result).toMatchObject({ day: null })
    expect(from).not.toHaveBeenCalled()
  })
  it('isolates constructor errors and malformed saved action/version without any source fallback', async () => {
    const unavailable = createSupabaseConversationMealFeedbackService({} as ServiceClient)
    expect(await unavailable.ensureOriginal(input())).toBeNull()
    expect(await unavailable.readOriginal(input())).toBeNull()
    const h = harness()
    vi.mocked(h.store.readReceipt).mockResolvedValueOnce({
      action: 'available',
      feedback: parseRegistrationFeedback(legacyFeedback(), identity),
    } as unknown as ConversationMealFeedbackRead)
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.store.readSource).not.toHaveBeenCalled()
  })
  it('composes the actual qualified C11 readbridge for official day/block with no unrelated readers', async () => {
    const h = harness(),
      capture = vi.fn(async () => original().clinical),
      unused = vi.fn(async () => {
        throw new Error('unrelated')
      })
    const readers: CurrentClinicalReaderSources = {
      today: vi.fn(async () => day()),
      profile: unused,
      plan: unused,
      trends: unused,
      progress: unused,
    }
    const service = createSupabaseConversationMealFeedbackService(h.db, {
      store: h.store,
      loadClinical: (db, who, observation) =>
        loadFeedbackV2ClinicalContext(db, who, observation, { source: { capture }, readers }),
    })
    expect(await service.ensureOriginal(input())).toEqual(h.expected)
    expect(capture).toHaveBeenCalledTimes(2)
    expect(readers.today).toHaveBeenCalledTimes(1)
    expect(unused).not.toHaveBeenCalled()
  })
})
