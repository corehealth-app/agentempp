import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  conversationFeedbackPresentationMobileHeaders,
  negotiateConversationFeedbackPresentation,
} from './conversation-feedback-presentation-negotiation'
import { createConversationMealReadonlyRuntime as createConversationMealReplyReadonlyRuntime } from './conversation-meal-readonly-runtime'

export { createConversationMealReadonlyRuntime as createConversationMealReplyReadonlyRuntime } from './conversation-meal-readonly-runtime'

import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { parseConversationMealReplySubmission } from './conversation-meal-reply-public-contracts'
import { createConversationMealReplyPublicService } from './conversation-meal-reply-public-service'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRouteWithContext, type MobileRouteRuntime } from './route'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u),
  hash = z.string().regex(/^[a-f0-9]{64}$/u)
interface ParentRoute {
  params: Promise<{ commandId: string }>
}
interface ReplyRoute {
  params: Promise<{ commandId: string; replyId: string }>
}
export interface ConversationMealReplyRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationMealReplyPublicService>, 'submit' | 'reconcile'>
}
function scope(request: Request, patient: string) {
  const owner = uuid.parse(request.headers.get('X-Conversation-Owner'))
  if (owner !== patient)
    throw new MobileApiError(
      409,
      'conversation_patient_changed',
      'The authenticated patient has changed',
    )
  return uuid.parse(request.headers.get('X-Conversation-Epoch'))
}
function query(request: Request) {
  const params = new URL(request.url).searchParams
  for (const key of params.keys()) {
    if (!['parent_input_hash', 'reply_input_hash'].includes(key) || params.getAll(key).length !== 1)
      throw new MobileApiError(
        422,
        'conversation_meal_reply_invalid_query',
        'A closed original reply query is required',
      )
  }
  return {
    parent_input_hash: hash.parse(params.get('parent_input_hash')),
    reply_input_hash: hash.parse(params.get('reply_input_hash')),
  }
}
function response(
  result: Awaited<
    ReturnType<ReturnType<typeof createConversationMealReplyPublicService>['reconcile']>
  >,
  requestId: string,
  selected: 'legacy' | '2',
) {
  return mobileSuccess(result, requestId, result.status === 'reconciliation_required' ? 202 : 200, {
    'X-Conversation-Protocol': 'meal-reply-v1',
    ...conversationFeedbackPresentationMobileHeaders(selected),
  })
}
export function createConversationMealReplyPublicRoutes(
  ports: ConversationMealReplyRoutePorts = {},
  runtime: MobileRouteRuntime = createConversationMealReplyReadonlyRuntime(),
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealReplyPublicService
  const available = () => {
    if (!enabled())
      throw new MobileApiError(
        503,
        'conversation_commands_unavailable',
        'Conversation command capability is unavailable',
      )
  }
  return Object.freeze({
    POST: createMobileRouteWithContext<ParentRoute>(async (context, route) => {
      available()
      if (new URL(context.request.url).search)
        throw new MobileApiError(
          422,
          'conversation_meal_reply_invalid_query',
          'Reply submission accepts no query parameters',
        )
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        epoch = scope(context.request, context.auth.userId),
        parent = uuid.parse((await route.params).commandId),
        body = parseConversationMealReplySubmission(await readJsonBody(context.request, 16384)),
        key = z
          .literal(`cmreply1:${body.reply_id}`)
          .parse(context.request.headers.get('Idempotency-Key'))
      return response(
        await service(context.supabase).submit(
          context.auth,
          parent,
          epoch,
          body,
          key,
          ...(selected === '2' ? ['2' as const] : []),
        ),
        context.requestId,
        selected,
      )
    }, runtime),
    GET: createMobileRouteWithContext<ReplyRoute>(async (context, route) => {
      available()
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        epoch = scope(context.request, context.auth.userId),
        params = await route.params,
        parent = uuid.parse(params.commandId),
        replyId = uuid.parse(params.replyId),
        input = query(context.request)
      return response(
        await service(context.supabase).reconcile(
          context.auth,
          parent,
          replyId,
          epoch,
          input,
          ...(selected === '2' ? ['2' as const] : []),
        ),
        context.requestId,
        selected,
      )
    }, runtime),
  })
}
