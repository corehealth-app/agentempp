/** Closed public factual result. A codec is not proof of database persistence:
 * callers must supply the actual private writer receipt/server binding and a
 * fresh current-policy presentation. Raw immutable feedback is never accepted. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import type { ConversationMealFeedbackPresentation } from './conversation-meal-feedback-presentation'
import {
  type ConversationMealEffectReceipt,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  bindConversationWriterCommand,
  conversationWriterClock,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { parseRegistrationFeedback } from './registration-feedback-receipt'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const number = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
const text = z
  .string()
  .min(1)
  .max(240)
  .refine((value) => value.trim().length > 0)
const mealKind = z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
const nutrients = z
  .object({ kcal: number, protein_g: number, carbs_g: number, fat_g: number })
  .strict()
const facts = z
  .object({
    kind: z.literal('meal'),
    meal_kind: mealKind,
    items: z
      .array(
        nutrients
          .extend({
            log_id: uuid,
            food_name: text,
            quantity_g: number.positive().max(9999),
            quantity: z
              .object({
                value: number.positive().max(999999),
                unit: z.enum(['g', 'mL', 'unit', 'scoop']),
                estimated: z.boolean(),
                reference_id: text.nullable(),
              })
              .strict(),
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
              'pending_approved',
              'llm_estimate',
            ]),
          })
          .strict(),
      )
      .min(1)
      .max(30),
    totals: nutrients,
  })
  .strict()
const section = z
  .object({
    key: z.enum(['saved', 'items', 'summary', 'day', 'block', 'education']),
    text: z
      .string()
      .min(1)
      .max(64000)
      .refine((value) => value.trim().length > 0),
  })
  .strict()
const policy = z
  .object({
    version: z.literal(1),
    observed_at: conversationWriterClock,
    assessment: z.enum(['complete', 'incomplete']),
    recording_allowed: z.literal(true),
    pause_weight_loss_guidance: z.boolean(),
    professional_assessment_recommended: z.boolean(),
    phase_selection_pending: z.boolean(),
    target_source: z.enum(['unavailable', 'official_only', 'assigned_phase']),
    hide: z
      .object({
        objective: z.boolean(),
        calories: z.boolean(),
        protein: z.boolean(),
        balance: z.boolean(),
        block: z.boolean(),
        budget: z.boolean(),
      })
      .strict(),
  })
  .strict()
const metadata = z.object({
  schema: z.literal('conversation.feedback-presentation.v1'),
  mode: z.literal('historical'),
  assistant: z.literal('Flow AI'),
  original: z
    .object({
      schema: z.enum(['registration.feedback.v1', 'registration.feedback.v2']),
      registration_id: uuid,
      kind: z.literal('meal'),
      local_date: z.string().date(),
    })
    .strict(),
  current_policy: policy,
  provenance: z
    .object({ epoch: uuid, command_id: uuid, observed_at: conversationWriterClock })
    .strict(),
})
const presentation = z.discriminatedUnion('format', [
  metadata
    .extend({
      status: z.literal('available'),
      format: z.literal('sections'),
      recorded: facts,
      sections: z.array(section).length(6),
    })
    .strict(),
  metadata
    .extend({
      status: z.literal('available'),
      format: z.literal('legacy'),
      legacy_body: z.unknown(),
    })
    .strict(),
  metadata
    .extend({
      status: z.literal('unavailable'),
      format: z.literal('placeholder'),
      sections: z.array(section).length(2),
    })
    .strict(),
])
export interface SavedConversationMealCommandResult {
  readonly schema: 'conversation.meal-command-result.v1'
  readonly status: 'saved'
  readonly owner_id: string
  readonly command_id: string
  readonly input_hash: string
  /** Original server epoch precondition, never rewritten to a newer observation. */
  readonly epoch: string
  readonly admitted_at: string
  readonly receipt: ConversationMealEffectReceipt
  readonly feedback: ConversationMealFeedbackPresentation | null
}
export interface SavedConversationMealCommandResultInput {
  readonly auth: MobileAuthContext
  readonly command: BoundConversationMealCommand
  readonly expectedEpoch: string
  readonly serverBinding: unknown
  readonly receipt: unknown
  readonly feedback: unknown
}
function invalid(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_command_result_unavailable',
    'Saved command result is unavailable',
  )
}
function instant(raw: string): bigint {
  conversationWriterClock.parse(raw)
  const match = /\.(\d{1,9})(?:Z|[+-]\d{2}:\d{2})$/u.exec(raw)
  if (/\.\d{10}/u.test(raw)) return invalid()
  return BigInt(Date.parse(raw)) * 1000000n + BigInt((match?.[1] ?? '').padEnd(9, '0').slice(3))
}
function guardedFeedback(
  raw: unknown,
  b: {
    owner: string
    epoch: string
    command: BoundConversationMealCommand
    admittedAt: string
    receipt: ConversationMealEffectReceipt
  },
): ConversationMealFeedbackPresentation | null {
  if (raw === null) return null
  try {
    const copy = structuredClone(raw),
      v = presentation.parse(copy),
      p = v.current_policy,
      restricted =
        p.assessment !== 'complete' ||
        !p.recording_allowed ||
        p.pause_weight_loss_guidance ||
        Object.values(p.hide).some(Boolean)
    if (
      !isDeepStrictEqual(v, copy) ||
      Buffer.byteLength(JSON.stringify(v), 'utf8') > 200000 ||
      v.original.registration_id !== b.receipt.registration_id ||
      v.original.local_date !== b.receipt.local_date ||
      v.provenance.command_id !== b.command.commandId ||
      v.provenance.epoch !== b.epoch ||
      v.current_policy.observed_at !== v.provenance.observed_at ||
      instant(v.provenance.observed_at) < instant(b.admittedAt)
    )
      return null
    if (v.format === 'sections') {
      const ids = v.recorded.items.map((i) => i.log_id)
      if (
        v.original.schema !== 'registration.feedback.v2' ||
        v.recorded.meal_kind !== b.receipt.meal_type ||
        new Set(ids).size !== ids.length ||
        !isDeepStrictEqual([...ids].sort(), [...b.receipt.log_ids].sort()) ||
        !isDeepStrictEqual(
          v.sections.map((s) => s.key),
          ['saved', 'items', 'summary', 'day', 'block', 'education'],
        )
      )
        return null
      return freezeInterpretation(v)
    }
    if (v.original.schema !== 'registration.feedback.v1') return null
    if (v.format === 'legacy') {
      if (restricted) return null
      const body = parseRegistrationFeedback(v.legacy_body, {
        userId: b.owner,
        registrationId: b.receipt.registration_id,
        kind: 'meal',
      })
      if (body.day && body.day.local_date !== b.receipt.local_date) return null
      return freezeInterpretation({ ...v, legacy_body: body })
    }
    if (
      !restricted ||
      !isDeepStrictEqual(
        v.sections.map((s) => s.key),
        ['saved', 'summary'],
      )
    )
      return null
    return freezeInterpretation(v)
  } catch {
    return null
  }
}

/** Only after factual success and current-policy guarded read. No writer,
 * model, clinical recapture or enrichment retry occurs on this boundary. */
export function projectSavedConversationMealCommandResult(
  input: SavedConversationMealCommandResultInput,
): SavedConversationMealCommandResult {
  try {
    const auth = structuredClone(input.auth),
      owner = authenticatedReevaluationOwner(auth),
      command = bindConversationWriterCommand(input.command),
      epoch = uuid.parse(input.expectedEpoch),
      rawBinding = structuredClone(input.serverBinding),
      b = conversationJournalBindingSchema.parse(rawBinding),
      receipt = parseConversationMealEffectReceipt(input.receipt, command)
    if (
      !isDeepStrictEqual(rawBinding, b) ||
      command.ownerId !== owner ||
      b.owner_id !== owner ||
      b.command_id !== command.commandId ||
      b.input_hash !== command.inputHash ||
      b.epoch !== epoch ||
      instant(receipt.consumed_at) < instant(b.admitted_at)
    )
      return invalid()
    const feedback = guardedFeedback(input.feedback, {
      owner,
      epoch,
      command,
      admittedAt: b.admitted_at,
      receipt,
    })
    return freezeInterpretation({
      schema: 'conversation.meal-command-result.v1',
      status: 'saved',
      owner_id: owner,
      command_id: command.commandId,
      input_hash: command.inputHash,
      epoch,
      admitted_at: b.admitted_at,
      receipt,
      feedback,
    })
  } catch {
    return invalid()
  }
}
