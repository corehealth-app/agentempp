import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import {
  executeIdempotent,
  type IdempotencyClaim,
  type MobileIdempotencyStore,
} from './idempotency'
import {
  handleRegistrationConfirm,
  handleRegistrationDelete,
  handleRegistrationGet,
  handleRegistrationPatch,
  handleRegistrationPropose,
  type RegistrationRouteDependencies,
} from './registration-handlers'
import type { MobileRouteContext } from './route'

// Synthetic HTTP/dependency fixtures only. No service, RPC, network or clock runs.
const ID = 'c59f1000-0000-4000-8000-000000000001'
const OWNER = 'c59f1000-0000-4000-8000-000000000002'
const FOREIGN = 'c59f1000-0000-4000-8000-000000000003'
const KEY = 'AAAA1111-BBBB-4CCC-8DDD-EEEEEEEEEEEE'
const CALLBACK_KEY = 'ffff1111-2222-4333-8444-555555555555'
const STAMP = '2026-10-15T12:00:00.123456-03:00'
const workout = {
  kind: 'workout' as const,
  workout_type: 'Caminhada',
  duration_min: 30,
  intensity: 'moderada' as const,
  performed_at: STAMP,
}
const uiCreate = { ...workout, workout_protocol: 'ui-v1' as const }
const meal = {
  kind: 'meal' as const,
  meal_type: 'almoco' as const,
  items: [{ food_name: 'Arroz branco', quantity_g: 150 }],
}
const legacyDTO = {
  id: ID,
  status: 'pending' as const,
  created_at: '2026-10-15T15:00:00Z',
  expires_at: '2026-10-16T15:00:00Z',
  resolved_at: null,
  proposal: {
    kind: 'workout',
    workout_type: 'Caminhada',
    duration_min: 30,
    estimated_kcal: 100,
    intensity: 'moderada',
  },
}
const dto = (revision = 2) => ({
  ...legacyDTO,
  workout_protocol: 'ui-v1' as const,
  content_revision: revision,
})
const editedDTO = () => ({
  ...dto(),
  receipt: { requestKey: 'wue1:' + KEY, expectedRevision: 1, resultRevision: 2 },
})
const confirmedDTO = (alreadyConfirmed = false) => ({
  ...dto(),
  status: 'confirmed' as const,
  already_confirmed: alreadyConfirmed,
  deduped: false,
})

type Deps = RegistrationRouteDependencies
type Mutator = 'patch' | 'confirm' | 'delete'
const mutations = ['patch', 'confirm', 'delete'] as const
function inputFor(method: Mutator, revision = method === 'patch' ? 1 : 2) {
  return method === 'patch'
    ? { ...uiCreate, expected_revision: revision }
    : { workout_protocol: 'ui-v1' as const, expected_revision: revision }
}
function context(
  method: string,
  body?: unknown,
  key: string | null = KEY,
  rawBody?: string,
): MobileRouteContext {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (key !== null) headers['Idempotency-Key'] = key
  const suffix =
    method === 'POST'
      ? body !== null && typeof body === 'object' && 'kind' in body
        ? 'propose'
        : ID + '/confirm'
      : ID
  return {
    request: new Request('https://performe.invalid/api/mobile/v1/registrations/' + suffix, {
      method,
      headers,
      ...(rawBody === undefined
        ? body === undefined
          ? {}
          : { body: JSON.stringify(body) }
        : { body: rawBody }),
    }),
    requestId: 'request-current-synthetic',
    // Opaque identity is passed to controlled dependencies, never used as an SDK.
    supabase: {} as MobileRouteContext['supabase'],
    auth: {
      accessToken: 'synthetic-not-a-token',
      authUserId: FOREIGN,
      userId: OWNER,
      identity: { id: FOREIGN, email: 'qa@example.invalid', emailConfirmedAt: STAMP },
      patient: {
        id: OWNER,
        authUserId: FOREIGN,
        email: 'qa@example.invalid',
        name: null,
        locale: 'pt-BR',
        timezone: 'UTC',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}
function setup(claim: IdempotencyClaim = { action: 'claimed', claimId: 'claim-synthetic' }) {
  const store = {
    claim: vi.fn<MobileIdempotencyStore['claim']>().mockResolvedValue(claim),
    complete: vi.fn<MobileIdempotencyStore['complete']>().mockResolvedValue(undefined),
    fail: vi.fn<MobileIdempotencyStore['fail']>().mockResolvedValue(undefined),
  } satisfies MobileIdempotencyStore
  const execute = vi
    .fn<Awaited<ReturnType<Deps['admitWorkoutProposal']>>['execute']>()
    .mockResolvedValue(dto())
  const deps = {
    proposeRegistration: vi.fn<Deps['proposeRegistration']>().mockResolvedValue(legacyDTO),
    editRegistration: vi.fn<Deps['editRegistration']>().mockResolvedValue(legacyDTO),
    confirmRegistration: vi.fn<Deps['confirmRegistration']>().mockResolvedValue({
      ...legacyDTO,
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    }),
    cancelRegistration: vi.fn<Deps['cancelRegistration']>().mockResolvedValue(legacyDTO),
    admitWorkoutProposal: vi.fn<Deps['admitWorkoutProposal']>().mockResolvedValue({ execute }),
    editVersionedWorkoutRegistration: vi
      .fn<Deps['editVersionedWorkoutRegistration']>()
      .mockResolvedValue(editedDTO()),
    confirmVersionedWorkoutRegistration: vi
      .fn<Deps['confirmVersionedWorkoutRegistration']>()
      .mockResolvedValue(confirmedDTO()),
    cancelVersionedWorkoutRegistration: vi
      .fn<Deps['cancelVersionedWorkoutRegistration']>()
      .mockResolvedValue({ ...dto(), status: 'cancelled' }),
    loadVersionedWorkoutRegistration: vi
      .fn<Deps['loadVersionedWorkoutRegistration']>()
      .mockResolvedValue(dto()),
    executeIdempotent: vi.fn<Deps['executeIdempotent']>((ctx, payload, operation, options) =>
      executeIdempotent(ctx, payload, store, operation, options),
    ),
  } satisfies Deps
  return { deps, store, execute }
}
function uiCall(method: Mutator, ctx: MobileRouteContext, deps: Deps, id = ID) {
  if (method === 'patch') return handleRegistrationPatch(ctx, id, deps)
  if (method === 'confirm') return handleRegistrationConfirm(ctx, id, deps)
  return handleRegistrationDelete(ctx, id, deps)
}
function versionedMock(method: Mutator, deps: ReturnType<typeof setup>['deps']) {
  if (method === 'patch') return deps.editVersionedWorkoutRegistration
  if (method === 'confirm') return deps.confirmVersionedWorkoutRegistration
  return deps.cancelVersionedWorkoutRegistration
}
function expectNoServiceCalls(s: ReturnType<typeof setup>) {
  for (const mock of [
    s.deps.proposeRegistration,
    s.deps.editRegistration,
    s.deps.confirmRegistration,
    s.deps.cancelRegistration,
    s.deps.admitWorkoutProposal,
    s.deps.editVersionedWorkoutRegistration,
    s.deps.confirmVersionedWorkoutRegistration,
    s.deps.cancelVersionedWorkoutRegistration,
    s.deps.loadVersionedWorkoutRegistration,
    s.execute,
  ])
    expect(mock).not.toHaveBeenCalled()
  expect(s.store.claim).not.toHaveBeenCalled()
}
function expectNoLegacyCalls(s: ReturnType<typeof setup>) {
  for (const mock of [
    s.deps.proposeRegistration,
    s.deps.editRegistration,
    s.deps.confirmRegistration,
    s.deps.cancelRegistration,
  ])
    expect(mock).not.toHaveBeenCalled()
}
function cached(status = 200): IdempotencyClaim {
  return {
    action: 'replay',
    status,
    body: { data: dto(0), meta: { api_version: 'v1', request_id: 'request-old' } },
  }
}
function expectVersionedIntent(
  method: Mutator,
  ctx: MobileRouteContext,
  s: ReturnType<typeof setup>,
  key = KEY,
) {
  if (method === 'patch') {
    expect(s.deps.editVersionedWorkoutRegistration.mock.calls).toEqual([
      [ctx.supabase, ctx.auth, ID, workout, key, 1],
    ])
  } else {
    expect(versionedMock(method, s.deps).mock.calls).toEqual([[ctx.supabase, ctx.auth, ID, 2]])
  }
  expectNoLegacyCalls(s)
}

describe('registration HTTP handlers: explicit ui-v1 intent and legacy compatibility', () => {
  it('awaits real UI admission before the HTTP claim and keeps the exact input/key frozen', async () => {
    const s = setup()
    let enter!: () => void
    let release!: () => void
    const entered = new Promise<void>((resolve) => {
      enter = resolve
    })
    const held = new Promise<void>((resolve) => {
      release = resolve
    })
    s.deps.admitWorkoutProposal.mockImplementation(async () => {
      enter()
      await held
      return { execute: s.execute }
    })
    const ctx = context('POST', { ...uiCreate, workout_type: ' Caminhada ', intensity: undefined })
    const pending = handleRegistrationPropose(ctx, s.deps)
    await entered
    expect(s.store.claim).not.toHaveBeenCalled()
    expect(s.execute).not.toHaveBeenCalled()
    release()
    const response = await pending
    expect(s.deps.admitWorkoutProposal.mock.calls).toEqual([[ctx.supabase, ctx.auth, workout, KEY]])
    expect(s.execute).toHaveBeenCalledOnce()
    expect(s.store.claim).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: OWNER,
        idempotencyKey: KEY,
        method: 'POST',
      }),
    )
    expect(response.status).toBe(201)
    expect(await response.json()).toEqual({
      data: dto(),
      meta: { api_version: 'v1', request_id: ctx.requestId },
    })
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expectNoLegacyCalls(s)
  })

  it('CREATE replay admits before looking at the cached revision0 and executes that same admission closure', async () => {
    const s = setup(cached(201))
    const events: string[] = []
    s.deps.admitWorkoutProposal.mockImplementation(async () => {
      events.push('admit')
      return { execute: s.execute }
    })
    s.store.claim.mockImplementation(async () => {
      events.push('claim')
      return cached(201)
    })
    s.execute.mockImplementation(async () => {
      events.push('execute')
      return dto(2)
    })
    const ctx = context('POST', uiCreate)
    const response = await handleRegistrationPropose(ctx, s.deps)
    expect(events).toEqual(['admit', 'claim', 'execute'])
    expect(s.deps.admitWorkoutProposal).toHaveBeenCalledOnce()
    expect(s.execute.mock.calls).toEqual([[]])
    expect(response.status).toBe(201)
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect(await response.json()).toEqual({
      data: dto(2),
      meta: { api_version: 'v1', request_id: ctx.requestId },
    })
    expect(s.store.complete).not.toHaveBeenCalled()
    expect(s.store.fail).not.toHaveBeenCalled()
    expectNoLegacyCalls(s)
  })

  it('propagates OFF503 from CREATE admission before claiming or falling back to the legacy writer', async () => {
    const s = setup()
    const unavailable = new MobileApiError(503, 'workout_registration_unavailable', 'Unavailable')
    s.deps.admitWorkoutProposal.mockRejectedValue(unavailable)
    await expect(handleRegistrationPropose(context('POST', uiCreate), s.deps)).rejects.toBe(
      unavailable,
    )
    expect(s.store.claim).not.toHaveBeenCalled()
    expect(s.execute).not.toHaveBeenCalled()
    expectNoLegacyCalls(s)
  })

  it.each(
    mutations,
  )('%s fresh uses only the authenticated original UI intent and strips SQL metadata', async (method) => {
    const s = setup()
    const ctx = context(method === 'confirm' ? 'POST' : method.toUpperCase(), inputFor(method))
    const response = await uiCall(method, ctx, s.deps)
    expect(response.status).toBe(200)
    expectVersionedIntent(method, ctx, s)
    expect(s.store.complete).toHaveBeenCalledOnce()
    const hashInput = s.deps.executeIdempotent.mock.calls[0][1]
    expect(JSON.stringify(hashInput)).toContain('"workout_protocol":"ui-v1"')
    expect(JSON.stringify(hashInput)).toContain(
      '"expected_revision":' + (method === 'patch' ? 1 : 2),
    )
  })

  it.each(
    mutations,
  )('%s replay refreshes the original command instead of returning cached revision0', async (method) => {
    const s = setup(cached())
    if (method === 'confirm')
      s.deps.confirmVersionedWorkoutRegistration.mockResolvedValue(confirmedDTO(true))
    const ctx = context(method === 'confirm' ? 'POST' : method.toUpperCase(), inputFor(method))
    const response = await uiCall(method, ctx, s.deps)
    expectVersionedIntent(method, ctx, s)
    expect((await response.json()).data).toEqual(
      method === 'patch'
        ? editedDTO()
        : method === 'confirm'
          ? confirmedDTO(true)
          : { ...dto(2), status: 'cancelled' },
    )
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect(s.store.complete).not.toHaveBeenCalled()
    expect(s.store.fail).not.toHaveBeenCalled()
  })

  it.each(
    mutations,
  )('%s replay cannot hide a fresh revision refusal behind a successful cached DTO', async (method) => {
    const s = setup(cached())
    const conflict = new MobileApiError(409, 'registration_revision_conflict', 'Review changed')
    versionedMock(method, s.deps).mockRejectedValue(conflict)
    await expect(
      uiCall(
        method,
        context(method === 'confirm' ? 'POST' : method.toUpperCase(), inputFor(method)),
        s.deps,
      ),
    ).rejects.toBe(conflict)
    expectNoLegacyCalls(s)
    expect(s.store.complete).not.toHaveBeenCalled()
  })

  it.each(mutations)('%s OFF503 never invokes a legacy fallback', async (method) => {
    const s = setup()
    const unavailable = new MobileApiError(503, 'workout_registration_unavailable', 'Unavailable')
    versionedMock(method, s.deps).mockRejectedValue(unavailable)
    await expect(
      uiCall(
        method,
        context(method === 'confirm' ? 'POST' : method.toUpperCase(), inputFor(method)),
        s.deps,
      ),
    ).rejects.toBe(unavailable)
    expectNoLegacyCalls(s)
    expect(s.store.fail.mock.calls).toEqual([['claim-synthetic', OWNER]])
  })

  it.each([
    'propose',
    'patch',
    'confirm',
    'delete',
  ] as const)('preserves the legacy %s cached replay without running either writer', async (method) => {
    const s = setup({
      action: 'replay',
      status: method === 'propose' ? 201 : 200,
      body: { data: legacyDTO, meta: { api_version: 'v1', request_id: 'request-old' } },
    })
    const ctx = context(
      method === 'propose' || method === 'confirm' ? 'POST' : method.toUpperCase(),
      method === 'propose' || method === 'patch' ? workout : undefined,
    )
    const response =
      method === 'propose'
        ? await handleRegistrationPropose(ctx, s.deps)
        : await uiCall(method, ctx, s.deps)
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect((await response.json()).data).toEqual(legacyDTO)
    expectNoLegacyCalls(s)
    expect(s.deps.admitWorkoutProposal).not.toHaveBeenCalled()
    for (const mock of [
      s.deps.editVersionedWorkoutRegistration,
      s.deps.confirmVersionedWorkoutRegistration,
      s.deps.cancelVersionedWorkoutRegistration,
    ])
      expect(mock).not.toHaveBeenCalled()
    expect(s.store.complete).not.toHaveBeenCalled()
  })

  it.each([
    workout,
    meal,
  ])('keeps legacy propose input %# on its original service', async (input) => {
    const s = setup()
    const ctx = context('POST', input)
    const response = await handleRegistrationPropose(ctx, s.deps)
    expect(s.deps.proposeRegistration.mock.calls).toEqual([[ctx.supabase, ctx.auth, input, KEY]])
    expect(response.status).toBe(201)
    expect(s.deps.admitWorkoutProposal).not.toHaveBeenCalled()
  })

  it.each([
    'confirm',
    'delete',
  ] as const)('zero-byte %s keeps the existing legacy contract without requiring Content-Type', async (method) => {
    const s = setup()
    const ctx = context(method === 'confirm' ? 'POST' : 'DELETE')
    ctx.request.headers.delete('Content-Type')
    await uiCall(method, ctx, s.deps)
    if (method === 'confirm')
      expect(s.deps.confirmRegistration.mock.calls).toEqual([[ctx.supabase, ctx.auth, ID]])
    else expect(s.deps.cancelRegistration.mock.calls).toEqual([[ctx.supabase, OWNER, ID]])
    expect(versionedMock(method, s.deps)).not.toHaveBeenCalled()
  })

  it.each([
    'propose',
    'patch',
    'ui-patch',
  ] as const)('uses the validated callback key, not the raw HTTP header, on %s', async (method) => {
    const s = setup()
    s.deps.executeIdempotent.mockImplementation((_ctx, _payload, operation) =>
      operation(CALLBACK_KEY),
    )
    const ctx = context(
      method === 'propose' ? 'POST' : 'PATCH',
      method === 'ui-patch' ? inputFor('patch') : workout,
    )
    if (method === 'propose') {
      await handleRegistrationPropose(ctx, s.deps)
      expect(s.deps.proposeRegistration.mock.calls).toEqual([
        [ctx.supabase, ctx.auth, workout, CALLBACK_KEY],
      ])
    } else {
      await handleRegistrationPatch(ctx, ID, s.deps)
      if (method === 'ui-patch') expectVersionedIntent('patch', ctx, s, CALLBACK_KEY)
      else
        expect(s.deps.editRegistration.mock.calls).toEqual([
          [ctx.supabase, ctx.auth, ID, workout, CALLBACK_KEY],
        ])
    }
  })

  it('includes revision in the HTTP hash while the service receives only the clean workout plus the explicit revision', async () => {
    const a = setup(),
      b = setup()
    await handleRegistrationPatch(context('PATCH', inputFor('patch', 1)), ID, a.deps)
    await handleRegistrationPatch(context('PATCH', inputFor('patch', 2)), ID, b.deps)
    expect(a.store.claim.mock.calls[0][0].requestHash).not.toBe(
      b.store.claim.mock.calls[0][0].requestHash,
    )
    expect(a.deps.editVersionedWorkoutRegistration.mock.calls[0][3]).toEqual(workout)
    expect(b.deps.editVersionedWorkoutRegistration.mock.calls[0][3]).toEqual(workout)
    expect(a.deps.editVersionedWorkoutRegistration.mock.calls[0][5]).toBe(1)
    expect(b.deps.editVersionedWorkoutRegistration.mock.calls[0][5]).toBe(2)
  })

  it('includes the explicit protocol in the HTTP hash and keeps it out of the admitted SQL input', async () => {
    const ui = setup(),
      legacy = setup()
    await handleRegistrationPropose(context('POST', uiCreate), ui.deps)
    await handleRegistrationPropose(context('POST', workout), legacy.deps)
    expect(JSON.stringify(ui.deps.executeIdempotent.mock.calls[0][1])).toContain(
      '"workout_protocol":"ui-v1"',
    )
    expect(ui.store.claim.mock.calls[0][0].requestHash).not.toBe(
      legacy.store.claim.mock.calls[0][0].requestHash,
    )
    expect(ui.deps.admitWorkoutProposal.mock.calls[0][2]).toEqual(workout)
  })

  it.each([
    'propose',
    'patch',
  ] as const)('rejects an invalid explicit protocol on %s instead of silently selecting legacy', async (method) => {
    const s = setup()
    const ctx = context(method === 'propose' ? 'POST' : 'PATCH', {
      ...workout,
      workout_protocol: 'legacy',
      ...(method === 'patch' ? { expected_revision: 0 } : {}),
    })
    await expect(
      method === 'propose'
        ? handleRegistrationPropose(ctx, s.deps)
        : handleRegistrationPatch(ctx, ID, s.deps),
    ).rejects.toThrow()
    expectNoServiceCalls(s)
  })

  it('rejects a client-owned user or SQL payload before any admission/claim', async () => {
    const s = setup()
    await expect(
      handleRegistrationPropose(
        context('POST', {
          ...uiCreate,
          user_id: FOREIGN,
          legacy_arguments: { p_user_id: FOREIGN },
        }),
        s.deps,
      ),
    ).rejects.toThrow()
    expectNoServiceCalls(s)
  })

  it.each([
    'confirm',
    'delete',
  ] as const)('any present JSON on %s must prove ui-v1 selection; JSON null is not absence', async (method) => {
    for (const body of [
      null,
      {},
      { workout_protocol: 'ui-v1' },
      { workout_protocol: 'legacy', expected_revision: 0 },
    ]) {
      const s = setup()
      await expect(
        uiCall(method, context(method === 'confirm' ? 'POST' : 'DELETE', body), s.deps),
      ).rejects.toThrow()
      expectNoServiceCalls(s)
    }
  })

  it.each([
    'confirm',
    'delete',
  ] as const)('strict JSON rejects duplicate revision keys on %s before any effect', async (method) => {
    const s = setup()
    const raw = '{"workout_protocol":"ui-v1","expected_revision":0,"expected_revision":2}'
    await expect(
      uiCall(
        method,
        context(method === 'confirm' ? 'POST' : 'DELETE', undefined, KEY, raw),
        s.deps,
      ),
    ).rejects.toMatchObject({ status: 400, code: 'invalid_json' })
    expectNoServiceCalls(s)
  })

  it.each([
    'patch',
    'confirm',
    'delete',
    'get',
  ] as const)('validates the %s path resource ID before using either service', async (method) => {
    const s = setup()
    const ctx = context(
      method === 'confirm' ? 'POST' : method.toUpperCase(),
      method === 'get' ? undefined : inputFor(method),
    )
    await expect(
      method === 'get'
        ? handleRegistrationGet(ctx, 'not-a-uuid', s.deps)
        : uiCall(method, ctx, s.deps, 'not-a-uuid'),
    ).rejects.toThrow()
    expectNoServiceCalls(s)
  })

  it.each([
    'propose',
    'patch',
    'confirm',
    'delete',
  ] as const)('requires the %s key before admission or any legacy/versioned write', async (method) => {
    for (const [key, code] of [
      [null, 'missing_idempotency_key'],
      ['short', 'invalid_idempotency_key'],
    ] as const) {
      const s = setup()
      const ctx = context(
        method === 'propose' || method === 'confirm' ? 'POST' : method.toUpperCase(),
        method === 'propose' ? uiCreate : inputFor(method),
        key,
      )
      await expect(
        method === 'propose' ? handleRegistrationPropose(ctx, s.deps) : uiCall(method, ctx, s.deps),
      ).rejects.toMatchObject({ status: 400, code })
      expectNoServiceCalls(s)
    }
  })

  it('GET is UI-only, needs no idempotency key, and binds lookup to auth.userId rather than any requested owner', async () => {
    const s = setup()
    const ctx = context('GET', undefined, null)
    ctx.request = new Request(ctx.request.url + '?user_id=' + FOREIGN)
    const response = await handleRegistrationGet(ctx, ID, s.deps)
    expect(s.deps.loadVersionedWorkoutRegistration.mock.calls).toEqual([[ctx.supabase, OWNER, ID]])
    expect(s.store.claim).not.toHaveBeenCalled()
    expectNoLegacyCalls(s)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      data: dto(),
      meta: { api_version: 'v1', request_id: ctx.requestId },
    })
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
  })

  it('GET OFF503 or foreign-owner refusal propagates without exposing a legacy pending', async () => {
    for (const error of [
      new MobileApiError(503, 'workout_registration_unavailable', 'Unavailable'),
      new MobileApiError(404, 'registration_not_found', 'Not found'),
    ]) {
      const s = setup()
      s.deps.loadVersionedWorkoutRegistration.mockRejectedValue(error)
      await expect(handleRegistrationGet(context('GET'), ID, s.deps)).rejects.toBe(error)
      expectNoLegacyCalls(s)
      expect(s.store.claim).not.toHaveBeenCalled()
    }
  })
})
