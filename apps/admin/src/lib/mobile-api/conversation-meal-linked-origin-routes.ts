import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealLinkedOriginService } from './conversation-meal-linked-origin'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { MobileApiError, mobileSuccess } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
interface OriginRoute {
  params: Promise<{ commandId: string }>
}
export interface ConversationMealLinkedOriginRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealLinkedOriginService>, 'read'>
}
export function createConversationMealLinkedOriginRoutes(
  ports: ConversationMealLinkedOriginRoutePorts = {},
  runtime: MobileRouteRuntime = createConversationMealReadonlyRuntime(),
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealLinkedOriginService,
    authenticate = runtime.authenticate.bind(runtime)
  return Object.freeze({
    GET: createMobileRouteWithContext<OriginRoute>(async (context, route) => {
      if (!enabled())
        throw new MobileApiError(
          503,
          'conversation_commands_unavailable',
          'Conversation command capability is unavailable',
        )
      const owner = uuid.parse(context.request.headers.get('X-Conversation-Owner')),
        epoch = uuid.parse(context.request.headers.get('X-Conversation-Epoch')),
        original = Object.freeze({
          owner: authenticatedReevaluationOwner(context.auth),
          subject: context.auth.authUserId,
          token: context.auth.accessToken,
          request: new Request(context.request.url, {
            headers: new Headers(context.request.headers),
          }),
        })
      if (owner !== original.owner)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The authenticated patient has changed',
        )
      if ([...new URL(context.request.url).searchParams].length !== 0)
        throw new MobileApiError(
          422,
          'conversation_meal_linked_origin_invalid_query',
          'No origin hints are accepted',
        )
      const commandId = uuid.parse((await route.params).commandId),
        result = await service(context.supabase).read(context.auth, commandId, epoch),
        current = await authenticate(original.request, context.supabase)
      if (
        current.authUserId !== original.subject ||
        current.identity.id !== original.subject ||
        current.patient.authUserId !== original.subject ||
        current.accessToken !== original.token ||
        authenticatedReevaluationOwner(current) !== original.owner
      )
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The original authenticated patient has changed',
        )
      return mobileSuccess(result, context.requestId, 200, {
        'X-Conversation-Protocol': 'meal-linked-origin-v1',
      })
    }, runtime),
  })
}
