/** Dormant injected orchestrator. No default client, RPC grant, route, cron or
 * feature flag. A trusted private transport and all final consumers still have
 * to be verified before this can be composed into a runtime. */
import {
  clinicalCivilDateSchema as civilDate,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { calculateClinicalSnapshotTargets } from './clinical-snapshot-calculation'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ClinicalDailyCalculation {
  readonly version: 1
  readonly formulaKcal: number | null
  readonly maintenanceKcal: number | null
  readonly sedentaryKcal: number | null
  readonly proteinTarget: number | null
  readonly maintenanceProteinTarget: number | null
}
export interface ClinicalDailyRepository {
  /** Returns the exact user_id/operation_key/result projection, or null. */
  findReceipt(userId: string, operationKey: string): Promise<unknown>
  /** Captures APPLICATION using the SQL clock, never a client timestamp. */
  capture(userId: string): Promise<unknown>
  /** Exactly one attempt. The adapter must retain its trusted owner binding. */
  apply(
    userId: string,
    operationKey: string,
    contextHash: string,
    calculation: ClinicalDailyCalculation,
  ): Promise<unknown>
}
interface Dependencies {
  readonly enabled: boolean
  readonly repository: ClinicalDailyRepository
}
const commandSchema = z.object({ operationKey: uuid }).strict()
const envelope = z.object({ user_id: uuid, operation_key: uuid, result: z.unknown() }).strict()
const integer = z.number().int().safe()
const kcal = integer.positive().nullable()
const protein = z.number().finite().min(0).max(9999.99).nullable()
const revision = z
  .string()
  .regex(/^[1-9][0-9]{0,18}$/)
  .refine((n) => n.length < 19 || n <= '9223372036854775807')
const applied = z.object({
  version: z.literal(1),
  availability: z.literal('applied'),
  application_id: uuid,
  application_no: revision,
  date: civilDate,
  state: z.enum(['none', 'running', 'suspended', 'completed']),
  reason: z.enum([
    'safety',
    'confirmation_required',
    'confirmed_schedule',
    'confirmed_target',
    'stored_target',
    'unknown_ledger_preserved',
    'episode_formula',
    'signup_formula',
    'signup_stored_target',
    'signup_preserved_unknown',
  ]),
  needs_new_confirmation: z.boolean(),
  applied_at: instant,
  source_kind: z.enum(['full', 'signup', 'first_phase']).optional(),
  source_review_id: uuid.nullable(),
  source_signup_id: uuid.optional(),
  source_first_phase_id: uuid.nullable().optional(),
  schedule_review_id: uuid.nullable(),
  targets: z
    .object({
      calories_target: kcal,
      protein_target: protein,
      formula_target: kcal,
      effective_adjustment: integer.nullable(),
    })
    .strict(),
  episode: z.object({
    user_id: uuid,
    signup_generation: uuid,
    signup_epoch: uuid,
    first_phase_id: uuid.nullable().optional(),
    review_id: uuid.nullable().optional(),
  }),
})
const unavailable = z
  .object({
    version: z.literal(1),
    availability: z.literal('unavailable'),
    reason: z.enum([
      'clinical_episode_unavailable',
      'day_closed',
      'schedule_not_started',
      'phase_not_started',
    ]),
    date: civilDate,
  })
  .strict()
function unavailableError(): never {
  throw new MobileApiError(503, 'mobile_clinical_daily_unavailable', 'Clinical update unavailable')
}
/** Closed repository conflicts only; backend exception text is never public. */
export function clinicalDailyRepositoryError(kind: 'changed' | 'busy' | 'unavailable') {
  if (kind === 'changed')
    return new MobileApiError(
      409,
      'mobile_clinical_daily_changed',
      'Clinical update changed; refresh before trying again',
    )
  if (kind === 'busy')
    return new MobileApiError(
      409,
      'mobile_clinical_daily_busy',
      'Clinical update is busy; try again',
    )
  return new MobileApiError(503, 'mobile_clinical_daily_unavailable', 'Clinical update unavailable')
}
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
function readResult(
  raw: unknown,
  owner: string,
  key: string,
  current?: { signupGeneration: string; signupEpoch: string; date: string },
) {
  const packet = envelope.parse(raw)
  if (!same(packet.user_id, owner) || !same(packet.operation_key, key)) return unavailableError()
  const result = z.discriminatedUnion('availability', [applied, unavailable]).parse(packet.result)
  if (current && result.date !== current.date) return unavailableError()
  if (result.availability === 'unavailable') return result
  if (
    !same(result.episode.user_id, owner) ||
    (result.source_kind === 'signup'
      ? result.source_review_id !== null ||
        result.source_first_phase_id != null ||
        !result.source_signup_id ||
        !same(result.source_signup_id, result.episode.signup_generation) ||
        result.schedule_review_id !== null ||
        result.state !== 'none' ||
        !['signup_formula', 'signup_stored_target', 'signup_preserved_unknown', 'safety'].includes(
          result.reason,
        )
      : result.source_kind === 'first_phase'
        ? result.source_review_id !== null ||
          !result.source_first_phase_id ||
          !result.episode.first_phase_id ||
          !same(result.source_first_phase_id, result.episode.first_phase_id) ||
          result.episode.review_id !== null ||
          result.source_signup_id !== undefined ||
          result.schedule_review_id !== null ||
          result.state !== 'none' ||
          result.reason === 'confirmed_schedule' ||
          result.reason.startsWith('signup_')
        : result.source_review_id === null ||
          result.source_signup_id !== undefined ||
          result.source_first_phase_id != null ||
          result.reason.startsWith('signup_')) ||
    (current &&
      (!same(result.episode.signup_generation, current.signupGeneration) ||
        !same(result.episode.signup_epoch, current.signupEpoch)))
  )
    return unavailableError()
  const target = result.targets
  const delta =
    target.calories_target === null || target.formula_target === null
      ? null
      : target.calories_target - target.formula_target
  if (
    target.effective_adjustment !== delta ||
    (result.reason === 'signup_formula' &&
      (target.calories_target === null || target.formula_target !== target.calories_target)) ||
    (result.state === 'suspended' && !result.needs_new_confirmation)
  )
    return unavailableError()
  // Do not copy the complete private episode/form, health answers or profile.
  const { episode: _episode, ...publicResult } = result
  return publicResult
}

export function createClinicalDailyService(dependencies: Dependencies) {
  return {
    async apply(auth: MobileAuthContext, command: unknown) {
      // Capture immutable scope before the FIRST await, including receipt lookup.
      const owner = authenticatedReevaluationOwner(auth)
      const parsed = commandSchema.safeParse(command)
      if (!parsed.success)
        throw new MobileApiError(
          422,
          'mobile_clinical_daily_invalid_request',
          'A stable operation key is required',
        )
      const key = parsed.data.operationKey
      if (dependencies.enabled !== true)
        return {
          version: 1 as const,
          availability: 'unavailable' as const,
          reason: 'disabled',
          date: null,
        }
      try {
        const repository = dependencies.repository
        const original = await repository.findReceipt(owner, key)
        // An original acknowledgement survives generation/reset/purge. No
        // recapture, recalculation or mutation is permitted on this branch.
        if (original !== null) return readResult(original, owner, key)
        const snapshot = await repository.capture(owner)
        const calculated = calculateClinicalSnapshotTargets(snapshot, owner)
        const authority = calculated.authority
        if (authority.kind !== 'APPLICATION' || authority.cycleId !== null)
          return unavailableError()
        const localUnavailable = (reason: string) => ({
          version: 1 as const,
          availability: 'unavailable' as const,
          reason,
          date: authority.date,
        })
        if (!calculated.guarded) {
          if (calculated.legacyTarget.origin === 'unproven')
            return localUnavailable('legacy_formula_origin_unproven')
          if (calculated.proteinAuthority === 'unverified_table')
            return localUnavailable('protein_table_unverified')
          if (!calculated.automaticCalculationReady)
            return localUnavailable('calculation_unavailable')
        }
        // A HOLD/guard must still reach the SQL safety/suspension branch, but
        // cannot offer or apply a freshly calculated target. SQL rechecks the
        // fresh full context and preserves the actual old target atomically.
        const calculation: ClinicalDailyCalculation = calculated.guarded
          ? {
              version: 1,
              formulaKcal: null,
              maintenanceKcal: null,
              sedentaryKcal: null,
              proteinTarget: null,
              maintenanceProteinTarget: null,
            }
          : {
              version: 1,
              formulaKcal: calculated.formulaKcal,
              maintenanceKcal: calculated.maintenanceKcal,
              sedentaryKcal: calculated.sedentaryKcal,
              proteinTarget: calculated.proteinTarget,
              maintenanceProteinTarget: calculated.maintenanceProteinTarget,
            }
        const result = await repository.apply(owner, key, authority.contextHash, calculation)
        return readResult(result, owner, key, authority)
      } catch (error) {
        if (error instanceof MobileApiError && error.status === 409) {
          if (error.code === 'mobile_clinical_daily_changed')
            throw clinicalDailyRepositoryError('changed')
          if (error.code === 'mobile_clinical_daily_busy')
            throw clinicalDailyRepositoryError('busy')
        }
        return unavailableError()
      }
    },
  }
}
