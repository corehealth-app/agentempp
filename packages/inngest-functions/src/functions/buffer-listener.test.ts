import { describe, expect, it } from 'vitest'
import {
  collectProviderMessageIds,
  collectProviderTimestamps,
  type BufferedInboundMessage,
} from './buffer-listener.js'

describe('buffer-listener providerMessageIds', () => {
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
})
