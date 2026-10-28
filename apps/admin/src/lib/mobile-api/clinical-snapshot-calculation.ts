/** Server-only, dormant clinical calculation. No DB/cache, model, clock, route,
 * flag or writer is composed here. Inputs come from the private SQL snapshot;
 * a numeric result is a projection, never permission to apply a target. */
import {
  type CalcConfig,
  calcBMR,
  computeDailyTargetsOnCivilDate,
  DEFAULT_CALC_CONFIG,
} from '@mpp/core'
import { healthRiskCodeSchema } from '@mpp/core/health-check'
import {
  ageOnClinicalDate,
  clinicalCivilDateSchema as civilDate,
  evaluateReevaluationSafety,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import {
  isFullReevaluationKind,
  legacyReevaluationOriginSchema,
  reevaluationFormDraftSchema,
  requiresReevaluationPhotos,
} from '@mpp/core/reevaluation-form'
import { isOfficialClinicalProteinTable } from '@mpp/core/reevaluation-protein-inputs'
import { z } from 'zod'
import {
  clinicalGenerationAnchorSchema,
  readClinicalGenerationAuthority,
} from './clinical-generation-authority'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const hash = z.string().regex(/^[a-f0-9]{64}$/)
const phase = z.enum(['recomposicao', 'manutencao', 'ganho_massa'])
const level = z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
const deficit = z.union([z.literal(400), z.literal(500), z.literal(600)])
const bf = z
  .number()
  .finite()
  .min(3)
  .max(60)
  .refine((n) => Math.abs(n * 100 - Math.round(n * 100)) < 1e-9)
const positive = z.number().finite().positive()
const kcal = positive.int().safe().max(2147483647)
const protein = z.number().finite().min(0).max(9999.99)
const configRow = z.object({
  key: z.string().startsWith('calc.').max(256),
  value: z.unknown(),
  updated_at: instant,
})
const boundOrigin = z.object({ user_id: uuid, signup_generation: uuid, signup_epoch: uuid })
/** Actual signup entry evidence, never historical formula evidence. */
export const clinicalSignupOriginSchema = boundOrigin
  .extend({
    episode_id: uuid,
    phase,
    started_at: instant,
    start_date: civilDate,
    timezone_at_entry: z.string().min(1).max(256),
    start_weight_kg: z.number().finite().min(30).max(300),
    start_height_cm: positive,
    start_body_fat_percent: bf.nullable(),
    start_training_frequency: z.number().int().min(0).max(7).nullable(),
    start_activity_level: level.nullable(),
    deficit_level: deficit.nullable(),
    maintenance_since: civilDate.nullable(),
    captured_at: instant,
    rule_version: z.literal('clinical-v1'),
  })
  .strict()
  .refine(
    (v) =>
      v.captured_at >= v.started_at &&
      (v.phase === 'recomposicao') === (v.deficit_level !== null) &&
      (v.phase === 'manutencao') === (v.maintenance_since !== null) &&
      (v.maintenance_since === null || v.maintenance_since === v.start_date),
  )
/** Applied target evidence is separate from a BF measurement origin. It never
 * makes a subsequent typed report eligible for the formula. */
export const clinicalTargetOriginSchema = boundOrigin
  .extend({
    version: z.literal(1),
    source: z.enum([
      'clinical_full_v1',
      'clinical_daily_v1',
      'clinical_signup_v1',
      'clinical_first_phase_v1',
    ]),
    target_component: z.literal('calories'),
    origin_id: uuid,
    snapshot_id: uuid,
    date: civilDate,
    phase,
    calories_target: kcal,
    formula_target: kcal,
    review_id: uuid.nullable(),
    application_id: uuid.nullable().optional(),
    signup_application_id: uuid.nullable().optional(),
    first_phase_id: uuid.nullable().optional(),
    context_hash: hash,
    recorded_at: instant,
  })
  .refine((v) =>
    v.source === 'clinical_first_phase_v1'
      ? v.review_id === null &&
        v.application_id == null &&
        v.signup_application_id == null &&
        v.first_phase_id != null
      : v.first_phase_id == null &&
        (v.source === 'clinical_full_v1'
          ? v.review_id !== null && v.application_id == null && v.signup_application_id == null
          : v.source === 'clinical_daily_v1'
            ? v.review_id === null && v.application_id != null && v.signup_application_id == null
            : v.review_id === null && v.application_id == null && v.signup_application_id != null),
  )
export const confirmedCalorieDecisionSchema = boundOrigin
  .extend({
    version: z.literal(1),
    source: z.enum(['confirmed_full_calculation_v1', 'confirmed_first_phase_calculation_v1']),
    review_id: uuid.nullable(),
    first_phase_id: uuid.nullable().optional(),
    source_episode_event_id: uuid,
    phase,
    decision_kind: z.enum(['calculated', 'preserved_known']),
    decision_date: civilDate,
    valid_from_date: civilDate,
    decided_at: instant,
    calories_target: kcal,
    formula_target: kcal,
    command_hash: hash,
    context_hash: hash,
  })
  .refine((v) =>
    v.source === 'confirmed_full_calculation_v1'
      ? v.review_id !== null && v.first_phase_id == null
      : v.review_id === null && v.first_phase_id != null,
  )
const signupProof = boundOrigin.extend({
  receipt_version: z.literal(1),
  onboarding_completed_at: instant,
  method: z.literal('arithmetic_mean_v1'),
  confirmed_body_fat_percent: bf,
  fingerprint: hash,
  decided_at: instant,
})
const recurringProof = boundOrigin.extend({
  mean_percent: bf,
  confirmed_at: instant,
  source_hash: hash,
})
const candidate = z.discriminatedUnion('availability', [
  z.object({
    version: z.literal(1),
    availability: z.literal('unavailable'),
    mean_percent: z.null(),
    mean_hundredths: z.null(),
    source_hash: z.null(),
  }),
  boundOrigin.extend({
    version: z.literal(1),
    availability: z.literal('available'),
    cycle_id: uuid,
    mean_percent: bf,
    mean_hundredths: z.number().int().min(300).max(6000),
    source_hash: hash,
  }),
])
const snapshotSchema = z.object({
  version: z.literal(1),
  user_id: uuid,
  review_kind: z.enum([
    'REGULAR',
    'EARLY_FULL',
    'TRANSITION_FULL',
    'ROUTINE_REVIEW',
    'SAFETY',
    'APPLICATION',
  ]),
  cycle_id: uuid.nullable(),
  observed_at: instant,
  valid_until: instant,
  context_hash: hash,
  facts: z.object({
    owner: z.object({
      id: uuid,
      status: z.literal('active'),
      locale: z.string().min(1),
      timezone: z.string().min(1),
    }),
    anchor: clinicalGenerationAnchorSchema,
    calculation_date: civilDate,
    profile: z.object({
      user_id: uuid,
      sex: z.enum(['masculino', 'feminino']).nullable(),
      birth_date: civilDate.nullable(),
      height_cm: positive.nullable(),
      weight_kg: z.number().finite().min(30).max(300).nullable(),
      body_fat_percent: positive.max(100).nullable(),
      body_fat_measured_at: instant.nullable(),
      onboarding_completed: z.literal(true),
      onboarding_completed_at: instant.nullable(),
      current_protocol: phase.nullable(),
      deficit_level: deficit.nullable(),
      activity_level: level.nullable(),
      training_frequency: z.number().int().min(0).max(7).nullable(),
      hunger_level: z.enum(['pouca', 'moderada', 'muita']).nullable(),
    }),
    day: z
      .object({
        id: uuid.optional(),
        user_id: uuid,
        date: civilDate,
        calories_target: kcal.nullable(),
        protein_target: protein.nullable(),
        day_closed: z.boolean(),
        current_protocol: phase.nullable().optional(),
      })
      .nullable(),
    calculation_config: z.array(configRow).max(2048),
    protocol_authority: z.object({
      phase_origin: z
        .union([
          legacyReevaluationOriginSchema,
          z.object({ kind: z.enum(['assigned', 'legacy_unassigned', 'confirmed_no_plan']) }),
        ])
        .optional(),
      body_fat_origin: recurringProof.nullable(),
      signup_body_fat_origin: signupProof.nullable(),
      body_fat_candidate: candidate.nullable(),
      target_origin: clinicalTargetOriginSchema.nullable().optional(),
      signup_origin: clinicalSignupOriginSchema.nullable().optional(),
      confirmed_calorie_decision: confirmedCalorieDecisionSchema.nullable().optional(),
      episode: boundOrigin
        .extend({
          event_id: uuid,
          review_id: uuid.nullable(),
          first_phase_id: uuid.nullable().optional(),
        })
        .refine(
          (v) =>
            (v.review_id !== null && v.first_phase_id == null) ||
            (v.review_id === null && v.first_phase_id != null),
        )
        .nullable()
        .optional(),
    }),
    safety: z.object({
      user_id: uuid,
      hold_active: z.boolean(),
      items: z.array(z.object({ code: healthRiskCodeSchema })).max(8),
    }),
  }),
})
/** Shared consumed-field schema; additional FULL authority is validated separately. */
export const clinicalCalculationSnapshotSchema = snapshotSchema
const projectionSchema = z
  .object({
    phase: phase.optional(),
    deficitLevel: deficit.optional(),
    form: reevaluationFormDraftSchema.optional(),
    applyActivityAnswer: z.boolean().default(false),
    proteinInputSource: z.enum(['profile', 'answers']).default('profile'),
    assessmentProposal: z.boolean().default(false),
    bodyFatCandidate: z
      .object({ sourceHash: hash, meanHundredths: z.number().int().min(300).max(6000) })
      .strict()
      .optional(),
  })
  .strict()

const factors = z
  .object({
    sedentario: positive,
    leve: positive,
    moderado: positive,
    alto: positive,
    atleta: positive,
  })
  .strict()
const proteinFactors = z
  .object({
    muita: positive,
    moderada: positive,
    pouca: positive,
    training_low: positive.optional(),
    optimal_mid_training: positive.optional(),
    optimal_high_training: positive.optional(),
  })
  .strict()
const formulaSchemas = {
  bmr_mifflin: z
    .object({
      weight_coef: positive,
      height_coef: positive,
      age_coef: positive,
      male_offset: z.number().finite(),
      female_offset: z.number().finite(),
    })
    .strict(),
  bmr_katch: z.object({ base: positive, lbm_coef: positive }).strict(),
  activity_factors: factors,
  protein_factors: proteinFactors,
  recomp_bmr_multiplier: positive,
  ganho_massa_surplus_multiplier: positive,
}
function configFromSnapshot(rows: z.infer<typeof configRow>[]) {
  const config: CalcConfig = structuredClone(DEFAULT_CALC_CONFIG)
  const seen = new Set<string>()
  let officialProtein = false
  for (const row of rows) {
    if (seen.has(row.key)) throw new Error('Duplicate configuration')
    seen.add(row.key)
    const key = row.key.slice(5)
    if (key === 'recomp_protein_g_per_kg') {
      // Preserve the existing core compatibility contract: 0/null disable;
      // malformed, absent, negative or excessive values fall back to 1.5.
      const value = row.value
      config.recomp_protein_g_per_kg =
        value === null || value === 0
          ? value
          : typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= 3
            ? value
            : DEFAULT_CALC_CONFIG.recomp_protein_g_per_kg
    } else if (Object.hasOwn(formulaSchemas, key)) {
      const typed = key as keyof typeof formulaSchemas
      Object.assign(config, { [key]: formulaSchemas[typed].parse(row.value) })
      if (typed === 'protein_factors') officialProtein = isOfficialClinicalProteinTable(row.value)
    }
  }
  return { config, officialProtein }
}
/** Same consumed formula fields as clinical calculation, without a process cache.
 * A parsed config is not provenance or permission to publish a computed target. */
export function readClinicalCalculationConfigRows(raw: unknown) {
  return configFromSnapshot(z.array(configRow).max(2048).parse(raw))
}
const finite = z.number().finite()
const closeConfigSchemas = {
  xp_rules: z
    .object({
      base: finite,
      training_bonus: finite,
      protein_bonus: finite,
      protein_threshold_g: finite,
      weight_xp: finite.optional(),
      meal_xp: finite.optional(),
      photo_xp: finite.optional(),
      protein_meta_xp: finite.optional(),
      calories_meta_xp: finite.optional(),
      steps_meta_xp: finite.optional(),
      water_meta_xp: finite.optional(),
      sleep_meta_xp: finite.optional(),
      training_xp: finite.optional(),
      perfect_day_xp: finite.optional(),
      persistence_xp: finite.optional(),
    })
    .strict(),
  levels: z
    .array(
      z
        .object({
          level: finite.int().min(1).max(2147483647),
          name: z.string(),
          min: finite,
          max: finite.nullable(),
        })
        .strict(),
    )
    .max(2048),
  badges: z
    .array(
      z
        .object({
          key: z.string(),
          type: z.enum(['streak', 'blocks', 'xp']),
          threshold: finite,
        })
        .strict(),
    )
    .max(2048),
  kcal_block: positive,
}
/** Complete uncached inputs consumed by a closer. A present object replaces the
 * whole key as in the legacy loader, but malformed shapes are refused. Keep XP
 * optional-key presence and level ordering exactly; both affect core behavior.
 * The caller must also validate the computed integer database payload. */
export function readClinicalCloseConfigRows(raw: unknown) {
  const rows = z.array(configRow).max(2048).parse(raw)
  const parsed = configFromSnapshot(rows)
  for (const row of rows) {
    const key = row.key.slice(5)
    if (Object.hasOwn(closeConfigSchemas, key)) {
      const typed = key as keyof typeof closeConfigSchemas
      Object.assign(parsed.config, { [typed]: closeConfigSchemas[typed].parse(row.value) })
    }
  }
  return parsed
}
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
function invalid(): never {
  throw new Error('Invalid clinical calculation context')
}

/** Shared n41 selection only. A verified numeric photo source can feed BMR;
 * a report cannot. This grants neither a phase nor target-write authority. */
export function readClinicalFormulaBodyFat(raw: unknown, expectedUserId: string) {
  const snapshot = snapshotSchema.pick({ user_id: true, observed_at: true, facts: true }).parse(raw)
  const { facts } = snapshot
  const { profile, anchor } = facts
  if (
    [snapshot.user_id, facts.owner.id, profile.user_id, facts.safety.user_id].some(
      (id) => !same(id, expectedUserId),
    )
  )
    invalid()
  const generationSource = readClinicalGenerationAuthority(anchor, {
    userId: expectedUserId,
    profileCompletedAt: profile.onboarding_completed_at,
    observedAt: snapshot.observed_at,
  })
  const bound = (proof: z.infer<typeof boundOrigin>) =>
    same(proof.user_id, expectedUserId) &&
    same(proof.signup_generation, anchor.signup_generation) &&
    same(proof.signup_epoch, anchor.signup_epoch)
  let formulaBodyFatPercent: number | null = null
  let origin: 'none' | 'report' | 'signup' | 'recurring' =
    profile.body_fat_percent === null ? 'none' : 'report'
  const signup = facts.protocol_authority.signup_body_fat_origin
  const recurring = facts.protocol_authority.body_fat_origin
  if (signup && generationSource.kind !== 'signup_receipt') invalid()
  if (signup) {
    if (
      !bound(signup) ||
      signup.onboarding_completed_at !== profile.onboarding_completed_at ||
      signup.confirmed_body_fat_percent !== profile.body_fat_percent ||
      signup.decided_at > snapshot.observed_at
    )
      invalid()
    formulaBodyFatPercent = signup.confirmed_body_fat_percent
    origin = 'signup'
  }
  if (recurring) {
    if (
      !bound(recurring) ||
      recurring.mean_percent !== profile.body_fat_percent ||
      recurring.confirmed_at !== profile.body_fat_measured_at ||
      recurring.confirmed_at > snapshot.observed_at
    )
      invalid()
    formulaBodyFatPercent = recurring.mean_percent
    origin = 'recurring'
  }
  return { formulaBodyFatPercent, origin }
}

/** Selects and validates ONLY consumed fields of the server snapshot. Complete
 * profile/photo/legal rows and raw SQL errors must never reach a public DTO.
 * PostgreSQL owns context hashing, the timezone catalogue and civil date. */
export function calculateClinicalSnapshotTargets(
  raw: unknown,
  expectedUserId: string,
  selection: unknown = {},
) {
  try {
    uuid.parse(expectedUserId)
    const snapshot = snapshotSchema.parse(raw)
    const choice = projectionSchema.parse(selection)
    const { facts } = snapshot
    const { profile, anchor } = facts
    // Health-only FULLs have no clinical target calculation, including after a
    // current guard has lifted. Their first later phase needs explicit authority.
    // Missing/legacy NULL is intentionally not reclassified by this marker.
    if (facts.protocol_authority.phase_origin?.kind === 'confirmed_no_plan') invalid()
    if (
      [snapshot.user_id, facts.owner.id, profile.user_id, facts.safety.user_id].some(
        (id) => !same(id, expectedUserId),
      ) ||
      snapshot.valid_until <= snapshot.observed_at ||
      new Set(facts.safety.items.map((item) => item.code)).size !== facts.safety.items.length ||
      facts.safety.hold_active !== facts.safety.items.length > 0 ||
      (facts.day &&
        (!same(facts.day.user_id, expectedUserId) || facts.day.date !== facts.calculation_date))
    )
      invalid()
    const generationSource = readClinicalGenerationAuthority(anchor, {
      userId: expectedUserId,
      profileCompletedAt: profile.onboarding_completed_at,
      observedAt: snapshot.observed_at,
    })
    const { config, officialProtein } = configFromSnapshot(facts.calculation_config)
    const bound = (proof: z.infer<typeof boundOrigin>) =>
      same(proof.user_id, expectedUserId) &&
      same(proof.signup_generation, anchor.signup_generation) &&
      same(proof.signup_epoch, anchor.signup_epoch)
    const targetOrigin = facts.protocol_authority.target_origin
    const calorieDecision = facts.protocol_authority.confirmed_calorie_decision
    const signupOrigin = facts.protocol_authority.signup_origin
    if (signupOrigin && generationSource.kind !== 'signup_receipt') invalid()
    if (
      signupOrigin &&
      (!bound(signupOrigin) ||
        signupOrigin.captured_at > snapshot.observed_at ||
        signupOrigin.started_at !== profile.onboarding_completed_at)
    )
      invalid()
    const initialSignup =
      snapshot.review_kind === 'APPLICATION' &&
      signupOrigin &&
      !facts.protocol_authority.episode &&
      facts.protocol_authority.phase_origin?.kind === 'assigned'
    if (
      initialSignup &&
      (signupOrigin.phase !== profile.current_protocol ||
        signupOrigin.deficit_level !== profile.deficit_level)
    )
      invalid()
    if (
      calorieDecision &&
      (!bound(calorieDecision) ||
        calorieDecision.phase !== profile.current_protocol ||
        !facts.protocol_authority.episode ||
        !bound(facts.protocol_authority.episode) ||
        !same(calorieDecision.source_episode_event_id, facts.protocol_authority.episode.event_id) ||
        (calorieDecision.source === 'confirmed_full_calculation_v1'
          ? calorieDecision.review_id !== facts.protocol_authority.episode.review_id
          : calorieDecision.first_phase_id !== facts.protocol_authority.episode.first_phase_id) ||
        calorieDecision.valid_from_date > facts.calculation_date ||
        calorieDecision.decided_at > snapshot.observed_at)
    )
      invalid()
    if (
      targetOrigin &&
      (!bound(targetOrigin) ||
        !facts.day?.id ||
        !same(targetOrigin.snapshot_id, facts.day.id) ||
        targetOrigin.date !== facts.day.date ||
        targetOrigin.phase !== facts.day.current_protocol ||
        targetOrigin.calories_target !== facts.day.calories_target ||
        targetOrigin.recorded_at > snapshot.observed_at)
    )
      invalid()
    const acceptedBodyFat = readClinicalFormulaBodyFat(snapshot, expectedUserId)
    let formulaBodyFatPercent = acceptedBodyFat.formulaBodyFatPercent
    let origin:
      | 'none'
      | 'report'
      | 'signup'
      | 'recurring'
      | 'regular_candidate'
      | 'transition_candidate' = acceptedBodyFat.origin
    if (choice.bodyFatCandidate) {
      const photo = facts.protocol_authority.body_fat_candidate
      if (
        !requiresReevaluationPhotos(snapshot.review_kind) ||
        !snapshot.cycle_id ||
        !photo ||
        photo.availability !== 'available' ||
        !bound(photo) ||
        !same(photo.cycle_id, snapshot.cycle_id) ||
        photo.source_hash !== choice.bodyFatCandidate.sourceHash ||
        photo.mean_hundredths !== choice.bodyFatCandidate.meanHundredths ||
        Math.abs(photo.mean_percent * 100 - photo.mean_hundredths) > 1e-9
      )
        invalid()
      formulaBodyFatPercent = photo.mean_percent
      origin =
        snapshot.review_kind === 'TRANSITION_FULL' ? 'transition_candidate' : 'regular_candidate'
    }
    const form = choice.form
    if (form && (form.kind !== snapshot.review_kind || form.phase !== profile.current_protocol))
      invalid()
    if (choice.assessmentProposal && (!form || !isFullReevaluationKind(snapshot.review_kind)))
      invalid()
    if (
      form?.answers.weightKg != null &&
      Math.abs(form.answers.weightKg * 100 - Math.round(form.answers.weightKg * 100)) > 1e-9
    )
      invalid()
    if (form?.phase === null) {
      const phaseOrigin = facts.protocol_authority.phase_origin
      if (
        !('legacyOrigin' in form) ||
        generationSource.kind !== 'legacy_transition' ||
        !requiresReevaluationPhotos(snapshot.review_kind) ||
        !choice.phase ||
        !choice.bodyFatCandidate ||
        phaseOrigin?.kind !== 'legacy_transition_unassigned' ||
        form.legacyOrigin.generation !== generationSource.generation ||
        form.legacyOrigin.epoch !== generationSource.epoch ||
        form.legacyOrigin.admittedAt !== generationSource.admitted_at ||
        phaseOrigin.generation !== form.legacyOrigin.generation ||
        phaseOrigin.epoch !== form.legacyOrigin.epoch ||
        phaseOrigin.admittedAt !== form.legacyOrigin.admittedAt
      )
        invalid()
    }
    const activity = form?.answers.activity
    if (
      choice.applyActivityAnswer &&
      (!activity?.activityLevelConfirmed || activity.activityLevel === null)
    )
      invalid()
    const row = {
      ...profile,
      current_protocol: choice.phase ?? profile.current_protocol,
      deficit_level: choice.deficitLevel ?? profile.deficit_level,
      weight_kg: form?.answers.weightKg ?? profile.weight_kg,
      hunger_level:
        choice.proteinInputSource === 'answers'
          ? (form?.answers.hunger ?? profile.hunger_level)
          : profile.hunger_level,
      training_frequency:
        choice.proteinInputSource === 'answers'
          ? (form?.answers.strengthSessions ?? profile.training_frequency)
          : profile.training_frequency,
      activity_level: choice.applyActivityAnswer
        ? (activity?.activityLevel ?? null)
        : profile.activity_level,
      body_fat_percent: formulaBodyFatPercent,
      goal_type: null,
      goal_value: null,
      water_intake: null,
    }
    const targets = computeDailyTargetsOnCivilDate(row, config, facts.calculation_date)
    const age =
      row.birth_date === null ? null : ageOnClinicalDate(row.birth_date, facts.calculation_date)
    const bmr =
      row.sex !== null && row.height_cm !== null && row.weight_kg !== null && age !== null
        ? calcBMR(
            {
              sex: row.sex,
              heightCm: row.height_cm,
              weightKg: row.weight_kg,
              age,
              bodyFatPercent: formulaBodyFatPercent,
            },
            config,
          )
        : null
    const maintenance = computeDailyTargetsOnCivilDate(
      { ...row, current_protocol: 'manutencao', deficit_level: null },
      config,
      facts.calculation_date,
    )
    const reportedBodyFat =
      requiresReevaluationPhotos(snapshot.review_kind) && choice.bodyFatCandidate
        ? formulaBodyFatPercent
        : profile.body_fat_percent
    const safety = {
      date: facts.calculation_date,
      birthDate: row.birth_date,
      heightCm: row.height_cm,
      weightKg: row.weight_kg,
      bodyFatPercent: reportedBodyFat,
      hold: {
        active: facts.safety.hold_active,
        items: facts.safety.items.map((item) => item.code),
      },
    }
    const guards = evaluateReevaluationSafety(safety)
    const fixedProtein =
      row.current_protocol === 'recomposicao' &&
      config.recomp_protein_g_per_kg !== null &&
      config.recomp_protein_g_per_kg !== 0
    const proteinAuthority = fixedProtein
      ? ('fixed_recomposition' as const)
      : officialProtein
        ? ('official_table' as const)
        : ('unverified_table' as const)
    const storedTargets = facts.day
      ? {
          calories_target: facts.day.calories_target,
          protein_target: facts.day.protein_target,
          day_closed: facts.day.day_closed,
        }
      : null
    // Do not silently migrate an old target whose BF formula origin is unknown.
    // Human policy: unknown old sources stay preserved until a new confirmed
    // assessment. A numeric increase is not evidence of typed-BF formula use.
    // A new immutable applied-target receipt resolves only this target's source;
    // the later typed BF still remains a report, excluded from the formula.
    const prospectiveDecision = calorieDecision && facts.day?.calories_target == null
    const prospectiveSignup = initialSignup && facts.day?.calories_target == null
    const uncertainLegacy =
      origin === 'report' && !targetOrigin && !prospectiveDecision && !prospectiveSignup
    const oldKcal = uncertainLegacy ? (storedTargets?.calories_target ?? null) : null
    if (bmr !== null) positive.parse(bmr)
    if (targets.calories_target !== null) kcal.parse(targets.calories_target)
    if (maintenance.calories_target !== null) kcal.parse(maintenance.calories_target)
    const ready =
      targets.calories_target !== null &&
      (row.current_protocol !== 'recomposicao' || row.deficit_level !== null) &&
      proteinAuthority !== 'unverified_table' &&
      guards.automaticTargetChangeAllowed &&
      (!uncertainLegacy || choice.assessmentProposal)
    return {
      authority: {
        userId: snapshot.user_id,
        signupGeneration: anchor.signup_generation,
        signupEpoch: anchor.signup_epoch,
        contextHash: snapshot.context_hash,
        kind: snapshot.review_kind,
        cycleId: snapshot.cycle_id,
        date: facts.calculation_date,
        observedAt: snapshot.observed_at,
        validUntil: snapshot.valid_until,
      },
      formulaKcal: targets.calories_target,
      proteinTarget: proteinAuthority === 'unverified_table' ? null : targets.protein_target,
      maintenanceKcal: maintenance.calories_target,
      maintenanceProteinTarget: officialProtein ? maintenance.protein_target : null,
      sedentaryKcal: bmr === null || row.activity_level === null ? null : Math.round(bmr * 1.2),
      bmr,
      config,
      formulaBodyFatPercent,
      proteinAuthority,
      bodyFat: {
        kind:
          origin === 'none'
            ? ('absent' as const)
            : origin === 'report'
              ? ('manual_report' as const)
              : ('confirmed_photo' as const),
        origin,
        hundredths: reportedBodyFat === null ? null : Math.round(reportedBodyFat * 100),
      },
      requiresBodyFatConfirmation:
        origin === 'regular_candidate' || origin === 'transition_candidate',
      safety,
      visibility: guards.hide,
      storedTargets,
      legacyTarget: {
        origin: uncertainLegacy ? ('unproven' as const) : ('not_applicable' as const),
        action: uncertainLegacy ? ('preserve' as const) : ('none' as const),
        beforeKcal: oldKcal,
        candidateKcal: null,
      },
      automaticCalculationReady: ready,
      assessmentProposal: choice.assessmentProposal,
      guarded: !guards.automaticTargetChangeAllowed,
    }
  } catch {
    return invalid()
  }
}
