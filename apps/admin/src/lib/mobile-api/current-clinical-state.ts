/** Current observation only. No default provider, public RPC, route or writer.
 * A historical onboarding ACK is never an input to this service. */
import { type Protocol, type SignupEligibilityConfig, signupGainCompositionUnmet } from '@mpp/core'
import {
  clinicalCivilDateSchema as date,
  evaluateReevaluationSafety,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import {
  clinicalGenerationAuthoritySchema,
  readClinicalGenerationAuthority,
} from './clinical-generation-authority'
import type { OnboardingCompletionInput } from './contracts'
import { parseHealthHoldSnapshot } from './health-hold-contracts'
import { MobileApiError } from './http'
import { onboardingClinicalSafetySchema } from './onboarding-clinical-safety'
import { asStoredBodyValue, decideOnboardingEligibility } from './protocol-eligibility-service'
import type { SignupPhotoGenerationToken } from './signup-body-photo-confirmation'

const uuid = z.string().uuid()
const zone = z
  .string()
  .min(1)
  .refine(
    (value) =>
      value === value.trim() &&
      Array.from(value).every((character) => {
        const code = character.charCodeAt(0)
        return code > 31 && code !== 127
      }),
  )
const protocol = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
const hash = z.string().regex(/^[0-9a-f]{64}$/)
const token = z
  .object({
    onboarding_completed: z.boolean(),
    onboarding_completed_at: z.string().datetime({ offset: true }).nullable(),
    receipt_count: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
  })
  .strict()
const bodySchema = z
  .object({
    locale: z.string().min(1).nullable(),
    timezone: zone,
    sex: z.enum(['masculino', 'feminino']).nullable(),
    birth_date: date.nullable(),
    height_cm: z.number().finite().min(100).max(250).nullable(),
    weight_kg: z.number().finite().min(30).max(300).nullable(),
    body_fat_percent: z.number().finite().min(3).max(60).nullable(),
    training_frequency: z.number().int().min(0).max(7).nullable(),
  })
  .strict()
const origin = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('confirmed_no_plan'),
      signupGeneration: uuid,
      signupEpoch: uuid,
      completedAt: instant,
    })
    .strict(),
  z.object({ kind: z.literal('assigned'), phase: protocol }).strict(),
  z.object({ kind: z.literal('legacy_unassigned') }).strict(),
  z.object({ kind: z.literal('not_completed') }).strict(),
])
const missingFields = ['birth_date', 'height_cm', 'weight_kg', 'body_fat_percent'] as const
const snapshot = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    mode: z.enum(['signup', 'profile']),
    profile_present: z.boolean(),
    epoch: uuid.nullable(),
    signup_generation: uuid.nullable(),
    generation_authority: clinicalGenerationAuthoritySchema.optional(),
    generation_token: token.nullable(),
    first_completion: z.boolean(),
    observed_at: instant,
    date,
    timezone: zone,
    body: bodySchema,
    assessment: z.enum(['complete', 'incomplete']),
    missing: z.array(z.enum(missingFields)).max(4),
    health_state: z.unknown(),
    safety: onboardingClinicalSafetySchema.nullable(),
    phase_origin: origin,
    calculation_config: z
      .array(
        z
          .object({ key: z.string().regex(/^calc\./), value: z.unknown(), updated_at: instant })
          .strict(),
      )
      .max(2048),
    profile_hash: hash,
    context_hash: hash,
  })
  .strict()
type SignupClinicalBody = Pick<
  OnboardingCompletionInput,
  'locale' | 'timezone' | 'sex' | 'birth_date' | 'height_cm' | 'weight_kg' | 'training_frequency'
> & { body_fat_percent?: number | null }
interface ExpectedClinicalState {
  expectedGeneration?: SignupPhotoGenerationToken
  expectedEpoch?: string
}
export type CurrentClinicalRequest = ExpectedClinicalState &
  (
    | { userId: string; mode: 'signup'; body: SignupClinicalBody }
    | { userId: string; mode: 'profile'; body?: never }
  )
export interface CurrentClinicalStateSource {
  capture(input: Readonly<CurrentClinicalRequest>): Promise<unknown>
}
export function currentClinicalError(
  kind: 'invalid_response' | 'unavailable' | 'changed' | 'busy',
) {
  return new MobileApiError(
    kind === 'invalid_response' ? 500 : kind === 'unavailable' ? 503 : 409,
    `mobile_current_clinical_${kind}`,
    'Unable to read current clinical state',
  )
}
const failure = currentClinicalError
function immutable<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) immutable(child)
    Object.freeze(value)
  }
  return value
}
function selectedBody(value: SignupClinicalBody): Required<SignupClinicalBody> {
  const body = bodySchema.parse({
    locale: value.locale,
    timezone: value.timezone,
    sex: value.sex,
    birth_date: value.birth_date,
    height_cm: asStoredBodyValue(value.height_cm),
    weight_kg: asStoredBodyValue(value.weight_kg),
    body_fat_percent:
      value.body_fat_percent == null ? null : asStoredBodyValue(value.body_fat_percent),
    training_frequency: value.training_frequency,
  })
  if (
    (body.locale !== 'pt-BR' && body.locale !== 'en-US') ||
    body.sex === null ||
    body.birth_date === null ||
    body.height_cm === null ||
    body.weight_kg === null ||
    body.training_frequency === null
  )
    throw failure('invalid_response')
  return {
    ...body,
    locale: body.locale,
    sex: body.sex,
    birth_date: body.birth_date,
    height_cm: body.height_cm,
    weight_kg: body.weight_kg,
    training_frequency: body.training_frequency,
  }
}
export function sameCurrentClinicalInstant(left: string | null, right: string | null) {
  if (left === null || right === null) return left === right
  const remainder = (value: string) => {
    const fraction = /T\d\d:\d\d:\d\d(?:\.(\d{1,6}))?(?:Z|[+-]\d\d:\d\d)$/.exec(value)
    if (!fraction) throw failure('invalid_response')
    return `${Date.parse(value)}:${(fraction[1] ?? '').padEnd(6, '0').slice(3)}`
  }
  return remainder(left) === remainder(right)
}
function safetyInput(
  value: z.infer<typeof snapshot>,
  health: ReturnType<typeof parseHealthHoldSnapshot>,
) {
  return {
    date: value.date,
    birthDate: value.body.birth_date,
    heightCm: value.body.height_cm,
    weightKg: value.body.weight_kg,
    bodyFatPercent: value.body.body_fat_percent,
    hold: { active: health.hold_active, items: health.items.map((item) => item.code) },
  }
}
function parse(raw: unknown, expected: CurrentClinicalRequest) {
  try {
    const serialized = JSON.stringify(raw)
    if (!serialized || serialized.length > 262144) throw failure('invalid_response')
    const value = snapshot.parse(JSON.parse(serialized))
    const health = parseHealthHoldSnapshot(value.health_state, expected.userId)
    if (
      value.user_id !== expected.userId ||
      value.mode !== expected.mode ||
      value.timezone !== value.body.timezone ||
      value.profile_present !== (value.generation_token !== null) ||
      value.first_completion !==
        (value.generation_token?.onboarding_completed_at == null &&
          value.generation_authority?.kind !== 'legacy_transition') ||
      new Set(value.missing).size !== value.missing.length ||
      value.missing.some((key) => value.body[key] !== null) ||
      (['birth_date', 'height_cm', 'weight_kg'] as const).some(
        (key) => value.body[key] === null && !value.missing.includes(key),
      ) ||
      (value.assessment === 'complete') !== (value.missing.length === 0) ||
      (value.assessment === 'complete') !== (value.safety !== null) ||
      new Set(value.calculation_config.map((row) => row.key)).size !==
        value.calculation_config.length ||
      (expected.expectedEpoch !== undefined &&
        value.epoch?.toLowerCase() !== expected.expectedEpoch.toLowerCase())
    )
      throw failure('invalid_response')
    if (value.generation_authority) {
      if (value.generation_token?.onboarding_completed !== true) throw failure('invalid_response')
      const authority = readClinicalGenerationAuthority(
        {
          signup_generation: value.signup_generation,
          signup_epoch: value.epoch,
          authority: value.generation_authority,
        },
        {
          userId: value.user_id,
          profileCompletedAt: value.generation_token.onboarding_completed_at,
          observedAt: value.observed_at,
        },
      )
      if (authority.kind === 'legacy_transition' && value.phase_origin.kind === 'confirmed_no_plan')
        throw failure('invalid_response')
    }
    if (expected.expectedGeneration) {
      const wanted = token.parse(expected.expectedGeneration),
        actual = value.generation_token
      if (
        !actual ||
        actual.onboarding_completed !== wanted.onboarding_completed ||
        actual.receipt_count !== wanted.receipt_count ||
        !sameCurrentClinicalInstant(actual.onboarding_completed_at, wanted.onboarding_completed_at)
      )
        throw failure('invalid_response')
    }
    if (expected.mode === 'signup') {
      const wanted = selectedBody(expected.body)
      if (
        (Object.keys(wanted) as (keyof typeof wanted)[]).some(
          (key) => wanted[key] !== value.body[key],
        )
      )
        throw failure('invalid_response')
    }
    const safety = evaluateReevaluationSafety(safetyInput(value, health))
    if (value.assessment === 'complete' && safety.assessment !== 'complete')
      throw failure('invalid_response')
    if (
      value.safety &&
      (value.safety.observed_at !== value.observed_at ||
        value.safety.date !== value.date ||
        value.safety.timezone !== value.timezone ||
        value.safety.no_plan !== safety.noPlan ||
        value.safety.hold_active !== health.hold_active ||
        value.safety.loss_guard !==
          (safety.guards.lowWeight === true || safety.guards.lowBodyFat === true) ||
        value.safety.hide_protein !== safety.hide.protein)
    )
      throw failure('invalid_response')
    const ready = value.generation_token?.onboarding_completed === true && !value.first_completion
    if ((value.phase_origin.kind === 'not_completed') === ready) throw failure('invalid_response')
    if (
      value.phase_origin.kind === 'confirmed_no_plan' &&
      (value.phase_origin.signupGeneration !== value.signup_generation ||
        value.phase_origin.signupEpoch !== value.epoch ||
        !sameCurrentClinicalInstant(
          value.phase_origin.completedAt,
          value.generation_token?.onboarding_completed_at ?? null,
        ) ||
        value.phase_origin.completedAt > value.observed_at)
    )
      throw failure('invalid_response')
    return immutable({ ...value, health_state: health })
  } catch {
    throw failure('invalid_response')
  }
}
export type CurrentClinicalSnapshot = ReturnType<typeof parse>

/** Decode an already captured backend observation. No recapture, clock or
 * implicit admission; used when the same SQL transaction captured other facts. */
export function readCurrentClinicalState(raw: unknown, userId: string): CurrentClinicalSnapshot {
  return parse(raw, { userId: uuid.parse(userId), mode: 'profile' })
}
/** Snapshot all producer inputs before the await, then detach all JSON aliases. */
export async function captureCurrentClinicalState(
  source: CurrentClinicalStateSource,
  input: CurrentClinicalRequest,
) {
  if (input.mode !== 'signup' && input.mode !== 'profile') throw failure('invalid_response')
  const expected = {
    userId: uuid.parse(input.userId),
    ...(input.expectedEpoch === undefined
      ? {}
      : { expectedEpoch: uuid.parse(input.expectedEpoch) }),
    ...(input.expectedGeneration === undefined
      ? {}
      : { expectedGeneration: token.parse(input.expectedGeneration) }),
  }
  const request: CurrentClinicalRequest = immutable(
    input.mode === 'signup'
      ? { ...expected, mode: 'signup', body: selectedBody(input.body) }
      : { ...expected, mode: 'profile' },
  )
  let raw: unknown
  try {
    raw = await source.capture(request)
  } catch (error) {
    // Keep only this port's closed error contract, rebuilding the message so
    // a producer cannot leak provider detail by copying a recognized code.
    if (error instanceof MobileApiError) {
      for (const kind of ['invalid_response', 'unavailable', 'changed', 'busy'] as const) {
        const safe = failure(kind)
        if (error.code === safe.code && error.status === safe.status) throw safe
      }
    }
    throw failure('unavailable')
  }
  return parse(raw, request)
}
/** Display policy only. Official day/episode/provenance latches remain required. */
export function projectCurrentClinicalState(value: CurrentClinicalSnapshot) {
  const safety = evaluateReevaluationSafety(safetyInput(value, value.health_state))
  const absent =
    value.phase_origin.kind === 'confirmed_no_plan' || value.phase_origin.kind === 'not_completed'
  const hide = { ...safety.hide }
  if (absent) for (const key of Object.keys(hide) as (keyof typeof hide)[]) hide[key] = true
  return {
    assessment: value.assessment,
    noPlanNow: safety.noPlan,
    holdActive: safety.holdActive,
    safetyRevision: value.health_state.safety_revision,
    observedAt: value.observed_at,
    recordingAllowed: true as const,
    pauseWeightLossGuidance: safety.pauseWeightLossGuidance,
    professionalAssessmentRecommended: safety.professionalAssessmentRecommended,
    phaseSelectionPending: value.phase_origin.kind === 'confirmed_no_plan',
    hide,
    targetSource:
      absent || safety.noPlan
        ? ('unavailable' as const)
        : value.phase_origin.kind === 'legacy_unassigned' ||
            value.assessment === 'incomplete' ||
            !safety.automaticTargetChangeAllowed
          ? ('official_only' as const)
          : ('assigned_phase' as const),
  }
}
type ChoiceReason = 'health_review' | 'loss_guard' | 'gain_composition' | 'gain_training'
export interface CurrentSignupChoices {
  version: 2
  decision: 'no_plan' | 'assigned' | 'choice'
  objective: 'recomposicao' | null
  options: {
    objective: Protocol
    status: 'available' | 'blocked' | 'not_offered'
    reasons: ChoiceReason[]
  }[]
}
/** Private version2; old HTTP and native assigned/choice DTO remain unchanged. */
export function currentSignupChoices(value: CurrentClinicalSnapshot): CurrentSignupChoices {
  const b = value.body
  if (
    value.mode !== 'signup' ||
    !value.first_completion ||
    value.assessment !== 'complete' ||
    !value.profile_present ||
    b.sex === null ||
    b.height_cm === null ||
    b.weight_kg === null ||
    b.training_frequency === null
  )
    throw failure('invalid_response')
  const { height_cm: height, weight_kg: weight, training_frequency: frequency } = b
  const safety = evaluateReevaluationSafety(safetyInput(value, value.health_state))
  if (safety.noPlan) return { version: 2, decision: 'no_plan', objective: null, options: [] }
  const config: SignupEligibilityConfig = {}
  for (const row of value.calculation_config) {
    if (row.key === 'calc.bf_limits') config.bf_limits = row.value
    if (row.key === 'calc.training_min') config.training_min = row.value
    if (row.key === 'calc.imc_limit_recomp') config.imc_limit_recomp = row.value
  }
  const decided = decideOnboardingEligibility(
    {
      sex: b.sex,
      height_cm: b.height_cm,
      weight_kg: b.weight_kg,
      body_fat_percent: b.body_fat_percent ?? undefined,
      training_frequency: b.training_frequency,
    },
    config,
  )
  const guarded =
    safety.holdActive || safety.guards.lowWeight === true || safety.guards.lowBodyFat === true
  return {
    version: 2,
    decision: guarded ? 'choice' : decided.outcome,
    objective: !guarded && decided.outcome === 'assigned' ? 'recomposicao' : null,
    options: (['recomposicao', 'ganho_massa', 'manutencao'] as const).map(
      (objective): CurrentSignupChoices['options'][number] => {
        if (safety.holdActive && objective !== 'manutencao')
          return { objective, status: 'blocked', reasons: ['health_review'] }
        if (guarded && objective === 'recomposicao')
          return { objective, status: 'blocked', reasons: ['loss_guard'] }
        if (guarded && objective === 'manutencao')
          return { objective, status: 'available', reasons: [] }
        if (guarded && objective === 'ganho_massa') {
          const reasons: ChoiceReason[] = []
          if (
            signupGainCompositionUnmet(
              { heightCm: height, weightKg: weight, bodyFatPercent: b.body_fat_percent },
              decided.limits,
            ).length
          )
            reasons.push('gain_composition')
          if (frequency < decided.limits.trainingMin) reasons.push('gain_training')
          return { objective, status: reasons.length ? 'blocked' : 'available', reasons }
        }
        const option = decided.objectives[objective]
        return {
          objective,
          status: option.status,
          reasons: option.reasons.map((reason) =>
            reason === 'composition' ? 'gain_composition' : 'gain_training',
          ),
        }
      },
    ),
  }
}

/** Revalidates the source binding before use; call before admission/HTTP claim.
 * Reacceptance acknowledges its historical phase, never redecides it. */
export function assertCurrentSignupObjectiveEligible(
  raw: unknown,
  userId: string,
  input: OnboardingCompletionInput,
): void {
  const value = parse(raw, { userId, mode: 'signup', body: input })
  if (!value.profile_present) throw failure('unavailable')
  if (!value.first_completion) return
  const decision = currentSignupChoices(value)
  const allowed =
    input.objective === null
      ? decision.decision === 'no_plan'
      : decision.options.some(
          (option) => option.objective === input.objective && option.status === 'available',
        )
  if (!allowed)
    throw new MobileApiError(
      422,
      'onboarding_objective_not_eligible',
      'The objective is not available for the data sent',
    )
}
