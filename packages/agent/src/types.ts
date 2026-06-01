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
  /** Enviar como UMA mensagem só (sem split do humanizer) — usado no card
   * determinístico de registro, que não pode ser quebrado em vários envios. */
  singleMessage?: boolean
  /** Proposta de registro pendente de confirmação por botão WhatsApp (Roberto
   * 2026-05-28, Fase B opção #4). Quando presente, o caller (process-message)
   * envia messaging.sendInteractive em vez de sendHumanized. O pending JÁ está
   * gravado no banco; `pendingId` permite atualizar proposal_msg_id após envio. */
  interactive?: {
    body: string
    buttons: Array<{ id: string; title: string }>
    pendingId: string
    /** Quando definido, envia como List Message (Roberto 2026-06-01, Fase 2
     * botões onboarding) — pra perguntas com 4-10 opções (botão simples
     * limita a 3). `buttonText` é o rótulo do botão "abrir lista". */
    list?: {
      buttonText: string
    }
  }
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
