import { randomBytes } from 'node:crypto'
import { MobileApiError, readJsonBody } from './http'
import { passwordRecoveryPage } from './password-recovery-page'
import { PASSWORD_RECOVERY_PATH } from './password-recovery-path'

export { PASSWORD_RECOVERY_PATH } from './password-recovery-path'

const stagingRef = 'xitugspwfxkcluxvrdeg'
const stagingOrigin = 'https://performe-ai-staging-bff.vercel.app'
type Environment = Record<string, string | undefined>
type RecoveryFetch = (url: string, init: RequestInit) => Promise<Response>
export type PasswordRecoveryConfiguration = {
  publicOrigin: string
  authOrigin: string
  publicKey: string
}

export function passwordRecoveryConfiguration(
  env: Environment,
): PasswordRecoveryConfiguration | null {
  if (
    env.MOBILE_PASSWORD_RECOVERY_PROJECT_REF !== stagingRef ||
    env.NEXT_PUBLIC_SUPABASE_URL !== `https://${stagingRef}.supabase.co`
  )
    return null
  const key = env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!key) return null
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) {
    try {
      const parts = key.split('.')
      if (
        parts.length !== 3 ||
        JSON.parse(Buffer.from(parts[1] ?? '', 'base64url').toString()).role !== 'anon'
      )
        return null
    } catch {
      return null
    }
  }
  return {
    publicOrigin: stagingOrigin,
    authOrigin: `https://${stagingRef}.supabase.co`,
    publicKey: key,
  }
}

function headers(nonce?: string): Headers {
  const result = new Headers({
    'Cache-Control': 'no-store, max-age=0',
    Pragma: 'no-cache',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-Robots-Tag': 'noindex, nofollow, noarchive',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  })
  if (nonce)
    result.set(
      'Content-Security-Policy',
      `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`,
    )
  return result
}

function result(status: string, code: number): Response {
  return Response.json({ status }, { status: code, headers: headers() })
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function authErrorCode(body: Record<string, unknown>): string | undefined {
  return typeof body.code === 'string'
    ? body.code
    : typeof body.error_code === 'string'
      ? body.error_code
      : undefined
}

async function authBody(response: Response): Promise<Record<string, unknown>> {
  // Provider payloads may contain credentials. Bound parsing and never expose
  // the raw payload or error, including when transport/parsing fails.
  const reader = response.body?.getReader()
  if (!reader) throw new Error('invalid_auth_response')
  const decoder = new TextDecoder('utf-8', { fatal: true })
  let bytes = 0
  let text = ''
  for (;;) {
    const chunk = await reader.read()
    if (chunk.done) break
    bytes += chunk.value.byteLength
    if (bytes > 256 * 1024) {
      await reader.cancel()
      throw new Error('invalid_auth_response')
    }
    text += decoder.decode(chunk.value, { stream: true })
  }
  const value: unknown = JSON.parse(text + decoder.decode())
  if (!record(value)) throw new Error('invalid_auth_response')
  return value
}

function validInput(body: unknown): body is {
  token_hash: string
  password: string
  password_confirmation: string
} {
  if (
    !record(body) ||
    Object.keys(body).sort().join(',') !== 'password,password_confirmation,token_hash'
  )
    return false
  return (
    typeof body.token_hash === 'string' &&
    /^[!-~]{20,2048}$/.test(body.token_hash) &&
    typeof body.password === 'string' &&
    body.password.trim().length > 0 &&
    body.password.length <= 1024 &&
    body.password_confirmation === body.password
  )
}

export function makePasswordRecoveryHandlers(
  configuration: PasswordRecoveryConfiguration | null,
  fetcher: RecoveryFetch = fetch,
  nonceSource: () => string = () => randomBytes(18).toString('base64url'),
) {
  async function GET(request: Request): Promise<Response> {
    const nonce = nonceSource()
    const enabled = configuration !== null
    const html = passwordRecoveryPage(nonce, request.headers.get('accept-language') ?? '', enabled)
    const responseHeaders = headers(nonce)
    responseHeaders.set('Content-Type', 'text/html; charset=utf-8')
    responseHeaders.set('Vary', 'Accept-Language')
    return new Response(html, { status: enabled ? 200 : 503, headers: responseHeaders })
  }

  async function HEAD(request: Request): Promise<Response> {
    const response = await GET(request)
    return new Response(null, { status: response.status, headers: response.headers })
  }

  async function POST(request: Request): Promise<Response> {
    if (!configuration) return result('unavailable', 503)
    const config = configuration
    if (
      request.headers.get('origin') !== config.publicOrigin ||
      new URL(request.url).origin !== config.publicOrigin ||
      new URL(request.url).pathname !== PASSWORD_RECOVERY_PATH ||
      request.headers.get('sec-fetch-site') === 'cross-site'
    )
      return result('forbidden', 403)
    let body: unknown
    try {
      body = await readJsonBody(request, 8192)
    } catch (error) {
      return result('invalid_request', error instanceof MobileApiError ? error.status : 400)
    }
    if (!validInput(body)) return result('invalid_request', 400)

    let recoveryBearer: string | null = null
    async function auth(
      path: string,
      method: string,
      payload?: unknown,
      timeout = 10000,
    ): Promise<Response> {
      const outgoing = new Headers({
        apikey: config.publicKey,
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Supabase-Api-Version': '2024-01-01',
      })
      if (recoveryBearer) outgoing.set('Authorization', `Bearer ${recoveryBearer}`)
      return fetcher(`${config.authOrigin}/auth/v1/${path}`, {
        method,
        headers: outgoing,
        body: payload === undefined ? undefined : JSON.stringify(payload),
        credentials: 'omit',
        redirect: 'error',
        cache: 'no-store',
        signal: AbortSignal.timeout(timeout),
      })
    }
    try {
      // Fixed type; never exchange a PKCE code or reuse an administrator's
      // cookie, JWT, user ID, URL or project supplied by the caller.
      const verification = await auth('verify', 'POST', {
        token_hash: body.token_hash,
        type: 'recovery',
      })
      if (!verification.ok) {
        const failure = await authBody(verification)
        if ([400, 403].includes(verification.status) && authErrorCode(failure) === 'otp_expired')
          return result('new_link_required', 400)
        return result('recovery_unavailable', verification.status === 429 ? 429 : 503)
      }
      const verified = await authBody(verification)
      if (
        typeof verified.access_token !== 'string' ||
        !/^[!-~]{1,16384}$/.test(verified.access_token)
      )
        return result('recovery_unconfirmed', 503)
      recoveryBearer = verified.access_token
      if (!record(verified.user) || typeof verified.user.id !== 'string')
        return result('recovery_unconfirmed', 503)
      const changed = await auth('user', 'PUT', { password: body.password })
      if (!changed.ok) {
        const failure = await authBody(changed)
        if (
          [400, 422].includes(changed.status) &&
          ['weak_password', 'same_password'].includes(authErrorCode(failure) ?? '')
        )
          return result('password_rejected', 400)
        return result('recovery_unconfirmed', 503)
      }
      const updated = await authBody(changed)
      if (updated.id !== verified.user.id) return result('recovery_unconfirmed', 503)
      return result('password_changed', 200)
    } catch {
      // Verification consumes a link; a missing update response may mean the
      // password changed. No automatic retry or claim of rollback/success.
      return result('recovery_unconfirmed', 503)
    } finally {
      if (recoveryBearer) {
        // Best effort; a failed logout must not contradict a confirmed update.
        try {
          await auth('logout?scope=local', 'POST', undefined, 3000)
        } catch {
          /* No session is stored or returned. */
        }
        recoveryBearer = null
      }
    }
  }
  return { GET, HEAD, POST }
}
