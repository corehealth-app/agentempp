/**
 * Regression tests of the real adapter with declared synthetic database receipts.
 * Real adapter/core imports, synthetic queued database receipts, no network.
 * Current module exports already exist. No clinical rule or aggregation is supplied.
 */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  handleSignupBodyPhotosDelete,
  handleSignupBodyPhotosGet,
} from '@/app/api/mobile/v1/onboarding/body-photos/handler'
import { type OnboardingCompletionInput, onboardingCompletionInputSchema } from './contracts'
import type { MobileRouteContext } from './route'
import { finalizeSignupBodyPhotos } from './signup-body-photo-finalization'
import { SIGNUP_BODY_PHOTO_POSE_CONTEXT } from './signup-body-photo-service'
import {
  createSupabaseSignupBodyPhotoFinalizationDependencies,
  finalizeSignupBodyPhotosAfterOnboarding,
  repairCompletedSignupBodyPhotos,
  signupBodyPhotoFinalizationTargetAllowed,
} from './supabase-signup-body-photo-finalization'

const ACCOUNT = '00000000-0000-4000-8000-000000000321'
const OTHER = '00000000-0000-4000-8000-000000000331'
const ASSET = '00000000-0000-4000-8000-000000000341'
const SECOND = '00000000-0000-4000-8000-000000000342'
const STAGING = 'xitugspwfxkcluxvrdeg'
const LEGACY = 'xuxehkhdvjivitduarvb'
const BUCKET = 'body-checkin-photos'
const AT = '2026-10-11T14:30:00.000Z'
const PHOTO_COLUMNS =
  'id, bucket_id, object_path, status, failure_stage, context_text, created_at, uploaded_at, processing_result'
const PROVENANCE_COLUMNS = 'user_id, bf_percent_estimated, bf_source, bf_estimated_at'
const DELETION_COLUMNS = 'id, user_id, status, deleted_at, processing_result'

type Receipt = { data: unknown; error: unknown }
type Step = { method: string; args: unknown[] }
type QueryCall = { table: string; steps: Step[]; executionCount: number }

/** Records attempts at call time, including calls whose eventual failure is caught. */
class QueuedClient {
  readonly queries: QueryCall[] = []
  readonly storageCalls: Array<{ method: string; args: unknown[] }> = []
  readonly forbidden: Array<{ method: string; args: unknown[] }> = []
  readonly results: Array<Receipt | (() => Promise<Receipt>)> = []
  storageResult: Receipt = { data: [], error: null }

  readonly client = {
    from: (table: string) => {
      const call: QueryCall = { table, steps: [], executionCount: 0 }
      this.queries.push(call)
      return new RecordingQuery(this, call)
    },
    rpc: (...args: unknown[]) => {
      this.forbidden.push({ method: 'rpc', args })
      throw new Error('unexpected RPC in finalization adapter')
    },
    storage: {
      from: (...args: unknown[]) => {
        this.storageCalls.push({ method: 'from', args })
        return {
          remove: async (...removeArgs: unknown[]) => {
            this.storageCalls.push({ method: 'remove', args: removeArgs })
            return this.storageResult
          },
        }
      },
    },
  } as unknown as ServiceClient

  next(result: Receipt | (() => Promise<Receipt>)): this {
    this.results.push(result)
    return this
  }

  execute(call: QueryCall): Receipt | Promise<Receipt> {
    call.executionCount += 1
    const result = this.results.shift()
    if (!result) throw new Error(`no declared result for ${call.table}`)
    return typeof result === 'function' ? result() : result
  }
}

class RecordingQuery implements PromiseLike<Receipt> {
  constructor(
    private readonly db: QueuedClient,
    private readonly call: QueryCall,
  ) {}

  private step(method: string, args: unknown[]): this {
    this.call.steps.push({ method, args })
    return this
  }

  select(...args: unknown[]): this {
    return this.step('select', args)
  }
  update(...args: unknown[]): this {
    return this.step('update', args)
  }
  eq(...args: unknown[]): this {
    return this.step('eq', args)
  }
  neq(...args: unknown[]): this {
    return this.step('neq', args)
  }
  in(...args: unknown[]): this {
    return this.step('in', args)
  }
  order(...args: unknown[]): this {
    return this.step('order', args)
  }
  limit(...args: unknown[]): this {
    return this.step('limit', args)
  }
  abortSignal(...args: unknown[]): this {
    return this.step('abortSignal', args)
  }
  async maybeSingle(): Promise<Receipt> {
    this.step('maybeSingle', [])
    return this.db.execute(this.call)
  }

  insert(...args: unknown[]): never {
    this.db.forbidden.push({ method: 'insert', args })
    throw new Error('unexpected insert in finalization adapter')
  }

  delete(...args: unknown[]): never {
    this.db.forbidden.push({ method: 'delete', args })
    throw new Error('unexpected hard delete in finalization adapter')
  }

  // biome-ignore lint/suspicious/noThenProperty: the actual database builder is awaited
  then<TResult1 = Receipt, TResult2 = never>(
    onfulfilled?: ((value: Receipt) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve()
      .then(() => this.db.execute(this.call))
      .then(onfulfilled, onrejected)
  }
}

function row(overrides: Record<string, unknown> = {}) {
  return {
    id: ASSET,
    bucket_id: BUCKET,
    object_path: `${ACCOUNT}/${ASSET}.jpg`,
    status: 'processed',
    failure_stage: null,
    context_text: SIGNUP_BODY_PHOTO_POSE_CONTEXT.front,
    created_at: AT,
    uploaded_at: AT,
    processing_result: { type: 'body', bf_percent_estimate: 21, notes: 'SYNTHETIC FREE TEXT' },
    ...overrides,
  }
}

function input(sex: 'masculino' | 'feminino' = 'feminino'): OnboardingCompletionInput {
  return onboardingCompletionInputSchema.parse({
    name: 'Synthetic adapter user',
    locale: 'pt-BR',
    country: 'BR',
    timezone: 'America/Sao_Paulo',
    sex,
    birth_date: '1990-01-01',
    height_cm: 165,
    weight_kg: 62,
    objective: 'manutencao',
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms_of_service',
        version: 'test-2026.1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  })
}

function context(db: QueuedClient): MobileRouteContext {
  return {
    request: new Request('https://adapter.test/api/mobile/v1/onboarding', { method: 'POST' }),
    requestId: 'request-adapter-20261011',
    supabase: db.client,
    auth: {
      accessToken: 'synthetic-adapter-token',
      authUserId: OTHER,
      userId: ACCOUNT,
      identity: { id: OTHER, email: 'synthetic@example.invalid', emailConfirmedAt: AT },
      patient: {
        id: ACCOUNT,
        authUserId: OTHER,
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function expectedRead(signal: AbortSignal): QueryCall {
  return {
    table: 'media_assets',
    executionCount: 1,
    steps: [
      { method: 'select', args: [PHOTO_COLUMNS] },
      { method: 'eq', args: ['user_id', ACCOUNT] },
      { method: 'eq', args: ['kind', 'body_checkin_photo'] },
      { method: 'neq', args: ['status', 'deleted'] },
      { method: 'order', args: ['created_at', { ascending: false }] },
      { method: 'limit', args: [1000] },
      { method: 'abortSignal', args: [signal] },
    ],
  }
}

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING}.supabase.co`)
  vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', '')
})

afterEach(() => {
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('B4a real Supabase finalization adapter', () => {
  it('constructs lazily and provides an explicit deferred resolver', async () => {
    const db = new QueuedClient()
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
    const signal = new AbortController().signal
    expect(
      await dependencies.resolveCandidate({ userId: ACCOUNT, photos: [] }, 'feminino', signal),
    ).toEqual({ kind: 'deferred_rule' })
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
  })

  it('reads exactly one owner-filtered page of nine columns, with the supplied signal', async () => {
    const db = new QueuedClient().next({ data: [], error: null })
    const signal = new AbortController().signal
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(await dependencies.repository.loadSnapshot(ACCOUNT, signal)).toEqual([])
    expect(db.queries).toEqual([expectedRead(signal)])
    expect(db.results).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('maps only exact signup context sentences and reduces processing fields before the resolver', async () => {
    const db = new QueuedClient().next({
      data: [
        row(),
        row({
          id: SECOND,
          object_path: `${ACCOUNT}/${SECOND}.jpg`,
          context_text: SIGNUP_BODY_PHOTO_POSE_CONTEXT.side,
        }),
        row({ id: '00000000-0000-4000-8000-000000000343', context_text: 'Foto de frente. ' }),
        row({ id: '00000000-0000-4000-8000-000000000344', context_text: null }),
      ],
      error: null,
    })
    const signal = new AbortController().signal
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(await dependencies.repository.loadSnapshot(ACCOUNT, signal)).toEqual([
      {
        id: ASSET,
        userId: ACCOUNT,
        bucketId: BUCKET,
        objectPath: `${ACCOUNT}/${ASSET}.jpg`,
        pose: 'front',
        status: 'processed',
        failureStage: null,
        createdAt: AT,
        uploadedAt: AT,
        bodyFatPercent: 21,
      },
      {
        id: SECOND,
        userId: ACCOUNT,
        bucketId: BUCKET,
        objectPath: `${ACCOUNT}/${SECOND}.jpg`,
        pose: 'side',
        status: 'processed',
        failureStage: null,
        createdAt: AT,
        uploadedAt: AT,
        bodyFatPercent: 21,
      },
    ])
    expect(db.queries).toEqual([expectedRead(signal)])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it.each([
    ['wrong reading type', { type: 'meal', bf_percent_estimate: 21 }],
    ['string number', { type: 'body', bf_percent_estimate: '21' }],
    ['NaN', { type: 'body', bf_percent_estimate: Number.NaN }],
    ['infinity', { type: 'body', bf_percent_estimate: Number.POSITIVE_INFINITY }],
    ['missing estimate', { type: 'body', notes: 'SYNTHETIC' }],
    ['null result', null],
  ])('does not coerce a %s into body fat', async (_name, result) => {
    const db = new QueuedClient().next({ data: [row({ processing_result: result })], error: null })
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    const photos = await dependencies.repository.loadSnapshot(ACCOUNT, new AbortController().signal)
    expect(photos).toHaveLength(1)
    expect(photos[0]?.bodyFatPercent).toBeNull()
    expect(Object.keys(photos[0] ?? {}).sort()).toEqual(
      [
        'bodyFatPercent',
        'bucketId',
        'createdAt',
        'failureStage',
        'id',
        'objectPath',
        'pose',
        'status',
        'uploadedAt',
        'userId',
      ].sort(),
    )
    expect(db.storageCalls).toEqual([])
  })

  it.each([
    ['query error', { data: null, error: { message: 'SYNTHETIC DB ERROR' } }],
    ['null data', { data: null, error: null }],
    ['object data', { data: {}, error: null }],
    ['invalid bucket', { data: [row({ bucket_id: 'meal-photos' })], error: null }],
    ['invalid id', { data: [row({ id: 'bad-id' })], error: null }],
    ['invalid date', { data: [row({ created_at: 'bad-date' })], error: null }],
  ])('fails a %s without writing or deleting', async (_name, receipt) => {
    const db = new QueuedClient().next(receipt)
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    await expect(
      dependencies.repository.loadSnapshot(ACCOUNT, new AbortController().signal),
    ).rejects.toThrow()
    expect(db.queries).toHaveLength(1)
    expect(db.queries[0]?.steps.some((step) => step.method === 'update')).toBe(false)
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('updates only the three provenance columns of the owner and returns the raw four-column receipt', async () => {
    const patch = {
      bf_percent_estimated: 21,
      bf_source: 'signup_photos' as const,
      bf_estimated_at: AT,
    }
    const receipt = { data: [{ user_id: ACCOUNT, ...patch }], error: null }
    const db = new QueuedClient().next(receipt)
    const signal = new AbortController().signal
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(await dependencies.repository.persistProvenance(ACCOUNT, patch, signal)).toBe(receipt)
    expect(db.queries).toEqual([
      {
        table: 'user_profiles',
        executionCount: 1,
        steps: [
          { method: 'update', args: [patch] },
          { method: 'eq', args: ['user_id', ACCOUNT] },
          { method: 'select', args: [PROVENANCE_COLUMNS] },
          { method: 'abortSignal', args: [signal] },
        ],
      },
    ])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it.each([
    ['zero rows', { data: [], error: null }],
    ['null rows', { data: null, error: null }],
    [
      'foreign owner',
      {
        data: [
          {
            user_id: OTHER,
            bf_percent_estimated: 21,
            bf_source: 'signup_photos',
            bf_estimated_at: AT,
          },
        ],
        error: null,
      },
    ],
    [
      'wrong value',
      {
        data: [
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 22,
            bf_source: 'signup_photos',
            bf_estimated_at: AT,
          },
        ],
        error: null,
      },
    ],
    ['database error', { data: null, error: { code: 'SYNTHETIC' } }],
  ])('preserves an invalid %s receipt for the helper to reject before Storage', async (_name, receipt) => {
    const db = new QueuedClient().next(receipt)
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(
      await dependencies.repository.persistProvenance(
        ACCOUNT,
        {
          bf_percent_estimated: 21,
          bf_source: 'signup_photos',
          bf_estimated_at: AT,
        },
        new AbortController().signal,
      ),
    ).toBe(receipt)
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('marks only the owner and explicit asset ids, returning the five receipt columns', async () => {
    const receipt = {
      data: [
        { id: ASSET, user_id: ACCOUNT, status: 'deleted', deleted_at: AT, processing_result: null },
        {
          id: SECOND,
          user_id: ACCOUNT,
          status: 'deleted',
          deleted_at: AT,
          processing_result: null,
        },
      ],
      error: null,
    }
    const db = new QueuedClient().next(receipt)
    const ids = Object.freeze([ASSET, SECOND])
    const signal = new AbortController().signal
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(await dependencies.repository.markDeleted(ACCOUNT, ids, AT, signal)).toBe(receipt)
    expect(ids).toEqual([ASSET, SECOND])
    expect(db.queries).toEqual([
      {
        table: 'media_assets',
        executionCount: 1,
        steps: [
          {
            method: 'update',
            args: [
              {
                status: 'deleted',
                deleted_at: AT,
                failure_stage: null,
                failure_code: null,
                processing_result: null,
              },
            ],
          },
          { method: 'eq', args: ['user_id', ACCOUNT] },
          { method: 'eq', args: ['kind', 'body_checkin_photo'] },
          { method: 'in', args: ['id', [ASSET, SECOND]] },
          { method: 'neq', args: ['status', 'deleted'] },
          { method: 'select', args: [DELETION_COLUMNS] },
          { method: 'abortSignal', args: [signal] },
        ],
      },
    ])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('does not convert a partial deletion receipt into a count or pretend it is complete', async () => {
    const receipt = {
      data: [
        { id: ASSET, user_id: ACCOUNT, status: 'deleted', deleted_at: AT, processing_result: null },
      ],
      error: null,
    }
    const db = new QueuedClient().next(receipt)
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(
      await dependencies.repository.markDeleted(
        ACCOUNT,
        [ASSET, SECOND],
        AT,
        new AbortController().signal,
      ),
    ).toBe(receipt)
    expect(db.storageCalls).toEqual([])
  })

  it('uses bucket plus paths at the adapter boundary and only paths at SDK remove; no signal is invented', async () => {
    const db = new QueuedClient()
    const paths = Object.freeze([`${ACCOUNT}/${ASSET}.jpg`, `${ACCOUNT}/${SECOND}.jpg`])
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    await dependencies.storage.remove(BUCKET, paths)
    expect(db.storageCalls).toEqual([
      { method: 'from', args: [BUCKET] },
      { method: 'remove', args: [[...paths]] },
    ])
    expect(paths).toEqual([`${ACCOUNT}/${ASSET}.jpg`, `${ACCOUNT}/${SECOND}.jpg`])
    expect(db.queries).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('propagates a Storage failure and performs no catalogue mark', async () => {
    const db = new QueuedClient()
    db.storageResult = { data: null, error: { message: 'SYNTHETIC STORAGE ERROR' } }
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    await expect(dependencies.storage.remove(BUCKET, [`${ACCOUNT}/${ASSET}.jpg`])).rejects.toThrow()
    expect(db.storageCalls).toEqual([
      { method: 'from', args: [BUCKET] },
      { method: 'remove', args: [[`${ACCOUNT}/${ASSET}.jpg`]] },
    ])
    expect(db.queries).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('keeps a real nonempty snapshot deferred, without provenance, mark or Storage', async () => {
    const db = new QueuedClient().next({ data: [row()], error: null })
    const dependencies = createSupabaseSignupBodyPhotoFinalizationDependencies(db.client)
    expect(
      await finalizeSignupBodyPhotos({ userId: ACCOUNT, sex: 'feminino' }, dependencies),
    ).toEqual({ state: 'deferred_rule' })
    expect(db.queries).toHaveLength(1)
    expect(db.queries[0]?.table).toBe('media_assets')
    expect(db.queries[0]?.steps.some((step) => step.method === 'update')).toBe(false)
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })
})

describe('B4a real default wrapper target guard', () => {
  it('runs an empty READ after completion in known staging even with the photo switch OFF', async () => {
    const db = new QueuedClient().next({ data: [], error: null })
    expect(signupBodyPhotoFinalizationTargetAllowed()).toBe(true)
    await finalizeSignupBodyPhotosAfterOnboarding(context(db), input())
    expect(db.queries).toHaveLength(1)
    const signal = db.queries[0]?.steps.find((step) => step.method === 'abortSignal')?.args[0]
    expect(signal).toBeInstanceOf(AbortSignal)
    expect(db.queries).toEqual([expectedRead(signal as AbortSignal)])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it.each([
    ['legacy with switch OFF', `https://${LEGACY}.supabase.co`, ''],
    ['legacy explicitly listed', `https://${LEGACY}.supabase.co`, LEGACY],
    ['other hosted ref listed', 'https://abcdefghijklmnopqrst.supabase.co', 'abcdefghijklmnopqrst'],
    ['missing URL', undefined, STAGING],
    ['invalid URL', 'not-a-url', STAGING],
    ['non-hosted URL', 'https://database.example.invalid', STAGING],
    ['http staging', `http://${STAGING}.supabase.co`, STAGING],
    ['lookalike hostname', `https://${STAGING}.supabase.co.example.invalid`, STAGING],
  ])('blocks %s before any adapter call', async (_name, url, listed) => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', url)
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', listed)
    const db = new QueuedClient()
    expect(signupBodyPhotoFinalizationTargetAllowed()).toBe(false)
    await expect(
      finalizeSignupBodyPhotosAfterOnboarding(context(db), input()),
    ).resolves.toBeUndefined()
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })
})

describe('B4a repair uses one budget for profile and media', () => {
  it('R1 profile resolves at the deadline before timer delivery: no media query may start', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(0)
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    const db = new QueuedClient()
      .next({
        data: {
          onboarding_completed: true,
          onboarding_completed_at: AT,
          get sex() {
            clock.mockReturnValue(3000)
            return 'feminino'
          },
        },
        error: null,
      })
      .next({ data: [], error: null })
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(db.queries.map((call) => call.table)).toEqual(['user_profiles'])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
    expect(warn.mock.calls).toEqual([
      [
        '[mobile-signup-body-photos] finalization_incomplete',
        { state: 'source_unknown', phase: 'read', reason: 'timeout' },
      ],
    ])
  })
})

it('R2 missing profile receipt is unknown: repair cannot authorize the old deleteAll', async () => {
  const db = new QueuedClient().next({ data: null, error: null })
  await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  expect(db.queries.map((call) => call.table)).toEqual(['user_profiles'])
  expect(db.storageCalls).toEqual([])
  expect(db.forbidden).toEqual([])
})

it('R3 other hosted ref explicitly ON: GET/DELETE do not query or claim even consent', async () => {
  const ref = 'abcdefghijklmnopqrst'
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${ref}.supabase.co`)
  vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', ref)
  const db = new QueuedClient()
  const response = await handleSignupBodyPhotosGet(context(db)).catch(() => null)
  expect(db.forbidden).toEqual([])
  expect(db.queries).toEqual([])
  expect(db.storageCalls).toEqual([])
  expect(response?.status).toBe(200)
  const json = await response?.json()
  expect(json?.data).toMatchObject({
    available: false,
    unavailable_reason: 'disabled',
  })
  await expect(handleSignupBodyPhotosDelete(context(db))).rejects.toMatchObject({
    status: 404,
    code: 'body_photos_unavailable',
  })
  expect(db.forbidden).toEqual([])
  expect(db.queries).toEqual([])
  expect(db.storageCalls).toEqual([])
})

function profile(completed = true) {
  return {
    onboarding_completed: completed,
    onboarding_completed_at: completed ? AT : null,
    sex: 'feminino',
  }
}

function repairRead(signal: AbortSignal): QueryCall {
  const expected = expectedRead(signal)
  expected.steps = expected.steps.filter((step) => step.method !== 'neq')
  expected.steps = expected.steps.map((step) =>
    step.method === 'order'
      ? { method: 'order', args: ['deleted_at', { ascending: false, nullsFirst: true }] }
      : step,
  )
  return expected
}

it('R4 known open profile does not read photos in repair and still permits the established B2 path', async () => {
  const db = new QueuedClient().next({ data: profile(false), error: null })
  expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({ completed: false })
  expect(db.queries.map((call) => call.table)).toEqual(['user_profiles'])
  expect(db.queries[0].steps).toEqual([
    { method: 'select', args: ['onboarding_completed, onboarding_completed_at, sex'] },
    { method: 'eq', args: ['user_id', ACCOUNT] },
    { method: 'abortSignal', args: [expect.any(AbortSignal)] },
    { method: 'maybeSingle', args: [] },
  ])
  expect(db.storageCalls).toEqual([])
})

it.each([
  profile(),
  { ...profile(), onboarding_completed_at: null },
  { ...profile(), onboarding_completed: false },
])('R5 each existing completion shape with no catalogue rows returns completed without mutations', async (value) => {
  const db = new QueuedClient().next({ data: value, error: null }).next({ data: [], error: null })
  expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({ completed: true })
  const signal = db.queries[0].steps.find((step) => step.method === 'abortSignal')
    ?.args[0] as AbortSignal
  expect(db.queries[1]).toEqual(repairRead(signal))
  expect(db.storageCalls).toEqual([])
  expect(db.forbidden).toEqual([])
})

it.each([
  'processed',
  'pending_upload',
  'failed',
] as const)('R6 live %s photo remains pending without a clinical/disposition callback', async (status) => {
  const db = new QueuedClient().next({ data: { ...profile(), sex: null }, error: null }).next({
    data: [row({ status, failure_stage: status === 'failed' ? 'upload' : null })],
    error: null,
  })
  await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  expect(db.queries.map((call) => call.table)).toEqual(['user_profiles', 'media_assets'])
  expect(db.queries.every((call) => !call.steps.some((step) => step.method === 'update'))).toBe(
    true,
  )
  expect(db.storageCalls).toEqual([])
  expect(db.forbidden).toEqual([])
})

it('R7 only already-deleted tombstones: remove late bytes once inside the budget, no provenance/mark/resolver', async () => {
  const db = new QueuedClient()
    .next({ data: profile(), error: null })
    .next({ data: [row({ status: 'deleted', processing_result: null })], error: null })
  expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({ completed: true })
  const signal = db.queries[0].steps.find((step) => step.method === 'abortSignal')
    ?.args[0] as AbortSignal
  expect(db.queries[1]).toEqual(repairRead(signal))
  expect(db.storageCalls).toEqual([
    { method: 'from', args: [BUCKET] },
    { method: 'remove', args: [[`${ACCOUNT}/${ASSET}.jpg`]] },
  ])
  expect(db.queries).toHaveLength(2)
  expect(db.forbidden).toEqual([])
})

it('R8 tombstones mixed with a live photo: deferred outcome never falls through to deleteAll', async () => {
  const db = new QueuedClient().next({ data: profile(), error: null }).next({
    data: [
      row({ status: 'deleted', processing_result: null }),
      row({ id: SECOND, object_path: `${ACCOUNT}/${SECOND}.jpg` }),
    ],
    error: null,
  })
  await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  expect(db.storageCalls).toEqual([])
  expect(db.queries).toHaveLength(2)
  expect(db.forbidden).toEqual([])
})

it('R9 failed removal of tombstone bytes is pending and starts no fresh mark/query', async () => {
  const db = new QueuedClient()
    .next({ data: profile(), error: null })
    .next({ data: [row({ status: 'deleted', processing_result: null })], error: null })
  db.storageResult = { data: null, error: { message: 'SYNTHETIC PRIVATE FAILURE' } }
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
  await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  expect(db.queries).toHaveLength(2)
  expect(warn.mock.calls).toEqual([
    [
      '[mobile-signup-body-photos] finalization_incomplete',
      { state: 'cleanup_unknown', phase: 'remove', reason: 'error' },
    ],
  ])
  expect(db.forbidden).toEqual([])
})

it.each([
  { data: null, error: { message: 'SYNTHETIC PRIVATE ERROR' } },
  { data: {}, error: null },
  { data: { ...profile(), sex: 'unknown' }, error: null },
])('R10 invalid profile never authorizes cleanup or a media read: %j', async (receipt) => {
  const db = new QueuedClient().next(receipt)
  vi.spyOn(console, 'warn').mockImplementation(() => undefined)
  await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  expect(db.queries.map((call) => call.table)).toEqual(['user_profiles'])
  expect(db.storageCalls).toEqual([])
})

it('R11 profile1500 + photo read1600 share 3000 total: late tombstone snapshot never removes bytes', async () => {
  vi.useFakeTimers({ toFake: ['Date', 'setTimeout', 'clearTimeout'] })
  vi.setSystemTime(0)
  vi.spyOn(performance, 'now').mockImplementation(() => Date.now())
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
  const db = new QueuedClient()
    .next(
      () =>
        new Promise((resolve) => setTimeout(() => resolve({ data: profile(), error: null }), 1500)),
    )
    .next(
      () =>
        new Promise((resolve) =>
          setTimeout(
            () =>
              resolve({ data: [row({ status: 'deleted', processing_result: null })], error: null }),
            1600,
          ),
        ),
    )
  const work = repairCompletedSignupBodyPhotos(db.client, ACCOUNT)
  const assertion = expect(work).rejects.toMatchObject({
    status: 503,
    code: 'body_photo_cleanup_pending',
  })
  await vi.advanceTimersByTimeAsync(3000)
  await assertion
  expect(db.queries).toHaveLength(2)
  expect(db.storageCalls).toEqual([])
  await vi.advanceTimersByTimeAsync(100)
  expect(db.storageCalls).toEqual([])
  expect(warn).toHaveBeenCalledOnce()
  expect(vi.getTimerCount()).toBe(0)
})
