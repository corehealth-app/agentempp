import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import { trainingExecutionVerifiedLogin } from './training-execution-runtime'

const auth = '13600000-0000-4000-8000-000000000001',
  login = '13600000-0000-4000-8000-000000000003'
const verified = (claims: unknown) =>
  ({
    accessToken: `e30.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.synthetic`,
    authUserId: auth,
    identity: { id: auth },
    patient: { authUserId: auth },
  }) as MobileAuthContext
describe('verified original token login reference', () => {
  it('extracts only the session of the already verified original Auth', () => {
    expect(
      trainingExecutionVerifiedLogin(
        verified({ sub: auth, session_id: login, app_metadata: { owner: 'ignored' } }),
      ),
    ).toBe(login)
  })
  it('refuses a missing login, foreign subject or malformed token before any RPC', () => {
    for (const claims of [
      { sub: auth },
      { sub: login, session_id: login },
      { sub: auth, session_id: 'invalid' },
    ])
      expect(() => trainingExecutionVerifiedLogin(verified(claims))).toThrow()
    expect(() =>
      trainingExecutionVerifiedLogin({
        ...verified({ sub: auth, session_id: login }),
        accessToken: 'opaque',
      }),
    ).toThrow()
  })
})
