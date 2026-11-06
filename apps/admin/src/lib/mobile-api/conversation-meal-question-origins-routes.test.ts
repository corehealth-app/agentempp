import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import type { ConversationMealQuestionOriginsPage } from './conversation-meal-question-origins'
import { createConversationMealQuestionOriginsRoutes } from './conversation-meal-question-origins-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

function setup() {
  const f = replyFixture('parent_head'),
    data: ConversationMealQuestionOriginsPage = {
      schema: 'conversation.meal-question-origins.v1',
      mode: 'lookup_only',
      items: [],
      auth_user_id: f.auth.authUserId,
      owner_id: f.identity.ownerId,
      epoch: f.identity.epoch,
      observed_at: f.state.observed_at,
      has_more: false,
      next_cursor: null,
    },
    read = vi.fn(async () => data),
    service = vi.fn(() => ({ read })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      authenticate: vi.fn(async () => f.auth),
      authorizeEntitlement: vi.fn(async () => {}),
      createServiceClient: () => ({}) as ServiceClient,
      createRequestId: () => 'unit-origin-request',
    },
    routes = createConversationMealQuestionOriginsRoutes({ enabled, service }, runtime),
    request = (query = '') =>
      new Request(`https://app.invalid/api/mobile/v1/conversation/intakes${query}`, {
        headers: {
          Authorization: 'Bearer unit-token',
          'X-Conversation-Owner': f.identity.ownerId,
          'X-Conversation-Epoch': f.identity.epoch,
        },
      })
  return { ...f, data, read, service, enabled, runtime, routes, request }
}
describe('owned meal origin discovery GET', () => {
  it('observes Auth and entitlement with no-store and default bounded query', async () => {
    const f = setup(),
      response = await f.routes.GET(f.request())
    expect(response.status).toBe(200)
    expect(response.headers.get('X-Conversation-Protocol')).toBe('intake-question-origins-v1')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect((await response.json()).data).toEqual(f.data)
    expect(f.read).toHaveBeenCalledWith(f.auth, f.identity.epoch, { limit: 10, cursor: null })
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(Object.keys(f.routes)).toEqual(['GET'])
  })
  it('passes an explicit bounded page without inspecting or changing its cursor', async () => {
    const f = setup()
    expect((await f.routes.GET(f.request('?limit=25&cursor=canonical-test-cursor'))).status).toBe(
      200,
    )
    expect(f.read).toHaveBeenCalledWith(f.auth, f.identity.epoch, {
      limit: 25,
      cursor: 'canonical-test-cursor',
    })
  })
  it.each([
    '?limit=0',
    '?limit=26',
    '?limit=1.5',
    '?limit=01',
    '?limit=',
    '?unknown=1',
    '?limit=2&limit=3',
    '?cursor=',
    '?cursor=a&cursor=b',
    '?parent_input_hash=aa',
  ])('refuses malformed or duplicate query %s before reading', async (query) => {
    const f = setup()
    expect((await f.routes.GET(f.request(query))).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'X-Conversation-Owner',
    'X-Conversation-Epoch',
  ])('requires the original %s observation', async (name) => {
    const f = setup(),
      request = f.request()
    request.headers.delete(name)
    expect((await f.routes.GET(request)).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('refuses a different patient, capability OFF, and expired Auth before reading', async () => {
    const f = setup(),
      request = f.request()
    request.headers.set('X-Conversation-Owner', f.auth.authUserId)
    expect((await f.routes.GET(request)).status).toBe(409)
    f.enabled.mockReturnValue(false)
    expect((await f.routes.GET(f.request())).status).toBe(503)
    vi.mocked(f.runtime.authenticate).mockRejectedValue(
      new MobileApiError(401, 'invalid_access_token', 'Unavailable'),
    )
    expect((await f.routes.GET(f.request())).status).toBe(401)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('adds GET alongside the original intake POST in both actual app surfaces', () => {
    const admin = readFileSync(
        new URL('../../app/api/mobile/v1/conversation/intakes/route.ts', import.meta.url),
        'utf8',
      ),
      bff = readFileSync(
        new URL(
          '../../../../mobile-bff/src/app/api/mobile/v1/conversation/intakes/route.ts',
          import.meta.url,
        ),
        'utf8',
      )
    expect(admin).toContain('export const POST = createConversationIntakeRoutes().POST')
    expect(admin).toContain('export const GET = createConversationMealQuestionOriginsRoutes().GET')
    expect(bff).toMatch(/export \{ GET, POST \}/)
  })
})
