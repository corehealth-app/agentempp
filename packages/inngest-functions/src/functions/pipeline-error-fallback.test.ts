import { describe, expect, it, vi } from 'vitest'
import { sendPipelineErrorFallback } from './pipeline-error-fallback.js'

describe('sendPipelineErrorFallback', () => {
  it('repete sem reply quando o provider rejeita a primeira entrega', async () => {
    const sendText = vi
      .fn()
      .mockResolvedValueOnce({ status: 'failed', providerMessageId: null, error: 'bad reply' })
      .mockResolvedValueOnce({ status: 'sent', providerMessageId: 'out-2' })

    await expect(
      sendPipelineErrorFallback({ sendText } as never, '15550000000', 'Tente novamente', 'in-1'),
    ).resolves.toMatchObject({ status: 'sent', providerMessageId: 'out-2' })
    expect(sendText.mock.calls).toEqual([
      ['15550000000', 'Tente novamente', { replyTo: 'in-1' }],
      ['15550000000', 'Tente novamente'],
    ])
  })

  it('aceita queued como entrega válida após exceção na tentativa com reply', async () => {
    const sendText = vi
      .fn()
      .mockRejectedValueOnce(new Error('reply unavailable'))
      .mockResolvedValueOnce({ status: 'queued', providerMessageId: 'out-queued' })

    await expect(
      sendPipelineErrorFallback({ sendText } as never, '15550000000', 'Tente novamente', 'in-1'),
    ).resolves.toMatchObject({ status: 'queued', providerMessageId: 'out-queued' })
  })

  it('propaga a falha final quando as duas tentativas são rejeitadas', async () => {
    const sendText = vi
      .fn()
      .mockResolvedValueOnce({ status: 'failed', providerMessageId: null, error: 'bad reply' })
      .mockResolvedValueOnce({ status: 'failed', providerMessageId: null, error: 'provider down' })

    await expect(
      sendPipelineErrorFallback({ sendText } as never, '15550000000', 'Tente novamente', 'in-1'),
    ).rejects.toThrow('provider down')
  })
})
