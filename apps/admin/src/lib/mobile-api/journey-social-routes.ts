import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { extractBearerToken, MobileApiError, mobileSuccess, readJsonBody } from './http'
import {
  socialBlockCommand,
  socialBlocksCursor,
  socialLimit,
  socialParticipationCommand,
  socialRankingCursor,
  socialReportCommand,
  socialUUID,
} from './journey-social-contracts'
import { createJourneySocialService, type JourneySocialRPCPort } from './journey-social-service'
import { createJourneySocialRuntime, journeySocialOwner } from './journey-social-runtime'
import { createMobileRoute, type MobileRouteContext, type MobileRouteRuntime } from './route'

export function journeySocialEnabled(env: Record<string, string | undefined> = process.env) {
  return env.MOBILE_JOURNEY_SOCIAL_ENABLED === 'true'
}
/** Only decode a login reference AFTER the runtime has verified the token via
 * Auth. No JWT metadata is used as ownership, entitlement or staff authority. */
export function journeySocialVerifiedLogin(auth: MobileAuthContext): string {
  try {
    const pieces = auth.accessToken.split('.'),
      encoded = pieces[1]
    if (
      pieces.length !== 3 ||
      auth.accessToken.length > 16384 ||
      !encoded ||
      !/^[A-Za-z0-9_-]+$/u.test(encoded)
    )
      throw Error()
    const claims = z
      .object({ sub: socialUUID, session_id: socialUUID })
      .passthrough()
      .parse(JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')))
    if (
      claims.sub !== auth.authUserId ||
      claims.sub !== auth.identity.id ||
      claims.sub !== auth.patient.authUserId
    )
      throw Error()
    return claims.session_id
  } catch {
    throw new MobileApiError(
      401,
      'journey_social_login_unavailable',
      'The original verified login is required.',
    )
  }
}
function invalid(): never {
  throw new MobileApiError(
    422,
    'journey_social_invalid_request',
    'A closed social request is required.',
  )
}
const paths = {
  profile: '/api/mobile/v1/profile/journey-social',
  ranking: '/api/mobile/v1/journey/ranking',
  blocks: '/api/mobile/v1/profile/journey-social/blocks',
  reports: '/api/mobile/v1/profile/journey-social/reports',
}
export function createJourneySocialRoutes(
  ports: { enabled?: () => boolean } = {},
  runtime?: MobileRouteRuntime,
) {
  const base = runtime ?? createJourneySocialRuntime()
  const fixed: MobileRouteRuntime = Object.freeze({
    authenticate: base.authenticate.bind(base),
    authorizeEntitlement: base.authorizeEntitlement.bind(base),
    createServiceClient: base.createServiceClient.bind(base),
    createRequestId: base.createRequestId.bind(base),
  })
  const enabled = ports.enabled?.bind(ports) ?? journeySocialEnabled
  function available() {
    if (enabled() !== true)
      throw new MobileApiError(503, 'journey_social_unavailable', 'Social progress is unavailable.')
  }
  function bind(context: MobileRouteContext, path: string, method: string) {
    available()
    if (new URL(context.request.url).pathname !== path || context.request.method !== method)
      return invalid()
    const original = structuredClone(context.auth),
      owner = journeySocialOwner(original),
      login = journeySocialVerifiedLogin(original)
    if (extractBearerToken(context.request.headers) !== original.accessToken)
      throw new MobileApiError(
        401,
        'journey_social_login_unavailable',
        'The original login is required.',
      )
    if (
      socialUUID.parse(context.request.headers.get('X-Journey-Owner')) !== owner ||
      socialUUID.parse(context.request.headers.get('X-Journey-Session')) !== login
    )
      throw new MobileApiError(
        409,
        'journey_social_patient_changed',
        'The original patient or login has changed.',
      )
    // Do not transfer/consume the mutation body when rechecking original Auth.
    const request = new Request(context.request.url, {
      method: context.request.method,
      headers: new Headers(context.request.headers),
    })
    async function authorize() {
      available()
      const current = await fixed.authenticate(request, context.supabase)
      if (
        current.accessToken !== original.accessToken ||
        current.authUserId !== original.authUserId ||
        current.identity.id !== original.authUserId ||
        current.patient.authUserId !== original.authUserId ||
        journeySocialOwner(current) !== owner ||
        journeySocialVerifiedLogin(current) !== login
      )
        throw new MobileApiError(
          409,
          'journey_social_patient_changed',
          'The original patient or login has changed.',
        )
      await fixed.authorizeEntitlement(current, request, context.supabase)
      available()
    }
    return createJourneySocialService(
      context.supabase as unknown as JourneySocialRPCPort,
      { owner, auth: original.authUserId, login },
      authorize,
    )
  }
  function query(context: MobileRouteContext, kind: 'ranking' | 'blocks' | null) {
    const params = new URL(context.request.url).searchParams
    for (const key of params.keys())
      if (kind === null || !['limit', 'cursor'].includes(key) || params.getAll(key).length !== 1)
        return invalid()
    const rawLimit = params.get('limit')
    if (rawLimit !== null && !/^[1-9]\d{0,2}$/u.test(rawLimit)) return invalid()
    const limit = socialLimit.parse(rawLimit === null ? 50 : Number(rawLimit))
    const raw = params.get('cursor')
    if (raw === null) return { limit, cursor: undefined }
    if (raw.length > 2048) return invalid()
    try {
      return {
        limit,
        cursor:
          kind === 'ranking'
            ? socialRankingCursor.parse(JSON.parse(raw))
            : socialBlocksCursor.parse(JSON.parse(raw)),
      }
    } catch {
      return invalid()
    }
  }
  function operationKey(context: MobileRouteContext, id: string) {
    z.literal(`jsocial1:${id}`).parse(context.request.headers.get('Idempotency-Key'))
  }
  const response = (value: unknown, id: string) =>
    mobileSuccess(value, id, 200, { 'X-Journey-Social': '1' })
  return Object.freeze({
    PROFILE_GET: createMobileRoute(async (context) => {
      const service = bind(context, paths.profile, 'GET')
      query(context, null)
      return response(await service.profile(), context.requestId)
    }, fixed),
    PROFILE_PATCH: createMobileRoute(async (context) => {
      const service = bind(context, paths.profile, 'PATCH')
      query(context, null)
      const command = socialParticipationCommand.parse(await readJsonBody(context.request, 8192))
      operationKey(context, command.operation_id)
      return response(await service.participate(command), context.requestId)
    }, fixed),
    RANKING_GET: createMobileRoute(async (context) => {
      const service = bind(context, paths.ranking, 'GET'),
        page = query(context, 'ranking')
      return response(await service.ranking(page.cursor, page.limit), context.requestId)
    }, fixed),
    BLOCKS_GET: createMobileRoute(async (context) => {
      const service = bind(context, paths.blocks, 'GET'),
        page = query(context, 'blocks')
      return response(await service.blocks(page.cursor, page.limit), context.requestId)
    }, fixed),
    BLOCKS_POST: createMobileRoute(async (context) => {
      const service = bind(context, paths.blocks, 'POST')
      query(context, null)
      const command = socialBlockCommand.parse(await readJsonBody(context.request, 8192))
      operationKey(context, command.operation_id)
      return response(await service.block(command), context.requestId)
    }, fixed),
    REPORTS_POST: createMobileRoute(async (context) => {
      const service = bind(context, paths.reports, 'POST')
      query(context, null)
      const command = socialReportCommand.parse(await readJsonBody(context.request, 8192))
      operationKey(context, command.operation_id)
      return response(await service.report(command), context.requestId)
    }, fixed),
  })
}
