import { describe, expect, it } from 'vitest'
import {
  buildBufferDispatchEventId,
  buildBufferedDispatchPayload,
  collectProviderMessageIds,
  collectProviderTimestamps,
  type BufferedInboundMessage,
} from './buffer-listener.js'

describe('buffer-listener providerMessageIds', () => {
  it('gera id estável para retries do mesmo burst e distinto para outro burst', () => {
    const first = buildBufferDispatchEventId('user-1', 'wamid-2')

    expect(buildBufferDispatchEventId('user-1', 'wamid-2')).toBe(first)
    expect(buildBufferDispatchEventId('user-1', 'wamid-3')).not.toBe(first)
    expect(buildBufferDispatchEventId('user-2', 'wamid-2')).not.toBe(first)
    expect(first).toMatch(/^buffer-dispatch-[a-f0-9]{64}$/)
  })

  it('preserva todos os providerMessageIds do burst na ordem de chegada', () => {
    const msgs: BufferedInboundMessage[] = [
      {
        provider_message_id: 'wamid-1',
        content_type: 'text',
        text: '20 min de bicicleta',
        received_at: '2026-07-02T01:47:21.000Z',
      },
      {
        provider_message_id: 'wamid-2',
        content_type: 'text',
        text: 'E 35 min de musculação',
        received_at: '2026-07-02T01:47:29.000Z',
      },
    ]

    expect(collectProviderMessageIds(msgs)).toEqual(['wamid-1', 'wamid-2'])
  })

  it('preserva todos os timestamps do provider alinhados aos ids', () => {
    const msgs: BufferedInboundMessage[] = [
      {
        provider_message_id: 'wamid-1',
        content_type: 'text',
        text: 'primeira',
        received_at: '2026-07-10T03:59:58.000Z',
      },
      {
        provider_message_id: 'wamid-2',
        content_type: 'text',
        text: 'segunda',
        received_at: '2026-07-10T04:00:02.000Z',
      },
    ]

    expect(collectProviderTimestamps(msgs)).toEqual([
      '2026-07-10T03:59:58.000Z',
      '2026-07-10T04:00:02.000Z',
    ])
  })

  it('compõe o lote reivindicado sem perder textos nem múltiplas imagens', () => {
    const payload = buildBufferedDispatchPayload([
      {
        provider_message_id: 'wamid-image-1',
        content_type: 'image',
        text: 'frente',
        mediaUrl: 'media-1',
        received_at: '2026-07-12T12:00:00.000Z',
      },
      {
        provider_message_id: 'wamid-image-2',
        content_type: 'image',
        text: 'costas',
        mediaUrl: 'media-2',
        received_at: '2026-07-12T12:00:02.000Z',
      },
    ])

    expect(payload.contentType).toBe('image')
    expect(payload.aggregated).toBe('frente\ncostas')
    expect(payload.mediaUrls).toEqual(['media-1', 'media-2'])
    expect(payload.latest.provider_message_id).toBe('wamid-image-2')
  })
})
