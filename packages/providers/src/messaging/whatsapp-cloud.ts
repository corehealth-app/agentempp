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
    // 1. resolve URL
    const meta = await fetch(`${this.base}/${mediaId}`, {
      headers: { Authorization: `Bearer ${this.cfg.accessToken}` },
    }).then((r) => r.json() as Promise<{ url: string }>)
    // 2. baixa bytes
    const r = await fetch(meta.url, {
      headers: { Authorization: `Bearer ${this.cfg.accessToken}` },
    })
    if (!r.ok) throw new Error(`downloadMedia failed: ${r.status}`)
    return await r.blob()
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

  async setTyping(_to: string, state: 'typing' | 'recording' | 'idle'): Promise<void> {
    // typing_indicator é experimental; implementação completa requer typing_indicator request
    if (state === 'idle') return
    // No-op silencioso por enquanto.
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
