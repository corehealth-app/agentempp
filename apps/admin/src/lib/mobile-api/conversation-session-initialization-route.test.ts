import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { createConversationSessionInitializationRoute } from './conversation-session-initialization-route'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

function fixture() {
  const db = {} as ServiceClient,
    initialize = vi.fn(async () => ({
      schema: 'conversation.session.v1' as const,
      owner_id: candidateAuth.userId,
      auth_user_id: candidateAuth.authUserId,
      epoch: '50000000-0000-4000-8000-000000000001',
      observed_at: '2026-11-16T01:00:00.000001Z',
      meal_command_protocol: 'conversation.command.v1' as const,
    })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      createServiceClient: () => db,
      authenticate: vi.fn(async () => candidateAuth),
      authorizeEntitlement: vi.fn(async () => {}),
      createRequestId: () => 'session-initialization-test',
    }
  return {
    initialize,
    enabled,
    runtime,
    route: createConversationSessionInitializationRoute({ enabled, initialize }, runtime),
  }
}
function request(
  body: unknown = { schema: 'conversation.session-initialization.v1' },
  query = '',
  key = 'conversation-session-initialize-v1',
) {
  return new Request(`https://app.invalid/api/mobile/v1/conversation/session${query}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
    body: JSON.stringify(body),
  })
}
describe('explicit conversation session initialization route', () => {
  it('requires real Auth/entitlement and exposes only the closed initialization POST', async () => {
    const f = fixture(),
      response = await f.route(request())
    expect(response.status).toBe(200)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-command-v1')
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(f.initialize).toHaveBeenCalledWith(expect.anything(), candidateAuth)
  })
  it.each([
    [
      { schema: 'conversation.session-initialization.v1', owner: candidateAuth.userId },
      '',
      'conversation-session-initialize-v1',
    ],
    [{ schema: 'other' }, '', 'conversation-session-initialize-v1'],
    [
      { schema: 'conversation.session-initialization.v1' },
      '?owner=foreign',
      'conversation-session-initialize-v1',
    ],
    [{ schema: 'conversation.session-initialization.v1' }, '', 'other-key'],
  ])('refuses caller-supplied initialization authority %j', async (body, query, key) => {
    const f = fixture()
    expect((await f.route(request(body, query, key))).status).toBe(422)
    expect(f.initialize).not.toHaveBeenCalled()
  })
  it('does not initialize without entitlement', async () => {
    const f = fixture()
    vi.mocked(f.runtime.authorizeEntitlement).mockRejectedValue(
      new MobileApiError(402, 'subscription_required', 'Unavailable'),
    )
    expect((await f.route(request())).status).toBe(402)
    expect(f.initialize).not.toHaveBeenCalled()
  })
  it('keeps initialization disabled on the existing capability boundary', async () => {
    const f = fixture()
    f.enabled.mockReturnValue(false)
    expect((await f.route(request())).status).toBe(503)
    expect(f.initialize).not.toHaveBeenCalled()
  })
})
