import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
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
import { createSupabaseConversationMealContinuationFeedback } from './conversation-meal-continuation-feedback'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

const parent = '60000000-0000-4000-8000-000000000001'
const child = '60000000-0000-4000-8000-000000000002'
const provider = `conversation.clarification/${owner}/${parent}`
function binding() {
  return {
    parentBinding: {
      owner_id: owner,
      command_id: parent,
      input_hash: 'a'.repeat(64),
      command_protocol: 'conversation.command.v1',
      kind: 'meal.report',
      epoch: clinical().epoch,
      admitted_at: '2026-11-03T10:00:00.000001Z',
    },
    childBinding: {
      owner_id: owner,
      command_id: child,
      input_hash: 'b'.repeat(64),
      command_protocol: 'conversation.clarification.v1',
      kind: 'meal.clarify',
      epoch: clinical().epoch,
      admitted_at: '2026-11-03T10:30:00.000001Z',
    },
    parentDecisionHash: 'c'.repeat(64),
    receipt: {
      schema: 'conversation.meal-continuation-effect.v1',
      owner_id: owner,
      command_id: child,
      input_hash: 'b'.repeat(64),
      parent_command_id: parent,
      parent_input_hash: 'a'.repeat(64),
      parent_decision_hash: 'c'.repeat(64),
      epoch: clinical().epoch,
      registration_id: registrationId,
      provider_key: provider,
      meal_type: 'cafe',
      local_date: '2026-11-03',
      timezone: 'UTC',
      consumed_at: '2026-11-03T11:00:00.000001Z',
      log_ids: [logId],
      effect_version: `cmeal1:${'d'.repeat(64)}`,
    },
  }
}
function original() {
  const c = context()
  Object.assign(c.confirmed.proposal, {
    command_protocol: 'conversation.clarification.v1',
    command_id: child,
    source_provider_message_id: provider,
    source_timestamp: binding().receipt.consumed_at,
  })
  for (const row of c.logs) {
    row.raw_provider_message_id = provider
    row.consumed_at = binding().receipt.consumed_at
  }
  return c
}
function input() {
  return { auth: structuredClone(auth), binding: binding() }
}
function feedback() {
  const o = parseFeedbackV2Capture(original(), { userId: owner, registrationId, kind: 'meal' })
  return prepareRegistrationFeedbackV2({
    registrationId,
    localDate: o.facts.localDate,
    locale: 'pt-BR',
    registration: o.facts.registration,
    policy: projectCurrentClinicalPublicPolicy(o.clinical),
    officialDay: day(),
  })
}
function harness() {
  const calls: { name: string; args: Record<string, unknown> }[] = []
  let saved: unknown = null,
    source: unknown = original(),
    scope = true
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args: structuredClone(args) })
    if (name === 'read_conversation_meal_feedback_source')
      return {
        data: { action: 'available', receipt: binding().receipt, context: source },
        error: null,
        success: true,
      }
    if (name === 'read_conversation_meal_feedback_v2')
      return {
        data:
          saved === null
            ? { action: 'absent' }
            : {
                action:
                  (saved as { schema?: string }).schema === 'registration.feedback.v1'
                    ? 'legacy'
                    : 'available',
                feedback: saved,
              },
        error: null,
        success: true,
      }
    if (name === 'commit_conversation_meal_feedback_v2') {
      saved = args.p_feedback
      return { data: { action: 'committed', feedback: saved }, error: null, success: true }
    }
    throw new Error('Unexpected factual writer or source recapture')
  })
  const from = vi.fn(() => {
    throw new Error('No domain/table writer')
  })
  const loadClinical = vi.fn(async () => ({
    policy: projectCurrentClinicalPublicPolicy(
      parseFeedbackV2Capture(source, { userId: owner, registrationId, kind: 'meal' }).clinical,
    ),
    officialDay: day(),
  }))
  const capture = vi.fn(async () => clinical())
  const checkCurrentScope = vi.fn(async () => scope)
  const db = { rpc, from } as unknown as ServiceClient
  const service = createSupabaseConversationMealContinuationFeedback(db, {
    checkCurrentScope,
    loadClinical,
    clinicalSource: { capture },
  })
  return {
    calls,
    rpc,
    from,
    loadClinical,
    capture,
    checkCurrentScope,
    service,
    setSaved(v: unknown) {
      saved = v
    },
    setSource(v: unknown) {
      source = v
    },
    revoke() {
      scope = false
    },
  }
}

describe('actual linked meal feedback binding', () => {
  it('keeps the actual child protocol and parent provider identity without a fake v1 command', () => {
    const b = parseConversationMealContinuationFeedbackBinding(binding())
    expect(b).toEqual(binding())
    expect(b.receipt.schema).toBe('conversation.meal-continuation-effect.v1')
    expect(Object.isFrozen(b.receipt.log_ids)).toBe(true)
  })
  it.each([
    'owner',
    'epoch',
    'parent',
    'child',
    'hash',
    'decision',
    'provider',
    'protocol',
    'date',
    'clock',
    'duplicate',
    'extra',
  ])('rejects damaged %s linkage', (kind) => {
    const b = binding()
    if (kind === 'owner') b.childBinding.owner_id = other
    if (kind === 'epoch') b.childBinding.epoch = other
    if (kind === 'parent') b.receipt.parent_command_id = child
    if (kind === 'child') b.receipt.command_id = parent
    if (kind === 'hash') b.receipt.input_hash = 'e'.repeat(64)
    if (kind === 'decision') b.receipt.parent_decision_hash = 'e'.repeat(64)
    if (kind === 'provider') b.receipt.provider_key = `conversation.meal/${owner}/${child}`
    if (kind === 'protocol') b.receipt.schema = 'conversation.meal-effect.v1'
    if (kind === 'date') b.receipt.local_date = '2026-11-04'
    if (kind === 'clock') b.receipt.consumed_at = '2026-11-03T10:20:00.000001Z'
    if (kind === 'duplicate') b.receipt.log_ids.push(logId)
    if (kind === 'extra') Object.assign(b.receipt, { snapshot: { private: true } })
    expect(() => parseConversationMealContinuationFeedbackBinding(b)).toThrow()
  })
})
describe('linked frozen original feedback and current presentation', () => {
  it('seals all six real sections after the actual child effect without another factual writer', async () => {
    const h = harness()
    expect(h.calls).toEqual([])
    const result = await h.service.ensureOriginal(input())
    expect(result).toEqual(feedback())
    expect(h.calls.map((c) => c.name)).toEqual([
      'read_conversation_meal_feedback_v2',
      'read_conversation_meal_feedback_source',
      'commit_conversation_meal_feedback_v2',
    ])
    expect(h.calls.every((c) => c.args.p_command_id === child && c.args.p_user_id === owner)).toBe(
      true,
    )
    expect(h.calls[2]?.args.p_expected_effect_version).toBe(binding().receipt.effect_version)
    expect(
      result?.schema === 'registration.feedback.v2' &&
        result.registration.kind === 'meal' &&
        result.registration.items[0]?.quantity.unit,
    ).toBe('mL')
    expect(h.from).not.toHaveBeenCalled()
  })
  it('replays the first stored winner with no recapture, clinical reload or seal', async () => {
    const h = harness()
    h.setSaved(feedback())
    expect(await h.service.ensureOriginal(input())).toEqual(feedback())
    expect(h.calls.map((c) => c.name)).toEqual(['read_conversation_meal_feedback_v2'])
    expect(h.loadClinical).not.toHaveBeenCalled()
  })
  it('preserves an actual legacy winner instead of replacing it with v2', async () => {
    const h = harness()
    h.setSaved(legacyFeedback())
    expect(await h.service.ensureOriginal(input())).toEqual(legacyFeedback())
    expect(h.calls).toHaveLength(1)
  })
  it('uses one read to recover a lost seal response and never repeats commit', async () => {
    const h = harness(),
      real = h.rpc.getMockImplementation()
    h.rpc.mockImplementation(async (name, args) => {
      const result = await real?.(name, args)
      if (name === 'commit_conversation_meal_feedback_v2') throw new Error('lost response')
      return result as Awaited<ReturnType<NonNullable<typeof real>>>
    })
    expect(await h.service.ensureOriginal(input())).toEqual(feedback())
    expect(h.calls.filter((c) => c.name === 'commit_conversation_meal_feedback_v2')).toHaveLength(1)
    expect(h.calls.filter((c) => c.name === 'read_conversation_meal_feedback_v2')).toHaveLength(2)
  })
  it('withholds unknown optional enrichment without changing saved food', async () => {
    const h = harness()
    h.loadClinical.mockRejectedValueOnce(new Error('day unavailable'))
    const result = await h.service.ensureOriginal(input())
    expect(result?.schema).toBe('registration.feedback.v2')
    expect(result?.schema === 'registration.feedback.v2' && result.day).toBeNull()
    expect(h.from).not.toHaveBeenCalled()
  })
  it('rejects a source belonging to the parent protocol even if its food numbers match', async () => {
    const h = harness(),
      c = original()
    Object.assign(c.confirmed.proposal, { command_protocol: 'conversation.command.v1' })
    h.setSource(c)
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.calls.some((c) => c.name.startsWith('commit_'))).toBe(false)
  })
  it('preserves microsecond identity between the frozen logs and actual child receipt', async () => {
    const h = harness(),
      c = original()
    const row = c.logs[0]
    if (!row) throw new Error('Missing fixture log')
    row.consumed_at = '2026-11-03T11:00:00.000002Z'
    h.setSource(c)
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.calls.some((c) => c.name.startsWith('commit_'))).toBe(false)
  })
  it('never exposes feedback or seals after its original authenticated lease is revoked', async () => {
    const h = harness(),
      real = h.rpc.getMockImplementation()
    h.rpc.mockImplementation(async (name, args) => {
      const result = await real?.(name, args)
      h.revoke()
      return result as Awaited<ReturnType<NonNullable<typeof real>>>
    })
    expect(await h.service.ensureOriginal(input())).toBeNull()
    expect(h.calls).toHaveLength(1)
  })
  it('rejects a foreign patient before the first RPC', async () => {
    const h = harness(),
      i = input()
    i.auth.userId = other
    expect(await h.service.ensureOriginal(i)).toBeNull()
    expect(h.calls).toEqual([])
  })
  it('renders six historical sections from the actual sealed winner under stable current policy', async () => {
    const h = harness()
    h.setSaved(feedback())
    const result = await h.service.readHistorical(input())
    expect(result?.status).toBe('available')
    expect(result?.format === 'sections' && result.sections.map((s) => s.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    expect(result?.provenance.command_id).toBe(child)
    expect(h.calls.map((c) => c.name)).toEqual(['read_conversation_meal_feedback_v2'])
    expect(h.capture).toHaveBeenCalledTimes(2)
    expect(h.loadClinical).not.toHaveBeenCalled()
  })
  it('withholds old guidance after an epoch reset rather than republishing stale targets', async () => {
    const h = harness()
    h.setSaved(feedback())
    h.capture
      .mockResolvedValueOnce(clinical())
      .mockResolvedValueOnce({ ...clinical(), epoch: other })
    expect(await h.service.readHistorical(input())).toBeNull()
    expect(h.calls).toHaveLength(1)
  })
  it('does not present a child effect from after the actual current observation clock', async () => {
    const h = harness()
    h.setSaved(feedback())
    const c = clinical()
    c.observed_at = c.safety.observed_at = '2026-11-03T10:45:00.000001Z'
    h.capture.mockResolvedValue(c)
    expect(await h.service.readHistorical(input())).toBeNull()
    expect(h.calls).toEqual([])
  })
  it.each([
    'false',
    'unknown',
    'getter',
  ])('refuses damaged SDK %s metadata without evaluating hooks', async (kind) => {
    const h = harness(),
      hook = vi.fn(() => feedback())
    h.rpc.mockImplementationOnce(async () => {
      const response: Record<string, unknown> = {
        data: { action: 'available', feedback: feedback() },
        error: null,
        success: true,
      }
      if (kind === 'false') response.success = false
      if (kind === 'unknown') response.private = 'must not escape'
      if (kind === 'getter')
        Object.defineProperty(response, 'success', { enumerable: true, get: hook })
      return response as Awaited<ReturnType<typeof h.rpc>>
    })
    expect(await h.service.readOriginal(input())).toBeNull()
    expect(hook).not.toHaveBeenCalled()
  })
  it('pins callbacks and the original identity before asynchronous work', async () => {
    const h = harness(),
      i = input(),
      real = h.rpc.getMockImplementation()
    h.rpc.mockImplementationOnce(async (name, args) => {
      i.binding.childBinding.command_id = parent
      i.auth.userId = other
      return (await real?.(name, args)) as Awaited<ReturnType<NonNullable<typeof real>>>
    })
    expect(await h.service.ensureOriginal(i)).toEqual(feedback())
    expect(h.calls.every((c) => c.args.p_user_id === owner && c.args.p_command_id === child)).toBe(
      true,
    )
  })
  it('refuses a getter in an outbound historical binding before any RPC', async () => {
    const h = harness(),
      i = input(),
      hook = vi.fn(() => binding())
    Object.defineProperty(i, 'binding', { enumerable: true, get: hook })
    expect(await h.service.readOriginal(i)).toBeNull()
    expect(hook).not.toHaveBeenCalled()
    expect(h.calls).toEqual([])
  })
  it('masks historical targets and block under current clinical protection', async () => {
    const h = harness()
    h.setSaved(feedback())
    const c = clinical()
    Object.assign(c.health_state, {
      hold_active: true,
      safety_revision: '1',
      last_declared_at: c.observed_at,
      items: [{ code: 'reduced_intake', declared_at: c.observed_at }],
    })
    Object.assign(c.safety, { hold_active: true })
    h.capture.mockResolvedValue(c)
    const result = await h.service.readHistorical(input())
    expect(result?.format).toBe('sections')
    const texts = result?.format === 'sections' ? result.sections.map((s) => s.text).join('\n') : ''
    expect(texts).not.toContain('1.900')
    expect(texts).not.toContain('7.700')
    expect(h.calls.every((c) => c.name.startsWith('read_'))).toBe(true)
  })
})
