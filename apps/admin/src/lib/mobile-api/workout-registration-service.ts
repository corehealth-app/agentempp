import {
  observeWorkoutStrengthCatalogue,
  type WorkoutStrengthCataloguePort,
} from '@mpp/agent/workout-strength-catalogue'
import { confirmedWorkoutLogIDFromCapture } from '@mpp/agent/workout-strength-identity'
import type { Json, ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import type { RegistrationProposalInput } from './contracts'
import { MobileApiError } from './http'
import { loadPendingRows, meDto, pendingRegistrationDto } from './read-model'
import {
  buildWorkoutRegistrationCandidate,
  prepareWorkoutRegistrationConfirmation,
} from './registration-service'
import {
  createWorkoutRegistrationRepository,
  toWorkoutRegistrationDto,
  type WorkoutRegistration,
  type WorkoutRegistrationPort,
} from './workout-registration-repository'
import { workoutRegistrationEnabled } from './workout-registration-switch'

type WorkoutInput = Extract<RegistrationProposalInput, { kind: 'workout' }>
type Repository = ReturnType<typeof createWorkoutRegistrationRepository>
type Confirmation = Awaited<ReturnType<Repository['confirm']>>
type Denial = {
  status: 'forbidden' | 'conflict'
  reason: string
  registration?: WorkoutRegistration
}

function requireEnabled(): void {
  if (!workoutRegistrationEnabled())
    throw new MobileApiError(
      503,
      'workout_registration_unavailable',
      'Workout review is temporarily unavailable.',
    )
}

/** The existing authenticated /me read advertises availability for NEW intents.
 * A client must retain the protocol in an immutable attempt, including retry. */
export function meWithWorkoutRegistrationCapability(auth: MobileAuthContext) {
  return {
    ...meDto(auth),
    ...(workoutRegistrationEnabled() ? { workout_registration_protocol: 'ui-v1' as const } : {}),
  }
}

function repository(supabase: ServiceClient): Repository {
  return createWorkoutRegistrationRepository(supabase as unknown as WorkoutRegistrationPort)
}

export function requireWorkoutRequestKey(key: string): string {
  if (!/^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/.test(key)) {
    throw new MobileApiError(
      400,
      'invalid_workout_idempotency_key',
      'A UUID Idempotency-Key is required for this workout intent.',
    )
  }
  return key
}

function reject(result: Denial): never {
  if (result.status === 'forbidden')
    throw new MobileApiError(
      409,
      'registration_authority_stale',
      'This workout is no longer available for this session.',
    )
  const details = result.registration
    ? { registration: toWorkoutRegistrationDto(result.registration) }
    : undefined
  const codes: Record<string, string> = {
    revision_conflict: 'registration_revision_conflict',
    request_content_conflict: 'registration_request_conflict',
    request_key_conflict: 'registration_request_conflict',
    unproved_pending: 'registration_request_conflict',
    already_confirmed: 'registration_already_confirmed',
    expired: 'registration_expired',
    not_pending: 'registration_not_pending',
    revision_exhausted: 'registration_revision_exhausted',
    capture_not_accepted: 'registration_capture_conflict',
  }
  throw new MobileApiError(
    result.reason === 'expired' ? 410 : 409,
    codes[result.reason] ?? 'registration_update_conflict',
    'Review the current workout before changing it.',
    details,
  )
}

/** Admission happens before the route's HTTP claim/cache. The returned closure
 * retains this exact input/owner/key; replay never promotes an old namespace. */
export async function admitWorkoutProposal(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  input: WorkoutInput,
  httpKey: string,
) {
  requireEnabled()
  const key = `wui1:${requireWorkoutRequestKey(httpKey)}`
  const owner = auth.userId
  const originalInput = structuredClone(input)
  const originalAuth = { ...auth, patient: { ...auth.patient } }
  const repo = repository(supabase)
  const admission = await repo.admit(owner, key, originalInput)
  if (!('admission' in admission)) reject(admission)
  const admissionID = admission.admission.admissionID
  return {
    async execute() {
      requireEnabled()
      let result = await repo.materialize(owner, admissionID, originalInput, null, null)
      if (result.status === 'preparation_required') {
        const proposal = await buildWorkoutRegistrationCandidate(
          supabase,
          originalAuth,
          originalInput,
          key,
        )
        const expiry = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
        result = await repo.materialize(owner, admissionID, originalInput, proposal, expiry)
      }
      if (result.status === 'preparation_required')
        throw new TypeError('Unexpected workout materialization probe')
      if (!('pendingID' in result)) reject(result)
      const current = await repo.get(owner, result.pendingID)
      if (current.status !== 'available') reject(current)
      return toWorkoutRegistrationDto(current.registration)
    },
  }
}

export async function editVersionedWorkoutRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  id: string,
  input: WorkoutInput,
  httpKey: string,
  expectedRevision: number,
) {
  requireEnabled()
  const key = `wue1:${requireWorkoutRequestKey(httpKey)}`
  const owner = auth.userId
  const originalInput = structuredClone(input)
  const repo = repository(supabase)
  let result = await repo.edit(owner, id, expectedRevision, key, originalInput, null)
  if (result.status === 'preparation_required') {
    const proposal = await buildWorkoutRegistrationCandidate(supabase, auth, originalInput, key)
    result = await repo.edit(owner, id, expectedRevision, key, originalInput, proposal)
  }
  if (result.status === 'preparation_required') throw new TypeError('Unexpected workout edit probe')
  if (!('receipt' in result)) reject(result)
  return {
    ...toWorkoutRegistrationDto(result.registration),
    receipt: {
      requestKey: result.receipt.requestKey,
      expectedRevision: result.receipt.expectedRevision,
      resultRevision: result.receipt.resultRevision,
    },
  }
}

async function catalogue(
  supabase: ServiceClient,
  rawType: string,
): Promise<{ observation: Json | null; decision: Json }> {
  const observed = await observeWorkoutStrengthCatalogue(rawType, {
    enabled: true,
    createClient: () => supabase as unknown as WorkoutStrengthCataloguePort,
  })
  if (observed.status !== 'observed')
    throw new TypeError('Workout catalogue observer was not enabled')
  const classification = observed.classification
  if (classification.status === 'unavailable')
    return { observation: null, decision: { status: 'unavailable', reason: classification.reason } }
  if (observed.read.status !== 'complete')
    throw new TypeError('Workout catalogue observation is incomplete')
  const read = observed.read
  const base = {
    status: classification.status,
    observationKey: classification.observation.observationKey,
    matcherVersion: classification.observation.matcherVersion,
    originalOperationType: rawType,
  }
  return {
    observation: {
      status: 'available',
      ...read.observation,
      complete: true,
      rowCount: String(read.activeRows.length),
      activeRows: read.activeRows.map((row) => ({ ...row })),
    },
    decision:
      classification.status === 'matched'
        ? { ...base, method: classification.method, selectedRowID: classification.catalogue.id }
        : { ...base, reason: classification.reason },
  }
}

function record(value: Json | undefined): { [key: string]: Json | undefined } | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : null
}

function needsStoredCatalogue(result: Confirmation): boolean {
  if (
    result.status !== 'conflict' ||
    result.reason !== 'capture_not_accepted' ||
    !('capture' in result)
  )
    return false
  const strength = result.capture.strength
  return (
    result.capture.legacy_result === null &&
    strength.status === 'forbidden' &&
    strength.reason === 'invalid_authority'
  )
}

export async function confirmVersionedWorkoutRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  id: string,
  expectedRevision: number,
) {
  requireEnabled()
  const owner = auth.userId
  const repo = repository(supabase)
  let result = await repo.confirm(owner, id, expectedRevision, null, null, null)
  if (
    (result.status === 'unavailable' && result.reason === 'preparation_required') ||
    needsStoredCatalogue(result)
  ) {
    // A stored S7 winner needs only an observation. It must not depend on the
    // current weight/config/calculation again, and no13 JSON is round-tripped.
    if (!('registration' in result)) throw new TypeError('Missing workout preparation projection')
    const registration = result.registration
    const rawType = registration.proposal.workoutType
    if (typeof rawType !== 'string') throw new TypeError('Missing workout proposal type')
    const needsPreparation = result.status === 'unavailable'
    const [args, observed] = await Promise.all([
      needsPreparation
        ? prepareWorkoutRegistrationConfirmation(supabase, auth, registration.proposal)
        : Promise.resolve(null),
      catalogue(supabase, rawType),
    ])
    result = await repo.confirm(
      owner,
      id,
      expectedRevision,
      args,
      observed.observation,
      observed.decision,
    )
  }
  if (result.status === 'forbidden' || result.status === 'conflict') reject(result)
  if (result.status !== 'confirmed' && result.status !== 'reused')
    throw new MobileApiError(
      503,
      'workout_registration_unavailable',
      'Workout confirmation is temporarily unavailable.',
    )
  const legacy = record(result.capture.legacy_result)
  const strength = result.capture.strength
  const binding = record(strength.binding)
  const deduped =
    legacy?.deduped === true ||
    legacy?.inserted === false ||
    (legacy === null &&
      ((binding !== null && binding.resolution !== 'sql_insert') ||
        (strength.status === 'unavailable' && strength.reason === 'legacy_provenance_gap')))
  const rawType = result.registration.proposal.workoutType
  const confirmedWorkoutID =
    typeof rawType === 'string' ? confirmedWorkoutLogIDFromCapture(strength, owner, rawType) : null
  return {
    ...toWorkoutRegistrationDto(result.registration),
    already_confirmed: result.status === 'reused',
    deduped,
    ...(confirmedWorkoutID === null ? {} : { confirmed_workout_id: confirmedWorkoutID }),
  }
}

export async function cancelVersionedWorkoutRegistration(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  id: string,
  expectedRevision: number,
) {
  requireEnabled()
  const result = await repository(supabase).cancel(auth.userId, id, expectedRevision)
  if (result.status === 'forbidden' || result.status === 'conflict') reject(result)
  return toWorkoutRegistrationDto(result.registration)
}

export async function loadVersionedWorkoutRegistration(
  supabase: ServiceClient,
  userID: string,
  id: string,
) {
  requireEnabled()
  const result = await repository(supabase).get(userID, id)
  if (result.status !== 'available') reject(result)
  return toWorkoutRegistrationDto(result.registration)
}

export async function loadWorkoutAwarePendingRegistrations(
  supabase: ServiceClient,
  userID: string,
) {
  requireEnabled()
  const rows = await loadPendingRows(supabase, userID)
  let repo: Repository | undefined
  const projected = await Promise.all(
    rows.map(async (row) => {
      const marker = (row as { workout_ui_admission_id?: unknown }).workout_ui_admission_id
      if (marker === null || marker === undefined) return pendingRegistrationDto(row)
      repo ??= repository(supabase)
      const current = await repo.get(userID, row.id)
      // A forbidden protected row is never promoted to the legacy projection.
      if (
        current.status !== 'available' ||
        current.registration.status !== 'pending' ||
        new Date(current.registration.expires_at).getTime() <= Date.now()
      )
        return null
      return toWorkoutRegistrationDto(current.registration)
    }),
  )
  return projected.filter((row) => row !== null)
}
