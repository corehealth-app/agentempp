import type { ServiceClient } from '@mpp/db'
import { ZodError } from 'zod'
import { createServiceClient } from '../supabase/server'
import { authenticatePatient, type MobileAuthContext } from './auth'
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
  createServiceClient(): ServiceClient
  createRequestId(request: Request): string
}

type MobileRouteHandler<RouteContext = unknown> = (
  context: MobileRouteContext,
  routeContext?: RouteContext,
) => Promise<Response>

const defaultRuntime: MobileRouteRuntime = {
  authenticate(request, supabase) {
    return authenticatePatient(request, createMobileAuthDependencies(supabase))
  },
  createServiceClient,
  createRequestId(request) {
    const supplied = request.headers.get('x-request-id')
    return supplied && /^[A-Za-z0-9._:-]{8,128}$/.test(supplied) ? supplied : crypto.randomUUID()
  },
}

export function createMobileRoute<RouteContext = unknown>(
  handler: MobileRouteHandler<RouteContext>,
  runtime: MobileRouteRuntime = defaultRuntime,
) {
  return async (request: Request, routeContext?: RouteContext): Promise<Response> => {
    const requestId = runtime.createRequestId(request)
    try {
      const supabase = runtime.createServiceClient()
      const auth = await runtime.authenticate(request, supabase)
      return await handler({ auth, request, requestId, supabase }, routeContext)
    } catch (error) {
      if (error instanceof MobileApiError) return mobileErrorResponse(error, requestId)
      if (error instanceof ZodError) return mobileErrorResponse(validationError(error), requestId)
      console.error('[mobile-api] unexpected_error', {
        request_id: requestId,
        path: new URL(request.url).pathname,
        error_name: error instanceof Error ? error.name : 'UnknownError',
      })
      return mobileErrorResponse(
        new MobileApiError(500, 'internal_error', 'Unexpected server error'),
        requestId,
      )
    }
  }
}
