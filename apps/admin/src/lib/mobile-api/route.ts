import type { ServiceClient } from '@mpp/db'
import { ZodError } from 'zod'
import { createServiceClient } from '../supabase/server'
import { authenticatePatient, type MobileAuthContext } from './auth'
import { authorizeMobileEntitlement } from './entitlement-service'
import { MobileApiError, mobileErrorResponse, validationError } from './http'
import { createMobileAuthDependencies } from './supabase-auth'

export interface MobileRouteContext {
  auth: MobileAuthContext
  request: Request
  requestId: string
  supabase: ServiceClient
}

export interface MobileRouteRuntime {
  authenticate(request: Request, supabase: ServiceClient): Promise<MobileAuthContext>
  authorizeEntitlement(
    auth: MobileAuthContext,
    request: Request,
    supabase: ServiceClient,
  ): Promise<void>
  createServiceClient(): ServiceClient
  createRequestId(request: Request): string
}

type MobileRouteHandler<RouteContext> = (
  context: MobileRouteContext,
  routeContext: RouteContext,
) => Promise<Response>

type StaticMobileRouteHandler = (context: MobileRouteContext) => Promise<Response>

const SAFE_UNEXPECTED_ERROR_NAMES = new Set([
  'Error',
  'TypeError',
  'RangeError',
  'ReferenceError',
  'SyntaxError',
  'AggregateError',
  'AbortError',
])

export function safeUnexpectedErrorName(error: unknown): string {
  return error instanceof Error && SAFE_UNEXPECTED_ERROR_NAMES.has(error.name)
    ? error.name
    : 'UnknownError'
}

const defaultRuntime: MobileRouteRuntime = {
  authenticate(request, supabase) {
    return authenticatePatient(request, createMobileAuthDependencies(supabase))
  },
  authorizeEntitlement(auth, request, supabase) {
    return authorizeMobileEntitlement(supabase, auth.userId, new URL(request.url).pathname)
  },
  createServiceClient,
  createRequestId(request) {
    const supplied = request.headers.get('x-request-id')
    return supplied && /^[A-Za-z0-9._:-]{8,128}$/.test(supplied) ? supplied : crypto.randomUUID()
  },
}

async function runMobileRoute<RouteContext>(
  request: Request,
  routeContext: RouteContext,
  handler: MobileRouteHandler<RouteContext>,
  runtime: MobileRouteRuntime = defaultRuntime,
): Promise<Response> {
  const requestId = runtime.createRequestId(request)
  try {
    const supabase = runtime.createServiceClient()
    const auth = await runtime.authenticate(request, supabase)
    await runtime.authorizeEntitlement(auth, request, supabase)
    // New conversational media clients bind every asset operation to the
    // patient observed before capture/upload. The header is a precondition,
    // never ownership authority. Existing clients without it are unchanged.
    const expectedPatient = request.headers.get('X-Conversation-Owner')
    if (
      expectedPatient !== null &&
      /^\/api\/mobile\/v1\/media(?:\/|$)/u.test(new URL(request.url).pathname)
    ) {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(expectedPatient))
        throw new MobileApiError(
          422,
          'conversation_owner_invalid',
          'A valid original patient is required',
        )
      if (expectedPatient !== auth.userId)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The authenticated patient has changed',
        )
    }
    return await handler({ auth, request, requestId, supabase }, routeContext)
  } catch (error) {
    if (error instanceof MobileApiError) return mobileErrorResponse(error, requestId)
    if (error instanceof ZodError) return mobileErrorResponse(validationError(error), requestId)
    console.error('[mobile-api] unexpected_error', {
      request_id: requestId,
      scope: 'mobile_api_v1',
      error_name: safeUnexpectedErrorName(error),
    })
    return mobileErrorResponse(
      new MobileApiError(500, 'internal_error', 'Unexpected server error'),
      requestId,
    )
  }
}

export function createMobileRoute(
  handler: StaticMobileRouteHandler,
  runtime: MobileRouteRuntime = defaultRuntime,
) {
  return (request: Request): Promise<Response> =>
    runMobileRoute(request, undefined, (context) => handler(context), runtime)
}

export function createMobileRouteWithContext<RouteContext>(
  handler: MobileRouteHandler<RouteContext>,
  runtime: MobileRouteRuntime = defaultRuntime,
) {
  return (request: Request, routeContext: RouteContext): Promise<Response> =>
    runMobileRoute(request, routeContext, handler, runtime)
}
