/**
 * WhatsApp Cloud API (Meta) — provider oficial.
 *
 * Implementa MessagingProvider. Não ativado por padrão.
 * Ativar trocando MESSAGING_PROVIDER=whatsapp_cloud.
 *
 * Pré-requisitos (configurar via /settings/api-keys):
 *   - meta_whatsapp.access_token
 *   - meta_whatsapp.phone_number_id
 *   - meta_whatsapp.app_secret
 *   - meta_whatsapp.verify_token
 */
import { createHmac, timingSafeEqual } from 'node:crypto'
import type {
  HSMTemplate,
  MessagingProvider,
  NormalizedInbound,
  QualityStatus,
  SendOpts,
  SendResult,
} from './types.js'

export interface WhatsAppCloudConfig {
  phoneNumberId: string
  accessToken: string
  appSecret: string
  verifyToken: string
  apiVersion?: string // 'v21.0'
}

export class WhatsAppCloudProvider implements MessagingProvider {
  readonly name = 'whatsapp_cloud'
  private base: string

  constructor(private cfg: WhatsAppCloudConfig) {
    this.base = `https://graph.facebook.com/${cfg.apiVersion ?? 'v21.0'}`
  }

  private async post(body: Record<string, unknown>): Promise<SendResult> {
    const r = await fetch(`${this.base}/${this.cfg.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.cfg.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })
    const json = (await r.json()) as { messages?: Array<{ id: string }>; error?: { message: string } }
    if (!r.ok) return { providerMessageId: null, status: 'failed', error: json.error?.message }
    return { providerMessageId: json.messages?.[0]?.id ?? null, status: 'sent' }
  }

  async sendText(to: string, text: string, opts?: SendOpts): Promise<SendResult> {
    return this.post({
      messaging_product: 'whatsapp',
      to,
      type: 'text',
      text: { body: text, preview_url: opts?.preview_url ?? false },
      ...(opts?.replyTo ? { context: { message_id: opts.replyTo } } : {}),
    })
  }

  async sendAudio(to: string, audioUrl: string): Promise<SendResult> {
    return this.post({
      messaging_product: 'whatsapp',
      to,
      type: 'audio',
      audio: audioUrl.startsWith('http') ? { link: audioUrl } : { id: audioUrl },
    })
  }

  async sendImage(to: string, url: string, caption?: string): Promise<SendResult> {
    return this.post({
      messaging_product: 'whatsapp',
      to,
      type: 'image',
      image: {
        ...(url.startsWith('http') ? { link: url } : { id: url }),
        ...(caption ? { caption } : {}),
      },
    })
  }

  async sendTemplate(to: string, template: HSMTemplate): Promise<SendResult> {
    const components = Object.keys(template.variables).length
      ? [
          {
            type: 'body',
            parameters: Object.values(template.variables).map((v) => ({ type: 'text', text: v })),
          },
        ]
      : []
    return this.post({
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: {
        name: template.name,
        language: { code: template.language },
        ...(components.length ? { components } : {}),
      },
    })
  }

  async uploadMedia(file: Blob, mimeType: string): Promise<string> {
    const form = new FormData()
    form.append('messaging_product', 'whatsapp')
    form.append('type', mimeType)
    form.append('file', file, 'media')
    const r = await fetch(`${this.base}/${this.cfg.phoneNumberId}/media`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.cfg.accessToken}` },
      body: form,
    })
    if (!r.ok) throw new Error(`uploadMedia failed: ${r.status}`)
    const json = (await r.json()) as { id: string }
    return json.id
  }

  async downloadMedia(mediaId: string): Promise<Blob> {
    // Retry com backoff: a falha mais comum (Roberto 2026-05-27 08:47) é
    // transitória — timeout/hiccup da CDN lookaside ou 5xx momentâneo da Graph
    // API. 1 foto falhou enquanto outras do mesmo paciente/dia funcionaram.
    // Retentamos só falhas transitórias (rede / 408 / 429 / 5xx); erro
    // definitivo (401/403/404 = token/ID inválido) sobe na hora.
    // 1. resolve URL
    const meta = await this.fetchWithRetry(
      `${this.base}/${mediaId}`,
      { headers: { Authorization: `Bearer ${this.cfg.accessToken}` } },
      `resolve mediaId=${mediaId}`,
    )
    const metaJson = (await meta.json()) as { url?: string; error?: { message?: string } }
    if (!metaJson.url) {
      throw new Error(
        `downloadMedia: failed to resolve mediaId=${mediaId} (${meta.status} ${metaJson.error?.message ?? 'sem url'})`,
      )
    }
    // 2. baixa bytes
    const r = await this.fetchWithRetry(
      metaJson.url,
      { headers: { Authorization: `Bearer ${this.cfg.accessToken}` } },
      `download bytes mediaId=${mediaId}`,
    )
    return await r.blob()
  }

  /**
   * fetch com até 3 tentativas (backoff 300ms/900ms) em falhas TRANSITÓRIAS:
   * erro de rede (fetch throw), timeout (408), rate limit (429) ou 5xx.
   * Erros definitivos (4xx exceto 408/429) sobem imediatamente — retry não
   * resolveria token/ID inválido. Lança no esgotamento das tentativas.
   */
  private async fetchWithRetry(
    url: string,
    init: RequestInit,
    label: string,
    attempts = 3,
  ): Promise<Response> {
    let lastErr: unknown
    for (let i = 0; i < attempts; i++) {
      try {
        const res = await fetch(url, init)
        if (res.ok) return res
        const transient = res.status === 408 || res.status === 429 || res.status >= 500
        if (!transient || i === attempts - 1) {
          throw new Error(`downloadMedia [${label}] failed: ${res.status}`)
        }
      } catch (e) {
        lastErr = e
        if (i === attempts - 1) throw e instanceof Error ? e : new Error(String(e))
      }
      await new Promise((r) => setTimeout(r, 300 * (i + 1) ** 2))
    }
    throw lastErr instanceof Error ? lastErr : new Error(`downloadMedia [${label}] failed`)
  }

  async markRead(providerMessageId: string): Promise<void> {
    await fetch(`${this.base}/${this.cfg.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.cfg.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        status: 'read',
        message_id: providerMessageId,
      }),
    })
  }

  /**
   * Mostra "digitando..." real do WhatsApp.
   * Cloud API: marca como lida + typing_indicator no mesmo POST.
   * O indicador some sozinho em ~25s ou ao enviar a próxima mensagem.
   */
  async showTypingFor(providerMessageId: string): Promise<void> {
    await fetch(`${this.base}/${this.cfg.phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.cfg.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        status: 'read',
        message_id: providerMessageId,
        typing_indicator: { type: 'text' },
      }),
    })
  }

  /** @deprecated Cloud API exige message_id da última msg do user. Use showTypingFor. */
  async setTyping(_to: string, _state: 'typing' | 'recording' | 'idle'): Promise<void> {
    // No-op no Cloud API. Use showTypingFor(providerMessageId).
  }

  /**
   * Reage a uma mensagem do user com emoji.
   * Passar emoji='' remove a reação.
   */
  async react(to: string, providerMessageId: string, emoji: string): Promise<SendResult> {
    return this.post({
      messaging_product: 'whatsapp',
      to,
      type: 'reaction',
      reaction: {
        message_id: providerMessageId,
        emoji,
      },
    })
  }

  parseInbound(payload: unknown): NormalizedInbound[] {
    const result: NormalizedInbound[] = []
    const p = payload as {
      entry?: Array<{
        changes?: Array<{
          field?: string
          value?: {
            messages?: Array<{
              id: string
              from: string
              type: string
              timestamp: string
              text?: { body: string }
              image?: { id: string; caption?: string; mime_type: string }
              audio?: { id: string; mime_type: string }
              video?: { id: string; mime_type: string }
            }>
          }
        }>
      }>
    }
    for (const entry of p.entry ?? []) {
      for (const change of entry.changes ?? []) {
        if (change.field !== 'messages') continue
        for (const msg of change.value?.messages ?? []) {
          result.push({
            providerMessageId: msg.id,
            from: msg.from,
            type:
              msg.type === 'text'
                ? 'text'
                : msg.type === 'audio'
                  ? 'audio'
                  : msg.type === 'image'
                    ? 'image'
                    : 'text',
            text: msg.text?.body ?? msg.image?.caption,
            mediaUrl: msg.image?.id ?? msg.audio?.id,
            mediaMimeType: msg.image?.mime_type ?? msg.audio?.mime_type,
            timestamp: new Date(Number.parseInt(msg.timestamp, 10) * 1000),
            raw: msg,
          })
        }
      }
    }
    return result
  }

  verifyWebhook(headers: Record<string, string>, rawBody: string): boolean {
    const sig = headers['x-hub-signature-256'] ?? headers['X-Hub-Signature-256']
    if (!sig) return false
    const expected = `sha256=${createHmac('sha256', this.cfg.appSecret).update(rawBody).digest('hex')}`
    if (sig.length !== expected.length) return false
    return timingSafeEqual(Buffer.from(sig), Buffer.from(expected))
  }

  async getQualityStatus(): Promise<QualityStatus> {
    const r = await fetch(
      `${this.base}/${this.cfg.phoneNumberId}?fields=quality_rating,messaging_limit_tier,display_phone_number`,
      { headers: { Authorization: `Bearer ${this.cfg.accessToken}` } },
    )
    if (!r.ok) return { rating: 'UNKNOWN', tier: 'unknown' }
    const json = (await r.json()) as { quality_rating?: string; messaging_limit_tier?: string }
    return {
      rating: (json.quality_rating ?? 'UNKNOWN') as QualityStatus['rating'],
      tier: json.messaging_limit_tier ?? 'unknown',
    }
  }
}
