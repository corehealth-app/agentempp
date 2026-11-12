import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationMealLinkedOriginRoutes } from './conversation-meal-linked-origin-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

function setup() {
  const f = replyFixture('saved'),
    read = vi.fn().mockResolvedValue({ schema: 'conversation.meal-linked-origin.v1' }),
    service = vi.fn(() => ({ read })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      authenticate: vi.fn(async () => f.auth),
      authorizeEntitlement: vi.fn(async () => {}),
      createServiceClient: () => ({}) as ServiceClient,
      createRequestId: () => 'synthetic-origin-read',
    },
    routes = createConversationMealLinkedOriginRoutes({ service, enabled }, runtime),
    request = () =>
      new Request(
        `https://app.invalid/api/mobile/v1/conversation/meal-commands/${f.identity.replyId}/origin`,
        {
          headers: {
            Authorization: 'Bearer synthetic-token',
            'X-Conversation-Owner': f.identity.ownerId,
            'X-Conversation-Epoch': f.identity.epoch,
          },
        },
      ),
    run = (req = request()) =>
      routes.GET(req, { params: Promise.resolve({ commandId: f.identity.replyId }) })
  return { ...f, read, service, enabled, runtime, routes, request, run }
}
describe('owned linked origin read route', () => {
  it('uses read-only Auth and entitlement and returns a closed uncached GET protocol', async () => {
    const f = setup(),
      response = await f.run()
    expect(response.status).toBe(200)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-linked-origin-v1')
    expect(Object.keys(f.routes)).toEqual(['GET'])
    expect(f.read).toHaveBeenCalledWith(f.auth, f.identity.replyId, f.identity.epoch)
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(2)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
  })
  it.each([
    'X-Conversation-Owner',
    'X-Conversation-Epoch',
  ])('requires %s before lookup', async (header) => {
    const f = setup(),
      req = f.request()
    req.headers.delete(header)
    expect((await f.run(req)).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects a foreign owner, malformed child or any invented hash query', async () => {
    const f = setup(),
      req = f.request()
    req.headers.set('X-Conversation-Owner', f.auth.authUserId)
    expect((await f.run(req)).status).toBe(409)
    expect(
      (await f.routes.GET(f.request(), { params: Promise.resolve({ commandId: 'invalid' }) }))
        .status,
    ).toBe(422)
    const withQuery = new Request(`${f.request().url}?input_hash=${'0'.repeat(64)}`, {
      headers: f.request().headers,
    })
    expect((await f.run(withQuery)).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('retains flag OFF and authentication failure without looking up an origin', async () => {
    const f = setup()
    f.enabled.mockReturnValue(false)
    expect((await f.run()).status).toBe(503)
    vi.mocked(f.runtime.authenticate).mockRejectedValue(
      new MobileApiError(401, 'invalid_access_token', 'Unavailable'),
    )
    expect((await f.run()).status).toBe(401)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('discards completed facts if the original authenticated mapping changed before publication', async () => {
    const f = setup()
    vi.mocked(f.runtime.authenticate)
      .mockResolvedValueOnce(f.auth)
      .mockResolvedValueOnce({ ...f.auth, accessToken: 'different-token' })
    expect((await f.run()).status).toBe(409)
    expect(f.read).toHaveBeenCalledTimes(1)
  })
})
