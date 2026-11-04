/** Private dormant command-only adapter. Frozen originals are not current
 * clinical authority or a public presentation. No domain writer is called. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  parseRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import { MobileApiError } from './http'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import {
  type FeedbackV2Observation,
  parseFeedbackV2Capture,
} from './registration-feedback-v2-store'

const uuid = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.string(), z.number().finite(), z.array(json), z.record(json)]),
)
const receiptSchema = z
  .object({
    schema: z.literal('conversation.meal-effect.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: z.string().regex(/^[a-f0-9]{64}$/u),
    registration_id: uuid,
    provider_key: z.string(),
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
    local_date: z.string().date(),
    timezone: z.string().min(1),
    consumed_at: z.string().datetime({ offset: true }),
    log_ids: z.array(uuid).min(1).max(30),
    effect_version: z.string().regex(/^cmeal1:[a-f0-9]{64}$/u),
  })
  .strict()
export type ConversationMealEffectReceipt = Readonly<z.infer<typeof receiptSchema>>
export interface ConversationMealFeedbackBinding {
  readonly command: BoundConversationMealCommand
  /** Actual mandatory SQL effect receipt; never accepted from a mobile body. */
  readonly receipt: unknown
}
export type ConversationMealFeedbackSource =
  | {
      action: 'available'
      receipt: ConversationMealEffectReceipt
      originalObservation: FeedbackV2Observation
    }
  | {
      action: 'unavailable'
      reason: 'original_context_unavailable'
      receipt: ConversationMealEffectReceipt
    }
  | { action: 'absent' | 'stale_epoch' }
export type ConversationMealFeedbackRead =
  | { action: 'available'; feedback: RegistrationFeedbackV2 }
  | { action: 'legacy'; feedback: RegistrationFeedback }
  | { action: 'absent' | 'stale_epoch' | 'event_conflict' }
export type ConversationMealFeedbackCommit =
  | { action: 'committed' | 'replay'; feedback: RegistrationFeedbackV2 }
  | { action: 'legacy'; feedback: RegistrationFeedback }
  | {
      action: 'unavailable'
      reason: 'original_context_unavailable'
      receipt: ConversationMealEffectReceipt
    }
  | { action: 'absent' | 'stale_epoch' | 'source_conflict' | 'event_conflict' }
export interface ConversationMealFeedbackStore {
  readSource(command: BoundConversationMealCommand): Promise<ConversationMealFeedbackSource>
  readReceipt(binding: ConversationMealFeedbackBinding): Promise<ConversationMealFeedbackRead>
  commit(
    input: ConversationMealFeedbackBinding & { readonly feedback: unknown },
  ): Promise<ConversationMealFeedbackCommit>
}
class FeedbackFailure extends MobileApiError {
  constructor() {
    super(503, 'conversation_meal_feedback_unavailable', 'Command feedback is unavailable')
  }
}
function invalid(): never {
  throw new FeedbackFailure()
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function detach<T>(value: T): T {
  return freeze(structuredClone(value))
}
function commandBinding(raw: BoundConversationMealCommand): BoundConversationMealCommand {
  const copy = structuredClone(raw),
    result = bindConversationCommand(copy.ownerId, `cmsg1:${copy.commandId}`, copy.command)
  if (!isDeepStrictEqual(result, copy)) return invalid()
  return detach(result)
}
function effect(
  raw: unknown,
  command: BoundConversationMealCommand,
): ConversationMealEffectReceipt {
  const copy = structuredClone(raw),
    value = receiptSchema.parse(copy)
  if (
    !isDeepStrictEqual(copy, value) ||
    value.owner_id !== command.ownerId ||
    value.command_id !== command.commandId ||
    value.input_hash !== command.inputHash ||
    value.provider_key !== `conversation.meal/${command.ownerId}/${command.commandId}` ||
    new Set(value.log_ids).size !== value.log_ids.length ||
    (command.command.meal_type !== undefined && value.meal_type !== command.command.meal_type) ||
    getLocalDateString(value.timezone, new Date(value.consumed_at)) !== value.local_date
  )
    return invalid()
  return freeze(value)
}
function bind(raw: ConversationMealFeedbackBinding) {
  const command = commandBinding(raw.command),
    receipt = effect(raw.receipt, command)
  return {
    command,
    receipt,
    identity: {
      userId: command.ownerId,
      registrationId: receipt.registration_id,
      kind: 'meal' as const,
    },
  }
}
function data(raw: unknown): unknown {
  const value = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (value.error !== null) return invalid()
  return structuredClone(value.data)
}
function sameIDs(a: readonly string[], b: readonly string[]): boolean {
  return isDeepStrictEqual([...a].sort(), [...b].sort())
}
function v2(raw: unknown, binding: ReturnType<typeof bind>): RegistrationFeedbackV2 {
  const result = parseRegistrationFeedbackV2(raw, binding.identity)
  if (
    result.local_date !== binding.receipt.local_date ||
    result.registration.kind !== 'meal' ||
    result.registration.meal_kind !== binding.receipt.meal_type ||
    !sameIDs(
      result.registration.items.map((item) => item.log_id),
      binding.receipt.log_ids,
    )
  )
    return invalid()
  return detach(result)
}
const absent = z.object({ action: z.literal('absent') }).strict()
const stale = z.object({ action: z.literal('stale_epoch') }).strict()
const eventConflict = z.object({ action: z.literal('event_conflict') }).strict()
const sourceConflict = z.object({ action: z.literal('source_conflict') }).strict()
const unavailable = z
  .object({
    action: z.literal('unavailable'),
    reason: z.literal('original_context_unavailable'),
    receipt: z.unknown(),
  })
  .strict()
const legacy = z.object({ action: z.literal('legacy'), feedback: z.unknown() }).strict()

export function createSupabaseConversationMealFeedbackStore(
  db: ServiceClient,
): ConversationMealFeedbackStore {
  const rpc = db.rpc.bind(db)
  return Object.freeze({
    async readSource(
      original: BoundConversationMealCommand,
    ): Promise<ConversationMealFeedbackSource> {
      try {
        const command = commandBinding(original)
        const result = z
          .discriminatedUnion('action', [
            z
              .object({
                action: z.literal('available'),
                receipt: z.unknown(),
                context: z.unknown(),
              })
              .strict(),
            unavailable,
            absent,
            stale,
          ])
          .parse(
            data(
              await rpc('read_conversation_meal_feedback_source', {
                p_user_id: command.ownerId,
                p_command_id: command.commandId,
              }),
            ),
          )
        if (result.action === 'absent' || result.action === 'stale_epoch') return freeze(result)
        const receipt = effect(result.receipt, command)
        if (result.action === 'unavailable')
          return freeze({ action: result.action, reason: result.reason, receipt })
        const originalObservation = parseFeedbackV2Capture(result.context, {
          userId: command.ownerId,
          registrationId: receipt.registration_id,
          kind: 'meal',
        })
        const c = originalObservation.context,
          proposal = c.confirmed.proposal
        if (
          !isDeepStrictEqual(c, result.context) ||
          proposal === null ||
          Array.isArray(proposal) ||
          typeof proposal !== 'object' ||
          proposal.command_protocol !== 'conversation.command.v1' ||
          proposal.command_id !== command.commandId ||
          proposal.source_provider_message_id !== receipt.provider_key ||
          proposal.source_timestamp !== receipt.consumed_at ||
          proposal.source_timezone !== receipt.timezone ||
          proposal.mealType !== receipt.meal_type ||
          originalObservation.facts.localDate !== receipt.local_date ||
          !sameIDs(originalObservation.facts.logIds, receipt.log_ids)
        )
          return invalid()
        return freeze({ action: 'available', receipt, originalObservation })
      } catch {
        return invalid()
      }
    },
    async readReceipt(
      input: ConversationMealFeedbackBinding,
    ): Promise<ConversationMealFeedbackRead> {
      try {
        const b = bind(input)
        const result = z
          .discriminatedUnion('action', [
            z.object({ action: z.literal('available'), feedback: z.unknown() }).strict(),
            legacy,
            absent,
            stale,
            eventConflict,
          ])
          .parse(
            data(
              await rpc('read_conversation_meal_feedback_v2', {
                p_user_id: b.command.ownerId,
                p_command_id: b.command.commandId,
              }),
            ),
          )
        if (result.action === 'available')
          return freeze({ action: result.action, feedback: v2(result.feedback, b) })
        if (result.action === 'legacy')
          return freeze({
            action: result.action,
            feedback: detach(parseRegistrationFeedback(result.feedback, b.identity)),
          })
        return freeze(result)
      } catch {
        return invalid()
      }
    },
    async commit(
      input: ConversationMealFeedbackBinding & { readonly feedback: unknown },
    ): Promise<ConversationMealFeedbackCommit> {
      try {
        const b = bind(input),
          proposed = structuredClone(input.feedback)
        // Validate JSON transportability only. SQL must fence epoch and replay
        // the first v1/v2 winner before inspecting a proposed v2 DTO/version.
        json.parse(proposed)
        const result = z
          .discriminatedUnion('action', [
            z.object({ action: z.enum(['committed', 'replay']), feedback: z.unknown() }).strict(),
            legacy,
            unavailable,
            absent,
            stale,
            sourceConflict,
            eventConflict,
          ])
          .parse(
            data(
              await rpc('commit_conversation_meal_feedback_v2', {
                p_user_id: b.command.ownerId,
                p_command_id: b.command.commandId,
                p_expected_effect_version: b.receipt.effect_version,
                p_feedback: proposed as Json,
              }),
            ),
          )
        if (result.action === 'unavailable') {
          const receipt = effect(result.receipt, b.command)
          if (!isDeepStrictEqual(receipt, b.receipt)) return invalid()
          return freeze({ action: result.action, reason: result.reason, receipt })
        }
        if (result.action === 'legacy')
          return freeze({
            action: result.action,
            feedback: detach(parseRegistrationFeedback(result.feedback, b.identity)),
          })
        if (
          result.action === 'absent' ||
          result.action === 'stale_epoch' ||
          result.action === 'source_conflict' ||
          result.action === 'event_conflict'
        )
          return freeze({ action: result.action })
        const saved = v2(result.feedback, b)
        if (result.action === 'committed' && !isDeepStrictEqual(saved, proposed)) return invalid()
        return freeze({ action: result.action, feedback: saved })
      } catch {
        return invalid()
      }
    },
  })
}
