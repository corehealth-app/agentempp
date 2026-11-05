import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationMealCommandSchema } from './conversation-command-contracts'
import {
  conversationFeedbackPresentationMobileHeaders,
  negotiateConversationFeedbackPresentation,
} from './conversation-feedback-presentation-negotiation'
import {
  type ConversationMealCommandReply,
  createConversationMealCommandService,
} from './conversation-meal-command-service'
import { resolveCurrentClinicalRuntime } from './current-clinical-runtime-switch'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRoute, createMobileRouteWithContext, type MobileRouteRuntime } from './route'

const uuid = z
    .string()
    .uuid()
    .regex(/^[0-9a-f-]+$/u),
  hash = z.string().regex(/^[a-f0-9]{64}$/u)
interface CommandRouteContext {
  params: Promise<{ commandId: string }>
}
export interface ConversationMealCommandRoutePorts {
  enabled?: () => boolean
  service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealCommandService>, 'submit' | 'read' | 'session'>
}
/** Explicit opt-in on the established staging target only. No request value
 * can select an environment, turn this on or fall back to a legacy writer. */
export function conversationMealCommandsEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_COMMANDS_ENABLED === 'true' &&
    resolveCurrentClinicalRuntime(env).mode === 'current'
  )
}
function reply(
  result: ConversationMealCommandReply,
  requestId: string,
  selected: 'legacy' | '2',
): Response {
  return mobileSuccess(result, requestId, result.status === 'pending' ? 202 : 200, {
    'X-Conversation-Protocol': 'meal-command-v1',
    ...conversationFeedbackPresentationMobileHeaders(selected),
  })
}
function requireOriginalPatient(request: Request, authenticatedPatient: string): void {
  const expected = uuid.parse(request.headers.get('X-Conversation-Owner'))
  if (expected !== authenticatedPatient)
    throw new MobileApiError(
      409,
      'conversation_patient_changed',
      'The authenticated patient has changed',
    )
}
export function createConversationMealCommandRoutes(
  ports: ConversationMealCommandRoutePorts = {},
  runtime?: MobileRouteRuntime,
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealCommandService
  const available = () => {
    if (!enabled())
      throw new MobileApiError(
        503,
        'conversation_commands_unavailable',
        'Conversation command capability is unavailable',
      )
  }
  return Object.freeze({
    SESSION: createMobileRoute(async (context) => {
      available()
      return mobileSuccess(
        await service(context.supabase).session(context.auth),
        context.requestId,
        200,
        {
          'X-Conversation-Protocol': 'meal-command-v1',
        },
      )
    }, runtime),
    POST: createMobileRoute(async (context) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        epoch = uuid.parse(context.request.headers.get('X-Conversation-Epoch')),
        body = conversationMealCommandSchema.parse(await readJsonBody(context.request, 16384)),
        key = z
          .literal(`cmsg1:${body.command_id}`)
          .parse(context.request.headers.get('Idempotency-Key'))
      return reply(
        await service(context.supabase).submit(
          context.auth,
          key,
          body,
          epoch,
          ...(selected === '2' ? ['2' as const] : []),
        ),
        context.requestId,
        selected,
      )
    }, runtime),
    GET: createMobileRouteWithContext<CommandRouteContext>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        epoch = uuid.parse(context.request.headers.get('X-Conversation-Epoch')),
        inputHash = hash.parse(context.request.headers.get('X-Conversation-Input-Hash')),
        commandId = uuid.parse((await route.params).commandId)
      return reply(
        await service(context.supabase).read(
          context.auth,
          commandId,
          inputHash,
          epoch,
          ...(selected === '2' ? ['2' as const] : []),
        ),
        context.requestId,
        selected,
      )
    }, runtime),
  })
}
