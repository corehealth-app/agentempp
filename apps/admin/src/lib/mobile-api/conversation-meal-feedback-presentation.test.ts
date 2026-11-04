import {
  prepareRegistrationFeedbackV2,
  renderRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  auth,
  clinical,
  context,
  day,
  legacyFeedback,
  logId,
  other,
  owner,
  registrationId,
} from './__fixtures__/feedback-v2-source'
import type { ConversationJournalBinding } from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import { createSupabaseConversationMealFeedbackPresentation } from './conversation-meal-feedback-presentation'
import type {
  ConversationMealFeedbackService,
  OriginalConversationMealFeedback,
} from './conversation-meal-feedback-service'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import type { CurrentClinicalStateSource } from './current-clinical-state'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
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
function serverBinding(): ConversationJournalBinding {
  return {
    owner_id: owner,
    command_id: commandId,
    input_hash: command().inputHash,
    command_protocol: 'conversation.command.v1',
    kind: 'meal.report',
    epoch: clinical().epoch,
    admitted_at: '2026-11-03T10:00:00Z',
  }
}
function input() {
  return {
    auth: structuredClone(auth),
    command: structuredClone(command()),
    receipt: receipt(),
    serverBinding: serverBinding(),
  }
}
function saved() {
  const c = context()
  Object.assign(c.confirmed.proposal, {
    source_provider_message_id: provider,
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
  })
  for (const log of c.logs) log.raw_provider_message_id = provider
  const o = parseFeedbackV2Capture(c, { userId: owner, registrationId, kind: 'meal' })
  return prepareRegistrationFeedbackV2({
    registrationId,
    localDate: o.facts.localDate,
    locale: 'pt-BR',
    registration: o.facts.registration,
    policy: projectCurrentClinicalPublicPolicy(o.clinical),
    officialDay: day(),
  })
}
function current() {
  const s = clinical()
  s.date = s.safety.date = '2026-11-04'
  s.observed_at = s.safety.observed_at = '2026-11-04T12:00:00.000001Z'
  return s
}
function held(code: 'professional_diet' | 'reduced_intake' | 'pregnant_or_breastfeeding') {
  const s = current()
  Object.assign(s.health_state, {
    safety_revision: '1',
    hold_active: true,
    declared_no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'professional_diet',
    last_declared_at: s.observed_at,
    items: [{ code, declared_at: s.observed_at }],
  })
  Object.assign(s.safety, {
    hold_active: true,
    no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'professional_diet' || code === 'pregnant_or_breastfeeding',
  })
  return s
}
function harness(raw: unknown = current(), original: OriginalConversationMealFeedback = saved()) {
  const events: string[] = [],
    capture = vi.fn<CurrentClinicalStateSource['capture']>(async () => {
      events.push('clinical')
      return raw
    })
  const service: ConversationMealFeedbackService = {
    readOriginal: vi.fn(async () => {
      events.push('original')
      return original
    }),
    ensureOriginal: vi.fn(async () => {
      throw new Error('seal forbidden')
    }),
  }
  const rpc = vi.fn(async () => {
      throw new Error('unexpected RPC')
    }),
    from = vi.fn(() => {
      throw new Error('effect forbidden')
    }),
    db = { rpc, from } as unknown as ServiceClient
  const source = { capture },
    presentation = createSupabaseConversationMealFeedbackPresentation(db, {
      clinicalSource: source,
      original: service,
    })
  return { raw, original, events, capture, service, rpc, from, db, source, presentation }
}
function sections(
  value: Awaited<
    ReturnType<
      ReturnType<typeof createSupabaseConversationMealFeedbackPresentation>['readHistorical']
    >
  >,
) {
  if (!value || value.format !== 'sections') throw new Error('section fixture')
  return value
}
const text = (items: readonly { key: string; text: string }[], key: string) =>
  items.find((item) => item.key === key)?.text ?? ''

describe('current clinical guard for historical command feedback', () => {
  it('renders six historical sections between two actualowned currentobservations without mutating original', async () => {
    const h = harness(),
      before = structuredClone(h.original)
    expect(h.events).toEqual([])
    const value = sections(await h.presentation.readHistorical(input()))
    expect(h.events).toEqual(['clinical', 'original', 'clinical'])
    expect(value).toMatchObject({
      schema: 'conversation.feedback-presentation.v1',
      mode: 'historical',
      assistant: 'Flow AI',
      status: 'available',
      original: {
        schema: 'registration.feedback.v2',
        registration_id: registrationId,
        kind: 'meal',
        local_date: '2026-11-03',
      },
      provenance: {
        epoch: serverBinding().epoch,
        command_id: commandId,
        observed_at: current().observed_at,
      },
    })
    expect(value.sections.map((s) => s.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    expect(value.recorded).toEqual(saved().registration)
    expect(value.sections.slice(0, 3)).toEqual(renderRegistrationFeedbackV2(saved()).slice(0, 3))
    expect(text(value.sections, 'day')).toContain('2026-11-03')
    expect(text(value.sections, 'day')).not.toContain('2026-11-04')
    expect(text(value.sections, 'day')).toContain('1.900')
    expect(text(value.sections, 'block')).toContain('7.700')
    expect(value.current_policy.observed_at).toBe(current().observed_at)
    expect(h.original).toEqual(before)
    expect(h.service.ensureOriginal).not.toHaveBeenCalled()
    expect(h.from).not.toHaveBeenCalled()
    expect(h.capture).toHaveBeenCalledWith({
      userId: owner,
      mode: 'profile',
      expectedEpoch: serverBinding().epoch,
    })
  })
  it('keeps old day numbers after currentbodychanges instead of recalculating today', async () => {
    const raw = current()
    raw.body.weight_kg = 85
    const h = harness(raw),
      value = sections(await h.presentation.readHistorical(input()))
    expect(text(value.sections, 'day')).toContain('1.900')
    expect(text(value.sections, 'day')).toContain('1.774')
    expect(value.recorded).toEqual(saved().registration)
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.from).not.toHaveBeenCalled()
  })
  it('masks old targets/percentages/budget/objective/block/education under n10 pause while keeping savedmeal facts', async () => {
    const raw = current()
    raw.body.body_fat_percent = 10
    raw.safety.loss_guard = true
    const h = harness(raw),
      value = sections(await h.presentation.readHistorical(input()))
    expect(value.current_policy.pause_weight_loss_guidance).toBe(true)
    expect(value.recorded).toEqual(saved().registration)
    expect(text(value.sections, 'day')).not.toContain('1.900')
    expect(text(value.sections, 'day')).not.toContain('1.774')
    expect(text(value.sections, 'day')).not.toContain('%')
    expect(text(value.sections, 'block')).not.toContain('7.700')
    expect(text(value.sections, 'block')).not.toContain('500')
    expect(text(value.sections, 'education')).toContain('pausadas')
    expect(text(value.sections, 'education')).not.toBe(
      text(renderRegistrationFeedbackV2(saved()), 'education'),
    )
    expect(h.original).toEqual(saved())
  })
  it.each([
    'professional_diet',
    'reduced_intake',
    'pregnant_or_breastfeeding',
  ] as const)('uses actual publicpolicy combination for%s without rawhealth codes', async (code) => {
    const h = harness(held(code)),
      value = sections(await h.presentation.readHistorical(input()))
    expect(value.current_policy.pause_weight_loss_guidance).toBe(true)
    expect(value.current_policy.hide.protein).toBe(code !== 'reduced_intake')
    if (code === 'professional_diet') expect(value.current_policy.hide.calories).toBe(false)
    expect(text(value.sections, 'day')).not.toContain('120 g')
    expect(text(value.sections, 'block')).not.toContain('7.700')
    const json = JSON.stringify(value)
    expect(json).not.toContain(code)
    expect(json).not.toContain('body_fat_percent')
    expect(json).not.toContain('health_state')
  })
  it('uses the real absentphase allfield hide policy even without pause', async () => {
    const raw = current()
    Object.assign(raw.phase_origin, {
      kind: 'confirmed_no_plan',
      signupGeneration: raw.signup_generation,
      signupEpoch: raw.epoch,
      completedAt: raw.generation_token.onboarding_completed_at,
    })
    delete (raw.phase_origin as Record<string, unknown>).phase
    const h = harness(raw),
      value = sections(await h.presentation.readHistorical(input()))
    expect(Object.values(value.current_policy.hide).every(Boolean)).toBe(true)
    expect(value.current_policy.pause_weight_loss_guidance).toBe(false)
    expect(text(value.sections, 'day')).not.toContain('1.900')
    expect(text(value.sections, 'day')).not.toContain('1.774')
    expect(text(value.sections, 'block')).not.toContain('7.700')
    expect(text(value.sections, 'education')).toContain('indisponível')
  })
  it('withholds oldday/block/education on incomplete assessment even when hide/pause flags are false', async () => {
    const raw = {
        ...current(),
        body: { ...current().body, weight_kg: null },
        assessment: 'incomplete',
        missing: ['weight_kg'],
        safety: null,
      },
      h = harness(raw)
    const value = sections(await h.presentation.readHistorical(input()))
    expect(value.current_policy).toMatchObject({
      assessment: 'incomplete',
      pause_weight_loss_guidance: false,
    })
    expect(text(value.sections, 'day')).not.toContain('1.900')
    expect(text(value.sections, 'block')).not.toContain('7.700')
    expect(text(value.sections, 'education')).toContain('indisponível')
    expect(value.recorded).toEqual(saved().registration)
  })
  it('preserves unrestricted v1 bodycompatibility only in historical wrapper', async () => {
    const body = parseRegistrationFeedback(legacyFeedback(), {
        userId: owner,
        registrationId,
        kind: 'meal',
      }),
      h = harness(current(), body),
      value = await h.presentation.readHistorical(input())
    expect(value).toMatchObject({
      format: 'legacy',
      status: 'available',
      assistant: 'Flow AI',
      legacy_body: body,
      original: { schema: 'registration.feedback.v1' },
    })
    expect(h.service.ensureOriginal).not.toHaveBeenCalled()
    expect(Object.isFrozen(value)).toBe(true)
  })
  it('does not regexredact or leak opaque v1 when currentpolicy restricts it', async () => {
    const body = parseRegistrationFeedback(legacyFeedback(), {
        userId: owner,
        registrationId,
        kind: 'meal',
      }),
      raw = current()
    raw.body.body_fat_percent = 10
    raw.safety.loss_guard = true
    const h = harness(raw, body),
      value = await h.presentation.readHistorical(input())
    expect(value).toMatchObject({
      format: 'placeholder',
      status: 'unavailable',
      mode: 'historical',
    })
    expect(value).not.toHaveProperty('legacy_body')
    expect(JSON.stringify(value)).not.toContain('Synthetic total')
    expect(h.original).toEqual(body)
  })
  it.each([
    'auth',
    'receiptowner',
    'wronglog',
    'serverowner',
    'inputhash',
    'serverepoch',
  ] as const)('withholds%s without another account/policy fallback', async (change) => {
    const h = harness(),
      request = input()
    if (change === 'auth') request.auth.userId = other
    if (change === 'receiptowner') request.receipt.owner_id = other
    if (change === 'wronglog') request.receipt.log_ids = [other]
    if (change === 'serverowner') request.serverBinding.owner_id = other
    if (change === 'inputhash') request.serverBinding.input_hash = 'b'.repeat(64)
    if (change === 'serverepoch') request.serverBinding.epoch = other
    expect(await h.presentation.readHistorical(request)).toBeNull()
    expect(h.service.ensureOriginal).not.toHaveBeenCalled()
  })
  it.each([
    'owner',
    'epoch',
    'body',
    'health',
    'generation',
    'olderclock',
  ] as const)('withholds pre/post drift%s after readonlyoriginal read', async (change) => {
    const h = harness(),
      post = current()
    post.observed_at = post.safety.observed_at = '2026-11-04T12:00:01.000001Z'
    if (change === 'owner') post.user_id = other
    if (change === 'epoch') post.epoch = other
    if (change === 'body') post.body.weight_kg = 85
    if (change === 'health') Object.assign(post, held('reduced_intake'))
    if (change === 'generation') post.signup_generation = other
    if (change === 'olderclock')
      post.observed_at = post.safety.observed_at = '2026-11-04T12:00:00.000000Z'
    h.capture.mockResolvedValueOnce(current()).mockResolvedValueOnce(post)
    expect(await h.presentation.readHistorical(input())).toBeNull()
    expect(h.service.readOriginal).toHaveBeenCalledTimes(1)
    expect(h.service.ensureOriginal).not.toHaveBeenCalled()
  })
  it('withholds unknown policy/outage and missing original rather than exposing v1 or making a seal', async () => {
    const body = parseRegistrationFeedback(legacyFeedback(), {
        userId: owner,
        registrationId,
        kind: 'meal',
      }),
      h = harness(current(), body)
    h.capture.mockRejectedValueOnce(new Error('private-health-sentinel'))
    const log = vi.spyOn(console, 'error')
    try {
      expect(await h.presentation.readHistorical(input())).toBeNull()
      expect(log).not.toHaveBeenCalled()
    } finally {
      log.mockRestore()
    }
    expect(h.service.readOriginal).not.toHaveBeenCalled()
    const missing = harness()
    vi.mocked(missing.service.readOriginal).mockResolvedValueOnce(null)
    expect(await missing.presentation.readHistorical(input())).toBeNull()
    expect(missing.service.ensureOriginal).not.toHaveBeenCalled()
  })
  it('pins auth/serverbinding and producer callbacks before firstawait', async () => {
    const h = harness(),
      request = input()
    let release!: (value: unknown) => void
    h.capture.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = resolve
        }),
    )
    const pending = h.presentation.readHistorical(request)
    request.auth.userId = other
    request.serverBinding.epoch = other
    request.receipt.log_ids = [other]
    const replaced = vi.fn()
    Object.assign(h.source, { capture: replaced })
    Object.assign(h.service, { readOriginal: replaced })
    release(current())
    const value = sections(await pending)
    expect(value.provenance.epoch).toBe(serverBinding().epoch)
    expect(replaced).not.toHaveBeenCalled()
  })
  it('uses real default currentclinical/source and originalreceipt factories with expectedepoch RPC fencing', async () => {
    const rpc = vi.fn(async (name: string) => {
        if (name === 'get_mobile_current_clinical_state') return { data: current(), error: null }
        if (name === 'read_conversation_meal_feedback_v2')
          return { data: { action: 'available', feedback: saved() }, error: null }
        throw new Error('unexpected effect/read')
      }),
      from = vi.fn(() => {
        throw new Error('effects forbidden')
      }),
      db = { rpc, from } as unknown as ServiceClient
    const presentation = createSupabaseConversationMealFeedbackPresentation(db)
    expect(rpc).not.toHaveBeenCalled()
    const value = sections(await presentation.readHistorical(input()))
    expect(value.sections).toHaveLength(6)
    expect(rpc.mock.calls.map((call) => call[0])).toEqual([
      'get_mobile_current_clinical_state',
      'read_conversation_meal_feedback_v2',
      'get_mobile_current_clinical_state',
    ])
    expect(rpc).toHaveBeenCalledWith('get_mobile_current_clinical_state', {
      p_user_id: owner,
      p_mode: 'profile',
      p_body: null,
      p_expected: { epoch: serverBinding().epoch },
    })
    expect(from).not.toHaveBeenCalled()
  })
})
