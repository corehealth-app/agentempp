import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  editAuthId,
  editBinding,
  editInput,
  editOperationId,
  editReadState,
  editReceipt,
  writerBinding,
} from './__fixtures__/conversation-meal-edit'
import {
  bindConversationMealEdit,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'
import { createConversationMealEditPublicService } from './conversation-meal-edit-public-service'

const auth = {
  ...candidateAuth,
  authUserId: editAuthId,
  identity: { ...candidateAuth.identity, id: editAuthId },
  patient: { ...candidateAuth.patient, authUserId: editAuthId },
}
const original = () => {
  const b = editBinding()
  return { commandId: b.commandId, inputHash: b.inputHash, epoch: b.epoch }
}
function setup() {
  const op = bindConversationMealEdit({
    binding: editBinding(),
    operationId: editOperationId,
    input: editInput(),
  })
  const receipt = editReceipt(op.inputHash)
  const state = parseConversationMealEditState(editReadState(), editBinding())
  const store = {
    readState: vi.fn().mockResolvedValue(state),
    readOperation: vi
      .fn()
      .mockResolvedValue({ action: 'available', binding: writerBinding(), receipt }),
    save: vi.fn(),
    undoSave: vi.fn(),
    undoRegistration: vi.fn(),
  }
  const execute = vi.fn().mockResolvedValue({
    status: 'saved',
    binding: writerBinding(),
    operationId: op.operationId,
    inputHash: op.inputHash,
    receipt,
  })
  const service = createConversationMealEditPublicService({} as ServiceClient, {
    store,
    writer: { execute },
  })
  return { op, receipt, state, store, execute, service }
}
describe('public factual command edit service without implicit effects', () => {
  it('reads a group once and projects its actual binding and private version', async () => {
    const f = setup(),
      value = await f.service.readGroup(auth, original())
    expect(value).toMatchObject({
      schema: 'conversation.meal-group.v1',
      owner_id: auth.userId,
      current: { items: [{ id: f.state.currentState?.items[0].id }] },
    })
    expect(f.store.readState).toHaveBeenCalledTimes(1)
    expect(f.store.readState).toHaveBeenCalledWith(editBinding())
    expect(f.store.readOperation).not.toHaveBeenCalled()
    expect(f.execute).not.toHaveBeenCalled()
  })
  it('returns a saved ACK even if every potential follow-up read would fail', async () => {
    const f = setup()
    f.store.readState.mockRejectedValue(new Error('GET failed'))
    f.store.readOperation.mockRejectedValue(new Error('GET failed'))
    const result = await f.service.execute(
      auth,
      original(),
      editOperationId,
      editInput(),
      'public-edit-request',
    )
    expect(result).toMatchObject({ status: 'saved', receipt: { input_hash: f.op.inputHash } })
    expect(result.receipt).not.toHaveProperty('snapshot')
    expect(f.execute).toHaveBeenCalledTimes(1)
    expect(f.execute).toHaveBeenCalledWith(
      auth,
      original(),
      editOperationId,
      f.op.input,
      'public-edit-request',
    )
    expect(f.store.readOperation).not.toHaveBeenCalled()
    expect(f.store.readState).not.toHaveBeenCalled()
  })
  it('reconciles a winner through exactly one operation read, never the writer or a group read', async () => {
    const f = setup(),
      result = await f.service.reconcile(auth, original(), editOperationId, editInput())
    expect(result).toMatchObject({ schema: 'conversation.meal-edit-result.v1', status: 'saved' })
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
    expect(f.store.readOperation).toHaveBeenCalledWith({
      binding: editBinding(),
      operationId: editOperationId,
      input: f.op.input,
    })
    expect(f.store.readState).not.toHaveBeenCalled()
    expect(f.execute).not.toHaveBeenCalled()
    for (const method of [f.store.save, f.store.undoSave, f.store.undoRegistration])
      expect(method).not.toHaveBeenCalled()
  })
  it('proves the actual command binding after an absent operation, never fabricates one from headers', async () => {
    const f = setup()
    f.store.readOperation.mockResolvedValue({ action: 'absent' })
    expect(await f.service.reconcile(auth, original(), editOperationId, editInput())).toEqual({
      schema: 'conversation.meal-edit-state.v1',
      status: 'absent',
      owner_id: auth.userId,
      command_id: original().commandId,
      input_hash: original().inputHash,
      epoch: original().epoch,
      operation_id: editOperationId,
      operation_input_hash: f.op.inputHash,
    })
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
    expect(f.store.readState).toHaveBeenCalledTimes(1)
    expect(f.execute).not.toHaveBeenCalled()
  })
  it('does not cache an absent reconciliation over a later committed winner with the same input', async () => {
    const f = setup()
    f.store.readOperation.mockResolvedValueOnce({ action: 'absent' })
    expect(await f.service.reconcile(auth, original(), editOperationId, editInput())).toMatchObject(
      { status: 'absent' },
    )
    expect(await f.service.reconcile(auth, original(), editOperationId, editInput())).toMatchObject(
      { status: 'saved', receipt: { operation_id: editOperationId, input_hash: f.op.inputHash } },
    )
    expect(f.store.readOperation).toHaveBeenCalledTimes(2)
    expect(f.store.readState).toHaveBeenCalledTimes(1)
    expect(f.execute).not.toHaveBeenCalled()
  })
  it.each([
    'stale_epoch',
    'input_conflict',
    'event_conflict',
  ])('preserves read refusal %s without fallback reads or a write', async (action) => {
    const f = setup()
    f.store.readOperation.mockResolvedValue({ action })
    await expect(
      f.service.reconcile(auth, original(), editOperationId, editInput()),
    ).rejects.toMatchObject({ status: 409, code: `conversation_meal_edit_${action}` })
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
    expect(f.store.readState).not.toHaveBeenCalled()
    expect(f.execute).not.toHaveBeenCalled()
  })
  it('does not claim operation absence after the command epoch changed', async () => {
    const f = setup()
    f.store.readOperation.mockResolvedValue({ action: 'absent' })
    f.store.readState.mockResolvedValue({
      ...f.state,
      binding: { ...f.state.binding, epoch: editOperationId },
    })
    await expect(
      f.service.reconcile(auth, original(), editOperationId, editInput()),
    ).rejects.toMatchObject({ status: 503 })
  })
  it('requires original operation input and rejects changed bodies instead of recovering another intent', async () => {
    const f = setup()
    await expect(
      f.service.reconcile(auth, original(), editOperationId, {
        ...editInput(),
        items: [{ food_name: 'outro', quantity_g: 100 }],
      }),
    ).rejects.toMatchObject({ status: 503 })
    expect(f.execute).not.toHaveBeenCalled()
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
  })
  it('detaches original identity and input before the first await', async () => {
    const f = setup(),
      identity = original(),
      input = editInput()
    let resolve: (v: unknown) => void = () => {}
    f.store.readOperation.mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    const promise = f.service.reconcile(auth, identity, editOperationId, input)
    identity.epoch = editOperationId
    input.items[0].quantity_g = 999
    expect(f.store.readOperation.mock.calls[0][0]).toEqual({
      binding: editBinding(),
      operationId: editOperationId,
      input: f.op.input,
    })
    resolve({ action: 'available', binding: writerBinding(), receipt: f.receipt })
    expect(await promise).toMatchObject({ status: 'saved' })
  })
  it.each([
    { extra_authority: true },
    { items: [] },
    { expected_revision: -1 },
  ])('rejects malformed closed edit input before I/O', async (extra) => {
    const f = setup()
    await expect(
      f.service.reconcile(auth, original(), editOperationId, { ...editInput(), ...extra }),
    ).rejects.toMatchObject({ status: 422 })
    expect(f.store.readOperation).not.toHaveBeenCalled()
    expect(f.execute).not.toHaveBeenCalled()
  })
})
