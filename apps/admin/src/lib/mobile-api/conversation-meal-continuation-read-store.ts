/** One read-only RPC. No retry, capture, admission, interpreter, calculator,
 * nutrition callback, writer, reward or current Auth authority is provided. */
import type { ServiceClient } from '@mpp/db'
import {
  type ConversationMealContinuationReadIdentity,
  type ConversationMealContinuationReadOutcome,
  conversationContinuationReadUnavailable,
  parseConversationMealContinuationRead,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'

export interface ConversationMealContinuationReadStore {
  read(
    identity: ConversationMealContinuationReadIdentity,
  ): Promise<ConversationMealContinuationReadOutcome>
}
export function createSupabaseConversationMealContinuationReadStore(
  db: ServiceClient,
): ConversationMealContinuationReadStore {
  const rpc = db.rpc.bind(db) as (
    name: 'read_conversation_meal_continuation',
    args: Record<string, string | null>,
  ) => PromiseLike<unknown>
  return Object.freeze({
    async read(rawIdentity: ConversationMealContinuationReadIdentity) {
      try {
        const identity = parseConversationMealContinuationReadIdentity(rawIdentity)
        const args = Object.freeze({
          p_user_id: identity.ownerId,
          p_parent_command_id: identity.parentCommandId,
          p_expected_epoch: identity.epoch,
          p_parent_input_hash: identity.parentInputHash,
          p_reply_id: identity.replyId ?? null,
          p_reply_input_hash: identity.replyInputHash ?? null,
        })
        const response = await rpc('read_conversation_meal_continuation', args)
        if (!response || typeof response !== 'object' || Array.isArray(response))
          conversationContinuationReadUnavailable()
        const fields = Object.getOwnPropertyDescriptors(response)
        const allowed = new Set(['data', 'error', 'count', 'status', 'statusText', 'success'])
        for (const key of Reflect.ownKeys(fields)) {
          if (typeof key !== 'string' || !allowed.has(key))
            conversationContinuationReadUnavailable()
          const field = fields[key]
          if (!field?.enumerable || !('value' in field)) conversationContinuationReadUnavailable()
        }
        if (
          !fields.data ||
          !fields.error ||
          fields.error.value !== null ||
          (fields.success && fields.success.value !== true)
        )
          conversationContinuationReadUnavailable()
        // SDK envelope metadata is distinct from the exact private SQL JSON.
        return parseConversationMealContinuationRead(fields.data.value, identity)
      } catch {
        return conversationContinuationReadUnavailable()
      }
    },
  })
}
