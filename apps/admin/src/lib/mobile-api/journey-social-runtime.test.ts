import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { authenticateJourneySocialPatient, journeySocialOwner } from './journey-social-runtime'

const owner = '19800000-0000-4000-8000-000000000001',
  auth = '19800000-0000-4000-8000-000000000002'
function fixture() {
  const calls: string[] = []
  const user = { id: auth, email: 'qa@example.invalid', email_confirmed_at: '2026-11-18T00:00:00Z' }
  const patient = {
    id: owner,
    auth_user_id: auth,
    email: user.email,
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    country_confirmed: true,
    status: 'active',
  }
  let admin: unknown = null,
    queryError: unknown = null
  const db = {
    auth: {
      async getUser(token: string) {
        calls.push(`verify:${token}`)
        return { data: { user }, error: null }
      },
    },
    from(table: string) {
      calls.push(`from:${table}`)
      return {
        select() {
          return {
            eq(key: string, value: string) {
              calls.push(`where:${table}:${key}:${value}`)
              return {
                async maybeSingle() {
                  return { data: table === 'users' ? patient : admin, error: queryError }
                },
              }
            },
          }
        },
      }
    },
    rpc() {
      throw Error('No bootstrap, epoch, lease, or other RPC is allowed in authentication')
    },
  } as unknown as ServiceClient
  return {
    db,
    calls,
    user,
    patient,
    setAdmin: (value: unknown) => {
      admin = value
    },
    failQuery: () => {
      queryError = { message: 'private database message' }
    },
  }
}
const request = () =>
  new Request('https://unit.invalid/api/mobile/v1/profile/journey-social', {
    headers: { Authorization: 'Bearer verified-test-token' },
  })
describe('Journey existing-patient runtime independent of clinical state', () => {
  it('verifies real SDK identity and reads only existing patient and admin membership', async () => {
    const f = fixture(),
      value = await authenticateJourneySocialPatient(request(), f.db)
    expect(journeySocialOwner(value)).toBe(owner)
    expect(value.authUserId).toBe(auth)
    expect(f.calls).toEqual([
      'verify:verified-test-token',
      'from:admin_users',
      `where:admin_users:id:${auth}`,
      'from:users',
      `where:users:auth_user_id:${auth}`,
    ])
    expect(Object.isFrozen(value)).toBe(true)
    expect(Object.isFrozen(value.patient)).toBe(true)
  })
  it('refuses a missing bearer before any SDK or data access', async () => {
    const f = fixture()
    await expect(
      authenticateJourneySocialPatient(new Request('https://unit.invalid'), f.db),
    ).rejects.toMatchObject({ status: 401 })
    expect(f.calls).toEqual([])
  })
  it('refuses any administrator membership before loading a patient', async () => {
    const f = fixture()
    f.setAdmin({ id: auth })
    await expect(authenticateJourneySocialPatient(request(), f.db)).rejects.toMatchObject({
      status: 403,
    })
    expect(f.calls).not.toContain('from:users')
  })
  it('refuses unconfirmed identity, inactive patient and mismatched ownership', async () => {
    const a = fixture()
    a.user.email_confirmed_at = ''
    await expect(authenticateJourneySocialPatient(request(), a.db)).rejects.toMatchObject({
      status: 403,
    })
    const b = fixture()
    b.patient.status = 'inactive'
    await expect(authenticateJourneySocialPatient(request(), b.db)).rejects.toMatchObject({
      status: 403,
    })
    const c = fixture()
    c.patient.auth_user_id = owner
    await expect(authenticateJourneySocialPatient(request(), c.db)).rejects.toMatchObject({
      status: 409,
    })
  })
  it('fails closed on data errors without leaking database text', async () => {
    const f = fixture()
    f.failQuery()
    await expect(authenticateJourneySocialPatient(request(), f.db)).rejects.toMatchObject({
      status: 503,
    })
    await expect(authenticateJourneySocialPatient(request(), f.db)).rejects.not.toThrow(
      'private database message',
    )
  })
})
