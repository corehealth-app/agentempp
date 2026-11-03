/** Read-only enrichment; never install the runtime factory, admission or daily effects here. */
import type { FlowClinicalPolicy, FlowClinicalToday } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
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
import type { FeedbackV2Observation } from './registration-feedback-v2-store'
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
  exercise_calories: amount,
})
export interface FeedbackV2ClinicalContext {
  policy: FlowClinicalPolicy
  officialDay: FlowClinicalToday | null
}
export interface FeedbackV2ClinicalDependencies {
  source?: CurrentClinicalStateSource
  readers?: CurrentClinicalReaderSources
}
/** Optional facts only. A source mismatch withholds the day; commit still
 * recaptures the complete SQL context so stale facts cannot be sealed. */
export function proveFeedbackV2Day(
  observation: FeedbackV2Observation,
  today: FlowClinicalToday,
): FlowClinicalToday | null {
  try {
    const { context, facts, clinical } = observation
    const s = savedDay.parse(context.snapshot)
    if (
      s.user_id !== context.user_id ||
      s.date !== facts.localDate ||
      clinical.date !== facts.localDate ||
      today.local_date !== facts.localDate ||
      today.consumed.source !== 'daily_snapshot'
    )
      return null
    const rows = facts.registration.kind === 'meal' ? today.meals : today.workouts
    if (facts.logIds.some((id) => rows.filter((row) => row.id === id).length !== 1)) return null
    if (
      today.consumed.calories_kcal !== s.calories_consumed ||
      today.consumed.protein_g !== s.protein_g ||
      today.consumed.carbs_g !== s.carbs_g ||
      today.consumed.fat_g !== s.fat_g ||
      today.exercise_kcal !== s.exercise_calories
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
    return today
  } catch {
    return null
  }
}
export async function loadFeedbackV2ClinicalContext(
  db: ServiceClient,
  auth: MobileAuthContext,
  observation: FeedbackV2Observation,
  dependencies: FeedbackV2ClinicalDependencies = {},
): Promise<FeedbackV2ClinicalContext> {
  const who = structuredClone(auth)
  const owner = authenticatedReevaluationOwner(who)
  const expected = readCurrentClinicalState(observation.context.clinical, owner)
  if (owner !== observation.context.user_id) throw currentClinicalError('changed')
  const policy = projectCurrentClinicalPublicPolicy(expected)
  // A current-day reader must not supply today's totals to a historical event,
  // and incomplete observation cannot authorize targets through a numeric read.
  if (expected.date !== observation.facts.localDate || expected.assessment !== 'complete')
    return { policy, officialDay: null }
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
          state.observed_at < expected.observed_at ||
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
    const today = await createCurrentClinicalReadModel(db, pinned, dependencies.readers).today(
      who,
      'https://feedback.internal.invalid/today?clinical_policy=current_clinical_v1',
    )
    return Object.freeze({ policy, officialDay: proveFeedbackV2Day(observation, today) })
  } catch (error) {
    if (
      observationFailure ||
      (error instanceof MobileApiError && error.code === 'mobile_current_clinical_changed')
    )
      throw currentClinicalError('changed')
    // An optional numeric reader is not an alternative source of clinical
    // authority. Keep the pinned policy and let SQL's final CAS prove it again.
    return Object.freeze({ policy, officialDay: null })
  }
}
