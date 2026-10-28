import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import {
  createSignupHealthAdmissionService,
  signupHealthAdmissionInputSchema,
  signupHealthError,
} from './signup-health-admission'
import { createSupabaseSignupHealthAdmissionRepository } from './supabase-signup-health-admission'

/** Injection-only POST /onboarding/health. No mounted route/default activation. */
export function createSignupHealthAdmissionRoutes(
  dependencies: { readonly enabled: boolean },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true
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
        throw new MobileApiError(
          404,
          'mobile_signup_health_disabled',
          'Health declaration unavailable',
        )
      if (new URL(context.request.url).searchParams.size) throw signupHealthError('input')
      const auth = structuredClone(context.auth)
      const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
      const input = signupHealthAdmissionInputSchema.parse(
        await readJsonBody(context.request, 8192),
      )
      const service = createSignupHealthAdmissionService({
        enabled: true,
        repository: createSupabaseSignupHealthAdmissionRepository(context.supabase),
      })
      return mobileSuccess(
        await service.admit(auth, { ...input, operation_key: key }),
        context.requestId,
      )
    }, fixed),
  })
}
