import { addIsoDateDays, getLocalDayUtcBounds } from '@mpp/agent'
import { z } from 'zod'

const uuid = z.string().uuid()
const clock = z.string().datetime({ offset: true })
const civil = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((v) => {
    const d = new Date(`${v}T00:00:00Z`)
    return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === v
  })
const policySchema = z
  .object({
    version: z.literal(1),
    observed_at: clock,
    assessment: z.enum(['complete', 'incomplete']),
    recording_allowed: z.boolean(),
    pause_weight_loss_guidance: z.boolean(),
    professional_assessment_recommended: z.boolean(),
    phase_selection_pending: z.boolean(),
    target_source: z.enum(['assigned_phase', 'official_only', 'unavailable']),
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
const scopeSchema = z
  .object({
    authUserID: uuid,
    ownerID: uuid,
    epoch: uuid,
    timezone: z.string().min(1).max(100),
    currentLocalDate: civil,
    observedAt: clock,
    binding: z.string().min(1),
    policy: policySchema,
  })
  .strict()
export type OwnedClinicalWindowScope = z.infer<typeof scopeSchema>
/** Shared validation of the existing owned clinical read scope, not write authority. */
export function parseOwnedClinicalWindowScope(raw: unknown): OwnedClinicalWindowScope {
  return scopeSchema.parse(raw)
}
export function clinicalWindowDates(timezone: string, selectedDate: string) {
  const date = civil.parse(selectedDate)
  new Intl.DateTimeFormat('en-US', { timeZone: timezone }).format(new Date(0))
  const weekday = (new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7
  const start = addIsoDateDays(date, -weekday)
  const dates = Array.from({ length: 7 }, (_, i) => addIsoDateDays(start, i))
  const end = addIsoDateDays(start, 6)
  return {
    dates,
    selectedDate: date,
    weekStart: start,
    weekEnd: end,
    startUTC: getLocalDayUtcBounds(timezone, start).startIso,
    endUTC: getLocalDayUtcBounds(timezone, end).endExclusiveIso,
  }
}
