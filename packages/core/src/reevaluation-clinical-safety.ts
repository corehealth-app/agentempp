import { z } from 'zod'
import { HEALTH_RISK_CODES } from './health-check-contracts.js'
import { calcIMC } from './nutrition.js'

/** Server-derived civil dates, never the host clock or a client timestamp. */
export const clinicalCivilDateSchema = z.string().refine((value) => {
  if (!/^\d{4}-\d\d-\d\d$/.test(value) || value.startsWith('0000')) return false
  const instant = new Date(`${value}T00:00:00.000Z`)
  return Number.isFinite(instant.getTime()) && instant.toISOString().slice(0, 10) === value
})
export const clinicalTimestampSchema = z.string().refine((value) => {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(value) || value.startsWith('0000'))
    return false
  const ms = `${value.slice(0, 23)}Z`
  const instant = new Date(ms)
  return Number.isFinite(instant.getTime()) && instant.toISOString() === ms
})
export function clinicalDateOrdinal(value: string): number {
  const date = clinicalCivilDateSchema.parse(value)
  return new Date(`${date}T00:00:00.000Z`).getTime() / 86400000
}
export function ageOnClinicalDate(birthDate: string, date: string): number {
  const birth = clinicalCivilDateSchema.parse(birthDate)
  const today = clinicalCivilDateSchema.parse(date)
  if (birth > today) throw new RangeError('Birth date is after the clinical date')
  return (
    Number(today.slice(0, 4)) -
    Number(birth.slice(0, 4)) -
    (today.slice(5) < birth.slice(5) ? 1 : 0)
  )
}
const holdSchema = z
  .object({
    active: z.boolean(),
    items: z.array(z.enum(HEALTH_RISK_CODES)).max(8),
  })
  .strict()
  .refine(
    (value) =>
      value.active === value.items.length > 0 && new Set(value.items).size === value.items.length,
  )
const safetySchema = z
  .object({
    date: clinicalCivilDateSchema,
    birthDate: clinicalCivilDateSchema.nullable(),
    heightCm: z.number().finite().positive().nullable(),
    weightKg: z.number().finite().min(30).max(300).nullable(),
    // Guard evidence may be a report; it is not authority to use that report in BMR.
    bodyFatPercent: z.number().finite().positive().max(100).nullable(),
    hold: holdSchema,
  })
  .strict()
export type ReevaluationSafetyInput = z.infer<typeof safetySchema>

/** n10 including the human A1/A2 override. Pure projection only: no state clear,
 * clinical write, substitute calorie target or automatic phase transition. */
export function evaluateReevaluationSafety(input: unknown) {
  const value = safetySchema.parse(input)
  const age = value.birthDate === null ? null : ageOnClinicalDate(value.birthDate, value.date)
  const bmi =
    value.weightKg !== null && value.heightCm !== null
      ? calcIMC(value.weightKg, value.heightCm)
      : null
  if (bmi !== null && !Number.isFinite(bmi)) throw new RangeError('Invalid BMI context')
  const lowWeight = age === null || bmi === null ? null : age >= 18 && bmi < 18.5
  const lowBodyFat = value.bodyFatPercent === null ? null : value.bodyFatPercent <= 10
  const under18 = age === null ? null : age < 18
  const pregnant = value.hold.items.includes('pregnant_or_breastfeeding')
  const noPlan = under18 === true || pregnant
  const lossGuard = lowWeight === true || lowBodyFat === true
  const missing = (['birthDate', 'weightKg', 'heightCm'] as const).filter(
    (field) => value[field] === null,
  )
  const complete = missing.length === 0
  const paused = !complete || noPlan || lossGuard || value.hold.active
  return {
    assessment: complete ? ('complete' as const) : ('incomplete' as const),
    missing,
    age,
    bmi,
    guards: { lowWeight, lowBodyFat, under18, pregnantOrBreastfeeding: pregnant },
    holdActive: value.hold.active,
    noPlan,
    pauseWeightLossGuidance: noPlan || lossGuard || value.hold.active,
    automaticTargetChangeAllowed: !paused,
    neutralExitAllowed: complete && value.hold.active && !noPlan && !lossGuard,
    professionalAssessmentRecommended: noPlan || lossGuard || value.hold.active,
    recordingAllowed: true as const,
    hide: {
      objective: noPlan,
      calories: noPlan,
      protein: noPlan || value.hold.items.includes('professional_diet'),
      balance: noPlan,
      block: noPlan,
      budget: noPlan,
    },
  }
}
export type ReevaluationSafety = ReturnType<typeof evaluateReevaluationSafety>
