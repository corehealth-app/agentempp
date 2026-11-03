/** Optional enrichment after a saved effect. No registration writer is reachable
 * from this module; route/client negotiation is deliberately not installed. */
import { isDeepStrictEqual } from 'node:util'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  parseRegistrationFeedbackV2,
  prepareRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  type ConfirmedRegistration,
  identityFor,
  parseRegistrationFeedback,
  type RegistrationFeedbackIdentity,
} from './registration-feedback-receipt'
import { loadFeedbackV2ClinicalContext } from './registration-feedback-v2-clinical'
import {
  createSupabaseRegistrationFeedbackV2Store,
  type FeedbackV2Read,
  parseFeedbackV2Capture,
  type RegistrationFeedbackV2Store,
} from './registration-feedback-v2-store'

export type VersionedRegistrationFeedback = RegistrationFeedback | RegistrationFeedbackV2
export interface FeedbackV2ServiceDependencies {
  store?: RegistrationFeedbackV2Store
  loadClinical?: typeof loadFeedbackV2ClinicalContext
}
function boundIdentity(auth: MobileAuthContext, row: ConfirmedRegistration) {
  const owner = authenticatedReevaluationOwner(auth)
  const identity = identityFor(owner, row)
  if (!identity) return null
  return z
    .object({
      userId: z.string().uuid(),
      registrationId: z.string().uuid(),
      kind: z.enum(['meal', 'workout']),
    })
    .strict()
    .parse(identity)
}
function fromRead(
  value: FeedbackV2Read,
  identity: RegistrationFeedbackIdentity,
): VersionedRegistrationFeedback | null {
  if (value.action === 'available') return parseRegistrationFeedbackV2(value.feedback, identity)
  if (value.action === 'legacy') return parseRegistrationFeedback(value.feedback, identity)
  return null
}
/** A historical read never loads current source, prepares text or writes a
 * receipt. The future timeline must apply its current clinical read surface
 * separately, while preserving the immutable historical receipt. */
export async function readRegistrationFeedbackV2(
  db: ServiceClient,
  auth: MobileAuthContext,
  row: ConfirmedRegistration,
  reader: Pick<
    RegistrationFeedbackV2Store,
    'readReceipt'
  > = createSupabaseRegistrationFeedbackV2Store(db),
): Promise<VersionedRegistrationFeedback | null> {
  try {
    const identity = boundIdentity(structuredClone(auth), structuredClone(row))
    if (!identity) return null
    return fromRead(await reader.readReceipt(identity), identity)
  } catch {
    return null
  }
}
export async function ensureRegistrationFeedbackV2(
  db: ServiceClient,
  auth: MobileAuthContext,
  row: ConfirmedRegistration,
  dependencies: FeedbackV2ServiceDependencies = {},
): Promise<VersionedRegistrationFeedback | null> {
  try {
    const who = structuredClone(auth),
      savedRow = structuredClone(row)
    const identity = boundIdentity(who, savedRow)
    if (!identity) return null
    const source = dependencies.store ?? createSupabaseRegistrationFeedbackV2Store(db)
    // Snapshot callback identities before the first await, including injected
    // implementations. Private source aliases are detached again on capture.
    const store = Object.freeze({
      readReceipt: source.readReceipt.bind(source),
      capture: source.capture.bind(source),
      commit: source.commit.bind(source),
    })
    const loadClinical = dependencies.loadClinical ?? loadFeedbackV2ClinicalContext
    const existing = await store.readReceipt(identity)
    if (existing.action !== 'absent') return fromRead(existing, identity)
    const captured = await store.capture(identity)
    if (captured.action !== 'available') return null
    const observation = parseFeedbackV2Capture(captured.observation.context, identity)
    if (!isDeepStrictEqual(savedRow.proposal, observation.context.confirmed.proposal)) return null
    if (
      savedRow.confirmedWorkoutId !== undefined &&
      (observation.facts.registration.kind !== 'workout' ||
        savedRow.confirmedWorkoutId !== observation.facts.registration.log_id)
    )
      return null
    const clinical = await loadClinical(db, who, observation)
    const feedback = prepareRegistrationFeedbackV2({
      registrationId: identity.registrationId,
      localDate: observation.facts.localDate,
      locale: who.patient.locale,
      registration: observation.facts.registration,
      officialDay: clinical.officialDay,
      policy: clinical.policy,
      // Generated relationship summaries are not confirmed preferences.
      preferencesKnown: false,
    })
    try {
      const result = await store.commit({ ...identity, observation, feedback })
      if (result.action === 'committed' || result.action === 'replay')
        return parseRegistrationFeedbackV2(result.feedback, identity)
      if (result.action === 'legacy') return parseRegistrationFeedback(result.feedback, identity)
      return null
    } catch {
      // Unknown outcome: resolve once by immutable receipt. Never retry the
      // commit, re-run extraction or invoke a domain writer on this path.
      return fromRead(await store.readReceipt(identity), identity)
    }
  } catch {
    // No private provider/health detail reaches the public response or logs.
    // The caller's already-saved registration remains successful.
    return null
  }
}
