import { clearCalcConfigCache, loadCalcConfig } from '@mpp/agent'
import { buildDailyState } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalDailyEffect } from './clinical-daily-effect'
import { clinicalDailyRepositoryError } from './clinical-daily-service'
import {
  type ClinicalHttpDependencies,
  createCurrentClinicalGetRoute,
} from './current-clinical-http'
import {
  type ClinicalReadEndpoint,
  type CurrentClinicalReaderSources,
  createCurrentClinicalReadModel,
  readClinicalRepresentation,
} from './current-clinical-read-model'
import { readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import * as todayHandlers from './today-handler'

const owner = 'b3b01000-0000-4000-8000-000000002940'
const other = 'b3b01000-0000-4000-8000-000000002941'
const epoch = 'b3b01000-0000-4000-8000-000000002942'
const generation = 'b3b01000-0000-4000-8000-000000002943'
const at = '2026-10-26T10:00:00.000001Z'
const completed = '2026-10-25T10:00:00.000001Z'
const legacyURL = 'https://bodyflow.test/api/mobile/v1/today'
const url = `${legacyURL}?clinical_policy=current_clinical_v1`
const auth: MobileAuthContext = {
  userId: owner,
  authUserId: other,
  accessToken: 'redacted-test',
  identity: { id: other, email: null, emailConfirmedAt: at },
  patient: {
    id: owner,
    authUserId: other,
    email: null,
    name: 'Synthetic QA',
    locale: 'pt-BR',
    timezone: 'UTC',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
function snapshot() {
  return {
    version: 1,
    user_id: owner,
    mode: 'profile',
    profile_present: true,
    epoch,
    signup_generation: generation,
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: completed as string | null,
      receipt_count: 1,
    },
    first_completion: false,
    observed_at: at,
    date: '2026-10-26',
    timezone: 'America/Sao_Paulo',
    body: {
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      sex: 'masculino',
      birth_date: '1990-01-01',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: 24,
      training_frequency: 4,
    },
    assessment: 'complete',
    missing: [],
    health_state: {
      version: 1,
      user_id: owner,
      safety_revision: '0',
      hold_active: false,
      declared_no_plan: false,
      hide_protein: false,
      last_declared_at: null as string | null,
      items: [] as { code: string; declared_at: string }[],
    },
    safety: {
      version: 1,
      no_plan: false,
      hold_active: false,
      loss_guard: false,
      hide_protein: false,
      recording_allowed: true,
      date: '2026-10-26',
      timezone: 'America/Sao_Paulo',
      observed_at: at,
    },
    phase_origin: { kind: 'assigned', phase: 'recomposicao' } as Record<string, unknown>,
    calculation_config: [{ key: 'calc.training_min', value: 4, updated_at: at }],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
function hold(s = snapshot(), code = 'reduced_intake') {
  s.health_state = {
    ...s.health_state,
    hold_active: true,
    safety_revision: '1',
    declared_no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'professional_diet',
    last_declared_at: at,
    items: [{ code, declared_at: at }],
  }
  s.safety = {
    ...s.safety,
    hold_active: true,
    no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'professional_diet' || code === 'pregnant_or_breastfeeding',
  }
  return s
}
function today() {
  return buildDailyState({
    localDate: '2026-10-26',
    generatedAt: at,
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: 1800, protein_target: 120 },
    snapshot: {
      caloriesConsumed: 650,
      caloriesTarget: 1900,
      proteinG: 25,
      proteinTarget: 130,
      carbsG: 90,
      fatG: 15,
      exerciseCalories: 100,
      waterConsumedMl: 500,
      protocol: 'recomposicao',
      dayClosed: false,
      dayStatus: null,
      updatedAt: at,
    },
    progress: { blocksCompleted: 2, deficitBlock: 300, updatedAt: at },
    meals: [
      {
        id: generation,
        meal_type: 'cafe',
        food_name: 'leite com whey',
        quantity_g: 230,
        kcal: 250,
        protein_g: 30,
        carbs_g: 12,
        fat_g: 7,
        consumed_at: at,
      },
    ],
    workouts: [],
    pendingRegistrations: [],
    routineItems: [],
    hydrationTarget: null,
    mealGap: {
      expected: ['cafe'],
      registered: ['cafe'],
      skipped: [],
      open: [],
      reliable: true,
      activeDays: 8,
    },
  })
}
function progress() {
  return {
    xp_total: 10,
    level: 1,
    current_streak: 2,
    longest_streak: 3,
    blocks_completed: 2,
    deficit_block: 300,
    current_weight: 80,
    current_bf_percent: 24,
    badges_earned: [],
    last_active_date: '2026-10-26',
    next_reevaluation: null,
    updated_at: at,
    current_bf_origin: null,
    current_protocol: 'recomposicao' as const,
    block_7700_enabled: true,
  }
}
function setup(s = snapshot()) {
  const current = vi.fn(async () => structuredClone(s)),
    baseToday = today()
  const reads = {
    today: vi.fn<CurrentClinicalReaderSources['today']>(async () => baseToday),
    progress: vi.fn<CurrentClinicalReaderSources['progress']>(async () => progress()),
    plan: vi.fn<CurrentClinicalReaderSources['plan']>(async () => ({
      training: null,
      nutrition: [
        {
          id: generation,
          type: 'nutrition',
          payload: { instruction: 'meta 1900 kcal' },
          notes: 'proteina 130 g',
          generated_at: at,
          valid_until: null,
          version: 1,
        },
      ],
    })),
    trends: vi.fn<CurrentClinicalReaderSources['trends']>(async () => ({
      days: 7,
      daily: [
        {
          date: '2026-10-25',
          calories_consumed: 650,
          calories_target: 1900,
          exercise_calories: 100,
          protein_g: 25,
          protein_target: 130,
          water_consumed_ml: 500,
          deficit_accumulated: 300,
          xp_earned: 10,
          day_closed: true,
        },
      ],
      weights: [{ date: '2026-10-25', weight_kg: 80 }],
    })),
    profile: vi.fn<CurrentClinicalReaderSources['profile']>(async () => ({
      current_protocol: 'recomposicao',
    })),
  }
  const client = {} as ServiceClient
  const model = createCurrentClinicalReadModel(client, { capture: current }, reads)
  return { s, current, reads, client, model, baseToday }
}
/** The default BFF/agent reader runs; only database transport is synthetic.
 * Every write/unknown table and any global_config lookup is refused. */
function actualTodayClient(
  caloriesTarget: number | null = 3261,
  progressSequence?: Array<{ deficit_block: number; blocks_completed: number; updated_at: string }>,
  protocol: 'ganho_massa' | 'recomposicao' | 'manutencao' = 'ganho_massa',
  state = snapshot(),
) {
  let progressReads = 0
  const calls: string[][] = []
  const profile = {
    ...state.body,
    activity_level: 'moderado',
    hunger_level: 'moderada',
    current_protocol: protocol,
    deficit_level: 500,
    goal_type: null,
    goal_value: null,
    water_intake: null,
    wake_time: '07:00',
    bedtime: '23:00',
  }
  const dailyContext = {
    version: 1,
    user_id: owner,
    review_kind: 'APPLICATION',
    cycle_id: null,
    observed_at: at,
    valid_until: '2026-10-27T03:00:00.000000Z',
    context_hash: 'c'.repeat(64),
    facts: {
      owner: { id: owner, status: 'active', locale: state.body.locale, timezone: state.timezone },
      anchor: {
        signup_generation: generation,
        signup_epoch: epoch,
        authority: {
          kind: 'signup_receipt',
          generation,
          epoch,
          completed_at: completed,
          timezone_at_signup: state.timezone,
        } as Record<string, unknown>,
      },
      calculation_date: state.date,
      profile: {
        ...profile,
        user_id: owner,
        body_fat_measured_at: null as string | null,
        onboarding_completed: true,
        onboarding_completed_at: completed as string | null,
      },
      day: null,
      calculation_config: structuredClone(state.calculation_config),
      protocol_authority: {
        body_fat_origin: null as Record<string, unknown> | null,
        signup_body_fat_origin: {
          user_id: owner,
          signup_generation: generation,
          signup_epoch: epoch,
          receipt_version: 1,
          onboarding_completed_at: completed,
          method: 'arithmetic_mean_v1',
          confirmed_body_fat_percent: state.body.body_fat_percent,
          fingerprint: 'd'.repeat(64),
          decided_at: at,
        } as Record<string, unknown> | null,
        body_fat_candidate: null,
      },
      safety: { user_id: owner, hold_active: false, items: [] },
    },
  }
  const stored = {
    id: generation,
    calories_consumed: 650,
    calories_target: caloriesTarget,
    protein_g: 25,
    protein_target: caloriesTarget === null ? null : 130,
    carbs_g: 90,
    fat_g: 15,
    exercise_calories: 100,
    water_consumed_ml: 500,
    current_protocol: protocol,
    day_closed: false,
    day_status: null,
    updated_at: at,
    meal_logs: [],
    workout_logs: [],
  }
  class Query {
    constructor(readonly table: string) {}
    select() {
      return this
    }
    eq(key: string, value: string) {
      calls.push([this.table, key, value])
      if (key === 'user_id' && value !== owner) throw new Error('foreign owner')
      return this
    }
    gt() {
      return this
    }
    gte() {
      return this
    }
    lte() {
      return this
    }
    lt() {
      return this
    }
    filter() {
      return this
    }
    order() {
      return this
    }
    limit() {
      return this
    }
    async maybeSingle() {
      if (this.table === 'user_profiles')
        return {
          error: null,
          data: structuredClone(profile),
        }
      if (this.table === 'daily_snapshots') return { data: structuredClone(stored), error: null }
      if (this.table === 'user_progress')
        return {
          data: progressSequence?.[Math.min(progressReads++, progressSequence.length - 1)] ?? {
            deficit_block: 300,
            blocks_completed: 2,
            updated_at: at,
          },
          error: null,
        }
      return { data: null, error: null }
    }
    // biome-ignore lint/suspicious/noThenProperty: this test implements the Supabase thenable query contract.
    then<TResult1 = { data: never[]; error: null }, TResult2 = never>(
      fulfilled?:
        | ((value: { data: never[]; error: null }) => TResult1 | PromiseLike<TResult1>)
        | null,
      rejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ) {
      return Promise.resolve({ data: [], error: null }).then(fulfilled, rejected)
    }
  }
  const client = {
    from(table: string) {
      if (
        ![
          'user_profiles',
          'daily_snapshots',
          'user_progress',
          'pending_registrations',
          'notification_preferences',
          'product_events',
        ].includes(table)
      )
        throw new Error(`Unexpected query: ${table}`)
      return new Query(table)
    },
    async rpc(name: string, parameters: Record<string, unknown>) {
      if (parameters.p_user_id !== owner) throw new Error('Unexpected RPC owner')
      if (name === 'get_mobile_clinical_daily_context')
        return { data: structuredClone(dailyContext), error: null }
      if (name !== 'list_mobile_routine_items') throw new Error('Unexpected RPC')
      return { data: { local_date: '2026-10-26', items: [] }, error: null }
    },
  } as unknown as ServiceClient
  return { client, calls, stored, profile, dailyContext }
}
describe('current clinical readers share one server policy', () => {
  it('keeps the actual daily balance unchanged when only an unconfirmed reported body-fat value changes', async () => {
    const balances: Array<number | null> = []
    for (const bodyFat of [24, 50]) {
      const s = snapshot()
      s.body.birth_date = '1986-01-01'
      s.body.body_fat_percent = bodyFat
      const db = actualTodayClient(1576, undefined, 'recomposicao', s)
      db.dailyContext.facts.protocol_authority.signup_body_fat_origin = null
      db.stored.calories_consumed = 1700
      db.stored.exercise_calories = 0
      const before = structuredClone(db.stored)
      const result = await createCurrentClinicalReadModel(db.client, {
        capture: async () => structuredClone(s),
      }).today(auth, url)
      balances.push(result.daily_balance_kcal)
      expect(result.targets.calories_kcal).toBe(1576)
      expect(result.daily_balance_reference_kcal).toBe(2076)
      expect(db.stored).toEqual(before)
    }
    expect(balances).toEqual([-376, -376])
  })
  it.each([
    'signup',
    'recurring',
    'legacy_recurring',
  ] as const)('retains a genuinely confirmed %s photo origin in the actual numeric reader', async (origin) => {
    const s = snapshot()
    s.body.birth_date = '1986-01-01'
    s.body.body_fat_percent = 50
    const db = actualTodayClient(1576, undefined, 'recomposicao', s)
    db.stored.calories_consumed = 1700
    db.stored.exercise_calories = 0
    if (origin !== 'signup') {
      db.dailyContext.facts.protocol_authority.signup_body_fat_origin = null
      db.dailyContext.facts.profile.body_fat_measured_at = at
      db.dailyContext.facts.protocol_authority.body_fat_origin = {
        user_id: owner,
        signup_generation: generation,
        signup_epoch: epoch,
        mean_percent: 50,
        confirmed_at: at,
        source_hash: 'e'.repeat(64),
      }
    }
    if (origin === 'legacy_recurring') {
      s.generation_token.onboarding_completed_at = null
      s.generation_token.receipt_count = 0
      db.dailyContext.facts.profile.onboarding_completed_at = null
      db.dailyContext.facts.anchor.authority = {
        kind: 'legacy_transition',
        user_id: owner,
        generation,
        epoch,
        admitted_at: completed,
        admitted_date: '2026-10-25',
        timezone_at_admission: s.timezone,
        profile_completed_marker: null,
      }
      Object.assign(s, {
        generation_authority: structuredClone(db.dailyContext.facts.anchor.authority),
      })
    }
    const before = structuredClone(db.stored)
    const result = await createCurrentClinicalReadModel(db.client, {
      capture: async () => structuredClone(s),
    }).today(auth, url)
    expect(result.daily_balance_kcal).toBe(124)
    expect(result.daily_balance_reference_kcal).toBe(1576)
    expect(db.stored).toEqual(before)
  })
  it.each([
    'owner',
    'generation',
    'epoch',
    'date',
    'profile',
    'config',
    'completion',
    'locale',
    'timezone',
    'older',
    'expired',
  ] as const)('refuses a daily formula capture that differs from the current read at %s', async (changed) => {
    const s = snapshot()
    const db = actualTodayClient(2000, undefined, 'recomposicao', s)
    const f = db.dailyContext.facts
    if (changed === 'owner') f.owner.id = other
    if (changed === 'generation') f.anchor.signup_generation = other
    if (changed === 'epoch') f.anchor.signup_epoch = other
    if (changed === 'date') f.calculation_date = '2026-10-25'
    if (changed === 'profile') db.profile.weight_kg = 81
    if (changed === 'config') {
      const row = f.calculation_config[0]
      if (!row) throw new Error('Missing config fixture')
      row.value = 3
    }
    if (changed === 'completion') f.profile.onboarding_completed_at = at
    if (changed === 'locale') f.owner.locale = 'en-US'
    if (changed === 'timezone') f.owner.timezone = 'UTC'
    if (changed === 'older') db.dailyContext.observed_at = '2026-10-26T10:00:00.000000Z'
    if (changed === 'expired') db.dailyContext.valid_until = at
    await expect(
      createCurrentClinicalReadModel(db.client, {
        capture: async () => structuredClone(s),
      }).today(auth, url),
    ).rejects.toBeInstanceOf(MobileApiError)
    expect(db.stored.calories_target).toBe(2000)
  })
  it.each([
    'owner',
    'generation',
    'epoch',
    'value',
    'future',
  ] as const)('refuses an invalid photo origin at %s instead of using a reported percentage', async (invalid) => {
    const s = snapshot()
    const db = actualTodayClient(2000, undefined, 'recomposicao', s)
    const proof = db.dailyContext.facts.protocol_authority.signup_body_fat_origin
    if (!proof) throw new Error('Missing proof fixture')
    if (invalid === 'owner') proof.user_id = other
    if (invalid === 'generation') proof.signup_generation = other
    if (invalid === 'epoch') proof.signup_epoch = other
    if (invalid === 'value') proof.confirmed_body_fat_percent = 25
    if (invalid === 'future') proof.decided_at = '2026-10-26T10:00:00.000002Z'
    await expect(
      createCurrentClinicalReadModel(db.client, {
        capture: async () => structuredClone(s),
      }).today(auth, url),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_invalid_response' })
    expect(db.stored.calories_target).toBe(2000)
  })
  it('accepts the same completion instant and configuration regardless of offset or row ordering', async () => {
    const s = snapshot()
    s.generation_token.onboarding_completed_at = '2026-10-25T10:00:00.000001+00:00'
    s.calculation_config.push({ key: 'calc.recomp_protein_g_per_kg', value: 1.5, updated_at: at })
    const db = actualTodayClient(2000, undefined, 'recomposicao', s)
    db.dailyContext.facts.calculation_config.reverse()
    const result = await createCurrentClinicalReadModel(db.client, {
      capture: async () => structuredClone(s),
    }).today(auth, url)
    expect(result.targets.calories_kcal).toBe(2000)
  })
  it.each([
    'professional_diet',
    'pregnant_or_breastfeeding',
  ])('refuses Today when %s is declared during the actual weekly enrichment RPC', async (risk) => {
    const s = setup()
    s.s.body.sex = 'feminino'
    let enterWeekly!: () => void
    let releaseWeekly!: () => void
    const entered = new Promise<void>((resolve) => {
      enterWeekly = resolve
    })
    const released = new Promise<void>((resolve) => {
      releaseWeekly = resolve
    })
    const client = {
      async rpc(name: string, parameters: Record<string, unknown>) {
        if (name !== 'get_mobile_strength_week_context' || parameters.p_user_id !== owner)
          throw new Error('Unexpected weekly RPC')
        enterWeekly()
        await released
        return { data: { status: 'unavailable', reason: 'missing_scope' }, error: null }
      },
    } as unknown as ServiceClient
    const handler = createCurrentClinicalGetRoute(
      'today',
      {
        authenticate: async () => auth,
        authorizeEntitlement: async () => {},
        createServiceClient: () => client,
        createRequestId: () => 'qa-enrichment-policy-race',
      },
      {
        createReadModel: () => s.model,
        applyDaily: async () => {},
        closeDays: async () => {},
      },
      () => true,
    )
    const pending = handler(new Request(url))
    await entered
    hold(s.s, risk)
    releaseWeekly()
    const response = await pending
    expect(response.status).toBe(409)
    expect(await response.json()).toMatchObject({
      error: { code: 'mobile_current_clinical_changed' },
    })
  })
  it('carries the fresh-progress latch through the real numeric reader with unchanged clinical captures', async () => {
    const s = snapshot()
    s.phase_origin = { kind: 'assigned', phase: 'recomposicao' }
    const old = { deficit_block: 300, blocks_completed: 2, updated_at: at }
    const fresh = {
      deficit_block: 600,
      blocks_completed: 3,
      updated_at: '2026-10-26T10:00:00.000002Z',
    }
    const db = actualTodayClient(2000, [old, fresh, fresh, fresh], 'recomposicao', s)
    const capture = vi.fn(async () => structuredClone(s))
    const result = await createCurrentClinicalReadModel(db.client, { capture }).today(auth, url)
    expect(result.block_7700).toMatchObject({ current_kcal: 600, completed_blocks: 3 })
    expect(db.calls.filter(([table]) => table === 'user_progress')).toHaveLength(4)
    expect(capture).toHaveBeenCalledTimes(2)
  })
  it('uses the real default reader with captured config, civil clock and day latch, ignoring stale cache', async () => {
    clearCalcConfigCache()
    await loadCalcConfig({
      from: () => ({
        select: () => ({
          like: async () => ({
            data: [{ key: 'calc.ganho_massa_surplus_multiplier', value: 1.05 }],
            error: null,
          }),
        }),
      }),
    })
    try {
      const s = snapshot()
      s.phase_origin = { kind: 'assigned', phase: 'ganho_massa' }
      s.calculation_config = [
        { key: 'calc.ganho_massa_surplus_multiplier', value: 1.25, updated_at: at },
      ]
      const db = actualTodayClient(3261, undefined, 'ganho_massa', s),
        r = await createCurrentClinicalReadModel(db.client, {
          capture: async () => structuredClone(s),
        }).today(auth, url)
      expect(r.targets.calories_kcal).toBe(3261)
      expect(r.daily_balance_reference_kcal).toBe(2609)
      // §2c: gain/maintenance expenditure already includes activity; exercise
      // stays recorded but is not subtracted a second time in this balance.
      expect(r.daily_balance_kcal).toBe(-1959)
      expect(r.daily_balance_includes_exercise).toBe(false)
      expect(r.targets.calories_source).toBe('daily_snapshot')
      expect(db.calls).toContainEqual(['daily_snapshots', 'date', '2026-10-26'])
      expect(db.stored.calories_target).toBe(3261)
    } finally {
      clearCalcConfigCache()
    }
  })
  it('does not run the legacy target fallback through the real reader when no target was stored', async () => {
    const s = snapshot()
    s.phase_origin = { kind: 'assigned', phase: 'ganho_massa' }
    const db = actualTodayClient(null, undefined, 'ganho_massa', s)
    const r = await createCurrentClinicalReadModel(db.client, {
      capture: async () => structuredClone(s),
    }).today(auth, url)
    expect(r.targets).toMatchObject({ calories_kcal: null, protein_g: null, source: 'unavailable' })
    expect(r.consumed.calories_kcal).toBe(650)
    expect(r.daily_balance_kcal).toBeNull()
    expect(db.stored.calories_target).toBeNull()
  })

  it('retains official targets, records, freshness/version and latches for a healthy assigned account', async () => {
    const h = setup(),
      result = await h.model.today(auth, url)
    expect(result.targets).toEqual(h.baseToday.targets)
    expect(result.meals).toEqual(h.baseToday.meals)
    expect(result.consumed).toEqual(h.baseToday.consumed)
    expect(result.calculation_version).toBe(h.baseToday.calculation_version)
    expect(result.clinical_policy).toMatchObject({ version: 1, target_source: 'assigned_phase' })
    expect(h.reads.today.mock.calls[0]?.[1]).toBe(owner)
    expect(h.current).toHaveBeenCalledTimes(2)
  })
  it.each([
    'minor',
    'pregnant',
  ])('suppresses every target/derived guidance for %s and keeps recording data', async (kind) => {
    const s = kind === 'pregnant' ? hold(snapshot(), 'pregnant_or_breastfeeding') : snapshot()
    if (kind === 'minor') {
      s.body.birth_date = '2010-01-01'
      s.safety.no_plan = true
      s.safety.hide_protein = true
    }
    const h = setup(s),
      result = await h.model.today(auth, url)
    expect(result.protocol).toBeNull()
    expect(result.current_protocol).toBeNull()
    expect(result.targets).toMatchObject({
      calories_kcal: null,
      protein_g: null,
      source: 'unavailable',
    })
    expect(result.remaining_food_kcal).toBeNull()
    expect(result.daily_balance_kcal).toBeNull()
    expect(result.daily_balance_reference_kcal).toBeNull()
    expect(result.daily_balance_includes_exercise).toBeNull()
    expect(result.protein_status).toMatchObject({
      target_g: null,
      remaining_g: null,
      percentage: null,
      status: 'target_unavailable',
    })
    expect(result.block_7700).toMatchObject({
      enabled: false,
      current_kcal: null,
      completed_blocks: null,
    })
    expect(result.consumed.calories_kcal).toBe(650)
    expect(result.meals).toEqual(h.baseToday.meals)
    expect(result.hydration.consumed_ml).toBe(500)
    expect(result.clinical_policy?.recording_allowed).toBe(true)
    expect(JSON.stringify(result)).not.toContain('pregnant_or_breastfeeding')
  })
  it('does not assign a first phase or targets after an actual no-plan origin becomes unguarded', async () => {
    const s = snapshot()
    s.phase_origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: generation,
      signupEpoch: epoch,
      completedAt: completed,
    }
    const h = setup(s)
    h.baseToday.current_protocol = null
    const r = await h.model.today(auth, url)
    expect(r.targets.calories_kcal).toBeNull()
    expect(r.clinical_policy).toMatchObject({
      phase_selection_pending: true,
      target_source: 'unavailable',
    })
  })
  it('legacy NULL is not no-plan, and mixed sources are checked separately without inferring numeric equality', async () => {
    const s = snapshot()
    s.phase_origin = { kind: 'legacy_unassigned' }
    const h = setup(s)
    h.baseToday.current_protocol = null
    h.baseToday.targets.protein_source = 'profile_calculation'
    h.baseToday.targets.protein_g = 120
    h.baseToday.targets.source = 'mixed'
    const r = await h.model.today(auth, url)
    expect(r.targets.calories_kcal).toBe(1900)
    expect(r.targets.protein_g).toBeNull()
    expect(r.targets.source).toBe('mixed')
    expect(r.sources.targets).toBe('mixed')
    expect(r.clinical_policy).toMatchObject({
      target_source: 'official_only',
      phase_selection_pending: false,
    })
  })
  it('never publishes profile-calculated fallback as an official target, even for assigned phase', async () => {
    const h = setup()
    h.baseToday.targets.calories_source = 'profile_calculation'
    h.baseToday.targets.calories_kcal = 1900
    const r = await h.model.today(auth, url)
    expect(r.targets.calories_kcal).toBeNull()
    expect(r.remaining_food_kcal).toBeNull()
    expect(r.daily_balance_kcal).toBeNull()
    expect(r.exercise_kcal).toBe(100)
  })
  it('HOLD keeps stored targets/phase but strips opaque nutrition and welcome guidance', async () => {
    const h = setup(hold()),
      p = await h.model.plan(auth, url),
      protocol = await h.model.protocol(auth, url)
    expect(p.nutrition).toEqual([])
    expect(p.clinical_policy?.pause_weight_loss_guidance).toBe(true)
    expect(protocol.current_protocol).toBe('recomposicao')
    expect(protocol.targets.calories).toBe(1900)
    expect(protocol.welcome).toBeNull()
  })
  it('professional diet hides protein target while preserving the stored calorie target and consumed food', async () => {
    const h = setup(hold(snapshot(), 'professional_diet')),
      r = await h.model.today(auth, url)
    expect(r.targets.calories_kcal).toBe(1900)
    expect(r.targets.protein_g).toBeNull()
    expect(r.consumed.protein_g).toBe(25)
  })
  it('Progress/Trends suppress numeric guidance only in a negotiated representation, not persisted history', async () => {
    const h = setup(hold(snapshot(), 'pregnant_or_breastfeeding'))
    const p = await h.model.progress(auth, url),
      t = await h.model.trends(auth, url, { days: 7 })
    expect(p?.blocks_completed).toBeNull()
    expect(p?.deficit_block).toBeNull()
    expect(p?.current_weight).toBe(80)
    expect(t.daily[0]).toMatchObject({
      calories_consumed: 650,
      calories_target: null,
      protein_target: null,
      deficit_accumulated: null,
      water_consumed_ml: 500,
      day_closed: true,
    })
    expect(t.weights).toEqual([{ date: '2026-10-25', weight_kg: 80 }])
    expect(
      (await h.reads.trends(h.client, owner, { days: 7 }, 'America/Sao_Paulo')).daily[0]
        ?.deficit_accumulated,
    ).toBe(300)
  })
  it.each([
    'minor',
    'hold',
    'professional',
    'await_phase',
  ])('refuses old representation before numeric readers for %s', async (kind) => {
    let s = snapshot()
    if (kind === 'minor') {
      s.body.birth_date = '2010-01-01'
      s.safety.no_plan = true
      s.safety.hide_protein = true
    }
    if (kind === 'hold') s = hold(s)
    if (kind === 'professional') s = hold(s, 'professional_diet')
    if (kind === 'await_phase')
      s.phase_origin = {
        kind: 'confirmed_no_plan',
        signupGeneration: generation,
        signupEpoch: epoch,
        completedAt: completed,
      }
    const h = setup(s)
    await expect(h.model.today(auth, legacyURL)).rejects.toMatchObject({
      status: 409,
      code: 'clinical_client_update_required',
    })
    expect(h.reads.today).not.toHaveBeenCalled()
    expect(h.current).toHaveBeenCalledTimes(1)
  })
  it('does not add a new field to a healthy legacy representation', async () => {
    const h = setup(),
      r = await h.model.today(auth, legacyURL)
    expect(r).not.toHaveProperty('clinical_policy')
    expect(r.targets).toEqual(h.baseToday.targets)
  })
  it.each([
    '',
    'wrong',
    'current_clinical_v2',
    'current_clinical_v1&clinical_policy=current_clinical_v1',
  ])('refuses malformed negotiation %s before any capture', async (value) => {
    const h = setup()
    await expect(
      h.model.today(auth, `${url.split('?')[0]}?clinical_policy=${value}`),
    ).rejects.toMatchObject({ status: 400, code: 'invalid_clinical_policy_representation' })
    expect(h.current).not.toHaveBeenCalled()
    expect(h.reads.today).not.toHaveBeenCalled()
  })
  it('extracts only negotiation and preserves strict business query parameters', () => {
    const r = readClinicalRepresentation(`${url}&days=7`)
    expect(r.compatible).toBe(true)
    expect([...r.search.entries()]).toEqual([['days', '7']])
  })
  it.each([
    'owner',
    'health',
    'config',
    'date',
    'profile',
    'epoch',
    'generation',
  ])('refuses %s changing during a read rather than serving a stale policy', async (kind) => {
    const h = setup()
    const changed = snapshot()
    if (kind === 'owner') changed.user_id = other
    if (kind === 'health') Object.assign(changed, hold())
    if (kind === 'config')
      changed.calculation_config = [{ key: 'calc.training_min', value: 3, updated_at: at }]
    if (kind === 'date') {
      changed.date = '2026-10-27'
      changed.safety.date = changed.date
      changed.observed_at = '2026-10-27T10:00:00.000001Z'
      changed.safety.observed_at = changed.observed_at
    }
    if (kind === 'profile') changed.profile_hash = 'c'.repeat(64)
    if (kind === 'epoch') changed.epoch = other
    if (kind === 'generation') changed.signup_generation = other
    h.current.mockResolvedValueOnce(snapshot()).mockResolvedValueOnce(changed)
    await expect(h.model.today(auth, url)).rejects.toMatchObject({
      status: kind === 'owner' ? 500 : 409,
    })
  })
  it('ignores fresh observation clock/hash in the stable binding and detaches numeric output before second await', async () => {
    const h = setup()
    let calls = 0
    h.current.mockImplementation(async () => {
      const s = snapshot()
      if (++calls === 2) {
        h.baseToday.targets.calories_kcal = 9999
        s.observed_at = '2026-10-26T10:01:00.000001Z'
        s.safety.observed_at = s.observed_at
        s.context_hash = 'c'.repeat(64)
      }
      return s
    })
    const r = await h.model.today(auth, url)
    expect(r.targets.calories_kcal).toBe(1900)
    expect(Object.isFrozen(r.targets)).toBe(true)
  })
  it('uses immutable owner/client and server timezone even if auth changes during capture', async () => {
    const h = setup(),
      localAuth = structuredClone(auth)
    h.current.mockImplementationOnce(async () => {
      localAuth.userId = other
      localAuth.patient.timezone = 'Pacific/Honolulu'
      return snapshot()
    })
    await h.model.today(localAuth, url)
    expect(h.reads.today.mock.calls[0]?.[0]).toBe(h.client)
    expect(h.reads.today.mock.calls[0]?.[1]).toBe(owner)
    expect(h.reads.today.mock.calls[0]?.[2]).toMatchObject({
      timezone: 'America/Sao_Paulo',
      date: '2026-10-26',
    })
  })
  it('propagates the underlying official reader refusal, without a second/fallback read', async () => {
    const h = setup()
    h.reads.today.mockRejectedValueOnce(new Error('official latch changed'))
    await expect(h.model.today(auth, url)).rejects.toThrow('official latch changed')
    expect(h.current).toHaveBeenCalledTimes(1)
    expect(h.reads.today).toHaveBeenCalledTimes(1)
  })
  it('rejects a backwards clinical observation rather than presenting it as fresh', async () => {
    const h = setup(),
      old = snapshot()
    old.observed_at = '2026-10-26T09:59:59.000001Z'
    old.safety.observed_at = old.observed_at
    h.current.mockResolvedValueOnce(snapshot()).mockResolvedValueOnce(old)
    await expect(h.model.today(auth, url)).rejects.toMatchObject({
      status: 409,
      code: 'mobile_current_clinical_changed',
    })
  })
  it('refuses a Today result from a different civil day without changing either day', async () => {
    const h = setup()
    h.baseToday.local_date = '2026-10-25'
    await expect(h.model.today(auth, url)).rejects.toMatchObject({ status: 409 })
    expect(h.baseToday.consumed.calories_kcal).toBe(650)
  })
  it('does not relabel a stale current protocol using a fresh current snapshot', async () => {
    const h = setup()
    h.baseToday.current_protocol = 'ganho_massa'
    await expect(h.model.today(auth, url)).rejects.toMatchObject({ status: 409 })
  })
  it('keeps an absent progress row absent, and does not manufacture measurements or counters', async () => {
    const h = setup()
    h.reads.progress.mockResolvedValueOnce(null)
    expect(await h.model.progress(auth, url)).toBeNull()
  })
  it('rejects a substituted authenticated owner before the clinical or numeric source', async () => {
    const h = setup()
    await expect(h.model.today({ ...auth, userId: other }, url)).rejects.toMatchObject({
      status: 403,
    })
    expect(h.current).not.toHaveBeenCalled()
    expect(h.reads.today).not.toHaveBeenCalled()
  })
})

/** HTTP tests use the real route/auth wrapper and real clinical reader. Only
 * Auth and SQL transport are controlled; effects are explicit dormant ports. */
function httpSetup(endpoint: ClinicalReadEndpoint = 'today', s = snapshot()) {
  const h = setup(s),
    calls: string[] = [],
    localAuth = structuredClone(auth)
  h.current.mockImplementation(async () => {
    calls.push('capture')
    return structuredClone(s)
  })
  h.reads.today.mockImplementation(async () => {
    calls.push('numeric')
    return h.baseToday
  })
  const effects: ClinicalHttpDependencies = {
    createReadModel: (_client: ServiceClient) => h.model,
    async applyDaily(scope: { auth: MobileAuthContext; admission: { owner: string } }) {
      expect(scope.auth.userId).toBe(owner)
      expect(scope.admission.owner).toBe(owner)
      calls.push('daily')
    },
    async closeDays(scope: { auth: MobileAuthContext; admission: { owner: string } }) {
      expect(scope.auth.userId).toBe(owner)
      expect(scope.admission.owner).toBe(owner)
      calls.push('closer')
    },
  }
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => h.client,
    createRequestId: () => 'request-not-a-daily-uuid',
    async authenticate() {
      calls.push('auth')
      return localAuth
    },
    async authorizeEntitlement() {
      calls.push('entitlement')
    },
  }
  function route() {
    return endpoint === 'today'
      ? todayHandlers.createTodayGetRoute(runtime, () => false, effects)
      : todayHandlers.createCurrentClinicalGetRoute(endpoint, runtime, effects, () => false)
  }
  return { ...h, calls, localAuth, effects, runtime, route }
}

describe('clinical HTTP preflight and server-only composition', () => {
  it('establishes the explicit scoped source only after the representation gate and returns its fresh baseline', async () => {
    const h = setup()
    const fresh = {
      ...snapshot(),
      signup_generation: other,
      generation_authority: {
        kind: 'legacy_transition',
        user_id: owner,
        generation: other,
        epoch,
        admitted_at: completed,
        admitted_date: '2026-10-25',
        timezone_at_admission: 'America/Sao_Paulo',
        profile_completed_marker: completed,
      },
    }
    const establish = vi.fn(async () => readCurrentClinicalState(fresh, owner))
    const model = createCurrentClinicalReadModel(h.client, { capture: h.current }, h.reads, {
      admission: { establish },
    })
    const admission = await model.preflight(auth, url, 'today')
    expect(establish).toHaveBeenCalledOnce()
    expect(admission.state.signup_generation).toBe(other)
    expect(admission.state.generation_authority?.kind).toBe('legacy_transition')
    expect(h.reads.today).not.toHaveBeenCalled()
    const guarded = setup(hold())
    const refused = vi.fn()
    const gate = createCurrentClinicalReadModel(
      guarded.client,
      { capture: guarded.current },
      guarded.reads,
      { admission: { establish: refused } },
    )
    await expect(gate.preflight(auth, legacyURL, 'today')).rejects.toMatchObject({
      code: 'clinical_client_update_required',
    })
    expect(refused).not.toHaveBeenCalled()
    await expect(model.preflight(auth, url + '&days=invalid', 'trends')).rejects.toBeDefined()
    expect(establish).toHaveBeenCalledTimes(1)
  })
  it.each([
    'today',
    'progress',
  ] as const)('keeps confirmed no-plan %s available without calling the daily formula/writer', async (endpoint) => {
    const s = snapshot()
    s.phase_origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: generation,
      signupEpoch: epoch,
      completedAt: completed,
    }
    const h = httpSetup(endpoint, s)
    h.baseToday.current_protocol = null
    h.reads.progress.mockResolvedValue({ ...progress(), current_protocol: null })
    const nextOperationKey = vi.fn(() => other)
    const createService = vi.fn(() => {
      throw new Error('No-plan must not calculate targets')
    })
    h.effects.applyDaily = createClinicalDailyEffect({ nextOperationKey, createService })
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    expect((await response.json()).data.clinical_policy).toMatchObject({
      recording_allowed: true,
      phase_selection_pending: true,
      target_source: 'unavailable',
    })
    expect(nextOperationKey).not.toHaveBeenCalled()
    expect(createService).not.toHaveBeenCalled()
    expect(h.calls).toContain('closer')
    // Today closes the additional async weekly enrichment publication window.
    expect(h.calls.filter((c) => c === 'capture')).toHaveLength(endpoint === 'today' ? 4 : 3)
  })
  it('does not skip an assigned HOLD: its daily service must reach the SQL safety branch', async () => {
    const h = httpSetup('today', hold())
    const apply = vi.fn(async () => ({
      version: 1 as const,
      availability: 'unavailable' as const,
      reason: 'clinical_episode_unavailable' as const,
      date: '2026-10-26',
    }))
    const nextOperationKey = vi.fn(() => other)
    h.effects.applyDaily = createClinicalDailyEffect({
      nextOperationKey,
      createService: () => ({ apply }),
    })
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    expect(apply).toHaveBeenCalledTimes(1)
    expect(apply).toHaveBeenCalledWith(expect.objectContaining({ userId: owner }), {
      operationKey: other,
    })
    expect(nextOperationKey).toHaveBeenCalledTimes(1)
    expect((await response.json()).data.clinical_policy.pause_weight_loss_guidance).toBe(true)
  })
  it.each([
    'today',
    'progress',
  ] as const)('preserves unknown-phase legacy %s and still closes records without assigning daily targets', async (endpoint) => {
    const state = snapshot()
    state.phase_origin = { kind: 'legacy_unassigned' }
    const h = httpSetup(endpoint, state)
    h.baseToday.current_protocol = null
    h.reads.progress.mockResolvedValue({ ...progress(), current_protocol: null })
    const nextOperationKey = vi.fn(() => other)
    const createService = vi.fn(() => {
      throw new Error('Unknown phase cannot become a target writer')
    })
    h.effects.applyDaily = createClinicalDailyEffect({ nextOperationKey, createService })
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data.clinical_policy).toMatchObject({
      recording_allowed: true,
      phase_selection_pending: false,
      target_source: 'official_only',
    })
    if (endpoint === 'today') {
      expect(data.targets.calories_kcal).toBe(1900)
      expect(data.consumed.calories_kcal).toBe(650)
    }
    expect(nextOperationKey).not.toHaveBeenCalled()
    expect(createService).not.toHaveBeenCalled()
    expect(h.calls).toContain('closer')
    expect(h.calls.filter((call) => call === 'capture')).toHaveLength(endpoint === 'today' ? 4 : 3)
  })
  it('preserves an initial phase which is not yet civil-effective without a legacy fallback or HTTP failure', async () => {
    const h = httpSetup('today', snapshot())
    const apply = vi.fn(async () => ({
      version: 1 as const,
      availability: 'unavailable' as const,
      reason: 'phase_not_started' as const,
      date: '2026-10-26',
    }))
    h.effects.applyDaily = createClinicalDailyEffect({
      nextOperationKey: () => other,
      createService: () => ({ apply }),
    })
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    expect(apply).toHaveBeenCalledOnce()
    expect(h.calls).toContain('closer')
  })
  it('rejects an old client before even constructing the no-plan daily effect service', async () => {
    const s = snapshot()
    s.phase_origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: generation,
      signupEpoch: epoch,
      completedAt: completed,
    }
    const h = httpSetup('today', s),
      createService = vi.fn(() => {
        throw new Error('Forbidden')
      })
    h.effects.applyDaily = createClinicalDailyEffect({ createService })
    expect((await h.route()(new Request(legacyURL))).status).toBe(409)
    expect(createService).not.toHaveBeenCalled()
    expect(h.calls).not.toContain('closer')
  })
  it('stops a changed daily application without a closer or fallback numeric reader', async () => {
    const h = httpSetup(),
      apply = vi.fn(async () => {
        throw clinicalDailyRepositoryError('changed')
      })
    h.effects.applyDaily = createClinicalDailyEffect({
      nextOperationKey: () => other,
      createService: () => ({ apply }),
    })
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(409)
    expect(apply).toHaveBeenCalledTimes(1)
    expect(h.calls).not.toContain('closer')
    expect(h.reads.today).not.toHaveBeenCalled()
  })
  it('uses the server-only clinical composition instead of the legacy closer', async () => {
    const h = httpSetup(),
      handler = h.route()
    const response = await handler(new Request(url))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toMatchObject({
      targets: { calories_kcal: 1900 },
      clinical_policy: { version: 1 },
    })
    expect(h.calls).toEqual([
      'auth',
      'entitlement',
      'capture',
      'daily',
      'closer',
      'capture',
      'numeric',
      'capture',
      'capture',
    ])
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(response.headers.get('X-Request-Id')).toBe('request-not-a-daily-uuid')
  })
  it('rejects an unsupported current Protocol locale before any numeric reads', async () => {
    const s = snapshot()
    s.body.locale = 'fr-FR'
    const h = setup(s)
    await expect(h.model.protocol(auth, url)).rejects.toMatchObject({
      status: 409,
      code: 'protocol_locale_unsupported',
    })
    expect(h.reads.today).not.toHaveBeenCalled()
    expect(h.reads.profile).not.toHaveBeenCalled()
  })
  it.each([
    401, 402, 403,
  ])('preserves the auth/entitlement %s before clinical I/O', async (status) => {
    const h = httpSetup()
    const denied = new MobileApiError(status, 'denied', 'Denied')
    if (status === 401)
      h.runtime.authenticate = async () => {
        throw denied
      }
    else
      h.runtime.authorizeEntitlement = async () => {
        throw denied
      }
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(status)
    expect(h.current).not.toHaveBeenCalled()
    expect(h.calls).not.toContain('daily')
    expect(h.calls).not.toContain('closer')
    expect(h.reads.today).not.toHaveBeenCalled()
  })
  it.each([
    '?clinical_policy=',
    '?clinical_policy=nope',
    '?clinical_policy=current_clinical_v1&clinical_policy=current_clinical_v1',
  ])('rejects malformed negotiation %s before effects', async (query) => {
    const h = httpSetup(),
      response = await h.route()(new Request(legacyURL + query))
    expect(response.status).toBe(400)
    expect(h.current).not.toHaveBeenCalled()
    expect(h.calls).toEqual(['auth', 'entitlement'])
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
  it('refuses an old representation under current risk before effects or numbers', async () => {
    const h = httpSetup('today', hold()),
      response = await h.route()(new Request(legacyURL))
    expect(response.status).toBe(409)
    expect((await response.json()).error.code).toBe('clinical_client_update_required')
    expect(h.calls).toEqual(['auth', 'entitlement', 'capture'])
    expect(h.reads.today).not.toHaveBeenCalled()
  })
  it('keeps the preflight admission detached and fixes effect methods before await', async () => {
    const h = httpSetup(),
      handler = h.route()
    h.current.mockImplementationOnce(async () => {
      h.localAuth.userId = other
      h.localAuth.patient.id = other
      h.effects.applyDaily = async () => {
        throw new Error('substituted callback')
      }
      return snapshot()
    })
    expect((await handler(new Request(url))).status).toBe(200)
    expect(h.calls).toContain('daily')
    expect(h.calls).toContain('closer')
  })
  it.each([
    'daily',
    'closer',
  ])('propagates the %s CAS refusal without a fallback reader', async (stage) => {
    const h = httpSetup()
    const failure = async () => {
      throw new MobileApiError(409, 'clinical_changed', 'Changed')
    }
    if (stage === 'daily') h.effects.applyDaily = failure
    else h.effects.closeDays = failure
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(409)
    expect((await response.json()).error.code).toBe('clinical_changed')
    expect(h.reads.today).not.toHaveBeenCalled()
    if (stage === 'daily') expect(h.calls).not.toContain('closer')
  })
  it('reads a fresh policy after a legitimate clinical effect rather than publishing the preflight snapshot', async () => {
    const h = httpSetup()
    h.effects.applyDaily = async () => {
      Object.assign(h.s, hold())
    }
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    expect((await response.json()).data.clinical_policy.pause_weight_loss_guidance).toBe(true)
  })
  it.each([
    'plan',
    'trends',
    'protocol',
  ] as const)('uses the guarded %s reader without adding a daily or closer write', async (endpoint) => {
    const h = httpSetup(endpoint),
      response = await h.route()(new Request(`${url}&days=7`))
    expect(response.status).toBe(200)
    expect((await response.json()).data.clinical_policy.version).toBe(1)
    expect(h.calls).not.toContain('daily')
    expect(h.calls).not.toContain('closer')
  })
  it('removes only clinical negotiation before validating the strict Trends query', async () => {
    const h = httpSetup('trends'),
      response = await h.route()(new Request(`${url}&days=7&unknown=x`))
    expect(response.status).toBe(422)
    expect(h.current).not.toHaveBeenCalled()
    expect(h.reads.trends).not.toHaveBeenCalled()
  })
  it('preserves an absent Progress row and runs the required clinical effects first', async () => {
    const h = httpSetup('progress')
    h.reads.progress.mockResolvedValueOnce(null)
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toBeNull()
    expect(h.calls.slice(0, 5)).toEqual(['auth', 'entitlement', 'capture', 'daily', 'closer'])
  })
  it('refuses unsupported current locale in the Protocol preflight', async () => {
    const s = snapshot()
    s.body.locale = 'fr-FR'
    const h = httpSetup('protocol', s)
    const response = await h.route()(new Request(url))
    expect(response.status).toBe(409)
    expect(h.reads.profile).not.toHaveBeenCalled()
    expect(h.reads.today).not.toHaveBeenCalled()
  })
})
