import {
  parseRevenueCatProductPlanMap,
  type RevenueCatNormalizationConfiguration,
} from './revenuecat-webhook'

type Environment = Record<string, string | undefined>
export type RevenueCatWebhookConfiguration = RevenueCatNormalizationConfiguration & {
  signingSecret: string
}
export type MobileBillingCapability = {
  provider: 'revenuecat'
  available: boolean
  reason: 'provider_not_configured' | 'provider_configured'
}

export function parseRevenueCatWebhookConfiguration(
  env: Environment,
): RevenueCatWebhookConfiguration | null {
  const signingSecret = env.REVENUECAT_WEBHOOK_SIGNING_SECRET
  const environment = env.REVENUECAT_WEBHOOK_ENVIRONMENT
  const productPlanMap = env.REVENUECAT_PRODUCT_PLAN_MAP
  if (!signingSecret || !environment || !productPlanMap) return null
  if (signingSecret.length < 32) return null
  if (environment !== 'sandbox' && environment !== 'production') return null
  try {
    return {
      signingSecret,
      expectedEnvironment: environment,
      entitlementKey: 'bodyflow_full',
      productPlanMap: parseRevenueCatProductPlanMap(productPlanMap),
    }
  } catch {
    return null
  }
}

function providerEnvironment(): Environment {
  return {
    REVENUECAT_WEBHOOK_SIGNING_SECRET: process.env.REVENUECAT_WEBHOOK_SIGNING_SECRET,
    REVENUECAT_WEBHOOK_ENVIRONMENT: process.env.REVENUECAT_WEBHOOK_ENVIRONMENT,
    REVENUECAT_PRODUCT_PLAN_MAP: process.env.REVENUECAT_PRODUCT_PLAN_MAP,
  }
}

export function loadRevenueCatWebhookConfiguration(): RevenueCatWebhookConfiguration | null {
  return parseRevenueCatWebhookConfiguration(providerEnvironment())
}

function selectedProject(env: Environment): boolean {
  const ref = env.MOBILE_REVENUECAT_BILLING_PROJECT_REF ?? ''
  if (!/^[a-z0-9]{20}$/.test(ref) || ref === 'xuxehkhdvjivitduarvb') return false
  const origin = env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  // Exact canonical origins also reject normalized-away default ports,
  // credentials, whitespace and ambiguous multi-project selectors.
  return origin === `https://${ref}.supabase.co` || origin === `https://${ref}.supabase.co/`
}

/** This explicit operational switch stays absent until store, webhook and
 * commercial qualification. Parsing config is not proof of that qualification.
 * Only the capability is public; never return credentials or product mapping. */
export function resolveMobileBillingCapability(env: Environment): MobileBillingCapability {
  const available = selectedProject(env) && parseRevenueCatWebhookConfiguration(env) !== null
  return {
    provider: 'revenuecat',
    available,
    reason: available ? 'provider_configured' : 'provider_not_configured',
  }
}

export function mobileBillingCapability(): MobileBillingCapability {
  // Webpack also folds local aliases of process.env. Keep property reads
  // behind the resolver parameter so they use this request's environment.
  // The resolver reads only its five known keys and returns no configuration.
  return resolveMobileBillingCapability(process.env)
}
