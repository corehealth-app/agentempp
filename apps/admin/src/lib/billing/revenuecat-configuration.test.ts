import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  loadRevenueCatWebhookConfiguration,
  parseRevenueCatWebhookConfiguration,
  resolveMobileBillingCapability,
} from './revenuecat-configuration'

const REF = 'xitugspwfxkcluxvrdeg'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'
const SECRET = '  synthetic-only-secret-exact-bytes-32plus  '
const configured = {
  NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  MOBILE_REVENUECAT_BILLING_PROJECT_REF: REF,
  REVENUECAT_WEBHOOK_SIGNING_SECRET: SECRET,
  REVENUECAT_WEBHOOK_ENVIRONMENT: 'sandbox',
  REVENUECAT_PRODUCT_PLAN_MAP: '{"synthetic_monthly":"mensal","synthetic_annual":"anual"}',
}
const unavailable = { provider: 'revenuecat', available: false, reason: 'provider_not_configured' }

afterEach(() => vi.unstubAllEnvs())

describe('RevenueCat runtime configuration', () => {
  it('preserves exact signing bytes, environment and the bounded product mapping', () => {
    expect(parseRevenueCatWebhookConfiguration(configured)).toEqual({
      signingSecret: SECRET,
      expectedEnvironment: 'sandbox',
      entitlementKey: 'bodyflow_full',
      productPlanMap: { synthetic_monthly: 'mensal', synthetic_annual: 'anual' },
    })
  })

  it.each([
    ['missing secret', { REVENUECAT_WEBHOOK_SIGNING_SECRET: undefined }],
    ['short secret', { REVENUECAT_WEBHOOK_SIGNING_SECRET: 'x'.repeat(31) }],
    ['missing environment', { REVENUECAT_WEBHOOK_ENVIRONMENT: undefined }],
    ['unrecognized environment', { REVENUECAT_WEBHOOK_ENVIRONMENT: 'SANDBOX' }],
    ['missing map', { REVENUECAT_PRODUCT_PLAN_MAP: undefined }],
    ['empty map', { REVENUECAT_PRODUCT_PLAN_MAP: '{}' }],
    ['malformed map', { REVENUECAT_PRODUCT_PLAN_MAP: '{' }],
    ['unsupported plan', { REVENUECAT_PRODUCT_PLAN_MAP: '{"synthetic":"weekly"}' }],
    [
      'too many products',
      {
        REVENUECAT_PRODUCT_PLAN_MAP: JSON.stringify(
          Object.fromEntries(Array.from({ length: 33 }, (_, i) => [`synthetic_${i}`, 'mensal'])),
        ),
      },
    ],
  ])('keeps an invalid provider unavailable: %s', (_label, override) => {
    expect(parseRevenueCatWebhookConfiguration({ ...configured, ...override })).toBeNull()
    expect(resolveMobileBillingCapability({ ...configured, ...override })).toEqual(unavailable)
  })

  it.each([
    ['missing selector', { MOBILE_REVENUECAT_BILLING_PROJECT_REF: undefined }],
    ['boolean is not project approval', { MOBILE_REVENUECAT_BILLING_PROJECT_REF: 'true' }],
    ['wrong project', { MOBILE_REVENUECAT_BILLING_PROJECT_REF: 'aaaaaaaaaaaaaaaaaaaa' }],
    [
      'legacy project',
      {
        MOBILE_REVENUECAT_BILLING_PROJECT_REF: OLD_PRODUCTION,
        NEXT_PUBLIC_SUPABASE_URL: `https://${OLD_PRODUCTION}.supabase.co`,
      },
    ],
    [
      'mixed legacy selection',
      { MOBILE_REVENUECAT_BILLING_PROJECT_REF: `${REF},${OLD_PRODUCTION}` },
    ],
    ['missing origin', { NEXT_PUBLIC_SUPABASE_URL: undefined }],
    ['http', { NEXT_PUBLIC_SUPABASE_URL: `http://${REF}.supabase.co` }],
    [
      'credentials',
      { NEXT_PUBLIC_SUPABASE_URL: `https://synthetic@example.invalid@${REF}.supabase.co` },
    ],
    ['path', { NEXT_PUBLIC_SUPABASE_URL: `https://${REF}.supabase.co/rest/v1` }],
    ['query', { NEXT_PUBLIC_SUPABASE_URL: `https://${REF}.supabase.co?project=other` }],
    ['fragment', { NEXT_PUBLIC_SUPABASE_URL: `https://${REF}.supabase.co#other` }],
    ['default port', { NEXT_PUBLIC_SUPABASE_URL: `https://${REF}.supabase.co:443` }],
    ['nondefault port', { NEXT_PUBLIC_SUPABASE_URL: `https://${REF}.supabase.co:444` }],
    ['different domain', { NEXT_PUBLIC_SUPABASE_URL: 'https://example.invalid' }],
  ])('keeps project selection fail-closed: %s', (_label, override) => {
    expect(resolveMobileBillingCapability({ ...configured, ...override })).toEqual(unavailable)
  })

  it.each([
    '',
    '/',
  ])('returns only a public capability for the selected canonical origin%s', (suffix) => {
    const result = resolveMobileBillingCapability({
      ...configured,
      NEXT_PUBLIC_SUPABASE_URL: configured.NEXT_PUBLIC_SUPABASE_URL + suffix,
    })
    expect(result).toEqual({
      provider: 'revenuecat',
      available: true,
      reason: 'provider_configured',
    })
    const output = JSON.stringify(result)
    expect(output).not.toContain(SECRET)
    expect(output).not.toContain(REF)
    expect(output).not.toContain('synthetic_monthly')
  })

  it('reads provider configuration at request time without a cached secret or prior success', () => {
    for (const [key, value] of Object.entries(configured)) vi.stubEnv(key, value)
    expect(loadRevenueCatWebhookConfiguration()?.signingSecret).toBe(SECRET)
    vi.stubEnv('REVENUECAT_WEBHOOK_SIGNING_SECRET', undefined)
    expect(loadRevenueCatWebhookConfiguration()).toBeNull()
  })
})
