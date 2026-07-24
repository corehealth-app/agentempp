import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MobileApiError, mobileSuccess } from './http'
import { createMobileRoute, type MobileRouteRuntime } from './route'

const patientContext = {
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
    status: 'active',
  },
}

function runtime(overrides: Partial<MobileRouteRuntime> = {}): MobileRouteRuntime {
  return {
    authenticate: vi.fn().mockResolvedValue(patientContext),
    authorizeEntitlement: vi.fn().mockResolvedValue(undefined),
    createServiceClient: vi
      .fn()
      .mockReturnValue({ kind: 'service-client' } as unknown as ServiceClient),
    createRequestId: vi.fn().mockReturnValue('request-id'),
    ...overrides,
  }
}

afterEach(() => {
  vi.restoreAllMocks()
})

describe('mobile route wrapper', () => {
  it('passes authenticated patient context to the handler', async () => {
    const handler = vi.fn(async (context) =>
      mobileSuccess({ user_id: context.auth.userId }, context.requestId),
    )
    const route = createMobileRoute(handler, runtime())

    const response = await route(new Request('https://example.test/api/mobile/v1/me'))

    expect(response.status).toBe(200)
    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        auth: expect.objectContaining({ userId: 'patient-1' }),
        requestId: 'request-id',
        supabase: { kind: 'service-client' },
      }),
    )
  })

  it('authorizes product access after authentication and before the handler', async () => {
    const order: string[] = []
    const authorizeEntitlement = vi.fn(async () => {
      order.push('authorize')
    })
    const handler = vi.fn(async (_context) => {
      order.push('handler')
      return mobileSuccess({ ok: true }, 'request-id')
    })
    const route = createMobileRoute(handler, runtime({ authorizeEntitlement }))

    const response = await route(new Request('https://example.test/api/mobile/v1/today'))

    expect(response.status).toBe(200)
    expect(order).toEqual(['authorize', 'handler'])
    expect(authorizeEntitlement).toHaveBeenCalledWith(
      patientContext,
      expect.objectContaining({ url: 'https://example.test/api/mobile/v1/today' }),
      { kind: 'service-client' },
    )
  })

  it('does not execute a protected handler when entitlement authorization fails', async () => {
    const handler = vi.fn()
    const route = createMobileRoute(
      handler,
      runtime({
        authorizeEntitlement: vi
          .fn()
          .mockRejectedValue(
            new MobileApiError(402, 'subscription_required', 'An active subscription is required'),
          ),
      }),
    )

    const response = await route(new Request('https://example.test/api/mobile/v1/today'))

    expect(response.status).toBe(402)
    expect(handler).not.toHaveBeenCalled()
  })

  it('maps expected API errors to the public error envelope', async () => {
    const route = createMobileRoute(
      vi.fn(),
      runtime({
        authenticate: vi
          .fn()
          .mockRejectedValue(new MobileApiError(403, 'forbidden', 'Access denied')),
      }),
    )

    const response = await route(new Request('https://example.test/api/mobile/v1/me'))

    expect(response.status).toBe(403)
    expect(await response.json()).toEqual({
      error: { code: 'forbidden', message: 'Access denied', request_id: 'request-id' },
    })
  })

  it('hides unexpected internal errors', async () => {
    const route = createMobileRoute(
      vi.fn().mockRejectedValue(new Error('database password leaked here')),
      runtime(),
    )

    const response = await route(new Request('https://example.test/api/mobile/v1/me'))

    expect(response.status).toBe(500)
    const body = await response.json()
    expect(JSON.stringify(body)).not.toContain('database password')
    expect(body).toEqual({
      error: {
        code: 'internal_error',
        message: 'Unexpected server error',
        request_id: 'request-id',
      },
    })
  })

  it('never logs a capability URL when authentication fails before the handler', async () => {
    const capability = 'opaque-sensitive-cover-capability'
    const authenticationError = new Error('private auth lookup detail')
    authenticationError.name = capability
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const route = createMobileRoute(
      vi.fn(),
      runtime({
        authenticate: vi.fn().mockRejectedValue(authenticationError),
      }),
    )

    const response = await route(
      new Request(`https://example.test/api/mobile/v1/content/covers/${capability}`),
    )

    expect(response.status).toBe(500)
    expect(consoleError).toHaveBeenCalledWith('[mobile-api] unexpected_error', {
      request_id: 'request-id',
      scope: 'mobile_api_v1',
      error_name: 'UnknownError',
    })
    const serializedLogs = JSON.stringify(consoleError.mock.calls)
    expect(serializedLogs).not.toContain(capability)
    expect(serializedLogs).not.toContain('/api/')
    expect(serializedLogs).not.toContain('private auth lookup detail')
  })
})
