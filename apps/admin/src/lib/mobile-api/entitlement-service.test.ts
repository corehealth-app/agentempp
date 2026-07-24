import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  authorizeMobileEntitlement,
  loadMobileEntitlement,
  mobilePathRequiresEntitlement,
} from './entitlement-service'

const USER_ID = '00000000-0000-4000-8000-000000000001'

function serviceClient(result: { data: unknown; error: { message: string } | null }) {
  return {
    rpc: vi.fn().mockResolvedValue(result),
  } as unknown as ServiceClient
}

const activeDecision = {
  entitlement: 'bodyflow_full',
  has_active_access: true,
  status: 'active',
  source: 'revenuecat',
  plan: 'mensal',
  access_expires_at: '2026-08-24T00:00:00.000Z',
  grace_expires_at: null,
  cancel_at_period_end: false,
  reason: 'valid_entitlement',
  decision_at: '2026-07-24T00:00:00.000Z',
}

describe('mobile entitlement service', () => {
  it('loads the central decision and returns a stable disabled billing capability', async () => {
    const supabase = serviceClient({ data: activeDecision, error: null })

    await expect(
      loadMobileEntitlement(supabase, USER_ID, new Date('2026-07-24T00:00:00.000Z')),
    ).resolves.toEqual({
      ...activeDecision,
      mobile_billing: {
        provider: 'revenuecat',
        available: false,
        reason: 'provider_not_configured',
      },
    })
    expect(supabase.rpc).toHaveBeenCalledWith('resolve_user_entitlement', {
      p_user_id: USER_ID,
      p_entitlement_key: 'bodyflow_full',
      p_now: '2026-07-24T00:00:00.000Z',
    })
  })

  it('fails closed when the database returns no entitlement record', async () => {
    const supabase = serviceClient({ data: null, error: null })

    await expect(loadMobileEntitlement(supabase, USER_ID)).rejects.toMatchObject({
      status: 500,
      code: 'entitlement_decision_failed',
    })
  })

  it('rejects an unsafe decision instead of leaking provider references', async () => {
    const supabase = serviceClient({
      data: { ...activeDecision, source_reference: 'private-provider-reference' },
      error: null,
    })

    await expect(loadMobileEntitlement(supabase, USER_ID)).rejects.toMatchObject({
      status: 500,
      code: 'entitlement_decision_failed',
    })
  })

  it('maps database failures without exposing their details', async () => {
    const supabase = serviceClient({
      data: null,
      error: { message: 'database password and provider receipt' },
    })

    await expect(loadMobileEntitlement(supabase, USER_ID)).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
      message: 'Entitlement lookup failed',
    })
  })

  it('requires entitlement for product data while preserving the acquisition flow', () => {
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/today')).toBe(true)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/content/article-id')).toBe(true)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/registrations/propose')).toBe(true)

    expect(mobilePathRequiresEntitlement('/api/mobile/v1/me')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/profile')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/onboarding')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/entitlements')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/coach/persona')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/devices/device-id')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/notification-preferences')).toBe(false)
    expect(mobilePathRequiresEntitlement('/api/mobile/v1/me-not-really')).toBe(true)
  })

  it('blocks a protected route when the central decision denies access', async () => {
    const supabase = serviceClient({
      data: {
        ...activeDecision,
        has_active_access: false,
        status: 'expired',
        source: null,
        plan: null,
        access_expires_at: null,
        reason: 'no_entitlement',
      },
      error: null,
    })

    await expect(
      authorizeMobileEntitlement(
        supabase,
        USER_ID,
        '/api/mobile/v1/today',
        new Date('2026-07-24T00:00:00.000Z'),
      ),
    ).rejects.toMatchObject({
      status: 402,
      code: 'subscription_required',
      message: 'An active subscription is required',
    })
  })

  it('does not query billing for an acquisition-flow route', async () => {
    const supabase = serviceClient({ data: activeDecision, error: null })

    await expect(
      authorizeMobileEntitlement(
        supabase,
        USER_ID,
        '/api/mobile/v1/entitlements',
        new Date('2026-07-24T00:00:00.000Z'),
      ),
    ).resolves.toBeUndefined()
    expect(supabase.rpc).not.toHaveBeenCalled()
  })
})
