import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { loadMobileEntitlement } from './entitlement-service'

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
})
