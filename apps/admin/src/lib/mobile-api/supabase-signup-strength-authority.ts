import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import type {
  CapturedSignupStrengthRequest,
  SignupStrengthAuthoritySource,
  SignupStrengthEpochObservation,
  SignupStrengthRequestIdentity,
} from './signup-strength-authority'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
const key = z.string().regex(/^[A-Za-z0-9._:-]{8,128}$/)
const hash = z.string().regex(/^[0-9a-f]{64}$/)

/** Validate the civil date while retaining all original microseconds. */
function utc6(value: string): boolean {
  if (
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/.test(value) ||
    value.startsWith('0000-')
  )
    return false
  const milliseconds = `${value.slice(0, 23)}Z`
  const date = new Date(milliseconds)
  return Number.isFinite(date.getTime()) && date.toISOString() === milliseconds
}
const timestamp = z.string().refine(utc6)
const observeInput = z.object({ userId: uuid }).strict()
const bindInput = z
  .object({ userId: uuid, requestKey: key, requestHash: hash, expectedEpoch: uuid })
  .strict()
const admission = z
  .object({
    ownerID: uuid,
    admissionID: uuid,
    epoch: uuid,
    requestKey: key,
    requestHash: hash,
    admittedAt: timestamp,
  })
  .strict()
const observeReply = z
  .object({
    status: z.literal('observed'),
    observation: z
      .object({
        ownerID: uuid,
        epoch: uuid,
        changedAt: timestamp,
      })
      .strict(),
  })
  .strict()
const bindReply = z.union([
  z.object({ status: z.enum(['admitted', 'reused']), admission }).strict(),
  z
    .object({
      status: z.literal('forbidden'),
      reason: z.enum(['invalid_observation', 'stale_epoch']),
    })
    .strict(),
  z
    .object({ status: z.literal('conflict'), reason: z.literal('request_content_conflict') })
    .strict(),
])
const verifyReply = z.union([
  z.object({ status: z.literal('verified'), admission }).strict(),
  z
    .object({
      status: z.literal('forbidden'),
      reason: z.enum(['invalid_admission', 'stale_epoch']),
    })
    .strict(),
])

type RpcName =
  | 'observe_mobile_signup_strength_epoch'
  | 'admit_mobile_signup_strength_request'
  | 'verify_mobile_signup_strength_request'
type AuthorityRpc = (name: RpcName, parameters: Record<string, unknown>) => PromiseLike<unknown>

function failure(kind: 'invalid_input' | 'invalid_response' | 'unavailable'): MobileApiError {
  return new MobileApiError(
    500,
    `mobile_signup_strength_authority_${kind}`,
    'Unable to verify signup request authority',
  )
}
function parse<T>(
  schema: z.ZodType<T>,
  input: unknown,
  kind: 'invalid_input' | 'invalid_response' = 'invalid_response',
): T {
  try {
    const parsed = schema.safeParse(input)
    if (parsed.success) return parsed.data
  } catch {
    // Never expose internal wire fields or a ZodError as a public submission error.
  }
  throw failure(kind)
}
function refusal(
  reason: 'invalid_observation' | 'invalid_admission' | 'stale_epoch' | 'request_content_conflict',
): never {
  throw new MobileApiError(
    409,
    `mobile_signup_strength_${reason}`,
    'Reload and review the signup state before trying again',
  )
}

/** Injection seam only. Default application composition does not instantiate it. */
export function createSupabaseSignupStrengthAuthoritySource(
  supabase: ServiceClient,
): SignupStrengthAuthoritySource {
  // A narrow backend-only port preserves the generated DB types and original receiver.
  const rpc = supabase.rpc.bind(supabase) as unknown as AuthorityRpc
  async function invoke(name: RpcName, parameters: Record<string, unknown>): Promise<unknown> {
    let response: unknown
    try {
      response = await rpc(name, parameters)
    } catch {
      throw failure('unavailable')
    }
    if (
      !response ||
      typeof response !== 'object' ||
      Array.isArray(response) ||
      !Object.hasOwn(response, 'data') ||
      !Object.hasOwn(response, 'error')
    )
      throw failure('invalid_response')
    const envelope = response as { data: unknown; error: unknown }
    if (envelope.error !== null) throw failure('unavailable')
    return envelope.data
  }

  return Object.freeze({
    async observe(input: { readonly userId: string }): Promise<SignupStrengthEpochObservation> {
      const { userId } = parse(observeInput, input, 'invalid_input')
      const result = parse(
        observeReply,
        await invoke('observe_mobile_signup_strength_epoch', { p_user_id: userId }),
      )
      if (result.observation.ownerID.toLowerCase() !== userId.toLowerCase())
        throw failure('invalid_response')
      return Object.freeze({ userId, epoch: result.observation.epoch })
    },
    async bind(input: SignupStrengthRequestIdentity): Promise<CapturedSignupStrengthRequest> {
      const { userId, requestKey, requestHash, expectedEpoch } = parse(
        bindInput,
        input,
        'invalid_input',
      )
      const result = parse(
        bindReply,
        await invoke('admit_mobile_signup_strength_request', {
          p_user_id: userId,
          p_request_key: requestKey,
          p_request_hash: requestHash,
          p_expected_epoch: expectedEpoch,
        }),
      )
      if (result.status === 'forbidden' || result.status === 'conflict') refusal(result.reason)
      function sameIdentity(value: z.infer<typeof admission>): boolean {
        return (
          value.ownerID.toLowerCase() === userId.toLowerCase() &&
          value.epoch.toLowerCase() === expectedEpoch.toLowerCase() &&
          value.requestKey === requestKey &&
          value.requestHash === requestHash
        )
      }
      if (!sameIdentity(result.admission)) throw failure('invalid_response')
      const admissionId = result.admission.admissionID
      const admittedAt = result.admission.admittedAt
      return Object.freeze({
        userId,
        requestKey,
        requestHash,
        epoch: expectedEpoch,
        admissionId,
        async verifyReplay(): Promise<void> {
          const verified = parse(
            verifyReply,
            await invoke('verify_mobile_signup_strength_request', {
              p_user_id: userId,
              p_admission_id: admissionId,
              p_request_key: requestKey,
              p_request_hash: requestHash,
              p_expected_epoch: expectedEpoch,
            }),
          )
          if (verified.status === 'forbidden') refusal(verified.reason)
          if (
            !sameIdentity(verified.admission) ||
            verified.admission.admissionID.toLowerCase() !== admissionId.toLowerCase() ||
            verified.admission.admittedAt !== admittedAt
          )
            throw failure('invalid_response')
        },
      })
    },
  })
}
