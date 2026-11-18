import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import { mobilePathRequiresEntitlement } from './entitlement-service'
import { MobileApiError } from './http'
import { createJourneySocialRoutes } from './journey-social-routes'
import type { MobileRouteRuntime } from './route'

const owner = '19600000-0000-4000-9000-000000000001',
  auth = '19600000-0000-4000-8000-000000000001',
  login = '19600000-0000-4000-a000-000000000001',
  member = '19600000-0000-4000-b000-000000000001',
  operation = '19600000-0000-4000-c000-000000000001'
const token = `${Buffer.from('{}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: auth, session_id: login })).toString('base64url')}.verified-test-signature`
const baseProfile = {
  revision: 1,
  opted_in: true,
  nickname: 'Pessoa A',
  member_id: member,
  moderation: 'active',
}
const command = {
  operation_id: operation,
  expected_revision: 0,
  opted_in: true,
  nickname: 'Pessoa A',
  consent_version: 'journey-social.v1',
}
const paths = {
  profile: '/api/mobile/v1/profile/journey-social',
  ranking: '/api/mobile/v1/journey/ranking',
  blocks: '/api/mobile/v1/profile/journey-social/blocks',
  reports: '/api/mobile/v1/profile/journey-social/reports',
  resolve: '/api/mobile/v1/profile/journey-social/operations/resolve',
}
function harness(enabled = true, activeAccess = true) {
  let calls = 0,
    checks = 0,
    changeAt = 0,
    reply: unknown = baseProfile
  const db = {
    async rpc() {
      calls++
      return { data: reply, error: null }
    },
  } as unknown as ServiceClient
  const context = (): MobileAuthContext => ({
    accessToken: token,
    authUserId: auth,
    userId: owner,
    identity: { id: auth, email: 'qa@example.invalid', emailConfirmedAt: '2026-11-01T00:00:00Z' },
    patient: {
      id: owner,
      authUserId: auth,
      email: 'qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  })
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => db,
    createRequestId: () => 'journey-route-test',
    async authenticate() {
      checks++
      const current = context()
      if (checks === changeAt) current.accessToken = 'replacement'
      return current
    },
    async authorizeEntitlement(_auth, request) {
      if (!activeAccess && mobilePathRequiresEntitlement(new URL(request.url).pathname))
        throw new MobileApiError(402, 'subscription_required', 'Active access required')
    },
  }
  const routes = createJourneySocialRoutes({ enabled: () => enabled }, runtime)
  function request(
    path = paths.profile,
    method = 'GET',
    body?: unknown,
    headers: Record<string, string> = {},
  ) {
    return new Request(`https://unit.invalid${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Journey-Owner': owner,
        'X-Journey-Session': login,
        'Content-Type': 'application/json',
        'Idempotency-Key': `jsocial1:${operation}`,
        ...headers,
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })
  }
  return {
    routes,
    request,
    calls: () => calls,
    change: (at: number) => {
      changeAt = at
    },
    reply: (data: unknown) => {
      reply = data
    },
  }
}
describe('Journey social closed patient routes', () => {
  it('recovers a privacy operation through its own key even after subscription access expires', async () => {
    const f = harness(true, false)
    const data = {
      status: 'fenced',
      operation_id: operation,
      kind: 'profile',
      expected_revision: 0,
      receipt: null,
      profile: baseProfile,
    }
    f.reply(data)
    const result = await f.routes.RESOLVE_POST(
      f.request(
        paths.resolve,
        'POST',
        { kind: 'profile', command },
        { 'Idempotency-Key': `jsocial-resolve1:${operation}` },
      ),
    )
    expect(result.status).toBe(200)
    expect((await result.json()).data).toEqual(data)
    expect(result.headers.get('Cache-Control')).toBe('no-store')
    expect(result.headers.get('X-Journey-Social')).toBe('1')
    expect(f.calls()).toBe(1)
  })
  it('refuses recovery through the original mutation key or an open body/query', async () => {
    const f = harness()
    for (const [path, body, headers] of [
      [paths.resolve, { kind: 'profile', command }, {}],
      [
        paths.resolve,
        { kind: 'profile', command, owner_id: owner },
        { 'Idempotency-Key': `jsocial-resolve1:${operation}` },
      ],
      [
        `${paths.resolve}?limit=1`,
        { kind: 'profile', command },
        { 'Idempotency-Key': `jsocial-resolve1:${operation}` },
      ],
    ] as const) {
      expect((await f.routes.RESOLVE_POST(f.request(path, 'POST', body, headers))).status).toBe(422)
    }
    expect(f.calls()).toBe(0)
  })
  it('retains the feature flag and original-login fence during recovery', async () => {
    const disabled = harness(false)
    expect(
      (
        await disabled.routes.RESOLVE_POST(
          disabled.request(paths.resolve, 'POST', { kind: 'profile', command }),
        )
      ).status,
    ).toBe(503)
    expect(disabled.calls()).toBe(0)
    const changed = harness()
    changed.change(3)
    changed.reply({
      status: 'fenced',
      operation_id: operation,
      kind: 'profile',
      expected_revision: 0,
      receipt: null,
      profile: baseProfile,
    })
    expect(
      (
        await changed.routes.RESOLVE_POST(
          changed.request(
            paths.resolve,
            'POST',
            { kind: 'profile', command },
            { 'Idempotency-Key': `jsocial-resolve1:${operation}` },
          ),
        )
      ).status,
    ).toBe(409)
    expect(changed.calls()).toBe(1)
  })
  it('keeps the disabled feature before any new social RPC', async () => {
    const f = harness(false),
      r = await f.routes.PROFILE_GET(f.request())
    expect(r.status).toBe(503)
    expect(f.calls()).toBe(0)
  })
  it('returns the strict current profile without caching', async () => {
    const f = harness(),
      r = await f.routes.PROFILE_GET(f.request())
    expect(r.status).toBe(200)
    expect((await r.json()).data).toEqual(baseProfile)
    expect(r.headers.get('Cache-Control')).toBe('no-store')
    expect(r.headers.get('X-Journey-Social')).toBe('1')
    expect(f.calls()).toBe(1)
  })
  it('binds a changed owner or login before physical access', async () => {
    for (const key of ['X-Journey-Owner', 'X-Journey-Session']) {
      const f = harness(),
        r = await f.routes.PROFILE_GET(
          f.request(paths.profile, 'GET', undefined, { [key]: member }),
        )
      expect(r.status).toBe(409)
      expect(f.calls()).toBe(0)
    }
  })
  it('does not transfer the original verified token after re-authentication changes', async () => {
    const f = harness()
    f.change(2)
    const r = await f.routes.PROFILE_GET(f.request())
    expect(r.status).toBe(409)
    expect(f.calls()).toBe(0)
  })
  it('does not publish a result when the login changes after the physical RPC', async () => {
    const f = harness()
    f.change(3)
    const r = await f.routes.PROFILE_GET(f.request())
    expect(r.status).toBe(409)
    expect(f.calls()).toBe(1)
  })
  it('applies a participation command once with its matching operation key', async () => {
    const f = harness()
    f.reply({
      status: 'applied',
      receipt: { operation_id: operation, revision: 1, opted_in: true },
      profile: baseProfile,
    })
    const r = await f.routes.PROFILE_PATCH(f.request(paths.profile, 'PATCH', command))
    expect(r.status).toBe(200)
    expect((await r.json()).data.profile).toEqual(baseProfile)
    expect(f.calls()).toBe(1)
  })
  it('refuses extra owner/role fields, mismatched idempotency and duplicate body keys', async () => {
    const f = harness()
    let r = await f.routes.PROFILE_PATCH(
      f.request(paths.profile, 'PATCH', { ...command, actor_id: auth }),
    )
    expect(r.status).toBe(422)
    r = await f.routes.PROFILE_PATCH(
      f.request(paths.profile, 'PATCH', command, { 'Idempotency-Key': 'wrong-key' }),
    )
    expect(r.status).toBe(422)
    const duplicate = new Request(`https://unit.invalid${paths.profile}`, {
      method: 'PATCH',
      headers: f.request().headers,
      body: `{"operation_id":"${operation}","operation_id":"${member}"}`,
    })
    r = await f.routes.PROFILE_PATCH(duplicate)
    expect(r.status).toBe(400)
    expect(f.calls()).toBe(0)
  })
  it('keeps privacy withdrawal accessible under the existing Profile exemption when a subscription expires', async () => {
    const f = harness(true, false)
    f.reply({
      status: 'applied',
      receipt: { operation_id: operation, revision: 2, opted_in: false },
      profile: { ...baseProfile, revision: 2, opted_in: false, nickname: null },
    })
    const r = await f.routes.PROFILE_PATCH(
      f.request(paths.profile, 'PATCH', {
        operation_id: operation,
        expected_revision: 1,
        opted_in: false,
        nickname: null,
        consent_version: null,
      }),
    )
    expect(r.status).toBe(200)
    expect(f.calls()).toBe(1)
  })
  it('retains the normal entitlement gate for the ranking', async () => {
    const f = harness(true, false),
      r = await f.routes.RANKING_GET(f.request(paths.ranking))
    expect(r.status).toBe(402)
    expect(f.calls()).toBe(0)
  })
  it.each([
    '?owner_id=x',
    '?limit=1&limit=2',
    '?cursor={"owner_id":"x"}',
    '?limit=1.5',
  ])('rejects an open/ambiguous ranking query %s', async (query) => {
    const f = harness(),
      r = await f.routes.RANKING_GET(f.request(paths.ranking + query))
    expect(r.status).toBe(422)
    expect(f.calls()).toBe(0)
  })
  it('refuses an operation selected through another path or method', async () => {
    const f = harness()
    expect((await f.routes.RANKING_GET(f.request(paths.profile))).status).toBe(422)
    expect((await f.routes.PROFILE_GET(f.request(paths.profile, 'POST'))).status).toBe(422)
    expect(f.calls()).toBe(0)
  })
})
