import type { ServiceClient } from '@mpp/db'
import { createServiceClient } from '../supabase/server'
import {
  authenticateConversationReplyPatient,
  createConversationMealReplyReadonlyAuth,
} from './conversation-meal-reply-scope'
import { authorizeMobileEntitlement } from './entitlement-service'
import type { MobileRouteRuntime } from './route'

/** Existing-account authentication: never calls bootstrapPatient, refreshes a
 * token or creates an epoch. Normal entitlement and server client remain real. */
export function createConversationMealReadonlyRuntime(): MobileRouteRuntime {
  const runtime: MobileRouteRuntime = {
    createServiceClient,
    authenticate: (request: Request, db: ServiceClient) =>
      authenticateConversationReplyPatient(request, createConversationMealReplyReadonlyAuth(db)),
    authorizeEntitlement: (auth, request, db) =>
      authorizeMobileEntitlement(db, auth.userId, new URL(request.url).pathname),
    createRequestId: (request: Request) => {
      const value = request.headers.get('x-request-id')
      return value && /^[A-Za-z0-9._:-]{8,128}$/u.test(value) ? value : crypto.randomUUID()
    },
  }
  return Object.freeze(runtime)
}
