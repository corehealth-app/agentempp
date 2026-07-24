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

function safeUnexpectedErrorName(error: unknown): string {
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
