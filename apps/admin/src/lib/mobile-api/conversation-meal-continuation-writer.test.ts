import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import actualSQL from './__fixtures__/conversation-meal-continuation-read-sql.json'
import { bindConversationMealReply } from './conversation-meal-continuation-input'
import { createSupabaseConversationMealContinuationWriter } from './conversation-meal-continuation-writer'

const samples = actualSQL.samples
function example(name: 'saved' | 'prepared' | 'admitted_quantity_reply' = 'saved') {
  const state = structuredClone(samples[name])
  const b = state.reply.binding
  const identity = {
    ownerId: b.owner_id,
    parentCommandId: state.parent.binding.command_id,
    parentInputHash: state.parent.binding.input_hash,
    epoch: b.epoch,
    replyId: b.command_id,
    replyInputHash: b.input_hash,
  }
  const bound = bindConversationMealReply({
    binding: {
      ownerId: identity.ownerId,
      parentCommandId: identity.parentCommandId,
      parentInputHash: identity.parentInputHash,
      epoch: identity.epoch,
      decisionHash: state.parent.decision.decision_hash,
    },
    replyId: identity.replyId,
    idempotencyKey: `cmreply1:${identity.replyId}`,
    input: state.reply.body,
  })
  return { state, identity, bound }
}
function server(state: unknown, write: unknown = { data: {}, error: null }) {
  const rpc = vi.fn(async (name: string, _parameters?: unknown) => {
    if (name === 'read_conversation_meal_continuation') return { data: state, error: null }
    if (write instanceof Error) throw write
    return write
  })
  return {
    rpc,
    writer: createSupabaseConversationMealContinuationWriter({ rpc } as unknown as ServiceClient),
  }
}
function storedPreparation(state: ReturnType<typeof example>['state']) {
  if (!state.reply.preparation) throw new Error('Actual preparation fixture required')
  return state.reply.preparation
}

describe('linked continuation one-write/one-read bridge', () => {
  it('proves actual persisted admission from a closed full read, not an RPC success label', async () => {
    const f = example('admitted_quantity_reply'),
      s = server(f.state)
    const result = await s.writer.admit(f.bound)
    expect(result.status).toBe('observed')
    expect(result.state).toEqual(f.state)
    expect(s.rpc.mock.calls.map(([name]) => name)).toEqual([
      'admit_conversation_meal_reply',
      'read_conversation_meal_continuation',
    ])
    expect(s.rpc).toHaveBeenNthCalledWith(1, 'admit_conversation_meal_reply', {
      p_user_id: f.identity.ownerId,
      p_parent_command_id: f.identity.parentCommandId,
      p_parent_input_hash: f.identity.parentInputHash,
      p_expected_epoch: f.identity.epoch,
      p_parent_decision_hash: f.bound.binding.decisionHash,
      p_reply_id: f.identity.replyId,
      p_input: f.bound.input,
    })
  })
  it('proves preparation from its actual immutable stored payload', async () => {
    const f = example('prepared'),
      s = server(f.state)
    const result = await s.writer.prepare(f.identity, storedPreparation(f.state).preparation)
    expect(result.status).toBe('observed')
    expect(result.state).toEqual(f.state)
    expect(s.rpc.mock.calls.map(([name]) => name)).toEqual([
      'prepare_conversation_meal_continuation',
      'read_conversation_meal_continuation',
    ])
  })
  it('proves the actual child effect after an uncertain commit with no second writer', async () => {
    const f = example(),
      s = server(f.state, new Error('lost response'))
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result.status).toBe('observed')
    expect(result.state).toEqual(f.state)
    expect(s.rpc.mock.calls.map(([name]) => name)).toEqual([
      'commit_conversation_meal_continuation',
      'read_conversation_meal_continuation',
    ])
  })
  it('never treats ready preparation as a saved meal', async () => {
    const f = example('prepared'),
      s = server(f.state, { data: { action: 'committed' }, error: null })
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result.status).toBe('reconciliation_required')
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it('retains uncertainty when the follow-up read fails instead of repeating a write', async () => {
    const f = example(),
      s = server(null, new Error('lost response'))
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result).toEqual({ status: 'reconciliation_required', state: null, refusal: null })
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it('does no RPC for a malformed identity or a changed client body hash', async () => {
    const f = example(),
      s = server(f.state)
    await expect(
      s.writer.commit(
        { ...f.identity, replyId: undefined },
        storedPreparation(f.state).prepared_hash,
      ),
    ).rejects.toThrow()
    await expect(s.writer.admit({ ...f.bound, inputHash: '0'.repeat(64) })).rejects.toThrow()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it.each([
    'saved',
    'admitted_quantity_reply',
  ] as const)('admission replay preserves the exact original intent for %s', async (name) => {
    const f = example(name),
      s = server(f.state, new Error('uncertain admission'))
    expect((await s.writer.admit(f.bound)).status).toBe('observed')
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it('does not promote a different sealed preparation to this operation', async () => {
    const f = example('prepared'),
      s = server(f.state)
    const changed = structuredClone(storedPreparation(f.state).preparation)
    changed.meal.items[0].name = 'another food'
    const result = await s.writer.prepare(f.identity, changed)
    expect(result.status).toBe('reconciliation_required')
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it.each([
    'stale_epoch',
    'input_conflict',
    'ineligible',
    'reply_conflict',
    'event_conflict',
    'absent',
  ])('a %s read never proves a commit', async (action) => {
    const f = example(),
      s = server({ action }, { data: { action: 'committed' }, error: null })
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result).toEqual({ status: 'reconciliation_required', state: { action }, refusal: null })
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it('retains a closed SQL refusal without treating it as saved food', async () => {
    const f = example('prepared'),
      s = server(f.state, { data: { action: 'source_conflict' }, error: null })
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result.status).toBe('reconciliation_required')
    if (result.status !== 'reconciliation_required') throw new Error('Expected reconciliation')
    expect(result.refusal).toBe('source_conflict')
    expect(result.state).toEqual(f.state)
  })
  it.each([
    { data: { action: 'source_conflict', private: 'not public' }, error: null },
    { data: { action: 'invented' }, error: null },
    { data: null, error: { message: 'private credential must not escape' } },
    null,
  ])('discarded mutation envelopes never replace the actual read proof %#', async (envelope) => {
    const f = example(),
      s = server(f.state, envelope)
    const result = await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)
    expect(result).toEqual({ status: 'observed', state: f.state })
    expect(JSON.stringify(result)).not.toContain('credential')
  })
  it('does not invoke getters in a damaged mutation envelope', async () => {
    const f = example(),
      getter = vi.fn(() => {
        throw new Error('must not execute')
      })
    const envelope = Object.defineProperty({ error: null }, 'data', {
      enumerable: true,
      get: getter,
    })
    const s = server(f.state, envelope)
    expect(
      (await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)).status,
    ).toBe('observed')
    expect(getter).not.toHaveBeenCalled()
  })
  it('pins both SDK callbacks before the first await', async () => {
    const f = example()
    const rpc = vi.fn(async (name: string) => {
      if (name === 'commit_conversation_meal_continuation') {
        client.rpc = vi.fn(() => {
          throw new Error('changed method')
        })
        return { data: null, error: null }
      }
      return { data: f.state, error: null }
    })
    const client = { rpc },
      writer = createSupabaseConversationMealContinuationWriter(client as unknown as ServiceClient)
    expect((await writer.commit(f.identity, storedPreparation(f.state).prepared_hash)).status).toBe(
      'observed',
    )
    expect(rpc).toHaveBeenCalledTimes(2)
    expect(client.rpc).not.toHaveBeenCalled()
  })
  it('does not retag the original owner after a request starts', async () => {
    const f = example(),
      original = structuredClone(f.identity)
    const rpc = vi.fn(async (name: string) => {
      if (name === 'commit_conversation_meal_continuation') {
        f.identity.ownerId = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
        f.identity.replyId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
      }
      return { data: name === 'read_conversation_meal_continuation' ? f.state : {}, error: null }
    })
    const writer = createSupabaseConversationMealContinuationWriter({
      rpc,
    } as unknown as ServiceClient)
    expect((await writer.commit(f.identity, storedPreparation(f.state).prepared_hash)).status).toBe(
      'observed',
    )
    expect(rpc).toHaveBeenNthCalledWith(2, 'read_conversation_meal_continuation', {
      p_user_id: original.ownerId,
      p_parent_command_id: original.parentCommandId,
      p_parent_input_hash: original.parentInputHash,
      p_expected_epoch: original.epoch,
      p_reply_id: original.replyId,
      p_reply_input_hash: original.replyInputHash,
    })
  })
  it('keeps historical SQL hashes opaque while binding the requested prepared hash', async () => {
    const f = example(),
      s = server(f.state)
    const result = await s.writer.commit(f.identity, 'f'.repeat(64))
    expect(result.status).toBe('reconciliation_required')
    expect(s.rpc).toHaveBeenCalledTimes(2)
  })
  it.each([
    '',
    'f'.repeat(63),
    'F'.repeat(64),
    'z'.repeat(64),
  ])('rejects malformed prepared hash before a writer: %s', async (hash) => {
    const f = example(),
      s = server(f.state)
    await expect(s.writer.commit(f.identity, hash)).rejects.toThrow()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it('rejects malformed/unbound preparation before any RPC', async () => {
    const f = example(),
      s = server(f.state),
      p = storedPreparation(f.state).preparation
    await expect(s.writer.prepare(f.identity, { ...p, private_extra: true })).rejects.toThrow()
    await expect(
      s.writer.prepare(f.identity, { ...p, input_hash: 'f'.repeat(64) }),
    ).rejects.toThrow()
    await expect(
      s.writer.prepare(f.identity, {
        ...p,
        parent_ref: { ...p.parent_ref, command_id: f.identity.replyId },
      }),
    ).rejects.toThrow()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it('rejects custom array prototype hooks before binding admission', async () => {
    const f = example(),
      s = server(f.state),
      hook = vi.fn(() => [])
    const raw = structuredClone(f.bound),
      list: unknown[] = []
    Object.setPrototypeOf(list, { toJSON: hook })
    Object.assign(raw, { unsafe: list })
    await expect(s.writer.admit(raw)).rejects.toThrow()
    expect(hook).not.toHaveBeenCalled()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it('a foreign owner read is discarded instead of exposing health state', async () => {
    const f = example(),
      wrong = structuredClone(f.state)
    wrong.parent.binding.owner_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
    const s = server(wrong)
    expect(await s.writer.commit(f.identity, storedPreparation(f.state).prepared_hash)).toEqual({
      status: 'reconciliation_required',
      state: null,
      refusal: null,
    })
  })
  it('separate reconciliation is exactly one read with no new mutation', async () => {
    const f = example(),
      s = server(f.state)
    expect(await s.writer.read(f.identity)).toEqual(f.state)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('read_conversation_meal_continuation', expect.any(Object))
  })
  it('preserves actual closed rate_limited while making one write and one read only', async () => {
    const f = example('admitted_quantity_reply'),
      s = server({ action: 'reply_conflict' }, { data: { action: 'rate_limited' }, error: null })
    expect(await s.writer.admit(f.bound)).toEqual({
      status: 'reconciliation_required',
      state: { action: 'reply_conflict' },
      refusal: 'rate_limited',
    })
    expect(s.rpc.mock.calls.map(([name]) => name)).toEqual([
      'admit_conversation_meal_reply',
      'read_conversation_meal_continuation',
    ])
  })
})
