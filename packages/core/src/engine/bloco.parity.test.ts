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
