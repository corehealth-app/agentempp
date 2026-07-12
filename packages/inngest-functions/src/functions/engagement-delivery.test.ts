import { describe, expect, it } from 'vitest'
import {
  classifyAudioEngagementDelivery,
  classifyTextEngagementDelivery,
  shouldSendEngagementAsAudio,
} from './engagement-delivery.js'

describe('engagement delivery classification', () => {
  it('aceita todas as bolhas de texto somente com confirmação e provider id', () => {
    expect(
      classifyTextEngagementDelivery(
        [
          { content: 'Bom dia', status: 'sent', providerMessageId: 'wamid-1' },
          { content: 'Vamos nessa', status: 'sent', providerMessageId: 'wamid-2' },
        ],
        '2026-07-12T12:00:00.000Z',
      ),
    ).toEqual({
      sent: true,
      sentAt: '2026-07-12T12:00:00.000Z',
      deliveries: [
        {
          content: 'Bom dia',
          contentType: 'text',
          mediaUrl: null,
          providerMessageId: 'wamid-1',
        },
        {
          content: 'Vamos nessa',
          contentType: 'text',
          mediaUrl: null,
          providerMessageId: 'wamid-2',
        },
      ],
    })
  })

  it.each([
    [[]],
    [[{ content: 'x', status: 'failed' as const, providerMessageId: null }]],
    [[{ content: 'x', status: 'sent' as const, providerMessageId: null }]],
    [
      [
        { content: 'a', status: 'sent' as const, providerMessageId: 'wamid-a' },
        { content: 'b', status: 'queued' as const, providerMessageId: 'wamid-b' },
      ],
    ],
  ])('rejeita entrega de texto parcial ou sem identidade: %j', (results) => {
    expect(classifyTextEngagementDelivery(results, '2026-07-12T12:00:00.000Z')).toMatchObject({
      sent: false,
    })
  })

  it('classifica áudio com o texto e media id persistíveis', () => {
    expect(
      classifyAudioEngagementDelivery(
        { status: 'sent', providerMessageId: 'wamid-audio' },
        'Mensagem falada',
        'media-1',
        '2026-07-12T12:00:00.000Z',
      ),
    ).toMatchObject({
      sent: true,
      deliveries: [
        {
          content: 'Mensagem falada',
          contentType: 'audio',
          mediaUrl: 'media-1',
          providerMessageId: 'wamid-audio',
        },
      ],
    })
  })
})

describe('shouldSendEngagementAsAudio', () => {
  it('é estável para o mesmo usuário e data e respeita os limites', () => {
    const first = shouldSendEngagementAsAudio('user-1', '2026-07-12', 0.25)
    expect(shouldSendEngagementAsAudio('user-1', '2026-07-12', 0.25)).toBe(first)
    expect(shouldSendEngagementAsAudio('user-1', '2026-07-12', 0)).toBe(false)
    expect(shouldSendEngagementAsAudio('user-1', '2026-07-12', 1)).toBe(true)
  })
})
