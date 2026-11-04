import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { type PrivateConfirmedMealState, privateConfirmedMealVersion } from './confirmed-meal-read'
import { bindConversationMealEdit } from './conversation-meal-edit-contracts'
import { createConversationMealEditService } from './conversation-meal-edit-service'
import { MobileApiError } from './http'
import { auth, fixture, now, owner } from './testing/confirmed-meal-fixtures'

const commandId = 'c1110000-0000-4000-8000-000000000070'
const operationId = 'c1110000-0000-4000-8000-000000000071'
const epoch = 'c1110000-0000-4000-8000-000000000072'
const original = { commandId, inputHash: 'a'.repeat(64), epoch }
function setup() {
  const rows = fixture(),
    user = rows.users[0]
  const currentState: PrivateConfirmedMealState = {
    context: {
      id: user.id,
      auth_user_id: user.auth_user_id,
      country: user.country,
      country_confirmed: user.country_confirmed,
      timezone: user.timezone,
      status: user.status,
      wpp: user.wpp,
      updated_at: user.updated_at,
    },
    snapshot: rows.daily_snapshots[0],
    items: rows.meal_logs,
  }
  const binding = {
    owner_id: owner,
    command_id: commandId,
    input_hash: original.inputHash,
    epoch,
    command_protocol: 'conversation.command.v1',
    kind: 'meal.report',
    admitted_at: now.toISOString(),
  }
  const input = {
    schema: 'conversation.meal-edit.v1',
    kind: 'save',
    expected_revision: 0,
    expected_version: privateConfirmedMealVersion(currentState),
    record_id: currentState.items[0].id,
    items: [{ food_name: currentState.items[0].food_name, quantity_g: 170 }],
  }
  const receiptFor = (raw: unknown) => {
    const op = bindConversationMealEdit({
      binding: { ownerId: owner, ...original },
      operationId,
      input: raw,
    })
    const removed =
      op.input.kind === 'undo_registration'
        ? currentState.items.map((row) => row.id)
        : [currentState.items[0].id]
    const inserted =
      op.input.kind === 'undo_registration' ? [] : ['c1110000-0000-4000-8000-000000000074']
    return {
      schema: 'conversation.meal-edit-effect.v1',
      owner_id: owner,
      command_id: commandId,
      operation_id: operationId,
      input_hash: op.inputHash,
      kind:
        op.input.kind === 'save'
          ? 'saved'
          : op.input.kind === 'undo_save'
            ? 'save_undone'
            : 'registration_undone',
      revision: op.input.expected_revision + 1,
      applied_at: now.toISOString(),
      undo_expires_at:
        op.input.kind === 'save' ? new Date(now.getTime() + 300000).toISOString() : null,
      target_operation_id: op.input.kind === 'undo_save' ? op.input.target_operation_id : null,
      removed_item_ids: removed,
      new_item_ids: inserted,
      next_record_id: inserted[0] ?? null,
      snapshot: {
        id: currentState.snapshot.id,
        date: currentState.snapshot.date,
        calories_consumed: 210,
        protein_g: 26,
        carbs_g: 9,
        fat_g: 7.5,
        daily_balance: -1790,
      },
    }
  }
  const receipt = receiptFor(input)
  const available = {
    action: 'available',
    binding,
    revision: 0,
    currentState,
    lineageCompatible: true,
    originalReceipt: null,
    lastOperation: null,
    registrationUndoExpiresAt: new Date(now.getTime() + 300000).toISOString(),
    observedAt: now.toISOString(),
  }
  const store = {
    readState: vi.fn().mockResolvedValue(available),
    readOperation: vi.fn().mockResolvedValue({ action: 'absent' }),
    save: vi.fn().mockResolvedValue({ action: 'committed', binding, receipt }),
    undoSave: vi.fn().mockImplementation(async ({ input }: { input: unknown }) => ({
      action: 'committed',
      binding,
      receipt: receiptFor(input),
    })),
    undoRegistration: vi.fn().mockImplementation(async ({ input }: { input: unknown }) => ({
      action: 'committed',
      binding,
      receipt: receiptFor(input),
    })),
  }
  const clock = vi.fn(() => new Date(now)),
    service = createConversationMealEditService({} as ServiceClient, { store, now: clock })
  return {
    rows,
    currentState,
    binding,
    receipt,
    input,
    available,
    store,
    clock,
    service,
    run: (raw: unknown = input) =>
      service.execute(auth, original, operationId, raw, 'test-edit-request'),
  }
}
describe('private durable command Save/Undo orchestration', () => {
  it('returns an original winner before current-state lookup, clock or calculation', async () => {
    const f = setup()
    f.store.readOperation.mockResolvedValue({
      action: 'available',
      binding: f.binding,
      receipt: f.receipt,
    })
    expect(await f.run()).toMatchObject({ status: 'saved', receipt: f.receipt })
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
    for (const m of [
      f.store.readState,
      f.store.save,
      f.store.undoSave,
      f.store.undoRegistration,
      f.clock,
    ])
      expect(m).not.toHaveBeenCalled()
  })
  it('uses the actual existing C11 quantity preparer and supplies the entire exact private CAS once', async () => {
    const f = setup()
    expect(await f.run()).toMatchObject({ status: 'saved', receipt: f.receipt })
    expect(f.store.save).toHaveBeenCalledTimes(1)
    const request = f.store.save.mock.calls[0]?.[0]
    expect(request.binding).toEqual({ ownerId: owner, ...original })
    expect(request.expectedState).toEqual(f.currentState)
    expect(request.nutritionMode).toBe('quantity_only')
    expect(request.quantityChange).toEqual({ quantity_g: 170 })
    expect(request.calculatedItems).toMatchObject([{ quantity_g: 170, kcal: 110, protein_g: 6 }])
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
    expect(f.store.readState).toHaveBeenCalledTimes(1)
  })
  it.each([
    'expected_version',
    'expected_revision',
  ])('refuses stale client %s without silently substituting the fresh state', async (field) => {
    const f = setup(),
      raw = { ...f.input, [field]: field === 'expected_version' ? `v1:${'f'.repeat(64)}` : 1 }
    await expect(f.run(raw)).rejects.toMatchObject({ status: 409 })
    expect(f.store.save).not.toHaveBeenCalled()
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
  })
  it('checks actual Auth linkage even for Undo, independently of patient ownership', async () => {
    const f = setup()
    f.currentState.context.auth_user_id = 'c1110000-0000-4000-8000-000000000099'
    const raw = {
      schema: 'conversation.meal-edit.v1',
      kind: 'undo_registration',
      expected_revision: 0,
      expected_version: privateConfirmedMealVersion(f.currentState),
    }
    await expect(f.run(raw)).rejects.toMatchObject({ status: 409 })
    expect(f.store.undoRegistration).not.toHaveBeenCalled()
  })
  it('does not calculate or restore rows in JS for either Undo kind', async () => {
    for (const kind of ['undo_registration', 'undo_save']) {
      const f = setup()
      // A Save must precede Undo Save; revision zero is only registration Undo.
      const revision = kind === 'undo_save' ? 1 : 0
      f.available.revision = revision
      const raw = {
        schema: 'conversation.meal-edit.v1',
        kind,
        expected_revision: revision,
        expected_version: f.input.expected_version,
        ...(kind === 'undo_save'
          ? { target_operation_id: 'c1110000-0000-4000-8000-000000000073' }
          : {}),
      }
      expect(await f.run(raw)).toMatchObject({ status: 'saved' })
      const writer = kind === 'undo_save' ? f.store.undoSave : f.store.undoRegistration
      expect(writer).toHaveBeenCalledTimes(1)
      expect(writer.mock.calls[0]?.[0]).toMatchObject({ expectedState: f.currentState, input: raw })
      expect(writer.mock.calls[0]?.[0]).not.toHaveProperty('calculatedItems')
      expect(f.store.save).not.toHaveBeenCalled()
    }
  })
  it('recovers a lost write outcome by one receipt read, never by another write', async () => {
    const f = setup()
    f.store.save.mockRejectedValue(new Error('lost response after commit'))
    f.store.readOperation
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce({ action: 'available', binding: f.binding, receipt: f.receipt })
    expect(await f.run()).toMatchObject({ status: 'saved', receipt: f.receipt })
    expect(f.store.save).toHaveBeenCalledTimes(1)
    expect(f.store.readOperation).toHaveBeenCalledTimes(2)
    expect(f.store.readState).toHaveBeenCalledTimes(1)
  })
  it('keeps an unknown write in reconciliation without claiming it failed to save', async () => {
    const f = setup()
    f.store.save.mockRejectedValue(new Error('unknown outcome'))
    await expect(f.run()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_edit_reconciliation_required',
    })
    expect(f.store.save).toHaveBeenCalledTimes(1)
    expect(f.store.readOperation).toHaveBeenCalledTimes(2)
  })
  it('preserves a known SQL refusal without another operation read or retry', async () => {
    const f = setup()
    f.store.save.mockResolvedValue({ action: 'day_closed' })
    await expect(f.run()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_edit_day_closed',
    })
    expect(f.store.save).toHaveBeenCalledTimes(1)
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
  })
  it('does not publish a saved claim for a receipt with a different operation input hash', async () => {
    const f = setup()
    f.store.save.mockResolvedValue({
      action: 'committed',
      binding: f.binding,
      receipt: { ...f.receipt, input_hash: 'f'.repeat(64) },
    })
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.store.save).toHaveBeenCalledTimes(1)
    expect(f.store.readOperation).toHaveBeenCalledTimes(1)
  })
  it('does not write when the coherent SQL state belongs to a newer epoch', async () => {
    const f = setup()
    f.available.binding = { ...f.binding, epoch: 'c1110000-0000-4000-8000-000000000099' }
    await expect(f.run()).rejects.toMatchObject({ status: 409 })
    expect(f.store.save).not.toHaveBeenCalled()
  })
  it('lets a concurrent original winner recover a preparation error; otherwise preserves the error', async () => {
    for (const winner of [true, false]) {
      const f = setup(),
        failure = new MobileApiError(422, 'MEAL_NUTRITION_UNRESOLVED', 'Review item')
      const prepare = vi.fn().mockRejectedValue(failure)
      const service = createConversationMealEditService({} as ServiceClient, {
        store: f.store,
        now: f.clock,
        prepare,
      })
      f.store.readOperation
        .mockResolvedValueOnce({ action: 'absent' })
        .mockResolvedValueOnce(
          winner
            ? { action: 'available', binding: f.binding, receipt: f.receipt }
            : { action: 'absent' },
        )
      const run = service.execute(auth, original, operationId, f.input, 'test-edit-request')
      if (winner) expect(await run).toMatchObject({ status: 'saved' })
      else await expect(run).rejects.toBe(failure)
      expect(prepare).toHaveBeenCalledTimes(1)
      expect(f.store.save).not.toHaveBeenCalled()
      expect(f.store.readOperation).toHaveBeenCalledTimes(2)
    }
  })
  it('rejects client-supplied authority or invalid fields before the first operation read', async () => {
    for (const extra of [
      { owner_id: owner },
      { expectedState: {} },
      { calories: 0 },
      { expected_revision: -1 },
    ]) {
      const f = setup()
      await expect(f.run({ ...f.input, ...extra })).rejects.toMatchObject({ status: 422 })
      expect(f.store.readOperation).not.toHaveBeenCalled()
      expect(f.store.readState).not.toHaveBeenCalled()
    }
  })
})
