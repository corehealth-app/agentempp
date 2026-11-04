import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { mobileSuccess } from './http'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import { auth } from './testing/confirmed-meal-fixtures'

const patient = auth.userId
const other = 'c1110000-0000-4000-8000-000000000099'
const routes = [
  ['POST', '/media'],
  ['GET', `/media/${other}`],
  ['POST', `/media/${other}/complete`],
  ['POST', `/media/${other}/process`],
  ['DELETE', `/media/${other}`],
] as const
function setup() {
  const handler = vi.fn(async () => mobileSuccess({ ok: true }, 'request-id'))
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn().mockResolvedValue(auth),
    authorizeEntitlement: vi.fn().mockResolvedValue(undefined),
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'request-id',
  }
  return { handler, runtime, route: createMobileRoute(handler, runtime) }
}
describe('explicit conversation patient precondition for media operations', () => {
  it.each(
    routes,
  )('refuses a remapped patient before %s %s reaches the handler', async (method, path) => {
    const f = setup()
    const response = await f.route(
      new Request(`https://example.test/api/mobile/v1${path}`, {
        method,
        headers: { 'X-Conversation-Owner': other },
      }),
    )
    expect(response.status).toBe(409)
    expect((await response.json()).error.code).toBe('conversation_patient_changed')
    expect(f.handler).not.toHaveBeenCalled()
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
  })
  it.each(routes)('allows matching original patient for %s %s', async (method, path) => {
    const f = setup()
    const response = await f.route(
      new Request(`https://example.test/api/mobile/v1${path}`, {
        method,
        headers: { 'X-Conversation-Owner': patient },
      }),
    )
    expect(response.status).toBe(200)
    expect(f.handler).toHaveBeenCalledTimes(1)
  })
  it.each([
    '',
    'not-a-uuid',
    `${patient},${patient}`,
    auth.authUserId,
  ])('rejects an invalid or Auth-subject header without accepting it as authority: %s', async (value) => {
    const f = setup()
    const response = await f.route(
      new Request('https://example.test/api/mobile/v1/media', {
        method: 'POST',
        headers: { 'X-Conversation-Owner': value },
      }),
    )
    expect([409, 422]).toContain(response.status)
    expect(f.handler).not.toHaveBeenCalled()
  })
  it('preserves old media clients without the optional header and unrelated routes', async () => {
    const f = setup()
    expect(
      (await f.route(new Request('https://example.test/api/mobile/v1/media', { method: 'POST' })))
        .status,
    ).toBe(200)
    expect(
      (
        await f.route(
          new Request('https://example.test/api/mobile/v1/today', {
            headers: { 'X-Conversation-Owner': 'irrelevant' },
          }),
        )
      ).status,
    ).toBe(200)
    expect(f.handler).toHaveBeenCalledTimes(2)
  })
})
