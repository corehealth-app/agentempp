/** Dormant HTTP daily composition. Only an explicit server composition may use
 * it; this does not enable a route, capability, cron or client-side authority. */
import { randomUUID } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { clinicalDailyRepositoryError, createClinicalDailyService } from './clinical-daily-service'
import type { ClinicalHttpDependencies } from './current-clinical-http'
import { readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseClinicalDailyRepository } from './supabase-clinical-daily'

type DailyService = Pick<ReturnType<typeof createClinicalDailyService>, 'apply'>
const preservedReasons = new Set([
  'clinical_episode_unavailable',
  'day_closed',
  'schedule_not_started',
  'phase_not_started',
  'legacy_formula_origin_unproven',
  'protein_table_unverified',
  'calculation_unavailable',
])
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
export function createClinicalDailyEffect(
  options: {
    readonly nextOperationKey?: () => string
    readonly createService?: (client: ServiceClient) => DailyService
  } = {},
): ClinicalHttpDependencies['applyDaily'] {
  const nextKey = options.nextOperationKey ?? randomUUID
  const createService =
    options.createService ??
    ((client: ServiceClient) =>
      createClinicalDailyService({
        enabled: true,
        repository: createSupabaseClinicalDailyRepository(client),
      }))
  return async (input) => {
    const auth = freeze(structuredClone(input.auth))
    const owner = authenticatedReevaluationOwner(auth).toLowerCase()
    const client = input.supabase
    try {
      if (input.admission.owner.toLowerCase() !== owner)
        throw clinicalDailyRepositoryError('changed')
      const state = readCurrentClinicalState(input.admission.state, owner)
      // Neither a confirmed absence nor an unknown legacy phase is maintenance.
      // Skip only this target writer; HTTP still closes records and reads fresh.
      // In particular an assigned HOLD must reach SQL to suspend its schedule.
      if (
        state.phase_origin.kind === 'confirmed_no_plan' ||
        state.phase_origin.kind === 'legacy_unassigned'
      )
        return
      const service = createService(client),
        apply = service.apply.bind(service)
      const result = await apply(auth, { operationKey: uuid.parse(nextKey()).toLowerCase() })
      if (
        result.version === 1 &&
        (result.availability === 'applied' ||
          (result.availability === 'unavailable' && preservedReasons.has(result.reason)))
      )
        return
      throw clinicalDailyRepositoryError('unavailable')
    } catch (error) {
      if (error instanceof MobileApiError && error.status === 409)
        for (const kind of ['changed', 'busy'] as const)
          if (error.code === `mobile_clinical_daily_${kind}`)
            throw clinicalDailyRepositoryError(kind)
      throw clinicalDailyRepositoryError('unavailable')
    }
  }
}
