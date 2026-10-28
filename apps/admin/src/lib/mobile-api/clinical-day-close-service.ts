/** Dormant server-owned orchestration. No route/default client or clock input.
 * Only a freshly captured backend context can produce a new numeric effect. */
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { prepareClinicalDayClose } from './clinical-day-close-calculation'
import {
  type ClinicalCloseScope,
  type ClinicalDayCloseEffect,
  clinicalCloseCommandSchema,
  clinicalClosedResultSchema,
  clinicalCloseError,
  clinicalCloseRequestSchema,
  clinicalResetResultSchema,
} from './clinical-day-close-contracts'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ClinicalDayCloseRepository {
  findReceipt(userId: string, key: string): Promise<unknown>
  capture(scope: ClinicalCloseScope): Promise<unknown>
  apply(
    scope: ClinicalCloseScope,
    key: string,
    contextHash: string,
    effect: ClinicalDayCloseEffect,
  ): Promise<unknown>
}
const envelope = z
  .object({
    user_id: uuid,
    operation_key: uuid,
    request: clinicalCloseRequestSchema,
    result: z.unknown(),
  })
  .strict()
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
function readResult(raw: unknown, scope: ClinicalCloseScope, key: string) {
  const packet = envelope.parse(raw),
    request = packet.request
  if (
    !same(packet.user_id, scope.userId) ||
    !same(packet.operation_key, key) ||
    request.from !== scope.from ||
    request.date !== scope.date ||
    request.timezone !== scope.timezone
  )
    throw clinicalCloseError('unavailable')
  if (scope.date === null) return clinicalResetResultSchema.parse(packet.result)
  const result = clinicalClosedResultSchema.parse(packet.result)
  if (result.date !== scope.date || result.detail.progress.lastActiveDate !== scope.date)
    throw clinicalCloseError('unavailable')
  return result
}
export function createClinicalDayCloseService(dependencies: {
  readonly enabled: boolean
  readonly repository: ClinicalDayCloseRepository
}) {
  const enabled = dependencies.enabled === true
  // Bind callbacks once; mutable dependency objects cannot switch repositories
  // while an awaited original-receipt lookup is in flight.
  const findReceipt = dependencies.repository.findReceipt.bind(dependencies.repository)
  const capture = dependencies.repository.capture.bind(dependencies.repository)
  const apply = dependencies.repository.apply.bind(dependencies.repository)
  return Object.freeze({
    async run(auth: MobileAuthContext, input: unknown) {
      const userId = authenticatedReevaluationOwner(auth).toLowerCase()
      try {
        const command = clinicalCloseCommandSchema.parse(input)
        const key = command.operationKey.toLowerCase()
        const scope: ClinicalCloseScope = Object.freeze({
          userId,
          from: command.from,
          date: command.date,
          timezone: command.timezone,
        })
        if (!enabled) return { kind: 'unavailable' as const, reason: 'disabled' as const }
        const original = await findReceipt(userId, key)
        // Original ACK survives reset, target changes and photo disposal. Never
        // recapture or recompute a successful keyed operation on this branch.
        if (original !== null) return readResult(original, scope, key)
        const raw = await capture(scope)
        const prepared = prepareClinicalDayClose(raw, scope)
        if (prepared.kind === 'skip') return prepared.result
        const result = await apply(scope, key, prepared.contextHash, prepared.effect)
        return readResult(result, scope, key)
      } catch (error) {
        if (error instanceof MobileApiError) {
          for (const kind of ['changed', 'busy'] as const)
            if (error.status === 409 && error.code === `mobile_clinical_close_${kind}`)
              throw clinicalCloseError(kind)
        }
        throw clinicalCloseError('unavailable')
      }
    },
  })
}
