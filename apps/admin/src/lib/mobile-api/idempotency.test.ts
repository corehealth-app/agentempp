import { describe, expect, it, vi } from 'vitest'
import {
  executeIdempotent,
  type IdempotencyClaim,
  type MobileIdempotencyStore,
} from './idempotency'
import type { MobileRouteContext } from './route'

function context(idempotencyKey?: string): MobileRouteContext {
  return {
    auth: {
      accessToken: 'token',
      authUserId: 'auth-1',
      userId: 'patient-1',
      identity: {
        id: 'auth-1',
        email: 'patient@example.com',
        emailConfirmedAt: '2026-07-20T00:00:00Z',
      },
      patient: {
        id: 'patient-1',
        authUserId: 'auth-1',
        email: 'patient@example.com',
        name: null,
        locale: 'pt-BR',
        timezone: 'America/New_York',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
    request: new Request('https://example.test/api/mobile/v1/me', {
      method: 'PATCH',
      headers: idempotencyKey ? { 'idempotency-key': idempotencyKey } : undefined,
    }),
    requestId: 'request-current',
    supabase: {} as never,
  }
}

function store(claim: IdempotencyClaim): MobileIdempotencyStore {
  return {
    claim: vi.fn().mockResolvedValue(claim),
    complete: vi.fn().mockResolvedValue(undefined),
    fail: vi.fn().mockResolvedValue(undefined),
  }
}

describe('mobile mutation idempotency', () => {
  it('requires an idempotency key before running a mutation', async () => {
    const persistence = store({ action: 'claimed', claimId: 'claim-1' })

    await expect(
      executeIdempotent(context(), { name: 'New name' }, persistence, vi.fn()),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(persistence.claim).not.toHaveBeenCalled()
  })

  it('claims and stores the first deterministic response', async () => {
    const persistence = store({ action: 'claimed', claimId: 'claim-1' })
    const operation = vi
      .fn()
      .mockResolvedValue(
        Response.json(
          { data: { ok: true }, meta: { api_version: 'v1', request_id: 'request-current' } },
          { status: 201 },
        ),
      )

    const response = await executeIdempotent(
      context('mobile-request-0001'),
      { name: 'New name' },
      persistence,
      operation,
    )

    expect(response.status).toBe(201)
    expect(operation).toHaveBeenCalledOnce()
    expect(persistence.complete).toHaveBeenCalledWith(
      'claim-1',
      'patient-1',
      201,
      expect.objectContaining({ data: { ok: true } }),
    )
  })

  it('passes the normalized idempotency key to the mutation', async () => {
    const persistence = store({ action: 'claimed', claimId: 'claim-1' })
    const operation = vi.fn().mockResolvedValue(Response.json({ data: { ok: true } }))

    await executeIdempotent(
      context('  mobile-request-0001  '),
      { amount_ml: 350 },
      persistence,
      operation,
    )

    expect(operation).toHaveBeenCalledWith('mobile-request-0001')
    expect(persistence.claim).toHaveBeenCalledWith(
      expect.objectContaining({ idempotencyKey: 'mobile-request-0001' }),
    )
  })

  it('replays a completed response without running the mutation again', async () => {
    const persistence = store({
      action: 'replay',
      status: 200,
      body: {
        data: { ok: true },
        meta: { api_version: 'v1', request_id: 'request-original' },
      },
    })
    const operation = vi.fn()

    const response = await executeIdempotent(
      context('mobile-request-0001'),
      { name: 'New name' },
      persistence,
      operation,
    )

    expect(operation).not.toHaveBeenCalled()
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(await response.json()).toEqual({
      data: { ok: true },
      meta: { api_version: 'v1', request_id: 'request-current' },
    })
  })

  it('can refresh a temporary capability while preserving the completed mutation replay', async () => {
    const persistence = store({
      action: 'replay',
      status: 201,
      body: { data: { asset: { id: 'asset-1' }, upload: { signed_url: 'expired' } } },
    })
    const operation = vi.fn()
    const refreshReplay = vi
      .fn()
      .mockResolvedValue(
        Response.json(
          { data: { asset: { id: 'asset-1' }, upload: { signed_url: 'fresh' } } },
          { status: 201 },
        ),
      )

    const response = await executeIdempotent(
      context('mobile-request-0001'),
      { kind: 'meal_photo' },
      persistence,
      operation,
      { refreshReplay },
    )

    expect(operation).not.toHaveBeenCalled()
    expect(refreshReplay).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'replay', status: 201 }),
    )
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(await response.json()).toMatchObject({
      data: { asset: { id: 'asset-1' }, upload: { signed_url: 'fresh' } },
    })
  })

  it('can keep a temporary capability out of the persisted replay body', async () => {
    const persistence = store({ action: 'claimed', claimId: 'claim-1' })
    const operation = vi.fn().mockResolvedValue(
      Response.json(
        {
          data: {
            asset: { id: 'asset-1' },
            upload: { signed_url: 'https://storage.test/private-capability' },
          },
        },
        { status: 201 },
      ),
    )

    const response = await executeIdempotent(
      context('mobile-request-0001'),
      { kind: 'meal_photo' },
      persistence,
      operation,
      { responseBodyForStorage: () => ({ temporary_capability_redacted: true }) },
    )

    expect(await response.json()).toMatchObject({
      data: { upload: { signed_url: 'https://storage.test/private-capability' } },
    })
    expect(persistence.complete).toHaveBeenCalledWith('claim-1', 'patient-1', 201, {
      temporary_capability_redacted: true,
    })
  })

  it('rejects reuse of a key for another request', async () => {
    const persistence = store({ action: 'conflict' })

    await expect(
      executeIdempotent(
        context('mobile-request-0001'),
        { name: 'Different payload' },
        persistence,
        vi.fn(),
      ),
    ).rejects.toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
  })

  it('marks an interrupted operation as failed before propagating the error', async () => {
    const persistence = store({ action: 'claimed', claimId: 'claim-1' })
    const operation = vi.fn().mockRejectedValue(new Error('operation failed'))

    await expect(
      executeIdempotent(
        context('mobile-request-0001'),
        { name: 'New name' },
        persistence,
        operation,
      ),
    ).rejects.toThrow('operation failed')
    expect(persistence.fail).toHaveBeenCalledWith('claim-1', 'patient-1')
  })
})
