/** Private persisted candidate codec. A candidate is not resolved nutrition or
 * consumption authority. No public route or domain writer consumes this DTO. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import {
  bindConversationCommand,
  conversationMealExecutionCommandSchema,
} from './conversation-command-contracts'
import { MobileApiError } from './http'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const amount = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
const text = (max: number) => z.string().min(1).max(max)
const oversizedText = z
  .object({ sha256: hash, utf16_length: z.number().int().positive().max(Number.MAX_SAFE_INTEGER) })
  .strict()
const evidence = z
  .object({
    caption: z.string().max(1000).nullable(),
    transcript: z.string().max(2000).nullable(),
    oversized: z
      .object({ caption: oversizedText.optional(), transcript: oversizedText.optional() })
      .strict()
      .optional(),
  })
  .strict()
  .superRefine((value, ctx) => {
    if (
      value.oversized &&
      ((!value.oversized.caption && !value.oversized.transcript) ||
        (value.oversized.caption &&
          (value.caption !== null || value.oversized.caption.utf16_length <= 1000)) ||
        (value.oversized.transcript &&
          (value.transcript !== null || value.oversized.transcript.utf16_length <= 2000)))
    )
      ctx.addIssue({ code: 'custom', message: 'Invalid oversized source evidence' })
  })
const mediaBinding = z
  .object({
    asset_id: uuid,
    kind: z.enum(['meal_photo', 'audio_note']),
    processed_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }),
    processing_hash: hash,
  })
  .strict()
const boundCommand = z
  .object({
    ownerId: uuid,
    commandId: uuid,
    inputHash: hash,
    command: conversationMealExecutionCommandSchema,
  })
  .strict()
const intent = z.discriminatedUnion('decision', [
  z
    .object({
      decision: z.literal('actual_report'),
      basis: z.literal('first_person_report'),
      foodText: text(2000),
    })
    .strict(),
  z
    .object({
      decision: z.literal('explicit_media_registration'),
      basis: z.literal('user_registration_action'),
    })
    .strict(),
  z
    .object({
      decision: z.literal('clarification_required'),
      reason: z.enum([
        'invalid_source',
        'consumption_not_established',
        'mixed_statement',
        'missing_audio',
      ]),
    })
    .strict(),
  z
    .object({
      decision: z.literal('conversational'),
      reason: z.enum([
        'question',
        'not_consumed',
        'future_or_conditional',
        'habit',
        'third_party_or_quote',
      ]),
    })
    .strict(),
])
const nutrients = z
  .object({
    kcal: amount.nullable(),
    protein_g: amount.nullable(),
    carbs_g: amount.nullable(),
    fat_g: amount.nullable(),
  })
  .strict()
const item = z
  .object({
    candidate_id: text(80),
    name: text(160),
    quantity_g: amount.positive().max(9999).nullable(),
    quantity_basis: z.enum(['stated', 'visual_estimate', 'portion_reference', 'missing']),
    count: amount.nullable(),
    unit_label: text(160).nullable(),
    confidence: amount.max(1).nullable(),
    needs_review: z.boolean(),
    review_reason: z
      .enum(['low_confidence', 'estimated_quantity', 'missing_quantity', 'ambiguous'])
      .nullable(),
    quantity_display: z
      .object({
        unit: z.enum(['mL', 'unit', 'scoop']),
        grams_per_unit: amount.positive().max(9999),
        reference_id: text(160),
        estimated: z.literal(true),
      })
      .strict()
      .optional(),
  })
  .strict()
const draft = z
  .object({
    source: z.enum(['text', 'photo', 'audio']),
    media_asset_id: uuid.nullable(),
    transcript: text(2000).nullable(),
    context_note: text(500).nullable(),
    items: z.array(item).max(30),
    nutrition_label: z
      .object({
        product_name: text(160).nullable(),
        serving_size_g: amount.nullable(),
        per_serving: nutrients.nullable(),
        per_100g: nutrients.nullable(),
        confidence: amount.max(1).nullable(),
        applies_to_candidate_id: text(80).nullable(),
      })
      .strict()
      .nullable(),
    extraction: z
      .object({
        method: z.enum(['deterministic', 'vision', 'llm_text']),
        model: text(160).nullable(),
      })
      .strict(),
  })
  .strict()
  .superRefine((value, ctx) => {
    const ids = new Set(value.items.map((i) => i.candidate_id))
    if (
      ids.size !== value.items.length ||
      (value.nutrition_label?.applies_to_candidate_id &&
        !ids.has(value.nutrition_label.applies_to_candidate_id))
    )
      ctx.addIssue({ code: 'custom', message: 'Invalid candidate references' })
    if (
      (value.source === 'text' &&
        (value.media_asset_id !== null ||
          value.transcript !== null ||
          value.context_note !== null)) ||
      (value.source !== 'text' && value.media_asset_id === null) ||
      (value.source === 'photo' && value.transcript !== null) ||
      (value.source === 'audio' && value.transcript === null)
    )
      ctx.addIssue({ code: 'custom', message: 'Invalid candidate source' })
  })
const common = { command: boundCommand, intent }
const preparation = z
  .discriminatedUnion('status', [
    z
      .object({
        ...common,
        status: z.literal('prepared'),
        draft,
        mediaBinding: mediaBinding.nullable(),
        sourceEvidence: evidence,
      })
      .strict(),
    z
      .object({
        ...common,
        status: z.literal('conversational'),
        sourceEvidence: evidence.optional(),
      })
      .strict(),
    z
      .object({
        ...common,
        status: z.literal('clarification_required'),
        draft: draft.optional(),
        captionDraft: draft.optional(),
        preparationIssue: z
          .enum(['conflicting_user_sources', 'unresolved_source', 'missing_quantity_or_identity'])
          .optional(),
        unresolvedText: z.array(text(2000)).min(1).max(30).optional(),
        mediaBinding: mediaBinding.nullable().optional(),
        sourceEvidence: evidence.optional(),
      })
      .strict(),
  ])
  .superRefine((value, ctx) => {
    const bad = () =>
      ctx.addIssue({ code: 'custom', message: 'Invalid persisted candidate binding' })
    let expected: BoundConversationMealCommand
    try {
      expected = bindConversationCommand(
        value.command.ownerId,
        `cmsg1:${value.command.commandId}`,
        value.command.command,
      )
    } catch {
      bad()
      return
    }
    if (!isDeepStrictEqual(value.command, expected)) bad()
    if (value.status === 'conversational' && value.intent.decision !== 'conversational') bad()
    // A caption may safely establish a question/negation even when the other
    // source was oversized. Persist that stopped result, never a food draft.
    if (
      value.sourceEvidence?.oversized &&
      (value.status === 'prepared' ||
        (value.status === 'clarification_required' && (value.draft || value.captionDraft)) ||
        !['clarification_required', 'conversational'].includes(value.intent.decision))
    )
      bad()
    if (value.status === 'prepared') {
      if (
        !['actual_report', 'explicit_media_registration'].includes(value.intent.decision) ||
        !value.draft.items.length ||
        value.draft.items.some(
          (i) =>
            i.quantity_g === null ||
            i.review_reason === 'ambiguous' ||
            i.review_reason === 'low_confidence',
        )
      )
        bad()
    }
    if (value.status !== 'conversational' && value.draft) {
      if (value.draft.source === 'text') {
        if (
          value.command.command.source.channel !== 'text' ||
          value.mediaBinding != null ||
          (value.sourceEvidence &&
            (value.sourceEvidence.caption !== null || value.sourceEvidence.transcript !== null))
        )
          bad()
      } else {
        const s = value.command.command.source
        if (
          s.channel !== 'media' ||
          value.mediaBinding?.asset_id !== s.media_asset_id ||
          value.draft.media_asset_id !== s.media_asset_id ||
          value.mediaBinding.kind !==
            (value.draft.source === 'photo' ? 'meal_photo' : 'audio_note') ||
          !value.sourceEvidence ||
          value.sourceEvidence.transcript !== value.draft.transcript
        )
          bad()
      }
    }
    if (
      value.status === 'clarification_required' &&
      value.captionDraft?.source !== undefined &&
      value.captionDraft.source !== 'text'
    )
      bad()
  })
const envelope = z
  .object({
    schema: z.literal('conversation.meal-candidate.v1'),
    input_hash: hash,
    status: z.enum(['prepared', 'conversational', 'clarification_required']),
    candidate: preparation,
  })
  .strict()
export type ConversationCandidateEnvelope = z.infer<typeof envelope>
export const conversationJournalBindingSchema = z
  .object({
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    command_protocol: z.literal('conversation.command.v1'),
    kind: z.literal('meal.report'),
    epoch: uuid,
    admitted_at: z.string().datetime({ offset: true }),
  })
  .strict()
export type ConversationJournalBinding = z.infer<typeof conversationJournalBindingSchema>
export function conversationJournalUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_journal_unavailable',
    'Conversation preparation is temporarily unavailable',
  )
}
export function detachAndFreeze<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) detachAndFreeze(child)
    Object.freeze(value)
  }
  return value
}
export function parseConversationCandidate(
  raw: unknown,
  bound: BoundConversationMealCommand,
): ConversationCandidateEnvelope {
  try {
    const result = envelope.parse(raw)
    if (
      result.input_hash !== bound.inputHash ||
      result.status !== result.candidate.status ||
      !isDeepStrictEqual(result.candidate.command, bound) ||
      Buffer.byteLength(JSON.stringify(result), 'utf8') > 131072
    )
      return conversationJournalUnavailable()
    return detachAndFreeze(result)
  } catch {
    return conversationJournalUnavailable()
  }
}
export function encodeConversationCandidate(
  bound: BoundConversationMealCommand,
  raw: unknown,
): ConversationCandidateEnvelope {
  const candidate = raw as { status?: unknown }
  return parseConversationCandidate(
    {
      schema: 'conversation.meal-candidate.v1',
      input_hash: bound.inputHash,
      status: candidate?.status,
      candidate: raw,
    },
    bound,
  )
}
