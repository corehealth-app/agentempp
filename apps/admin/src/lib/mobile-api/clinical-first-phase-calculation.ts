/** Explicit later entry, dormant private projection. No signup/FULL substitute,
 * profile mutation, default route, flag, client effect or writer. SQL must bind
 * the current no-plan source/health/profile/config/day to this dedicated scope. */
import { computeDailyTargetsOnCivilDate } from '@mpp/core'
import {
  clinicalDateOrdinal,
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import { readClinicalGenerationAuthority } from './clinical-generation-authority'
import {
  clinicalPhaseEntryDeficit,
  clinicalPhaseEntryEpisode,
  projectClinicalPhaseEntry,
} from './clinical-phase-entry-policy'
import {
  clinicalCalculationSnapshotSchema,
  readClinicalCalculationConfigRows,
  readClinicalFormulaBodyFat,
} from './clinical-snapshot-calculation'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const phase = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
const origin = z
  .object({
    kind: z.literal('confirmed_no_plan'),
    signupGeneration: uuid,
    signupEpoch: uuid,
    completedAt: instant,
  })
  .strict()
const base = clinicalCalculationSnapshotSchema.shape.facts
const contextSchema = clinicalCalculationSnapshotSchema
  .extend({
    review_kind: z.literal('FIRST_PHASE'),
    cycle_id: z.null(),
    facts: base.extend({
      first_phase: z.object({ effective_date: date }).strict(),
      protocol_authority: base.shape.protocol_authority.extend({
        phase_origin: origin,
        episode: z.null(),
        signup_origin: z.null(),
        target_origin: z.null().optional(),
        confirmed_calorie_decision: z.null().optional(),
        body_fat_candidate: z.null(),
      }),
    }),
  })
  .strict()
const selectionSchema = z.object({ phase }).strict()
type Context = z.infer<typeof contextSchema>
function invalid(): never {
  throw new Error('Invalid first phase context')
}
function immutable<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) immutable(child)
    Object.freeze(value)
  }
  return value
}
function readContext(raw: unknown, userId: string) {
  try {
    uuid.parse(userId)
    const serialized = JSON.stringify(raw)
    if (!serialized || serialized.length > 2097152) return invalid()
    const value = contextSchema.parse(JSON.parse(serialized)),
      { facts } = value,
      { profile, anchor } = facts
    const generationAuthority = readClinicalGenerationAuthority(anchor, {
      userId,
      profileCompletedAt: profile.onboarding_completed_at,
      observedAt: value.observed_at,
    })
    const source = facts.protocol_authority.phase_origin
    if (
      generationAuthority.kind !== 'signup_receipt' ||
      [value.user_id, facts.owner.id, profile.user_id, facts.safety.user_id].some(
        (id) => id !== userId,
      ) ||
      profile.current_protocol !== null ||
      profile.deficit_level !== null ||
      source.signupGeneration !== anchor.signup_generation ||
      source.signupEpoch !== anchor.signup_epoch ||
      source.completedAt !== profile.onboarding_completed_at ||
      source.completedAt > value.observed_at ||
      value.valid_until <= value.observed_at ||
      facts.safety.hold_active !== Boolean(facts.safety.items.length) ||
      new Set(facts.safety.items.map((v) => v.code)).size !== facts.safety.items.length ||
      (facts.day && (facts.day.user_id !== userId || facts.day.date !== facts.calculation_date)) ||
      clinicalDateOrdinal(facts.first_phase.effective_date) !==
        clinicalDateOrdinal(facts.calculation_date) + (facts.day?.day_closed ? 1 : 0) ||
      [profile.weight_kg, profile.height_cm, profile.body_fat_percent].some(
        (v) => v !== null && Math.abs(v * 100 - Math.round(v * 100)) > 1e-9,
      )
    )
      return invalid()
    const bodyFat = readClinicalFormulaBodyFat(value, userId)
    const config = readClinicalCalculationConfigRows(facts.calculation_config)
    return { value, bodyFat, ...config }
  } catch {
    return invalid()
  }
}
function project(value: Context) {
  const { facts } = value
  return projectClinicalPhaseEntry({
    date: facts.calculation_date,
    effectiveDate: facts.first_phase.effective_date,
    profile: facts.profile,
    hold: { active: facts.safety.hold_active, items: facts.safety.items.map((v) => v.code) },
    calculationConfig: facts.calculation_config,
  })
}
export function projectClinicalFirstPhase(raw: unknown, userId: string) {
  const snapshot = readContext(raw, userId)
  return immutable(project(snapshot.value))
}
export function evaluateClinicalFirstPhase(raw: unknown, userId: string, rawChoice: unknown) {
  const snapshot = readContext(raw, userId),
    choice = selectionSchema.parse(structuredClone(rawChoice))
  const options = project(snapshot.value)
  if (
    options.availability !== 'available' ||
    !options.options.some((o) => o.phase === choice.phase && o.status === 'available')
  )
    throw new Error('First phase choice unavailable')
  const { value, config, officialProtein, bodyFat } = snapshot,
    { facts } = value,
    { profile } = facts
  const deficitLevel = clinicalPhaseEntryDeficit(
    choice.phase,
    profile.hunger_level,
    facts.calculation_config,
  )
  const row = {
    ...profile,
    current_protocol: choice.phase,
    deficit_level: deficitLevel,
    body_fat_percent: bodyFat.formulaBodyFatPercent,
    goal_type: null,
    goal_value: null,
    water_intake: null,
  }
  const targets = computeDailyTargetsOnCivilDate(row, config, facts.first_phase.effective_date)
  const fixedProtein =
    choice.phase === 'recomposicao' &&
    config.recomp_protein_g_per_kg != null &&
    config.recomp_protein_g_per_kg !== 0
  if (
    targets.calories_target === null ||
    targets.protein_target === null ||
    (!fixedProtein && !officialProtein)
  )
    throw new Error('First phase calculation unavailable')
  z.number().int().positive().max(2147483647).parse(targets.calories_target)
  z.number().finite().min(0).max(9999.99).parse(targets.protein_target)
  return immutable({
    context: value,
    selection: choice,
    package: {
      version: 1 as const,
      phase: choice.phase,
      deficitLevel,
      effectiveDate: facts.first_phase.effective_date,
      targets: {
        beforeKcal: facts.day?.calories_target ?? null,
        beforeProtein: facts.day?.protein_target ?? null,
        afterKcal: targets.calories_target,
        afterProtein: targets.protein_target,
        formulaAfterKcal: targets.calories_target,
      },
      formulaBodyFat: { origin: bodyFat.origin, percent: bodyFat.formulaBodyFatPercent },
      episode: clinicalPhaseEntryEpisode(
        choice.phase,
        facts.calculation_date,
        facts.day?.day_closed ?? false,
      ),
    },
  })
}
