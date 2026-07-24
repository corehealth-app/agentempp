import { describe, expect, it } from 'vitest'
import { isSelfAuthenticatedApiPath } from './public-api-path'

describe('self-authenticated API paths', () => {
  it('lets the mobile BFF validate bearer auth instead of redirecting to admin login', () => {
    expect(isSelfAuthenticatedApiPath('/api/mobile/v1/me')).toBe(true)
    expect(isSelfAuthenticatedApiPath('/api/webhooks/revenuecat')).toBe(true)
    expect(isSelfAuthenticatedApiPath('/api/inngest')).toBe(true)
    expect(isSelfAuthenticatedApiPath('/api/admin/send-message')).toBe(true)
    expect(isSelfAuthenticatedApiPath('/api/stripe/checkout')).toBe(false)
  })
})
