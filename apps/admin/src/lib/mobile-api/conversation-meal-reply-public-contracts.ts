/** Public whitelists for a real linked answer. Historical IDs are never Auth,
 * current question permission, a fake report command or a persistence proof. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { parseConversationMealHistoricalPresentation } from './conversation-meal-command-result'
import {
  bindConversationMealReply,
  parseConversationMealQuestion,
  parseConversationMealReplyBody,
} from './conversation-meal-continuation-input'
import {
  type ConversationMealContinuationReadIdentity,
  type ConversationMealContinuationReadOutcome,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationRead,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import type { ConversationMealContinuationServiceResult } from './conversation-meal-continuation-service'
import type { ConversationMealFeedbackPresentation } from './conversation-meal-feedback-presentation'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  conversationJournalInstant as instant,
  conversationJournalUUID as uuid,
} from './conversation-meal-journal-store'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

type Available = Extract<ConversationMealContinuationReadOutcome, { action: 'available' }>
export type ConversationMealReplyIdentity = ConversationMealContinuationReadIdentity & {
  readonly replyId: string
  readonly replyInputHash: string
}
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const submitSchema = z
  .object({
    schema: z.literal('conversation.meal-reply-submit.v1'),
    reply_id: uuid,
    parent_input_hash: hash,
    parent_decision_hash: hash,
    input: z.unknown(),
  })
  .strict()
export type ConversationMealReplySubmission = Omit<z.infer<typeof submitSchema>, 'input'> & {
  readonly input: ReturnType<typeof parseConversationMealReplyBody>
}
export const conversationMealReplyReason = z.enum([
  'reply_conflict',
  'parent_fulfilled',
  'reply_superseded',
  'awaiting_explicit_resume',
  'ready_for_explicit_resume',
  'question_changed',
  'source_changed',
  'day_closed',
  'nutrition_unresolved',
  'clarification_unavailable',
  'processing_uncertain',
])
export type ConversationMealReplyPublicReason = z.infer<typeof conversationMealReplyReason>
export interface PublicConversationMealReplyResult {
  readonly schema: 'conversation.meal-reply-result.v1'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly parent_command_id: string
  readonly parent_input_hash: string
  readonly parent_decision_hash: string
  readonly reply_id: string
  readonly reply_input_hash: string
  readonly parent_binding: Available['parent']['binding']
  readonly child_binding: NonNullable<Available['reply']>['binding'] | null
  readonly observed_at: string
  readonly status: 'saved' | 'needs_reply' | 'held' | 'reconciliation_required'
  readonly receipt: NonNullable<Available['reply']>['receipt']
  readonly question: Available['head']['question']
  readonly feedback: ConversationMealFeedbackPresentation | null
  readonly reason: ConversationMealReplyPublicReason | null
}
export function conversationMealReplyUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_reply_unavailable',
    'Linked meal reply is unavailable',
  )
}
function invalid(): never {
  throw new MobileApiError(
    422,
    'conversation_meal_reply_invalid',
    'A closed original linked answer is required',
  )
}
export function parseConversationMealReplySubmission(
  raw: unknown,
): ConversationMealReplySubmission {
  try {
    const copy = detachConversationContinuationReadJson(raw),
      v = submitSchema.parse(copy)
    if (Buffer.byteLength(JSON.stringify(copy), 'utf8') > 16384 || !isDeepStrictEqual(copy, v))
      return invalid()
    return freezeInterpretation({ ...v, input: parseConversationMealReplyBody(v.input) })
  } catch {
    return invalid()
  }
}
export function bindConversationMealReplySubmission(raw: {
  ownerId: string
  parentCommandId: string
  epoch: string
  idempotencyKey: string | null
  body: unknown
}) {
  try {
    const v = z
        .object({
          ownerId: uuid,
          parentCommandId: uuid,
          epoch: uuid,
          idempotencyKey: z.string().nullable(),
          body: z.unknown(),
        })
        .strict()
        .parse(detachConversationContinuationReadJson(raw)),
      submission = parseConversationMealReplySubmission(v.body)
    if (submission.reply_id === v.parentCommandId) return invalid()
    const reply = bindConversationMealReply({
      binding: {
        ownerId: v.ownerId,
        parentCommandId: v.parentCommandId,
        parentInputHash: submission.parent_input_hash,
        epoch: v.epoch,
        decisionHash: submission.parent_decision_hash,
      },
      replyId: submission.reply_id,
      input: submission.input,
      idempotencyKey: v.idempotencyKey,
    })
    return freezeInterpretation({ submission, reply })
  } catch {
    return invalid()
  }
}
export function parseConversationMealReplyIdentity(
  raw: ConversationMealContinuationReadIdentity,
): ConversationMealReplyIdentity {
  const i = parseConversationMealContinuationReadIdentity(raw)
  if (!i.replyId || !i.replyInputHash || i.replyId === i.parentCommandId)
    return conversationMealReplyUnavailable()
  return freezeInterpretation({ ...i, replyId: i.replyId, replyInputHash: i.replyInputHash })
}
function outcome(
  raw: unknown,
  i: ConversationMealReplyIdentity,
): ConversationMealContinuationServiceResult | null {
  if (raw === null) return null
  const v = detachConversationContinuationReadJson(raw),
    base = { identity: z.unknown() },
    parsed = z
      .discriminatedUnion('status', [
        z
          .object({
            ...base,
            status: z.literal('saved'),
            receipt: z.unknown(),
            historicalFeedback: z.null(),
            feedbackGate: z.literal('continuation_feedback_v2_unavailable'),
          })
          .strict(),
        z.object({ ...base, status: z.literal('needs_reply'), question: z.unknown() }).strict(),
        z
          .object({
            ...base,
            status: z.literal('held'),
            reason: z.string().regex(/^[a-z_]{1,80}$/u),
          })
          .strict(),
        z
          .object({
            ...base,
            status: z.literal('reconciliation_required'),
            reason: z.string().regex(/^[a-z_]{1,80}$/u),
          })
          .strict(),
      ])
      .parse(v)
  if (
    !isDeepStrictEqual(
      parseConversationMealReplyIdentity(
        parsed.identity as ConversationMealContinuationReadIdentity,
      ),
      i,
    )
  )
    return conversationMealReplyUnavailable()
  if (parsed.status === 'needs_reply') parseConversationMealQuestion(parsed.question)
  return parsed as ConversationMealContinuationServiceResult
}
function safeReason(reason: string): ConversationMealReplyPublicReason {
  if (reason === 'question_conflict' || reason === 'meal_type_conflict') return 'question_changed'
  if (reason === 'source_conflict') return 'source_changed'
  const p = conversationMealReplyReason.safeParse(reason)
  return p.success ? p.data : 'clarification_unavailable'
}
function samePolicy(
  a: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
  b: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
) {
  const { observed_at: _a, ...left } = a,
    { observed_at: _b, ...right } = b
  return isDeepStrictEqual(left, right)
}
export interface ConversationMealReplyProjection {
  readonly auth: MobileAuthContext
  readonly identity: ConversationMealReplyIdentity
  readonly proof: {
    readonly kind: 'reply' | 'parent_only_after_reply_conflict'
    readonly state: unknown
  }
  readonly observation: unknown
  readonly mode: 'read' | 'submit'
  readonly outcome: unknown
  readonly feedback: unknown
}
function projectionInput(raw: ConversationMealReplyProjection) {
  const fields = Object.getOwnPropertyDescriptors(raw),
    allowed = new Set(['auth', 'identity', 'proof', 'observation', 'mode', 'outcome', 'feedback']),
    core: Record<string, unknown> = {}
  for (const key of Reflect.ownKeys(fields)) {
    if (typeof key !== 'string' || !allowed.has(key)) return conversationMealReplyUnavailable()
  }
  for (const key of ['auth', 'identity', 'proof', 'observation', 'mode', 'outcome']) {
    const d = fields[key]
    if (!d?.enumerable || !('value' in d)) return conversationMealReplyUnavailable()
    Object.defineProperty(core, key, { enumerable: true, value: d.value })
  }
  const optional = fields.feedback
  return {
    input: detachConversationContinuationReadJson(core) as Omit<
      ConversationMealReplyProjection,
      'feedback'
    >,
    optionalFeedback: optional?.enumerable && 'value' in optional ? optional.value : null,
  }
}
export function projectConversationMealReplyResult(
  raw: ConversationMealReplyProjection,
): PublicConversationMealReplyResult {
  try {
    const { input, optionalFeedback } = projectionInput(raw),
      auth = input.auth,
      owner = authenticatedReevaluationOwner(auth),
      i = parseConversationMealReplyIdentity(input.identity),
      profile = readCurrentClinicalState(input.observation, owner)
    if (
      owner !== i.ownerId ||
      profile.epoch !== i.epoch ||
      !['read', 'submit'].includes(input.mode) ||
      !['reply', 'parent_only_after_reply_conflict'].includes(input.proof.kind)
    )
      return conversationMealReplyUnavailable()
    const parentOnly = input.proof.kind === 'parent_only_after_reply_conflict',
      readIdentity = parentOnly
        ? {
            ownerId: i.ownerId,
            parentCommandId: i.parentCommandId,
            parentInputHash: i.parentInputHash,
            epoch: i.epoch,
          }
        : i,
      state = parseConversationMealContinuationRead(input.proof.state, readIdentity)
    if (state.action !== 'available' || instant(profile.observed_at) < instant(state.observed_at))
      return conversationMealReplyUnavailable()
    const r = state.reply,
      o = outcome(input.outcome, i)
    let status: PublicConversationMealReplyResult['status'] = 'held',
      reason: ConversationMealReplyPublicReason | null = 'awaiting_explicit_resume',
      receipt: PublicConversationMealReplyResult['receipt'] = null,
      question: Available['head']['question'] = null,
      feedback: ConversationMealFeedbackPresentation | null = null
    if (parentOnly) {
      status = 'reconciliation_required'
      reason = 'reply_conflict'
    } else if (r?.state === 'saved' && r.receipt) {
      if (
        !state.fulfillment ||
        state.fulfillment.child_binding.command_id !== i.replyId ||
        !isDeepStrictEqual(state.fulfillment.receipt, r.receipt) ||
        (o?.status === 'saved' && !isDeepStrictEqual(o.receipt, r.receipt))
      )
        return conversationMealReplyUnavailable()
      status = 'saved'
      reason = null
      receipt = r.receipt
      const supplied = parseConversationMealHistoricalPresentation(optionalFeedback, {
        ownerId: owner,
        commandId: r.binding.command_id,
        epoch: i.epoch,
        admittedAt: r.binding.admitted_at,
        receipt: {
          registration_id: receipt.registration_id,
          local_date: receipt.local_date,
          meal_type: receipt.meal_type,
          log_ids: receipt.log_ids,
        },
      })
      if (
        supplied &&
        samePolicy(supplied.current_policy, projectCurrentClinicalPublicPolicy(profile)) &&
        instant(supplied.provenance.observed_at) >= instant(state.observed_at) &&
        instant(supplied.provenance.observed_at) <= instant(profile.observed_at) &&
        instant(supplied.provenance.observed_at) >= instant(receipt.consumed_at)
      )
        feedback = supplied
    } else {
      if (o?.status === 'saved') return conversationMealReplyUnavailable()
      if (
        r?.state === 'awaiting_reply' &&
        state.head.fulfilled_by === null &&
        state.head.question
      ) {
        status = 'needs_reply'
        reason = null
        question = state.head.question
      } else if (r?.state === 'superseded') {
        reason = 'reply_superseded'
      } else if (state.head.fulfilled_by !== null) {
        reason = 'parent_fulfilled'
      } else if (input.mode === 'read') {
        reason = r?.state === 'prepared' ? 'ready_for_explicit_resume' : 'awaiting_explicit_resume'
      } else if (o?.status === 'held') {
        reason = safeReason(o.reason)
      } else {
        status = 'reconciliation_required'
        reason = 'processing_uncertain'
      }
    }
    let result: PublicConversationMealReplyResult = {
      schema: 'conversation.meal-reply-result.v1',
      auth_user_id: uuid.parse(auth.authUserId),
      owner_id: owner,
      epoch: i.epoch,
      parent_command_id: i.parentCommandId,
      parent_input_hash: i.parentInputHash,
      parent_decision_hash: state.parent.decision.decision_hash,
      reply_id: i.replyId,
      reply_input_hash: i.replyInputHash,
      parent_binding: state.parent.binding,
      child_binding: parentOnly ? null : (r?.binding ?? null),
      observed_at: profile.observed_at,
      status,
      receipt,
      question,
      feedback,
      reason,
    }
    if (Buffer.byteLength(JSON.stringify(result), 'utf8') > 240000) {
      result = { ...result, feedback: null }
      if (Buffer.byteLength(JSON.stringify(result), 'utf8') > 240000)
        return conversationMealReplyUnavailable()
    }
    return freezeInterpretation(result)
  } catch {
    return conversationMealReplyUnavailable()
  }
}
