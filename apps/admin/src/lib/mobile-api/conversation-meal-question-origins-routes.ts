import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationIntakesEnabled } from './conversation-intake-routes'
import { createConversationMealQuestionOriginsService } from './conversation-meal-question-origins'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { workoutUUID } from './conversation-workout-contracts'
import { MobileApiError, mobileSuccess } from './http'
import { createMobileRoute, type MobileRouteRuntime } from './route'

export interface ConversationMealQuestionOriginsRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealQuestionOriginsService>, 'read'>
}
function query(request: Request) {
  const params = new URL(request.url).searchParams
  if (
    [...params.keys()].some((key) => !['limit', 'cursor'].includes(key)) ||
    params.getAll('limit').length > 1 ||
    params.getAll('cursor').length > 1
  )
    throw new MobileApiError(
      422,
      'conversation_meal_question_origins_invalid_query',
      'A bounded original history page is required',
    )
  const limit = params.get('limit') ?? '10'
  if (!/^(?:[1-9]|1[0-9]|2[0-5])$/u.test(limit))
    throw new MobileApiError(
      422,
      'conversation_meal_question_origins_invalid_query',
      'A bounded original history page is required',
    )
  return {
    limit: Number(limit),
    cursor: params.has('cursor') ? z.string().min(1).max(1024).parse(params.get('cursor')) : null,
  }
}
export function createConversationMealQuestionOriginsRoutes(
  ports: ConversationMealQuestionOriginsRoutePorts = {},
  runtime: MobileRouteRuntime = createConversationMealReadonlyRuntime(),
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationIntakesEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealQuestionOriginsService
  function available() {
    if (!enabled())
      throw new MobileApiError(
        503,
        'conversation_intake_unavailable',
        'Conversation intake capability is unavailable',
      )
  }
  return Object.freeze({
    GET: createMobileRoute(async (context) => {
      available()
      const owner = workoutUUID.parse(context.request.headers.get('X-Conversation-Owner'))
      if (owner !== context.auth.userId)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The authenticated patient has changed',
        )
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        input = query(context.request),
        result = await service(context.supabase).read(context.auth, epoch, input)
      available()
      return mobileSuccess(result, context.requestId, 200, {
        'X-Conversation-Protocol': 'intake-question-origins-v1',
      })
    }, runtime),
  })
}
