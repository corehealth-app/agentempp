import { getLocalDateString, loadOfficialDailyState } from '@mpp/agent'
import {
  prepareRegistrationFeedback,
  type RegistrationFeedback,
  type RegistrationFeedbackInput,
} from '@mpp/agent/registration-feedback'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  createSupabaseRegistrationFeedbackStore,
  parseRegistrationFeedback,
  type RegistrationFeedbackIdentity,
  type RegistrationFeedbackStore,
} from './registration-feedback-store'

interface ConfirmedRegistration {
  id: string
  user_id?: string
  status: string
  proposal: Json
  confirmedWorkoutId?: string
}
export type RegistrationFeedbackDaySnapshot = NonNullable<RegistrationFeedbackInput['day']> & {
  consumed: NonNullable<RegistrationFeedbackInput['day']>['consumed'] & { source: string }
  meals: readonly { id: string }[]
  workouts: readonly { id: string }[]
}
interface FeedbackDependencies {
  store: RegistrationFeedbackStore
  loadDay(
    db: ServiceClient,
    userId: string,
    timezone: string,
    instant: Date,
  ): Promise<RegistrationFeedbackDaySnapshot>
  loadLogIds(
    db: ServiceClient,
    identity: RegistrationFeedbackIdentity,
    proposal: { source_provider_message_id: string; workoutType?: string },
  ): Promise<string[]>
}
const number = z.number().finite().min(0).max(Number.MAX_SAFE_INTEGER)
const nutrients = z.object({ kcal: number, protein_g: number, carbs_g: number, fat_g: number })
const meal = z.object({
  kind: z.literal('meal'),
  mealType: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
  totals: nutrients,
  items: z
    .array(nutrients.extend({ name: z.string().trim().min(1) }))
    .min(1)
    .max(30),
})
const timing = z.object({
  source_timestamp: z.string().datetime({ offset: true }),
  source_timezone: z.string().min(1),
  source_local_date: z.string().date(),
  source_provider_message_id: z.string().min(1),
  workoutType: z.string().min(1).optional(),
})

function identityFor(
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

async function loadLogIds(
  db: ServiceClient,
  identity: RegistrationFeedbackIdentity,
  source: { source_provider_message_id: string; workoutType?: string },
): Promise<string[]> {
  if (identity.kind === 'workout' && !source.workoutType) return []
  const { data, error } =
    identity.kind === 'meal'
      ? await db
          .from('meal_logs')
          .select('id')
          .eq('user_id', identity.userId)
          .eq('raw_provider_message_id', source.source_provider_message_id)
          .limit(31)
      : await db
          .from('workout_logs')
          .select('id')
          .eq('user_id', identity.userId)
          .eq('raw_provider_message_id', source.source_provider_message_id)
          .eq('workout_type', source.workoutType ?? '')
          .limit(31)
  if (error) throw new Error('Unable to link confirmed registration to its day')
  const ids = z
    .array(z.object({ id: z.string().uuid() }).strict())
    .max(30)
    .parse(data)
  return ids.map((row) => row.id)
}

async function provenDay(
  db: ServiceClient,
  row: ConfirmedRegistration,
  identity: RegistrationFeedbackIdentity,
  deps: FeedbackDependencies,
): Promise<RegistrationFeedbackInput['day']> {
  // This is a read of official facts, never the Today handler that closes days.
  try {
    const source = timing.parse(row.proposal)
    const instant = new Date(source.source_timestamp)
    if (getLocalDateString(source.source_timezone, instant) !== source.source_local_date)
      return null
    const state = await deps.loadDay(db, identity.userId, source.source_timezone, instant)
    if (state.local_date !== source.source_local_date || state.consumed.source !== 'daily_snapshot')
      return null
    const ids =
      identity.kind === 'workout' && row.confirmedWorkoutId
        ? [z.string().uuid().parse(row.confirmedWorkoutId)]
        : await deps.loadLogIds(db, identity, source)
    const observed = new Set(
      (identity.kind === 'meal' ? state.meals : state.workouts).map((log) => log.id),
    )
    if (ids.length === 0 || ids.some((id) => !observed.has(id))) return null
    return {
      local_date: state.local_date,
      current_protocol: state.current_protocol,
      remaining_food_kcal: state.remaining_food_kcal,
      food_excess_kcal: state.food_excess_kcal,
      exercise_kcal: state.exercise_kcal,
      consumed: {
        calories_kcal: state.consumed.calories_kcal,
        protein_g: state.consumed.protein_g,
        carbs_g: state.consumed.carbs_g,
        fat_g: state.consumed.fat_g,
      },
      targets: { calories_kcal: state.targets.calories_kcal, protein_g: state.targets.protein_g },
    }
  } catch {
    return null
  }
}

/** Owned read path only. Reopening never selects a phrase, reads a day or writes a receipt. */
export async function readRegistrationFeedback(
  db: ServiceClient,
  userId: string,
  row: ConfirmedRegistration,
  store: RegistrationFeedbackStore = createSupabaseRegistrationFeedbackStore(db),
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

/** Optional enrichment AFTER business success. It never executes or retries a registration writer. */
export async function ensureRegistrationFeedback(
  db: ServiceClient,
  auth: MobileAuthContext,
  row: ConfirmedRegistration,
  dependencies?: Partial<FeedbackDependencies>,
): Promise<RegistrationFeedback | null> {
  try {
    const identity = identityFor(auth.userId, row)
    if (!identity) return null
    const deps: FeedbackDependencies = {
      store: dependencies?.store ?? createSupabaseRegistrationFeedbackStore(db),
      loadDay: dependencies?.loadDay ?? loadOfficialDailyState,
      loadLogIds: dependencies?.loadLogIds ?? loadLogIds,
    }
    const saved = await deps.store.readReceipt(identity)
    if (saved.action === 'available') return parseRegistrationFeedback(saved.feedback, identity)
    if (saved.action === 'event_conflict') return null
    const parsedMeal = identity.kind === 'meal' ? meal.parse(row.proposal) : null
    const facts: RegistrationFeedbackInput = {
      userId: identity.userId,
      registrationId: row.id,
      locale: auth.patient.locale,
      accountName: auth.patient.name,
      registration:
        parsedMeal === null
          ? { status: 'confirmed', kind: 'workout' }
          : {
              status: 'confirmed',
              kind: 'meal',
              mealKind: parsedMeal.mealType,
              totals: parsedMeal.totals,
              items: parsedMeal.items.map(({ name, ...item }) => ({ ...item, food_name: name })),
            },
      day: await provenDay(db, row, identity, deps),
    }
    const expectedProposal = structuredClone(row.proposal)
    for (let attempt = 0; attempt < 3; attempt++) {
      const snapshot = await deps.store.loadCursor(identity.userId)
      const prepared = prepareRegistrationFeedback(facts, snapshot.cursor)
      try {
        const result = await deps.store.commit({
          ...identity,
          expectedProposal,
          expectedCursorRevision: snapshot.cursorRevision,
          expectedCursor: snapshot.cursor,
          steps: prepared.steps,
          feedback: prepared.feedback,
        })
        if (result.action === 'committed' || result.action === 'replay')
          return parseRegistrationFeedback(result.feedback, identity)
        if (result.action !== 'cursor_conflict') return null
      } catch {
        // Outcome is unknown. Resolve once by read, never blindly repeat this commit.
        const recovered = await deps.store.readReceipt(identity)
        return recovered.action === 'available'
          ? parseRegistrationFeedback(recovered.feedback, identity)
          : null
      }
    }
    return null
  } catch {
    // No private input/error reaches telemetry and a saved meal/workout stays successful.
    return null
  }
}
