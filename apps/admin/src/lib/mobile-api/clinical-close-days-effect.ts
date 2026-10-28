/** Dormant HTTP effect composition only. No route/default enables it. Guards
 * and discovery stay with the existing wrapper; SQL owns every mutation. */
import { randomUUID } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { clinicalCloseError } from './clinical-day-close-contracts'
import { createClinicalDayCloseService } from './clinical-day-close-service'
import type { ClinicalHttpDependencies } from './current-clinical-http'
import { closeOpenDaysOnRequest } from './day-close-on-request'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseClinicalDayCloseRepository } from './supabase-clinical-day-close'

type ClinicalService = Pick<ReturnType<typeof createClinicalDayCloseService>, 'run'>
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
export function createClinicalCloseDaysEffect(
  options: {
    readonly env?: Record<string, string | undefined>
    readonly now?: Date
    readonly nextOperationKey?: () => string
    readonly createService?: (client: ServiceClient) => ClinicalService
  } = {},
): ClinicalHttpDependencies['closeDays'] {
  const env = options.env === undefined ? undefined : Object.freeze({ ...options.env })
  const now = options.now === undefined ? undefined : new Date(options.now.getTime())
  const nextKey = options.nextOperationKey ?? randomUUID
  const createService =
    options.createService ??
    ((client: ServiceClient) =>
      createClinicalDayCloseService({
        enabled: true,
        repository: createSupabaseClinicalDayCloseRepository(client),
      }))
  return async (input) => {
    const auth = freeze(structuredClone(input.auth))
    const owner = authenticatedReevaluationOwner(auth).toLowerCase()
    const client = input.supabase
    try {
      if (input.admission.owner.toLowerCase() !== owner) throw clinicalCloseError('changed')
      const service = createService(client),
        run = service.run.bind(service)
      const used = new Set<string>()
      const key = () => {
        const value = uuid.parse(nextKey()).toLowerCase()
        if (used.has(value)) throw clinicalCloseError('unavailable')
        used.add(value)
        return value
      }
      const scopeOwner = (userId: string) => {
        if (userId.toLowerCase() !== owner) throw clinicalCloseError('changed')
      }
      await closeOpenDaysOnRequest(
        { auth, supabase: client },
        {
          env,
          now,
          clinicalAuthority: {
            async closeDate(scope) {
              scopeOwner(scope.userId)
              const result = await run(auth, {
                operationKey: key(),
                from: scope.from,
                date: scope.date,
                timezone: scope.timezone,
              })
              if ('closed' in result && result.date === scope.date) {
                if (result.closed) return result
                if (result.skipReason === 'already_closed' || result.skipReason === 'inactive')
                  return {
                    date: result.date,
                    closed: false,
                    dryRun: false,
                    late: result.late,
                    reason: result.skipReason,
                  }
                if (
                  ['earlier_date_changed', 'not_closable_yet', 'behind_frontier'].includes(
                    result.skipReason,
                  )
                )
                  throw clinicalCloseError('changed')
              }
              throw clinicalCloseError('unavailable')
            },
            async resetInactive(scope) {
              scopeOwner(scope.userId)
              const result = await run(auth, {
                operationKey: key(),
                from: scope.from,
                date: null,
                timezone: scope.timezone,
              })
              if ('kind' in result && result.kind === 'applied') return result.reset
              if ('kind' in result && result.kind === 'unchanged') {
                if (result.reset.reason === 'unchanged') return null
                if (result.reset.reason === 'pending_activity') throw clinicalCloseError('changed')
              }
              throw clinicalCloseError('unavailable')
            },
          },
        },
      )
    } catch (error) {
      if (error instanceof MobileApiError)
        for (const kind of ['changed', 'busy'] as const)
          if (error.code === `mobile_clinical_close_${kind}` && error.status === 409)
            throw clinicalCloseError(kind)
      throw clinicalCloseError('unavailable')
    }
  }
}
