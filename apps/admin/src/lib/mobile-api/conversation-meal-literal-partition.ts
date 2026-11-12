/** Private provider transport only. Persisted interpretations retain canonical v1. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type ConversationMealInterpretationSource,
  freezeInterpretation,
  interpretationModelSchema,
  interpretationReferenceSchema,
  interpretationUnavailable,
  MEAL_INTERPRETATION_MAX_BYTES,
  type MealInterpretationModelResult,
  type MealInterpretationUnit,
  validateConversationMealInterpretationSource,
} from './conversation-meal-interpretation-contracts'
import type { MealInterpretationValidationReason } from './conversation-meal-interpretation-validation'

const canonicalSource = interpretationModelSchema.shape.sources.element
const canonicalFood = interpretationModelSchema.shape.foods.element
const literalReference = interpretationReferenceSchema
  .omit({ start: true, end: true })
  .extend({ part_index: interpretationReferenceSchema.shape.start })

export const mealLiteralPartitionSchema = interpretationModelSchema.extend({
  schema: z.literal('conversation.meal-literal-partition.v1'),
  sources: z
    .array(
      canonicalSource.omit({ spans: true }).extend({
        parts: z
          .array(
            canonicalSource.shape.spans.element.omit({ start: true, end: true }).extend({
              // Nonempty/exact-length checks belong below, not unsupported wire minLength.
              text: z.string(),
            }),
          )
          .max(4096),
      }),
    )
    .min(1)
    .max(4),
  foods: z
    .array(
      canonicalFood.extend({
        name: literalReference.nullable(),
        quantity: literalReference.nullable(),
        unit: literalReference.nullable(),
      }),
    )
    .max(30),
})

/** Exact concatenation establishes positions; it never establishes consumption.
 * The caller must still run the unchanged canonical semantic validator. */
export function materializeConversationMealLiteralPartition(
  raw: unknown,
  originalSource: ConversationMealInterpretationSource,
  onFailure?: (reason: MealInterpretationValidationReason) => void,
): MealInterpretationModelResult {
  let failureReason: MealInterpretationValidationReason = 'validation_internal'
  const reject = (reason: MealInterpretationValidationReason): never => {
    failureReason = reason
    return interpretationUnavailable()
  }
  try {
    let source: ConversationMealInterpretationSource
    try {
      source = validateConversationMealInterpretationSource(originalSource)
    } catch {
      return reject('source_contract')
    }
    let copy: unknown, wire: z.infer<typeof mealLiteralPartitionSchema>
    try {
      copy = structuredClone(raw)
      wire = mealLiteralPartitionSchema.parse(copy)
    } catch {
      return reject('model_schema')
    }
    if (
      !isDeepStrictEqual(copy, wire) ||
      Buffer.byteLength(JSON.stringify(wire), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
    )
      return reject('model_envelope')
    if (
      !isDeepStrictEqual(
        wire.sources.map((s) => s.unit),
        source.source_units,
      )
    )
      return reject('source_units')

    const byUnit = new Map<
      MealInterpretationUnit,
      MealInterpretationModelResult['sources'][number]['spans']
    >()
    const sources = wire.sources.map((s, index) => {
      const input = source.sources[index]
      if (!input || input.unit !== s.unit) return reject('source_units')
      if (s.unit === 'vision_items') {
        if (
          input.text !== null ||
          s.classification !== 'visual' ||
          s.parts.length ||
          !isDeepStrictEqual(
            s.visual_indexes,
            input.visual_items.map((_, i) => i),
          )
        )
          return reject('source_shape')
        return {
          unit: s.unit,
          classification: s.classification,
          visual_indexes: s.visual_indexes,
          spans: [],
        }
      }
      const text = input.text
      if (text === null || !text.length || s.classification === 'visual' || s.visual_indexes.length)
        return reject('source_shape')
      if (s.parts.some((part) => !part.text.length)) return reject('span_range')
      if (s.parts.map((part) => part.text).join('') !== text) return reject('span_partition')
      let cursor = 0
      const spans = s.parts.map((part) => {
        const start = cursor,
          end = start + part.text.length
        // Exact concatenation still permits two pieces to split a surrogate pair.
        const left = text.charCodeAt(end - 1),
          right = text.charCodeAt(end)
        if (left >= 0xd800 && left <= 0xdbff && right >= 0xdc00 && right <= 0xdfff)
          return reject('span_range')
        cursor = end
        return { start, end, kind: part.kind, food_index: part.food_index }
      })
      byUnit.set(s.unit, spans)
      return {
        unit: s.unit,
        classification: s.classification,
        visual_indexes: s.visual_indexes,
        spans,
      }
    })
    const reference = (ref: z.infer<typeof literalReference> | null) => {
      if (ref === null) return null
      const span = byUnit.get(ref.unit)?.[ref.part_index]
      if (!span) return reject('reference_binding')
      return { unit: ref.unit, start: span.start, end: span.end }
    }
    const result = {
      schema: 'conversation.meal-interpretation.v1' as const,
      decision: wire.decision,
      reason: wire.reason,
      sources,
      foods: wire.foods.map((food) => ({
        index: food.index,
        name: reference(food.name),
        quantity: reference(food.quantity),
        unit: reference(food.unit),
        visual_index: food.visual_index,
      })),
    }
    // No wire-only property is allowed to escape into the persisted DTO.
    return freezeInterpretation(interpretationModelSchema.parse(result))
  } catch {
    try {
      onFailure?.(failureReason)
    } catch {
      // Observation cannot replace the public error or authorize another attempt.
    }
    return interpretationUnavailable()
  }
}
