import { fixture } from '../testing/confirmed-meal-fixtures'
import { writerBinding, writerCommand, writerReceipt } from './conversation-meal-writer'

export const editOperationId = '10000000-0000-4000-8000-000000000080'
export const editNewId = '10000000-0000-4000-8000-000000000081'
export const editTargetId = '10000000-0000-4000-8000-000000000082'
export const editAuthId = '90000000-0000-4000-8000-000000000001'
export function editBinding() {
  const b = writerBinding()
  return { ownerId: b.owner_id, commandId: b.command_id, inputHash: b.input_hash, epoch: b.epoch }
}
export function editState() {
  const rows = fixture(),
    original = writerReceipt(),
    b = editBinding()
  return {
    context: {
      id: b.ownerId,
      auth_user_id: editAuthId,
      country: 'BR',
      country_confirmed: true,
      timezone: original.timezone,
      status: 'active',
      wpp: null,
      updated_at: '2026-11-04T12:00:00.123456+00:00',
    },
    snapshot: {
      ...rows.daily_snapshots[0],
      user_id: b.ownerId,
      date: original.local_date,
      calories_target: null,
      protein_target: null,
      updated_at: '2026-11-04T12:00:00.123456+00:00',
    },
    items: [
      {
        ...rows.meal_logs[0],
        id: original.log_ids[0],
        user_id: b.ownerId,
        raw_message_id: editAuthId,
        raw_provider_message_id: original.provider_key,
        consumed_at: original.consumed_at,
        created_at: '2026-11-04T12:00:00.000004+00:00',
      },
    ],
  }
}
export function editInput() {
  return {
    schema: 'conversation.meal-edit.v1',
    kind: 'save',
    expected_revision: 0,
    expected_version: `v1:${'a'.repeat(64)}`,
    record_id: writerReceipt().log_ids[0],
    items: [{ food_name: 'Arroz cozido', quantity_g: 200, quantity_basis: 'stated' }],
  }
}
export function editReadState() {
  return {
    action: 'available',
    command: writerBinding(),
    original_receipt: writerReceipt(),
    revision: 0,
    current_state: editState(),
    lineage_compatible: true,
    last_operation: null,
    registration_undo_expires_at: '2026-11-04T12:05:00.000004+00:00',
    observed_at: '2026-11-04T12:01:00.000004+00:00',
  }
}
export function editReceipt(inputHash: string) {
  const b = editBinding(),
    s = editState().snapshot
  return {
    schema: 'conversation.meal-edit-effect.v1',
    owner_id: b.ownerId,
    command_id: b.commandId,
    operation_id: editOperationId,
    input_hash: inputHash,
    kind: 'saved',
    revision: 1,
    applied_at: '2026-11-04T12:01:00.123456+00:00',
    undo_expires_at: '2026-11-04T12:06:00.123456+00:00',
    target_operation_id: null,
    removed_item_ids: [writerReceipt().log_ids[0]],
    new_item_ids: [editNewId],
    next_record_id: editNewId,
    snapshot: {
      id: s.id,
      date: s.date,
      calories_consumed: 200,
      protein_g: 5,
      carbs_g: 40,
      fat_g: 1,
      daily_balance: null,
    },
  }
}
export { writerBinding, writerCommand, writerReceipt }
