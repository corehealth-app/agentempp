import { describe, expect, it } from 'vitest'
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
import wireFixture from './__fixtures__/conversation-meal-edit-public.json'
import { privateConfirmedMealVersion } from './confirmed-meal-read'
import {
  bindConversationMealEdit,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'
import {
  projectConversationMealEditResult,
  projectConversationMealGroup,
} from './conversation-meal-edit-public'

const auth = {
  ...candidateAuth,
  authUserId: editAuthId,
  identity: { ...candidateAuth.identity, id: editAuthId },
  patient: { ...candidateAuth.patient, authUserId: editAuthId },
}
function group(wire: unknown = editReadState()) {
  const state = parseConversationMealEditState(wire, editBinding())
  return projectConversationMealGroup(auth, editBinding(), state)
}
/** The shared native wire receipt predates workout coverage. Keep that
 * historical private input separate from today's complete snapshot. */
function preCoverageReadState() {
  const wire = editReadState()
  const { exercise_energy_complete, ...snapshot } = wire.current_state.snapshot
  expect(exercise_energy_complete).toBe(true)
  return { ...wire, current_state: { ...wire.current_state, snapshot } }
}
describe('closed factual command meal group and operation result', () => {
  it('keeps the exact shared native wire fixtures and PostgreSQL decimal operation hash', () => {
    expect(group(preCoverageReadState())).toEqual(wireFixture.group.data)
    const op = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input: wireFixture.input,
    })
    expect(
      projectConversationMealEditResult(auth, op, {
        status: 'saved',
        binding: writerBinding(),
        operationId: op.operationId,
        inputHash: op.inputHash,
        receipt: editReceipt(op.inputHash),
      }),
    ).toEqual(wireFixture.saved.data)
    expect(
      bindConversationMealEdit({
        binding: editBinding(),
        operationId: editOperationId,
        input: wireFixture.exponent_hash_case.input,
      }).inputHash,
    ).toBe(wireFixture.exponent_hash_case.operation_input_hash)
  })
  it('keeps current workout coverage in the full version without rewriting the historical wire receipt', () => {
    const complete = editReadState()
    const incomplete = editReadState()
    incomplete.current_state.snapshot.exercise_energy_complete = false
    const historicalVersion = group(preCoverageReadState()).current?.expected_version
    const completeVersion = group(complete).current?.expected_version
    const incompleteVersion = group(incomplete).current?.expected_version
    expect(completeVersion).toBeDefined()
    expect(incompleteVersion).toBeDefined()
    expect(completeVersion).not.toBe(incompleteVersion)
    expect(completeVersion).not.toBe(historicalVersion)
    expect(incompleteVersion).not.toBe(historicalVersion)
    expect(historicalVersion).toBe(wireFixture.group.data.current.expected_version)
  })
  it('projects current facts and the FULL private version without returning private state or guidance', () => {
    const wire = editReadState(),
      value = group(wire),
      privateState = parseConversationMealEditState(wire, editBinding()).currentState
    if (privateState === null) throw new Error('Expected fixture current state')
    expect(value).toMatchObject({
      schema: 'conversation.meal-group.v1',
      owner_id: auth.userId,
      revision: 0,
      current: {
        expected_version: privateConfirmedMealVersion(privateState),
        items: [{ id: wire.current_state.items[0].id }],
      },
      actions: {
        save: { allowed: true },
        undo_registration: { allowed: true },
        undo_save: { allowed: false, reason: 'no_save_to_undo' },
      },
    })
    expect(value.original_receipt).toEqual(wire.original_receipt)
    for (const field of [
      'snapshot',
      'context',
      'auth_user_id',
      'daily_balance',
      'calories_target',
      'protein_target',
      'current_policy',
      'image_url',
      'raw_message_id',
      'raw_provider_message_id',
      'food_db_id',
      'created_at',
      'updated_at',
    ])
      expect(JSON.stringify(value)).not.toContain(`"${field}"`)
  })
  it('preserves null nutrition and a null current group without pretending either is zero or deletion', () => {
    const wire = editReadState()
    wire.current_state.items[0].kcal = null
    expect(group(wire).current?.items[0].kcal).toBeNull()
    const empty = projectConversationMealGroup(auth, editBinding(), {
      ...parseConversationMealEditState(editReadState(), editBinding()),
      currentState: null,
    })
    expect(empty.current).toBeNull()
    expect(empty.original_receipt).toBeDefined()
    expect(empty.actions).toEqual({
      save: { allowed: false, reason: 'current_group_unavailable' },
      undo_registration: { allowed: false, reason: 'current_group_unavailable' },
      undo_save: { allowed: false, reason: 'current_group_unavailable' },
    })
  })
  it.each([
    ['leite', 206, 'mL', 1.03],
    ['whey', 30, 'scoop', 30],
    ['leite em pó marca desconhecida', 30, null, null],
  ])('retains canonical grams with exact-name estimated reference for %s', (name, grams, unit, factor) => {
    const wire = editReadState()
    Object.assign(wire.current_state.items[0], { food_name: name, quantity_g: grams })
    const item = group(wire).current?.items[0]
    expect(item?.quantity_g).toBe(grams)
    if (unit)
      expect(item?.quantity_display).toMatchObject({
        unit,
        grams_per_unit: factor,
        estimated: true,
      })
    else expect(item?.quantity_display).toBeNull()
  })
  it('uses server microsecond clock, rejecting equality at the five-minute deadline', () => {
    const wire = editReadState()
    wire.observed_at = '2026-11-04T12:05:00.000003+00:00'
    expect(group(wire).actions.undo_registration).toEqual({ allowed: true })
    wire.observed_at = wire.registration_undo_expires_at
    expect(group(wire).actions.undo_registration).toEqual({
      allowed: false,
      reason: 'undo_expired',
    })
    expect(group(wire).actions.save).toEqual({ allowed: true })
  })
  it.each([
    'day_closed',
    'not_current_day',
    'invalid_timezone',
  ])('withholds all fresh actions for %s', (reason) => {
    const wire = editReadState()
    if (reason === 'day_closed') wire.current_state.snapshot.day_closed = true
    else if (reason === 'not_current_day') wire.observed_at = '2026-11-05T12:01:00.000004+00:00'
    else wire.current_state.context.timezone = 'Not/A_Timezone'
    const actions = group(wire).actions
    for (const action of Object.values(actions)) expect(action).toEqual({ allowed: false, reason })
  })
  it('uses the current context timezone at midnight rather than original receipt timezone or device date', () => {
    const wire = editReadState()
    wire.current_state.context.timezone = 'Pacific/Kiritimati'
    expect(group(wire).actions.save).toEqual({ allowed: false, reason: 'not_current_day' })
  })
  it('allows fresh Save after an external generation but denies Undo', () => {
    const wire = editReadState()
    wire.lineage_compatible = false
    expect(group(wire).actions).toMatchObject({
      save: { allowed: true },
      undo_registration: { allowed: false, reason: 'version_changed' },
    })
  })
  it('offers Undo only for the latest Save and preserves its exact deadline/target', () => {
    const wire = editReadState(),
      receipt = editReceipt('b'.repeat(64))
    const value = projectConversationMealGroup(auth, editBinding(), {
      ...parseConversationMealEditState(wire, editBinding()),
      revision: 1,
      lastOperation: receipt,
      observedAt: '2026-11-04T12:02:00Z',
    })
    expect(value.actions.undo_save).toEqual({ allowed: true })
    expect(value.actions.undo_registration).toEqual({ allowed: false, reason: 'version_changed' })
    expect(value.last_operation).toMatchObject({
      operation_id: editOperationId,
      undo_expires_at: receipt.undo_expires_at,
    })
    expect(value.last_operation).not.toHaveProperty('snapshot')
  })
  it('denies a mismatched actual Auth linkage without exposing facts', () => {
    const foreign = {
      ...auth,
      authUserId: auth.userId,
      identity: { ...auth.identity, id: auth.userId },
      patient: { ...auth.patient, authUserId: auth.userId },
    }
    expect(() =>
      projectConversationMealGroup(
        foreign,
        editBinding(),
        parseConversationMealEditState(editReadState(), editBinding()),
      ),
    ).toThrow()
  })
  it('retains facts for a null timezone while withholding all fresh actions', () => {
    const state = parseConversationMealEditState(editReadState(), editBinding())
    if (!state.currentState) throw new Error('Expected fixture current state')
    const current = {
      ...state.currentState,
      context: { ...state.currentState.context, timezone: null },
    }
    const value = projectConversationMealGroup(auth, editBinding(), {
      ...state,
      currentState: current,
    })
    expect(value.current?.timezone).toBeNull()
    for (const action of Object.values(value.actions))
      expect(action).toEqual({ allowed: false, reason: 'invalid_timezone' })
  })
  it('withholds Undo Save exactly at its deadline and after a different physical generation', () => {
    const state = parseConversationMealEditState(editReadState(), editBinding()),
      last = editReceipt('b'.repeat(64))
    const input = { ...state, revision: 1, lastOperation: last, observedAt: last.undo_expires_at }
    expect(projectConversationMealGroup(auth, editBinding(), input).actions.undo_save).toEqual({
      allowed: false,
      reason: 'undo_expired',
    })
    expect(
      projectConversationMealGroup(auth, editBinding(), {
        ...input,
        lineageCompatible: false,
        observedAt: '2026-11-04T12:02:00Z',
      }).actions,
    ).toMatchObject({
      save: { allowed: true },
      undo_save: { allowed: false, reason: 'version_changed' },
    })
  })
  it('withholds actions when revision cannot advance without overflow', () => {
    const state = parseConversationMealEditState(editReadState(), editBinding()),
      last = { ...editReceipt('b'.repeat(64)), revision: 2147483647 }
    const value = projectConversationMealGroup(auth, editBinding(), {
      ...state,
      revision: 2147483647,
      lastOperation: last,
      observedAt: '2026-11-04T12:02:00Z',
    })
    for (const action of Object.values(value.actions))
      expect(action).toEqual({ allowed: false, reason: 'revision_exhausted' })
  })
  it('returns an immutable operation ACK without its clinical snapshot or a dependent current-group read', () => {
    const op = bindConversationMealEdit({
        binding: editBinding(),
        operationId: editOperationId,
        input: editInput(),
      }),
      receipt = editReceipt(op.inputHash)
    const value = projectConversationMealEditResult(auth, op, {
      status: 'saved',
      binding: writerBinding(),
      operationId: op.operationId,
      inputHash: op.inputHash,
      receipt: { ...receipt, snapshot: { ...receipt.snapshot, daily_balance: -900 } },
    })
    expect(value).toMatchObject({
      schema: 'conversation.meal-edit-result.v1',
      status: 'saved',
      input_hash: editBinding().inputHash,
      receipt: {
        schema: 'conversation.meal-edit-effect-public.v1',
        input_hash: op.inputHash,
        operation_id: op.operationId,
      },
    })
    expect(value.receipt).not.toHaveProperty('snapshot')
    expect(JSON.stringify(value)).not.toContain('daily_balance')
    expect(Object.isFrozen(value.receipt)).toBe(true)
  })
  it.each([
    'input_hash',
    'epoch',
    'owner_id',
  ])('rejects a result whose actual command %s differs', (key) => {
    const op = bindConversationMealEdit({
      binding: editBinding(),
      operationId: editOperationId,
      input: editInput(),
    })
    expect(() =>
      projectConversationMealEditResult(auth, op, {
        status: 'saved',
        binding: {
          ...writerBinding(),
          [key]: key === 'input_hash' ? 'f'.repeat(64) : editOperationId,
        },
        operationId: op.operationId,
        inputHash: op.inputHash,
        receipt: editReceipt(op.inputHash),
      }),
    ).toThrow()
  })
  it('rejects nonfinite public facts rather than serializing null or hiding corruption', () => {
    const wire = editReadState()
    wire.current_state.items[0].kcal = Number.NaN
    expect(() => group(wire)).toThrow()
  })
})
