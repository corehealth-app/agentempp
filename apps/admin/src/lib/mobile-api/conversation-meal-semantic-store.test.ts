import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  candidateCommand,
  candidateEpoch,
  candidateId,
  candidateOwner,
} from './__fixtures__/conversation-candidate'
import { createSupabaseConversationMealSemanticStore } from './conversation-meal-semantic-store'

const attemptId = '10000000-0000-4000-8000-000000000010'
const sourceHash = 'a'.repeat(64)
const version = 'conversation.meal-interpreter.v1'
function result() {
  return {
    schema: 'conversation.meal-interpretation.v1',
    interpreter_version: version,
    owner_id: candidateOwner,
    command_id: candidateId,
    attempt_id: attemptId,
    input_hash: candidateCommand().inputHash,
    source_hash: sourceHash,
    source_units: ['command_text'],
    decision: 'clarification_required',
    reason: 'ambiguous',
    sources: [
      {
        unit: 'command_text',
        classification: 'ambiguous',
        spans: [{ start: 0, end: 15, kind: 'other', food_index: null }],
        visual_indexes: [],
      },
    ],
    foods: [],
    provider_metadata: {
      model: 'anthropic/claude-haiku-4.5',
      prompt_tokens: 12,
      completion_tokens: 20,
      cost_usd: 0.00000001,
      latency_ms: 500,
    },
  }
}
function envelope(action = 'available', status = 'completed') {
  return {
    action,
    owner_id: candidateOwner,
    command_id: candidateId,
    attempt_id: attemptId,
    interpreter_version: version,
    input_hash: candidateCommand().inputHash,
    source_hash: sourceHash,
    epoch: candidateEpoch,
    status,
    result: status === 'completed' ? result() : null,
    result_hash: status === 'completed' ? 'b'.repeat(64) : null,
    started_at: '2026-11-04T00:00:00Z',
    finished_at: status === 'started' ? null : '2026-11-04T00:00:01Z',
    error_code:
      status === 'unknown'
        ? 'provider_outcome_unknown'
        : status === 'error'
          ? 'provider_terminal_error'
          : null,
  }
}
function db(raw: unknown) {
  const rpc = vi.fn(async (_name: string, _args: unknown) => ({
    data: raw,
    error: null as unknown,
  }))
  const from = vi.fn(() => {
    throw new Error('domain/media/analytics lookup forbidden')
  })
  return { rpc, from, client: { rpc, from } as unknown as ServiceClient }
}

describe('durable semantic invocation transport', () => {
  it('is inert and read cannot grant a provider call', async () => {
    const d = db(envelope())
    const store = createSupabaseConversationMealSemanticStore(d.client)
    expect(d.rpc).not.toHaveBeenCalled()
    const read = await store.read(candidateCommand())
    expect(read).toMatchObject({ action: 'available', status: 'completed', result: result() })
    expect(read.action).not.toBe('claimed')
    expect(d.rpc).toHaveBeenCalledWith('read_conversation_meal_semantic_attempt', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
      p_interpreter_version: version,
    })
    expect(d.from).not.toHaveBeenCalled()
  })
  it('only accepts claimed from start for the exact source', async () => {
    const d = db(envelope('claimed', 'started'))
    const read = await createSupabaseConversationMealSemanticStore(d.client).start(
      candidateCommand(),
      sourceHash,
    )
    expect(read).toMatchObject({ action: 'claimed', attempt_id: attemptId, status: 'started' })
    expect(d.rpc).toHaveBeenCalledWith('start_conversation_meal_semantic_attempt', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
      p_interpreter_version: version,
      p_expected_source_hash: sourceHash,
    })
  })
  it.each([
    'started',
    'unknown',
    'error',
  ])('preserves %s as reconciliation, not a new permission', async (status) => {
    const d = db(envelope('reconciliation_required', status))
    const store = createSupabaseConversationMealSemanticStore(d.client)
    expect((await store.read(candidateCommand())).action).toBe('reconciliation_required')
    expect((await store.start(candidateCommand(), sourceHash)).action).toBe(
      'reconciliation_required',
    )
    expect(d.rpc).toHaveBeenCalledTimes(2)
  })
  it('stores one result and treats the DB numeric hash as an opaque token', async () => {
    const d = db(envelope('committed'))
    const store = createSupabaseConversationMealSemanticStore(d.client)
    expect(await store.commit(candidateCommand(), attemptId, result())).toMatchObject({
      action: 'committed',
      result_hash: 'b'.repeat(64),
    })
    expect(d.rpc).toHaveBeenCalledWith('commit_conversation_meal_semantic_result', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
      p_interpreter_version: version,
      p_attempt_id: attemptId,
      p_result: result(),
    })
  })
  it('keeps a first terminal winner when a later payload is invalid', async () => {
    const d = db(envelope('replay'))
    expect(
      await createSupabaseConversationMealSemanticStore(d.client).commit(
        candidateCommand(),
        attemptId,
        null,
      ),
    ).toMatchObject({ action: 'replay', result: result() })
  })
  it('marks an unknown outcome once without inventing a result', async () => {
    const d = db(envelope('committed', 'unknown'))
    const store = createSupabaseConversationMealSemanticStore(d.client)
    expect(
      await store.markUnknown(candidateCommand(), attemptId, 'provider_outcome_unknown'),
    ).toMatchObject({ status: 'unknown' })
    expect(d.rpc).toHaveBeenCalledWith('mark_conversation_meal_semantic_unknown', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
      p_interpreter_version: version,
      p_attempt_id: attemptId,
      p_error_code: 'provider_outcome_unknown',
    })
  })
  it.each([
    'absent',
    'stale_epoch',
    'source_required',
    'source_conflict',
    'day_closed',
    'attempt_conflict',
  ])('preserves refusal %s without extra work', async (action) => {
    const d = db({ action })
    const store = createSupabaseConversationMealSemanticStore(d.client)
    const response =
      action === 'attempt_conflict'
        ? await store.commit(candidateCommand(), attemptId, null)
        : action === 'absent' || action === 'stale_epoch'
          ? await store.read(candidateCommand())
          : await store.start(candidateCommand(), sourceHash)
    expect(response).toEqual({ action })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    ['owner_id', '10000000-0000-4000-8000-000000000099'],
    ['command_id', '10000000-0000-4000-8000-000000000099'],
    ['input_hash', 'c'.repeat(64)],
    ['interpreter_version', 'future'],
    ['epoch', null],
    ['attempt_id', null],
    ['result_hash', null],
    ['finished_at', null],
    ['error_code', 'provider_outcome_unknown'],
    ['extra', true],
  ])('rejects malformed or cross-bound %s', async (key, value) => {
    const d = db({ ...envelope(), [key]: value })
    await expect(
      createSupabaseConversationMealSemanticStore(d.client).read(candidateCommand()),
    ).rejects.toMatchObject({ code: 'conversation_meal_semantic_unavailable' })
  })
  it('rejects claim on read and replay response mismatched to a start source', async () => {
    const d = db(envelope('claimed', 'started')),
      store = createSupabaseConversationMealSemanticStore(d.client)
    await expect(store.read(candidateCommand())).rejects.toMatchObject({ status: 503 })
    d.rpc.mockResolvedValueOnce({
      data: { ...envelope('replay'), source_hash: 'c'.repeat(64) },
      error: null,
    })
    await expect(store.start(candidateCommand(), sourceHash)).rejects.toMatchObject({ status: 503 })
  })
  it('binds the result owner/source/attempt to its durable envelope', async () => {
    for (const field of ['owner_id', 'command_id', 'attempt_id', 'input_hash', 'source_hash']) {
      const raw = envelope()
      if (raw.result === null) throw new Error('fixture result absent')
      Object.assign(raw.result, {
        [field]: field.endsWith('hash') ? 'c'.repeat(64) : '10000000-0000-4000-8000-000000000099',
      })
      await expect(
        createSupabaseConversationMealSemanticStore(db(raw).client).read(candidateCommand()),
      ).rejects.toMatchObject({ status: 503 })
    }
  })
  it('detaches command and submitted JSON before awaiting RPC', async () => {
    const raw = envelope('committed'),
      d = db(raw),
      payload = result(),
      command = structuredClone(candidateCommand())
    const store = createSupabaseConversationMealSemanticStore(d.client)
    const response = store.commit(command, attemptId, payload)
    payload.provider_metadata.model = 'mutated'
    Object.assign(command.command, { source: { channel: 'text', text: 'changed' } })
    const saved = await response
    expect(saved).toMatchObject({ result: result() })
    expect(d.rpc.mock.calls[0]?.[1]).toMatchObject({ p_result: result() })
    if (raw.result === null) throw new Error('fixture result absent')
    raw.result.provider_metadata.model = 'changed response'
    if (!('result' in saved)) throw new Error('missing saved interpretation')
    expect(Object.isFrozen(saved.result)).toBe(true)
  })
  it('never retries or leaks private errors on an uncertain RPC', async () => {
    const d = db(null)
    d.rpc.mockRejectedValue(new Error('private-provider-secret'))
    await expect(
      createSupabaseConversationMealSemanticStore(d.client).commit(
        candidateCommand(),
        attemptId,
        result(),
      ),
    ).rejects.toMatchObject({ message: 'Meal interpretation state is unavailable' })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
})
