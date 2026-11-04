import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { writerBinding, writerCommand, writerEpoch } from './__fixtures__/conversation-meal-writer'
import { createSupabaseConversationMealDecisionStore } from './conversation-meal-decision-store'

const command = writerCommand()
const identity = {
  ownerId: command.ownerId,
  commandId: command.commandId,
  inputHash: command.inputHash,
  epoch: writerEpoch,
}
const payload = {
  schema: 'conversation.meal-decision.v1',
  status: 'not_recorded',
  reason: 'future',
  food_indexes: [],
}
const proof = {
  sourceHash: 'b'.repeat(64),
  attemptId: '10000000-0000-4000-8000-000000000080',
  resultHash: 'c'.repeat(64),
}
function receipt() {
  return {
    ...payload,
    owner_id: identity.ownerId,
    command_id: identity.commandId,
    epoch: writerEpoch,
    input_hash: identity.inputHash,
    source_hash: proof.sourceHash,
    attempt_id: proof.attemptId,
    semantic_result_hash: proof.resultHash,
    decision_hash: createHash('sha256')
      .update(
        '{"food_indexes":[],"reason":"future","schema":"conversation.meal-decision.v1","status":"not_recorded"}',
      )
      .digest('hex'),
    sealed_at: '2026-11-04T12:01:00.000004Z',
  }
}
function setup(
  raw: unknown = { action: 'available', command: writerBinding(), decision: receipt() },
) {
  const rpc = vi.fn().mockResolvedValue({ data: raw, error: null })
  const from = vi.fn(() => {
    throw Error('No domain lookup')
  })
  return {
    rpc,
    from,
    store: createSupabaseConversationMealDecisionStore({ rpc, from } as unknown as ServiceClient),
  }
}
describe('durable non-registration decision store', () => {
  it('reads one closed actual original command and terminal winner without side effects', async () => {
    const f = setup()
    expect(f.rpc).not.toHaveBeenCalled()
    expect(await f.store.read(identity)).toEqual({
      action: 'available',
      binding: writerBinding(),
      decision: receipt(),
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.rpc).toHaveBeenCalledWith('read_conversation_meal_decision', {
      p_user_id: identity.ownerId,
      p_command_id: identity.commandId,
      p_expected_epoch: writerEpoch,
      p_expected_input_hash: identity.inputHash,
    })
    expect(f.from).not.toHaveBeenCalled()
  })
  it('seals exactly once with original source/attempt/result proof', async () => {
    const f = setup({ action: 'sealed', command: writerBinding(), decision: receipt() })
    expect(await f.store.seal(identity, proof, payload)).toMatchObject({
      action: 'sealed',
      decision: receipt(),
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.rpc).toHaveBeenCalledWith('seal_conversation_meal_decision', {
      p_user_id: identity.ownerId,
      p_command_id: identity.commandId,
      p_expected_epoch: writerEpoch,
      p_expected_input_hash: identity.inputHash,
      p_expected_source_hash: proof.sourceHash,
      p_attempt_id: proof.attemptId,
      p_expected_result_hash: proof.resultHash,
      p_decision: payload,
    })
  })
  it.each([
    'owner_id',
    'command_id',
    'epoch',
    'input_hash',
  ])('rejects a mismatched %s without a success claim', async (key) => {
    const f = setup({
      action: 'available',
      command: writerBinding(),
      decision: { ...receipt(), [key]: key.endsWith('hash') ? 'f'.repeat(64) : proof.attemptId },
    })
    await expect(f.store.read(identity)).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('preserves the opaque SQL decision token without reserializing numeric lexemes', async () => {
    // PostgreSQL can retain 0.0 in JSONB while JSON.parse yields the number 0.
    // The trusted SQL read already verifies its canonical checksum.
    const actual = { ...receipt(), food_indexes: [0], decision_hash: 'd'.repeat(64) }
    const f = setup({ action: 'available', command: writerBinding(), decision: actual })
    expect(await f.store.read(identity)).toMatchObject({ decision: actual })
  })
  it.each([
    { ...payload, food_indexes: [0, 0] },
    { ...payload, food_indexes: [30] },
    { ...payload, owner_id: identity.ownerId },
    { ...payload, reason: '' },
  ])('rejects an invalid closed decision before RPC', async (input) => {
    const f = setup()
    await expect(f.store.seal(identity, proof, input)).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).not.toHaveBeenCalled()
  })
  it('preserves a refusal without retry or domain lookup', async () => {
    const f = setup({ action: 'resolved_conflict' })
    expect(await f.store.seal(identity, proof, payload)).toEqual({ action: 'resolved_conflict' })
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.from).not.toHaveBeenCalled()
  })
  it('rejects an unknown transport outcome without retrying a write', async () => {
    const f = setup()
    f.rpc.mockRejectedValue(new Error('private credential details'))
    await expect(f.store.seal(identity, proof, payload)).rejects.toMatchObject({
      status: 503,
      code: 'conversation_decision_unavailable',
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
})
