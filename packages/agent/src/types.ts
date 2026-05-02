import type { AgentStage } from '@mpp/core'

/**
 * Entrada normalizada para o agente.
 */
export interface AgentInput {
  /** Identificador externo do remetente (ex: WhatsApp E.164 sem +). */
  from: string
  /** ID estável da mensagem no provider, para idempotência. */
  providerMessageId: string
  /** Conteúdo principal. */
  text?: string
  /** Para mídia única (compatibilidade). */
  mediaUrl?: string
  mediaMimeType?: string
  /** Múltiplas mídias do mesmo turno (ex: 3 fotos corporais). */
  mediaUrls?: string[]
  contentType: 'text' | 'audio' | 'image'
  /** Hint do agente pra classificar imagem (vision). */
  imageHint?: 'meal' | 'body' | 'scale' | 'other'
  /** Provider de origem (whatsapp_cloud, console, ...). */
  provider: string
  /** Timestamp do provider. */
  timestamp: Date
}

/**
 * Resposta do agente após processar.
 */
export interface AgentOutput {
  text: string
  /** Se houve sugestão de output em áudio. */
  preferAudio: boolean
  toolCalls: Array<{ name: string; arguments: unknown; result?: unknown; error?: string }>
  stage: AgentStage
  modelUsed: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  latencyMs: number
}

/**
 * Resolução de qual sub-agente usar baseado no estado do user.
 */
export interface StageResolution {
  stage: AgentStage
  reason: string
}
