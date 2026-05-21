import { describe, it, expect } from 'vitest'
import { creditDayToBloco, accumulateBloco } from './bloco.js'

// Paridade com blocos validados em produção em 2026-05-20.
type Day = {
  hasActivity: boolean
  dayStatus: 'complete' | 'incomplete_no_response' | 'user_skipped' | null
  caloriesConsumed: number
  caloriesTarget: number | null
  dailyBalance: number
}
function bloco(days: Day[], designDeficit: number) {
  return accumulateBloco(days.map((d) => creditDayToBloco({ ...d, designDeficit }))).deficitBlock
}

describe('paridade: engine reproduz valores validados em prod (2026-05-20)', () => {
  it('Roberto 19/05 (user_skipped) credita 832', () => {
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'user_skipped',
        caloriesConsumed: 2076,
        caloriesTarget: 1843,
        dailyBalance: -332,
        designDeficit: 500,
      }),
    ).toBe(832)
  })
  it('Raphaela: 1 dia sem atividade → bloco 0', () => {
    expect(
      bloco(
        [{ hasActivity: false, dayStatus: 'complete', caloriesConsumed: 0, caloriesTarget: 980, dailyBalance: -980 }],
        500,
      ),
    ).toBe(0)
  })
})

describe('fechamento (closer): replay multi-dia cobrindo as 6 ramificações', () => {
  // Cada dia espelha uma ramificação do daily-closer; o crédito esperado é o
  // mesmo que o closer produzia antes da migração (paridade por construção).
  it('acumula os créditos corretos no bloco', () => {
    const dias: Day[] = [
      { hasActivity: true, dayStatus: 'complete', caloriesConsumed: 1500, caloriesTarget: 1843, dailyBalance: -343 }, // 843
      { hasActivity: true, dayStatus: 'complete', caloriesConsumed: 400, caloriesTarget: 1843, dailyBalance: -1443 }, // sub-reg complete → 500
      { hasActivity: true, dayStatus: 'incomplete_no_response', caloriesConsumed: 400, caloriesTarget: 1843, dailyBalance: -1443 }, // sub-reg incomplete → 0
      { hasActivity: false, dayStatus: 'complete', caloriesConsumed: 0, caloriesTarget: 1843, dailyBalance: -1843 }, // sem atividade → 0
      { hasActivity: true, dayStatus: 'user_skipped', caloriesConsumed: 2076, caloriesTarget: 1843, dailyBalance: -332 }, // 832
      { hasActivity: true, dayStatus: 'incomplete_no_response', caloriesConsumed: 1300, caloriesTarget: 1843, dailyBalance: -343 }, // incomplete >=50% → 343
      { hasActivity: true, dayStatus: 'complete', caloriesConsumed: 2200, caloriesTarget: 1843, dailyBalance: 357 }, // excedente leve → 143
    ]
    // 843 + 500 + 0 + 0 + 832 + 343 + 143 = 2661
    expect(bloco(dias, 500)).toBe(2661)
  })
})
