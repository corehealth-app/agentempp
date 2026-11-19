import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { matchesModerationSession } from './session-watch'

const actor = '20000000-0000-4000-8000-000000000002'
const login = '20000000-0000-4000-a000-000000000002'
const context = {
  origin: 'https://admin.example.invalid',
  owner: '116234755b6d715da027f8def7c855b0379f43f61632186d08bcbbc9ec4bee87',
  login: 'deab31b7ba61be6560f34575ad01c5d143384ee600d8b29a945be3d9112613fe',
}
const hash = async (value: string) => createHash('sha256').update(value).digest('hex')
function session(changes: Record<string, unknown> = {}) {
  return {
    user: { id: actor },
    access_token: `header.${Buffer.from(JSON.stringify({ sub: actor, session_id: login, ...changes })).toString('base64url')}.signature`,
  }
}
describe('browser events only invalidate operational identity', () => {
  it('does not admit a truncated token even when its copied claims match', async () => {
    const truncated = session()
    truncated.access_token = truncated.access_token.split('.').slice(0, 2).join('.')
    await expect(matchesModerationSession(context, truncated, hash)).resolves.toBe(false)
  })
  it('preserves a token refresh of the same original owner/login', async () => {
    await expect(matchesModerationSession(context, session({ exp: 123456 }), hash)).resolves.toBe(
      true,
    )
  })
  it('rejects logout and malformed events', async () => {
    await expect(matchesModerationSession(context, null, hash)).resolves.toBe(false)
    await expect(
      matchesModerationSession(context, { user: { id: actor }, access_token: 'broken' }, hash),
    ).resolves.toBe(false)
  })
  it('rejects a new login of the same operator', async () => {
    await expect(
      matchesModerationSession(
        context,
        session({ session_id: '20000000-0000-4000-a000-000000000003' }),
        hash,
      ),
    ).resolves.toBe(false)
  })
  it('rejects user/claim mismatch or another origin namespace', async () => {
    await expect(
      matchesModerationSession(
        context,
        session({ sub: '20000000-0000-4000-8000-000000000003' }),
        hash,
      ),
    ).resolves.toBe(false)
    await expect(
      matchesModerationSession(
        { ...context, origin: 'https://other.example.invalid' },
        session(),
        hash,
      ),
    ).resolves.toBe(false)
  })
})
