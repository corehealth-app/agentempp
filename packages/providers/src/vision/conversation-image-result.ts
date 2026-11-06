/** Observations only. No consumed portion, performed workout or clinical
 * assessment can be established by this nonclinical image-purpose result. */
import { z } from 'zod'

const text = z.string().max(2000),
  number = z.number().finite().nonnegative(),
  confidence = number.max(1)
const macros = z
  .object({
    kcal: number.nullable(),
    protein_g: number.nullable(),
    carbs_g: number.nullable(),
    fat_g: number.nullable(),
  })
  .strict()
const label = z
  .object({
    type: z.literal('nutrition_label'),
    product_name: text.nullable(),
    serving_size_g: number.nullable(),
    per_serving: macros,
    per_100g: macros,
    confidence,
    notes: text.optional(),
    nutrition_label_error: z.literal('nutrition_label_unreadable').optional(),
  })
  .strict()
const meal = z
  .object({
    type: z.literal('meal'),
    items: z
      .array(
        z
          .object({
            name: z.string().min(1).max(240),
            quantity_g_estimate: number,
            confidence,
            notes: text.optional(),
          })
          .strict(),
      )
      .max(30),
    meal_context: text.optional(),
    nutrition_label_visible: z.boolean().optional(),
    nutrition_label: label.optional(),
    nutrition_label_error: z.literal('nutrition_label_unreadable').optional(),
  })
  .strict()
const equipment = z
  .object({
    type: z.literal('equipment'),
    equipment: z.array(z.string().min(1).max(240)).max(30),
    location: z.enum(['academia_completa', 'academia_limitada', 'casa']).nullable(),
    confidence,
    notes: text.optional(),
  })
  .strict()
const ready = z
  .object({
    schema: z.literal('conversation.image-result.v1'),
    status: z.literal('ready'),
    classification: z.enum(['meal', 'equipment', 'nutrition_label']),
    analysis: z.discriminatedUnion('type', [meal, equipment, label]),
  })
  .strict()
  .refine((v) => v.classification === v.analysis.type)
export const conversationImageResultSchema = z.union([
  ready,
  z
    .object({
      schema: z.literal('conversation.image-result.v1'),
      status: z.literal('unsupported'),
      classification: z.enum(['body', 'scale', 'other', 'unknown']),
      reason: z.literal('image_not_supported_for_conversation'),
    })
    .strict(),
])
export type ConversationImageResult = z.infer<typeof conversationImageResultSchema>
export function parseConversationImageResult(raw: unknown): ConversationImageResult {
  return conversationImageResultSchema.parse(raw)
}
/** Explicit public projection from existing provider observations. Unknown
 * fields/usage/raw answers are dropped; error text never crosses this seam. */
export function projectConversationImageResult(
  classification: 'meal' | 'equipment' | 'nutrition_label',
  raw: unknown,
): ConversationImageResult {
  const object = z.record(z.unknown()).parse(raw)
  const redact = (value: Record<string, unknown>): Record<string, unknown> => ({
    ...value,
    ...(value.nutrition_label_error === undefined
      ? {}
      : { nutrition_label_error: 'nutrition_label_unreadable' as const }),
  })
  let analysis: z.infer<typeof meal> | z.infer<typeof equipment> | z.infer<typeof label>
  if (classification === 'meal') {
    const value = redact(object)
    if (value.nutrition_label !== undefined)
      value.nutrition_label = label
        .strip()
        .parse(redact(z.record(z.unknown()).parse(value.nutrition_label)))
    analysis = meal.strip().parse(value)
  } else if (classification === 'equipment') analysis = equipment.strip().parse(object)
  else analysis = label.strip().parse(redact(object))
  return parseConversationImageResult({
    schema: 'conversation.image-result.v1',
    status: 'ready',
    classification,
    analysis,
  })
}
