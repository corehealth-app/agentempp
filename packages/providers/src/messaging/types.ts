/**
 * Adapter pattern: MessagingProvider abstrai o canal de mensagens.
 *
 * Implementadores:
 *  - ConsoleProvider (dev / playground via terminal)
 *  - WhatsAppCloudProvider (produção, futuro)
 *  - TwilioProvider (fallback futuro)
 */

export type ContentType = 'text' | 'audio' | 'image' | 'template' | 'interactive'

export interface NormalizedInbound {
  /** ID estável do provider para idempotência. */
  providerMessageId: string
  /** Número/identificador do remetente (E.164 sem +, ou identificador do canal). */
  from: string
  /** Tipo de conteúdo. */
  type: ContentType
  /** Texto (quando type=text) ou caption. */
  text?: string
  /** Para mídia: URL pública ou path local. */
  mediaUrl?: string
  /** MIME type da mídia. */
  mediaMimeType?: string
  /** Timestamp do provider. */
  timestamp: Date
  /** Payload bruto para auditoria. */
  raw: unknown
}

export interface SendOpts {
  /** Substitui formatação default do provider. */
  preview_url?: boolean
  /** Mensagem em resposta a outra (quoted reply). */
  replyTo?: string
}

export interface SendResult {
  /** ID retornado pelo provider. Pode ser null se assíncrono. */
  providerMessageId: string | null
  status: 'queued' | 'sent' | 'failed'
  error?: string
}

export interface HSMTemplate {
  name: string
  language: string
  variables: Record<string, string>
}

export interface QualityStatus {
  rating: 'GREEN' | 'YELLOW' | 'RED' | 'UNKNOWN'
  tier: string
}

export interface MessagingProvider {
  readonly name: string

  // Outbound
  sendText(to: string, text: string, opts?: SendOpts): Promise<SendResult>
  sendAudio(to: string, audioUrl: string): Promise<SendResult>
  sendImage(to: string, url: string, caption?: string): Promise<SendResult>
  sendTemplate(to: string, template: HSMTemplate): Promise<SendResult>

  // Reações (emoji em mensagem específica)
  /** emoji '' (string vazia) remove a reação */
  react(to: string, providerMessageId: string, emoji: string): Promise<SendResult>

  // Mídia
  uploadMedia(file: Blob, mimeType: string): Promise<string>
  downloadMedia(mediaId: string): Promise<Blob>

  // Estado da conversa
  markRead(providerMessageId: string): Promise<void>
  /**
   * Mostra o "digitando..." real do WhatsApp na conversa.
   * Esse indicador some sozinho após ~25s ou quando a próxima mensagem é enviada.
   * Idempotente — chamar múltiplas vezes só re-arma o timer.
   */
  showTypingFor(providerMessageId: string): Promise<void>
  /** @deprecated use showTypingFor — Cloud API só permite typing ao receber msg */
  setTyping(to: string, state: 'typing' | 'recording' | 'idle'): Promise<void>

  // Webhook
  parseInbound(payload: unknown): NormalizedInbound[]
  verifyWebhook(headers: Record<string, string>, rawBody: string): boolean

  // Operação
  getQualityStatus(): Promise<QualityStatus>
}
