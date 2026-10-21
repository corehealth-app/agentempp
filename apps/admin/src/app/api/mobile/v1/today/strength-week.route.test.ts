/** Real route wrapper, weekly repository/composer/core; controlled Auth and RPC.
 * No PostgREST/database execution is claimed by this HTTP contract suite. */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from '@/lib/mobile-api/auth'
import { MobileApiError } from '@/lib/mobile-api/http'
import type { StrengthWeekTarget } from '@/lib/mobile-api/strength-training-week-service'
import { createTodayGetRoute } from '@/lib/mobile-api/today-handler'
import { loadTodayStrengthTrainingWeek } from '@/lib/mobile-api/today-strength-training-week'

const dependencies = vi.hoisted(() => ({
  authenticate: vi.fn(),
  authorize: vi.fn(),
  createServiceClient: vi.fn(),
  loadToday: vi.fn(),
}))
vi.mock('@/lib/mobile-api/auth', () => ({ authenticatePatient: dependencies.authenticate }))
vi.mock('@/lib/mobile-api/supabase-auth', () => ({ createMobileAuthDependencies: () => ({}) }))
vi.mock('@/lib/mobile-api/entitlement-service', () => ({
  authorizeMobileEntitlement: dependencies.authorize,
}))
vi.mock('@/lib/supabase/server', () => ({ createServiceClient: dependencies.createServiceClient }))
vi.mock('@/lib/mobile-api/read-model', () => ({ loadToday: dependencies.loadToday }))

const { GET } = await import('./route')
const id = (n: number) => `a6000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const OWNER = id(1)
const STAGING = 'xitugspwfxkcluxvrdeg'
const DAILY = {
  local_date: '2026-10-14',
  current_protocol: 'recomposicao',
  protocol: 'recomposicao',
  marker: 'unchanged daily data',
}
const AUTH: MobileAuthContext = {
  accessToken: 'synthetic-token',
  authUserId: id(70),
  userId: OWNER,
  identity: { id: id(70), email: null, emailConfirmedAt: null },
  patient: {
    id: OWNER,
    authUserId: id(70),
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'UTC',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
const target = (): StrengthWeekTarget => ({
  target_id: id(4),
  user_id: OWNER,
  generation: id(2),
  week_start: '2026-10-12',
  timezone_at_freeze: 'UTC',
  frozen_at: '2026-10-12T00:00:00.123456Z',
  source: 'accepted_plan',
  planned_days: 3,
  source_key: id(5),
  source_proof: {
    plan: { coverage: 'covered', source_version_id: id(5), source_order: '9007199254740993' },
    frequency: {
      coverage: 'covered',
      source_version_id: id(6),
      source_order: '9223372036854775807',
    },
  },
})
const workout = (n: number, localDate = '2026-10-12') => ({
  ownerKey: OWNER,
  workoutKey: id(n),
  localDate,
  state: 'confirmed',
  catalogueCategory: 'musculacao',
  storedStrengthAnswer: null,
})
function available(t = target()) {
  return {
    status: 'available',
    target: t,
    binding: {
      ownerID: OWNER,
      generation: id(2),
      epoch: id(7),
      lifecycleKey: id(3),
      signupAdmissionID: id(8),
      frequencySourceVersionID: id(9),
      workoutAdmissionID: id(10),
      workoutContentRevision: 0,
      boundAt: '2026-10-11T12:00:00.123456Z',
    },
    calendar: {
      ownerID: OWNER,
      lifecycleKey: id(3),
      scopeKey: id(11),
      timeZone: 'UTC',
      weekStartDate: '2026-10-12',
      asOfLocalDate: '2026-10-14',
    },
    projection: {
      status: 'available',
      workouts: [workout(20), workout(21), workout(22, '2026-10-13')],
    },
    observed_at: '2026-10-14T12:00:00.123457Z',
  }
}
const reply = (data: unknown) => ({ data, error: null })
function outcomes(t = target(), projected: unknown = available(t), readTarget = t) {
  return [
    reply({
      status: 'ready',
      context: {
        kind: 'existing_target',
        user_id: OWNER,
        generation: id(2),
        timezone: 'UTC',
        week_start: '2026-10-12',
        observed_at: '2026-10-14T12:00:00.123456Z',
        target: readTarget,
      },
    }),
    reply({ status: 'reused', target: t }),
    reply(projected),
  ]
}
function client(responses: { data: unknown; error: unknown }[] = outcomes()) {
  const rpc = vi.fn(async (_name: string, _parameters: unknown) => {
    const next = responses.shift()
    if (!next) throw new Error('Unexpected RPC or implicit retry')
    return structuredClone(next)
  })
  const db = { rpc } as unknown as ServiceClient
  dependencies.createServiceClient.mockReturnValue(db)
  return { db, rpc }
}
function request() {
  return new Request(
    `https://bodyflow.test/api/mobile/v1/today?user_id=${id(999)}&observed_at=2030-01-01`,
    { headers: { 'x-request-id': 'weekly-request-1' } },
  )
}
const EXPECTED = {
  status: 'available',
  week_start: '2026-10-12',
  as_of_local_date: '2026-10-14',
  time_zone: 'UTC',
  observed_at: '2026-10-14T12:00:00.123457Z',
  completed_strength_days: 2,
  planned_days: 3,
  target_source: 'accepted_plan',
  target_availability: 'available',
  percentage: 67,
}

beforeEach(() => {
  vi.resetAllMocks()
  dependencies.authenticate.mockResolvedValue(AUTH)
  dependencies.authorize.mockResolvedValue(undefined)
  dependencies.loadToday.mockResolvedValue(structuredClone(DAILY))
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', '')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING}.supabase.co`)
  vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', STAGING)
})
afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('explicit server weekly composition', () => {
  it('keeps the real route wrapper and composes the official daily and weekly results explicitly', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'http://127.0.0.1:21994')
    const { rpc } = client()
    const response = await createTodayGetRoute(undefined, () => true)(request())
    expect(response.status).toBe(200)
    expect(response.headers.get('vary')).toBe('Authorization')
    expect((await response.json()).data).toEqual({ ...DAILY, strength_training_week: EXPECTED })
    expect(rpc).toHaveBeenCalledTimes(3)
  })

  it.each([
    403, 402,
  ])('cannot bypass a real wrapper denial %i with an enabled weekly callback', async (status) => {
    const denied = new MobileApiError(status, 'test_access_denied', 'Access denied')
    if (status === 403) dependencies.authenticate.mockRejectedValue(denied)
    else dependencies.authorize.mockRejectedValue(denied)
    const { rpc } = client([])
    expect((await createTodayGetRoute(undefined, () => true)(request())).status).toBe(status)
    expect(dependencies.loadToday).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('stops before weekly composition if the daily read fails', async () => {
    dependencies.loadToday.mockRejectedValue(
      new MobileApiError(500, 'data_access_failed', 'Daily state lookup failed'),
    )
    const { rpc } = client([])
    expect((await createTodayGetRoute(undefined, () => true)(request())).status).toBe(500)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('preserves a weekly operational failure in the explicitly composed route', async () => {
    const { rpc } = client([
      { data: null, error: { code: 'XX001', message: 'private provider detail' } },
    ])
    const response = await createTodayGetRoute(undefined, () => true)(request())
    expect(response.status).toBe(500)
    expect((await response.json()).error).toEqual({
      code: 'strength_week_data_access_failed',
      message: 'Strength week lookup failed',
      request_id: 'weekly-request-1',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('reads the official summary with a loopback configuration and an explicit enabled callback', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'http://127.0.0.1:21994')
    const { db, rpc } = client()
    expect(await loadTodayStrengthTrainingWeek(db, OWNER, 'recomposicao', () => true)).toEqual(
      EXPECTED,
    )
    expect(rpc).toHaveBeenCalledTimes(3)
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_user_id: OWNER })
  })

  it('explicit OFF preserves omission and no RPC even with a globally allowed project', async () => {
    const { db, rpc } = client([])
    expect(
      await loadTodayStrengthTrainingWeek(db, OWNER, 'recomposicao', () => false),
    ).toBeUndefined()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('consults the current callback and propagates real repository errors without retry', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'http://127.0.0.1:21994')
    let enabled = false
    const { db, rpc } = client([
      { data: null, error: { code: 'XX001', message: 'private provider detail' } },
    ])
    const current = () => enabled
    expect(await loadTodayStrengthTrainingWeek(db, OWNER, 'recomposicao', current)).toBeUndefined()
    enabled = true
    await expect(
      loadTodayStrengthTrainingWeek(db, OWNER, 'recomposicao', current),
    ).rejects.toMatchObject({ status: 500, code: 'strength_week_data_access_failed' })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})

describe('GET /today weekly strength public boundary', () => {
  it('OFF preserves the exact daily object and never touches weekly RPC', async () => {
    vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', '')
    const { rpc } = client([])
    const response = await GET(request())
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual(DAILY)
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    null,
    undefined,
    'unknown',
  ])('does not infer eligibility from the historical protocol when current_protocol is %s', async (current_protocol) => {
    const daily = { ...DAILY, current_protocol }
    dependencies.loadToday.mockResolvedValue(daily)
    const { rpc } = client([])
    expect((await (await GET(request())).json()).data).toEqual(JSON.parse(JSON.stringify(daily)))
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ])('publishes the official weekly summary for %s without internal proofs', async (current_protocol) => {
    dependencies.loadToday.mockResolvedValue({ ...DAILY, current_protocol })
    const { db, rpc } = client()
    const response = await GET(request())
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expect((await response.json()).data).toEqual({
      ...DAILY,
      current_protocol,
      strength_training_week: EXPECTED,
    })
    expect(dependencies.authorize).toHaveBeenCalledWith(db, OWNER, '/api/mobile/v1/today')
    expect(dependencies.loadToday).toHaveBeenCalledWith(db, OWNER, 'UTC')
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'get_mobile_strength_week_context',
      'freeze_mobile_strength_week_target',
      'get_mobile_strength_week_projection',
    ])
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_user_id: OWNER })
    expect(rpc.mock.calls[2]?.[1]).toEqual({
      p_user_id: OWNER,
      p_expected_generation: id(2),
      p_target_id: id(4),
    })
    expect(dependencies.authorize.mock.invocationCallOrder[0]).toBeLessThan(
      dependencies.loadToday.mock.invocationCallOrder[0] ?? 0,
    )
    expect(dependencies.loadToday.mock.invocationCallOrder[0]).toBeLessThan(
      rpc.mock.invocationCallOrder[0] ?? 0,
    )
  })

  it('publishes the persisted CAS winner, not the earlier read or the profile', async () => {
    const t: StrengthWeekTarget = {
      ...target(),
      target_id: id(12),
      source: 'informed_frequency',
      source_key: id(6),
      planned_days: 4,
    }
    const { rpc } = client(outcomes(t, available(t), target()))
    const response = await GET(request())
    expect((await response.json()).data.strength_training_week).toEqual({
      ...EXPECTED,
      planned_days: 4,
      target_source: 'informed_frequency',
      percentage: 50,
    })
    expect(rpc.mock.calls[2]?.[1]).toMatchObject({ p_target_id: id(12) })
  })

  it.each([
    'zero',
    'absent',
  ] as const)('preserves X and %s Y with no invented percentage', async (kind) => {
    const t: StrengthWeekTarget =
      kind === 'zero'
        ? { ...target(), source: 'informed_frequency', source_key: id(6), planned_days: 0 }
        : { ...target(), source: 'absent', source_key: null, planned_days: null }
    client(outcomes(t, available(t)))
    const response = await GET(request())
    expect((await response.json()).data.strength_training_week).toEqual({
      ...EXPECTED,
      planned_days: t.planned_days,
      target_source: t.source,
      target_availability: kind,
      percentage: null,
    })
  })

  it('preserves X above Y and the capped percentage from the real core', async () => {
    const raw = available()
    raw.calendar.asOfLocalDate = '2026-10-16'
    raw.observed_at = '2026-10-16T12:00:00.123457Z'
    raw.projection.workouts.push(workout(23, '2026-10-15'), workout(24, '2026-10-16'))
    client(outcomes(target(), raw))
    expect((await (await GET(request())).json()).data.strength_training_week).toEqual({
      ...EXPECTED,
      as_of_local_date: '2026-10-16',
      observed_at: raw.observed_at,
      completed_strength_days: 4,
      percentage: 100,
    })
  })

  it('keeps weekly calendar and UTC6 observation independent of daily date, cached auth zone and device/request clock', async () => {
    dependencies.authenticate.mockResolvedValue({
      ...AUTH,
      patient: { ...AUTH.patient, timezone: 'America/New_York' },
    })
    dependencies.loadToday.mockResolvedValue({ ...DAILY, local_date: '2026-10-11' })
    const { db } = client()
    const data = (await (await GET(request())).json()).data
    expect(data.local_date).toBe('2026-10-11')
    expect(data.strength_training_week).toEqual(EXPECTED)
    expect(dependencies.loadToday).toHaveBeenCalledWith(db, OWNER, 'America/New_York')
  })

  it.each([
    ['context', { status: 'unavailable', reason: 'missing_scope' }, 1],
    ['freeze', { status: 'conflict', reason: 'week_changed' }, 2],
    ['projection', { status: 'unavailable', reason: 'provenance_gap' }, 3],
    ['projection', { status: 'conflict', reason: 'generation_changed' }, 3],
  ] as const)('keeps %s negative typed and without partial fields', async (_stage, negative, count) => {
    const replies = outcomes().slice(0, count)
    replies[count - 1] = reply(negative)
    const { rpc } = client(replies)
    const response = await GET(request())
    expect(response.status).toBe(200)
    expect((await response.json()).data.strength_training_week).toEqual(negative)
    expect(rpc).toHaveBeenCalledTimes(count)
  })

  it.each([
    401, 403, 402,
  ])('blocks weekly RPC and daily reads when auth/access refuses %i', async (status) => {
    const denied = new MobileApiError(status, 'test_access_denied', 'Access denied')
    if (status === 402) dependencies.authorize.mockRejectedValue(denied)
    else dependencies.authenticate.mockRejectedValue(denied)
    const { rpc } = client([])
    const response = await GET(request())
    expect(response.status).toBe(status)
    expect(dependencies.loadToday).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('does not freeze after the daily read fails', async () => {
    dependencies.loadToday.mockRejectedValue(
      new MobileApiError(500, 'data_access_failed', 'Daily state lookup failed'),
    )
    const { rpc } = client([])
    expect((await GET(request())).status).toBe(500)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('preserves provider failures as errors without retry or leaked detail', async () => {
    const { rpc } = client([
      { data: null, error: { code: 'XX001', message: 'secret provider detail' } },
    ])
    const response = await GET(request())
    expect(response.status).toBe(500)
    expect(await response.json()).toEqual({
      error: {
        code: 'strength_week_data_access_failed',
        message: 'Strength week lookup failed',
        request_id: 'weekly-request-1',
      },
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('rejects a malformed projection rather than publishing partial counts or unavailable', async () => {
    const raw = available()
    raw.binding.ownerID = id(999)
    const { rpc } = client(outcomes(target(), raw))
    const response = await GET(request())
    expect(response.status).toBe(500)
    expect((await response.json()).error.code).toBe('strength_week_invalid_response')
    expect(rpc).toHaveBeenCalledTimes(3)
  })
})
