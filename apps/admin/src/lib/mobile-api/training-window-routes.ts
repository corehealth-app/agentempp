import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { MobileApiError, mobileSuccess } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import { createTrainingWindowReadService } from './training-window-runtime'
export interface TrainingWindowRoutePorts {
  service?(client: ServiceClient): {
    read(auth: MobileAuthContext, selectedDate?: string): Promise<unknown>
  }
}
function query(request: Request) {
  const search = new URL(request.url).searchParams
  for (const key of search.keys()) {
    if (!['date', 'clinical_policy'].includes(key) || search.getAll(key).length !== 1)
      throw new MobileApiError(
        422,
        'training_window_invalid_query',
        'A closed training query is required',
      )
  }
  if (search.get('clinical_policy') !== 'current_clinical_v1')
    throw new MobileApiError(
      422,
      'training_window_invalid_query',
      'The current clinical representation is required',
    )
  return search.has('date')
    ? z
        .string()
        .regex(/^\d{4}-\d{2}-\d{2}$/)
        .parse(search.get('date'))
    : undefined
}
/** Existing-account Auth + normal entitlement only; no bootstrap, admission,
 * daily application, closer or domain operation is reachable from this GET. */
export function createTrainingWindowRoutes(
  ports: TrainingWindowRoutePorts = {},
  runtime?: MobileRouteRuntime,
) {
  const base = runtime ?? createConversationMealReadonlyRuntime()
  const fixed = Object.freeze({
    authenticate: base.authenticate.bind(base),
    authorizeEntitlement: base.authorizeEntitlement.bind(base),
    createServiceClient: base.createServiceClient.bind(base),
    createRequestId: base.createRequestId.bind(base),
  })
  const service = ports.service?.bind(ports) ?? createTrainingWindowReadService
  return Object.freeze({
    GET: createMobileRoute(async (context) => {
      const date = query(context.request),
        who = structuredClone(context.auth)
      const original = new Request(context.request, {
        headers: new Headers(context.request.headers),
      })
      const owner = authenticatedReevaluationOwner(who)
      const value = await service(context.supabase).read(who, date)
      const current = await fixed.authenticate(original, context.supabase)
      if (
        current.accessToken !== who.accessToken ||
        current.authUserId !== who.authUserId ||
        current.identity.id !== who.authUserId ||
        current.patient.authUserId !== who.authUserId ||
        authenticatedReevaluationOwner(current) !== owner
      )
        throw new MobileApiError(
          409,
          'training_window_patient_changed',
          'The authenticated patient changed during this read',
        )
      await fixed.authorizeEntitlement(current, original, context.supabase)
      return mobileSuccess(value, context.requestId)
    }, fixed),
  })
}
