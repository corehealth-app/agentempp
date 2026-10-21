import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import type {
  SignupCompletionIntent,
  SignupCompletionIntentSource,
  SignupCompletionPreparation,
  SignupCompletionVerification,
} from './signup-completion-intent'
import { signupCompletionRequestKeySchema } from './signup-completion-transport'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
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
const preparationInput = z.object({ userId: uuid, preparationId: uuid }).strict()
const verificationInput = z
  .object({
    userId: uuid,
    intentId: uuid,
    requestKey: signupCompletionRequestKeySchema,
  })
  .strict()
const intent = z
  .object({
    ownerID: uuid,
    preparationID: uuid,
    intentID: uuid,
    requestKey: signupCompletionRequestKeySchema,
    epoch: uuid,
    issuedAt: z.string().refine(utc6),
  })
  .strict()
const stale = z
  .object({ status: z.literal('forbidden'), reason: z.literal('stale_epoch') })
  .strict()
const beginReply = z.union([
  z.object({ status: z.enum(['issued', 'reused']), intent }).strict(),
  stale,
])
const resolveReply = z.union([
  z.object({ status: z.literal('resolved'), intent }).strict(),
  z.object({ status: z.literal('absent') }).strict(),
  stale,
])
const verifyReply = z.union([
  z.object({ status: z.literal('verified'), intent }).strict(),
  z
    .object({ status: z.literal('forbidden'), reason: z.enum(['invalid_intent', 'stale_epoch']) })
    .strict(),
])
type RpcName =
  | 'begin_mobile_signup_completion_intent'
  | 'resolve_mobile_signup_completion_intent'
  | 'verify_mobile_signup_completion_intent'
type IntentRpc = (name: RpcName, parameters: Record<string, unknown>) => PromiseLike<unknown>
type WireIntent = z.infer<typeof intent>
function failure(kind: 'invalid_input' | 'invalid_response' | 'unavailable'): MobileApiError {
  return new MobileApiError(
    500,
    `mobile_signup_completion_intent_${kind}`,
    'Unable to verify signup completion intent',
  )
}
function parse<T>(
  schema: z.ZodType<T>,
  input: unknown,
  kind: 'invalid_input' | 'invalid_response' = 'invalid_response',
): T {
  try {
    const result = schema.safeParse(input)
    if (result.success) return result.data
  } catch {
    /* Internal wire errors never become public submission errors. */
  }
  throw failure(kind)
}
function refusal(reason: 'stale_epoch' | 'invalid_intent'): never {
  throw new MobileApiError(
    409,
    reason === 'stale_epoch'
      ? 'mobile_signup_strength_stale_epoch'
      : 'mobile_signup_completion_invalid_intent',
    'Reload and review the signup state before trying again',
  )
}
const sameUuid = (left: string, right: string) => left.toLowerCase() === right.toLowerCase()
function snapshot(
  value: WireIntent,
  userId: string,
  overrides: { preparationId?: string; intentId?: string } = {},
): SignupCompletionIntent {
  return Object.freeze({
    userId,
    preparationId: overrides.preparationId ?? value.preparationID,
    intentId: overrides.intentId ?? value.intentID,
    requestKey: value.requestKey,
    epoch: value.epoch,
    issuedAt: value.issuedAt,
  })
}

/** Backend-only adapter. Construction binds the receiver but performs no I/O. */
export function createSupabaseSignupCompletionIntentSource(
  supabase: ServiceClient,
): SignupCompletionIntentSource {
  const rpc = supabase.rpc.bind(supabase) as unknown as IntentRpc
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
  function owned(value: WireIntent, userId: string): void {
    if (!sameUuid(value.ownerID, userId)) throw failure('invalid_response')
  }
  return Object.freeze({
    async begin(input: SignupCompletionPreparation): Promise<SignupCompletionIntent> {
      const { userId, preparationId } = parse(preparationInput, input, 'invalid_input')
      const result = parse(
        beginReply,
        await invoke('begin_mobile_signup_completion_intent', {
          p_user_id: userId,
          p_preparation_id: preparationId,
        }),
      )
      if (result.status === 'forbidden') refusal(result.reason)
      owned(result.intent, userId)
      if (!sameUuid(result.intent.preparationID, preparationId)) throw failure('invalid_response')
      return snapshot(result.intent, userId, { preparationId })
    },
    async resolve(input: SignupCompletionPreparation): Promise<SignupCompletionIntent | null> {
      const { userId, preparationId } = parse(preparationInput, input, 'invalid_input')
      const result = parse(
        resolveReply,
        await invoke('resolve_mobile_signup_completion_intent', {
          p_user_id: userId,
          p_preparation_id: preparationId,
        }),
      )
      if (result.status === 'forbidden') refusal(result.reason)
      if (result.status === 'absent') return null
      owned(result.intent, userId)
      if (!sameUuid(result.intent.preparationID, preparationId)) throw failure('invalid_response')
      return snapshot(result.intent, userId, { preparationId })
    },
    async verify(input: SignupCompletionVerification): Promise<SignupCompletionIntent> {
      const { userId, intentId, requestKey } = parse(verificationInput, input, 'invalid_input')
      const result = parse(
        verifyReply,
        await invoke('verify_mobile_signup_completion_intent', {
          p_user_id: userId,
          p_intent_id: intentId,
          p_request_key: requestKey,
        }),
      )
      if (result.status === 'forbidden') refusal(result.reason)
      owned(result.intent, userId)
      if (!sameUuid(result.intent.intentID, intentId) || result.intent.requestKey !== requestKey)
        throw failure('invalid_response')
      return snapshot(result.intent, userId, { intentId })
    },
  })
}
