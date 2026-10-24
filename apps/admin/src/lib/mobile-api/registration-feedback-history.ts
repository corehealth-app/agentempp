import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import type { PrivateConfirmedMealState } from './confirmed-meal-read'
import { readRegistrationFeedback } from './registration-feedback-service'
import {
  createWorkoutRegistrationRepository,
  type WorkoutRegistrationPort,
} from './workout-registration-repository'

const candidateSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  status: z.literal('confirmed'),
  proposal: z.record(z.unknown()),
  workout_ui_admission_id: z.string().uuid().nullable(),
})
type Link =
  | { kind: 'meal'; provider: string; mealType: string; localDate: string }
  | { kind: 'workout'; provider: string; workoutType: string }

function matches(proposal: Json, link: Link): boolean {
  if (proposal === null || typeof proposal !== 'object' || Array.isArray(proposal)) return false
  return (
    proposal.kind === link.kind &&
    proposal.source_provider_message_id === link.provider &&
    (link.kind === 'meal'
      ? proposal.registration_origin === 'mobile_app' &&
        proposal.mealType === link.mealType &&
        proposal.source_local_date === link.localDate
      : proposal.workoutType === link.workoutType)
  )
}

/** An inverse lookup is not a foreign key. Ambiguity and malformed replies omit
 * enrichment, never pick the newest registration or manufacture a new receipt. */
async function readLinkedReceipt(db: ServiceClient, userId: string, link: Link) {
  let query = db
    .from('pending_registrations')
    // Match the existing registration reader: the generated table predates
    // the optional protected marker. Validate its actual presence below;
    // never cast an absent marker into permission for a legacy fallback.
    .select('*')
    .eq('user_id', userId)
    .eq('status', 'confirmed')
    .eq('proposal->>kind', link.kind)
    .eq('proposal->>source_provider_message_id', link.provider)
  if (link.kind === 'meal')
    query = query
      .eq('proposal->>registration_origin', 'mobile_app')
      .eq('proposal->>mealType', link.mealType)
      .eq('proposal->>source_local_date', link.localDate)
  else query = query.eq('proposal->>workoutType', link.workoutType)
  const { data, error } = await query.limit(2)
  if (error || !data || data.length !== 1) return null
  const row = data[0],
    parsed = candidateSchema.safeParse(row)
  if (!parsed.success || row.user_id !== userId || !matches(row.proposal, link)) return null
  if (parsed.data.workout_ui_admission_id !== null) {
    if (link.kind !== 'workout') return null
    const projection = await createWorkoutRegistrationRepository(
      db as unknown as WorkoutRegistrationPort,
    ).get(userId, row.id)
    // A negative protected read cannot downgrade to the legacy raw candidate.
    if (
      projection.status !== 'available' ||
      projection.registration.status !== 'confirmed' ||
      projection.registration.id !== row.id ||
      !matches(projection.registration.proposal, link)
    )
      return null
    return readRegistrationFeedback(db, userId, projection.registration)
  }
  return readRegistrationFeedback(db, userId, row)
}

/** Called only after the ordinary C11 owned read. Its version and live totals
 * are unchanged; edits can keep the receipt of the ORIGINAL confirmation. */
export async function readMealHistoryFeedback(
  db: ServiceClient,
  auth: MobileAuthContext,
  state: PrivateConfirmedMealState,
): Promise<RegistrationFeedback | null> {
  try {
    const anchor = state.items[0],
      source = anchor?.raw_provider_message_id
    if (
      state.context.id !== auth.userId ||
      state.context.auth_user_id !== auth.authUserId ||
      state.context.status !== 'active' ||
      state.snapshot.user_id !== auth.userId ||
      !source ||
      !anchor.meal_type ||
      state.items.some(
        (row) =>
          row.user_id !== auth.userId ||
          row.snapshot_id !== state.snapshot.id ||
          row.raw_provider_message_id !== source ||
          row.meal_type !== anchor.meal_type,
      )
    )
      return null
    return await readLinkedReceipt(db, auth.userId, {
      kind: 'meal',
      provider: source,
      mealType: anchor.meal_type,
      localDate: state.snapshot.date,
    })
  } catch {
    return null
  }
}

/** The caller must FIRST complete the strength reader's current lifecycle/fact
 * proof. A pending registration GET alone is not that proof. No day is loaded. */
export async function readWorkoutHistoryFeedback(
  db: ServiceClient,
  userId: string,
  workoutId: string,
): Promise<RegistrationFeedback | null> {
  try {
    const { data, error } = await db
      .from('workout_logs')
      .select('id,user_id,raw_provider_message_id,workout_type')
      .eq('user_id', userId)
      .eq('id', workoutId)
      .maybeSingle()
    if (
      error ||
      !data ||
      data.id !== workoutId ||
      data.user_id !== userId ||
      !data.raw_provider_message_id ||
      !data.workout_type
    )
      return null
    return await readLinkedReceipt(db, userId, {
      kind: 'workout',
      provider: data.raw_provider_message_id,
      workoutType: data.workout_type,
    })
  } catch {
    return null
  }
}

export function includesRegistrationFeedback(request: Request): boolean {
  return new URL(request.url).searchParams.get('include') === 'registration_feedback'
}
