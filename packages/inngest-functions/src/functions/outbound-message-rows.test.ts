import { describe, expect, it } from 'vitest'
import { buildOutboundMessageRows } from './outbound-message-rows.js'

describe('buildOutboundMessageRows', () => {
  it('persiste uma linha por bolha com provider id e custo apenas uma vez', () => {
    const rows = buildOutboundMessageRows({
      userId: 'user-1',
      provider: 'whatsapp_cloud',
      contentType: 'text',
      stage: 'recomposicao',
      modelUsed: 'model-x',
      promptTokens: 100,
      completionTokens: 20,
      costUsd: 0.01,
      latencyMs: 900,
      deliveries: [
        { content: 'Tabela', providerMessageId: 'wamid-1', status: 'sent' },
        { content: 'Comentário', providerMessageId: 'wamid-2', status: 'sent' },
        { content: 'Card', providerMessageId: 'wamid-3', status: 'queued' },
      ],
    })

    expect(rows).toHaveLength(3)
    expect(rows.map((row) => row.provider_message_id)).toEqual(['wamid-1', 'wamid-2', 'wamid-3'])
    expect(rows.map((row) => row.content)).toEqual(['Tabela', 'Comentário', 'Card'])
    expect(rows.map((row) => row.delivery_status)).toEqual(['sent', 'sent', 'queued'])
    expect(rows.map((row) => row.cost_usd)).toEqual([0.01, null, null])
    expect(rows.map((row) => row.prompt_tokens)).toEqual([100, null, null])
  })
})
