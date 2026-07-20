import { describe, expect, it, vi } from 'vitest'
import { authenticatePatient, type MobileAuthDependencies } from './auth'
import { MobileApiError } from './http'

function dependencies(overrides: Partial<MobileAuthDependencies> = {}): MobileAuthDependencies {
  return {
    verifyAccessToken: vi.fn().mockResolvedValue({
      id: 'auth-1',
      email: 'patient@example.com',
      emailConfirmedAt: '2026-07-20T00:00:00Z',
    }),
    bootstrapPatient: vi.fn().mockResolvedValue('patient-1'),
    loadPatient: vi.fn().mockResolvedValue({
      id: 'patient-1',
      authUserId: 'auth-1',
      email: 'patient@example.com',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/New_York',
      country: 'US',
      status: 'active',
    }),
    ...overrides,
  }
}

describe('mobile patient authentication', () => {
  it('rejects requests without a bearer token before touching Supabase', async () => {
    const deps = dependencies()

    await expect(
      authenticatePatient(new Request('https://example.test'), deps),
    ).rejects.toMatchObject({ status: 401, code: 'missing_access_token' })
    expect(deps.verifyAccessToken).not.toHaveBeenCalled()
  })

  it('bootstraps only a confirmed patient identity', async () => {
    const deps = dependencies()
    const request = new Request('https://example.test', {
      headers: { authorization: 'Bearer valid-token' },
    })

    const context = await authenticatePatient(request, deps)

    expect(deps.bootstrapPatient).toHaveBeenCalledWith('valid-token')
    expect(context.userId).toBe('patient-1')
    expect(context.authUserId).toBe('auth-1')
  })

  it('rejects an unconfirmed email before domain bootstrap', async () => {
    const deps = dependencies({
      verifyAccessToken: vi.fn().mockResolvedValue({
        id: 'auth-1',
        email: 'patient@example.com',
        emailConfirmedAt: null,
      }),
    })
    const request = new Request('https://example.test', {
      headers: { authorization: 'Bearer valid-token' },
    })

    await expect(authenticatePatient(request, deps)).rejects.toEqual(
      new MobileApiError(403, 'email_not_confirmed', 'Confirm your email before continuing'),
    )
    expect(deps.bootstrapPatient).not.toHaveBeenCalled()
  })

  it('does not silently link a legacy domain identity', async () => {
    const deps = dependencies({
      bootstrapPatient: vi.fn().mockRejectedValue(new Error('legacy_identity_conflict')),
    })
    const request = new Request('https://example.test', {
      headers: { authorization: 'Bearer valid-token' },
    })

    await expect(authenticatePatient(request, deps)).rejects.toMatchObject({
      status: 409,
      code: 'identity_migration_required',
    })
  })

  it('rejects a blocked or deleted domain account', async () => {
    const deps = dependencies({
      loadPatient: vi.fn().mockResolvedValue({
        id: 'patient-1',
        authUserId: 'auth-1',
        email: 'patient@example.com',
        name: null,
        locale: 'pt-BR',
        timezone: 'America/New_York',
        country: 'US',
        status: 'blocked',
      }),
    })
    const request = new Request('https://example.test', {
      headers: { authorization: 'Bearer valid-token' },
    })

    await expect(authenticatePatient(request, deps)).rejects.toMatchObject({
      status: 403,
      code: 'patient_account_inactive',
    })
  })
})
