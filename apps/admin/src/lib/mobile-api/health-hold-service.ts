import { healthRiskSetSchema } from '@mpp/core/health-check'
import type { MobileAuthContext } from './auth'
import {
  type HealthHoldSnapshot,
  type HealthRiskDeclaration,
  healthHoldFailure,
  parseHealthHoldSnapshot,
  parseHealthRiskDeclaration,
  sanitizeHealthHoldFailure,
} from './health-hold-contracts'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

export interface HealthHoldRepository {
  get(userId: string): Promise<unknown>
  declare(userId: string, operationKey: string, items: readonly string[]): Promise<unknown>
}
export interface HealthHoldDependencies {
  readonly enabled: boolean
  readonly repository: HealthHoldRepository
}
export const disabledHealthHold = Object.freeze({
  availability: 'unavailable',
  reason: 'disabled',
} as const)
export type HealthHoldReadResult =
  | typeof disabledHealthHold
  | { availability: 'available'; state: HealthHoldSnapshot }
export type HealthHoldDeclarationResult =
  | typeof disabledHealthHold
  | ({ availability: 'available' } & HealthRiskDeclaration)

function authenticatedOwner(auth: MobileAuthContext): string {
  const ids = [
    auth?.userId,
    auth?.authUserId,
    auth?.identity?.id,
    auth?.patient?.id,
    auth?.patient?.authUserId,
  ]
  if (
    ids.some((id) => !uuid.safeParse(id).success) ||
    auth.userId.toLowerCase() !== auth.patient.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.identity.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.patient.authUserId.toLowerCase() ||
    auth.patient.status !== 'active'
  )
    throw healthHoldFailure('identity_invalid')
  return auth.userId.toLowerCase()
}

/** Injection-only: no route, default configuration or clinical consumer enables this authority. */
export async function getHealthHold(
  auth: MobileAuthContext,
  dependencies: HealthHoldDependencies,
): Promise<HealthHoldReadResult> {
  const userId = authenticatedOwner(auth)
  if (dependencies.enabled !== true) return disabledHealthHold
  try {
    return {
      availability: 'available',
      state: parseHealthHoldSnapshot(await dependencies.repository.get(userId), userId),
    }
  } catch (error) {
    throw sanitizeHealthHoldFailure(error)
  }
}
export async function declareHealthRisk(
  auth: MobileAuthContext,
  operationKey: string,
  items: unknown,
  dependencies: HealthHoldDependencies,
): Promise<HealthHoldDeclarationResult> {
  const userId = authenticatedOwner(auth)
  const parsed = healthRiskSetSchema.safeParse(items)
  if (!uuid.safeParse(operationKey).success || !parsed.success)
    throw healthHoldFailure('invalid_input')
  if (dependencies.enabled !== true) return disabledHealthHold
  const key = operationKey.toLowerCase()
  try {
    const response = await dependencies.repository.declare(userId, key, parsed.data)
    return {
      availability: 'available',
      ...parseHealthRiskDeclaration(response, userId, key, parsed.data),
    }
  } catch (error) {
    throw sanitizeHealthHoldFailure(error)
  }
}
