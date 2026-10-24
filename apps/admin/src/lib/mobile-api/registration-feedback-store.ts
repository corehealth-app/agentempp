import type { FlowStatusPhraseCursor } from '@mpp/agent/flow-curated-phrases'
import type {
  prepareRegistrationFeedback,
  RegistrationFeedback,
} from '@mpp/agent/registration-feedback'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  createSupabaseFlowPhraseReplyStore,
  type FlowPhraseCursorSnapshot,
} from './flow-phrase-reply-store'

export interface RegistrationFeedbackIdentity {
  userId: string
  registrationId: string
  kind: 'meal' | 'workout'
}
export interface RegistrationFeedbackCommit extends RegistrationFeedbackIdentity {
  expectedProposal: Json
  expectedCursorRevision: string
  expectedCursor: FlowStatusPhraseCursor | null
  steps: ReturnType<typeof prepareRegistrationFeedback>['steps']
  feedback: RegistrationFeedback
}
export type RegistrationFeedbackRead =
  | { action: 'available'; feedback: RegistrationFeedback }
  | { action: 'absent' | 'event_conflict' }
export type RegistrationFeedbackCommitResult =
  | { action: 'committed' | 'replay'; feedback: RegistrationFeedback }
  | { action: 'cursor_conflict' | 'event_conflict' }
export interface RegistrationFeedbackStore {
  readReceipt(identity: RegistrationFeedbackIdentity): Promise<RegistrationFeedbackRead>
  loadCursor(userId: string): Promise<FlowPhraseCursorSnapshot>
  commit(input: RegistrationFeedbackCommit): Promise<RegistrationFeedbackCommitResult>
}

const uuid = z.string().regex(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u)
const number = z.number().finite().min(0).max(Number.MAX_SAFE_INTEGER)
const target = number.positive().nullable()
const text = z
  .string()
  .min(1)
  .max(4000)
  .refine((value) => value.trim().length > 0)
const totals = z
  .object({ kcal: number, protein_g: number, carbs_g: number, fat_g: number })
  .strict()
const feedbackSchema = z
  .object({
    schema: z.literal('registration.feedback.v1'),
    registration_id: uuid,
    kind: z.enum(['meal', 'workout']),
    locale: z.enum(['pt-BR', 'en']),
    meal_totals: totals.nullable(),
    day: z
      .object({
        local_date: z.string().date(),
        current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
        remaining_food_kcal: number.nullable(),
        food_excess_kcal: number.nullable(),
        exercise_kcal: number,
        consumed: z
          .object({ calories_kcal: number, protein_g: number, carbs_g: number, fat_g: number })
          .strict(),
        targets: z.object({ calories_kcal: target, protein_g: target }).strict(),
        calorie_percentage: number.nullable(),
        protein_percentage: number.nullable(),
      })
      .strict()
      .nullable(),
    lines: z
      .array(
        z
          .object({
            key: z.enum([
              'meal_totals',
              'day_calories',
              'day_protein',
              'food_budget',
              'day_unavailable',
            ]),
            text,
          })
          .strict(),
      )
      .min(1)
      .max(5),
    food_comment: text.nullable(),
    incentive: text.nullable(),
  })
  .strict()

function invalid(): never {
  throw new Error('Invalid registration feedback receipt')
}
function validateIdentity(identity: RegistrationFeedbackIdentity): void {
  uuid.parse(identity.userId)
  uuid.parse(identity.registrationId)
  z.enum(['meal', 'workout']).parse(identity.kind)
}

/** Closed public projection. Never normalize unknown data through JSON.stringify first. */
export function parseRegistrationFeedback(
  value: unknown,
  identity: RegistrationFeedbackIdentity,
): RegistrationFeedback {
  validateIdentity(identity)
  const feedback = feedbackSchema.parse(value)
  const keys = new Set(feedback.lines.map((line) => line.key))
  const day = feedback.day
  if (
    feedback.registration_id !== identity.registrationId ||
    feedback.kind !== identity.kind ||
    keys.size !== feedback.lines.length ||
    (feedback.kind === 'meal') !== (feedback.meal_totals !== null) ||
    (feedback.kind === 'meal') !== keys.has('meal_totals') ||
    (feedback.kind === 'workout' && feedback.food_comment !== null) ||
    (feedback.locale === 'en' && (feedback.food_comment !== null || feedback.incentive !== null)) ||
    (day === null
      ? !keys.has('day_unavailable') ||
        feedback.lines.some((line) =>
          ['day_calories', 'day_protein', 'food_budget'].includes(line.key),
        )
      : keys.has('day_unavailable') ||
        !keys.has('day_calories') ||
        !keys.has('day_protein') ||
        (day.targets.calories_kcal === null) !== (day.calorie_percentage === null) ||
        (day.targets.protein_g === null) !== (day.protein_percentage === null))
  )
    invalid()
  return feedback
}

/** Trusted-backend only. Construction never reads or advances the shared cursor. */
export function createSupabaseRegistrationFeedbackStore(
  supabase: ServiceClient,
): RegistrationFeedbackStore {
  const phrases = createSupabaseFlowPhraseReplyStore(supabase)
  return {
    loadCursor: phrases.loadCursor,
    async readReceipt(identity) {
      validateIdentity(identity)
      const { data, error } = await supabase.rpc('read_mobile_registration_feedback', {
        p_user_id: identity.userId,
        p_registration_id: identity.registrationId,
      })
      if (error) throw new Error('Unable to read registration feedback receipt')
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('available'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('absent') }).strict(),
          z.object({ action: z.literal('event_conflict') }).strict(),
        ])
        .parse(data)
      return result.action === 'available'
        ? { action: 'available', feedback: parseRegistrationFeedback(result.feedback, identity) }
        : result
    },
    async commit(input) {
      const feedback = parseRegistrationFeedback(input.feedback, input)
      const revision = z
        .string()
        .regex(/^(0|[1-9][0-9]*)$/u)
        .refine((value) => value.length <= 19 && BigInt(value) <= 9223372036854775807n)
        .parse(input.expectedCursorRevision)
      const copyCursor = (cursor: FlowStatusPhraseCursor) => ({
        ...cursor,
        usedTextKeys: [...cursor.usedTextKeys],
      })
      // The DTO was validated above; this conversion gives the RPC its Json type
      // without losing NaN, undefined or extra private fields during validation.
      const publicJson: Json = JSON.parse(JSON.stringify(feedback))
      const { data, error } = await supabase.rpc('commit_mobile_registration_feedback', {
        p_user_id: input.userId,
        p_registration_id: input.registrationId,
        p_expected_proposal: input.expectedProposal,
        p_expected_revision: revision,
        p_expected_cursor: input.expectedCursor === null ? null : copyCursor(input.expectedCursor),
        p_steps: input.steps.map((step) => ({
          receipt: { ...step.receipt, selection: { ...step.receipt.selection } },
          nextCursor: copyCursor(step.nextCursor),
        })),
        p_feedback: publicJson,
      })
      if (error) throw new Error('Unable to commit registration feedback receipt')
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('committed'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('replay'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('cursor_conflict') }).strict(),
          z.object({ action: z.literal('event_conflict') }).strict(),
        ])
        .parse(data)
      if (result.action !== 'committed' && result.action !== 'replay') return result
      const saved = parseRegistrationFeedback(result.feedback, input)
      if (result.action === 'committed' && JSON.stringify(saved) !== JSON.stringify(feedback))
        invalid()
      return { action: result.action, feedback: saved }
    },
  }
}
