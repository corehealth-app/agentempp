import { flowChatInputSchema, flowChatLimitSchema } from '@/lib/mobile-api/contracts'
import type {
  FlowChatDependencies,
  loadFlowHistory,
  SendFlowMessageInput,
  sendFlowMessage,
} from '@/lib/mobile-api/flow-chat-service'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

type ExecuteIdempotent = (
  context: MobileRouteContext,
  payload: unknown,
  operation: (idempotencyKey: string) => Promise<Response>,
) => Promise<Response>

export interface FlowChatRouteDependencies {
  createChatDependencies(context: MobileRouteContext): FlowChatDependencies
  loadHistory: typeof loadFlowHistory
  sendMessage: typeof sendFlowMessage
  executeIdempotent: ExecuteIdempotent
  now(): Date
}

export async function handleFlowChatGet(
  context: MobileRouteContext,
  dependencies: FlowChatRouteDependencies,
): Promise<Response> {
  const url = new URL(context.request.url)
  const unexpected = [...url.searchParams.keys()].some((key) => key !== 'limit')
  if (unexpected) {
    throw new MobileApiError(422, 'validation_failed', 'Unexpected query parameter')
  }
  const limit = flowChatLimitSchema.parse(url.searchParams.get('limit') ?? '50')
  const chat = dependencies.createChatDependencies(context)
  return mobileSuccess(
    await dependencies.loadHistory(chat, context.auth.userId, limit),
    context.requestId,
  )
}

export async function handleFlowChatPost(
  context: MobileRouteContext,
  dependencies: FlowChatRouteDependencies,
): Promise<Response> {
  const input = flowChatInputSchema.parse(await readJsonBody(context.request, 16 * 1024))
  const chat = dependencies.createChatDependencies(context)
  return dependencies.executeIdempotent(context, input, async (idempotencyKey) => {
    const sendInput: SendFlowMessageInput = {
      userId: context.auth.userId,
      text: input.text,
      idempotencyKey,
      requestId: context.requestId,
      now: dependencies.now(),
    }
    return mobileSuccess(await dependencies.sendMessage(chat, sendInput), context.requestId, 201)
  })
}
