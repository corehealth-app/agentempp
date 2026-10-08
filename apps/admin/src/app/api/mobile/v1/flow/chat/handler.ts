import { type FlowPresentationObjective, projectStoredFlowMetricAnswer } from '@mpp/agent/flow-public-metrics'
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
  loadPresentationContext(context: MobileRouteContext): Promise<FlowPresentationObjective>
  now(): Date
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function invalidResponse(): MobileApiError {
  return new MobileApiError(500, 'flow_response_invalid', 'Flow returned an invalid response')
}

/** Public route boundary; stored rows and HTTP idempotency bodies stay intact. */
function validateMessage(value: unknown): asserts value is Record<string, unknown> {
  if (
    !record(value) ||
    value.conversation_id !== 'flow' ||
    (value.role !== 'assistant' && value.role !== 'user') ||
    typeof value.content !== 'string' ||
    typeof value.id !== 'string' ||
    typeof value.request_id !== 'string' ||
    typeof value.created_at !== 'string' ||
    typeof value.state !== 'string' ||
    !['processing', 'completed', 'failed'].includes(value.state)
  )
    throw invalidResponse()
}

function publicMessage(value: unknown, locale: string | null, objective: FlowPresentationObjective, hasSuggestion = false) {
  validateMessage(value)
  return value.role === 'user'
    ? value
    : { ...value, content: projectStoredFlowMetricAnswer(value.content as string, locale, hasSuggestion, objective) }
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
  const [history, objective] = await Promise.all([
    dependencies.loadHistory(chat, context.auth.userId, limit),
    dependencies.loadPresentationContext(context),
  ])
  return mobileSuccess(
    {
      ...history,
      messages: history.messages.map((message) =>
        publicMessage(message, context.auth.patient.locale, objective),
      ),
    },
    context.requestId,
  )
}

export async function handleFlowChatPost(
  context: MobileRouteContext,
  dependencies: FlowChatRouteDependencies,
): Promise<Response> {
  const input = flowChatInputSchema.parse(await readJsonBody(context.request, 16 * 1024))
  const chat = dependencies.createChatDependencies(context)
  const response = await dependencies.executeIdempotent(context, input, async (idempotencyKey) => {
    const sendInput: SendFlowMessageInput = {
      userId: context.auth.userId,
      text: input.text,
      idempotencyKey,
      requestId: context.requestId,
      now: dependencies.now(),
    }
    return mobileSuccess(await dependencies.sendMessage(chat, sendInput), context.requestId, 201)
  })
  // This must run AFTER idempotency: a cached HTTP reply bypasses sendMessage.
  if (!response.ok) return response
  let body: unknown
  try {
    body = await response.clone().json()
  } catch {
    throw invalidResponse()
  }
  if (
    !record(body) ||
    !record(body.data) ||
    body.data.conversation_id !== 'flow' ||
    !record(body.meta) ||
    body.meta.api_version !== 'v1' ||
    typeof body.meta.request_id !== 'string' ||
    !record(body.data.message) ||
    body.data.message.role !== 'assistant'
  ) {
    throw invalidResponse()
  }
  const data = body.data
  validateMessage(data.message)
  // Outside the mutation/cache callback: retry can reuse a saved turn after a read failure.
  const objective = await dependencies.loadPresentationContext(context)
  const hasSuggestion =
    record(data.draft) &&
    typeof data.draft.id === 'string' &&
    (data.draft.domain === 'nutrition' || data.draft.domain === 'training')
  const headers = new Headers(response.headers)
  // A cached body can have a length for its original, unprojected bytes.
  headers.delete('Content-Length')
  return Response.json(
    {
      ...body,
      data: {
        ...data,
        message: publicMessage(data.message, context.auth.patient.locale, objective, hasSuggestion),
      },
    },
    { status: response.status, statusText: response.statusText, headers },
  )
}
