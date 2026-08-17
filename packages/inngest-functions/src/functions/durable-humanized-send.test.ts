import type { MessagingProvider } from '@mpp/providers'
import { describe, expect, it, vi } from 'vitest'
import { type StepRunner, sendHumanizedDurably } from './durable-humanized-send.js'

function createMemoizedStepRunner() {
  const completed = new Map<string, Awaited<ReturnType<StepRunner>>>()
  const run: StepRunner = async (id, operation) => {
    const existing = completed.get(id)
    if (existing) return existing
    const value = await operation()
    completed.set(id, value)
    return value
  }
  return run
}

describe('sendHumanizedDurably', () => {
  it('repete apenas o chunk que falhou quando o workflow tenta novamente', async () => {
    const sendText = vi
      .fn()
      .mockResolvedValueOnce({ status: 'sent', providerMessageId: 'out-1' })
      .mockRejectedValueOnce(new Error('provider unavailable'))
      .mockResolvedValueOnce({ status: 'sent', providerMessageId: 'out-2' })
    const runStep = createMemoizedStepRunner()
    const input = {
      provider: { sendText } as unknown as MessagingProvider,
      to: '15550000000',
      text: 'Primeiro trecho.\n\nSegundo trecho.',
      stepPrefix: 'send-to-user',
      runStep,
      opts: { minDelay: 0, maxDelay: 0, showTyping: false, replyTo: 'in-1' },
    }

    await expect(sendHumanizedDurably(input)).rejects.toThrow('provider unavailable')
    await expect(sendHumanizedDurably(input)).resolves.toMatchObject([
      { content: 'Primeiro trecho.', providerMessageId: 'out-1' },
      { content: 'Segundo trecho.', providerMessageId: 'out-2' },
    ])

    expect(sendText.mock.calls).toEqual([
      ['15550000000', 'Primeiro trecho.', { replyTo: 'in-1' }],
      ['15550000000', 'Segundo trecho.', undefined],
      ['15550000000', 'Segundo trecho.', undefined],
    ])
  })

  it('trata status failed como falha durável e não avança para o próximo chunk', async () => {
    const sendText = vi.fn().mockResolvedValue({
      status: 'failed',
      providerMessageId: null,
      error: 'delivery rejected',
    })

    await expect(
      sendHumanizedDurably({
        provider: { sendText } as unknown as MessagingProvider,
        to: '15550000000',
        text: 'Primeiro trecho.\n\nSegundo trecho.',
        stepPrefix: 'send-to-user',
        runStep: createMemoizedStepRunner(),
        opts: { minDelay: 0, maxDelay: 0, showTyping: false },
      }),
    ).rejects.toThrow('delivery rejected')

    expect(sendText).toHaveBeenCalledTimes(1)
  })

  it('mantém uma única etapa quando singleMessage está ativo', async () => {
    const sendText = vi
      .fn()
      .mockResolvedValue({ status: 'queued', providerMessageId: 'out-single' })
    const runStep = vi.fn(createMemoizedStepRunner())

    const result = await sendHumanizedDurably({
      provider: { sendText } as unknown as MessagingProvider,
      to: '15550000000',
      text: 'Linha um.\n\nLinha dois.',
      stepPrefix: 'send-card',
      runStep,
      opts: { minDelay: 0, maxDelay: 0, showTyping: false, singleMessage: true },
    })

    expect(result).toHaveLength(1)
    expect(result[0]?.content).toBe('Linha um.\n\nLinha dois.')
    expect(runStep).toHaveBeenCalledTimes(1)
    expect(runStep.mock.calls[0]?.[0]).toBe('send-card-chunk-1')
  })
})
