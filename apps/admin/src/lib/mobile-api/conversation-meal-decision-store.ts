/** Immutable terminal non-registration. No provider, calculator, registration
 * or automatic recovery/retry belongs to this one-shot service-only adapter. */
import { isDeepStrictEqual } from 'node:util'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationWriterClock } from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

const uuid = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const identitySchema = z
  .object({ ownerId: uuid, commandId: uuid, inputHash: hash, epoch: uuid })
  .strict()
export type ConversationMealDecisionIdentity = Readonly<z.infer<typeof identitySchema>>
export const conversationMealDecisionSchema = z
  .object({
    schema: z.literal('conversation.meal-decision.v1'),
    status: z.literal('not_recorded'),
    reason: z.string().regex(/^[a-z_]{1,80}$/u),
    food_indexes: z
      .array(z.number().int().min(0).max(29))
      .max(30)
      .refine((v) => new Set(v).size === v.length),
  })
  .strict()
export type ConversationMealDecision = Readonly<z.infer<typeof conversationMealDecisionSchema>>
const proofSchema = z.object({ sourceHash: hash, attemptId: uuid, resultHash: hash }).strict()
export type ConversationMealDecisionProof = Readonly<z.infer<typeof proofSchema>>
const receiptSchema = conversationMealDecisionSchema
  .extend({
    owner_id: uuid,
    command_id: uuid,
    epoch: uuid,
    input_hash: hash,
    source_hash: hash,
    attempt_id: uuid,
    semantic_result_hash: hash,
    decision_hash: hash,
    sealed_at: conversationWriterClock,
  })
  .strict()
export type ConversationMealDecisionReceipt = Readonly<z.infer<typeof receiptSchema>>
export type ConversationMealDecisionAvailable = {
  readonly action: 'available' | 'sealed' | 'replay'
  readonly binding: ConversationJournalBinding
  readonly decision: ConversationMealDecisionReceipt
}
export type ConversationMealDecisionRefusal = {
  readonly action:
    | 'absent'
    | 'stale_epoch'
    | 'input_conflict'
    | 'event_conflict'
    | 'source_required'
    | 'source_conflict'
    | 'semantic_required'
    | 'semantic_conflict'
    | 'decision_conflict'
    | 'resolved_conflict'
}
export type ConversationMealDecisionOutcome =
  | ConversationMealDecisionAvailable
  | ConversationMealDecisionRefusal
export interface ConversationMealDecisionStore {
  read(identity: ConversationMealDecisionIdentity): Promise<ConversationMealDecisionOutcome>
  seal(
    identity: ConversationMealDecisionIdentity,
    proof: ConversationMealDecisionProof,
    decision: unknown,
  ): Promise<ConversationMealDecisionOutcome>
}
export function conversationMealDecisionUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_decision_unavailable',
    'The original decision is unavailable',
  )
}
function exact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = structuredClone(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(copy, value)) return conversationMealDecisionUnavailable()
  return value
}
function instant(raw: string): bigint {
  conversationWriterClock.parse(raw)
  const match = /\.(\d{1,9})(?:Z|[+-]\d{2}:\d{2})$/u.exec(raw)
  return BigInt(Date.parse(raw)) * 1000000n + BigInt((match?.[1] ?? '').padEnd(9, '0').slice(3))
}
export function parseConversationMealDecisionReceipt(
  raw: unknown,
  binding: ConversationJournalBinding,
): ConversationMealDecisionReceipt {
  try {
    const v = exact(receiptSchema, raw)
    if (
      v.owner_id !== binding.owner_id ||
      v.command_id !== binding.command_id ||
      v.input_hash !== binding.input_hash ||
      v.epoch !== binding.epoch ||
      instant(v.sealed_at) < instant(binding.admitted_at)
    )
      return conversationMealDecisionUnavailable()
    // SQL validates its canonical checksum. Keep its opaque token: JSONB
    // numeric lexemes such as 0.0 do not survive JavaScript JSON decoding.
    return freezeInterpretation(v)
  } catch {
    return conversationMealDecisionUnavailable()
  }
}
function decode(
  raw: unknown,
  identity: ConversationMealDecisionIdentity,
  actions: readonly string[],
  proof?: ConversationMealDecisionProof,
  submitted?: ConversationMealDecision,
): ConversationMealDecisionOutcome {
  const refusal = z
    .object({
      action: z.enum([
        'absent',
        'stale_epoch',
        'input_conflict',
        'event_conflict',
        'source_required',
        'source_conflict',
        'semantic_required',
        'semantic_conflict',
        'decision_conflict',
        'resolved_conflict',
      ]),
    })
    .strict()
    .safeParse(raw)
  if (refusal.success) {
    if (!actions.includes(refusal.data.action)) return conversationMealDecisionUnavailable()
    return freezeInterpretation(refusal.data)
  }
  const v = exact(
    z
      .object({
        action: z.enum(['available', 'sealed', 'replay']),
        command: conversationJournalBindingSchema,
        decision: z.unknown(),
      })
      .strict(),
    raw,
  )
  const b = v.command
  if (
    !actions.includes(v.action) ||
    b.owner_id !== identity.ownerId ||
    b.command_id !== identity.commandId ||
    b.input_hash !== identity.inputHash ||
    b.epoch !== identity.epoch
  )
    return conversationMealDecisionUnavailable()
  const decision = parseConversationMealDecisionReceipt(v.decision, b)
  if (
    proof &&
    (decision.source_hash !== proof.sourceHash ||
      decision.attempt_id !== proof.attemptId ||
      decision.semantic_result_hash !== proof.resultHash)
  )
    return conversationMealDecisionUnavailable()
  if (
    submitted &&
    !isDeepStrictEqual(
      {
        schema: decision.schema,
        status: decision.status,
        reason: decision.reason,
        food_indexes: decision.food_indexes,
      },
      submitted,
    )
  )
    return conversationMealDecisionUnavailable()
  return freezeInterpretation({ action: v.action, binding: b, decision })
}
export function createSupabaseConversationMealDecisionStore(
  db: ServiceClient,
): ConversationMealDecisionStore {
  type RPC = (
    name: 'read_conversation_meal_decision' | 'seal_conversation_meal_decision',
    args: Record<string, Json>,
  ) => PromiseLike<unknown>
  const rpc = db.rpc.bind(db) as RPC
  async function call(name: Parameters<RPC>[0], args: Parameters<RPC>[1]) {
    const v = z
      .object({ data: z.unknown(), error: z.unknown() })
      .parse(await rpc(name, freezeInterpretation(args)))
    if (v.error !== null) return conversationMealDecisionUnavailable()
    return v.data
  }
  const args = (i: ConversationMealDecisionIdentity) => ({
    p_user_id: i.ownerId,
    p_command_id: i.commandId,
    p_expected_epoch: i.epoch,
    p_expected_input_hash: i.inputHash,
  })
  return Object.freeze({
    async read(rawIdentity: ConversationMealDecisionIdentity) {
      try {
        const identity = exact(identitySchema, rawIdentity)
        return decode(await call('read_conversation_meal_decision', args(identity)), identity, [
          'available',
          'absent',
          'stale_epoch',
          'input_conflict',
          'event_conflict',
        ])
      } catch {
        return conversationMealDecisionUnavailable()
      }
    },
    async seal(
      rawIdentity: ConversationMealDecisionIdentity,
      rawProof: ConversationMealDecisionProof,
      rawDecision: unknown,
    ) {
      try {
        const identity = exact(identitySchema, rawIdentity),
          proof = exact(proofSchema, rawProof),
          decision = exact(conversationMealDecisionSchema, rawDecision)
        return decode(
          await call('seal_conversation_meal_decision', {
            ...args(identity),
            p_expected_source_hash: proof.sourceHash,
            p_attempt_id: proof.attemptId,
            p_expected_result_hash: proof.resultHash,
            p_decision: decision as Json,
          }),
          identity,
          [
            'sealed',
            'replay',
            'absent',
            'stale_epoch',
            'input_conflict',
            'event_conflict',
            'source_required',
            'source_conflict',
            'semantic_required',
            'semantic_conflict',
            'decision_conflict',
            'resolved_conflict',
          ],
          proof,
          decision,
        )
      } catch {
        return conversationMealDecisionUnavailable()
      }
    },
  })
}
