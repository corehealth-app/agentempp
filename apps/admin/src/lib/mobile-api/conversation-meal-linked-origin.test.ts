import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { editReadState } from './__fixtures__/conversation-meal-edit'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationMealLinkedOriginService } from './conversation-meal-linked-origin'

function setup() {
  const f = replyFixture('saved'),
    fulfillment = f.state.fulfillment!,
    wire = {
      ...editReadState(),
      command: structuredClone(fulfillment.child_binding),
      original_receipt: structuredClone(fulfillment.receipt),
      current_state: null,
      lineage_compatible: false,
      observed_at: f.state.observed_at,
      registration_undo_expires_at:
        new Date(Date.parse(fulfillment.receipt.consumed_at) + 300_000).toISOString().slice(0, 19) +
        fulfillment.receipt.consumed_at.slice(19),
    },
    rpc = vi.fn(async (name: string) => ({
      data: name === 'read_conversation_meal_edit_state' ? wire : f.state,
      error: null,
    })),
    from = vi.fn(() => {
      throw new Error('No table access or write')
    }),
    capture = vi.fn().mockResolvedValue(f.profile),
    verifyAccessToken = vi.fn().mockResolvedValue(f.auth.identity),
    loadPatient = vi.fn().mockResolvedValue(f.auth.patient),
    db = { rpc, from } as unknown as ServiceClient,
    service = createConversationMealLinkedOriginService(db, {
      auth: { verifyAccessToken, loadPatient, isAdmin: vi.fn().mockResolvedValue(false) },
      clinical: { capture },
    }),
    run = () => service.read(f.auth, f.identity.replyId, f.identity.epoch)
  return { ...f, wire, rpc, from, capture, verifyAccessToken, loadPatient, run }
}

describe('owned cold linked meal origin lookup', () => {
  it('recovers genuine parent and child admissions and original receipt with only existing readonly RPCs', async () => {
    const f = setup(),
      result = await f.run()
    expect(result).toEqual({
      schema: 'conversation.meal-linked-origin.v1',
      auth_user_id: f.auth.authUserId,
      owner_id: f.identity.ownerId,
      epoch: f.identity.epoch,
      observed_at: f.state.observed_at,
      parent_binding: f.state.fulfillment!.parent_binding,
      child_binding: f.state.fulfillment!.child_binding,
      parent_decision_hash: f.state.parent.decision.decision_hash,
      receipt: f.state.fulfillment!.receipt,
    })
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.receipt)).toBe(true)
    expect(f.rpc.mock.calls.map((x) => x[0])).toEqual([
      'read_conversation_meal_edit_state',
      'read_conversation_meal_continuation',
    ])
    expect(f.rpc).toHaveBeenNthCalledWith(1, 'read_conversation_meal_edit_state', {
      p_user_id: f.identity.ownerId,
      p_command_id: f.identity.replyId,
    })
    expect(f.rpc).toHaveBeenNthCalledWith(2, 'read_conversation_meal_continuation', {
      p_user_id: f.identity.ownerId,
      p_parent_command_id: f.identity.parentCommandId,
      p_expected_epoch: f.identity.epoch,
      p_parent_input_hash: f.identity.parentInputHash,
      p_reply_id: f.identity.replyId,
      p_reply_input_hash: f.identity.replyInputHash,
    })
    expect(f.capture).toHaveBeenCalledTimes(3)
    expect(f.from).not.toHaveBeenCalled()
    for (const field of [
      'source',
      'current_state',
      'feedback',
      'question',
      'grant',
      'answer_lease',
      'snapshot',
    ])
      expect(Object.keys(result)).not.toContain(field)
  })

  it.each([
    'absent',
    'stale_epoch',
    'event_conflict',
  ])('does not invent an origin from %s', async (action) => {
    const f = setup()
    f.rpc.mockResolvedValueOnce({ data: { action } as never, error: null })
    await expect(f.run()).rejects.toMatchObject({ status: 409 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    'owner',
    'command',
    'epoch',
    'hash',
    'protocol',
    'receipt',
    'unknown',
  ])('rejects malformed or foreign %s before reading the continuation', async (field) => {
    const f = setup()
    if (field === 'owner') f.wire.command.owner_id = f.auth.authUserId
    if (field === 'command') f.wire.command.command_id = f.identity.parentCommandId
    if (field === 'epoch') f.wire.command.epoch = f.auth.authUserId
    if (field === 'hash') f.wire.command.input_hash = '0'.repeat(64)
    if (field === 'protocol')
      Object.assign(f.wire.command, {
        command_protocol: 'conversation.command.v1',
        kind: 'meal.report',
      })
    if (field === 'receipt') f.wire.original_receipt.parent_decision_hash = '0'.repeat(64)
    if (field === 'unknown') Object.assign(f.wire, { unsafe: true })
    // A structurally valid but different parent decision is only contradicted
    // by the independent continuation. All other mutations fail in state.
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(field === 'receipt' ? 2 : 1)
  })

  it('does not return old patient facts after a mapping change between its two reads', async () => {
    const f = setup()
    f.capture.mockImplementation(async () => {
      if (f.rpc.mock.calls.length === 1)
        f.loadPatient.mockResolvedValue({ ...f.auth.patient, id: f.auth.authUserId })
      return f.profile
    })
    await expect(f.run()).rejects.toMatchObject({ status: 409 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })

  it('classifies a completely valid old epoch without treating it as current or reading its continuation', async () => {
    const f = setup(),
      oldEpoch = f.auth.authUserId
    f.wire.command.epoch = oldEpoch
    f.wire.original_receipt.epoch = oldEpoch
    await expect(f.run()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_linked_origin_stale_epoch',
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })

  it('does not publish linked facts after a final clinical epoch change', async () => {
    const f = setup()
    f.capture.mockImplementation(async () =>
      f.rpc.mock.calls.length === 2 ? { ...f.profile, epoch: f.auth.authUserId } : f.profile,
    )
    await expect(f.run()).rejects.toMatchObject({
      status: 500,
      code: 'mobile_current_clinical_invalid_response',
    })
    expect(f.rpc).toHaveBeenCalledTimes(2)
  })

  it('pins state before the asynchronous scope check instead of rereading mutable SDK output', async () => {
    const f = setup(),
      original = structuredClone(f.wire)
    f.capture.mockImplementation(async () => {
      if (f.rpc.mock.calls.length === 1) f.wire.original_receipt.parent_input_hash = 'f'.repeat(64)
      return f.profile
    })
    expect((await f.run()).receipt).toEqual(original.original_receipt)
  })

  it.each([
    'absent',
    'stale_epoch',
    'reply_conflict',
    'event_conflict',
  ])('refuses continuation %s without writes or another attempt', async (action) => {
    const f = setup()
    f.rpc.mockResolvedValueOnce({ data: f.wire, error: null })
    f.rpc.mockResolvedValueOnce({ data: { action } as never, error: null })
    await expect(f.run()).rejects.toMatchObject({ status: 409 })
    expect(f.rpc).toHaveBeenCalledTimes(2)
  })

  it.each([
    'before',
    'after',
  ] as const)('refuses a read clock outside its %s scope observations', async (side) => {
    const f = setup()
    f.wire.observed_at = side === 'before' ? '2026-11-04T13:57:32.800000Z' : '2026-11-04T14:00:00Z'
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })

  it('rejects a provider error without exposing its body', async () => {
    const f = setup()
    f.rpc.mockResolvedValueOnce({
      data: null as never,
      error: { message: 'private-sql-detail' } as never,
    })
    await expect(f.run()).rejects.toMatchObject({
      status: 503,
      message: 'Linked meal origin is unavailable',
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
})
