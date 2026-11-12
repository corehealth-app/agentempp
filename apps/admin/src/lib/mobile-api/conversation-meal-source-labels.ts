/** Private provider transport. Only the server supplies source text and offsets. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type ConversationMealInterpretationSource,
  freezeInterpretation,
  interpretationModelSchema,
  interpretationUnavailable,
  MEAL_INTERPRETATION_MAX_BYTES,
  type MealInterpretationModelResult,
  type MealInterpretationUnit,
  validateConversationMealInterpretationSource,
} from './conversation-meal-interpretation-contracts'
import type { MealInterpretationValidationReason } from './conversation-meal-interpretation-validation'

export interface MealSourceToken {
  readonly key: string | null
  readonly text: string
  readonly start: number
  readonly end: number
}
/** Lexical boundaries only: no food identity, measurement or intent inference.
 * Every codepoint, including whitespace, remains in its original UTF16 range. */
export function tokenizeConversationMealSource(text: string): readonly MealSourceToken[] {
  const tokens: MealSourceToken[] = []
  const lexer = /\s+|\d+(?:[.,]\d+)?|[\p{L}\p{M}]+(?:['’-][\p{L}\p{M}]+)*|[\s\S]/gu
  let index = 0
  for (const match of text.matchAll(lexer)) {
    const value = match[0]
    tokens.push({
      key: /^\s+$/u.test(value) ? null : `t${index++}`,
      text: value,
      start: match.index,
      end: match.index + value.length,
    })
  }
  return freezeInterpretation(tokens)
}
const canonicalSource = interpretationModelSchema.shape.sources.element
const canonicalFood = interpretationModelSchema.shape.foods.element
const labelSchema = canonicalSource.shape.spans.element.omit({ start: true, end: true })
type Span = MealInterpretationModelResult['sources'][number]['spans'][number]
type Ref = NonNullable<MealInterpretationModelResult['foods'][number]['name']>
type Role = 'food' | 'quantity' | 'unit'

/** The strict schema requires exactly the keys this frozen source owns. Its
 * output contains labels, not regenerated words, offsets or food references.
 * The caller must still apply the canonical semantic validator before saving. */
export function prepareConversationMealSourceLabels(
  original: ConversationMealInterpretationSource,
) {
  const source = validateConversationMealInterpretationSource(original)
  const tokenSets = new Map(
    source.sources.map((s) => [s.unit, tokenizeConversationMealSource(s.text ?? '')]),
  )
  const sourceShape: Record<string, z.ZodTypeAny> = {}
  for (const s of source.sources) {
    const labels: Record<string, typeof labelSchema> = {}
    for (const token of tokenSets.get(s.unit) ?? [])
      if (token.key !== null) labels[token.key] = labelSchema
    sourceShape[s.unit] = z
      .object({
        classification:
          s.unit === 'vision_items' ? z.literal('visual') : canonicalSource.shape.classification,
        labels: z.object(labels).strict(),
      })
      .strict()
  }
  const schema = z
    .object({
      schema: z.literal('conversation.meal-source-labels.v1'),
      decision: interpretationModelSchema.shape.decision,
      reason: interpretationModelSchema.shape.reason,
      sources: z.object(sourceShape).strict(),
      foods: z.array(canonicalFood.pick({ index: true, visual_index: true })).max(30),
    })
    .strict()
  const input = freezeInterpretation({
    media_action: source.media_binding ? 'register_consumed_meal' : null,
    sources: source.sources.map((s) => ({
      ...s,
      tokens: (tokenSets.get(s.unit) ?? []).flatMap((t) =>
        t.key === null ? [] : [[t.key, t.text] as const],
      ),
    })),
  })
  function materialize(
    raw: unknown,
    onFailure?: (reason: MealInterpretationValidationReason) => void,
  ): MealInterpretationModelResult {
    let reason: MealInterpretationValidationReason = 'validation_internal'
    const reject = (value: MealInterpretationValidationReason): never => {
      reason = value
      return interpretationUnavailable()
    }
    try {
      let copy: unknown, wire: z.infer<typeof schema>
      try {
        copy = structuredClone(raw)
        wire = schema.parse(copy)
      } catch {
        return reject('model_schema')
      }
      if (
        !isDeepStrictEqual(copy, wire) ||
        Buffer.byteLength(JSON.stringify(wire), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
      )
        return reject('model_envelope')
      const refs = new Map<number, Partial<Record<Role, Ref>>>()
      const sources = source.sources.map((s) => {
        const labeled = wire.sources[s.unit] as {
          classification: z.infer<typeof canonicalSource.shape.classification>
          labels: Record<string, z.infer<typeof labelSchema>>
        }
        const spans: Span[] = []
        const append = (span: Span) => {
          const last = spans.at(-1)
          if (
            last &&
            last.end === span.start &&
            last.kind === span.kind &&
            last.food_index === span.food_index
          )
            last.end = span.end
          else spans.push(span)
        }
        const text = s.text ?? ''
        let cursor = 0
        for (const token of tokenSets.get(s.unit) ?? []) {
          if (token.key === null) continue
          const label = labeled.labels[token.key]
          if (!label) return reject('span_partition')
          const last = spans.at(-1)
          if (
            last &&
            last.kind === label.kind &&
            last.food_index === label.food_index &&
            /^\s*$/u.test(text.slice(cursor, token.start))
          ) {
            // Only original whitespace can bridge equal labels. Connectors and
            // punctuation must themselves be labeled; nothing is silently skipped.
            last.end = token.end
          } else {
            if (cursor < token.start)
              append({ start: cursor, end: token.start, kind: 'separator', food_index: null })
            append({ start: token.start, end: token.end, ...label })
          }
          cursor = token.end
        }
        if (cursor < text.length)
          append({ start: cursor, end: text.length, kind: 'separator', food_index: null })
        for (const span of spans) {
          if (span.food_index === null) continue
          if (
            !['food', 'quantity', 'unit'].includes(span.kind) ||
            span.food_index >= wire.foods.length
          )
            return reject('occurrence_binding')
          const role = span.kind as Role,
            group = refs.get(span.food_index) ?? {}
          // Two independent runs cannot be collapsed by finding a convenient
          // occurrence, swallowing intervening discourse or choosing one amount.
          if (group[role]) return reject('reference_binding')
          group[role] = { unit: s.unit as Ref['unit'], start: span.start, end: span.end }
          refs.set(span.food_index, group)
        }
        return {
          unit: s.unit as MealInterpretationUnit,
          classification: labeled.classification,
          spans,
          visual_indexes: s.visual_items.map((_, i) => i),
        }
      })
      const result = {
        schema: 'conversation.meal-interpretation.v1' as const,
        decision: wire.decision,
        reason: wire.reason,
        sources,
        foods: wire.foods.map((f) => {
          const group = refs.get(f.index)
          return {
            ...f,
            name: group?.food ?? null,
            quantity: group?.quantity ?? null,
            unit: group?.unit ?? null,
          }
        }),
      }
      return freezeInterpretation(interpretationModelSchema.parse(result))
    } catch {
      try {
        onFailure?.(reason)
      } catch {
        // Observation cannot change rejection or authorize another attempt.
      }
      return interpretationUnavailable()
    }
  }
  return Object.freeze({ schema, input, materialize })
}
