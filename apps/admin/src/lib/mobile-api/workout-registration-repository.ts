import type { Json } from '@mpp/db'
import { z } from 'zod'
import type { RegistrationProposalInput } from './contracts'
import { sanitizePendingProposal } from './read-model'

type WorkoutInput = Extract<RegistrationProposalInput, { kind: 'workout' }>
type RpcName =
  | 'admit_mobile_workout_registration'
  | 'materialize_mobile_workout_registration'
  | 'get_mobile_workout_registration'
  | 'edit_mobile_workout_registration'
  | 'cancel_mobile_workout_registration'
  | 'confirm_mobile_workout_registration'

/** Internal backend port. No client factory, environment switch or product caller
 * is activated here. Shape validation is not proof of database provenance. */
export interface WorkoutRegistrationPort {
  rpc(
    name: RpcName,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown | null }>
}

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
const revision = z.number().int().min(0).max(2147483647)
const timestamp = z.string().datetime({ offset: true })
const pendingStatus = z.enum(['pending', 'confirmed', 'cancelled', 'expired'])
const createKey = z
  .string()
  .regex(/^wui1:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/)
const editKey = z
  .string()
  .regex(/^wue1:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/)
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.string(), z.number().finite(), z.boolean(), z.array(json), z.record(json)]),
)

const registrationSchema = z
  .object({
    id: uuid,
    status: pendingStatus,
    created_at: timestamp,
    expires_at: timestamp,
    resolved_at: timestamp.nullable(),
    proposal: z.record(json).refine((value) => value.kind === 'workout'),
    workout_protocol: z.literal('ui-v1'),
    content_revision: revision,
  })
  .strict()

export type WorkoutRegistration = z.infer<typeof registrationSchema>

const forbidden = z
  .object({
    status: z.literal('forbidden'),
    reason: z.enum([
      'invalid_admission',
      'stale_epoch',
      'pending_missing',
      'invalid_confirmation',
      'unproved_lifecycle',
      'stale_lifecycle',
      'stale_workout',
      'mixed_owner',
      'invalid_authority',
    ]),
  })
  .strict()
const proposalConflict = z
  .object({
    status: z.literal('conflict'),
    reason: z.enum(['request_content_conflict', 'unproved_pending']),
  })
  .strict()
const admissionSchema = z.union([
  z
    .object({
      status: z.enum(['admitted', 'reused']),
      admission: z
        .object({
          ownerID: uuid,
          admissionID: uuid,
          epoch: uuid,
          requestNamespace: z.literal('mobile_workout_proposal_v1'),
          requestKey: createKey,
          requestHash: z.string().regex(/^[a-f0-9]{64}$/),
          admittedAt: timestamp,
        })
        .strict(),
    })
    .strict(),
  forbidden,
  proposalConflict,
])
const materializationSchema = z.union([
  z
    .object({
      status: z.enum(['materialized', 'reused']),
      pendingID: uuid,
      pendingStatus,
      cancelledCount: z.number().int().nonnegative(),
    })
    .strict(),
  forbidden,
  proposalConflict,
])
const projectionSchema = z.union([
  z.object({ status: z.literal('available'), registration: registrationSchema }).strict(),
  forbidden,
])
const conflict = z
  .object({
    status: z.literal('conflict'),
    reason: z.enum([
      'already_confirmed',
      'not_pending',
      'revision_conflict',
      'expired',
      'request_content_conflict',
      'request_key_conflict',
      'revision_exhausted',
    ]),
    registration: registrationSchema,
  })
  .strict()
const editSchema = z.union([
  z
    .object({
      status: z.enum(['edited', 'reused']),
      registration: registrationSchema,
      receipt: z
        .object({ requestKey: editKey, expectedRevision: revision, resultRevision: revision })
        .strict(),
    })
    .strict(),
  conflict,
  forbidden,
])
const cancelSchema = z.union([
  z.object({ status: z.enum(['cancelled', 'reused']), registration: registrationSchema }).strict(),
  conflict,
  forbidden,
])
// Capture is backend-only JSON. Its provenance, binding and fact are proved by
// the atomic SQL/resolver; this adapter neither reinterprets nor exposes it.
const captureSchema = z.object({ legacy_result: json, strength: z.record(json) }).strict()
const confirmationSchema = z.union([
  z
    .object({
      status: z.enum(['confirmed', 'reused']),
      registration: registrationSchema,
      capture: captureSchema,
    })
    .strict(),
  z
    .object({
      status: z.literal('unavailable'),
      reason: z.literal('preparation_required'),
      registration: registrationSchema,
    })
    .strict(),
  z
    .object({
      status: z.literal('conflict'),
      reason: z.literal('capture_not_accepted'),
      registration: registrationSchema,
      capture: captureSchema,
    })
    .strict(),
  conflict,
  forbidden,
])

function invalidReply(): never {
  throw new TypeError('Invalid workout registration reply')
}

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value)
  return parsed.success ? parsed.data : invalidReply()
}

function isCandidateRequired(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === '22023' &&
    'message' in error &&
    error.message === 'invalid_mobile_workout_proposal_candidate'
  )
}

function checkRegistration<T>(result: T, id: string): T {
  if (typeof result === 'object' && result !== null && 'registration' in result) {
    const registration = result.registration as WorkoutRegistration
    if (registration.id.toLowerCase() !== id.toLowerCase()) invalidReply()
  }
  return result
}

/** HTTP projection is a closed list, including on conflict. Never spread the
 * raw SQL projection, capture, provider, admission, hash or legacy arguments. */
export function toWorkoutRegistrationDto(registration: WorkoutRegistration) {
  return {
    id: registration.id,
    status: registration.status,
    created_at: registration.created_at,
    expires_at: registration.expires_at,
    resolved_at: registration.resolved_at,
    proposal: sanitizePendingProposal(registration.proposal),
    workout_protocol: registration.workout_protocol,
    content_revision: registration.content_revision,
  }
}

export function createWorkoutRegistrationRepository(port: WorkoutRegistrationPort) {
  async function call(name: RpcName, args: Record<string, unknown>, candidateProbe = false) {
    const rpc = port.rpc
    if (typeof rpc !== 'function')
      throw new TypeError('Workout registration port requires a callable rpc')
    // Preserve the caller's first preparation and immutable attempt values;
    // no JSON stringify/parse, normalization or reconstruction of the13 args.
    const reply = await rpc.call(port, name, structuredClone(args))
    if (!reply || typeof reply !== 'object' || !('data' in reply) || !('error' in reply))
      invalidReply()
    if (reply.error !== null) {
      if (candidateProbe && isCandidateRequired(reply.error))
        return { preparationRequired: true as const }
      throw reply.error
    }
    return { data: reply.data }
  }

  return {
    async admit(ownerID: string, requestKey: string, input: WorkoutInput) {
      uuid.parse(ownerID)
      createKey.parse(requestKey)
      const reply = await call('admit_mobile_workout_registration', {
        p_user_id: ownerID,
        p_request_key: requestKey,
        p_input: input,
      })
      const result = parse(admissionSchema, reply.data)
      if (
        'admission' in result &&
        (result.admission.ownerID.toLowerCase() !== ownerID.toLowerCase() ||
          result.admission.requestKey !== requestKey)
      )
        invalidReply()
      return result
    },
    async materialize(
      ownerID: string,
      admissionID: string,
      input: WorkoutInput,
      proposal: Json | null,
      expiresAt: string | null,
    ) {
      uuid.parse(ownerID)
      uuid.parse(admissionID)
      const reply = await call(
        'materialize_mobile_workout_registration',
        {
          p_user_id: ownerID,
          p_admission_id: admissionID,
          p_input: input,
          p_proposal: proposal,
          p_expires_at: expiresAt,
        },
        proposal === null,
      )
      if ('preparationRequired' in reply) return { status: 'preparation_required' as const }
      return parse(materializationSchema, reply.data)
    },
    async get(ownerID: string, registrationID: string) {
      uuid.parse(ownerID)
      uuid.parse(registrationID)
      const reply = await call('get_mobile_workout_registration', {
        p_user_id: ownerID,
        p_registration_id: registrationID,
      })
      return checkRegistration(parse(projectionSchema, reply.data), registrationID)
    },
    async edit(
      ownerID: string,
      registrationID: string,
      expectedRevision: number,
      requestKey: string,
      input: WorkoutInput,
      proposal: Json | null,
    ) {
      uuid.parse(ownerID)
      uuid.parse(registrationID)
      revision.parse(expectedRevision)
      editKey.parse(requestKey)
      const reply = await call(
        'edit_mobile_workout_registration',
        {
          p_user_id: ownerID,
          p_registration_id: registrationID,
          p_expected_revision: expectedRevision,
          p_request_key: requestKey,
          p_input: input,
          p_proposal: proposal,
        },
        proposal === null,
      )
      if ('preparationRequired' in reply) return { status: 'preparation_required' as const }
      const result = checkRegistration(parse(editSchema, reply.data), registrationID)
      if (
        'receipt' in result &&
        (result.receipt.requestKey !== requestKey ||
          result.receipt.expectedRevision !== expectedRevision ||
          result.receipt.resultRevision !== expectedRevision + 1 ||
          result.registration.content_revision < result.receipt.resultRevision ||
          (result.status === 'edited' &&
            (result.registration.content_revision !== result.receipt.resultRevision ||
              result.registration.status !== 'pending')))
      )
        invalidReply()
      return result
    },
    async cancel(ownerID: string, registrationID: string, expectedRevision: number) {
      uuid.parse(ownerID)
      uuid.parse(registrationID)
      revision.parse(expectedRevision)
      const reply = await call('cancel_mobile_workout_registration', {
        p_user_id: ownerID,
        p_registration_id: registrationID,
        p_expected_revision: expectedRevision,
      })
      const result = checkRegistration(parse(cancelSchema, reply.data), registrationID)
      if (
        (result.status === 'cancelled' || result.status === 'reused') &&
        (result.registration.status !== 'cancelled' ||
          result.registration.content_revision !== expectedRevision)
      )
        invalidReply()
      return result
    },
    async confirm(
      ownerID: string,
      registrationID: string,
      expectedRevision: number,
      legacyArguments: Json | null,
      catalogueObservation: Json | null,
      catalogueDecision: Json | null,
    ) {
      uuid.parse(ownerID)
      uuid.parse(registrationID)
      revision.parse(expectedRevision)
      const reply = await call('confirm_mobile_workout_registration', {
        p_user_id: ownerID,
        p_registration_id: registrationID,
        p_expected_revision: expectedRevision,
        p_legacy_arguments: legacyArguments,
        p_catalogue_observation: catalogueObservation,
        p_catalogue_decision: catalogueDecision,
      })
      const result = checkRegistration(parse(confirmationSchema, reply.data), registrationID)
      if (
        (result.status === 'confirmed' || result.status === 'reused') &&
        (result.registration.status !== 'confirmed' ||
          result.registration.content_revision !== expectedRevision)
      )
        invalidReply()
      return result
    },
  }
}
