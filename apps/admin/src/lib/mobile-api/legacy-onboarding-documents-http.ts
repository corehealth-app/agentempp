import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import {
  createLegacyDocumentService,
  legacyDocumentError,
  legacyDocumentInputSchema,
} from './legacy-onboarding-documents'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import { createSupabaseLegacyDocumentRepository } from './supabase-legacy-onboarding-documents'

/** Explicit opt-in, inert until a current route selects this factory. */
export function createLegacyOnboardingDocumentsRoutes(
  options: { readonly enabled: boolean },
  runtime?: MobileRouteRuntime,
) {
  const enabled = options.enabled === true
  const fixed =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  return Object.freeze({
    POST: createMobileRoute(async (context) => {
      if (!enabled)
        throw new MobileApiError(404, 'mobile_legacy_documents_disabled', 'Notices unavailable')
      if (new URL(context.request.url).searchParams.size) throw legacyDocumentError('input')
      const auth = structuredClone(context.auth)
      const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
      const input = legacyDocumentInputSchema.parse(await readJsonBody(context.request, 16384))
      const service = createLegacyDocumentService(
        createSupabaseLegacyDocumentRepository(context.supabase),
      )
      return mobileSuccess(
        await service.accept(auth, { ...input, operation_key: key }),
        context.requestId,
      )
    }, fixed),
  })
}
