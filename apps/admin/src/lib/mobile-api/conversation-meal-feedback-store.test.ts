import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  context,
  fixtureFirst,
  legacyFeedback,
  logId,
  other,
  owner,
  registrationId,
} from './__fixtures__/feedback-v2-source'
import { bindConversationCommand } from './conversation-command-contracts'
import { createSupabaseConversationMealFeedbackStore } from './conversation-meal-feedback-store'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

const commandId = '10000000-0000-4000-8000-000000000009'
const provider = `conversation.meal/${owner}/${commandId}`
const command = () =>
  bindConversationCommand(owner, `cmsg1:${commandId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
    kind: 'meal.report',
    meal_type: 'cafe',
    source: { channel: 'text', text: 'Comi leite integral 206 g' },
  })
function original() {
  const c = context()
  Object.assign(c.confirmed.proposal, {
    source_provider_message_id: provider,
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
  })
  for (const row of c.logs) row.raw_provider_message_id = provider
  return c
}
function receipt() {
  return {
    schema: 'conversation.meal-effect.v1',
    owner_id: owner,
    command_id: commandId,
    input_hash: command().inputHash,
    registration_id: registrationId,
    provider_key: provider,
    meal_type: 'cafe',
    local_date: '2026-11-03',
    timezone: 'UTC',
    consumed_at: '2026-11-03T11:00:00Z',
    log_ids: [logId],
    effect_version: `cmeal1:${'a'.repeat(64)}`,
  }
}
const binding = () => ({ command: command(), receipt: receipt() })
function feedback() {
  const observation = parseFeedbackV2Capture(original(), {
    userId: owner,
    registrationId,
    kind: 'meal',
  })
  return prepareRegistrationFeedbackV2({
    registrationId,
    localDate: observation.facts.localDate,
    locale: 'pt-BR',
    registration: observation.facts.registration,
    policy: null,
    officialDay: null,
  })
}
function db(data: unknown) {
  const rpc = vi.fn<(name: string, args: unknown) => Promise<{ data: unknown; error: unknown }>>(
    async () => ({ data, error: null }),
  )
  const from = vi.fn(() => {
    throw new Error('live source/domain/analytics forbidden')
  })
  return { rpc, from, client: { rpc, from } as unknown as ServiceClient }
}

describe('command feedback uses only frozen-source RPCs', () => {
  it('is inert and reads the original private source without generic T2C or live recapture', async () => {
    const raw = { action: 'available', receipt: receipt(), context: original() },
      d = db(raw)
    const store = createSupabaseConversationMealFeedbackStore(d.client)
    expect(d.rpc).not.toHaveBeenCalled()
    const result = await store.readSource(command())
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('read_conversation_meal_feedback_source', {
      p_user_id: owner,
      p_command_id: commandId,
    })
    expect(result.action).toBe('available')
    if (result.action !== 'available') throw new Error('fixture')
    expect(result.receipt).toEqual(receipt())
    expect(result.originalObservation.facts.logIds).toEqual([logId])
    expect(Object.isFrozen(result.originalObservation.context.logs)).toBe(true)
    fixtureFirst(raw.context.logs).kcal = 999
    expect(result.originalObservation.facts.registration).toEqual(feedback().registration)
    expect(d.from).not.toHaveBeenCalled()
  })
  it('preserves explicit unavailable original context and the confirmed factual receipt', async () => {
    const value = {
        action: 'unavailable',
        reason: 'original_context_unavailable',
        receipt: receipt(),
      },
      d = db(value)
    expect(
      await createSupabaseConversationMealFeedbackStore(d.client).readSource(command()),
    ).toEqual(value)
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.from).not.toHaveBeenCalled()
  })
  it.each([
    'available',
    'legacy',
  ] as const)('reads %s winner without source reads or new effects', async (action) => {
    const saved = action === 'available' ? feedback() : legacyFeedback(),
      d = db({ action, feedback: saved })
    const result = await createSupabaseConversationMealFeedbackStore(d.client).readReceipt(
      binding(),
    )
    expect(result).toEqual({ action, feedback: saved })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('read_conversation_meal_feedback_v2', {
      p_user_id: owner,
      p_command_id: commandId,
    })
    expect(Object.isFrozen(result)).toBe(true)
  })
  it.each([
    'committed',
    'replay',
    'legacy',
  ] as const)('commits via only the command RPC and preserves %s', async (action) => {
    const saved = action === 'legacy' ? legacyFeedback() : feedback(),
      d = db({ action, feedback: saved })
    const result = await createSupabaseConversationMealFeedbackStore(d.client).commit({
      ...binding(),
      feedback: action === 'committed' ? saved : null,
    })
    expect(result).toEqual({ action, feedback: saved })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('commit_conversation_meal_feedback_v2', {
      p_user_id: owner,
      p_command_id: commandId,
      p_expected_effect_version: receipt().effect_version,
      p_feedback: action === 'committed' ? saved : null,
    })
  })
  it('replay/legacy wins before invalid proposed v2 payload and a wrong but valid version', async () => {
    for (const action of ['replay', 'legacy']) {
      const saved = action === 'legacy' ? legacyFeedback() : feedback(),
        d = db({ action, feedback: saved })
      const result = await createSupabaseConversationMealFeedbackStore(d.client).commit({
        command: command(),
        receipt: { ...receipt(), effect_version: `cmeal1:${'b'.repeat(64)}` },
        feedback: { invalid: true },
      })
      expect(result).toEqual({ action, feedback: saved })
      expect(d.rpc).toHaveBeenCalledTimes(1)
    }
  })
  it.each([
    'absent',
    'stale_epoch',
    'event_conflict',
    'source_conflict',
  ])('retains explicit refusal %s without another operation', async (action) => {
    const d = db({ action }),
      store = createSupabaseConversationMealFeedbackStore(d.client)
    expect(await store.commit({ ...binding(), feedback: null })).toEqual({ action })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.from).not.toHaveBeenCalled()
  })
  it('unknown commit outcome is not retried; recovery is only an explicit receipt read', async () => {
    const d = db({ action: 'available', feedback: feedback() })
    d.rpc.mockRejectedValueOnce(new Error('private-sentinel-token'))
    const store = createSupabaseConversationMealFeedbackStore(d.client)
    await expect(store.commit({ ...binding(), feedback: feedback() })).rejects.toMatchObject({
      code: 'conversation_meal_feedback_unavailable',
      status: 503,
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(await store.readReceipt(binding())).toEqual({
      action: 'available',
      feedback: feedback(),
    })
    expect(d.rpc.mock.calls.map((call) => call[0])).toEqual([
      'commit_conversation_meal_feedback_v2',
      'read_conversation_meal_feedback_v2',
    ])
  })
  it.each([
    ['owner', { owner_id: other }],
    ['command', { command_id: other }],
    ['input hash', { input_hash: 'b'.repeat(64) }],
    ['provider', { provider_key: 'live-generic' }],
    ['duplicate logs', { log_ids: [logId, logId] }],
    ['version', { effect_version: 'invalid' }],
    ['closed receipt', { private_context: 'secret' }],
  ])('rejects %s factual receipt binding before RPC', async (_label, change) => {
    const d = db({ action: 'available', feedback: feedback() })
    await expect(
      createSupabaseConversationMealFeedbackStore(d.client).readReceipt({
        command: command(),
        receipt: { ...receipt(), ...change },
      }),
    ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
    expect(d.rpc).not.toHaveBeenCalled()
  })
  it.each([
    ['foreign registration', { registration_id: other }],
    ['foreign logs', { log_ids: [other] }],
    ['wrong date', { local_date: '2026-11-02' }],
    ['wrong meal', { meal_type: 'jantar' }],
    ['wrong instant', { consumed_at: '2026-11-03T11:00:00.000001Z' }],
  ])('rejects original source/receipt %s mismatch', async (_label, change) => {
    const d = db({ action: 'available', receipt: { ...receipt(), ...change }, context: original() })
    await expect(
      createSupabaseConversationMealFeedbackStore(d.client).readSource(command()),
    ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
  })
  it('rejects NULL available context, current recapture mismatches and rewritten private JSON', async () => {
    const changed = original()
    fixtureFirst(changed.logs).kcal = 999
    const rewrite = original()
    Object.defineProperty(rewrite.clinical, '__proto__', { value: { x: 1 }, enumerable: true })
    for (const raw of [null, changed, rewrite]) {
      const d = db({ action: 'available', receipt: receipt(), context: raw })
      await expect(
        createSupabaseConversationMealFeedbackStore(d.client).readSource(command()),
      ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
      expect(d.rpc).toHaveBeenCalledTimes(1)
    }
  })
  it('binds returned v2 registration/logs/date and committed echo while preserving v1', async () => {
    for (const changed of [
      { ...feedback(), registration_id: other },
      { ...feedback(), local_date: '2026-11-02' },
    ]) {
      const d = db({ action: 'available', feedback: changed })
      await expect(
        createSupabaseConversationMealFeedbackStore(d.client).readReceipt(binding()),
      ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
    }
    const saved = feedback(),
      d = db({ action: 'committed', feedback: { ...saved, locale: 'en' } })
    await expect(
      createSupabaseConversationMealFeedbackStore(d.client).commit({
        ...binding(),
        feedback: saved,
      }),
    ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
  })
  it('pins original bound/receipt/payload and SDK callback before await', async () => {
    const saved = feedback(),
      d = db(null),
      originalBinding = structuredClone(binding()),
      payload = structuredClone(saved)
    let release!: (value: { data: unknown; error: unknown }) => void
    d.rpc.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = resolve
        }),
    )
    const store = createSupabaseConversationMealFeedbackStore(d.client)
    const pending = store.commit({ ...originalBinding, feedback: payload })
    originalBinding.command = { ...originalBinding.command, ownerId: other }
    originalBinding.receipt.log_ids = [other]
    payload.locale = 'en'
    const changedRpc = vi.fn()
    Object.assign(d.client, { rpc: changedRpc })
    release({ data: { action: 'committed', feedback: saved }, error: null })
    expect(await pending).toEqual({ action: 'committed', feedback: saved })
    expect(d.rpc.mock.calls[0]?.[1]).toMatchObject({ p_user_id: owner, p_feedback: saved })
    expect(changedRpc).not.toHaveBeenCalled()
  })
  it('redacts SQL/private errors and malformed DTOs without any fallback', async () => {
    for (const result of [
      { data: null, error: { message: 'private-sentinel-token' } },
      { data: { action: 'unavailable', reason: 'unknown', receipt: receipt() }, error: null },
    ]) {
      const d = db(null)
      d.rpc.mockResolvedValue(result)
      try {
        await createSupabaseConversationMealFeedbackStore(d.client).readSource(command())
        throw new Error('expected')
      } catch (error) {
        expect(error).toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
        expect(String(error)).not.toContain('private-sentinel')
      }
      expect(d.from).not.toHaveBeenCalled()
    }
  })
  it('rejects forged original bindings before SQL and rejects a substituted unavailable receipt', async () => {
    const value = {
        action: 'unavailable',
        reason: 'original_context_unavailable',
        receipt: receipt(),
      },
      d = db(value)
    const store = createSupabaseConversationMealFeedbackStore(d.client)
    await expect(
      store.readSource({ ...command(), inputHash: 'f'.repeat(64) }),
    ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
    expect(d.rpc).not.toHaveBeenCalled()
    expect(await store.commit({ ...binding(), feedback: null })).toEqual(value)
    d.rpc.mockResolvedValueOnce({
      data: { ...value, receipt: { ...receipt(), effect_version: `cmeal1:${'b'.repeat(64)}` } },
      error: null,
    })
    await expect(store.commit({ ...binding(), feedback: null })).rejects.toMatchObject({
      code: 'conversation_meal_feedback_unavailable',
    })
    expect(d.rpc).toHaveBeenCalledTimes(2)
  })
  it('all status reads preserve absent, stale and conflicts without any commit/capture', async () => {
    for (const action of ['absent', 'stale_epoch', 'event_conflict'] as const) {
      const d = db({ action }),
        store = createSupabaseConversationMealFeedbackStore(d.client)
      expect(await store.readReceipt(binding())).toEqual({ action })
      expect(d.rpc).toHaveBeenCalledTimes(1)
      if (action !== 'event_conflict') expect(await store.readSource(command())).toEqual({ action })
      expect(
        d.rpc.mock.calls.every(([name]) => name.startsWith('read_conversation_meal_feedback')),
      ).toBe(true)
    }
  })
  it('refuses a v2 receipt with another log ID while keeping the closed factual IDs', async () => {
    const saved = feedback()
    if (saved.registration.kind !== 'meal') throw new Error('fixture')
    fixtureFirst(saved.registration.items).log_id = other
    const d = db({ action: 'available', feedback: saved })
    await expect(
      createSupabaseConversationMealFeedbackStore(d.client).readReceipt(binding()),
    ).rejects.toMatchObject({ code: 'conversation_meal_feedback_unavailable' })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
})
