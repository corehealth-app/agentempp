/** Public cycle entry factories. No route.ts or default runtime activates them.
 * The SQL starter, not a client kind/date, reconciles the real occurrence. */
import { clinicalCivilDateSchema as date } from '@mpp/core/reevaluation-clinical-safety'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { clinicalFullError, fullPositiveCounter } from './clinical-full-contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import {
  parseReevaluationCycleRpcState,
  reevaluationCycleUuidSchema as uuid,
} from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'

const startInput = z
  .object({ reason: z.enum(['gain_review_notice', 'not_well_with_plan']).nullable() })
  .strict()
export const clinicalFullEntryDto = z
  .object({
    version: z.literal(1),
    availability: z.enum(['available', 'unavailable']),
    unavailable_reason: z.enum(['not_due', 'onboarding_incomplete', 'anchor_unproven']).nullable(),
    clock: z
      .object({ base_date: date, due_date: date, timezone: z.string().min(1) })
      .strict()
      .nullable(),
    cycle: z
      .object({
        id: uuid,
        kind: z.enum(['REGULAR', 'EARLY_FULL', 'TRANSITION_FULL']),
        status: z.enum(['open', 'collecting', 'review_ready']),
        revision: fullPositiveCounter,
      })
      .strict()
      .nullable(),
  })
  .strict()
type Rpc = (
  name: 'get_mobile_reevaluation_cycle' | 'start_mobile_clinical_full',
  args: Record<string, unknown>,
) => PromiseLike<unknown>
async function invoke(
  rpc: Rpc,
  owner: string,
  start?: { key: string; reason: z.infer<typeof startInput>['reason'] },
) {
  let raw: unknown
  try {
    raw = await rpc(start ? 'start_mobile_clinical_full' : 'get_mobile_reevaluation_cycle', {
      p_user_id: owner,
      ...(start ? { p_operation_key: start.key, p_reason: start.reason } : {}),
    })
  } catch {
    throw clinicalFullError('unavailable')
  }
  if (
    !raw ||
    typeof raw !== 'object' ||
    Array.isArray(raw) ||
    !Object.hasOwn(raw, 'data') ||
    !Object.hasOwn(raw, 'error')
  )
    throw clinicalFullError('unavailable')
  const packet = raw as { data: unknown; error: unknown }
  if (packet.error !== null) {
    const code =
      packet.error && typeof packet.error === 'object' && 'code' in packet.error
        ? packet.error.code
        : null
    throw clinicalFullError(
      code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
    )
  }
  let state: ReturnType<typeof parseReevaluationCycleRpcState>
  try {
    state = parseReevaluationCycleRpcState(packet.data)
  } catch {
    throw clinicalFullError('unavailable')
  }
  const cycle = state.cycle
  return clinicalFullEntryDto.parse({
    version: 1,
    availability: state.availability,
    unavailable_reason: state.unavailable_reason,
    clock: state.clock,
    cycle: cycle
      ? { id: cycle.id, kind: cycle.kind, status: cycle.status, revision: cycle.revision }
      : null,
  })
}
export function createClinicalFullEntryRoutes(
  dependencies: {
    readonly enabled: boolean
    admitLegacy?(client: ServiceClient, owner: string): Promise<void>
  },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true
  const admitLegacy = dependencies.admitLegacy?.bind(dependencies)
  const fixedRuntime =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  const route = (start: boolean) =>
    createMobileRoute(async (context) => {
      if (!enabled)
        throw new MobileApiError(404, 'clinical_full_entry_unavailable', 'Review unavailable')
      if (new URL(context.request.url).searchParams.size) throw clinicalFullError('invalid')
      const owner = authenticatedReevaluationOwner(structuredClone(context.auth)).toLowerCase()
      const rpc = context.supabase.rpc.bind(context.supabase) as unknown as Rpc
      let input: { key: string; reason: z.infer<typeof startInput>['reason'] } | undefined
      if (start) {
        const key = uuid.parse(requireIdempotencyKey(context.request)).toLowerCase()
        const body = startInput.parse(await readJsonBody(context.request, 2048))
        input = { key, reason: body.reason }
      }
      await admitLegacy?.(context.supabase, owner)
      return mobileSuccess(await invoke(rpc, owner, input), context.requestId)
    }, fixedRuntime)
  return Object.freeze({ GET: route(false), START: route(true) })
}
