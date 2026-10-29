import { describe, expect, it, vi } from 'vitest'
import {
  makePasswordRecoveryHandlers,
  PASSWORD_RECOVERY_PATH,
  passwordRecoveryConfiguration,
} from './password-recovery'

const origin = 'https://performe-ai-staging-bff.vercel.app'
const authOrigin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const userID = '11111111-1111-4111-8111-111111111111'
const hash = 'pkce_synthetic-recovery-token-with-prefix'
const password = 'Synthetic recovery password 731!'
const config = {
  publicOrigin: origin,
  authOrigin,
  publicKey: 'sb_publishable_synthetic_only',
}

function request(body: unknown = { token_hash: hash, password, password_confirmation: password }) {
  return new Request(`${origin}${PASSWORD_RECOVERY_PATH}`, {
    method: 'POST',
    headers: {
      origin,
      'content-type': 'application/json',
      cookie: 'administrative-session=must-not-be-forwarded',
      authorization: 'Bearer unrelated-administrative-session',
    },
    body: JSON.stringify(body),
  })
}

function harness(replies?: Array<Response | Error>) {
  const queue = replies ?? [
    Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
    Response.json({ id: userID }),
    new Response(null, { status: 204 }),
  ]
  const fetcher = vi.fn(async (_url: string, _init: RequestInit): Promise<Response> => {
    const reply = queue.shift()
    if (reply instanceof Error) throw reply
    if (!reply) throw new Error('unexpected extra request')
    return reply
  })
  return { fetcher, ...makePasswordRecoveryHandlers(config, fetcher, () => 'synthetic-nonce') }
}

describe('password recovery for the existing iOS build', () => {
  it.each([
    'missing_origin',
    'wrong_request_host',
    'wrong_path',
    'cross_site',
  ])('refuses %s before a recovery token can be consumed', async (scenario) => {
    const h = harness()
    let target = request()
    if (scenario === 'missing_origin') target.headers.delete('origin')
    if (scenario === 'cross_site') target.headers.set('sec-fetch-site', 'cross-site')
    if (scenario === 'wrong_request_host')
      target = new Request(`https://untrusted.example${PASSWORD_RECOVERY_PATH}`, target)
    if (scenario === 'wrong_path')
      target = new Request(`${origin}/api/mobile/v1/auth/other`, target)
    expect((await h.POST(target)).status).toBe(403)
    expect(h.fetcher).not.toHaveBeenCalled()
  })

  it.each([
    `{"token_hash":"${hash}","password":"first","password":"second","password_confirmation":"second"}`,
    new Uint8Array([123, 34, 120, 34, 58, 34, 255, 34, 125]),
  ])('rejects ambiguous JSON or invalid UTF-8 before Auth', async (body) => {
    const h = harness()
    const input = new Request(`${origin}${PASSWORD_RECOVERY_PATH}`, {
      method: 'POST',
      headers: { origin, 'content-type': 'application/json' },
      body,
    })
    expect((await h.POST(input)).status).toBe(400)
    expect(h.fetcher).not.toHaveBeenCalled()
  })

  it('keeps GET, HEAD, scanners and email-link loading free of Auth effects', async () => {
    const h = harness()
    const result = await h.GET(new Request(`${origin}${PASSWORD_RECOVERY_PATH}`))
    const html = await result.text()
    expect(result.status).toBe(200)
    expect(html).toContain('Nova senha')
    expect(html).toContain('history.replaceState')
    expect(html).toContain("addEventListener('submit'")
    expect(html).not.toContain('localStorage')
    expect(html).not.toContain('sessionStorage')
    expect(html).not.toContain(config.publicKey)
    expect((await h.HEAD(new Request(`${origin}${PASSWORD_RECOVERY_PATH}`))).status).toBe(200)
    expect(h.fetcher).not.toHaveBeenCalled()
    expect(result.headers.get('cache-control')).toContain('no-store')
    expect(result.headers.get('referrer-policy')).toBe('no-referrer')
    expect(result.headers.get('content-security-policy')).toContain("frame-ancestors 'none'")
    expect(result.headers.get('content-security-policy')).toContain("'nonce-synthetic-nonce'")
    expect(result.headers.has('set-cookie')).toBe(false)
  })

  it('supports English and a named confirmation field', async () => {
    const h = harness()
    const result = await h.GET(
      new Request(`${origin}${PASSWORD_RECOVERY_PATH}`, {
        headers: { 'accept-language': 'en-US,en;q=0.9' },
      }),
    )
    expect(await result.text()).toContain('Confirm new password')
  })

  it('verifies recovery explicitly, uses only its bearer, updates once and revokes only that session', async () => {
    const h = harness()
    const result = await h.POST(request())
    expect(result.status).toBe(200)
    expect(await result.json()).toEqual({ status: 'password_changed' })
    expect(h.fetcher).toHaveBeenCalledTimes(3)
    const calls = h.fetcher.mock.calls
    expect(calls.map(([url]) => url)).toEqual([
      `${authOrigin}/auth/v1/verify`,
      `${authOrigin}/auth/v1/user`,
      `${authOrigin}/auth/v1/logout?scope=local`,
    ])
    expect(JSON.parse(String(calls[0]?.[1].body))).toEqual({ token_hash: hash, type: 'recovery' })
    expect(JSON.parse(String(calls[1]?.[1].body))).toEqual({ password })
    expect(new Headers(calls[1]?.[1].headers).get('authorization')).toBe(
      'Bearer synthetic-recovery-bearer',
    )
    for (const [, init] of calls) {
      expect(new Headers(init.headers).get('cookie')).toBeNull()
      expect(new Headers(init.headers).get('x-supabase-api-version')).toBe('2024-01-01')
      expect(init.credentials).toBe('omit')
      expect(init.redirect).toBe('error')
      expect(init.cache).toBe('no-store')
    }
    expect(result.headers.has('set-cookie')).toBe(false)
  })

  it.each([
    {},
    { token_hash: hash, password, password_confirmation: 'different' },
    { token_hash: 'not allowed\ncontrol', password, password_confirmation: password },
    { token_hash: 'x'.repeat(2049), password, password_confirmation: password },
    { token_hash: hash, password: ' ', password_confirmation: ' ' },
    { token_hash: hash, password, password_confirmation: password, type: 'signup' },
    { token_hash: hash, password, password_confirmation: password, user_id: userID },
  ])('rejects malformed or extra inputs before consuming a link: %j', async (input) => {
    const h = harness()
    expect((await h.POST(request(input))).status).toBe(400)
    expect(h.fetcher).not.toHaveBeenCalled()
  })

  it('rejects cross-origin requests and oversized streamed bodies before Auth', async () => {
    const h = harness()
    const cross = request()
    cross.headers.set('origin', 'https://untrusted.example')
    expect((await h.POST(cross)).status).toBe(403)
    const large = request({
      token_hash: 'x'.repeat(10000),
      password,
      password_confirmation: password,
    })
    expect((await h.POST(large)).status).toBe(413)
    expect(h.fetcher).not.toHaveBeenCalled()
  })

  it('rejects expired/replayed hashes without updating or revealing the provider response', async () => {
    const h = harness([
      Response.json({ code: 'otp_expired', details: 'private-provider-detail' }, { status: 403 }),
    ])
    const result = await h.POST(request())
    expect(result.status).toBe(400)
    expect(await result.json()).toEqual({ status: 'new_link_required' })
    expect(h.fetcher).toHaveBeenCalledTimes(1)
  })

  it.each([
    401, 429, 500,
  ])('does not present provider status %i as an expired link', async (status) => {
    const h = harness([
      Response.json({ code: 'provider_failure', message: 'private detail' }, { status }),
    ])
    const response = await h.POST(request())
    expect(response.status).toBe(status === 429 ? 429 : 503)
    expect(await response.json()).toEqual({ status: 'recovery_unavailable' })
    expect(h.fetcher).toHaveBeenCalledTimes(1)
  })

  it('supports the documented legacy Auth error envelope without exposing its message', async () => {
    const h = harness([
      Response.json(
        { code: 403, error_code: 'otp_expired', msg: 'provider-only-detail' },
        { status: 403 },
      ),
    ])
    const response = await h.POST(request())
    expect(await response.json()).toEqual({ status: 'new_link_required' })
    expect(h.fetcher).toHaveBeenCalledTimes(1)
  })

  it('revokes a returned bearer even if the verified user is missing', async () => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer' }),
      new Response(null, { status: 204 }),
    ])
    const response = await h.POST(request())
    expect(await response.json()).toEqual({ status: 'recovery_unconfirmed' })
    expect(h.fetcher.mock.calls.map(([url]) => url)).toEqual([
      `${authOrigin}/auth/v1/verify`,
      `${authOrigin}/auth/v1/logout?scope=local`,
    ])
  })

  it.each([
    'weak_password',
    'same_password',
  ])('reports password rejection %s without claiming link expiration', async (code) => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
      Response.json({ code, message: 'provider detail' }, { status: 422 }),
      new Response(null, { status: 204 }),
    ])
    const response = await h.POST(request())
    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ status: 'password_rejected' })
    expect(h.fetcher).toHaveBeenCalledTimes(3)
  })

  it('does not claim success or expiration after a provider update failure', async () => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
      Response.json({ code: 'unexpected_failure' }, { status: 500 }),
      new Response(null, { status: 204 }),
    ])
    const response = await h.POST(request())
    expect(response.status).toBe(503)
    expect(await response.json()).toEqual({ status: 'recovery_unconfirmed' })
    expect(h.fetcher).toHaveBeenCalledTimes(3)
  })

  it('preserves the password acknowledgement when local logout returns an error', async () => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
      Response.json({ id: userID }),
      Response.json({ code: 'unexpected_failure' }, { status: 500 }),
    ])
    const response = await h.POST(request())
    expect(await response.json()).toEqual({ status: 'password_changed' })
    expect(h.fetcher).toHaveBeenCalledTimes(3)
  })

  it('does not claim success or retry if update loses its response after verification', async () => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
      new Error('transport failure with secret-shaped details'),
      new Response(null, { status: 204 }),
    ])
    const result = await h.POST(request())
    expect(result.status).toBe(503)
    expect(await result.json()).toEqual({ status: 'recovery_unconfirmed' })
    expect(h.fetcher).toHaveBeenCalledTimes(3)
    expect(h.fetcher.mock.calls.filter(([url]) => url.endsWith('/user'))).toHaveLength(1)
  })

  it('refuses a different identity in the update response and still closes the recovery session', async () => {
    const h = harness([
      Response.json({ access_token: 'synthetic-recovery-bearer', user: { id: userID } }),
      Response.json({ id: '22222222-2222-4222-8222-222222222222' }),
      new Response(null, { status: 204 }),
    ])
    expect((await h.POST(request())).status).toBe(503)
    expect(h.fetcher.mock.calls.at(-1)?.[0]).toContain('logout?scope=local')
  })

  it('stays unavailable until the exact staging project is enabled', async () => {
    const fetcher = vi.fn()
    const h = makePasswordRecoveryHandlers(null, fetcher, () => 'nonce')
    expect((await h.GET(new Request(`${origin}${PASSWORD_RECOVERY_PATH}`))).status).toBe(503)
    expect((await h.POST(request())).status).toBe(503)
    expect(fetcher).not.toHaveBeenCalled()
    const env = {
      MOBILE_PASSWORD_RECOVERY_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
      NEXT_PUBLIC_SUPABASE_URL: authOrigin,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: config.publicKey,
    }
    expect(passwordRecoveryConfiguration(env)).toEqual(config)
    expect(
      passwordRecoveryConfiguration({ ...env, MOBILE_PASSWORD_RECOVERY_PROJECT_REF: undefined }),
    ).toBeNull()
    expect(
      passwordRecoveryConfiguration({
        ...env,
        NEXT_PUBLIC_SUPABASE_URL: 'https://wrong-project.example',
      }),
    ).toBeNull()
    expect(
      passwordRecoveryConfiguration({
        ...env,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_secret_forbidden',
      }),
    ).toBeNull()
  })
})
