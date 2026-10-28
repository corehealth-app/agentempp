/** Public consent boundary, still injection-only. Nothing mounts/activates it.
 * Shown legal identity, current occurrence and expiry are always checked in SQL. */
import { z } from 'zod'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  createReevaluationPhotoConsentService,
  reevaluationPhotoConsentAcceptInput,
} from './reevaluation-photo-consent'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

export interface ReevaluationPhotoConsentRouteContext {
  params: Promise<{ cycleId: string }>
}
export function createReevaluationPhotoConsentRoutes(
  dependencies: { readonly enabled: boolean },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true
  const fixedRuntime =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  const route = (accept: boolean) =>
    createMobileRouteWithContext<ReevaluationPhotoConsentRouteContext>(
      async (context, routeContext) => {
        if (!enabled)
          throw new MobileApiError(
            404,
            'reevaluation_photo_consent_unavailable',
            'Photo consent unavailable',
          )
        if (new URL(context.request.url).searchParams.size)
          throw new MobileApiError(
            422,
            'mobile_reevaluation_photo_consent_input',
            'Photo consent unavailable',
          )
        const { cycleId } = z
          .object({ cycleId: uuid })
          .strict()
          .parse(await routeContext.params)
        const service = createReevaluationPhotoConsentService(context.supabase),
          auth = structuredClone(context.auth)
        const value = accept
          ? await service.accept(
              auth,
              cycleId,
              uuid.parse(requireIdempotencyKey(context.request)),
              reevaluationPhotoConsentAcceptInput.parse(await readJsonBody(context.request, 8192)),
            )
          : await service.read(auth, cycleId)
        return mobileSuccess(value, context.requestId)
      },
      fixedRuntime,
    )
  return Object.freeze({ GET: route(false), ACCEPT: route(true) })
}
