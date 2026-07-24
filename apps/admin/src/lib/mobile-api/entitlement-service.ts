import { entitlementDecisionSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'

const BODYFLOW_ENTITLEMENT_KEY = 'bodyflow_full'
const ENTITLEMENT_EXEMPT_PATHS = [
  '/api/mobile/v1/me',
  '/api/mobile/v1/profile',
  '/api/mobile/v1/onboarding',
  '/api/mobile/v1/entitlements',
  '/api/mobile/v1/coach/persona',
  '/api/mobile/v1/devices',
  '/api/mobile/v1/notification-preferences',
] as const

function isPathOrChild(path: string, allowedPath: string): boolean {
  return path === allowedPath || path.startsWith(`${allowedPath}/`)
}

export function mobilePathRequiresEntitlement(path: string): boolean {
  return !ENTITLEMENT_EXEMPT_PATHS.some((allowedPath) => isPathOrChild(path, allowedPath))
}

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

export async function authorizeMobileEntitlement(
  supabase: ServiceClient,
  userId: string,
  path: string,
  now = new Date(),
): Promise<void> {
  if (!mobilePathRequiresEntitlement(path)) return

  const decision = await loadMobileEntitlement(supabase, userId, now)
  if (!decision.has_active_access) {
    throw new MobileApiError(402, 'subscription_required', 'An active subscription is required')
  }
}
