import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import { createNutritionWindowRoutes } from './nutrition-window-routes'
import type { MobileRouteRuntime } from './route'

const AUTH = 'a2222222-2222-4222-8222-222222222222',
  OWNER = 'a1111111-1111-4111-8111-111111111111'
const who = (): MobileAuthContext => ({
  accessToken: 'synthetic',
  authUserId: AUTH,
  userId: OWNER,
  identity: { id: AUTH, email: null, emailConfirmedAt: '2026-11-01T00:00:00Z' },
  patient: {
    id: OWNER,
    authUserId: AUTH,
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
})
function harness(change = false, deny = false) {
  let authCalls = 0,
    reads = 0,
    entitlementCalls = 0
  const runtime: MobileRouteRuntime = {
    authenticate: async () => {
      const a = who()
      if (++authCalls > 1 && change) {
        a.userId = AUTH
        a.patient.id = AUTH
      }
      return a
    },
    authorizeEntitlement: async () => {
      if (++entitlementCalls > 1 && deny)
        throw new MobileApiError(403, 'not_entitled', 'Unavailable')
    },
    createServiceClient: () => ({}) as ReturnType<MobileRouteRuntime['createServiceClient']>,
    createRequestId: () => 'nutrition-read-test',
  }
  const route = createNutritionWindowRoutes(
    {
      service: () => ({
        read: async () => {
          reads++
          return { schema: 'controlled-nutrition-observation' }
        },
      }),
    },
    runtime,
  )
  return { route, counts: () => ({ authCalls, reads, entitlementCalls }) }
}
describe('Nutrition GET uses existing-account readonly identity and final scope fence', () => {
  it('reauthenticates and rechecks entitlement before publishing the owned read', async () => {
    const f = harness(),
      r = await f.route.GET(
        new Request(
          'https://unit.invalid/api/mobile/v1/nutrition/window?clinical_policy=current_clinical_v1',
        ),
      )
    expect(r.status).toBe(200)
    expect(f.counts()).toEqual({ authCalls: 2, reads: 1, entitlementCalls: 2 })
  })
  it('refuses unknown/duplicate query keys without any data read', async () => {
    for (const q of [
      'date=2026-11-04&date=2026-11-05',
      'owner=another',
      'clinical_policy=legacy',
    ]) {
      const f = harness(),
        r = await f.route.GET(
          new Request(`https://unit.invalid/api/mobile/v1/nutrition/window?${q}`),
        )
      expect(r.status).toBeGreaterThanOrEqual(400)
      expect(f.counts().reads).toBe(0)
    }
  })
  it('withholds a late payload after patient or entitlement changes', async () => {
    for (const [change, deny] of [
      [true, false],
      [false, true],
    ]) {
      const f = harness(change, deny),
        r = await f.route.GET(
          new Request(
            'https://unit.invalid/api/mobile/v1/nutrition/window?clinical_policy=current_clinical_v1',
          ),
        )
      expect(r.status).toBeGreaterThanOrEqual(400)
      expect(f.counts().reads).toBe(1)
      expect(await r.text()).not.toContain('controlled-nutrition-observation')
    }
  })
})
