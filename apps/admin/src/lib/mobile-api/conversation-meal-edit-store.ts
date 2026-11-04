/** One-shot service-only transport. No implicit read, retry, calculation,
 * admission, legacy mutation, provider or public projection occurs here. */
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  bindConversationMealEdit,
  bindConversationMealEditIdentity,
  type ConversationMealEditBinding,
  type ConversationMealEditReceipt,
  type ConversationMealEditServerBinding,
  type ConversationMealEditState,
  conversationMealEditUnavailable,
  detachConversationMealEditJson,
  parseConversationMealEditCurrentState,
  parseConversationMealEditReceipt,
  parseConversationMealEditServerBinding,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

type Refusal<A extends string> = { readonly action: A }
export type ConversationMealEditStateRead =
  | Refusal<'absent' | 'stale_epoch' | 'event_conflict'>
  | ConversationMealEditState
export interface ConversationMealEditOperationInput {
  readonly binding: ConversationMealEditBinding
  readonly operationId: string
  readonly input: unknown
}
export type ConversationMealEditOperationRead =
  | Refusal<'absent' | 'stale_epoch' | 'input_conflict' | 'event_conflict'>
  | {
      readonly action: 'available'
      readonly binding: ConversationMealEditServerBinding
      readonly receipt: ConversationMealEditReceipt
    }
export type ConversationMealEditWriteOutcome =
  | Refusal<
      | 'absent'
      | 'stale_epoch'
      | 'input_conflict'
      | 'event_conflict'
      | 'version_conflict'
      | 'day_closed'
      | 'undo_expired'
      | 'in_progress'
    >
  | {
      readonly action: 'committed' | 'replay'
      readonly binding: ConversationMealEditServerBinding
      readonly receipt: ConversationMealEditReceipt
    }
export interface ConversationMealEditWriteInput extends ConversationMealEditOperationInput {
  /** Private server values. Null permits SQL's original-winner replay. */
  readonly expectedState: unknown
  readonly requestId: string
  /** Qualified original child FX from readState; not sent as an RPC argument. */
  readonly originalReceipt?: unknown
}
export interface ConversationMealEditSaveInput extends ConversationMealEditWriteInput {
  readonly calculatedItems: unknown
  readonly nutritionMode: 'quantity_only' | 'recalculated' | null
  readonly quantityChange: { readonly quantity_g: number } | null
}
export interface ConversationMealEditStore {
  readState(binding: ConversationMealEditBinding): Promise<ConversationMealEditStateRead>
  readOperation(
    input: ConversationMealEditOperationInput,
  ): Promise<ConversationMealEditOperationRead>
  save(input: ConversationMealEditSaveInput): Promise<ConversationMealEditWriteOutcome>
  undoSave(input: ConversationMealEditWriteInput): Promise<ConversationMealEditWriteOutcome>
  undoRegistration(input: ConversationMealEditWriteInput): Promise<ConversationMealEditWriteOutcome>
}
class EditTransportFailure extends MobileApiError {
  constructor(code: 'busy' | 'conflict') {
    super(409, `conversation_meal_edit_${code}`, 'Meal edit state is unavailable')
  }
}
function fail(error: unknown): never {
  if (error instanceof EditTransportFailure) throw error
  return conversationMealEditUnavailable()
}
function data(raw: unknown): Json {
  const envelope = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (envelope.error !== null) {
    const e = envelope.error
    const code = e && typeof e === 'object' && 'code' in e ? e.code : null
    if (code === '55P03') throw new EditTransportFailure('busy')
    if (code === '40001') throw new EditTransportFailure('conflict')
    return conversationMealEditUnavailable()
  }
  return detachConversationMealEditJson(envelope.data)
}
const refusal = <const A extends [string, ...string[]]>(values: A) =>
  z.object({ action: z.enum(values) }).strict()
const success = <const A extends [string, ...string[]]>(values: A) =>
  z.object({ action: z.enum(values), command: z.unknown(), receipt: z.unknown() }).strict()
const writeRefusal = refusal([
  'absent',
  'stale_epoch',
  'input_conflict',
  'event_conflict',
  'version_conflict',
  'day_closed',
  'undo_expired',
  'in_progress',
])

export function createSupabaseConversationMealEditStore(
  db: ServiceClient,
): ConversationMealEditStore {
  // Bounded bridge until generated declarations are integrated by the owner.
  type RPC = (
    name:
      | 'read_conversation_meal_edit_state'
      | 'read_conversation_meal_edit_operation'
      | 'commit_conversation_meal_item_edit'
      | 'undo_conversation_meal_item_edit'
      | 'undo_conversation_meal_registration',
    args: Record<string, Json>,
  ) => PromiseLike<unknown>
  const rpc = db.rpc.bind(db) as RPC
  const identity = (b: ConversationMealEditBinding) => ({
    p_user_id: b.ownerId,
    p_command_id: b.commandId,
  })
  async function write(
    input: ConversationMealEditWriteInput | ConversationMealEditSaveInput,
    kind: 'save' | 'undo_save' | 'undo_registration',
  ): Promise<ConversationMealEditWriteOutcome> {
    try {
      const op = bindConversationMealEdit(input)
      if (op.input.kind !== kind) return conversationMealEditUnavailable()
      const origin = Object.getOwnPropertyDescriptor(input, 'originalReceipt')
      if (origin && (!origin.enumerable || !('value' in origin)))
        return conversationMealEditUnavailable()
      const originalReceipt =
        origin?.value === undefined ? undefined : detachConversationMealEditJson(origin.value)
      const args: Record<string, Json> = {
        ...identity(op.binding),
        p_operation_id: op.operationId,
        p_input: op.input as Json,
        p_expected_state: detachConversationMealEditJson(input.expectedState),
        p_request_id: z.string().min(1).max(128).parse(input.requestId),
      }
      if (kind === 'save') {
        if (!('calculatedItems' in input)) return conversationMealEditUnavailable()
        args.p_calculated_items = detachConversationMealEditJson(input.calculatedItems)
        args.p_nutrition_mode = z
          .enum(['quantity_only', 'recalculated'])
          .nullable()
          .parse(input.nutritionMode)
        args.p_quantity_change = detachConversationMealEditJson(input.quantityChange)
      }
      if (originalReceipt !== undefined)
        parseConversationMealEditCurrentState(args.p_expected_state, op.binding, originalReceipt)
      const name =
        kind === 'save'
          ? 'commit_conversation_meal_item_edit'
          : kind === 'undo_save'
            ? 'undo_conversation_meal_item_edit'
            : 'undo_conversation_meal_registration'
      const v = z
        .union([writeRefusal, success(['committed', 'replay'])])
        .parse(data(await rpc(name, freezeConversationWriter(args))))
      if (v.action !== 'committed' && v.action !== 'replay')
        return freezeConversationWriter(writeRefusal.parse(v))
      const binding = parseConversationMealEditServerBinding(v.command, op.binding),
        receipt = parseConversationMealEditReceipt(v.receipt, op)
      if (v.action === 'committed') {
        const state = parseConversationMealEditCurrentState(
          args.p_expected_state,
          op.binding,
          originalReceipt,
        )
        const previousIds = state.items.map((row) => row.id)
        if (
          receipt.snapshot.id !== state.snapshot.id ||
          receipt.snapshot.date !== state.snapshot.date ||
          receipt.removed_item_ids.some((id) => !previousIds.includes(id)) ||
          receipt.new_item_ids.some((id) => previousIds.includes(id)) ||
          (kind === 'undo_registration' && receipt.removed_item_ids.length !== previousIds.length)
        )
          return conversationMealEditUnavailable()
      }
      return freezeConversationWriter({ action: v.action, binding, receipt })
    } catch (error) {
      return fail(error)
    }
  }
  return Object.freeze({
    async readState(input: ConversationMealEditBinding): Promise<ConversationMealEditStateRead> {
      try {
        const b = bindConversationMealEditIdentity(input),
          raw = data(await rpc('read_conversation_meal_edit_state', identity(b)))
        const empty = refusal(['absent', 'stale_epoch', 'event_conflict']).safeParse(raw)
        if (empty.success) return freezeConversationWriter(empty.data)
        return parseConversationMealEditState(raw, b)
      } catch (error) {
        return fail(error)
      }
    },
    async readOperation(
      input: ConversationMealEditOperationInput,
    ): Promise<ConversationMealEditOperationRead> {
      try {
        const op = bindConversationMealEdit(input)
        const v = z
          .union([
            refusal(['absent', 'stale_epoch', 'input_conflict', 'event_conflict']),
            success(['available']),
          ])
          .parse(
            data(
              await rpc('read_conversation_meal_edit_operation', {
                ...identity(op.binding),
                p_operation_id: op.operationId,
                p_input: op.input as Json,
              }),
            ),
          )
        if (v.action !== 'available') return freezeConversationWriter(v)
        const binding = parseConversationMealEditServerBinding(v.command, op.binding),
          receipt = parseConversationMealEditReceipt(v.receipt, op)
        return freezeConversationWriter({ action: 'available', binding, receipt })
      } catch (error) {
        return fail(error)
      }
    },
    save: (input: ConversationMealEditSaveInput) => write(input, 'save'),
    undoSave: (input: ConversationMealEditWriteInput) => write(input, 'undo_save'),
    undoRegistration: (input: ConversationMealEditWriteInput) => write(input, 'undo_registration'),
  })
}
