import { describe, expect, it } from 'vitest'
import { loadPrivateConfirmedMealState, privateConfirmedMealVersion } from './confirmed-meal-read'
import { createConfirmedMealRoutes } from './confirmed-meal-route-handlers'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import { anchorID, auth, fixture, now, sdk } from './testing/confirmed-meal-fixtures'

function setup(rejectAccess = false) {
  const rows = fixture()
  const { client, requests } = sdk(rows)
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => client,
    createRequestId: () => 'synthetic-route-id',
    authenticate: async () => auth,
    authorizeEntitlement: async () => {
      if (rejectAccess) throw new MobileApiError(402, 'subscription_required', 'Access required')
    },
  }
  return { rows, client, requests, routes: createConfirmedMealRoutes(runtime, () => now) }
}
const params = { params: Promise.resolve({ id: anchorID }) }
function request(method: string, body?: unknown) {
  return new Request(`https://app.invalid/api/mobile/v1/meal-records/${anchorID}`, {
    method,
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'synthetic-route-key' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
}

describe('confirmed meal HTTP handlers', () => {
  it('GET returns the official private-safe DTO with request metadata', async () => {
    const { routes } = setup()
    const response = await routes.GET(request('GET'), params)
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data).toMatchObject({ record_id: anchorID, editable: true, scope: 'group' })
    expect(body.meta).toEqual({ api_version: 'v1', request_id: 'synthetic-route-id' })
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(JSON.stringify(body)).not.toContain('private-group')
  })

  it.each([
    'PATCH',
    'DELETE',
  ] as const)('refuses extra client authority in %s before any read or mutation', async (method) => {
    const { routes, requests } = setup()
    const input = {
      expected_version: `v1:${'a'.repeat(64)}`,
      item_ids: [anchorID],
      ...(method === 'PATCH' ? { items: [{ food_name: 'iogurte natural', quantity_g: 170 }] } : {}),
      expected_state: {},
    }
    const response = await routes[method](request(method, input), params)
    expect(response.status).toBe(422)
    expect((await response.json()).error.code).toBe('validation_failed')
    expect(requests).toHaveLength(0)
  })

  it('refuses missing Idempotency-Key before reading a valid DELETE command', async () => {
    const { routes, requests } = setup()
    const req = request('DELETE', {
      expected_version: `v1:${'a'.repeat(64)}`,
      item_ids: [anchorID],
    })
    req.headers.delete('Idempotency-Key')
    const response = await routes.DELETE(req, params)
    expect(response.status).toBe(400)
    expect((await response.json()).error.code).toBe('missing_idempotency_key')
    expect(requests).toHaveLength(0)
  })

  it.each(['GET', 'PATCH', 'DELETE'] as const)('keeps entitlement guard on %s', async (method) => {
    const { routes, requests } = setup(true)
    const response = await routes[method](request(method), params)
    expect(response.status).toBe(402)
    expect(requests).toHaveLength(0)
  })

  it('does not treat a confirmed meal ID as a pending-registration operation', async () => {
    const { client, routes, requests } = setup()
    const state = await loadPrivateConfirmedMealState(client, auth, anchorID)
    requests.length = 0
    const response = await routes.PATCH(
      request('PATCH', {
        expected_version: privateConfirmedMealVersion(state),
        item_ids: [anchorID],
        items: [{ food_name: 'iogurte natural', quantity_g: 0.001 }],
      }),
      params,
    )
    expect(response.status).toBe(422)
    expect((await response.json()).error.code).toBe('MEAL_QUANTITY_NOT_REPRESENTABLE')
    expect(
      requests.some((entry) => entry.table === 'pending_registrations' || entry.method === 'POST'),
    ).toBe(false)
  })
})
