import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
} from './conversation-current-scope'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'
import { createSupabaseConversationMealContinuationReadStore } from './conversation-meal-continuation-read-store'
import { parseConversationMealEditState } from './conversation-meal-edit-contracts'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

type Origin = ReturnType<typeof parseConversationMealContinuationFeedbackBinding>
export interface ConversationMealLinkedOrigin {
  readonly schema: 'conversation.meal-linked-origin.v1'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly parent_binding: Origin['parentBinding']
  readonly child_binding: Origin['childBinding']
  readonly parent_decision_hash: string
  readonly receipt: Origin['receipt']
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_linked_origin_unavailable',
    'Linked meal origin is unavailable',
  )
}
function refuse(action: string): never {
  throw new MobileApiError(
    409,
    `conversation_meal_linked_origin_${action}`,
    'Linked meal origin has changed',
  )
}
const refusal = z.object({ action: z.enum(['absent', 'stale_epoch', 'event_conflict']) }).strict()

/** Hashes come only from owned trusted SQL state, never a public v3 event.
 * No existing reader fence is relaxed. This factual identity is not an ACK,
 * current group, clinical capability or permission to write. */
export function createConversationMealLinkedOriginService(
  db: ServiceClient,
  dependencies: ConversationCurrentScopeDependencies = {},
) {
  const rpc = db.rpc.bind(db),
    ownedRead = rpc as (
      name: 'read_conversation_meal_edit_state',
      args: { p_user_id: string; p_command_id: string },
    ) => PromiseLike<unknown>,
    from = db.from.bind(db),
    sdk = new Proxy(db, {
      get(target, key, receiver) {
        if (key === 'rpc') return rpc
        if (key === 'from') return from
        return Reflect.get(target, key, receiver)
      },
    }),
    reader = createSupabaseConversationMealContinuationReadStore(sdk),
    read = reader.read.bind(reader),
    ports: ConversationCurrentScopeDependencies = Object.freeze({
      ...(dependencies.auth
        ? {
            auth: Object.freeze({
              verifyAccessToken: dependencies.auth.verifyAccessToken.bind(dependencies.auth),
              loadPatient: dependencies.auth.loadPatient.bind(dependencies.auth),
              isAdmin: dependencies.auth.isAdmin.bind(dependencies.auth),
            }),
          }
        : {}),
      ...(dependencies.clinical
        ? {
            clinical: Object.freeze({
              capture: dependencies.clinical.capture.bind(dependencies.clinical),
            }),
          }
        : {}),
    })
  return Object.freeze({
    async read(
      original: MobileAuthContext,
      rawCommandId: string,
      rawEpoch: string,
    ): Promise<ConversationMealLinkedOrigin> {
      const who = freezeInterpretation(workoutSnapshot(original)),
        ownerId = authenticatedReevaluationOwner(who),
        commandId = workoutUUID.parse(rawCommandId),
        epoch = workoutUUID.parse(rawEpoch),
        scope = createConversationCurrentScope(
          sdk,
          who,
          { authUserId: who.authUserId, ownerId, epoch },
          ports,
        ),
        before = await scope.observe()
      // Pin and fully qualify private state before asynchronous revalidation.
      let state: ReturnType<typeof parseConversationMealEditState> | z.infer<typeof refusal>
      try {
        const envelope = z.object({ data: z.unknown(), error: z.null() }).parse(
            await ownedRead('read_conversation_meal_edit_state', {
              p_user_id: ownerId,
              p_command_id: commandId,
            }),
          ),
          raw = workoutSnapshot(envelope.data),
          denied = refusal.safeParse(raw)
        if (denied.success) state = denied.data
        else {
          const observed = z
            .object({ command: z.object({ input_hash: z.string(), epoch: z.string() }) })
            .parse(raw).command
          state = parseConversationMealEditState(raw, {
            ownerId,
            commandId,
            inputHash: observed.input_hash,
            epoch: observed.epoch,
          })
        }
      } catch {
        await scope.observe()
        return unavailable()
      }
      const middle = await scope.observe()
      if (state.action !== 'available') return refuse(state.action)
      if (state.binding.epoch !== epoch) return refuse('stale_epoch')
      const receipt = state.originalReceipt,
        at = conversationJournalInstant(state.observedAt)
      if (
        at < conversationJournalInstant(before.observed_at) ||
        at > conversationJournalInstant(middle.observed_at)
      )
        return unavailable()
      if (
        state.binding.command_protocol !== 'conversation.clarification.v1' ||
        receipt.schema !== 'conversation.meal-continuation-effect.v1'
      )
        return unavailable()
      const identity = {
        ownerId,
        epoch,
        parentCommandId: receipt.parent_command_id,
        parentInputHash: receipt.parent_input_hash,
        replyId: commandId,
        replyInputHash: state.binding.input_hash,
      }
      let linked: Awaited<ReturnType<typeof read>>
      try {
        linked = await read(identity)
      } catch {
        await scope.observe()
        return unavailable()
      }
      const after = await scope.observe()
      if (linked.action !== 'available') return refuse(linked.action)
      const seen = conversationJournalInstant(linked.observed_at),
        fulfillment = linked.fulfillment
      if (
        seen < conversationJournalInstant(middle.observed_at) ||
        seen > conversationJournalInstant(after.observed_at) ||
        !fulfillment ||
        !isDeepStrictEqual(fulfillment.child_binding, state.binding) ||
        !isDeepStrictEqual(fulfillment.receipt, receipt)
      )
        return unavailable()
      const origin = parseConversationMealContinuationFeedbackBinding({
        parentBinding: fulfillment.parent_binding,
        childBinding: fulfillment.child_binding,
        parentDecisionHash: linked.parent.decision.decision_hash,
        receipt,
      })
      return freezeInterpretation({
        schema: 'conversation.meal-linked-origin.v1',
        auth_user_id: who.authUserId,
        owner_id: ownerId,
        epoch,
        observed_at: linked.observed_at,
        parent_binding: origin.parentBinding,
        child_binding: origin.childBinding,
        parent_decision_hash: origin.parentDecisionHash,
        receipt: origin.receipt,
      })
    },
  })
}
