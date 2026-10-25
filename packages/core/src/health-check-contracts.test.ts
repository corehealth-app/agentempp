import { describe, expect, it } from 'vitest'
import {
  HEALTH_CHECK_QUESTION,
  HEALTH_RISK_CODES,
  HEALTH_RISK_ITEMS,
  healthCheckDraftSchema,
  PROFESSIONAL_CONVERSATION_DECLARATION,
} from './health-check-contracts.js'

describe('n10 single shared health catalog — draft only, no clinical mutation', () => {
  it('pins the eight labels and their source order without a duplicate loss-of-control question', () => {
    expect(HEALTH_RISK_ITEMS.map((item) => item.label)).toEqual([
      'Perdi peso sem querer',
      'Estou comendo muito menos do que o planejado ou pulando refeições',
      'Cansaço forte, fraqueza ou tontura que não passam',
      'Menstruação irregular ou ausente',
      'Senti que perdi o controle sobre o quanto estava comendo',
      'Uso remédio ou faço tratamento que muda o apetite ou o peso',
      'Tenho uma condição em que um profissional controla a minha alimentação ou a proteína',
      'Estou grávida ou amamentando',
    ])
    expect(HEALTH_RISK_ITEMS.map((item) => item.code)).toEqual(HEALTH_RISK_CODES)
    expect(new Set(HEALTH_RISK_CODES).size).toBe(8)
    expect(HEALTH_CHECK_QUESTION).toBe(
      'Alguma destas situações vale para você agora? Marque todas que valerem.',
    )
    expect(PROFESSIONAL_CONVERSATION_DECLARATION).toBe(
      'Já conversei com um profissional sobre o que informei.',
    )
    expect(Object.isFrozen(HEALTH_RISK_ITEMS)).toBe(true)
    expect(HEALTH_RISK_ITEMS.every(Object.isFrozen)).toBe(true)
  })

  it('keeps unknown, explicit none and a nonempty canonical risk set distinct', () => {
    for (const blank of [null, undefined, '', '  ', 'prefiro_nao_responder']) {
      expect(healthCheckDraftSchema.parse(blank)).toBeNull()
    }
    expect(healthCheckDraftSchema.parse({ kind: 'none' })).toEqual({ kind: 'none' })
    const input = { kind: 'risks', items: ['professional_diet', 'unintended_weight_loss'] }
    const before = JSON.stringify(input)
    expect(healthCheckDraftSchema.parse(input)).toEqual({
      kind: 'risks',
      items: ['unintended_weight_loss', 'professional_diet'],
    })
    expect(JSON.stringify(input)).toBe(before)
  })

  it.each([
    { kind: 'risks', items: [] },
    { kind: 'risks', items: ['none'] },
    { kind: 'risks', items: ['unknown-risk'] },
    { kind: 'risks', items: ['reduced_intake', 'reduced_intake'] },
    { kind: 'none', items: ['reduced_intake'] },
    { kind: 'risks', items: ['professional_diet'], notes: 'private-free-text' },
  ])('rejects ambiguous, duplicate and noncanonical declarations %#', (input) => {
    expect(healthCheckDraftSchema.safeParse(input).success).toBe(false)
  })
})
