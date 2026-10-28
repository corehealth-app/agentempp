/** Explicit request-owned boundary. Captures remain observational; neither an
 * import nor construction admits a source. Never reuse this memo across requests. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { clinicalGenerationAuthoritySchema } from './clinical-generation-authority'
import {
  type CurrentClinicalSnapshot,
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  currentClinicalError,
  readCurrentClinicalState,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'

const uuid = z.string().uuid()
const receipt = z.discriminatedUnion('availability', [
  z
    .object({
      version: z.literal(1),
      availability: z.literal('admitted'),
      authority: clinicalGenerationAuthoritySchema,
    })
    .strict(),
  z
    .object({
      version: z.literal(1),
      availability: z.literal('signup_proven'),
      generation: uuid,
      epoch: uuid,
    })
    .strict(),
  z
    .object({
      version: z.literal(1),
      availability: z.literal('unavailable'),
      reason: z.literal('onboarding_incomplete'),
    })
    .strict(),
])
export interface LegacyClinicalAdmissionSource {
  admit(userId: string): Promise<unknown>
}
export interface CurrentClinicalAdmission {
  establish(
    before: CurrentClinicalSnapshot,
    current: CurrentClinicalStateSource,
  ): Promise<CurrentClinicalSnapshot>
}
function decode(raw: unknown, owner: string) {
  try {
    const text = JSON.stringify(raw)
    if (!text || text.length > 32768) throw Error('Invalid admission')
    const value = receipt.parse(JSON.parse(text))
    if (
      value.availability === 'admitted' &&
      (value.authority.kind !== 'legacy_transition' || value.authority.user_id !== owner)
    )
      throw Error('Invalid source')
    return value
  } catch {
    throw currentClinicalError('invalid_response')
  }
}
function facts(state: CurrentClinicalSnapshot) {
  return hashMobileRequest({
    user_id: state.user_id,
    mode: state.mode,
    profile_present: state.profile_present,
    generation_token: state.generation_token,
    profile_hash: state.profile_hash,
    date: state.date,
    timezone: state.timezone,
    body: state.body,
    assessment: state.assessment,
    missing: state.missing,
    health_state: state.health_state,
    safety: state.safety && {
      ...state.safety,
      observed_at: undefined,
    },
    calculation_config: state.calculation_config,
  })
}
function identity(state: CurrentClinicalSnapshot) {
  return hashMobileRequest({
    owner: state.user_id,
    epoch: state.epoch,
    generation: state.signup_generation,
    authority: state.generation_authority,
    token: state.generation_token,
  })
}
function sanitized(error: unknown): never {
  if (error instanceof MobileApiError)
    for (const kind of ['changed', 'busy', 'invalid_response', 'unavailable'] as const) {
      const safe = currentClinicalError(kind)
      if (error.code === safe.code && error.status === safe.status) throw safe
    }
  throw currentClinicalError('unavailable')
}
export function createCurrentClinicalAdmission(
  source: LegacyClinicalAdmissionSource,
): CurrentClinicalAdmission {
  const admit = source.admit.bind(source)
  let owner: string | undefined, original: string | undefined
  let first: Promise<CurrentClinicalSnapshot> | undefined
  async function establishFirst(
    before: CurrentClinicalSnapshot,
    current: CurrentClinicalStateSource,
  ) {
    if (before.generation_token?.onboarding_completed !== true || before.generation_authority)
      return before
    const accepted = decode(await admit(before.user_id), before.user_id)
    if (accepted.availability === 'unavailable') throw currentClinicalError('changed')
    const generation =
      accepted.availability === 'admitted' ? accepted.authority.generation : accepted.generation
    const epoch = accepted.availability === 'admitted' ? accepted.authority.epoch : accepted.epoch
    if (before.epoch !== null && before.epoch !== epoch) throw currentClinicalError('changed')
    const after = await captureCurrentClinicalState(current, {
      userId: before.user_id,
      mode: 'profile',
      expectedEpoch: epoch,
    })
    if (
      after.observed_at < before.observed_at ||
      facts(after) !== facts(before) ||
      after.signup_generation !== generation ||
      after.epoch !== epoch ||
      (accepted.availability === 'admitted'
        ? hashMobileRequest(after.generation_authority ?? null) !==
          hashMobileRequest(accepted.authority)
        : after.generation_authority?.kind !== 'signup_receipt')
    )
      throw currentClinicalError('changed')
    return after
  }
  return Object.freeze({
    async establish(raw: CurrentClinicalSnapshot, source: CurrentClinicalStateSource) {
      const before = readCurrentClinicalState(raw, raw.user_id)
      const current = Object.freeze({ capture: source.capture.bind(source) })
      try {
        if (!first) {
          owner = before.user_id
          original = hashMobileRequest({ facts: facts(before), identity: identity(before) })
          first = establishFirst(before, current)
          return await first
        }
        if (before.user_id !== owner) throw currentClinicalError('changed')
        const established = await first
        if (identity(before) === identity(established)) return before
        if (
          original === hashMobileRequest({ facts: facts(before), identity: identity(before) }) &&
          before.observed_at <= established.observed_at
        )
          return established
        throw currentClinicalError('changed')
      } catch (error) {
        return sanitized(error)
      }
    },
  })
}

/** Service-only RPC, server clock only. The caller must perform Auth,
 * entitlement, input and representation gates before invoking this port. */
export function createSupabaseLegacyClinicalAdmissionSource(
  client: ServiceClient,
): LegacyClinicalAdmissionSource {
  const rpc = client.rpc.bind(client) as unknown as (
    name: 'admit_mobile_clinical_legacy_generation',
    args: { p_user_id: string },
  ) => PromiseLike<unknown>
  return Object.freeze({
    async admit(userId: string) {
      const owner = uuid.parse(userId)
      try {
        const response = await rpc('admit_mobile_clinical_legacy_generation', { p_user_id: owner })
        if (
          !response ||
          typeof response !== 'object' ||
          Array.isArray(response) ||
          !Object.hasOwn(response, 'data') ||
          !Object.hasOwn(response, 'error')
        )
          throw currentClinicalError('invalid_response')
        const packet = response as { data: unknown; error: unknown }
        if (packet.error !== null) {
          const code =
            packet.error && typeof packet.error === 'object' && 'code' in packet.error
              ? packet.error.code
              : null
          throw currentClinicalError(
            code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
          )
        }
        return decode(packet.data, owner)
      } catch (error) {
        return sanitized(error)
      }
    },
  })
}
