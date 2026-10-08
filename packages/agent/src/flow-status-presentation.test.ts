import { describe, expect, it } from 'vitest'
import { type BalanceCardData, renderBalanceCard } from './balance-card.js'
import {
  composeFlowStatusMessage,
  flowStatusExplanation,
  renderFlowStatusCard,
} from './flow-status-presentation.js'
import { composeStatusMessage } from './post-registration-message.js'

const card: BalanceCardData = Object.freeze({
  caloriesConsumed: 1500,
  caloriesTarget: 1800,
  proteinG: 90,
  proteinTarget: 120,
  exerciseCalories: 200,
  deficitBlock: 3120,
  protocol: 'ganho_massa',
  last14d: Object.freeze({
    consumed_total: 21000,
    target_total: 25200,
    dam: 6,
    days_with_data: 14,
  }),
})
const progress = Object.freeze({ currentStreak: 7, level: 2, xpTotal: 155, blocksCompleted: 4 })

describe('Flow deterministic status presentation', () => {
  it.each([
    'ganho_massa',
    'manutencao',
    null,
  ] as const)('%s omits pending budget/DAM and completed blocks without changing inputs or shared defaults', (protocol) => {
    const input = Object.freeze({ ...card, protocol })
    const before = structuredClone(input)
    const legacyCard = renderBalanceCard(input)
    const legacyStatus = composeStatusMessage(input, progress)
    const publicCard = renderFlowStatusCard(input)
    const publicStatus = composeFlowStatusMessage(input, progress)

    expect(publicCard).toBe(
      [
        '🔥 Consumido: **1.500 / 1.800 kcal (83%)**',
        '🎯 Restam: **300 kcal**',
        '💪 Proteína: **90 / 120g (75%)**',
        '🏃🏻 Exercício: **200 kcal**',
      ].join('\n'),
    )
    expect(publicStatus).toBe(
      `${publicCard}\n\n🏅 Sequência: **7 dias consecutivos** · Nível 2 (155 XP)`,
    )
    expect(publicStatus).not.toMatch(/bloco\(s\)|Orçamento|DAM|3\.120/)
    expect(legacyCard).toContain('Orçamento 14d: **21.000 / 25.200 kcal (83%)** · DAM: 6/14')
    expect(legacyStatus).toContain('4 bloco(s) de 7.700 completo(s)')
    expect(input).toEqual(before)
    expect(renderBalanceCard(input)).toBe(legacyCard)
    expect(composeStatusMessage(input, progress)).toBe(legacyStatus)
    expect(progress.blocksCompleted).toBe(4)
  })

  it('recomposition retains the same block, progress, food and exercise values', () => {
    const input = Object.freeze({ ...card, protocol: 'recomposicao' as const })
    expect(renderFlowStatusCard(input)).toBe(renderBalanceCard(input))
    expect(composeFlowStatusMessage(input, progress)).toBe(composeStatusMessage(input, progress))
    expect(composeFlowStatusMessage(input, progress)).toContain('3.120 / 7.700 kcal (41%)')
    expect(composeFlowStatusMessage(input, progress)).toContain('4 bloco(s) de 7.700 completo(s)')
    expect(composeFlowStatusMessage(input, progress)).not.toMatch(/Orçamento|DAM/)
  })

  it.each([
    'ganho_massa',
    'manutencao',
  ])('explains visibility for %s without claiming credit was stopped', (protocol) => {
    expect(flowStatusExplanation(protocol)).toBe(
      'O Bloco 7.700 é exibido apenas na recomposição corporal.',
    )
  })

  it.each([
    'recomposicao',
    null,
    undefined,
    'unknown',
  ])('no visibility claim for %s', (protocol) => {
    expect(flowStatusExplanation(protocol)).toBe('')
  })
})
