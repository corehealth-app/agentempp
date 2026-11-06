import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationMealQuestionReadRoutes } from './conversation-meal-question-read-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

function setup() {
  const f = replyFixture('parent_head'),
    data = { schema: 'conversation.meal-question-read.v1', status: 'needs_reply' },
    read = vi.fn().mockResolvedValue(data),
    service = vi.fn(() => ({ read })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      authenticate: vi.fn(async () => f.auth),
      authorizeEntitlement: vi.fn(async () => {}),
      createServiceClient: () => ({}) as ServiceClient,
      createRequestId: () => 'synthetic-question-request',
    },
    routes = createConversationMealQuestionReadRoutes({ enabled, service }, runtime),
    run = (request: Request) =>
      routes.GET(request, { params: Promise.resolve({ commandId: f.identity.parentCommandId }) }),
    request = (query = `?parent_input_hash=${f.identity.parentInputHash}`) =>
      new Request(
        `https://app.invalid/api/mobile/v1/conversation/commands/${f.identity.parentCommandId}/replies${query}`,
        {
          headers: {
            Authorization: 'Bearer synthetic-token',
            'X-Conversation-Owner': f.identity.ownerId,
            'X-Conversation-Epoch': f.identity.epoch,
          },
        },
      )
  return { ...f, data, read, service, enabled, runtime, routes, run, request }
}

describe('parent-only meal question GET route', () => {
  it('uses Auth/entitlement and the exact parent hash query with no-store meal-question-v1', async () => {
    const f = setup(),
      response = await f.run(f.request())
    expect(response.status).toBe(200)
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-question-v1')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect((await response.json()).data).toEqual(f.data)
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledWith(f.auth, f.identity.parentCommandId, f.identity.epoch, {
      parent_input_hash: f.identity.parentInputHash,
    })
    expect(Object.keys(f.routes)).toEqual(['GET'])
  })

  it.each([
    '',
    '?parent_input_hash=a',
    '?parent_input_hash=',
    '?unknown=1',
    '?reply_input_hash=aa',
    `?parent_input_hash=${'a'.repeat(64)}&parent_input_hash=${'b'.repeat(64)}`,
    `?parent_input_hash=${'a'.repeat(64)}&reply_input_hash=${'b'.repeat(64)}`,
  ])('rejects missing, duplicate or extra query %s before constructing a reader', async (query) => {
    const f = setup()
    expect((await f.run(f.request(query))).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })

  it.each(['X-Conversation-Owner', 'X-Conversation-Epoch'])('requires %s', async (header) => {
    const f = setup(),
      request = f.request()
    request.headers.delete(header)
    expect((await f.run(request)).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })

  it('rejects another owner and an invalid parent before a lookup', async () => {
    const f = setup(),
      request = f.request()
    request.headers.set('X-Conversation-Owner', f.auth.authUserId)
    expect((await f.run(request)).status).toBe(409)
    expect(
      (await f.routes.GET(f.request(), { params: Promise.resolve({ commandId: 'invalid' }) }))
        .status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })

  it('preserves the capability OFF and actual Auth/entitlement failures', async () => {
    const f = setup()
    f.enabled.mockReturnValue(false)
    expect((await f.run(f.request())).status).toBe(503)
    vi.mocked(f.runtime.authenticate).mockRejectedValue(
      new MobileApiError(401, 'invalid_access_token', 'Unavailable'),
    )
    expect((await f.run(f.request())).status).toBe(401)
    expect(f.service).not.toHaveBeenCalled()
  })

  it('exposes the new parent GET through Admin and BFF without replacing POST or child GET', () => {
    const admin = readFileSync(
        new URL(
          '../../app/api/mobile/v1/conversation/commands/[commandId]/replies/route.ts',
          import.meta.url,
        ),
        'utf8',
      ),
      bff = readFileSync(
        new URL(
          '../../../../mobile-bff/src/app/api/mobile/v1/conversation/commands/[commandId]/replies/route.ts',
          import.meta.url,
        ),
        'utf8',
      ),
      child = readFileSync(
        new URL(
          '../../app/api/mobile/v1/conversation/commands/[commandId]/replies/[replyId]/route.ts',
          import.meta.url,
        ),
        'utf8',
      )
    expect(admin).toContain('export const POST = createConversationMealReplyPublicRoutes().POST')
    expect(admin).toContain('export const GET = createConversationMealQuestionReadRoutes().GET')
    expect(bff).toMatch(/export \{ GET, POST \}/)
    expect(child).toContain('export const GET = createConversationMealReplyPublicRoutes().GET')
  })
})
