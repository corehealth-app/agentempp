import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import {
  disabledReevaluationCycleState,
  parseReevaluationCycleRpcState,
  type ReevaluationCycleState,
  reevaluationCycleUuidSchema,
} from './reevaluation-cycle-contracts'

export interface ReevaluationCycleRepository {
  get(userId: string): Promise<unknown>
  start(userId: string, idempotencyKey: string): Promise<unknown>
}

export interface ReevaluationCycleDependencies {
  readonly enabled: boolean
  readonly repository: ReevaluationCycleRepository
}

function authenticatedOwner(auth: MobileAuthContext): string {
  const ids = [
    auth?.userId,
    auth?.authUserId,
    auth?.identity?.id,
    auth?.patient?.id,
    auth?.patient?.authUserId,
  ]
  if (
    ids.some((id) => !reevaluationCycleUuidSchema.safeParse(id).success) ||
    auth.userId.toLowerCase() !== auth.patient.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.identity.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.patient.authUserId.toLowerCase() ||
    auth.patient.status !== 'active'
  )
    throw new MobileApiError(
      403,
      'mobile_reevaluation_identity_invalid',
      'Authenticated patient required',
    )
  return auth.userId
}

/** Injection-only foundation. No route, Today card or default composition enables it. */
export async function getReevaluationCycle(
  auth: MobileAuthContext,
  dependencies: ReevaluationCycleDependencies,
): Promise<ReevaluationCycleState> {
  const userId = authenticatedOwner(auth)
  if (dependencies.enabled !== true) return disabledReevaluationCycleState
  return parseReevaluationCycleRpcState(await dependencies.repository.get(userId))
}

export async function startReevaluationCycle(
  auth: MobileAuthContext,
  idempotencyKey: string,
  dependencies: ReevaluationCycleDependencies,
): Promise<ReevaluationCycleState> {
  const userId = authenticatedOwner(auth)
  if (!reevaluationCycleUuidSchema.safeParse(idempotencyKey).success)
    throw new MobileApiError(
      422,
      'mobile_reevaluation_invalid_key',
      'A stable idempotency key is required',
    )
  if (dependencies.enabled !== true) return disabledReevaluationCycleState
  return parseReevaluationCycleRpcState(await dependencies.repository.start(userId, idempotencyKey))
}
