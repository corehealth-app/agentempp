import { Inngest, EventSchemas } from 'inngest'

/**
 * Eventos tipados que circulam no Inngest.
 *
 * Disparados por:
 *  - Edge Function webhook-whatsapp ao receber mensagem
 *  - pg_cron jobs ao bater o horário
 *  - PG_NOTIFY do buffer-flush
 */
type Events = {
  'message.received': {
    data: {
      userId: string
      wpp: string
      providerMessageId: string
      contentType: 'text' | 'audio' | 'image'
      text?: string
      mediaUrl?: string
      /** Quando há múltiplas mídias agregadas pelo buffer (ex: 3 fotos corporais). */
      mediaUrls?: string[]
      provider: string
      timestamp: string
    }
  }
  'day.close.tick': {
    data: { hour: number; fired_at: string }
  }
  'engagement.tick': {
    data: { slot: string; fired_at: string }
  }
  'buffer.flush': {
    data: { count: number; fired_at: string }
  }
  'wa.quality.check': {
    data: { fired_at: string }
  }
  'subscription.event': {
    data: {
      provider_event_id: string
      event_type: string
      raw: unknown
    }
  }
}

export const inngest = new Inngest({
  id: 'agentempp',
  name: 'Agente MPP',
  schemas: new EventSchemas().fromRecord<Events>(),
})

export type InngestEvents = Events
