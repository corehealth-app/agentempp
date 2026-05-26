import { describe, it, expect } from 'vitest'
import { sendHumanized } from './humanizer.js'
import type { MessagingProvider } from './types.js'

// Card determinístico de registro (Fase 1) com vários itens + decimais nos macros.
// Bug (Roberto 2026-05-26): sendHumanized quebrava isso em VÁRIAS mensagens
// (split por \n\n + sub-split por frase nos "." dos decimais "3.8g") → card
// chegava estilhaçado. Fix: opção singleMessage envia tudo em 1 mensagem.
const CARD = [
  'Almoço registrado ✅',
  '',
  '**Almoço:**',
  '• *arroz branco cozido (150g):* 192 kcal | 3.8g proteína | 42.1g carboidrato | 0.3g gordura',
  '• *camarão cozido (100g):* 130 kcal | 22g proteína | 0g carboidrato | 4g gordura',
  '• *lula cozida (80g):* 120 kcal | 5.6g proteína | 4g carboidrato | 4g gordura',
  '',
  '**Total: 442 kcal | 31.4g proteína | 46.1g carboidrato | 8.3g gordura**',
  '',
  '🔥 Consumido: **1.000 / 1.041 kcal (96%)**',
  '🎯 Restam: **41 kcal**',
].join('\n')

function mockProvider() {
  const sent: string[] = []
  const provider = {
    sendText: async (_to: string, text: string) => {
      sent.push(text)
      return { status: 'sent' as const }
    },
  } as unknown as MessagingProvider
  return { provider, sent }
}

describe('sendHumanized — singleMessage (card de registro)', () => {
  it('singleMessage: envia o card inteiro em UMA mensagem', async () => {
    const { provider, sent } = mockProvider()
    await sendHumanized(provider, '5511999999999', CARD, {
      singleMessage: true,
      minDelay: 0,
      maxDelay: 0,
      showTyping: false,
    })
    expect(sent.length).toBe(1)
    expect(sent[0]).toContain('Almoço registrado')
    expect(sent[0]).toContain('🔥 Consumido')
    expect(sent[0]).toContain('🎯 Restam')
  })

  it('sem singleMessage: o card longo é fragmentado em VÁRIAS mensagens (bug do print)', async () => {
    const { provider, sent } = mockProvider()
    await sendHumanized(provider, '5511999999999', CARD, {
      minDelay: 0,
      maxDelay: 0,
      showTyping: false,
    })
    expect(sent.length).toBeGreaterThan(1)
  })
})
