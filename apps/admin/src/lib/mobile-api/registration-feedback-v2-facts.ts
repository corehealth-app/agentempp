import { getLocalDateString } from '@mpp/agent'
import {
  type FeedbackV2Registration,
  prepareRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import { confirmedWorkoutLogIDFromCapture } from '@mpp/agent/workout-strength-identity'
import { z } from 'zod'
import { mobileQuantityDisplay } from './mobile-quantity-display'

export interface FeedbackV2FactRequest {
  userId: string
  registrationId: string
  confirmed: unknown
  logs: unknown
  /** Private SQL capture only; never parsed from a mobile command body. */
  workoutProof?: unknown
}
export interface FeedbackV2RecordFacts {
  registration: FeedbackV2Registration
  localDate: string
  logIds: string[]
}

const number = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
const nutrients = z.object({ kcal: number, protein_g: number, carbs_g: number, fat_g: number })
const timing = z.object({
  source_provider_message_id: z.string().min(1),
  source_timestamp: z.string().datetime({ offset: true }),
  source_timezone: z.string().min(1),
  source_local_date: z.string().date(),
})
const proposalSchema = z.discriminatedUnion('kind', [
  timing.extend({
    kind: z.literal('meal'),
    mealType: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
    totals: nutrients,
    items: z
      .array(
        nutrients.extend({
          name: z.string().min(1),
          quantity_g: number.positive().max(9999),
          nutrition_source: z.string().min(1),
          quantity_basis: z.enum(['stated', 'portion_reference', 'visual_estimate']).optional(),
        }),
      )
      .min(1)
      .max(30),
  }),
  timing.extend({ kind: z.literal('workout'), workoutType: z.string().min(1) }),
])
const confirmedSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  status: z.literal('confirmed'),
  proposal: proposalSchema,
  confirmedWorkoutId: z.string().uuid().optional(),
  workout_protocol: z.literal('ui-v1').optional(),
})
const protectedProof = z
  .object({
    kind: z.literal('ui-v1'),
    epoch: z.string().uuid(),
    admission_id: z.string().uuid(),
    content_revision: z.number().int().min(0).max(2147483647),
    lifecycle_key: z.string().uuid(),
    operation_key: z.string(),
    workout_id: z.string().uuid(),
    resolver: z.unknown(),
  })
  .strict()
const logIdentity = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  raw_provider_message_id: z.string().min(1),
})
const mealLog = logIdentity.merge(nutrients).extend({
  food_name: z.string().min(1),
  quantity_g: number.positive(),
  source: z.string().min(1),
  consumed_at: z.string().datetime({ offset: true }),
  meal_type: z.string().nullable(),
})
const workoutLog = logIdentity.extend({
  workout_type: z.string().min(1),
  duration_min: number.positive().nullable(),
  intensity: z.string().nullable(),
  estimated_kcal: number.nullable(),
  performed_at: z.string().datetime({ offset: true }),
})
// Physical log columns use two decimal places. This accepts only their storage
// quantization, never a changed food, source or material nutrition correction.
const sameStoredNumber = (stored: number, original: number) =>
  Math.abs(stored - original) <= 0.005000001
const persistedNumbers = ['quantity_g', 'kcal', 'protein_g', 'carbs_g', 'fat_g'] as const

/** No reads/writes here. The caller supplies its owned query result, and this
 * projection refuses missing, edited, extra or ambiguous event evidence. */
export function projectRegistrationFeedbackV2Facts(
  request: FeedbackV2FactRequest,
): FeedbackV2RecordFacts | null {
  try {
    z.string().uuid().parse(request.userId)
    z.string().uuid().parse(request.registrationId)
    const confirmed = confirmedSchema.parse(request.confirmed)
    if (confirmed.id !== request.registrationId || confirmed.user_id !== request.userId) return null
    const proposal = confirmed.proposal
    const instant = new Date(proposal.source_timestamp)
    if (getLocalDateString(proposal.source_timezone, instant) !== proposal.source_local_date)
      return null
    const sameEvent = (row: z.infer<typeof logIdentity>, timestamp: string) =>
      row.user_id === request.userId &&
      row.raw_provider_message_id === proposal.source_provider_message_id &&
      new Date(timestamp).getTime() === instant.getTime()
    let registration: FeedbackV2Registration
    let logIds: string[]
    if (proposal.kind === 'meal') {
      const rows = z.array(mealLog).min(1).max(30).parse(request.logs)
      if (
        rows.length !== proposal.items.length ||
        new Set(rows.map((row) => row.id)).size !== rows.length ||
        rows.some((row) => !sameEvent(row, row.consumed_at) || row.meal_type !== proposal.mealType)
      )
        return null
      const unused = [...rows].sort((a, b) => a.id.localeCompare(b.id))
      const items = proposal.items.map((item) => {
        const index = unused.findIndex(
          (row) =>
            row.food_name === item.name &&
            row.source === item.nutrition_source &&
            persistedNumbers.every((key) => sameStoredNumber(row[key], item[key])),
        )
        const row = index < 0 ? undefined : unused.splice(index, 1)[0]
        if (!row) throw new Error('Confirmed meal facts changed')
        const display = mobileQuantityDisplay(row.food_name)
        return {
          log_id: row.id,
          food_name: row.food_name,
          quantity_g: row.quantity_g,
          quantity: display
            ? {
                value: Math.round((row.quantity_g / display.grams_per_unit) * 1e6) / 1e6,
                unit: display.unit,
                estimated: true,
                reference_id: display.reference_id,
              }
            : {
                value: row.quantity_g,
                unit: 'g' as const,
                estimated:
                  item.quantity_basis === 'portion_reference' ||
                  item.quantity_basis === 'visual_estimate',
                reference_id: null,
              },
          nutrition_source: row.source,
          kcal: row.kcal,
          protein_g: row.protein_g,
          carbs_g: row.carbs_g,
          fat_g: row.fat_g,
        }
      })
      registration = {
        kind: 'meal',
        meal_kind: proposal.mealType,
        items,
        totals: { ...proposal.totals },
      }
      logIds = items.map((item) => item.log_id)
    } else {
      const rows = z.array(workoutLog).length(1).parse(request.logs)
      const row = rows[0]
      if (
        !row ||
        !sameEvent(row, row.performed_at) ||
        row.workout_type !== proposal.workoutType ||
        (confirmed.confirmedWorkoutId !== undefined && row.id !== confirmed.confirmedWorkoutId)
      )
        return null
      if (confirmed.workout_protocol === 'ui-v1' || request.workoutProof !== undefined) {
        const proof = protectedProof.parse(request.workoutProof)
        if (
          proof.workout_id !== row.id ||
          proof.operation_key !== `ui:${proof.admission_id}:r:${proof.content_revision}`
        )
          return null
        const id = confirmedWorkoutLogIDFromCapture(
          proof.resolver,
          request.userId,
          proposal.workoutType,
        )
        if (id === null) {
          const gap = z
            .object({
              status: z.literal('unavailable'),
              reason: z.literal('legacy_provenance_gap'),
              confirmedWorkoutLogID: z.string().uuid(),
            })
            .strict()
            .parse(proof.resolver)
          if (gap.confirmedWorkoutLogID !== row.id) return null
        } else {
          const resolved = z
            .object({
              binding: z.object({ operationKey: z.string(), lifecycleKey: z.string().uuid() }),
            })
            .parse(proof.resolver)
          if (
            id !== row.id ||
            resolved.binding.operationKey !== proof.operation_key ||
            resolved.binding.lifecycleKey !== proof.lifecycle_key
          )
            return null
        }
      }
      registration = {
        kind: 'workout',
        log_id: row.id,
        workout_type: row.workout_type,
        duration_min: row.duration_min,
        intensity: row.intensity,
        estimated_kcal: row.estimated_kcal,
      }
      logIds = [row.id]
    }
    // Share the closed public contract without asking a model or creating
    // education/day context. The saved total is not reconstructed from floats.
    const valid = prepareRegistrationFeedbackV2({
      registrationId: request.registrationId,
      localDate: proposal.source_local_date,
      locale: null,
      registration,
      officialDay: null,
      policy: null,
      educationAvailable: false,
    })
    return { registration: valid.registration, localDate: valid.local_date, logIds }
  } catch {
    return null
  }
}
