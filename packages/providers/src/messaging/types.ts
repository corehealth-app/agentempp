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

/** Botão de reply em mensagem interactive (WhatsApp). */
export interface InteractiveButton {
  /** ID livre — fica embutido no inbound do tap (button_reply.id). Limite Meta: 256 chars. */
  id: string
  /** Texto exibido no botão. Limite Meta: 20 chars (não inclui emoji bem). */
  title: string
}

/** Item de List Message (WhatsApp). Pra perguntas com 4+ opções (botão simples limita a 3). */
export interface InteractiveListItem {
  /** ID livre — fica embutido no inbound do tap (list_reply.id). Limite Meta: 200 chars. */
  id: string
  /** Texto da opção. Limite Meta: 24 chars. */
  title: string
  /** Subtexto opcional. Limite Meta: 72 chars. */
  description?: string
}

export interface MessagingProvider {
  readonly name: string

  // Outbound
  sendText(to: string, text: string, opts?: SendOpts): Promise<SendResult>
  sendAudio(to: string, audioUrl: string): Promise<SendResult>
  sendImage(to: string, url: string, caption?: string): Promise<SendResult>
  sendTemplate(to: string, template: HSMTemplate): Promise<SendResult>
  /** Mensagem com botões de reply (max 3). Body up to 1024 chars.
   * Intra-janela 24h — sem aprovação de template. Tap chega como inbound
   * type='interactive', button_reply: { id, title }. Roberto 2026-05-28 (Fase A). */
  sendInteractive(
    to: string,
    body: string,
    buttons: InteractiveButton[],
    opts?: SendOpts,
  ): Promise<SendResult>
  /** List Message (WhatsApp) pra perguntas com 4-10 opções. Roberto 2026-06-01
   * (Fase 2 botões onboarding). Tap chega como list_reply: { id, title }.
   * buttonText: rótulo do botão "abrir lista" (ex: "Escolher", "Ver opções"). */
  sendInteractiveList(
    to: string,
    body: string,
    buttonText: string,
    items: InteractiveListItem[],
    opts?: SendOpts,
  ): Promise<SendResult>

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
