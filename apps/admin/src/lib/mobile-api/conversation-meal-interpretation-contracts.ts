/** Closed private interpretation DTOs. Neither shape nor model agreement is a
 * SQL consumption proof. Only backend-owned source/identity can build input. */
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import type { Json } from '@mpp/db'
import { z } from 'zod'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
  conversationMealCommandSchema,
} from './conversation-command-contracts'
import { MobileApiError } from './http'

export const MEAL_INTERPRETER_VERSION = 'conversation.meal-interpreter.v1' as const
export const MEAL_INTERPRETATION_MAX_BYTES = 131_072
export const mealInterpretationUnitSchema = z.enum([
  'command_text',
  'media_caption',
  'media_transcript',
  'vision_items',
])
export type MealInterpretationUnit = z.infer<typeof mealInterpretationUnitSchema>
const textUnit = z.enum(['command_text', 'media_caption', 'media_transcript'])
const uuid = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const integer = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER)
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.string(), z.number().finite(), z.array(json), z.record(json)]),
)
export const interpretationReferenceSchema = z
  .object({ unit: textUnit, start: integer, end: integer })
  .strict()
export const interpretationModelSchema = z
  .object({
    schema: z.literal('conversation.meal-interpretation.v1'),
    decision: z.enum(['reported_meal', 'not_reported', 'clarification_required']),
    reason: z.enum([
      'explicit_report',
      'nominal_food_list',
      'explicit_media_action',
      'dream',
      'future',
      'habit',
      'negated',
      'third_party',
      'question',
      'mixed',
      'ambiguous',
    ]),
    sources: z
      .array(
        z
          .object({
            unit: mealInterpretationUnitSchema,
            classification: z.enum([
              'reported',
              'nominal_list',
              'media_pointer',
              'visual',
              'dream',
              'future',
              'habit',
              'negated',
              'third_party',
              'question',
              'mixed',
              'ambiguous',
            ]),
            spans: z
              .array(
                z
                  .object({
                    start: integer,
                    end: integer,
                    kind: z.enum(['food', 'quantity', 'unit', 'report', 'separator', 'other']),
                    food_index: integer.max(29).nullable(),
                  })
                  .strict(),
              )
              .max(4096),
            visual_indexes: z.array(integer.max(29)).max(30),
          })
          .strict(),
      )
      .min(1)
      .max(4),
    foods: z
      .array(
        z
          .object({
            index: integer.max(29),
            name: interpretationReferenceSchema.nullable(),
            quantity: interpretationReferenceSchema.nullable(),
            unit: interpretationReferenceSchema.nullable(),
            visual_index: integer.max(29).nullable(),
          })
          .strict(),
      )
      .max(30),
  })
  .strict()
export type MealInterpretationModelResult = z.infer<typeof interpretationModelSchema>
export const mealInterpretationSchema = interpretationModelSchema
  .extend({
    interpreter_version: z.literal(MEAL_INTERPRETER_VERSION),
    owner_id: uuid,
    command_id: uuid,
    attempt_id: uuid,
    input_hash: hash,
    source_hash: hash,
    source_units: z.array(mealInterpretationUnitSchema).min(1).max(4),
    provider_metadata: z
      .object({
        model: z.string().min(1).max(128),
        prompt_tokens: integer,
        completion_tokens: integer,
        cost_usd: z.number().finite().nonnegative().nullable(),
        latency_ms: integer,
      })
      .strict(),
  })
  .strict()
export type ConversationMealInterpretation = z.infer<typeof mealInterpretationSchema>
export interface MealInterpretationBinding {
  ownerId: string
  commandId: string
  attemptId: string
  inputHash: string
  sourceHash: string
}
/** Closed replay decoding of a trusted SQL-sealed result. This header parser
 * does not validate arbitrary model output or replace frozen-source provenance. */
export function parseConversationMealInterpretation(
  raw: unknown,
  binding: MealInterpretationBinding,
): ConversationMealInterpretation {
  try {
    const who = z
      .object({
        ownerId: uuid,
        commandId: uuid,
        attemptId: uuid,
        inputHash: hash,
        sourceHash: hash,
      })
      .strict()
      .parse(structuredClone(binding))
    const copy = structuredClone(raw),
      value = mealInterpretationSchema.parse(copy)
    if (
      !isDeepStrictEqual(value, copy) ||
      value.owner_id !== who.ownerId ||
      value.command_id !== who.commandId ||
      value.attempt_id !== who.attemptId ||
      value.input_hash !== who.inputHash ||
      value.source_hash !== who.sourceHash ||
      !isDeepStrictEqual(
        value.source_units,
        value.sources.map((s) => s.unit),
      ) ||
      new Set(value.source_units).size !== value.source_units.length ||
      Buffer.byteLength(JSON.stringify(value), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
    )
      return interpretationUnavailable()
    return freezeInterpretation(value)
  } catch {
    return interpretationUnavailable()
  }
}
const mediaSchema = z
  .object({
    asset_id: uuid,
    kind: z.enum(['meal_photo', 'audio_note']),
    status: z.literal('processed'),
    processed_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }),
    processing_result: json,
    context_text: z.string().nullable(),
  })
  .strict()
export const mealInterpretationSourceSchema = z
  .object({
    schema: z.literal('conversation.meal-interpretation-source.v1'),
    interpreter_version: z.literal(MEAL_INTERPRETER_VERSION),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    source_hash: hash,
    epoch: uuid,
    captured_at: z.string().datetime({ offset: true }),
    media_binding: z
      .object({
        asset_id: uuid,
        kind: z.enum(['meal_photo', 'audio_note']),
        processed_at: z.string(),
        updated_at: z.string(),
        processing_hash: hash,
      })
      .strict()
      .nullable(),
    source_units: z.array(mealInterpretationUnitSchema).min(1).max(4),
    sources: z
      .array(
        z
          .object({
            unit: mealInterpretationUnitSchema,
            text: z.string().max(2000).nullable(),
            visual_items: z.array(json).max(30),
          })
          .strict(),
      )
      .min(1)
      .max(4),
  })
  .strict()
export type ConversationMealInterpretationSource = z.infer<typeof mealInterpretationSourceSchema>
export interface CapturedMealInterpretationSource {
  readonly sourceHash: string
  readonly capturedAt: string
  readonly epoch: string
  readonly context: Readonly<Record<string, unknown>>
}
export function interpretationUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_interpretation_unavailable',
    'Meal interpretation is unavailable',
  )
}
export function freezeInterpretation<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const item of Object.values(value)) freezeInterpretation(item)
    Object.freeze(value)
  }
  return value
}
export function validateConversationMealInterpretationSource(
  raw: ConversationMealInterpretationSource,
): ConversationMealInterpretationSource {
  try {
    const value = mealInterpretationSourceSchema.parse(structuredClone(raw))
    if (
      !isDeepStrictEqual(value, raw) ||
      !isDeepStrictEqual(
        value.source_units,
        value.sources.map((s) => s.unit),
      ) ||
      new Set(value.source_units).size !== value.source_units.length ||
      Buffer.byteLength(JSON.stringify(value), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
    )
      return interpretationUnavailable()
    if (
      value.media_binding === null
        ? !isDeepStrictEqual(value.source_units, ['command_text'])
        : value.source_units.includes('command_text')
    )
      return interpretationUnavailable()
    for (const s of value.sources) {
      if (s.unit === 'vision_items') {
        if (s.text !== null || !s.visual_items.length) return interpretationUnavailable()
      } else if (
        s.text === null ||
        !s.text.length ||
        s.visual_items.length ||
        s.text.length > (s.unit === 'media_caption' ? 1000 : 2000)
      )
        return interpretationUnavailable()
    }
    return freezeInterpretation(value)
  } catch {
    return interpretationUnavailable()
  }
}
function canonical(value: Json): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
  return `{${Object.entries(value)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${canonical(v ?? null)}`)
    .join(',')}}`
}

/** Pure early seam for invocation orchestration. No verbal intent pre-gate,
 * provider, database lookup, live media read or clinical authorization. */
export function buildConversationMealInterpretationSource(
  original: BoundConversationMealCommand,
  captured: CapturedMealInterpretationSource,
): ConversationMealInterpretationSource {
  try {
    const raw = structuredClone(original),
      command = bindConversationCommand(raw.ownerId, `cmsg1:${raw.commandId}`, raw.command)
    if (!isDeepStrictEqual(raw, command)) return interpretationUnavailable()
    const rawContext = structuredClone(captured.context)
    const c = z
      .object({
        schema: z.literal('conversation.meal-source.v1'),
        owner_id: uuid,
        command_id: uuid,
        input_hash: hash,
        epoch: uuid,
        source_input: conversationMealCommandSchema,
        source_units: z.array(mealInterpretationUnitSchema).min(1).max(4),
        source_evidence: z.record(json),
        media: mediaSchema.nullable(),
      })
      .passthrough()
      .parse(rawContext)
    if (!isDeepStrictEqual(c, rawContext)) return interpretationUnavailable()
    if (
      c.owner_id !== command.ownerId ||
      c.command_id !== command.commandId ||
      c.input_hash !== command.inputHash ||
      c.epoch !== captured.epoch ||
      !isDeepStrictEqual(c.source_input, command.command) ||
      new Set(c.source_units).size !== c.source_units.length
    )
      return interpretationUnavailable()
    const sources: ConversationMealInterpretationSource['sources'] = []
    let media_binding: ConversationMealInterpretationSource['media_binding'] = null
    if (command.command.source.channel === 'text') {
      if (
        c.media !== null ||
        !isDeepStrictEqual(c.source_units, ['command_text']) ||
        !isDeepStrictEqual(c.source_evidence, {})
      )
        return interpretationUnavailable()
      sources.push({ unit: 'command_text', text: command.command.source.text, visual_items: [] })
    } else {
      const m = c.media,
        input = command.command.source
      if (!m || m.asset_id !== input.media_asset_id) return interpretationUnavailable()
      const evidence = z
        .object({
          caption: z.string().max(1000).nullable(),
          transcript: z.string().max(2000).nullable(),
        })
        .strict()
        .parse(c.source_evidence)
      if (evidence.caption !== (input.caption ?? m.context_text)) return interpretationUnavailable()
      const result = z.record(json).parse(m.processing_result)
      if (evidence.caption !== null && evidence.caption.replace(/^ +| +$/gu, '').length > 0)
        sources.push({ unit: 'media_caption', text: evidence.caption, visual_items: [] })
      if (m.kind === 'audio_note') {
        if (
          typeof result.text !== 'string' ||
          !result.text.length ||
          result.text.length > 2000 ||
          evidence.transcript !== result.text
        )
          return interpretationUnavailable()
        sources.push({ unit: 'media_transcript', text: result.text, visual_items: [] })
      } else {
        if (
          evidence.transcript !== null ||
          !Array.isArray(result.items) ||
          result.items.length < 1 ||
          result.items.length > 30
        )
          return interpretationUnavailable()
        sources.push({
          unit: 'vision_items',
          text: null,
          visual_items: structuredClone(result.items),
        })
      }
      if (
        !isDeepStrictEqual(
          sources.map((s) => s.unit),
          c.source_units,
        )
      )
        return interpretationUnavailable()
      media_binding = {
        asset_id: m.asset_id,
        kind: m.kind,
        processed_at: m.processed_at,
        updated_at: m.updated_at,
        processing_hash: createHash('sha256').update(canonical(m.processing_result)).digest('hex'),
      }
    }
    const packet = mealInterpretationSourceSchema.parse({
      schema: 'conversation.meal-interpretation-source.v1',
      interpreter_version: MEAL_INTERPRETER_VERSION,
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      source_hash: captured.sourceHash,
      epoch: c.epoch,
      captured_at: captured.capturedAt,
      media_binding,
      source_units: c.source_units,
      sources,
    })
    if (Buffer.byteLength(JSON.stringify(packet), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES)
      return interpretationUnavailable()
    return validateConversationMealInterpretationSource(packet)
  } catch {
    return interpretationUnavailable()
  }
}
