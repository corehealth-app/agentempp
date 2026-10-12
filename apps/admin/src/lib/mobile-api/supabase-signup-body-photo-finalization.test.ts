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
      { method: 'eq', args: ['signup_origin', true] },
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
          { method: 'eq', args: ['signup_origin', true] },
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

function dispositionRpc(db: QueuedClient, receipts: Array<Receipt | (() => Promise<Receipt>)>) {
  const calls: Array<{ name: string; params: Record<string, unknown>; signal?: AbortSignal }> = []
  const rpc = (name: string, params: Record<string, unknown>) => {
    const call: (typeof calls)[number] = { name, params }
    calls.push(call)
    const pending = Promise.resolve().then(() => {
      const receipt = receipts.shift()
      if (!receipt) throw new Error('undeclared disposition receipt')
      return typeof receipt === 'function' ? receipt() : receipt
    })
    return Object.assign(pending, {
      abortSignal: (signal: AbortSignal) => {
        call.signal = signal
        return pending
      },
    })
  }
  ;(db.client as unknown as { rpc: typeof rpc }).rpc = rpc
  return calls
}
function readyDisposition(count = 1) {
  return {
    version: 1,
    user_id: ACCOUNT,
    kind: 'ready',
    current_profile_completed: true,
    generation: AT,
    policy: 'delete_all_signup_v1',
    estimate_state: 'unusable',
    sweep_no: 1,
    cursor: null,
    manifest_count: count,
    remaining_count: count,
  }
}
function emptyDisposition(completed = true): Receipt {
  return {
    data: { version: 1, user_id: ACCOUNT, kind: 'empty', current_profile_completed: completed },
    error: null,
  }
}
function dispositionPage(ids = [ASSET]): Receipt {
  return {
    data: {
      version: 1,
      user_id: ACCOUNT,
      generation: AT,
      sweep_no: 1,
      cursor: null,
      has_more: false,
      items: ids.map((id) => ({
        asset_id: id,
        bucket_id: BUCKET,
        object_path: `${ACCOUNT}/${id}.jpg`,
      })),
    },
    error: null,
  }
}
function dispositionAck(ids = [ASSET], newly = false): Receipt {
  return {
    data: {
      version: 1,
      user_id: ACCOUNT,
      generation: AT,
      sweep_no: 1,
      previous_cursor: null,
      cursor: ids.at(-1),
      sweep_complete: true,
      assets: ids.map((id) => ({
        asset_id: id,
        state: 'deleted',
        newly_deleted: newly,
        processing_result: null,
        deleted_at: AT,
        failure_stage: null,
        failure_code: null,
      })),
    },
    error: null,
  }
}

describe('B4a real default wrapper target guard', () => {
  it('runs an empty READ after completion in known staging even with the photo switch OFF', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [emptyDisposition()])
    expect(signupBodyPhotoFinalizationTargetAllowed()).toBe(true)
    await finalizeSignupBodyPhotosAfterOnboarding(context(db), input(), AT)
    expect(calls).toEqual([
      {
        name: 'prepare_mobile_signup_body_photo_disposition',
        params: { p_user_id: ACCOUNT, p_generation: AT, p_swept_generations: [] },
        signal: expect.any(AbortSignal),
      },
    ])
    expect(db.queries).toEqual([])
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
      finalizeSignupBodyPhotosAfterOnboarding(context(db), input(), AT),
    ).resolves.toBeUndefined()
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })
})

describe('D4 repair uses one total budget and trusted disposition receipts', () => {
  it('R1 preparation validates at the deadline: no page or Storage may start', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(0)
    const db = new QueuedClient()
    const receipt = readyDisposition()
    Object.defineProperty(receipt, 'current_profile_completed', {
      enumerable: true,
      get: () => {
        clock.mockReturnValue(3000)
        return true
      },
    })
    const calls = dispositionRpc(db, [{ data: receipt, error: null }])
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(1)
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('R2 missing preparation receipt is unknown and cannot authorize deleteAll', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [{ data: null, error: null }])
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(1)
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('R3 other hosted ref explicitly ON: GET/DELETE do not query or claim even consent', async () => {
    const ref = 'abcdefghijklmnopqrst'
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${ref}.supabase.co`)
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', ref)
    const db = new QueuedClient()
    const response = await handleSignupBodyPhotosGet(context(db)).catch(() => null)
    expect(response?.status).toBe(200)
    expect((await response?.json())?.data).toMatchObject({
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

  it('R4 known open profile with no historical scope permits the established B2 path', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [emptyDisposition(false)])
    expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({
      completed: false,
      newlyDeleted: 0,
    })
    expect(calls).toEqual([
      {
        name: 'prepare_mobile_signup_body_photo_disposition',
        params: { p_user_id: ACCOUNT, p_generation: null, p_swept_generations: [] },
        signal: expect.any(AbortSignal),
      },
    ])
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
  })

  it.each([
    'true/time',
    'true/no-time',
    'false/time',
  ])('R5 empty completed %s receives no mutation authorization', async () => {
    // Completion shape is evaluated by the SQL RPC. This fake declares its boolean only.
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [emptyDisposition()])
    expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({
      completed: true,
      newlyDeleted: 0,
    })
    expect(calls).toHaveLength(1)
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it.each([
    'processed',
    'pending_upload',
    'failed',
  ])('R6 unsealed legacy %s stays unknown instead of authorizing deletion', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [
      { data: null, error: { code: '55000', message: 'body_photo_disposition_scope_unknown' } },
    ])
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(1)
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('R7 tombstones resweep late bytes once, without counting a new deletion or writing BF3', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [
      { data: readyDisposition(), error: null },
      dispositionPage(),
      dispositionAck(),
      emptyDisposition(),
    ])
    expect(await repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).toEqual({
      completed: true,
      newlyDeleted: 0,
    })
    expect(db.storageCalls).toEqual([
      { method: 'from', args: [BUCKET] },
      { method: 'remove', args: [[`${ACCOUNT}/${ASSET}.jpg`]] },
    ])
    expect(calls.map((call) => call.name)).toEqual([
      'prepare_mobile_signup_body_photo_disposition',
      'get_mobile_signup_body_photo_disposition_page',
      'commit_mobile_signup_body_photo_disposition_page',
      'prepare_mobile_signup_body_photo_disposition',
    ])
    expect(calls.at(-1)?.params.p_swept_generations).toEqual([AT])
    expect(db.queries).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('R8 unsealed mixed tombstones/live remains pending without deleteAll', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [
      { data: null, error: { code: '55000', message: 'body_photo_disposition_scope_unknown' } },
    ])
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(1)
    expect(db.storageCalls).toEqual([])
    expect(db.queries).toEqual([])
    expect(db.forbidden).toEqual([])
  })

  it('R9 failed tombstone remove starts no ACK or new preparation and hides private errors', async () => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [{ data: readyDisposition(), error: null }, dispositionPage()])
    db.storageResult = { data: null, error: { message: 'SYNTHETIC PRIVATE FAILURE' } }
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(2)
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
    { data: { ...readyDisposition(), current_profile_completed: 'unknown' }, error: null },
  ])('R10 invalid preparation never authorizes a page or Storage: %j', async (receipt) => {
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [receipt])
    await expect(repairCompletedSignupBodyPhotos(db.client, ACCOUNT)).rejects.toMatchObject({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(calls).toHaveLength(1)
    expect(db.queries).toEqual([])
    expect(db.storageCalls).toEqual([])
  })

  it('R11 prepare1500 + page1600 share3000: late page never removes tombstone bytes', async () => {
    vi.useFakeTimers({ toFake: ['Date', 'setTimeout', 'clearTimeout'] })
    vi.setSystemTime(0)
    vi.spyOn(performance, 'now').mockImplementation(() => Date.now())
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    const db = new QueuedClient()
    const calls = dispositionRpc(db, [
      () =>
        new Promise((resolve) =>
          setTimeout(() => resolve({ data: readyDisposition(), error: null }), 1500),
        ),
      () => new Promise((resolve) => setTimeout(() => resolve(dispositionPage()), 1600)),
    ])
    const assertion = expect(
      repairCompletedSignupBodyPhotos(db.client, ACCOUNT),
    ).rejects.toMatchObject({ status: 503, code: 'body_photo_cleanup_pending' })
    await vi.advanceTimersByTimeAsync(3000)
    await assertion
    expect(calls).toHaveLength(2)
    expect(db.storageCalls).toEqual([])
    await vi.advanceTimersByTimeAsync(100)
    expect(db.storageCalls).toEqual([])
    expect(warn).toHaveBeenCalledOnce()
    expect(vi.getTimerCount()).toBe(0)
  })
})

// D4 characterization against the existing real post-completion entrypoint.
// Future SQL replies are declared here; this fake proves orchestration only.
describe('D4 disposes the sealed signup scope independently of photo confirmation', () => {
  it.each([
    ['one incomplete upload, without a usable estimate', false, 1],
    ['an explicitly declined18/24/30 mean, already saved atomically in BF3', true, 3],
  ] as const)('%s', async (_label, declined, count) => {
    vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    const ids = [ASSET, SECOND, '00000000-0000-4000-8000-000000000343'].slice(0, count)
    const poses = ['front', 'side', 'back'] as const
    const db = new QueuedClient().next({
      data: ids.map((id, i) =>
        row({
          id,
          object_path: `${ACCOUNT}/${id}.jpg`,
          status: declined ? 'processed' : 'pending_upload',
          context_text: SIGNUP_BODY_PHOTO_POSE_CONTEXT[poses[i]],
          uploaded_at: declined ? AT : null,
          processing_result: declined
            ? { type: 'body', bf_percent_estimate: [18, 24, 30][i] }
            : null,
        }),
      ),
      error: null,
    })
    const rpcCalls: string[] = []
    const rpc = vi.fn((name: string) => {
      rpcCalls.push(name)
      let data: unknown
      if (name === 'prepare_mobile_signup_body_photo_disposition')
        data = {
          version: 1,
          kind: 'ready',
          user_id: ACCOUNT,
          generation: AT,
          current_profile_completed: true,
          policy: 'delete_all_signup_v1',
          estimate_state: declined ? 'saved' : 'unusable',
          sweep_no: 1,
          cursor: null,
          manifest_count: count,
          remaining_count: count,
        }
      else if (name === 'get_mobile_signup_body_photo_disposition_page')
        data = {
          version: 1,
          user_id: ACCOUNT,
          generation: AT,
          sweep_no: 1,
          cursor: null,
          items: ids.map((id) => ({
            asset_id: id,
            bucket_id: BUCKET,
            object_path: `${ACCOUNT}/${id}.jpg`,
          })),
          has_more: false,
        }
      else if (name === 'commit_mobile_signup_body_photo_disposition_page')
        data = {
          version: 1,
          user_id: ACCOUNT,
          generation: AT,
          sweep_no: 1,
          previous_cursor: null,
          cursor: ids.at(-1),
          sweep_complete: true,
          assets: ids.map((id) => ({
            asset_id: id,
            state: 'deleted',
            newly_deleted: true,
            deleted_at: AT,
            processing_result: null,
            failure_stage: null,
            failure_code: null,
          })),
        }
      else throw new Error('unexpected disposition RPC')
      const result = Promise.resolve({ data, error: null })
      return Object.assign(result, {
        abortSignal: (signal: AbortSignal) => {
          if (signal.aborted) throw new Error('disposition stopped')
          return result
        },
      })
    })
    const caller = { ...context(db), supabase: { ...db.client, rpc } as unknown as ServiceClient }
    const submission = declined
      ? { ...input(), body_photo_confirmation: { decision: 'decline' as const } }
      : input()
    await finalizeSignupBodyPhotosAfterOnboarding(caller, submission, AT)
    expect(db.storageCalls).toEqual([
      { method: 'from', args: [BUCKET] },
      { method: 'remove', args: [ids.map((id) => `${ACCOUNT}/${id}.jpg`)] },
    ])
    expect(rpcCalls).toEqual([
      'prepare_mobile_signup_body_photo_disposition',
      'get_mobile_signup_body_photo_disposition_page',
      'commit_mobile_signup_body_photo_disposition_page',
    ])
    expect(db.queries).toEqual([]) // No direct BF3 write outside the atomic SQL receipt.
    expect(db.forbidden).toEqual([])
  })
})
