/**
 * P-DEPOIS-1: current BF origin through the REAL GET /progress handler.
 * Only authentication is passed through; real hook/read-model/HTTP response.
 * DayCloseMemoryDb applies real query filters/projections. One explicit test
 * boundary supplies the current canonical closed signup-photo RPC response.
 *
 * TEST FIRST: current handler returns24 for profile24.00/progressBFnull and
 * omits current_bf_origin. The positive must fail at that missing field, after
 * real handler/status/BF gates; new-RPC call count is a GREEN oracle AFTER it.
 * No external network, SQL, model, Storage or native operation is performed.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import type { MobileRouteContext } from './route'

vi.mock('@/lib/mobile-api/route', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
  createMobileRoute: (handler: unknown) => handler,
}))
const { GET } = await import('@/app/api/mobile/v1/progress/route')
const handler = GET as unknown as (context: MobileRouteContext) => Promise<Response>

const OWNER = '00000000-0000-4000-8000-000000000961'
const OTHER = '00000000-0000-4000-8000-000000000962'
const GENERATION = '2026-10-13T12:00:00.123456+00:00'
const NOW = new Date('2026-10-14T15:00:00.000Z')
const RPC = 'get_mobile_signup_body_photo_snapshot'
const PRIVATE_ERROR = 'P_PROGRESS_PRIVATE_DATABASE_DETAIL'
const SOURCES = {
  front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
}
const FINGERPRINT = 'a'.repeat(64)
type Row = Record<string, unknown>

/** Current SQL closed snapshot: mean24 already confirmed, sources may be gone. */
function closedSnapshot(owner = OWNER) {
  return {
    version: 1,
    user_id: owner,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: GENERATION,
      receipt_count: 1,
    },
    poses: [],
    remaining_uploads: 0,
    consent: null,
    estimate: null,
    candidate: null,
    confirmation: {
      decision: 'accepted',
      method: 'arithmetic_mean_v1',
      source_ids: SOURCES,
      fingerprint: FINGERPRINT,
      confirmed_body_fat_percent: 24,
      decided_at: GENERATION,
      invalidated_at: null,
      active: true,
    },
  }
}

interface Options {
  profile?: Row
  progressBF?: unknown
  noProgress?: boolean
  noProfile?: boolean
  snapshot?: unknown
  rpcError?: { code?: string; message?: string }
  rpcThrow?: boolean
  returnedProfileOwner?: string
  allowDayClose?: boolean
}
function harness(options: Options = {}) {
  const db = new DayCloseMemoryDb()
  const snapshots = new Map<string, unknown>()
  const originCalls: Array<{ requestOwner: string; args: Row }> = []
  const unexpectedRpcs: string[] = []
  const selects: Array<{ requestOwner: string; table: string; columns: string }> = []
  const timeline: string[] = []
  function addAccount(owner: string, profile: Row = {}, progressBF: unknown = null) {
    db.addAccount({
      userId: owner,
      profile: {
        sex: 'masculino',
        birth_date: '1986-01-01',
        height_cm: 180,
        weight_kg: 80,
        activity_level: 'leve',
        training_frequency: 3,
        water_intake: 'moderado',
        hunger_level: 'moderada',
        current_protocol: 'recomposicao',
        deficit_level: 500,
        goal_type: null,
        goal_value: null,
        onboarding_completed: true,
        onboarding_completed_at: GENERATION,
        body_fat_percent: '24.00',
        bf_percent_estimated: 24,
        bf_source: 'signup_photos',
        bf_estimated_at: GENERATION,
        ...profile,
      },
      progress: { current_bf_percent: progressBF },
    })
    snapshots.set(owner, closedSnapshot(owner))
  }
  addAccount(OWNER, options.profile, options.progressBF === undefined ? null : options.progressBF)
  if (options.snapshot !== undefined) snapshots.set(OWNER, options.snapshot)
  if (options.noProgress) db.tables.user_progress.length = 0
  if (options.noProfile) db.tables.user_profiles.length = 0

  function context(owner: string): MobileRouteContext {
    const supabase = {
      from(table: string) {
        timeline.push(`select:${table}`)
        const query = db.from(table)
        const select = query.select.bind(query)
        query.select = (columns = '*') => {
          selects.push({ requestOwner: owner, table, columns })
          return select(columns)
        }
        if (table === 'user_profiles' && options.returnedProfileOwner) {
          const single = query.maybeSingle.bind(query)
          query.maybeSingle = async () => {
            const result = await single()
            const row = result.data
            return row && typeof row === 'object' && !Array.isArray(row)
              ? { ...result, data: { ...(row as Row), user_id: options.returnedProfileOwner } }
              : result
          }
        }
        return query
      },
      async rpc(name: string, args: Row) {
        timeline.push(`rpc:${name}`)
        if (name === RPC) {
          originCalls.push({ requestOwner: owner, args: structuredClone(args) })
          expect(args).toEqual({ p_user_id: owner, p_include_open_photos: false })
          if (options.rpcThrow) throw new Error(PRIVATE_ERROR)
          if (!snapshots.has(owner)) throw new Error('Missing canonical fixture owner')
          return { data: structuredClone(snapshots.get(owner)), error: options.rpcError ?? null }
        }
        if (
          options.allowDayClose &&
          [
            'finalize_daily_close_atomic',
            'finalize_mobile_daily_close_atomic',
            'reset_mobile_inactive_streak_atomic',
            'advance_reevaluation_schedule',
          ].includes(name)
        )
          return db.rpc(name, args)
        unexpectedRpcs.push(name)
        throw new Error('Unexpected progress fixture RPC')
      },
    } as unknown as ServiceClient
    return {
      request: new Request('https://bodyflow.test/api/mobile/v1/progress'),
      requestId: `progress-photo-origin-${owner}`,
      supabase,
      auth: {
        accessToken: 'synthetic-not-a-token',
        authUserId: owner,
        userId: owner,
        identity: { id: owner, email: null, emailConfirmedAt: null },
        patient: {
          id: owner,
          authUserId: owner,
          email: null,
          name: null,
          locale: 'pt-BR',
          timezone: 'America/Sao_Paulo',
          country: 'BR',
          countryConfirmed: true,
          status: 'active',
        },
      },
    }
  }
  async function answer(owner = OWNER) {
    const response = await handler(context(owner))
    return {
      response,
      body: (await response.json()) as { data: Row | null; meta: Row },
    }
  }
  return { db, snapshots, originCalls, unexpectedRpcs, selects, timeline, addAccount, answer }
}
type Harness = ReturnType<typeof harness>

function expectClosedReads(h: Harness, owners: string[] = [OWNER]) {
  expect(h.originCalls).toEqual(
    owners.map((owner) => ({
      requestOwner: owner,
      args: { p_user_id: owner, p_include_open_photos: false },
    })),
  )
  expect(h.unexpectedRpcs).toEqual([])
}
function expectNoPrivateProof(body: unknown) {
  const json = JSON.stringify(body)
  for (const privateValue of [
    ...Object.values(SOURCES),
    FINGERPRINT,
    GENERATION,
    'confirmed_body_fat_percent',
    'generation_token',
    'arithmetic_mean_v1',
    PRIVATE_ERROR,
  ])
    expect(json).not.toContain(privateValue)
}
async function expectDataError(h: Harness, status = 500, code = 'data_access_failed') {
  let observed: unknown
  try {
    await h.answer()
  } catch (error) {
    observed = error
  }
  expect(observed).toBeInstanceOf(MobileApiError)
  expect(observed).toMatchObject({ status, code })
  const error = observed as MobileApiError
  expect(error.details).toBeUndefined()
  expect(`${error.name}: ${error.message}`).not.toContain(PRIVATE_ERROR)
  expect(h.db.writes).toEqual([])
  expect(h.unexpectedRpcs).toEqual([])
}
const OLD_KEYS = [
  'badges_earned',
  'block_7700_enabled',
  'blocks_completed',
  'current_bf_percent',
  'current_protocol',
  'current_streak',
  'current_weight',
  'deficit_block',
  'last_active_date',
  'level',
  'longest_streak',
  'next_reevaluation',
  'updated_at',
  'xp_total',
]

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', '')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
})
afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('P-DEPOIS-1 actual GET /progress — confirmed signup photo BF origin', () => {
  it('returns profile24.00 as BF24 and marks its active confirmed photo origin through the real handler', async () => {
    const h = harness()
    const saved = h.db.progress(OWNER)
    expect(saved?.current_bf_percent).toBeNull()
    const { response, body } = await h.answer()
    expect(response.status).toBe(200)
    expect(body.meta).toEqual({ api_version: 'v1', request_id: `progress-photo-origin-${OWNER}` })
    expect(
      h.db.operations
        .filter((operation) => operation.kind === 'select')
        .map((operation) => operation.target),
    ).toEqual(['user_progress', 'user_profiles'])
    expect(body.data?.current_bf_percent).toBe(24)
    // CAUSAL RED: current handler preserves24 but has no origin field.
    expect(body.data).toHaveProperty('current_bf_origin', 'signup_photos')
    // New read is a GREEN oracle, never a preimplementation setup requirement.
    expectClosedReads(h)
    expect(Object.keys(body.data ?? {}).sort()).toEqual([...OLD_KEYS, 'current_bf_origin'].sort())
    expect(body.data).toMatchObject({
      xp_total: saved?.xp_total,
      level: saved?.level,
      current_streak: saved?.current_streak,
      longest_streak: saved?.longest_streak,
      blocks_completed: saved?.blocks_completed,
      deficit_block: saved?.deficit_block,
      current_weight: saved?.current_weight,
      badges_earned: saved?.badges_earned,
      last_active_date: saved?.last_active_date,
      next_reevaluation: saved?.next_reevaluation,
      updated_at: saved?.updated_at,
      current_protocol: 'recomposicao',
      block_7700_enabled: true,
    })
    expect(h.db.progress(OWNER)).toEqual(saved)
    expect(h.db.writes).toEqual([])
    expectNoPrivateProof(body)
    expect(
      h.selects
        .find((read) => read.table === 'user_profiles')
        ?.columns.split(',')
        .map((column) => column.trim())
        .sort(),
    ).toEqual([
      'body_fat_percent',
      'current_protocol',
      'onboarding_completed',
      'onboarding_completed_at',
      'user_id',
    ])
  })

  it.each([
    'absent',
    'declined',
    'invalidated same-number manual write',
  ] as const)('returns origin null for %s despite public triplet and BF24 equality', async (kind) => {
    const snapshot: Row = closedSnapshot()
    if (kind === 'absent') {
      snapshot.confirmation = null
      snapshot.generation_token = { ...closedSnapshot().generation_token, receipt_count: 0 }
    } else if (kind === 'declined')
      snapshot.confirmation = {
        decision: 'declined',
        method: null,
        source_ids: null,
        fingerprint: null,
        confirmed_body_fat_percent: null,
        decided_at: GENERATION,
        invalidated_at: null,
        active: false,
      }
    else
      snapshot.confirmation = {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
        active: false,
      }
    const h = harness({ snapshot })
    const { body } = await h.answer()
    expect(body.data).toMatchObject({ current_bf_percent: 24, current_bf_origin: null })
    expectClosedReads(h)
    expect(h.db.writes).toEqual([])
    expectNoPrivateProof(body)
  })

  it('keeps an invalidated historical receipt negative after the manual BF changes', async () => {
    const snapshot = {
      ...closedSnapshot(),
      confirmation: {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
        active: false,
      },
    }
    const h = harness({ profile: { body_fat_percent: '25.00' }, snapshot })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 25,
      current_bf_origin: null,
    })
    expectClosedReads(h)
  })

  it('retains valid historical origin with public hints changed and capture switch OFF', async () => {
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', '')
    const h = harness({ profile: { bf_percent_estimated: 29, bf_source: 'manual' } })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: 'signup_photos',
    })
    expectClosedReads(h)
  })

  it.each([
    18.25, 24,
  ])('keeps persisted progress BF%s authoritative without inheriting profile origin or reading the receipt', async (value) => {
    const h = harness({ progressBF: value, rpcThrow: true })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: value,
      current_bf_origin: null,
    })
    expectClosedReads(h, [])
    expect(h.db.writes).toEqual([])
  })

  it.each([
    null,
    'not-a-number',
  ])('does not read origin for an unavailable profile BF: %s', async (value) => {
    const h = harness({ profile: { body_fat_percent: value }, rpcThrow: true })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: null,
      current_bf_origin: null,
    })
    expectClosedReads(h, [])
  })

  it('preserves data:null without origin read when progress is missing', async () => {
    const h = harness({ noProgress: true, rpcThrow: true })
    expect((await h.answer()).body.data).toBeNull()
    expectClosedReads(h, [])
    expect(h.db.writes).toEqual([])
  })

  it('keeps missing profile and BF unavailable without origin read', async () => {
    const h = harness({ noProfile: true, rpcThrow: true })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: null,
      current_bf_origin: null,
    })
    expectClosedReads(h, [])
  })

  it('accepts an open current generation without confirmation despite older historical receipts', async () => {
    const snapshot = {
      ...closedSnapshot(),
      confirmation: null,
      generation_token: {
        onboarding_completed: false,
        onboarding_completed_at: null,
        receipt_count: 2,
      },
    }
    const h = harness({
      profile: { onboarding_completed: false, onboarding_completed_at: null },
      snapshot,
    })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: null,
    })
    expectClosedReads(h)
  })

  it('keeps a legitimate legacy completed profile without a completion instant or receipt unmarked', async () => {
    const snapshot = {
      ...closedSnapshot(),
      confirmation: null,
      generation_token: {
        onboarding_completed: true,
        onboarding_completed_at: null,
        receipt_count: 0,
      },
    }
    const h = harness({ profile: { onboarding_completed_at: null }, snapshot })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: null,
    })
    expectClosedReads(h)
  })

  it('does not reuse an origin across A to B to A requests with identical BF values', async () => {
    const h = harness()
    h.addAccount(OTHER)
    h.snapshots.set(OTHER, {
      ...closedSnapshot(OTHER),
      confirmation: null,
      generation_token: { ...closedSnapshot().generation_token, receipt_count: 0 },
    })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: 'signup_photos',
    })
    expect((await h.answer(OTHER)).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: null,
    })
    h.snapshots.set(OWNER, {
      ...closedSnapshot(),
      confirmation: {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
        active: false,
      },
    })
    expect((await h.answer()).body.data).toMatchObject({
      current_bf_percent: 24,
      current_bf_origin: null,
    })
    expectClosedReads(h, [OWNER, OTHER, OWNER])
    expect(h.db.writes).toEqual([])
  })

  it('keeps actual on-request close before progress and origin reads', async () => {
    vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-22')
    vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', 'xitugspwfxkcluxvrdeg')
    vi.spyOn(console, 'info').mockImplementation(() => undefined)
    const h = harness({ allowDayClose: true, profile: { body_fat_percent: 24 } })
    h.db.registerMeal({
      userId: OWNER,
      date: '2026-10-13',
      consumedAt: '2026-10-13T15:00:00.000Z',
      kcal: 1500,
      proteinG: 110,
      caloriesTarget: 1576,
      proteinTarget: 120,
    })
    const { response, body } = await h.answer()
    expect(response.status).toBe(200)
    expect(body.data).toMatchObject({ current_bf_percent: 24, current_bf_origin: 'signup_photos' })
    const closes = h.timeline
      .map((entry, index) => ({ entry, index }))
      .filter(({ entry }) => /^rpc:finalize_(?:mobile_)?daily_close_atomic$/.test(entry))
    expect(closes.length).toBeGreaterThan(0)
    const lastClose = Math.max(...closes.map(({ index }) => index))
    expect(h.timeline.lastIndexOf('select:user_progress')).toBeGreaterThan(lastClose)
    expect(h.timeline.indexOf(`rpc:${RPC}`)).toBeGreaterThan(lastClose)
    expectClosedReads(h)
  })
})

type InvalidCase = { label: string; mutate: (snapshot: Row) => void }
const invalidCases: InvalidCase[] = [
  {
    label: 'wrong snapshot owner',
    mutate: (s) => {
      s.user_id = OTHER
    },
  },
  {
    label: 'wrong version',
    mutate: (s) => {
      s.version = 2
    },
  },
  {
    label: 'missing profile in snapshot',
    mutate: (s) => {
      s.profile_present = false
    },
  },
  {
    label: 'stale generation',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        onboarding_completed_at: '2026-10-12T12:00:00.123456+00:00',
      }
    },
  },
  {
    label: 'different microsecond within the same millisecond',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        onboarding_completed_at: '2026-10-13T12:00:00.123457+00:00',
      }
    },
  },
  {
    label: 'incomplete generation differs from profile',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        onboarding_completed: false,
      }
    },
  },
  {
    label: 'active receipt with receipt_count zero',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        receipt_count: 0,
      }
    },
  },
  {
    label: 'unknown mean method',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        method: 'minimum_v0',
      }
    },
  },
  {
    label: 'uninvalidated value mismatch despite active=false',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        confirmed_body_fat_percent: 24.01,
        active: false,
      }
    },
  },
  {
    label: 'uninvalidated value mismatch with active=true',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        confirmed_body_fat_percent: 24.01,
      }
    },
  },
  {
    label: 'invalidation with active=true',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
      }
    },
  },
  {
    label: 'active=false contradicts all positive proof',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        active: false,
      }
    },
  },
]

describe('P-DEPOIS-1 actual progress handler — typed provenance failures', () => {
  it.each(invalidCases)('rejects $label without a null-origin success or private details', async ({
    mutate,
  }) => {
    const snapshot: Row = closedSnapshot()
    mutate(snapshot)
    const h = harness({ snapshot })
    await expectDataError(h)
    expectClosedReads(h)
  })

  it.each([
    { label: 'null payload', snapshot: null },
    { label: 'array payload', snapshot: [] },
    { label: 'empty payload', snapshot: {} },
    { label: 'RPC error', rpcError: { code: '08006', message: PRIVATE_ERROR } },
    {
      label: 'P0002 with a nonmatching message',
      rpcError: { code: 'P0002', message: PRIVATE_ERROR },
    },
    { label: 'RPC unavailable', rpcError: { code: '42883', message: PRIVATE_ERROR } },
    { label: 'RPC throws', rpcThrow: true },
  ])('rejects $label as data_access_failed', async (options) => {
    const h = harness(options)
    await expectDataError(h)
    expectClosedReads(h)
  })

  it('preserves the exact existing snapshot-loader missing-domain-owner 404', async () => {
    const h = harness({ rpcError: { code: 'P0002', message: 'onboarding_user_not_found' } })
    await expectDataError(h, 404, 'patient_not_found')
    expectClosedReads(h)
  })

  it('rejects a returned profile of another owner without querying that owner', async () => {
    const h = harness({ returnedProfileOwner: OTHER })
    await expectDataError(h)
    expect(h.originCalls.length).toBeLessThanOrEqual(1)
    for (const call of h.originCalls)
      expect(call.args).toEqual({ p_user_id: OWNER, p_include_open_photos: false })
  })
})
