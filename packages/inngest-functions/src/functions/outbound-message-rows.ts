import type { ContentType, HumanizedSendResult } from '@mpp/providers'

export interface OutboundDelivery {
  content: string
  providerMessageId: string | null
  status: HumanizedSendResult['status']
  error?: string
}

export function buildOutboundMessageRows(input: {
  userId: string
  provider: string
  contentType: ContentType
  stage: string | null
  modelUsed: string | null
  promptTokens: number | null
  completionTokens: number | null
  costUsd: number | null
  latencyMs: number | null
  metadata?: Record<string, string>
  deliveries: OutboundDelivery[]
}) {
  return input.deliveries.map((delivery, index) => ({
    user_id: input.userId,
    direction: 'out' as const,
    role: 'assistant' as const,
    content_type: input.contentType,
    content: delivery.content,
    provider: input.provider,
    provider_message_id: delivery.providerMessageId,
    agent_stage: input.stage,
    model_used: index === 0 ? input.modelUsed : null,
    prompt_tokens: index === 0 ? input.promptTokens : null,
    completion_tokens: index === 0 ? input.completionTokens : null,
    cost_usd: index === 0 ? input.costUsd : null,
    latency_ms: index === 0 ? input.latencyMs : null,
    delivery_status: delivery.status,
    delivery_error: delivery.error ? { error: delivery.error } : null,
    raw_payload: input.metadata ?? null,
  }))
}
