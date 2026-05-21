import { describe, it, expect } from 'vitest'
import { creditDayToBloco, accumulateBloco, KCAL_BLOCK } from './bloco.js'

describe('creditDayToBloco — regra de crédito por dia (fiel ao daily-closer)', () => {
  const base = {
    hasActivity: true,
    dayStatus: 'complete' as const,
    caloriesConsumed: 1500,
    caloriesTarget: 1843,
    dailyBalance: -343,
    designDeficit: 500,
  }
  it('dia complete >=50%: designDeficit + déficit observado', () => {
    expect(creditDayToBloco(base)).toBe(843)
  })
  it('sem atividade: crédito 0', () => {
    expect(creditDayToBloco({ ...base, hasActivity: false })).toBe(0)
  })
  it('sub-registro <50% complete: credita só o designDeficit', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 400, dailyBalance: -1443 })).toBe(500)
  })
  it('sub-registro <50% incomplete: credita 0', () => {
    expect(creditDayToBloco({ ...base, dayStatus: 'incomplete_no_response', caloriesConsumed: 400, dailyBalance: -1443 })).toBe(0)
  })
  it('incomplete >=50%: credita só o déficit observado (sem designDeficit)', () => {
    expect(creditDayToBloco({ ...base, dayStatus: 'incomplete_no_response' })).toBe(343)
  })
  it('user_skipped: credita normal mesmo com consumo baixo (Roberto 19/05 = 832)', () => {
    expect(creditDayToBloco({ ...base, dayStatus: 'user_skipped', caloriesConsumed: 2076, dailyBalance: -332 })).toBe(832)
  })
  it('excedente leve (dd absorve): dd 500, balance +357 → 143 (fiel ao computeProgress)', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 2200, dailyBalance: 357 })).toBe(143)
  })
  it('excedente grande (> designDeficit): crédito 0, nunca negativo', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 2600, dailyBalance: 700 })).toBe(0)
  })
  it('protocolo não-recomp (designDeficit 0) on-plan: crédito 0', () => {
    expect(creditDayToBloco({ ...base, designDeficit: 0, dailyBalance: 0 })).toBe(0)
  })
})

describe('accumulateBloco', () => {
  it('soma % 7700 e conta blocos cheios', () => {
    expect(accumulateBloco([4000, 4000])).toEqual({ deficitBlock: 300, blocksCompleted: 1 })
  })
  it('lista vazia = 0/0', () => {
    expect(accumulateBloco([])).toEqual({ deficitBlock: 0, blocksCompleted: 0 })
  })
  it('arredonda a soma antes do módulo', () => {
    expect(accumulateBloco([100.4, 100.4])).toEqual({ deficitBlock: 201, blocksCompleted: 0 })
  })
})

describe('property: bloco sempre em [0, KCAL_BLOCK)', () => {
  it('para somas variadas', () => {
    for (const total of [0, 1, 7699, 7700, 7701, 15400, 23100.6]) {
      const r = accumulateBloco([total])
      expect(r.deficitBlock).toBeGreaterThanOrEqual(0)
      expect(r.deficitBlock).toBeLessThan(KCAL_BLOCK)
    }
  })
})
