/** Private orchestration only. Neither the full C11 state nor an unguarded
 * snapshot/receipt is a public chat presentation. No route is activated here. */

import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { prepareConfirmedMealMutation } from './confirmed-meal-mutation-preparation'
import { privateConfirmedMealVersion } from './confirmed-meal-read'
import type { ConversationJournalBinding } from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealEdit,
  bindConversationMealEdit,
  type ConversationMealEditReceipt,
  parseConversationMealEditReceipt,
  parseConversationMealEditServerBinding,
} from './conversation-meal-edit-contracts'
import {
  type ConversationMealEditStore,
  createSupabaseConversationMealEditStore,
} from './conversation-meal-edit-store'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const originalSchema = z
  .object({ commandId: uuid, inputHash: z.string().regex(/^[a-f0-9]{64}$/u), epoch: uuid })
  .strict()
export type ConversationMealEditOriginal = z.infer<typeof originalSchema>
export interface PrivateConversationMealEditResult {
  readonly status: 'saved'
  readonly binding: ConversationJournalBinding
  readonly operationId: string
  readonly inputHash: string
  readonly receipt: ConversationMealEditReceipt
}
export interface ConversationMealEditServicePorts {
  readonly store?: ConversationMealEditStore
  readonly prepare?: typeof prepareConfirmedMealMutation
  readonly now?: () => Date
}
function refuse(action: string): never {
  throw new MobileApiError(
    409,
    `conversation_meal_edit_${action}`,
    'The meal edit state has changed; reconcile before continuing',
  )
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_edit_unavailable',
    'Meal edit state is unavailable',
  )
}
function result(
  bound: BoundConversationMealEdit,
  actual: ConversationJournalBinding,
  receipt: ConversationMealEditReceipt,
): PrivateConversationMealEditResult {
  if (
    actual.owner_id !== bound.binding.ownerId ||
    actual.command_id !== bound.binding.commandId ||
    actual.input_hash !== bound.binding.inputHash ||
    actual.epoch !== bound.binding.epoch
  )
    return refuse('stale_epoch')
  const binding = parseConversationMealEditServerBinding(actual, bound.binding)
  const qualifiedReceipt = parseConversationMealEditReceipt(receipt, bound)
  return freezeConversationWriter({
    status: 'saved',
    binding,
    operationId: bound.operationId,
    inputHash: bound.inputHash,
    receipt: qualifiedReceipt,
  })
}
export function createConversationMealEditService(
  db: ServiceClient,
  ports: ConversationMealEditServicePorts = {},
) {
  const s = ports.store ?? createSupabaseConversationMealEditStore(db),
    store: ConversationMealEditStore = Object.freeze({
      readState: s.readState.bind(s),
      readOperation: s.readOperation.bind(s),
      save: s.save.bind(s),
      undoSave: s.undoSave.bind(s),
      undoRegistration: s.undoRegistration.bind(s),
    }),
    prepare = ports.prepare?.bind(ports) ?? prepareConfirmedMealMutation,
    clock = ports.now?.bind(ports) ?? (() => new Date())
  return Object.freeze({
    async execute(
      auth: MobileAuthContext,
      original: ConversationMealEditOriginal,
      operationId: string,
      rawInput: unknown,
      requestId: string,
    ): Promise<PrivateConversationMealEditResult> {
      const who = freezeConversationWriter(structuredClone(auth)),
        owner = authenticatedReevaluationOwner(who)
      let bound: BoundConversationMealEdit, request: string
      try {
        const identity = originalSchema.parse(structuredClone(original))
        bound = bindConversationMealEdit({
          binding: { ownerId: owner, ...identity },
          operationId,
          input: structuredClone(rawInput),
        })
        request = z
          .string()
          .regex(/^[A-Za-z0-9._:-]{1,128}$/u)
          .parse(requestId)
      } catch {
        throw new MobileApiError(
          422,
          'conversation_meal_edit_invalid',
          'A valid original command, edit identity and closed input are required',
        )
      }
      const operation = Object.freeze({
        binding: bound.binding,
        operationId: bound.operationId,
        input: bound.input,
      })
      const readWinner = async (): Promise<PrivateConversationMealEditResult | null> => {
        const v = await store.readOperation(operation)
        if (v.action === 'available') return result(bound, v.binding, v.receipt)
        if (v.action !== 'absent') return refuse(v.action)
        return null
      }
      // Original durable winner always precedes context, date, revision or
      // preparation. Expiry/day closure cannot cause a repeat calculation.
      const prior = await readWinner()
      if (prior) return prior
      const current = await store.readState(bound.binding)
      if (current.action !== 'available') return refuse(current.action)
      if (
        current.binding.owner_id !== owner ||
        current.binding.command_id !== bound.binding.commandId ||
        current.binding.input_hash !== bound.binding.inputHash ||
        current.binding.epoch !== bound.binding.epoch
      )
        return refuse('stale_epoch')
      const state =
        current.currentState === null
          ? null
          : freezeConversationWriter(structuredClone(current.currentState))
      if (!state || current.revision !== bound.input.expected_revision)
        return refuse('version_conflict')
      if (
        state.context.id !== owner ||
        state.context.auth_user_id !== who.authUserId ||
        state.context.status !== 'active'
      )
        return refuse('context_changed')
      if (privateConfirmedMealVersion(state) !== bound.input.expected_version)
        return refuse('version_conflict')

      let prepared: Awaited<ReturnType<typeof prepareConfirmedMealMutation>> | null = null
      if (bound.input.kind === 'save') {
        try {
          prepared = await prepare(
            db,
            who,
            bound.input.record_id,
            {
              method: 'PATCH',
              body: {
                expected_version: bound.input.expected_version,
                item_ids: [bound.input.record_id],
                items: bound.input.items,
              },
            },
            state,
            new Date(clock().getTime()),
          )
          if (!isDeepStrictEqual(prepared.expectedState, state)) return unavailable()
        } catch (error) {
          // A competing request may have published this exact operation while
          // preparation was running. Read once; never write on this path.
          try {
            const winner = await readWinner()
            if (winner) return winner
          } catch (readError) {
            if (readError instanceof MobileApiError && readError.status === 409) throw readError
          }
          throw error
        }
      }
      const input = { ...operation, expectedState: state, requestId: request }
      let written: Awaited<ReturnType<ConversationMealEditStore['save']>>
      try {
        if (bound.input.kind === 'save') {
          if (!prepared) return unavailable()
          written = await store.save({
            ...input,
            expectedState: prepared.expectedState,
            calculatedItems: prepared.calculatedItems,
            nutritionMode: prepared.nutritionMode,
            quantityChange: prepared.quantityChange,
          })
        } else if (bound.input.kind === 'undo_save') written = await store.undoSave(input)
        else written = await store.undoRegistration(input)
      } catch (error) {
        if (error instanceof MobileApiError && error.status === 409) throw error
        try {
          const winner = await readWinner()
          if (winner) return winner
        } catch (readError) {
          if (readError instanceof MobileApiError && readError.status === 409) throw readError
        }
        return refuse('reconciliation_required')
      }
      if (!('receipt' in written)) return refuse(written.action)
      return result(bound, written.binding, written.receipt)
    },
  })
}
