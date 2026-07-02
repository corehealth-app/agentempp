import { describe, expect, it } from 'vitest'
import { creditDayToBloco } from '@mpp/core'

describe('bloco credit policy used by daily-closer/recompute', () => {
  it('gap aberto no fechamento credita 0 mesmo com déficit observado', () => {
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'incomplete_no_response',
        caloriesConsumed: 1245,
        caloriesTarget: 1946,
        dailyBalance: -701,
        designDeficit: 500,
      }),
    ).toBe(0)
  })

  it('gap resolvido como complete volta a creditar normalmente', () => {
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'complete',
        caloriesConsumed: 1245,
        caloriesTarget: 1946,
        dailyBalance: -701,
        designDeficit: 500,
      }),
    ).toBe(1201)
  })
})
