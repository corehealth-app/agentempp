import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import { updateMe } from './commands'

const auth: MobileAuthContext = {
  accessToken: 'token',
  authUserId: 'auth-1',
  userId: 'patient-1',
  identity: {
    id: 'auth-1',
    email: 'patient@example.com',
    emailConfirmedAt: '2026-07-20T00:00:00Z',
  },
  patient: {
    id: 'patient-1',
    authUserId: 'auth-1',
    email: 'patient@example.com',
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: null,
    status: 'active',
  },
}

describe('mobile profile commands', () => {
  it('scopes profile updates to both patient and auth identities', async () => {
    const filters: Array<[string, string]> = []
    let updates: Record<string, unknown> = {}
    const builder = {
      eq(column: string, value: string) {
        filters.push([column, value])
        return this
      },
      select() {
        return this
      },
      async maybeSingle() {
        return {
          data: {
            id: 'patient-1',
            auth_user_id: 'auth-1',
            email: 'patient@example.com',
            name: null,
            locale: 'en-US',
            timezone: 'America/New_York',
            country: 'US',
            status: 'active',
          },
          error: null,
        }
      },
    }
    const supabase = {
      from() {
        return {
          update(value: Record<string, unknown>) {
            updates = value
            return builder
          },
        }
      },
    }

    await updateMe(supabase as never, auth, {
      locale: 'en-US',
      timezone: 'America/New_York',
      country: 'US',
    })

    expect(filters).toEqual([
      ['id', 'patient-1'],
      ['auth_user_id', 'auth-1'],
    ])
    expect(updates).toMatchObject({ country: 'US', country_confirmed: true })
  })
})
