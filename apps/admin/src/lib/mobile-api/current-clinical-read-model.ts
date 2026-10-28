/** One read-only clinical composition. No default route, writer or feature flag.
 * Clinical daily application/closer, native contracts and Flow must be integrated
 * together before activation; a read projection cannot create their authority. */
import { getMealPattern, getSkippedMealsForDate } from '@mpp/agent'
import { type DailyState, dailyTargetByProtocol } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { readClinicalRepresentation } from './clinical-representation'
import {
  clinicalCalculationSnapshotSchema,
  readClinicalCalculationConfigRows,
  readClinicalFormulaBodyFat,
} from './clinical-snapshot-calculation'
import { type TrendsQuery, trendsQuerySchema } from './contracts'
import type { CurrentClinicalAdmission } from './current-clinical-admission'
import {
  type CurrentClinicalSnapshot,
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  currentClinicalError,
  projectCurrentClinicalState,
  readCurrentClinicalState,
  sameCurrentClinicalInstant,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'
import { protocolReadModel } from './protocol-service'
import { loadPlan, loadProfile, loadProgress, loadToday, loadTrends } from './read-model'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseClinicalDailyRepository } from './supabase-clinical-daily'

type State = CurrentClinicalSnapshot
type Policy = ReturnType<typeof projectCurrentClinicalState>
export type ClinicalReadEndpoint = 'today' | 'progress' | 'plan' | 'trends' | 'protocol'
/** Private server admission, never a response DTO or durable write authority.
 * Writers must recapture/CAS after their owner lock; this snapshot is not a lock. */
export interface ClinicalReadAdmission {
  readonly owner: string
  readonly compatible: boolean
  readonly state: CurrentClinicalSnapshot
}
export interface CurrentClinicalReaderSources {
  today(client: ServiceClient, owner: string, state: State): Promise<DailyState>
  progress: typeof loadProgress
  plan: typeof loadPlan
  trends: typeof loadTrends
  profile: typeof loadProfile
}
export { readClinicalRepresentation } from './clinical-representation'

function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function publicPolicy(state: State) {
  const p = projectCurrentClinicalState(state)
  return freeze({
    version: 1 as const,
    observed_at: p.observedAt,
    assessment: p.assessment,
    recording_allowed: p.recordingAllowed,
    pause_weight_loss_guidance: p.pauseWeightLossGuidance,
    professional_assessment_recommended: p.professionalAssessmentRecommended,
    phase_selection_pending: p.phaseSelectionPending,
    target_source: p.targetSource,
    hide: { ...p.hide },
  })
}
type Presented<T> = T extends null
  ? null
  : T & { clinical_policy?: ReturnType<typeof publicPolicy> }
function stableBinding(s: State) {
  // Context hash contains the clock. Compare the actual closed observations,
  // retaining raw config values+dates, current health, owner and provenance.
  return hashMobileRequest({
    user_id: s.user_id,
    mode: s.mode,
    profile_present: s.profile_present,
    profile_hash: s.profile_hash,
    epoch: s.epoch,
    signup_generation: s.signup_generation,
    generation_authority: s.generation_authority,
    generation_token: s.generation_token,
    first_completion: s.first_completion,
    date: s.date,
    timezone: s.timezone,
    body: s.body,
    assessment: s.assessment,
    missing: s.missing,
    health_state: s.health_state,
    phase_origin: s.phase_origin,
    calculation_config: s.calculation_config,
  })
}
function requireRepresentation(policy: Policy, compatible: boolean) {
  if (
    !compatible &&
    (policy.pauseWeightLossGuidance ||
      policy.phaseSelectionPending ||
      Object.values(policy.hide).some(Boolean))
  )
    throw new MobileApiError(
      409,
      'clinical_client_update_required',
      'Update the app to view this information',
    )
}

// The signup boundary uses the same public projection and closed read binding.
// These exports do not install a provider, route, writer or default capability.
export {
  publicPolicy as projectCurrentClinicalPublicPolicy,
  requireRepresentation as requireCurrentClinicalRepresentation,
  stableBinding as currentClinicalReadBinding,
}

function checkProtocol(state: State, actual: unknown) {
  const origin = state.phase_origin
  if (origin.kind === 'not_completed') return
  if (actual !== (origin.kind === 'assigned' ? origin.phase : null))
    throw currentClinicalError('changed')
}
function requireProtocolLocale(state: State) {
  const locale = state.body.locale
  if (locale !== 'pt-BR' && locale !== 'en-US')
    throw new MobileApiError(
      409,
      'protocol_locale_unsupported',
      'The objective is unavailable for this locale',
    )
  return locale
}
function projectToday(data: DailyState, state: State) {
  if (data.local_date !== state.date) throw currentClinicalError('changed')
  checkProtocol(state, data.current_protocol)
  const p = projectCurrentClinicalState(state)
  // Per-field source only. Equality with a formula or aggregate 'mixed' is not proof.
  const calories =
    !p.hide.calories && data.targets.calories_source === 'daily_snapshot'
      ? data.targets.calories_kcal
      : null
  const protein =
    !p.hide.protein && data.targets.protein_source === 'daily_snapshot'
      ? data.targets.protein_g
      : null
  const cs = calories === null ? ('unavailable' as const) : ('daily_snapshot' as const)
  const ps = protein === null ? ('unavailable' as const) : ('daily_snapshot' as const)
  const source = cs === ps ? cs : ('mixed' as const)
  const balance = !p.hide.balance && calories !== null
  return {
    ...data,
    protocol: p.hide.objective ? null : data.protocol,
    current_protocol: p.hide.objective ? null : data.current_protocol,
    targets: {
      calories_kcal: calories,
      protein_g: protein,
      calories_source: cs,
      protein_source: ps,
      source,
    },
    remaining_food_kcal: calories === null ? null : data.remaining_food_kcal,
    food_excess_kcal: calories === null ? null : data.food_excess_kcal,
    daily_balance_kcal: balance ? data.daily_balance_kcal : null,
    daily_balance_reference_kcal: balance ? data.daily_balance_reference_kcal : null,
    daily_balance_includes_exercise: balance ? data.daily_balance_includes_exercise : null,
    protein_status: {
      ...data.protein_status,
      target_g: protein,
      remaining_g: protein === null ? null : data.protein_status.remaining_g,
      percentage: protein === null ? null : data.protein_status.percentage,
      status: protein === null ? ('target_unavailable' as const) : data.protein_status.status,
    },
    block_7700: p.hide.block
      ? {
          ...data.block_7700,
          enabled: false,
          availability: 'unavailable' as const,
          target_kcal: null,
          current_kcal: null,
          percentage: null,
          completed_blocks: null,
          total_credited_kcal: null,
          source: 'unavailable' as const,
        }
      : data.block_7700,
    sources: {
      ...data.sources,
      targets: source,
      block_7700: p.hide.block ? ('unavailable' as const) : data.sources.block_7700,
    },
  }
}
/** Read-only formula evidence, bound to the same current observation. A mutable
 * BF report remains available to safety/display, but cannot select the balance
 * rule. Only the existing signup/recurring photo proofs can feed that formula. */
function dailyFormulaEvidence(raw: unknown, owner: string, state: State) {
  let context: ReturnType<typeof clinicalCalculationSnapshotSchema.parse>
  let selected: ReturnType<typeof readClinicalFormulaBodyFat>
  try {
    context = clinicalCalculationSnapshotSchema.parse(raw)
    selected = readClinicalFormulaBodyFat(context, owner)
  } catch {
    throw currentClinicalError('invalid_response')
  }
  const f = context.facts
  const rows = new Map(f.calculation_config.map((row) => [row.key, row]))
  if (
    context.review_kind !== 'APPLICATION' ||
    context.cycle_id !== null ||
    f.anchor.signup_generation !== state.signup_generation ||
    f.anchor.signup_epoch !== state.epoch ||
    f.calculation_date !== state.date ||
    f.owner.timezone !== state.timezone ||
    f.owner.locale !== state.body.locale ||
    context.observed_at < state.observed_at ||
    context.observed_at >= context.valid_until ||
    f.profile.onboarding_completed !== state.generation_token?.onboarding_completed ||
    !sameCurrentClinicalInstant(
      f.profile.onboarding_completed_at,
      state.generation_token?.onboarding_completed_at ?? null,
    ) ||
    (state.generation_authority !== undefined &&
      hashMobileRequest(f.anchor.authority) !== hashMobileRequest(state.generation_authority)) ||
    rows.size !== f.calculation_config.length ||
    rows.size !== state.calculation_config.length ||
    state.calculation_config.some((row) => {
      const actual = rows.get(row.key)
      return (
        !actual ||
        actual.updated_at !== row.updated_at ||
        hashMobileRequest(actual.value) !== hashMobileRequest(row.value)
      )
    }) ||
    (
      [
        'sex',
        'birth_date',
        'height_cm',
        'weight_kg',
        'body_fat_percent',
        'training_frequency',
      ] as const
    ).some((key) => f.profile[key] !== state.body[key])
  )
    throw currentClinicalError('changed')
  return {
    profile: f.profile,
    formulaBodyFatPercent: selected.formulaBodyFatPercent,
  }
}
const defaultSources: CurrentClinicalReaderSources = {
  async today(client, owner, state) {
    const config = readClinicalCalculationConfigRows(state.calculation_config).config
    const policy = projectCurrentClinicalState(state)
    const evidence =
      policy.targetSource === 'assigned_phase'
        ? dailyFormulaEvidence(
            await createSupabaseClinicalDailyRepository(client).capture(owner),
            owner,
            state,
          )
        : null
    return loadToday(client, owner, state.timezone, new Date(state.observed_at), {
      requireFreshProgress: true,
      loadConfig: async () => config,
      loadMealPattern: getMealPattern,
      loadSkippedMeals: getSkippedMealsForDate,
      resolveTargetRead: (profile, capturedConfig, date) => {
        if (date !== state.date) throw currentClinicalError('changed')
        checkProtocol(state, profile?.current_protocol ?? null)
        if (
          evidence &&
          (!profile ||
            (
              [
                'sex',
                'birth_date',
                'height_cm',
                'weight_kg',
                'body_fat_percent',
                'activity_level',
                'training_frequency',
                'hunger_level',
                'current_protocol',
                'deficit_level',
              ] as const
            ).some((key) => profile[key] !== evidence.profile[key]))
        )
          throw currentClinicalError('changed')
        return {
          // The daily writer owns application/provenance. Read-only composition
          // never invents its missing snapshot through legacy NULL/TDEE fallback.
          calculatedTargets: { calories_target: null, protein_target: null },
          targetByProtocol:
            evidence && profile
              ? dailyTargetByProtocol(
                  { ...profile, body_fat_percent: evidence.formulaBodyFatPercent },
                  capturedConfig,
                  state.date,
                )
              : null,
        }
      },
    })
  },
  progress: loadProgress,
  plan: loadPlan,
  trends: loadTrends,
  profile: loadProfile,
}

/** Constructor is inert. Each method captures immutable identity and negotiation
 * before I/O. No numeric reader or implicit closer runs before the client gate. */
export function createCurrentClinicalReadModel(
  client: ServiceClient,
  source: CurrentClinicalStateSource,
  readers: CurrentClinicalReaderSources = defaultSources,
  options: { admission?: CurrentClinicalAdmission } = {},
) {
  const capture = Object.freeze({ capture: source.capture.bind(source) })
  const reads = Object.freeze({ ...readers })
  const establish = options.admission?.establish.bind(options.admission)
  async function preflight(
    auth: MobileAuthContext,
    url: string,
    endpoint: ClinicalReadEndpoint,
  ): Promise<ClinicalReadAdmission> {
    const owner = authenticatedReevaluationOwner(auth)
    const { compatible, search } = readClinicalRepresentation(url)
    if (endpoint === 'trends') trendsQuerySchema.parse(Object.fromEntries(search.entries()))
    const before = await captureCurrentClinicalState(capture, { userId: owner, mode: 'profile' })
    requireRepresentation(projectCurrentClinicalState(before), compatible)
    if (endpoint === 'protocol') requireProtocolLocale(before)
    const state = establish
      ? readCurrentClinicalState(await establish(before, capture), owner)
      : before
    requireRepresentation(projectCurrentClinicalState(state), compatible)
    if (endpoint === 'protocol') requireProtocolLocale(state)
    return freeze({ owner, compatible, state: structuredClone(state) })
  }
  async function run<T, U extends object | null>(
    auth: MobileAuthContext,
    url: string,
    read: (owner: string, state: State) => Promise<T>,
    project: (data: T, state: State) => U,
    decorate?: (owner: string, data: Presented<U>) => Promise<Presented<U>>,
  ): Promise<Presented<U>> {
    const owner = authenticatedReevaluationOwner(auth)
    const { compatible } = readClinicalRepresentation(url)
    const before = await captureCurrentClinicalState(capture, { userId: owner, mode: 'profile' })
    requireRepresentation(projectCurrentClinicalState(before), compatible)
    // Detach producer aliases BEFORE a second await; never cache this scope.
    const data = freeze(structuredClone(await read(owner, before)))
    const after = await captureCurrentClinicalState(capture, { userId: owner, mode: 'profile' })
    if (after.observed_at < before.observed_at || stableBinding(before) !== stableBinding(after))
      throw currentClinicalError('changed')
    const result = project(data, after)
    // The conditional type retains null only for readers which can lack a row.
    // Both branches enforce that shape at runtime.
    const presented = (
      result === null
        ? null
        : freeze({ ...result, ...(compatible ? { clinical_policy: publicPolicy(after) } : {}) })
    ) as Presented<U>
    if (!decorate) return presented
    const decorated = freeze(structuredClone(await decorate(owner, presented)))
    // An enrichment is part of this response, not a separate publication
    // window. In particular, a weekly RPC may overlap a new clinical HOLD.
    const final = await captureCurrentClinicalState(capture, { userId: owner, mode: 'profile' })
    if (final.observed_at < after.observed_at || stableBinding(after) !== stableBinding(final))
      throw currentClinicalError('changed')
    return decorated
  }
  return Object.freeze({
    preflight,
    today(
      auth: MobileAuthContext,
      url: string,
      decorate?: (
        owner: string,
        data: Presented<ReturnType<typeof projectToday>>,
      ) => Promise<Presented<ReturnType<typeof projectToday>>>,
    ) {
      return run(
        auth,
        url,
        (owner, state) => reads.today(client, owner, state),
        projectToday,
        decorate,
      )
    },
    progress(auth: MobileAuthContext, url: string) {
      return run(
        auth,
        url,
        (owner) => reads.progress(client, owner),
        (data, state) => {
          if (data === null) return null
          checkProtocol(state, data.current_protocol)
          const p = projectCurrentClinicalState(state)
          return {
            ...data,
            current_protocol: p.hide.objective ? null : data.current_protocol,
            block_7700_enabled: !p.hide.block && data.block_7700_enabled,
            blocks_completed: p.hide.block ? null : data.blocks_completed,
            deficit_block: p.hide.block ? null : data.deficit_block,
          }
        },
      )
    },
    plan(auth: MobileAuthContext, url: string) {
      return run(
        auth,
        url,
        (owner) => reads.plan(client, owner),
        (data, state) => {
          const p = projectCurrentClinicalState(state)
          // Arbitrary prescription JSON/notes cannot be selectively certified by
          // masking guessed keys. Keep stored rows, withhold incompatible guidance.
          return {
            ...data,
            training: p.hide.objective ? null : data.training,
            nutrition:
              p.pauseWeightLossGuidance || p.hide.objective || p.hide.calories || p.hide.protein
                ? []
                : data.nutrition,
          }
        },
      )
    },
    trends(auth: MobileAuthContext, url: string, rawQuery: TrendsQuery) {
      const query = freeze(trendsQuerySchema.parse(rawQuery))
      return run(
        auth,
        url,
        (owner, state) => reads.trends(client, owner, query, state.timezone),
        (data, state) => {
          const p = projectCurrentClinicalState(state)
          return {
            ...data,
            daily: data.daily.map((row) => ({
              ...row,
              calories_target: p.hide.calories ? null : row.calories_target,
              protein_target: p.hide.protein ? null : row.protein_target,
              deficit_accumulated: p.hide.block ? null : row.deficit_accumulated,
            })),
          }
        },
      )
    },
    protocol(auth: MobileAuthContext, url: string) {
      const name = auth.patient.name
      return run(
        auth,
        url,
        async (owner, state) => {
          requireProtocolLocale(state)
          const [profile, today] = await Promise.all([
            reads.profile(client, owner),
            reads.today(client, owner, state),
          ])
          return { profile, today }
        },
        (data, state) => {
          checkProtocol(state, data.profile?.current_protocol ?? null)
          const locale = requireProtocolLocale(state)
          const today = projectToday(data.today, state),
            p = projectCurrentClinicalState(state)
          const value = protocolReadModel({
            profile: data.profile,
            todayTargets: today.targets,
            name,
            locale,
          })
          return {
            ...value,
            current_protocol: p.hide.objective ? null : value.current_protocol,
            welcome: p.hide.objective || p.pauseWeightLossGuidance ? null : value.welcome,
          }
        },
      )
    },
  })
}
