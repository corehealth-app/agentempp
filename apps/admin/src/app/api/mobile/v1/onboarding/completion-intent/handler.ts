import { z } from 'zod'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { requireIdempotencyKey } from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  captureSignupCompletionSources,
  defaultSignupCompletionComposition,
  type SignupCompletionComposition,
} from '@/lib/mobile-api/signup-completion-composition'
import type { SignupCompletionIntent } from '@/lib/mobile-api/signup-completion-intent'

const preparationSchema = z.object({ preparation_id: z.string().uuid() }).strict()
const publicIntentSchema = z
  .object({
    protocol: z.literal('osc1'),
    preparation_id: z.string().uuid(),
    intent_id: z.string().uuid(),
    request_key: z
      .string()
      .regex(/^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
  })
  .strict()

function invalidPreparation(): MobileApiError {
  return new MobileApiError(
    400,
    'invalid_signup_completion_preparation',
    'Invalid signup preparation',
  )
}

function publicIntent(intent: SignupCompletionIntent, userId: string, preparationId: string) {
  if (!intent || intent.userId !== userId || intent.preparationId !== preparationId)
    throw invalidResponse()
  const result = publicIntentSchema.safeParse({
    protocol: 'osc1',
    preparation_id: intent.preparationId,
    intent_id: intent.intentId,
    request_key: intent.requestKey,
  })
  if (!result.success) throw invalidResponse()
  return result.data
}

function invalidResponse(): MobileApiError {
  return new MobileApiError(
    500,
    'mobile_signup_completion_intent_invalid_response',
    'Invalid signup preparation response',
  )
}

export async function handleSignupCompletionIntentPost(
  context: MobileRouteContext,
  composition: SignupCompletionComposition = defaultSignupCompletionComposition,
): Promise<Response> {
  const result = preparationSchema.safeParse(await readJsonBody(context.request))
  if (!result.success) throw invalidPreparation()
  const preparationId = result.data.preparation_id
  if (requireIdempotencyKey(context.request) !== preparationId) throw invalidPreparation()
  const sources = captureSignupCompletionSources(composition, context.supabase)
  // The SQL receipt is the idempotency authority for Q. There is no HTTP claim,
  // automatic retry or completion admission in this preparation endpoint.
  const intent = await sources.intents.begin({ userId: context.auth.userId, preparationId })
  return mobileSuccess(
    { completion_intent: publicIntent(intent, context.auth.userId, preparationId) },
    context.requestId,
  )
}

export async function handleSignupCompletionIntentGet(
  context: MobileRouteContext,
  composition: SignupCompletionComposition = defaultSignupCompletionComposition,
): Promise<Response> {
  const entries = [...new URL(context.request.url).searchParams.entries()]
  if (entries.length !== 1 || entries[0]?.[0] !== 'preparation_id') throw invalidPreparation()
  const result = preparationSchema.safeParse({ preparation_id: entries[0][1] })
  if (!result.success) throw invalidPreparation()
  const preparationId = result.data.preparation_id
  const sources = captureSignupCompletionSources(composition, context.supabase)
  const intent = await sources.intents.resolve({ userId: context.auth.userId, preparationId })
  // A request dispatched while enabled may return its known identity after OFF.
  // In particular, absent is never a signal to issue another receipt here.
  return mobileSuccess(
    {
      completion_intent:
        intent === null ? null : publicIntent(intent, context.auth.userId, preparationId),
    },
    context.requestId,
  )
}
