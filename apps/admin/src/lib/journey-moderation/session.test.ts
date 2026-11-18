import { describe, expect, it } from 'vitest'
import { createJourneyModerationSession } from './session'

const actor = '19900000-0000-4000-8000-000000000004'
const login = '19900000-0000-4000-a000-000000000004'
const other = '19900000-0000-4000-8000-000000000005'
const issuer = 'https://staging.example.invalid/auth/v1'
const now = 1795037700
function jwt(changes: Record<string, unknown> = {}) {
  return `header.${Buffer.from(JSON.stringify({ iss: issuer, sub: actor, session_id: login, exp: now + 60, aud: 'authenticated', role: 'authenticated', is_anonymous: false, ...changes })).toString('base64url')}.signature`
}
function fixture() {
  let token: string | null = jwt()
  let user: string | null = actor
  let role: unknown = { id: actor, role: 'operations_admin' }
  const events: string[] = []
  const deps = {
    enabled: () => true,
    expectedIssuer: issuer,
    now: () => now,
    readCookieAccessToken: async () => {
      events.push('cookie')
      return token
    },
    verifyAccessToken: async (value: string) => {
      events.push(value === token ? 'verify-exact-token' : 'WRONG-TOKEN')
      return user ? { id: user } : null
    },
    readOperatorRole: async (id: string) => {
      events.push(`role:${id}`)
      return role
    },
    createRPCPort: () => ({
      rpc: async () => {
        events.push('physical-gateway')
        return { data: { entries: [], next_cursor: null }, error: null }
      },
    }),
  }
  return {
    deps,
    events,
    setToken: (value: string | null) => {
      token = value
    },
    setUser: (value: string | null) => {
      user = value
    },
    setRole: (value: unknown) => {
      role = value
    },
  }
}
describe('original authenticated operational session binding', () => {
  it('verifies the exact cookie token, checks current role and never publishes that token', async () => {
    const f = fixture()
    const bound = await createJourneyModerationSession(f.deps)
    expect(Object.keys(bound).sort()).toEqual(['identity', 'service'])
    expect(bound.identity).toEqual({ actor, login })
    await expect(bound.service.queue({ limit: 20, cursor: null })).resolves.toEqual({
      entries: [],
      next_cursor: null,
    })
    expect(f.events).toEqual([
      'cookie',
      'verify-exact-token',
      `role:${actor}`,
      'cookie',
      'verify-exact-token',
      `role:${actor}`,
      'physical-gateway',
      'cookie',
      'verify-exact-token',
      `role:${actor}`,
    ])
  })
  it.each([
    'support',
    'nutrition_admin',
    'content_editor',
    'unknown',
  ])('denies non-operational role %s without creating a physical operation', async (role) => {
    const f = fixture()
    f.setRole({ id: actor, role })
    await expect(createJourneyModerationSession(f.deps)).rejects.toMatchObject({
      code: 'forbidden',
    })
    expect(f.events).not.toContain('physical-gateway')
  })
  it('is off before all cookie/Auth/SQL work by default', async () => {
    const f = fixture()
    f.deps.enabled = () => false
    await expect(createJourneyModerationSession(f.deps)).rejects.toMatchObject({
      code: 'unavailable',
    })
    expect(f.events).toEqual([])
  })
  it.each([
    { exp: now },
    { sub: other },
    { session_id: 'missing' },
    { iss: 'https://other.invalid/auth/v1' },
    { aud: 'service_role' },
    { role: 'service_role' },
    { is_anonymous: true },
    { nbf: now + 1 },
  ])('denies invalid verified identity/claims: %j', async (changes) => {
    const f = fixture()
    f.setToken(jwt(changes))
    await expect(createJourneyModerationSession(f.deps)).rejects.toMatchObject({
      code: 'unauthorized',
    })
    expect(f.events).not.toContain('physical-gateway')
  })
  it('a cookie token alone never authorizes an operator', async () => {
    const f = fixture()
    f.setUser(null)
    await expect(createJourneyModerationSession(f.deps)).rejects.toMatchObject({
      code: 'unauthorized',
    })
    expect(f.events.some((e) => e.startsWith('role:'))).toBe(false)
  })
  it('role row must belong to the verified user', async () => {
    const f = fixture()
    f.setRole({ id: other, role: 'master_admin' })
    await expect(createJourneyModerationSession(f.deps)).rejects.toMatchObject({
      code: 'forbidden',
    })
  })
  it('does not transfer a bound operation to a new login of the same operator', async () => {
    const f = fixture()
    const bound = await createJourneyModerationSession(f.deps)
    f.setToken(jwt({ session_id: '19900000-0000-4000-a000-000000000005' }))
    await expect(bound.service.queue({ limit: 20, cursor: null })).rejects.toMatchObject({
      code: 'unauthorized',
    })
    expect(f.events).not.toContain('physical-gateway')
  })
  it('checks role again after binding instead of relying on cached page access', async () => {
    const f = fixture()
    const bound = await createJourneyModerationSession(f.deps)
    f.setRole({ id: actor, role: 'support' })
    await expect(bound.service.queue({ limit: 20, cursor: null })).rejects.toMatchObject({
      code: 'forbidden',
    })
    expect(f.events).not.toContain('physical-gateway')
  })
  it('clears admission on cookie logout', async () => {
    const f = fixture()
    const bound = await createJourneyModerationSession(f.deps)
    f.setToken(null)
    await expect(bound.service.queue({ limit: 20, cursor: null })).rejects.toMatchObject({
      code: 'unauthorized',
    })
    expect(f.events).not.toContain('physical-gateway')
  })
})
