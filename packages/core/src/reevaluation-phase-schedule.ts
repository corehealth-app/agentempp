import { z } from 'zod'
import {
  clinicalCivilDateSchema,
  clinicalDateOrdinal,
  evaluateReevaluationSafety,
} from './reevaluation-clinical-safety.js'

const kcal = z.number().int().safe().positive()
const level = z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
const frequency = z.number().int().min(0).max(7).nullable()
const ledger = z
  .array(
    z
      .number()
      .int()
      .min(-200)
      .max(200)
      .refine((v) => v !== 0),
  )
  .max(200)
  .refine(
    (steps) => steps.reduce((sum, step) => sum + Math.abs(step), 0) <= 200,
    'Episode absolute ledger exceeds its cap',
  )
const activitySchema = z
  .object({
    phase: z.enum(['recomposicao', 'manutencao', 'ganho_massa']),
    safety: z.unknown(),
    bmr: z.number().finite().positive(),
    activityFactors: z
      .object({
        sedentario: z.number().finite().positive(),
        leve: z.number().finite().positive(),
        moderado: z.number().finite().positive(),
        alto: z.number().finite().positive(),
        atleta: z.number().finite().positive(),
      })
      .strict(),
    surplusMultiplier: z.number().finite().positive(),
    beforeLevel: level.nullable(),
    confirmedLevel: level.nullable(),
    levelConfirmed: z.boolean(),
    sessions: frequency,
    profileSessions: frequency,
    gainStartSessions: frequency,
    ledgerSteps: ledger,
  })
  .strict()

/** n3 calorie projection only. BMR/config/episode must be bound by the server
 * snapshot; no caller here persists a level, sessions, protein, or calorie step.
 * The confirmation orchestrator also compares protein before deciding whether
 * a same-level frequency answer needs a separate confirmation screen. */
export function evaluateConfirmedActivityChange(input: unknown) {
  const value = activitySchema.parse(input)
  const safety = evaluateReevaluationSafety(value.safety)
  const net = value.ledgerSteps.reduce((sum, step) => sum + step, 0)
  const base = {
    beforeKcal: null as number | null,
    afterKcal: null as number | null,
    activityChanged: false,
    sessionsToSave: null as number | null,
    levelToSave: null as z.infer<typeof level> | null,
    suppressPhaseCalorieStep: false,
    lowStrengthNotice: false,
    ledgerNet: net,
  }
  if (!safety.automaticTargetChangeAllowed)
    return { ...base, status: 'blocked' as const, reason: 'safety' }
  if (!value.levelConfirmed || value.confirmedLevel === null)
    return { ...base, status: 'missing' as const, reason: 'unconfirmed_activity' }
  if (value.beforeLevel === null)
    return { ...base, status: 'missing' as const, reason: 'previous_activity_unknown' }
  function target(at: z.infer<typeof level>) {
    if (value.phase === 'recomposicao') return null
    const tdee = value.bmr * value.activityFactors[at]
    return kcal.parse(
      value.phase === 'ganho_massa'
        ? Math.max(Math.round(tdee), Math.round(tdee * value.surplusMultiplier) + net)
        : Math.max(Math.round(tdee) + net, Math.round(value.bmr * 1.2)),
    )
  }
  const before = target(value.beforeLevel)
  const after = target(value.confirmedLevel)
  if (
    value.phase === 'ganho_massa' &&
    before !== null &&
    after !== null &&
    after > before &&
    (value.sessions === null ||
      value.profileSessions === null ||
      value.gainStartSessions === null ||
      value.sessions < Math.max(value.profileSessions, value.gainStartSessions))
  )
    return {
      ...base,
      beforeKcal: before,
      status: 'blocked' as const,
      reason: 'gain_training_baseline',
    }
  const changed = value.beforeLevel !== value.confirmedLevel
  return {
    ...base,
    status: changed ? ('proposed' as const) : ('unchanged' as const),
    reason: 'confirmed_activity',
    beforeKcal: before,
    afterKcal: after,
    activityChanged: changed,
    levelToSave: value.confirmedLevel,
    sessionsToSave: value.sessions,
    suppressPhaseCalorieStep: changed && value.phase !== 'recomposicao',
    lowStrengthNotice:
      value.phase === 'ganho_massa' && value.sessions !== null && value.sessions < 3,
  }
}

function plusDays(date: string, days: number): string {
  if (!Number.isSafeInteger(days) || days < 0)
    throw new RangeError('Invalid clinical date increment')
  const instant = new Date((clinicalDateOrdinal(date) + days) * 86400000)
  if (!Number.isFinite(instant.getTime())) throw new RangeError('Clinical schedule date overflow')
  return clinicalCivilDateSchema.parse(instant.toISOString().slice(0, 10))
}
function endDate(
  kind: 'recomp_to_maintenance' | 'gain_exit',
  start: string,
  initial: number,
  maintenance: number,
) {
  const gap = kind === 'gain_exit' ? initial - maintenance : maintenance - initial
  const weeksAfterFirst = Math.max(0, Math.ceil(gap / 100) - 1)
  return plusDays(start, weeksAfterFirst * 7)
}

/** A constant-space representation of every frozen date/value, using the
 * versioned 100-kcal/7-day formula. It is a proposal, not a DB confirmation. */
export const reevaluationPhaseScheduleSchema = z
  .object({
    version: z.literal(1),
    kind: z.enum(['recomp_to_maintenance', 'gain_exit']),
    state: z.enum(['running', 'suspended']),
    startDate: clinicalCivilDateSchema,
    startTargetKcal: kcal,
    maintenanceTargetKcal: kcal,
    plannedEndDate: clinicalCivilDateSchema,
  })
  .strict()
  .refine(
    (schedule) =>
      schedule.plannedEndDate ===
      endDate(
        schedule.kind,
        schedule.startDate,
        schedule.startTargetKcal,
        schedule.maintenanceTargetKcal,
      ),
    'Schedule dates do not match frozen values',
  )
export type ReevaluationPhaseSchedule = z.infer<typeof reevaluationPhaseScheduleSchema>
const planSchema = z
  .object({
    date: clinicalCivilDateSchema,
    safety: z.unknown(),
    currentTargetKcal: kcal,
    maintenanceTargetKcal: kcal,
    activityLevelConfirmed: z.boolean(),
  })
  .strict()
function plan(input: unknown, kind: ReevaluationPhaseSchedule['kind']): ReevaluationPhaseSchedule {
  const value = planSchema.parse(input)
  const safety = evaluateReevaluationSafety(value.safety)
  if ((value.safety as { date: string }).date !== value.date)
    throw new Error('Unbound clinical date')
  if (!safety.automaticTargetChangeAllowed || !value.activityLevelConfirmed)
    throw new Error('Schedule requires safe confirmed activity and a separate phase confirmation')
  return reevaluationPhaseScheduleSchema.parse({
    version: 1,
    kind,
    state: 'running',
    startDate: value.date,
    startTargetKcal: value.currentTargetKcal,
    maintenanceTargetKcal: value.maintenanceTargetKcal,
    plannedEndDate: endDate(kind, value.date, value.currentTargetKcal, value.maintenanceTargetKcal),
  })
}
/** n5. Eligibility and the chosen phase are checked by the subsequent server
 * orchestrator; this helper computes the complete schedule for its preview. */
export function planRecompositionTransition(input: unknown) {
  return plan(input, 'recomp_to_maintenance')
}
/** n18. No automatic invitation acceptance or phase write. */
export function planGainExit(input: unknown) {
  return plan(input, 'gain_exit')
}

const applySchema = z
  .object({
    schedule: reevaluationPhaseScheduleSchema,
    date: clinicalCivilDateSchema,
    safety: z.unknown(),
    currentTargetKcal: kcal,
    maintenanceTargetTodayKcal: kcal,
  })
  .strict()
/** The candidate R is TODAY only if this application actually commits the
 * target. A planned date never establishes an earlier effective R on its own.
 * Previously proven R is preserved separately by the episode authority. */
export function evaluatePhaseSchedule(input: unknown) {
  const value = applySchema.parse(input)
  const { schedule, date } = value
  const safety = evaluateReevaluationSafety(value.safety)
  if ((value.safety as { date: string }).date !== date) throw new Error('Unbound clinical date')
  const elapsed = clinicalDateOrdinal(date) - clinicalDateOrdinal(schedule.startDate)
  if (elapsed < 0) throw new RangeError('Schedule has not started')
  const base = {
    phase: schedule.kind === 'gain_exit' ? ('ganho_massa' as const) : ('manutencao' as const),
    targetKcal: value.currentTargetKcal,
    state: 'suspended' as 'running' | 'suspended' | 'completed',
    reachedMaintenance: false,
    maintenanceSinceCandidate: null as string | null,
    needsNewConfirmation: true,
  }
  if (!safety.automaticTargetChangeAllowed) return { ...base, reason: 'safety' }
  if (schedule.state === 'suspended') return { ...base, reason: 'confirmation_required' }
  const step = Math.floor(elapsed / 7) + 1
  const frozen =
    schedule.kind === 'gain_exit'
      ? Math.max(schedule.maintenanceTargetKcal, schedule.startTargetKcal - step * 100)
      : Math.min(schedule.maintenanceTargetKcal, schedule.startTargetKcal + step * 100)
  // The exit's M is frozen; only n5 caps its frozen values at a recalculated alvo.
  const target =
    schedule.kind === 'gain_exit' ? frozen : Math.min(frozen, value.maintenanceTargetTodayKcal)
  const reached =
    target ===
    (schedule.kind === 'gain_exit'
      ? schedule.maintenanceTargetKcal
      : value.maintenanceTargetTodayKcal)
  return {
    ...base,
    targetKcal: kcal.parse(target),
    state: reached ? ('completed' as const) : ('running' as const),
    phase:
      schedule.kind === 'recomp_to_maintenance' || reached
        ? ('manutencao' as const)
        : ('ganho_massa' as const),
    reason: 'confirmed_schedule',
    reachedMaintenance: reached,
    maintenanceSinceCandidate: reached ? date : null,
    needsNewConfirmation: !reached && date >= schedule.plannedEndDate,
  }
}

const invitationSchema = z
  .object({
    startDate: clinicalCivilDateSchema,
    date: clinicalCivilDateSchema,
    limitActive: z.boolean(),
    requested: z.boolean(),
  })
  .strict()
export function gainExitInvitation(input: unknown) {
  const value = invitationSchema.parse(input)
  const days = clinicalDateOrdinal(value.date) - clinicalDateOrdinal(value.startDate)
  if (days < 0) throw new RangeError('Gain episode has not started')
  return {
    week: Math.floor(days / 7) + 1,
    offer: days >= 49 || (value.limitActive && value.requested),
    reinforce: days >= 105,
  }
}
