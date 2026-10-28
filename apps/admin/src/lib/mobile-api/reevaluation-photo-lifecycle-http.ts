/** Injection-only recurring photo routes. No mounted route or default provider. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  createReevaluationPhotoLifecycleService,
  photoLifecycleError,
  type ReevaluationPhotoLifecycleOperations,
  reevaluationPhotoAllocateInput,
  reevaluationPhotoDiscardInput,
} from './reevaluation-photo-lifecycle'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

export interface ReevaluationPhotoLifecycleRouteContext {
  params: Promise<{ cycleId: string; assetId?: string }>
}
type Action = 'GET' | 'ALLOCATE' | 'UPLOAD' | 'COMPLETE' | 'PROCESS' | 'DISCARD'
export function createReevaluationPhotoLifecycleRoutes(
  dependencies: {
    readonly enabled: boolean
    createOperations(client: ServiceClient): ReevaluationPhotoLifecycleOperations
  },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true
  const createOperations = dependencies.createOperations.bind(dependencies)
  const fixedRuntime =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  const route = (action: Action) =>
    createMobileRouteWithContext<ReevaluationPhotoLifecycleRouteContext>(
      async (context, routeContext) => {
        if (!enabled)
          throw new MobileApiError(
            404,
            'reevaluation_photos_unavailable',
            'Reassessment photos unavailable',
          )
        if (new URL(context.request.url).searchParams.size) throw photoLifecycleError('input')
        const params = z
          .object({ cycleId: uuid, assetId: uuid.optional() })
          .strict()
          .parse(await routeContext.params)
        const assetId = ['UPLOAD', 'COMPLETE', 'PROCESS'].includes(action)
          ? uuid.parse(params.assetId)
          : null
        // Validate the complete public intention before creating ports that can
        // reach SQL, Storage or the provider. Replays re-enter their own authority.
        const key = action === 'GET' ? null : uuid.parse(requireIdempotencyKey(context.request))
        const input = action === 'GET' ? null : await readJsonBody(context.request, 8192)
        const allocation =
          action === 'ALLOCATE' ? reevaluationPhotoAllocateInput.parse(input) : null
        const discard = action === 'DISCARD' ? reevaluationPhotoDiscardInput.parse(input) : null
        if (['UPLOAD', 'COMPLETE', 'PROCESS'].includes(action)) z.object({}).strict().parse(input)
        const service = createReevaluationPhotoLifecycleService(createOperations(context.supabase))
        const auth = structuredClone(context.auth)
        const value =
          action === 'GET'
            ? await service.snapshot(auth, params.cycleId)
            : action === 'ALLOCATE'
              ? await service.allocate(auth, params.cycleId, key, allocation)
              : action === 'UPLOAD'
                ? await service.upload(auth, params.cycleId, assetId)
                : action === 'COMPLETE'
                  ? await service.complete(auth, params.cycleId, assetId)
                  : action === 'PROCESS'
                    ? await service.process(auth, params.cycleId, assetId, key)
                    : await service.discard(auth, params.cycleId, discard)
        return mobileSuccess(value, context.requestId)
      },
      fixedRuntime,
    )
  return Object.freeze({
    GET: route('GET'),
    ALLOCATE: route('ALLOCATE'),
    UPLOAD: route('UPLOAD'),
    COMPLETE: route('COMPLETE'),
    PROCESS: route('PROCESS'),
    DISCARD: route('DISCARD'),
  })
}
