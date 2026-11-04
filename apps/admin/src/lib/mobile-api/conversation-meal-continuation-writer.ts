/** Private one-write/one-read bridge. Only an actual closed post-write read
 * proves the requested durable state. No synthetic receipt, clock, child-v1
 * command, source capture, model invocation, automatic retry or public route. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import {
  type BoundConversationMealReply,
  bindConversationMealReply,
} from './conversation-meal-continuation-input'
import {
  type ConversationMealContinuationReadIdentity,
  type ConversationMealContinuationReadOutcome,
  conversationContinuationReadUnavailable,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationPreparationShape,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import { createSupabaseConversationMealContinuationReadStore } from './conversation-meal-continuation-read-store'

type Available = Extract<ConversationMealContinuationReadOutcome, { action: 'available' }>
type ReplyIdentity = ConversationMealContinuationReadIdentity & {
  readonly replyId: string
  readonly replyInputHash: string
}
const refusals = new Set([
  'absent',
  'stale_epoch',
  'input_conflict',
  'ineligible',
  'reply_conflict',
  'event_conflict',
  'decision_conflict',
  'question_conflict',
  'source_conflict',
  'day_closed',
  'prepared_required',
  'prepared_conflict',
])
export type ConversationMealContinuationWriteOutcome =
  | { readonly status: 'observed'; readonly state: Available }
  | {
      readonly status: 'reconciliation_required'
      readonly state: ConversationMealContinuationReadOutcome | null
      readonly refusal: string | null
    }
export interface ConversationMealContinuationWriter {
  read(
    identity: ConversationMealContinuationReadIdentity,
  ): Promise<ConversationMealContinuationReadOutcome>
  admit(reply: BoundConversationMealReply): Promise<ConversationMealContinuationWriteOutcome>
  prepare(
    identity: ConversationMealContinuationReadIdentity,
    preparation: unknown,
  ): Promise<ConversationMealContinuationWriteOutcome>
  commit(
    identity: ConversationMealContinuationReadIdentity,
    preparedHash: string,
  ): Promise<ConversationMealContinuationWriteOutcome>
}
function replyIdentity(raw: ConversationMealContinuationReadIdentity): ReplyIdentity {
  const v = parseConversationMealContinuationReadIdentity(raw)
  if (!v.replyId || !v.replyInputHash || v.replyId === v.parentCommandId)
    return conversationContinuationReadUnavailable()
  return Object.freeze({ ...v, replyId: v.replyId, replyInputHash: v.replyInputHash })
}
function args(i: ReplyIdentity) {
  return Object.freeze({
    p_user_id: i.ownerId,
    p_parent_command_id: i.parentCommandId,
    p_parent_input_hash: i.parentInputHash,
    p_expected_epoch: i.epoch,
    p_reply_id: i.replyId,
    p_reply_input_hash: i.replyInputHash,
  })
}
/** Rich mutation return values are deliberately never used as authority.
 * A closed refusal is useful diagnostics only, after the actual read fails to
 * prove the requested state. No getters from a damaged SDK envelope execute. */
function refusal(raw: unknown): string | null {
  try {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
    const fields = Object.getOwnPropertyDescriptors(raw)
    if (
      !fields.data ||
      !fields.error ||
      !('value' in fields.data) ||
      !('value' in fields.error) ||
      fields.error.value !== null
    )
      return null
    const value = detachConversationContinuationReadJson(fields.data.value)
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null
    const record = value as Record<string, unknown>
    return Object.keys(record).length === 1 &&
      typeof record.action === 'string' &&
      refusals.has(record.action)
      ? record.action
      : null
  } catch {
    return null
  }
}
export function createSupabaseConversationMealContinuationWriter(
  db: ServiceClient,
): ConversationMealContinuationWriter {
  const rpc = db.rpc.bind(db) as (
    name:
      | 'admit_conversation_meal_reply'
      | 'prepare_conversation_meal_continuation'
      | 'commit_conversation_meal_continuation',
    parameters: Readonly<Record<string, unknown>>,
  ) => PromiseLike<unknown>
  const reader = createSupabaseConversationMealContinuationReadStore(db)
  const read = reader.read.bind(reader)
  async function execute(
    name: Parameters<typeof rpc>[0],
    parameters: Readonly<Record<string, unknown>>,
    identity: ReplyIdentity,
    proves: (state: Available) => boolean,
  ): Promise<ConversationMealContinuationWriteOutcome> {
    let reason: string | null = null
    try {
      reason = refusal(await rpc(name, parameters))
    } catch {
      // The same identity may already have committed. Never issue a second POST.
    }
    let state: ConversationMealContinuationReadOutcome | null = null
    try {
      state = await read(identity)
    } catch {
      // A later explicit reconciliation still uses the same immutable identity.
    }
    return state?.action === 'available' && proves(state)
      ? Object.freeze({ status: 'observed', state })
      : Object.freeze({ status: 'reconciliation_required', state, refusal: reason })
  }
  return Object.freeze({
    read,
    async admit(rawReply: BoundConversationMealReply) {
      const detached = detachConversationContinuationReadJson(
        rawReply,
      ) as BoundConversationMealReply
      const bound = bindConversationMealReply({
        binding: detached.binding,
        replyId: detached.replyId,
        input: detached.input,
        idempotencyKey: detached.idempotencyKey,
      })
      if (!isDeepStrictEqual(bound, detached)) conversationContinuationReadUnavailable()
      const identity = replyIdentity({
        ownerId: bound.binding.ownerId,
        parentCommandId: bound.binding.parentCommandId,
        parentInputHash: bound.binding.parentInputHash,
        epoch: bound.binding.epoch,
        replyId: bound.replyId,
        replyInputHash: bound.inputHash,
      })
      return execute(
        'admit_conversation_meal_reply',
        Object.freeze({
          p_user_id: identity.ownerId,
          p_parent_command_id: identity.parentCommandId,
          p_parent_input_hash: identity.parentInputHash,
          p_expected_epoch: identity.epoch,
          p_parent_decision_hash: bound.binding.decisionHash,
          p_reply_id: identity.replyId,
          p_input: bound.input,
        }),
        identity,
        (s) =>
          s.reply !== null &&
          isDeepStrictEqual(s.reply.body, bound.input) &&
          s.parent.decision.decision_hash === bound.binding.decisionHash,
      )
    },
    async prepare(rawIdentity: ConversationMealContinuationReadIdentity, rawPreparation: unknown) {
      const identity = replyIdentity(rawIdentity)
      const preparation = parseConversationMealContinuationPreparationShape(rawPreparation)
      if (
        preparation.input_hash !== identity.replyInputHash ||
        preparation.parent_ref.command_id !== identity.parentCommandId ||
        preparation.parent_ref.input_hash !== identity.parentInputHash
      )
        conversationContinuationReadUnavailable()
      return execute(
        'prepare_conversation_meal_continuation',
        Object.freeze({
          ...args(identity),
          p_preparation: preparation,
        }),
        identity,
        (s) =>
          s.reply?.preparation !== null &&
          isDeepStrictEqual(s.reply?.preparation?.preparation, preparation),
      )
    },
    async commit(rawIdentity: ConversationMealContinuationReadIdentity, preparedHash: string) {
      const identity = replyIdentity(rawIdentity)
      if (typeof preparedHash !== 'string' || !/^[a-f0-9]{64}$/u.test(preparedHash))
        conversationContinuationReadUnavailable()
      return execute(
        'commit_conversation_meal_continuation',
        Object.freeze({
          ...args(identity),
          p_prepared_hash: preparedHash,
        }),
        identity,
        (s) =>
          s.reply?.preparation?.prepared_hash === preparedHash &&
          s.reply?.receipt !== null &&
          s.reply?.state === 'saved' &&
          s.fulfillment?.child_binding.command_id === identity.replyId,
      )
    },
  })
}
