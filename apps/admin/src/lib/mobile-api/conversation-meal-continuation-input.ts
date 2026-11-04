/** Closed linked-reply intent and server question data only. Parsing/binding
 * supplies no Auth, parent-proof, current-head, write or calculation authority. */
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  conversationOperationCanonicalJson,
  detachConversationMealEditJson,
} from './conversation-meal-edit-contracts'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import { mobileQuantityDisplay } from './mobile-quantity-display'

const uuid = z
  .string()
  .length(36)
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const hash = z
  .string()
  .length(64)
  .regex(/^[0-9a-f]{64}$/u)
const revision = z.number().finite().int().min(0).max(2147483647)
const foodIndex = z.number().finite().int().min(0).max(29)
const unit = z.enum(['g', 'kg', 'mL', 'L', 'unit', 'scoop', 'caneca'])
const mealType = z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
const answer = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('quantity'),
      food_index: foodIndex,
      amount: z.number().finite().positive().max(9999),
      unit,
    })
    .strict(),
  z.object({ kind: z.literal('meal_type'), meal_type: mealType }).strict(),
])
const bodySchema = z
  .object({
    schema: z.literal('conversation.meal-clarification.v1'),
    expected_revision: revision,
    question_key: hash,
    answer,
  })
  .strict()
export type ConversationMealReplyBody = Readonly<z.infer<typeof bodySchema>>
const bindingSchema = z
  .object({
    ownerId: uuid,
    parentCommandId: uuid,
    parentInputHash: hash,
    epoch: uuid,
    decisionHash: hash,
  })
  .strict()
export type ConversationMealReplyBinding = Readonly<z.infer<typeof bindingSchema>>
export interface BoundConversationMealReply {
  readonly binding: ConversationMealReplyBinding
  readonly replyId: string
  readonly input: ConversationMealReplyBody
  readonly inputHash: string
  readonly idempotencyKey: string
}
const referenceSchema = z
  .object({
    unit: z.enum(['mL', 'unit', 'scoop']),
    grams_per_unit: z.number().finite().positive(),
    reference_id: z.string().min(1).max(240),
    estimated: z.literal(true),
  })
  .strict()
const foodName = z
  .string()
  .min(1)
  .max(160)
  .refine(
    (s) =>
      s.trim().length > 0 &&
      !Array.from(s).some((character) => {
        const code = character.charCodeAt(0)
        return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
      }),
  )
const questionBase = {
  schema: z.literal('conversation.meal-question.v1'),
  question_key: hash,
  revision,
}
const questionSchema = z.discriminatedUnion('kind', [
  z
    .object({
      ...questionBase,
      kind: z.literal('quantity'),
      food_index: foodIndex,
      food_name: foodName,
      allowed_units: z
        .array(unit)
        .min(2)
        .max(7)
        .refine((v) => new Set(v).size === v.length),
      quantity_reference: referenceSchema.nullable(),
    })
    .strict(),
  z
    .object({
      ...questionBase,
      kind: z.literal('meal_type'),
      food_index: z.null(),
      food_name: z.null(),
      allowed_units: z.array(unit).length(0),
      quantity_reference: z.null(),
    })
    .strict(),
])
export type ConversationMealQuestion = Readonly<z.infer<typeof questionSchema>>
export type ConversationMealContinuationInputCode =
  | 'invalid_reply'
  | 'invalid_binding'
  | 'invalid_question'
  | 'question_conflict'
/** A caller maps this private validation result to its own transport policy. */
export class ConversationMealContinuationInputError extends Error {
  constructor(readonly code: ConversationMealContinuationInputCode) {
    super('Meal clarification data is unavailable')
    this.name = 'ConversationMealContinuationInputError'
  }
}
function fail(code: ConversationMealContinuationInputCode): never {
  throw new ConversationMealContinuationInputError(code)
}
function closed<T>(
  schema: z.ZodType<T>,
  raw: unknown,
  code: ConversationMealContinuationInputCode,
): T {
  try {
    const copy = detachConversationMealEditJson(raw),
      value = schema.parse(copy)
    if (!isDeepStrictEqual(copy, value)) return fail(code)
    return freezeConversationWriter(value)
  } catch {
    return fail(code)
  }
}
export function parseConversationMealReplyBody(raw: unknown): ConversationMealReplyBody {
  const input = closed(bodySchema, raw, 'invalid_reply')
  // First wire bound only; SQL remains authority for its jsonb text bound.
  if (Buffer.byteLength(JSON.stringify(input), 'utf8') > 16384) return fail('invalid_reply')
  return input
}
export function bindConversationMealReply(raw: {
  binding: ConversationMealReplyBinding
  replyId: string
  input: unknown
  idempotencyKey: string | null
}): BoundConversationMealReply {
  const value = closed(
    z
      .object({
        binding: bindingSchema,
        replyId: uuid,
        input: z.unknown(),
        idempotencyKey: z.string().nullable(),
      })
      .strict(),
    raw,
    'invalid_binding',
  )
  if (value.idempotencyKey !== `cmreply1:${value.replyId}`) return fail('invalid_binding')
  const input = parseConversationMealReplyBody(value.input)
  return freezeConversationWriter({
    binding: value.binding,
    replyId: value.replyId,
    input,
    inputHash: createHash('sha256').update(conversationOperationCanonicalJson(input)).digest('hex'),
    idempotencyKey: value.idempotencyKey,
  })
}
export function parseConversationMealQuestion(raw: unknown): ConversationMealQuestion {
  const question = closed(questionSchema, raw, 'invalid_question')
  if (question.kind === 'meal_type') return question
  const reference = mobileQuantityDisplay(question.food_name)
  const allowed: z.infer<typeof unit>[] = ['g', 'kg']
  if (reference?.unit === 'mL') {
    allowed.push('mL', 'L')
    if (reference.reference_id === 'fao-infoods-v2-whole-milk-tb') allowed.push('caneca')
  } else if (reference) allowed.push(reference.unit)
  // SQL derives this exact ordered list and the same whole-name reference.
  // Lookup normalization never changes the original name returned to caller.
  if (
    !isDeepStrictEqual(question.quantity_reference, reference) ||
    !isDeepStrictEqual(question.allowed_units, allowed)
  )
    return fail('invalid_question')
  return question
}
export function validateConversationMealReplyQuestion(
  rawInput: unknown,
  rawQuestion: unknown,
): void {
  const input = parseConversationMealReplyBody(rawInput),
    question = parseConversationMealQuestion(rawQuestion)
  if (
    input.expected_revision !== question.revision ||
    input.question_key !== question.question_key ||
    input.answer.kind !== question.kind
  )
    fail('question_conflict')
  if (
    input.answer.kind === 'quantity' &&
    question.kind === 'quantity' &&
    (input.answer.food_index !== question.food_index ||
      !question.allowed_units.includes(input.answer.unit))
  )
    fail('question_conflict')
}
