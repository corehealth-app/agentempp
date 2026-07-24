import { entitlementDecisionSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'

const BODYFLOW_ENTITLEMENT_KEY = 'bodyflow_full'

export async function loadMobileEntitlement(
  supabase: ServiceClient,
  userId: string,
  now = new Date(),
) {
  const { data, error } = await supabase.rpc('resolve_user_entitlement', {
    p_user_id: userId,
    p_entitlement_key: BODYFLOW_ENTITLEMENT_KEY,
    p_now: now.toISOString(),
  })

  if (error) {
    throw new MobileApiError(500, 'data_access_failed', 'Entitlement lookup failed')
  }

  const decision = entitlementDecisionSchema.safeParse(data)
  if (!decision.success) {
    throw new MobileApiError(
      500,
      'entitlement_decision_failed',
      'Entitlement decision is unavailable',
    )
  }

  return {
    ...decision.data,
    mobile_billing: {
      provider: 'revenuecat' as const,
      available: false,
      reason: 'provider_not_configured' as const,
    },
  }
}
