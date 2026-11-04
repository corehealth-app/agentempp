import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  editBinding,
  editInput,
  editOperationId,
  editReadState,
  editReceipt,
  editState,
  writerCommand,
} from './__fixtures__/conversation-meal-edit'
import {
  bindConversationMealEdit,
  detachConversationMealEditJson,
  parseConversationMealEditInput,
  parseConversationMealEditReceipt,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'

describe('private command edit closed contracts', () => {
  it('binds exact intent with a detached canonical hash and a distinct patient identity', () => {
    const input = editInput()
    const bound = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input,
    })
    expect(bound.inputHash).toBe('852da25cacdb763d018a5e3a4b777a306ab3d6ea2c92d31b58332c90afeb4c4c')
    expect(bound.binding.ownerId).not.toBe(editState().context.auth_user_id)
    input.items[0].food_name = 'changed after bind'
    expect(bound.input).toEqual(editInput())
    expect(bound.input.kind).toBe('save')
    if (bound.input.kind !== 'save') throw new Error('wrong intent kind')
    expect(Object.isFrozen(bound.input.items)).toBe(true)
    expect(
      bindConversationMealEdit({
        binding: editBinding(),
        operationId: editOperationId,
        input: Object.fromEntries(Object.entries(editInput()).reverse()),
      }).inputHash,
    ).toBe(bound.inputHash)
  })
  it.each([
    [1e-7, '0.0000001'],
    [1.23e-7, '0.000000123'],
    [1e-6, '0.000001'],
    [Number.MIN_VALUE, `0.${'0'.repeat(323)}5`],
  ] as const)('matches SQL jsonb decimal canonical hash for %s', (quantity, decimal) => {
    const input = {
      ...editInput(),
      items: [{ food_name: 'rice', quantity_g: quantity, user_kcal: quantity }],
    }
    const reference = `{"expected_revision":0,"expected_version":${JSON.stringify(input.expected_version)},"items":[{"food_name":"rice","quantity_g":${decimal},"user_kcal":${decimal}}],"kind":"save","record_id":${JSON.stringify(input.record_id)},"schema":"conversation.meal-edit.v1"}`
    const bound = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input,
    })
    expect(bound.inputHash).toBe(createHash('sha256').update(reference).digest('hex'))
    expect(bound.input).toEqual(input)
  })
  it.each([0, -0])('hashes user kcal zero as the actual JSON wire value', (zero) => {
    const input = {
      ...editInput(),
      items: [{ food_name: 'rice', quantity_g: 100, user_kcal: zero }],
    }
    const reference = `{"expected_revision":0,"expected_version":${JSON.stringify(input.expected_version)},"items":[{"food_name":"rice","quantity_g":100,"user_kcal":0}],"kind":"save","record_id":${JSON.stringify(input.record_id)},"schema":"conversation.meal-edit.v1"}`
    expect(
      bindConversationMealEdit({ binding: editBinding(), operationId: editOperationId, input })
        .inputHash,
    ).toBe(createHash('sha256').update(reference).digest('hex'))
  })
  it.each([
    { unexpected: true },
    { expected_revision: 0.1 },
    { expected_revision: 2147483648 },
    { expected_revision: null },
    { expected_version: 'v1:wrong' },
    { record_id: `${editOperationId.toUpperCase()}x` },
    { items: [] },
    { items: [{ food_name: 'rice', quantity_g: 0 }] },
    { items: [{ food_name: ' rice ', quantity_g: 1 }] },
    { items: [{ food_name: 'rice', quantity_g: 1, use_nutrition_label: true }] },
    { items: [{ food_name: 'rice', quantity_g: 1, user_kcal: null }] },
    { items: [{ food_name: 'rice', quantity_g: 1, kcal: 300 }] },
  ])('rejects malformed or client-authoritative original intent %#', (patch) => {
    expect(() => parseConversationMealEditInput({ ...editInput(), ...patch })).toThrow()
  })
  it('preserves UTF16 names and private full rows including unknown SQL columns and nanoseconds', () => {
    const raw = editReadState()
    Object.assign(
      raw.current_state.snapshot,
      JSON.parse('{"future_column":{"__proto__":{"safe":1}}}'),
    )
    const copy = structuredClone(raw)
    const result = parseConversationMealEditState(raw, editBinding())
    expect(result.currentState).toEqual(copy.current_state)
    expect(result.currentState?.snapshot.updated_at).toBe('2026-11-04T12:00:00.123456+00:00')
    raw.current_state.items[0].food_name = 'mutated'
    expect(result.currentState?.items[0].food_name).toBe(copy.current_state.items[0].food_name)
    expect(Object.isFrozen(result.currentState?.snapshot)).toBe(true)
  })
  it.each([
    'epoch',
    'input_hash',
    'owner_id',
    'command_id',
  ] as const)('rejects actual server binding drift in %s', (field) => {
    const raw = editReadState()
    raw.command[field] = field === 'input_hash' ? 'f'.repeat(64) : editOperationId
    expect(() => parseConversationMealEditState(raw, editBinding())).toThrow()
  })
  it('uses the existing original receipt parser when the genuine original command is supplied', () => {
    const binding = { ...editBinding(), originalCommand: writerCommand() }
    expect(parseConversationMealEditState(editReadState(), binding).originalReceipt).toEqual(
      editReadState().original_receipt,
    )
    const changed = structuredClone(binding)
    Object.assign(changed.originalCommand.command.source, { text: 'other intent' })
    expect(() => parseConversationMealEditState(editReadState(), changed)).toThrow()
  })
  it.each([
    'unknownEnvelope',
    'missingFullColumn',
    'foreignItem',
    'wrongProvider',
    'badOriginal',
    'duplicateIDs',
    'fakeLastRevision',
    'nonJson',
  ])('refuses unsafe state shape/binding %s', (attack) => {
    const raw = editReadState()
    if (attack === 'unknownEnvelope') Object.assign(raw, { context: {} })
    if (attack === 'missingFullColumn') Reflect.deleteProperty(raw.current_state.snapshot, 'steps')
    if (attack === 'foreignItem') raw.current_state.items[0].user_id = editOperationId
    if (attack === 'wrongProvider') raw.current_state.items[0].raw_provider_message_id = 'other'
    if (attack === 'badOriginal') raw.original_receipt.input_hash = 'f'.repeat(64)
    if (attack === 'duplicateIDs') raw.current_state.items.push(raw.current_state.items[0])
    if (attack === 'fakeLastRevision') raw.revision = 1
    if (attack === 'nonJson') Object.assign(raw.current_state.snapshot, { future: undefined })
    expect(() => parseConversationMealEditState(raw, editBinding())).toThrow()
  })
  it('allows an actually empty/deleted current group without inventing current facts', () => {
    const raw = { ...editReadState(), current_state: null, lineage_compatible: false }
    expect(parseConversationMealEditState(raw, editBinding()).currentState).toBeNull()
  })
  it('validates a new immutable receipt against operation input and five-minute microsecond clock', () => {
    const b = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input: editInput(),
    })
    const raw = editReceipt(b.inputHash)
    expect(parseConversationMealEditReceipt(raw, b)).toEqual(raw)
    expect(() =>
      parseConversationMealEditReceipt(
        { ...raw, undo_expires_at: '2026-11-04T12:06:00.123455+00:00' },
        b,
      ),
    ).toThrow()
  })
  it.each([
    'owner_id',
    'command_id',
    'operation_id',
    'input_hash',
    'kind',
    'revision',
    'target_operation_id',
    'removed_item_ids',
    'new_item_ids',
    'next_record_id',
    'extra',
  ])('rejects a mismatched receipt %s', (field) => {
    const b = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input: editInput(),
    })
    const raw = editReceipt(b.inputHash)
    const replacements: Record<string, unknown> = {
      owner_id: editOperationId,
      command_id: editOperationId,
      operation_id: editBinding().ownerId,
      input_hash: 'f'.repeat(64),
      kind: 'registration_undone',
      revision: 2,
      target_operation_id: editOperationId,
      removed_item_ids: [editOperationId],
      new_item_ids: [],
      next_record_id: null,
      extra: true,
    }
    expect(() =>
      parseConversationMealEditReceipt({ ...raw, [field]: replacements[field] }, b),
    ).toThrow()
  })
  it('rejects an impossible first-revision UndoSave receipt and a self-targeted Undo', () => {
    const target = '10000000-0000-4000-8000-000000000082'
    const input = {
      schema: 'conversation.meal-edit.v1',
      kind: 'undo_save',
      expected_revision: 0,
      expected_version: `v1:${'a'.repeat(64)}`,
      target_operation_id: target,
    }
    const b = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input,
    })
    expect(() =>
      parseConversationMealEditReceipt(
        {
          ...editReceipt(b.inputHash),
          kind: 'save_undone',
          undo_expires_at: null,
          target_operation_id: target,
        },
        b,
      ),
    ).toThrow()
    const self = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input: { ...input, expected_revision: 1, target_operation_id: editOperationId },
    })
    expect(() =>
      parseConversationMealEditReceipt(
        {
          ...editReceipt(self.inputHash),
          kind: 'save_undone',
          revision: 2,
          undo_expires_at: null,
          target_operation_id: editOperationId,
        },
        self,
      ),
    ).toThrow()
  })
  it('refuses sparse arrays with custom keys instead of silently changing them to JSON null', () => {
    const sparse = new Array(1)
    Object.assign(sparse, { extra: 3 })
    expect(() => detachConversationMealEditJson(sparse)).toThrow()
  })
  it.each([
    '00000000-0000-0000-0000-000000000000',
    '12345678-abcd-0000-0000-123456789abc',
  ])('accepts the actual SQL lowercase UUID layout %s', (operationId) => {
    expect(
      bindConversationMealEdit({ binding: editBinding(), operationId, input: editInput() })
        .operationId,
    ).toBe(operationId)
  })
  it.each([
    undefined,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    1n,
    new Date(),
    () => null,
    '\ud800',
    { nested: undefined },
  ])('rejects non-JSON or unencodable transport value %#', (value) => {
    expect(() => detachConversationMealEditJson(value)).toThrow()
  })
})
