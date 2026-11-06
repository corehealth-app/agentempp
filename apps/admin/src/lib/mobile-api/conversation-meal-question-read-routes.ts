import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealQuestionReadService } from './conversation-meal-question-read'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { MobileApiError, mobileSuccess } from './http'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u),
  hash = z.string().regex(/^[a-f0-9]{64}$/u)
interface ParentRoute {
  params: Promise<{ commandId: string }>
}
export interface ConversationMealQuestionReadRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealQuestionReadService>, 'read'>
}
function query(request: Request) {
  const params = new URL(request.url).searchParams
  if ([...params.keys()].length !== 1 || params.getAll('parent_input_hash').length !== 1)
    throw new MobileApiError(
      422,
      'conversation_meal_question_invalid_query',
      'Only the original parent input hash is accepted',
    )
  return { parent_input_hash: hash.parse(params.get('parent_input_hash')) }
}
export function createConversationMealQuestionReadRoutes(
  ports: ConversationMealQuestionReadRoutePorts = {},
  runtime: MobileRouteRuntime = createConversationMealReadonlyRuntime(),
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealQuestionReadService
  return Object.freeze({
    GET: createMobileRouteWithContext<ParentRoute>(async (context, route) => {
      if (!enabled())
        throw new MobileApiError(
          503,
          'conversation_commands_unavailable',
          'Conversation command capability is unavailable',
        )
      const owner = uuid.parse(context.request.headers.get('X-Conversation-Owner'))
      if (owner !== context.auth.userId)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The authenticated patient has changed',
        )
      const epoch = uuid.parse(context.request.headers.get('X-Conversation-Epoch')),
        parent = uuid.parse((await route.params).commandId),
        input = query(context.request),
        result = await service(context.supabase).read(context.auth, parent, epoch, input)
      return mobileSuccess(result, context.requestId, 200, {
        'X-Conversation-Protocol': 'meal-question-v1',
      })
    }, runtime),
  })
}
