import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MobileApiError } from '@/lib/mobile-api/http'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const USER_ID = '00000000-0000-0000-0000-000000000851'
const BODY_HASH = 'e'.repeat(64)

function context(body: unknown, idempotencyKey?: string): MobileRouteContext {
  const headers = new Headers({ 'content-type': 'application/json' })
  if (idempotencyKey) headers.set('idempotency-key', idempotencyKey)
  return {
    request: new Request(
      'https://bodyflow.test/api/mobile/v1/legal/medication-reminder-disclaimer/accept',
      { method: 'POST', headers, body: JSON.stringify(body) },
    ),
    requestId: 'request-legal-accept-0851',
    supabase: { rpc: vi.fn() } as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: USER_ID,
      userId: USER_ID,
      identity: { id: USER_ID, email: null, emailConfirmedAt: null },
      patient: {
        id: USER_ID,
        authUserId: USER_ID,
        email: null,
        name: null,
        locale: 'en-US',
        timezone: 'UTC',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

async function loadRoute(
  acceptMedicationDisclaimer = vi.fn(async (..._args: unknown[]) => ({
    document_key: 'medication_reminder_disclaimer',
    version: '2026-07-22.1',
    accepted_at: '2026-07-23T15:00:00.000Z',
  })),
) {
  vi.resetModules()
  const executeIdempotent = vi.fn(
    async (
      mobileContext: MobileRouteContext,
      _payload: unknown,
      operation: (idempotencyKey: string) => Promise<Response>,
    ) => {
      const key = mobileContext.request.headers.get('idempotency-key')
      if (!key) {
        throw new MobileApiError(400, 'missing_idempotency_key', 'Idempotency-Key is required')
      }
      return operation(key)
    },
  )
  vi.doMock('@/lib/mobile-api/route', () => ({
    createMobileRoute: (handler: (mobileContext: MobileRouteContext) => Promise<Response>) =>
      handler,
  }))
  vi.doMock('@/lib/mobile-api/idempotency', () => ({
    executeSupabaseIdempotent: executeIdempotent,
  }))
  vi.doMock('@/lib/mobile-api/routine-adherence-service', () => ({
    acceptMedicationDisclaimer,
    MEDICATION_DISCLAIMER_KEY: 'medication_reminder_disclaimer',
  }))
  vi.doMock('@/lib/mobile-api/supabase-routine-adherence', () => ({
    createSupabaseRoutineAdherenceDependencies: vi.fn(() => ({ repository: {} })),
  }))

  const routes = await import('./route')
  return { acceptMedicationDisclaimer, executeIdempotent, routes }
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/idempotency')
  vi.doUnmock('@/lib/mobile-api/routine-adherence-service')
  vi.doUnmock('@/lib/mobile-api/supabase-routine-adherence')
  vi.resetModules()
})

describe('medication reminder disclaimer acceptance route', () => {
  it('requires accepted=true and exact version/hash fields', async () => {
    const { acceptMedicationDisclaimer, routes } = await loadRoute()
    const post = routes.POST as unknown as (context: MobileRouteContext) => Promise<Response>

    for (const body of [
      { accepted: false, version: '2026-07-22.1', body_hash: BODY_HASH },
      { accepted: true, version: '2026-07-22.1', body_hash: 'bad' },
      {
        accepted: true,
        version: '2026-07-22.1',
        body_hash: BODY_HASH,
        document_key: 'other',
      },
    ]) {
      await expect(post(context(body, 'legal-invalid-0851'))).rejects.toThrow()
    }
    expect(acceptMedicationDisclaimer).not.toHaveBeenCalled()
  })

  it('requires Idempotency-Key before acceptance', async () => {
    const { acceptMedicationDisclaimer, routes } = await loadRoute()
    const post = routes.POST as unknown as (context: MobileRouteContext) => Promise<Response>

    await expect(
      post(context({ accepted: true, version: '2026-07-22.1', body_hash: BODY_HASH })),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(acceptMedicationDisclaimer).not.toHaveBeenCalled()
  })

  it('returns only document key, accepted version, and accepted_at', async () => {
    const { acceptMedicationDisclaimer, routes } = await loadRoute()
    const post = routes.POST as unknown as (context: MobileRouteContext) => Promise<Response>

    const response = await post(
      context(
        { accepted: true, version: '2026-07-22.1', body_hash: BODY_HASH },
        'legal-accept-0851',
      ),
    )

    expect(acceptMedicationDisclaimer.mock.calls[0]?.[2]).toEqual({
      accepted: true,
      version: '2026-07-22.1',
      body_hash: BODY_HASH,
    })
    const body = await response.json()
    expect(body.data).toEqual({
      document_key: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      accepted_at: '2026-07-23T15:00:00.000Z',
    })
    expect(Object.keys(body.data)).toEqual(['document_key', 'version', 'accepted_at'])
  })

  it('surfaces a stale version or hash as 409', async () => {
    const accept = vi.fn(async () => {
      throw new MobileApiError(
        409,
        'medication_disclaimer_version_stale',
        'Medication disclaimer version changed',
      )
    })
    const { routes } = await loadRoute(accept)
    const post = routes.POST as unknown as (context: MobileRouteContext) => Promise<Response>

    await expect(
      post(
        context(
          { accepted: true, version: '2026-07-22.0', body_hash: BODY_HASH },
          'legal-stale-0851',
        ),
      ),
    ).rejects.toMatchObject({ status: 409, code: 'medication_disclaimer_version_stale' })
  })
})
