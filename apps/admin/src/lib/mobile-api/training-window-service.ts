/** Official recorded activities only. Reading never writes, estimates a new
 * energy value, grants XP, or adds exercise calories to the food budget. */
import { getLocalDateString } from '@mpp/agent'
import { z } from 'zod'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'
import {
  clinicalWindowDates,
  type OwnedClinicalWindowScope,
  parseOwnedClinicalWindowScope,
} from './owned-clinical-window'

const amount = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER).nullable()
const workoutSchema = z
  .object({
    id: z.string().uuid(),
    user_id: z.string().uuid(),
    workout_type: z.string().min(1).max(240).nullable(),
    duration_min: z.number().finite().positive().max(Number.MAX_SAFE_INTEGER).nullable(),
    estimated_kcal: amount,
    intensity: z.string().min(1).max(240).nullable(),
    performed_at: z.string().datetime({ offset: true }),
  })
  .strict()
const captureSchema = z
  .object({ workouts: z.array(workoutSchema).max(1000), count: z.number().int().min(0).max(1000) })
  .strict()
type Capture = z.infer<typeof captureSchema>
export interface TrainingWindowDependencies {
  observe(): Promise<OwnedClinicalWindowScope>
  capture(window: ReturnType<typeof clinicalWindowDates>): Promise<unknown>
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'training_window_unavailable',
    'A complete training window is unavailable',
  )
}
function changed(): never {
  throw new MobileApiError(
    409,
    'training_window_changed',
    'Training changed during this read; refresh the window',
  )
}
function capture(raw: unknown, owner: string): Capture {
  const p = captureSchema.safeParse(raw)
  if (!p.success) return unavailable()
  const c = p.data
  if (
    c.count !== c.workouts.length ||
    new Set(c.workouts.map((w) => w.id)).size !== c.count ||
    c.workouts.some((w) => w.user_id !== owner)
  )
    return unavailable()
  return c
}
function version(c: Capture) {
  return hashMobileRequest({
    workouts: [...c.workouts].sort((a, b) => a.id.localeCompare(b.id)),
    count: c.count,
  })
}
function validatedScope(raw: unknown) {
  const s = parseOwnedClinicalWindowScope(raw)
  if (conversationJournalInstant(s.policy.observed_at) > conversationJournalInstant(s.observedAt))
    return unavailable()
  return s
}
export function projectTrainingWindow(
  rawScope: unknown,
  selectedDate: string | undefined,
  rawCapture: unknown,
) {
  const scope = validatedScope(rawScope),
    window = clinicalWindowDates(scope.timezone, selectedDate ?? scope.currentLocalDate),
    c = capture(rawCapture, scope.ownerID)
  const observation = conversationJournalInstant(scope.observedAt)
  const facts = c.workouts
    .map((w) => {
      const localDate = getLocalDateString(scope.timezone, new Date(w.performed_at))
      if (
        !window.dates.includes(localDate) ||
        conversationJournalInstant(w.performed_at) > observation
      )
        return unavailable()
      const { user_id: _owner, ...record } = w
      return { localDate, record }
    })
    .sort((a, b) => {
      const left = conversationJournalInstant(a.record.performed_at),
        right = conversationJournalInstant(b.record.performed_at)
      return left < right ? -1 : left > right ? 1 : a.record.id.localeCompare(b.record.id)
    })
  return {
    schema: 'training.window.v1' as const,
    auth_user_id: scope.authUserID,
    owner_id: scope.ownerID,
    epoch: scope.epoch,
    timezone: scope.timezone,
    current_local_date: scope.currentLocalDate,
    selected_local_date: window.selectedDate,
    week_start: window.weekStart,
    week_end: window.weekEnd,
    observed_at: scope.observedAt,
    source_version: version(c),
    completeness: 'complete' as const,
    clinical_policy: scope.policy,
    days: window.dates.map((local_date) => ({
      local_date,
      workouts: facts.filter((f) => f.localDate === local_date).map((f) => f.record),
    })),
  }
}
export async function readTrainingWindow(
  auth: { userId: string; authUserId: string },
  selectedDate: string | undefined,
  dependencies: TrainingWindowDependencies,
) {
  const observe = dependencies.observe.bind(dependencies),
    read = dependencies.capture.bind(dependencies),
    before = validatedScope(await observe())
  if (before.ownerID !== auth.userId || before.authUserID !== auth.authUserId) return changed()
  const window = clinicalWindowDates(before.timezone, selectedDate ?? before.currentLocalDate)
  const first = capture(await read(window), before.ownerID),
    second = capture(await read(window), before.ownerID)
  if (version(first) !== version(second)) return changed()
  const after = validatedScope(await observe())
  if (
    after.ownerID !== before.ownerID ||
    after.authUserID !== before.authUserID ||
    after.epoch !== before.epoch ||
    after.timezone !== before.timezone ||
    after.currentLocalDate !== before.currentLocalDate ||
    after.binding !== before.binding ||
    conversationJournalInstant(after.observedAt) < conversationJournalInstant(before.observedAt) ||
    hashMobileRequest(after.policy) !==
      hashMobileRequest({ ...before.policy, observed_at: after.policy.observed_at })
  )
    return changed()
  return projectTrainingWindow(after, selectedDate, second)
}
