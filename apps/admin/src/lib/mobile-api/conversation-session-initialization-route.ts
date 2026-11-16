import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import type { ConversationSessionObservation } from './conversation-meal-command-service'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { createConversationSessionInitialization } from './conversation-session-initialization'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRoute, type MobileRouteRuntime } from './route'

export function createConversationSessionInitializationRoute(
  ports: {
    enabled?: () => boolean
    initialize?: (
      db: ServiceClient,
      auth: MobileAuthContext,
    ) => Promise<ConversationSessionObservation>
  } = {},
  runtime?: MobileRouteRuntime,
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    initialize =
      ports.initialize?.bind(ports) ??
      ((db: ServiceClient, auth: MobileAuthContext) =>
        createConversationSessionInitialization(db).initialize(auth))
  return createMobileRoute(async (context) => {
    if (!enabled())
      throw new MobileApiError(
        503,
        'conversation_commands_unavailable',
        'Conversation capability unavailable',
      )
    if (new URL(context.request.url).search !== '')
      throw new MobileApiError(422, 'invalid_request', 'Session initialization accepts no query')
    z.literal('conversation-session-initialize-v1').parse(
      context.request.headers.get('Idempotency-Key'),
    )
    z.object({ schema: z.literal('conversation.session-initialization.v1') })
      .strict()
      .parse(await readJsonBody(context.request, 1024))
    return mobileSuccess(await initialize(context.supabase, context.auth), context.requestId, 200, {
      'X-Conversation-Protocol': 'meal-command-v1',
    })
  }, runtime ?? createConversationMealReadonlyRuntime())
}
