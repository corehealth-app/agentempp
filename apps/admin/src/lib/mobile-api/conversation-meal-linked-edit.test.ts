import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  editAuthId,
  editOperationId,
  editReadState,
  editReceipt,
} from './__fixtures__/conversation-meal-edit'
import actual from './__fixtures__/conversation-meal-linked-effect-sdk.json'
import { privateConfirmedMealVersion } from './confirmed-meal-read'
import {
  bindConversationMealEdit,
  parseConversationMealEditServerBinding,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'
import {
  projectConversationMealEditResult,
  projectConversationMealGroup,
} from './conversation-meal-edit-public'
import { createConversationMealEditService } from './conversation-meal-edit-service'
import { createSupabaseConversationMealEditStore } from './conversation-meal-edit-store'

// The binding and original effect are exact actual local SDK output. The C11
// rows below are synthetic unit context, not a claimed actual SQL response.
function linked() {
  const wire = editReadState(),
    child = actual.childBinding,
    effect = actual.receipt
  const context = {
    ...wire.current_state.context,
    id: child.owner_id,
    status: 'active' as const,
    timezone: effect.timezone,
    updated_at: effect.consumed_at,
  }
  const snapshot = {
    ...wire.current_state.snapshot,
    user_id: child.owner_id,
    date: effect.local_date,
    updated_at: effect.consumed_at,
  }
  const rows = wire.current_state.items.map((row) => ({
    ...row,
    id: effect.log_ids[0],
    user_id: child.owner_id,
    raw_provider_message_id: effect.provider_key,
    consumed_at: effect.consumed_at,
    meal_type: effect.meal_type as 'almoco',
  }))
  return {
    binding: {
      ownerId: child.owner_id,
      commandId: child.command_id,
      inputHash: child.input_hash,
      epoch: child.epoch,
    },
    auth: {
      ...candidateAuth,
      userId: child.owner_id,
      authUserId: editAuthId,
      identity: { ...candidateAuth.identity, id: editAuthId },
      patient: { ...candidateAuth.patient, id: child.owner_id, authUserId: editAuthId },
    },
    wire: {
      ...wire,
      command: structuredClone(child),
      original_receipt: structuredClone(effect),
      current_state: { context, snapshot, items: rows },
      observed_at: '2026-11-04T18:16:00.000000Z',
      registration_undo_expires_at: '2026-11-04T18:20:29.256011Z',
    },
  }
}
describe('actual clarification-owned meal edits', () => {
  it('keeps the actual child protocol and distinct registration ID instead of relabelling it as a report', () => {
    const f = linked()
    expect(actual.receipt.registration_id).not.toBe(actual.childBinding.command_id)
    const state = parseConversationMealEditState(f.wire, f.binding)
    expect(state.binding).toEqual(actual.childBinding)
    expect(state.originalReceipt).toEqual(actual.receipt)
    expect(state.currentState).toEqual(f.wire.current_state)
    expect(parseConversationMealEditServerBinding(actual.childBinding, f.binding)).toEqual(
      actual.childBinding,
    )
  })
  it('projects an explicitly versioned linked group with current facts and finite actions', () => {
    const f = linked()
    const state = parseConversationMealEditState(f.wire, f.binding)
    const group = projectConversationMealGroup(f.auth, f.binding, state)
    expect(group.schema).toBe('conversation.meal-group.v2')
    expect(group.original_receipt).toEqual(actual.receipt)
    expect(group.actions).toEqual({
      save: { allowed: true },
      undo_registration: { allowed: true },
      undo_save: { allowed: false, reason: 'no_save_to_undo' },
    })
    expect(group.current?.expected_version).toBe(privateConfirmedMealVersion(f.wire.current_state))
    expect(JSON.stringify(group)).not.toContain('auth_user_id')
    expect(JSON.stringify(group)).not.toContain('daily_balance')
    expect(f.wire.command.command_protocol).toBe('conversation.clarification.v1')
  })
  it('reads a linked current group through exactly the existing generic SQL RPC', async () => {
    const f = linked(),
      calls: string[] = []
    const db = {
      rpc: async (name: string) => {
        calls.push(name)
        return { data: f.wire, error: null }
      },
    } as unknown as ServiceClient
    const read = await createSupabaseConversationMealEditStore(db).readState(f.binding)
    expect(read).toMatchObject({
      action: 'available',
      binding: actual.childBinding,
      originalReceipt: actual.receipt,
    })
    expect(calls).toEqual(['read_conversation_meal_edit_state'])
  })
  it.each([
    [
      'wrong parent provider',
      (w: ReturnType<typeof linked>['wire']) => {
        w.original_receipt.parent_command_id = 'c3c70000-0000-4000-8000-000000000099'
      },
    ],
    [
      'parent retagged as child',
      (w: ReturnType<typeof linked>['wire']) => {
        w.original_receipt.parent_command_id = w.command.command_id
        w.original_receipt.provider_key = `conversation.clarification/${w.command.owner_id}/${w.command.command_id}`
      },
    ],
    [
      'wrong receipt epoch',
      (w: ReturnType<typeof linked>['wire']) => {
        w.original_receipt.epoch = 'c3c70000-0000-4000-8000-000000000099'
      },
    ],
    [
      'old report receipt protocol',
      (w: ReturnType<typeof linked>['wire']) => {
        w.original_receipt.schema = 'conversation.meal-effect.v1'
      },
    ],
    [
      'provider copied to child id',
      (w: ReturnType<typeof linked>['wire']) => {
        w.current_state.items[0].raw_provider_message_id = `conversation.meal/${w.command.owner_id}/${w.command.command_id}`
      },
    ],
    [
      'different linked group',
      (w: ReturnType<typeof linked>['wire']) => {
        w.current_state.items[0].raw_provider_message_id =
          'conversation.clarification/c3c70000-0000-4000-8000-000000000001/c3c70000-0000-4000-8000-000000000099'
      },
    ],
    [
      'effect before actual admission',
      (w: ReturnType<typeof linked>['wire']) => {
        w.original_receipt.consumed_at = '2026-11-04T18:15:27.997472Z'
      },
    ],
    [
      'wrong original undo window',
      (w: ReturnType<typeof linked>['wire']) => {
        w.registration_undo_expires_at = '2026-11-04T18:25:29.256011Z'
      },
    ],
  ] as const)('rejects %s', (_, corrupt) => {
    const f = linked()
    corrupt(f.wire)
    expect(() => parseConversationMealEditState(f.wire, f.binding)).toThrow()
  })
  it('projects a saved operation bound to the child, preserving generic edit identity and original hash', () => {
    const f = linked()
    const input = {
      schema: 'conversation.meal-edit.v1',
      kind: 'save',
      expected_revision: 0,
      expected_version: privateConfirmedMealVersion(f.wire.current_state),
      record_id: actual.receipt.log_ids[0],
      items: [{ food_name: 'Arroz cozido', quantity_g: 170 }],
    }
    const operation = bindConversationMealEdit({
      binding: f.binding,
      operationId: editOperationId,
      input,
    })
    const receipt = {
      ...editReceipt(operation.inputHash),
      owner_id: f.binding.ownerId,
      command_id: f.binding.commandId,
      removed_item_ids: [actual.receipt.log_ids[0]],
      applied_at: '2026-11-04T18:16:00.000000Z',
      undo_expires_at: '2026-11-04T18:21:00.000000Z',
    }
    const result = projectConversationMealEditResult(f.auth, operation, {
      status: 'saved',
      binding: actual.childBinding,
      operationId: editOperationId,
      inputHash: operation.inputHash,
      receipt,
    })
    expect(result.command_id).toBe(actual.childBinding.command_id)
    expect(result.input_hash).toBe(actual.childBinding.input_hash)
    expect(result.receipt.operation_id).toBe(editOperationId)
    expect(result.receipt.input_hash).toBe(operation.inputHash)
    expect(result.receipt.input_hash).not.toBe(result.input_hash)
  })
  it('passes the qualified original provider through the real service/store and reconciles a lost Save response without a second write', async () => {
    const f = linked(),
      state = f.wire.current_state
    const input = {
      schema: 'conversation.meal-edit.v1',
      kind: 'save',
      expected_revision: 0,
      expected_version: privateConfirmedMealVersion(state),
      record_id: actual.receipt.log_ids[0],
      items: [{ food_name: state.items[0].food_name, quantity_g: 170 }],
    }
    const operation = bindConversationMealEdit({
      binding: f.binding,
      operationId: editOperationId,
      input,
    })
    const effect = {
      ...editReceipt(operation.inputHash),
      owner_id: f.binding.ownerId,
      command_id: f.binding.commandId,
      removed_item_ids: [actual.receipt.log_ids[0]],
      snapshot: {
        ...editReceipt(operation.inputHash).snapshot,
        id: state.snapshot.id,
        date: actual.receipt.local_date,
      },
    }
    let committed = false
    const calls: { name: string; args: Record<string, unknown> }[] = []
    const db = {
      rpc: async (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args })
        if (name === 'read_conversation_meal_edit_state') return { data: f.wire, error: null }
        if (name === 'read_conversation_meal_edit_operation')
          return {
            data: committed
              ? { action: 'available', command: actual.childBinding, receipt: effect }
              : { action: 'absent' },
            error: null,
          }
        if (name === 'commit_conversation_meal_item_edit') {
          committed = true
          throw new Error('Response lost after controlled commit')
        }
        throw new Error('Unexpected writer or lookup')
      },
    } as unknown as ServiceClient
    const service = createConversationMealEditService(db, {
      now: () => new Date(f.wire.observed_at),
    })
    const original = {
      commandId: f.binding.commandId,
      inputHash: f.binding.inputHash,
      epoch: f.binding.epoch,
    }
    expect(
      await service.execute(f.auth, original, editOperationId, input, 'linked-edit-test'),
    ).toMatchObject({ status: 'saved', binding: actual.childBinding, receipt: effect })
    expect(calls.map((x) => x.name)).toEqual([
      'read_conversation_meal_edit_operation',
      'read_conversation_meal_edit_state',
      'commit_conversation_meal_item_edit',
      'read_conversation_meal_edit_operation',
    ])
    const sent = calls[2].args
    expect(sent.p_expected_state).toEqual(state)
    expect(sent.p_expected_state).not.toHaveProperty('originalReceipt')
    expect(sent).not.toHaveProperty('originalReceipt')
    expect(sent.p_nutrition_mode).toBe('quantity_only')
    expect(actual.receipt).toEqual(f.wire.original_receipt)
    expect(
      await service.execute(f.auth, original, editOperationId, input, 'linked-edit-replay'),
    ).toMatchObject({ status: 'saved', binding: actual.childBinding, receipt: effect })
    expect(calls.filter((x) => x.name === 'commit_conversation_meal_item_edit')).toHaveLength(1)
  })
  it('validates the actual child origin before any direct store write', async () => {
    const f = linked(),
      rpc = vi.fn()
    const db = { rpc } as unknown as ServiceClient
    const originalReceipt = {
      ...actual.receipt,
      provider_key: `conversation.clarification/${f.binding.ownerId}/${f.binding.commandId}`,
    }
    await expect(
      createSupabaseConversationMealEditStore(db).save({
        binding: f.binding,
        operationId: editOperationId,
        input: {
          schema: 'conversation.meal-edit.v1',
          kind: 'save',
          expected_revision: 0,
          expected_version: privateConfirmedMealVersion(f.wire.current_state),
          record_id: actual.receipt.log_ids[0],
          items: [{ food_name: 'Arroz cozido', quantity_g: 170 }],
        },
        expectedState: f.wire.current_state,
        originalReceipt,
        calculatedItems: [],
        nutritionMode: 'quantity_only',
        quantityChange: { quantity_g: 170 },
        requestId: 'linked-invalid-origin',
      }),
    ).rejects.toThrow()
    expect(rpc).not.toHaveBeenCalled()
  })
  it('keeps the same detached child origin when its caller mutates it during the SQL await', async () => {
    const f = linked()
    const request = {
      binding: f.binding,
      operationId: editOperationId,
      input: {
        schema: 'conversation.meal-edit.v1',
        kind: 'save',
        expected_revision: 0,
        expected_version: privateConfirmedMealVersion(f.wire.current_state),
        record_id: actual.receipt.log_ids[0],
        items: [{ food_name: 'Arroz cozido', quantity_g: 170 }],
      },
      expectedState: f.wire.current_state,
      originalReceipt: structuredClone(actual.receipt),
      calculatedItems: [],
      nutritionMode: 'quantity_only' as const,
      quantityChange: { quantity_g: 170 },
      requestId: 'linked-origin-detach',
    }
    const op = bindConversationMealEdit(request)
    const effect = {
      ...editReceipt(op.inputHash),
      owner_id: f.binding.ownerId,
      command_id: f.binding.commandId,
      removed_item_ids: [actual.receipt.log_ids[0]],
    }
    let release: (value: unknown) => void = () => {
      throw new Error('Not initialized')
    }
    let entered: () => void = () => {
      throw new Error('Not initialized')
    }
    const pending = new Promise<unknown>((resolve) => {
      release = resolve
    })
    const started = new Promise<void>((resolve) => {
      entered = resolve
    })
    const rpc = vi.fn(() => {
      entered()
      return pending
    })
    const result = createSupabaseConversationMealEditStore({
      rpc,
    } as unknown as ServiceClient).save(request)
    await started
    request.originalReceipt.provider_key = 'changed-after-call'
    release({
      data: { action: 'committed', command: actual.childBinding, receipt: effect },
      error: null,
    })
    await expect(result).resolves.toMatchObject({
      action: 'committed',
      binding: actual.childBinding,
      receipt: effect,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
