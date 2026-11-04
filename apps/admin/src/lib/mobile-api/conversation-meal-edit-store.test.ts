import { createHash } from 'node:crypto'
import type { Database, ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import {
  editBinding,
  editInput,
  editOperationId,
  editReadState,
  editReceipt,
  editState,
  editTargetId,
  writerBinding,
} from './__fixtures__/conversation-meal-edit'
import { bindConversationMealEdit } from './conversation-meal-edit-contracts'
import { createSupabaseConversationMealEditStore } from './conversation-meal-edit-store'

function transport(
  handler: (name: string, args: Record<string, unknown>) => unknown | Promise<unknown>,
) {
  const calls: { name: string; args: Record<string, unknown> }[] = []
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      return handler(name, args)
    },
    from() {
      throw new Error('no direct table access')
    },
  } as unknown as ServiceClient
  return { calls, client, store: createSupabaseConversationMealEditStore(client) }
}
const operation = () => ({
  binding: editBinding(),
  operationId: editOperationId,
  input: editInput(),
})
const save = () => ({
  ...operation(),
  expectedState: editState(),
  calculatedItems: [],
  nutritionMode: 'recalculated' as const,
  quantityChange: null,
  requestId: 'edit-test',
})

describe('one-shot private command edit SDK store', () => {
  it('accepts a SQL decimal-hashed receipt for an exponent-valued original intent without retry', async () => {
    const request = {
      ...save(),
      input: { ...editInput(), items: [{ food_name: 'rice', quantity_g: 100, user_kcal: 1e-7 }] },
    }
    const reference = `{"expected_revision":0,"expected_version":${JSON.stringify(request.input.expected_version)},"items":[{"food_name":"rice","quantity_g":100,"user_kcal":0.0000001}],"kind":"save","record_id":${JSON.stringify(request.input.record_id)},"schema":"conversation.meal-edit.v1"}`
    const inputHash = createHash('sha256').update(reference).digest('hex')
    const t = transport(() => ({
      data: { action: 'committed', command: writerBinding(), receipt: editReceipt(inputHash) },
      error: null,
    }))
    expect(await t.store.save(request)).toMatchObject({
      action: 'committed',
      receipt: { input_hash: inputHash },
    })
    expect(t.calls).toHaveLength(1)
    expect(t.calls[0].args.p_input).toEqual(request.input)
  })
  it('constructs inertly and reads the actual full private state with one RPC', async () => {
    const t = transport(() => ({ data: editReadState(), error: null }))
    expect(t.calls).toEqual([])
    const value = await t.store.readState(editBinding())
    expect(value).toMatchObject({
      action: 'available',
      binding: writerBinding(),
      currentState: editState(),
    })
    expect(t.calls).toEqual([
      {
        name: 'read_conversation_meal_edit_state',
        args: { p_user_id: editBinding().ownerId, p_command_id: editBinding().commandId },
      },
    ])
  })
  it.each([
    'readOperation',
    'save',
    'undoSave',
    'undoRegistration',
  ] as const)('uses only its exact RPC for %s and returns a real bound receipt', async (method) => {
    const op = operation()
    if (method.startsWith('undo'))
      Object.assign(op, {
        input: {
          schema: 'conversation.meal-edit.v1',
          kind: method === 'undoSave' ? 'undo_save' : 'undo_registration',
          expected_revision: method === 'undoSave' ? 1 : 0,
          expected_version: `v1:${'a'.repeat(64)}`,
          ...(method === 'undoSave' ? { target_operation_id: editTargetId } : {}),
        },
      })
    const bound = bindConversationMealEdit(op),
      receipt = editReceipt(bound.inputHash)
    if (method.startsWith('undo'))
      Object.assign(receipt, {
        kind: method === 'undoSave' ? 'save_undone' : 'registration_undone',
        revision: method === 'undoSave' ? 2 : 1,
        undo_expires_at: null,
        target_operation_id: method === 'undoSave' ? editTargetId : null,
        new_item_ids: method === 'undoSave' ? receipt.new_item_ids : [],
        next_record_id: method === 'undoSave' ? receipt.next_record_id : null,
      })
    const action = method === 'readOperation' ? 'available' : 'committed'
    const t = transport(() => ({
      data: { action, command: writerBinding(), receipt },
      error: null,
    }))
    const value =
      method === 'readOperation'
        ? await t.store.readOperation(op)
        : method === 'save'
          ? await t.store.save({ ...save(), ...op })
          : await t.store[method]({ ...op, expectedState: editState(), requestId: 'edit-test' })
    expect(value).toMatchObject({ action, receipt })
    const names = {
      readOperation: 'read_conversation_meal_edit_operation',
      save: 'commit_conversation_meal_item_edit',
      undoSave: 'undo_conversation_meal_item_edit',
      undoRegistration: 'undo_conversation_meal_registration',
    }
    expect(t.calls).toHaveLength(1)
    expect(t.calls[0].name).toBe(names[method])
    expect(t.calls[0].args.p_input).toEqual(op.input)
  })
  it('detaches every request before await and captures the original SDK callback', async () => {
    let finish: (value: unknown) => void = () => {}
    const t = transport(
      () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    )
    const input = save(),
      promise = t.store.save(input)
    input.input.items[0].food_name = 'changed'
    input.expectedState.items[0].food_name = 'changed'
    input.binding.epoch = editOperationId
    Object.assign(t.client, {
      rpc: () => {
        throw new Error('changed SDK callback')
      },
    })
    expect(t.calls[0].args.p_input).toEqual(editInput())
    expect(t.calls[0].args.p_expected_state).toEqual(editState())
    finish({
      data: {
        action: 'replay',
        command: writerBinding(),
        receipt: editReceipt(bindConversationMealEdit(operation()).inputHash),
      },
      error: null,
    })
    expect(await promise).toMatchObject({ action: 'replay' })
  })
  it.each([
    'readOperation',
    'save',
    'undoRegistration',
  ] as const)('rejects other epoch in successful %s without an invented epoch/read', async (method) => {
    const t = transport(() => ({
      data: {
        action: method === 'readOperation' ? 'available' : 'replay',
        command: { ...writerBinding(), epoch: editOperationId },
        receipt: editReceipt(bindConversationMealEdit(operation()).inputHash),
      },
      error: null,
    }))
    const p =
      method === 'readOperation'
        ? t.store.readOperation(operation())
        : method === 'save'
          ? t.store.save(save())
          : t.store.undoRegistration({
              ...operation(),
              input: {
                schema: 'conversation.meal-edit.v1',
                kind: 'undo_registration',
                expected_revision: 0,
                expected_version: `v1:${'a'.repeat(64)}`,
              },
              expectedState: null,
              requestId: 'edit-test',
            })
    await expect(p).rejects.toMatchObject({ code: 'conversation_meal_edit_unavailable' })
    expect(t.calls).toHaveLength(1)
  })
  it.each([
    'throw',
    'malformed',
    'sql',
  ])('never retries or reads after ambiguous %s outcome and redacts private details', async (kind) => {
    const t = transport(() => {
      if (kind === 'throw') throw new Error('private-source-clinical')
      return kind === 'sql'
        ? { data: null, error: { code: 'XX000', message: 'private-source-clinical' } }
        : { data: { action: 'committed', receipt: {} }, error: null }
    })
    await expect(t.store.save(save())).rejects.toMatchObject({
      code: 'conversation_meal_edit_unavailable',
      status: 503,
    })
    expect(t.calls).toHaveLength(1)
  })
  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'event_conflict',
    'version_conflict',
    'day_closed',
    'undo_expired',
    'in_progress',
  ])('preserves documented write refusal %s', async (action) => {
    const t = transport(() => ({ data: { action }, error: null }))
    expect(await t.store.save(save())).toEqual({ action })
    expect(t.calls).toHaveLength(1)
  })
  it.each([
    { action: 'unknown' },
    { action: 'absent', receipt: null },
    { action: 'available' },
    null,
  ])('rejects undeclared envelopes %#', async (data) => {
    await expect(
      transport(() => ({ data, error: null })).store.readState(editBinding()),
    ).rejects.toMatchObject({ code: 'conversation_meal_edit_unavailable' })
  })
  it('rejects a fresh success for a different snapshot without treating it as an unknown retry permission', async () => {
    const receipt = editReceipt(bindConversationMealEdit(operation()).inputHash)
    receipt.snapshot.id = editTargetId
    const t = transport(() => ({
      data: { action: 'committed', command: writerBinding(), receipt },
      error: null,
    }))
    await expect(t.store.save(save())).rejects.toMatchObject({
      code: 'conversation_meal_edit_unavailable',
    })
    expect(t.calls).toHaveLength(1)
  })
  it('preserves SQL first-winner replay with null/stale ancillary preparation', async () => {
    const receipt = editReceipt(bindConversationMealEdit(operation()).inputHash)
    const t = transport(() => ({
      data: { action: 'replay', command: writerBinding(), receipt },
      error: null,
    }))
    expect(
      await t.store.save({
        ...save(),
        expectedState: null,
        calculatedItems: null,
        nutritionMode: null,
        quantityChange: null,
      }),
    ).toMatchObject({ action: 'replay', receipt })
    expect(t.calls).toHaveLength(1)
  })
  it.each([
    '55P03',
    '40001',
  ])('maps a declared SQL %s failure to a redacted conflict without another RPC', async (code) => {
    const t = transport(() => ({
      data: null,
      error: { code, message: 'private source and clinical details' },
    }))
    try {
      await t.store.save(save())
      throw new Error('unexpected success')
    } catch (error) {
      expect(error).toMatchObject({
        status: 409,
        code: `conversation_meal_edit_${code === '55P03' ? 'busy' : 'conflict'}`,
      })
      expect(String(error)).not.toContain('private source')
    }
    expect(t.calls).toHaveLength(1)
  })
  it('sends the one real SDK/PostgREST RPC request with patient ID and unmodified private CAS', async () => {
    const requests: { url: string; method: string; body: unknown }[] = []
    const client = createClient<Database>('https://synthetic.invalid', 'synthetic-never-network', {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: async (url, init) => {
          requests.push({
            url: String(url),
            method: init?.method ?? '',
            body: JSON.parse(String(init?.body)),
          })
          return new Response(
            JSON.stringify({
              action: 'committed',
              command: writerBinding(),
              receipt: editReceipt(bindConversationMealEdit(operation()).inputHash),
            }),
            { status: 200, headers: { 'Content-Type': 'application/json' } },
          )
        },
      },
    })
    const value = await createSupabaseConversationMealEditStore(client).save(save())
    expect(value.action).toBe('committed')
    expect(requests).toHaveLength(1)
    expect(requests[0].url).toBe(
      'https://synthetic.invalid/rest/v1/rpc/commit_conversation_meal_item_edit',
    )
    expect(requests[0].method).toBe('POST')
    expect(requests[0].body).toEqual({
      p_user_id: editBinding().ownerId,
      p_command_id: editBinding().commandId,
      p_operation_id: editOperationId,
      p_input: editInput(),
      p_expected_state: editState(),
      p_calculated_items: [],
      p_nutrition_mode: 'recalculated',
      p_quantity_change: null,
      p_request_id: 'edit-test',
    })
  })
  it.each([
    'input',
    'binding',
    'kind',
    'callback',
  ])('refuses malformed request %s before an RPC and cannot swap the captured callback', async (attack) => {
    const t = transport(() => ({ data: { action: 'absent' }, error: null })),
      value = save()
    if (attack === 'input') Object.assign(value.input, { extra: 'client-macros' })
    if (attack === 'binding') value.binding.inputHash = 'not-a-hash'
    if (attack === 'kind') Object.assign(value.input, { kind: 'undo_registration' })
    if (attack === 'callback') {
      Object.assign(t.client, {
        rpc: () => {
          throw new Error('replacement callback')
        },
      })
      expect(await t.store.save(value)).toEqual({ action: 'absent' })
      expect(t.calls).toHaveLength(1)
    } else {
      await expect(t.store.save(value)).rejects.toMatchObject({
        code: 'conversation_meal_edit_unavailable',
      })
      expect(t.calls).toHaveLength(0)
    }
  })
})
