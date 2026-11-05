/** Read-only enrichment; never install the runtime factory, admission or daily effects here. */

import { isDeepStrictEqual } from 'node:util'
import type { FlowClinicalPolicy } from '@mpp/agent'
import type { FeedbackV3OfficialDay } from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  type CurrentClinicalReaderSources,
  createCurrentClinicalReadModel,
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import {
  type CurrentClinicalStateSource,
  currentClinicalError,
  readCurrentClinicalState,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import type { FeedbackV3Observation } from './registration-feedback-v3-contracts'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

const amount = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
const savedDay = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  date: z.string().date(),
  calories_consumed: amount,
  protein_g: amount,
  carbs_g: amount,
  fat_g: amount,
  calories_target: amount.nullable(),
  protein_target: amount.nullable(),
  exercise_calories: amount.nullable(),
  exercise_energy_complete: z.boolean().optional(),
})
export interface FeedbackV3ClinicalContext {
  policy: FlowClinicalPolicy
  officialDay: FeedbackV3OfficialDay | null
}
export interface FeedbackV3ClinicalDependencies {
  source?: CurrentClinicalStateSource
  readers?: CurrentClinicalReaderSources
}
/** Optional facts only. A source mismatch withholds the day; commit still
 * recaptures the complete SQL context so stale facts cannot be sealed. */
export function proveFeedbackV3Day(
  observation: FeedbackV3Observation,
  today: FeedbackV3OfficialDay,
): FeedbackV3OfficialDay | null {
  try {
    const { context, registration, clinical, localDate, logIds, energyComplete } = observation
    const s = savedDay.parse(context.snapshot)
    const frozen = context.source.kind === 'conversation_workout' || context.source.command !== null
    if (
      s.user_id !== context.user_id ||
      s.date !== localDate ||
      clinical.date !== localDate ||
      today.local_date !== localDate ||
      today.consumed.source !== 'daily_snapshot'
    )
      return null
    const rows = registration.kind === 'meal' ? today.meals : today.workouts
    if (logIds.some((id) => rows.filter((row) => row.id === id).length !== 1)) return null
    if (
      today.consumed.calories_kcal !== s.calories_consumed ||
      today.consumed.protein_g !== s.protein_g ||
      today.consumed.carbs_g !== s.carbs_g ||
      today.consumed.fat_g !== s.fat_g ||
      (!frozen &&
        (today.exercise_kcal !== (energyComplete ? s.exercise_calories : null) ||
          !isDeepStrictEqual(
            today.exercise_energy,
            energyComplete
              ? { status: 'available' }
              : { status: 'unavailable', reason: 'unknown_workout_energy' },
          )))
    )
      return null
    const targets = today.targets
    if (
      (targets.calories_kcal !== null &&
        targets.calories_source === 'daily_snapshot' &&
        targets.calories_kcal !== s.calories_target) ||
      (targets.protein_g !== null &&
        targets.protein_source === 'daily_snapshot' &&
        targets.protein_g !== s.protein_target)
    )
      return null
    if (
      targets.calories_kcal !== null &&
      targets.calories_source === 'daily_snapshot' &&
      ((today.remaining_food_kcal !== null &&
        today.remaining_food_kcal !== Math.max(0, targets.calories_kcal - s.calories_consumed)) ||
        (today.food_excess_kcal !== null &&
          today.food_excess_kcal !== Math.max(0, s.calories_consumed - targets.calories_kcal)))
    )
      return null
    const block = today.block_7700
    if (block.enabled && block.availability === 'available' && block.source === 'user_progress') {
      const progress = z
        .object({
          user_id: z.string().uuid(),
          deficit_block: amount,
          blocks_completed: amount.int(),
        })
        .parse(context.progress)
      if (
        progress.user_id !== context.user_id ||
        block.current_kcal !== progress.deficit_block ||
        block.completed_blocks !== progress.blocks_completed
      )
        return null
    }
    if (!frozen) return today
    // Frozen facts can predate the coverage marker. Current correction must
    // neither certify original coverage nor replace the original energy fact.
    const available =
      energyComplete === true &&
      today.exercise_energy.status === 'available' &&
      today.exercise_kcal === s.exercise_calories
    return {
      ...today,
      exercise_kcal: available ? today.exercise_kcal : null,
      exercise_energy: available
        ? { status: 'available' }
        : {
            status: 'unavailable',
            reason: observation.energyUnavailableReason ?? 'source_unavailable',
          },
    }
  } catch {
    return null
  }
}
export async function loadFeedbackV3ClinicalContext(
  db: ServiceClient,
  auth: MobileAuthContext,
  observation: FeedbackV3Observation,
  dependencies: FeedbackV3ClinicalDependencies = {},
): Promise<FeedbackV3ClinicalContext> {
  const who = structuredClone(auth)
  const owner = authenticatedReevaluationOwner(who)
  const expected = readCurrentClinicalState(observation.context.clinical, owner)
  if (owner !== observation.context.user_id) throw currentClinicalError('changed')
  const policy = projectCurrentClinicalPublicPolicy(expected)
  // Never attach today's totals to a historical event. Incomplete assessment
  // still permits factual intake; the current projector/v3 builder masks goals.
  if (expected.date !== observation.localDate) return { policy, officialDay: null }
  const binding = currentClinicalReadBinding(expected)
  const source = dependencies.source ?? createSupabaseCurrentClinicalStateSource(db)
  const capture = source.capture.bind(source)
  let observationFailure = false
  const pinned: CurrentClinicalStateSource = {
    async capture(request) {
      try {
        if (request.userId !== owner || request.mode !== 'profile')
          throw currentClinicalError('changed')
        const state = readCurrentClinicalState(await capture(request), owner)
        if (
          conversationJournalInstant(state.observed_at) <
            conversationJournalInstant(expected.observed_at) ||
          currentClinicalReadBinding(state) !== binding
        )
          throw currentClinicalError('changed')
        return state
      } catch {
        observationFailure = true
        throw currentClinicalError('changed')
      }
    },
  }
  try {
    const today = await createCurrentClinicalReadModel(
      db,
      pinned,
      dependencies.readers,
    ).todayWithEnergy(
      who,
      'https://feedback.internal.invalid/today?clinical_policy=current_clinical_v1&day_energy=field_availability_v1',
    )
    return Object.freeze({ policy, officialDay: proveFeedbackV3Day(observation, today) })
  } catch (error) {
    const frozen =
      observation.context.source.kind === 'conversation_workout' ||
      observation.context.source.command !== null
    if (
      !frozen &&
      (observationFailure ||
        (error instanceof MobileApiError && error.code === 'mobile_current_clinical_changed'))
    )
      throw currentClinicalError('changed')
    // An optional energy-aware reader is not an alternative source of clinical
    // authority. Keep the pinned policy and let SQL's final CAS prove it again.
    return Object.freeze({ policy, officialDay: null })
  }
}
