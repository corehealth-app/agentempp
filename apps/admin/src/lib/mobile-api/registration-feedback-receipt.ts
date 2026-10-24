import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'

export interface RegistrationFeedbackIdentity {
  userId: string
  registrationId: string
  kind: 'meal' | 'workout'
}
export type RegistrationFeedbackRead =
  | { action: 'available'; feedback: RegistrationFeedback }
  | { action: 'absent' | 'event_conflict' }
export interface RegistrationFeedbackReceiptReader {
  readReceipt(identity: RegistrationFeedbackIdentity): Promise<RegistrationFeedbackRead>
}

export interface ConfirmedRegistration {
  id: string
  user_id?: string
  status: string
  proposal: Json
  confirmedWorkoutId?: string
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

/** Receipt-only backend leaf: no cursor, catalog, selection or day dependency. */
export function createSupabaseRegistrationFeedbackReceiptReader(
  supabase: ServiceClient,
): RegistrationFeedbackReceiptReader {
  return {
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
  }
}

export function identityFor(
  userId: string,
  row: ConfirmedRegistration,
): RegistrationFeedbackIdentity | null {
  if (row.status !== 'confirmed' || (row.user_id !== undefined && row.user_id !== userId))
    return null
  const proposal = row.proposal
  if (proposal === null || typeof proposal !== 'object' || Array.isArray(proposal)) return null
  const kind = proposal.kind
  return kind === 'meal' || kind === 'workout' ? { userId, registrationId: row.id, kind } : null
}

/** Owned read path only. Reopening never selects a phrase, reads a day or writes a receipt. */
export async function readRegistrationFeedback(
  db: ServiceClient,
  userId: string,
  row: ConfirmedRegistration,
  store: RegistrationFeedbackReceiptReader = createSupabaseRegistrationFeedbackReceiptReader(db),
): Promise<RegistrationFeedback | null> {
  try {
    const identity = identityFor(userId, row)
    if (!identity) return null
    const saved = await store.readReceipt(identity)
    return saved.action === 'available' ? parseRegistrationFeedback(saved.feedback, identity) : null
  } catch {
    return null
  }
}
