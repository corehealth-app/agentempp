import { beforeEach, describe, expect, it, vi } from 'vitest'

const state = vi.hoisted(() => ({
  token: '',
  verified: true,
  role: 'operations_admin',
  calls: [] as string[],
}))
vi.mock('server-only', () => ({}))
vi.mock('@/lib/supabase/server', () => ({
  createClient: async () => {
    state.calls.push('create-cookie-client')
    return {
      auth: {
        getSession: async () => ({ data: { session: { access_token: state.token } }, error: null }),
        getUser: async (token: string) => {
          state.calls.push(token === state.token ? 'verify-exact-token' : 'WRONG-TOKEN')
          return {
            data: { user: state.verified ? { id: '19900000-0000-4000-8000-000000000004' } : null },
            error: null,
          }
        },
      },
      from: (table: string) => ({
        select: (fields: string) => ({
          eq: (key: string, id: string) => ({
            maybeSingle: async () => {
              state.calls.push(`${table}:${fields}:${key}:${id}`)
              return { data: { id, role: state.role }, error: null }
            },
          }),
        }),
      }),
    }
  },
  createServiceClient: () => {
    state.calls.push('create-service-client')
    return {
      rpc: async (name: string) => {
        state.calls.push(name)
        return { data: { entries: [], next_cursor: null }, error: null }
      },
    }
  },
}))

import { loadJourneyModerationOperator } from './server'

beforeEach(() => {
  vi.stubEnv('MOBILE_JOURNEY_SOCIAL_ENABLED', 'true')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://staging.example.invalid')
  const body = {
    sub: '19900000-0000-4000-8000-000000000004',
    session_id: '19900000-0000-4000-a000-000000000004',
    iss: 'https://staging.example.invalid/auth/v1',
    aud: 'authenticated',
    role: 'authenticated',
    exp: Math.floor(Date.now() / 1000) + 300,
  }
  state.token = `header.${Buffer.from(JSON.stringify(body)).toString('base64url')}.signature`
  state.verified = true
  state.role = 'operations_admin'
  state.calls = []
})
describe('real admin dependency composition', () => {
  it('keeps capability off before accessing cookies or a service client', async () => {
    vi.stubEnv('MOBILE_JOURNEY_SOCIAL_ENABLED', '')
    await expect(loadJourneyModerationOperator()).rejects.toMatchObject({ code: 'unavailable' })
    expect(state.calls).toEqual([])
  })
  it('uses verified cookie Auth and a role lookup before the service gateway', async () => {
    const bound = await loadJourneyModerationOperator()
    await expect(bound.service.queue({ limit: 20, cursor: null })).resolves.toEqual({
      entries: [],
      next_cursor: null,
    })
    expect(state.calls[0]).toBe('create-cookie-client')
    const roleRead = state.calls.indexOf(
      'admin_users:id,role:id:19900000-0000-4000-8000-000000000004',
    )
    expect(roleRead).toBeGreaterThan(state.calls.indexOf('verify-exact-token'))
    expect(state.calls.indexOf('create-service-client')).toBeGreaterThan(roleRead)
    expect(state.calls.filter((x) => x === 'journey_social_operator_authenticated')).toHaveLength(1)
    expect(JSON.stringify(bound.identity)).not.toContain(state.token)
  })
  it('does not create a service client for an unverified cookie', async () => {
    state.verified = false
    await expect(loadJourneyModerationOperator()).rejects.toMatchObject({ code: 'unauthorized' })
    expect(state.calls).not.toContain('create-service-client')
  })
  it('does not create a service client for a non-operational admin', async () => {
    state.role = 'support'
    await expect(loadJourneyModerationOperator()).rejects.toMatchObject({ code: 'forbidden' })
    expect(state.calls).not.toContain('create-service-client')
  })
})
