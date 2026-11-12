/** Private SQL transport contracts. Decoding a resolved payload supplies no
 * semantic authority, live catalog validation or permission to call a writer. */
import { isDeepStrictEqual } from 'node:util'
import type { Json } from '@mpp/db'
import { z } from 'zod'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
  conversationMealExecutionCommandSchema,
} from './conversation-command-contracts'
import {
  assertConversationIntakeMediaCapture,
  conversationIntakeMediaProjectionSchema,
} from './conversation-intake-media-origin'
import type { CapturedConversationMealSource } from './conversation-meal-source'
import { conversationMealMediaAnalysis } from './conversation-photo-observations'
import { MobileApiError } from './http'

const uuid = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
export const conversationWriterHash = z.string().regex(/^[a-f0-9]{64}$/u)
const number = z.number().finite()
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.string(), number, z.array(json), z.record(json)]),
)
const object = z.record(json)
const text = (max: number) =>
  z
    .string()
    .min(1)
    .max(max)
    .refine(
      (value) =>
        value.trim().length > 0 &&
        !Array.from(value).some((char) => {
          const c = char.charCodeAt(0)
          return (c < 32 && ![9, 10, 13].includes(c)) || c === 127
        }),
    )
export const conversationWriterClock = z
  .string()
  .datetime({ offset: true })
  .refine((value) => {
    const date = value.slice(0, 10),
      parsed = new Date(`${date}T00:00:00Z`)
    return (
      !value.startsWith('0000') &&
      Number.isFinite(Date.parse(value)) &&
      Number.isFinite(parsed.getTime()) &&
      parsed.toISOString().slice(0, 10) === date
    )
  })
const mealType = z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
const sourceUnit = z.enum(['command_text', 'media_caption', 'media_transcript', 'vision_items'])
const mediaSchema = z
  .object({
    asset_id: uuid,
    kind: z.enum(['meal_photo', 'audio_note', 'conversation_photo']),
    status: z.literal('processed'),
    processed_at: conversationWriterClock,
    updated_at: conversationWriterClock,
    processing_result: object,
    context_text: z.string().nullable(),
  })
  .strict()
const legacyContextSchema = z
  .object({
    schema: z.literal('conversation.meal-source.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: conversationWriterHash,
    epoch: uuid,
    source_input: conversationMealExecutionCommandSchema,
    source_units: z.array(sourceUnit).min(1).max(4),
    source_evidence: z.union([
      z.object({}).strict(),
      z.object({ caption: z.string().nullable(), transcript: z.string().nullable() }).strict(),
    ]),
    media: mediaSchema.nullable(),
    catalog: z.object({ epoch: uuid, revision: z.string().regex(/^\d+$/u) }).strict(),
    owner: z
      .object({
        timezone: z.string().min(1),
        locale: z.string().nullable(),
        country: z.string(),
        country_confirmed: z.literal(true),
      })
      .strict(),
    clinical: object,
    day: z
      .object({
        date: z.string().date(),
        day_closed: z.boolean(),
        calories_target: number.nullable(),
        protein_target: number.nullable(),
        current_protocol: z.string().nullable(),
        target_revision: z.string().regex(/^\d+$/u),
        calorie_origin: object.nullable(),
      })
      .strict(),
  })
  .strict()
const contextSchema = z.union([
  legacyContextSchema,
  legacyContextSchema
    .extend({
      schema: z.literal('conversation.meal-source.v2'),
      source_input: conversationMealExecutionCommandSchema,
      source_units: z
        .array(
          z.enum([
            'command_text',
            'media_caption',
            'media_context',
            'media_transcript',
            'vision_items',
          ]),
        )
        .min(1)
        .max(4),
      source_evidence: z
        .object({
          caption: z.string().nullable(),
          context_text: z.string().nullable(),
          transcript: z.string().nullable(),
        })
        .strict(),
      media: mediaSchema.extend({ owner_id: uuid }).strict(),
      intake_projection: conversationIntakeMediaProjectionSchema,
    })
    .strict(),
])
export interface ConversationMealStoredSource {
  readonly sourceHash: string
  readonly capturedAt: string
  readonly epoch: string
  readonly context: CapturedConversationMealSource['context']
}
export interface ConversationResolvedMealBinding {
  readonly command: BoundConversationMealCommand
  readonly source: ConversationMealStoredSource
}
const indexes = z.array(number.int().min(0).max(29)).min(1).max(30)
const macros = {
  kcal: number.min(0).max(99999),
  protein_g: number.min(0).max(9999),
  carbs_g: number.min(0).max(9999),
  fat_g: number.min(0).max(9999),
}
const itemSchema = z
  .object({
    name: text(250).refine((v) => v.replace(/^ +| +$/gu, '') === v),
    food_db_id: number.int().min(1).max(2147483647).nullable(),
    nutrition_source: z.enum([
      'taco',
      'canonical_exact',
      'canonical_fuzzy',
      'canonical_composite',
      'canonical_composite_partial',
      'rule_based',
      'user_correction',
      'history',
      'user_kcal',
      'product_label',
      'llm_estimate',
    ]),
    quantity_g: number.positive().max(9999),
    ...macros,
    confidence: number.min(0).max(1).nullable(),
    input_indexes: indexes,
    quantity_basis: z.enum(['stated', 'portion_reference', 'visual_estimate']),
    display_qty: number.positive().nullable(),
    display_unit: text(40).nullable(),
  })
  .strict()
const resolvedSchema = z
  .object({
    schema: z.literal('conversation.meal-resolved.v1'),
    input_hash: conversationWriterHash,
    source_hash: conversationWriterHash,
    meal_type: mealType,
    semantic_proof: z
      .object({
        schema: z.literal('conversation.meal-semantic.v1'),
        decision: z.literal('consumed_meal'),
        input_hash: conversationWriterHash,
        source_hash: conversationWriterHash,
        complete_source: z.literal(true),
        source_units: z.array(sourceUnit).min(1).max(4),
        input_count: number.int().min(1).max(30),
      })
      .strict(),
    items: z.array(itemSchema).min(1).max(30),
    totals: z
      .object({
        kcal: number.nonnegative(),
        protein_g: number.nonnegative(),
        carbs_g: number.nonnegative(),
        fat_g: number.nonnegative(),
      })
      .strict(),
    preparation_annotations: z
      .array(
        z
          .object({
            schema: z.literal('consumed.preparation.v1'),
            kind: z.literal('default_cooked'),
            input_indexes: indexes,
            food_name: text(250),
            policy: text(128),
            reference_id: text(200),
          })
          .strict(),
      )
      .max(30),
    source_receipts: z.array(z.object({ id: uuid, hash: conversationWriterHash }).strict()).max(64),
  })
  .strict()
export type ConversationResolvedMeal = Readonly<z.infer<typeof resolvedSchema>>

export function conversationWriterUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_writer_unavailable',
    'Meal registration state is unavailable',
  )
}
export function freezeConversationWriter<T>(v: T): T {
  if (v !== null && typeof v === 'object') {
    for (const child of Object.values(v)) freezeConversationWriter(child)
    Object.freeze(v)
  }
  return v
}
export function bindConversationWriterCommand(
  raw: BoundConversationMealCommand,
): BoundConversationMealCommand {
  const copy = structuredClone(raw),
    bound = bindConversationCommand(copy.ownerId, `cmsg1:${copy.commandId}`, copy.command)
  if (!isDeepStrictEqual(copy, bound)) return conversationWriterUnavailable()
  return freezeConversationWriter(bound)
}
export function parseConversationMealStoredSource(
  raw: ConversationMealStoredSource,
  command: BoundConversationMealCommand,
): ConversationMealStoredSource {
  try {
    // A real factory result also owns reader/audit ports. Project only the
    // stored fields before cloning; those capabilities are never invoked here.
    const copy = structuredClone({
        sourceHash: raw.sourceHash,
        capturedAt: raw.capturedAt,
        epoch: raw.epoch,
        context: raw.context,
      }),
      value = z
        .object({
          sourceHash: conversationWriterHash,
          capturedAt: conversationWriterClock,
          epoch: uuid,
          context: contextSchema,
        })
        .strict()
        .parse(copy)
    const c = value.context
    if (
      !isDeepStrictEqual(copy, value) ||
      c.owner_id !== command.ownerId ||
      c.command_id !== command.commandId ||
      c.input_hash !== command.inputHash ||
      c.epoch !== value.epoch ||
      !isDeepStrictEqual(c.source_input, command.command) ||
      new Set(c.source_units).size !== c.source_units.length
    )
      return conversationWriterUnavailable()
    if ('intake_origin' in command.command) assertConversationIntakeMediaCapture(command, c)
    else if (c.schema !== 'conversation.meal-source.v1' || c.media?.kind === 'conversation_photo')
      return conversationWriterUnavailable()
    if (command.command.source.channel === 'text') {
      if (
        !isDeepStrictEqual(c.source_units, ['command_text']) ||
        c.media !== null ||
        !isDeepStrictEqual(c.source_evidence, {})
      )
        return conversationWriterUnavailable()
    } else {
      const m = c.media
      if (
        !m ||
        m.asset_id !== command.command.source.media_asset_id ||
        m.status !== 'processed' ||
        !['meal_photo', 'audio_note', 'conversation_photo'].includes(String(m.kind))
      )
        return conversationWriterUnavailable()
      const caption =
          c.schema === 'conversation.meal-source.v2'
            ? command.command.source.caption
            : (command.command.source.caption ?? m.context_text),
        transcript =
          m.kind === 'audio_note' &&
          m.processing_result &&
          typeof m.processing_result === 'object' &&
          !Array.isArray(m.processing_result)
            ? m.processing_result.text
            : null
      const units: string[] = []
      if (typeof caption === 'string' && caption.replace(/^ +| +$/gu, '') !== '')
        units.push('media_caption')
      if (
        c.schema === 'conversation.meal-source.v2' &&
        m.context_text?.replace(/^ +| +$/gu, '') !== ''
      ) {
        if (m.context_text !== null) units.push('media_context')
      }
      if (m.kind === 'audio_note') units.push('media_transcript')
      else if (m.kind === 'conversation_photo') {
        const analysis = conversationMealMediaAnalysis(m)
        if (!Array.isArray(analysis.items) || analysis.items.length > 30)
          return conversationWriterUnavailable()
        if (analysis.items.length > 0) units.push('vision_items')
        else if (units.length === 0) return conversationWriterUnavailable()
      } else units.push('vision_items')
      if (
        !isDeepStrictEqual(c.source_units, units) ||
        !isDeepStrictEqual(c.source_evidence, {
          caption: caption ?? null,
          ...(c.schema === 'conversation.meal-source.v2' ? { context_text: m.context_text } : {}),
          transcript: transcript ?? null,
        })
      )
        return conversationWriterUnavailable()
    }
    return freezeConversationWriter(value)
  } catch {
    return conversationWriterUnavailable()
  }
}
// PostgreSQL jsonb::text adds separator spaces and expands decimal exponents.
// This byte budget is for the SQL persisted value, not compact JS JSON.
function pgJSON(v: unknown): string {
  if (typeof v === 'number') {
    const s = String(v)
    if (!/[eE]/u.test(s)) return s
    const [mantissa = '', exponent = '0'] = s.toLowerCase().split('e'),
      negative = mantissa.startsWith('-'),
      [whole = '', fraction = ''] = mantissa.replace('-', '').split('.'),
      digits = whole + fraction,
      point = whole.length + Number(exponent)
    return `${negative ? '-' : ''}${point <= 0 ? `0.${'0'.repeat(-point)}${digits}` : point >= digits.length ? digits + '0'.repeat(point - digits.length) : `${digits.slice(0, point)}.${digits.slice(point)}`}`
  }
  if (Array.isArray(v)) return `[${v.map(pgJSON).join(', ')}]`
  if (v !== null && typeof v === 'object')
    return `{${Object.entries(v)
      .map(([k, value]) => `${JSON.stringify(k)}: ${pgJSON(value)}`)
      .join(', ')}}`
  return JSON.stringify(v)
}
// All finite JSON numbers fit this decimal scale. Compare the exact decimal
// values PostgreSQL receives, including the tolerance and density boundaries.
const decimalScale = 10n ** 330n
function decimal(value: number): bigint {
  const [whole = '0', fraction = ''] = pgJSON(value).split('.')
  return BigInt(whole + fraction) * 10n ** BigInt(330 - fraction.length)
}
export function parseConversationResolvedMeal(
  raw: unknown,
  binding: ConversationResolvedMealBinding,
): ConversationResolvedMeal {
  try {
    const command = bindConversationWriterCommand(binding.command),
      source = parseConversationMealStoredSource(binding.source, command),
      copy = structuredClone(raw),
      v = resolvedSchema.parse(copy),
      p = v.semantic_proof
    if (
      !isDeepStrictEqual(copy, v) ||
      Buffer.byteLength(pgJSON(v), 'utf8') > 262144 ||
      v.input_hash !== command.inputHash ||
      v.source_hash !== source.sourceHash ||
      p.input_hash !== command.inputHash ||
      p.source_hash !== source.sourceHash ||
      !isDeepStrictEqual([...p.source_units].sort(), [...source.context.source_units].sort()) ||
      (command.command.meal_type !== undefined && v.meal_type !== command.command.meal_type)
    )
      return conversationWriterUnavailable()
    const covered = new Set<number>(),
      names = new Set<string>()
    const validIndexes = (ids: number[]) =>
      new Set(ids).size === ids.length && ids.every((id) => id < p.input_count)
    for (const i of v.items) {
      if (
        names.has(i.name) ||
        !validIndexes(i.input_indexes) ||
        (['canonical_exact', 'canonical_fuzzy', 'history'].includes(i.nutrition_source) &&
          i.food_db_id === null) ||
        decimal(i.kcal) > (decimal(i.quantity_g) * 95n) / 10n + 5n * decimalScale ||
        decimal(i.protein_g) + decimal(i.carbs_g) + decimal(i.fat_g) >
          (decimal(i.quantity_g) * 11n) / 10n + 5n * decimalScale
      )
        return conversationWriterUnavailable()
      names.add(i.name)
      for (const id of i.input_indexes) covered.add(id)
    }
    if (
      covered.size !== p.input_count ||
      new Set(v.source_receipts.map((r) => r.id)).size !== v.source_receipts.length
    )
      return conversationWriterUnavailable()
    for (const field of ['kcal', 'protein_g', 'carbs_g', 'fat_g'] as const) {
      const total = decimal(v.totals[field]),
        difference = total - v.items.reduce((sum, item) => sum + decimal(item[field]), 0n)
      if (
        total % (decimalScale / 10n) !== 0n ||
        (difference < 0n ? -difference : difference) > (50000001n * decimalScale) / 1000000000n
      )
        return conversationWriterUnavailable()
    }
    for (const a of v.preparation_annotations)
      if (
        !validIndexes(a.input_indexes) ||
        !v.items.some(
          (i) =>
            i.name === a.food_name && a.input_indexes.every((id) => i.input_indexes.includes(id)),
        )
      )
        return conversationWriterUnavailable()
    return freezeConversationWriter(v)
  } catch {
    return conversationWriterUnavailable()
  }
}
