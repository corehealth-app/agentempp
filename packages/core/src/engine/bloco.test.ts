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
  // Opção C (Roberto 2026-05-31): incomplete + paciente continuou interagindo
  // após reminder → credita normal (igual complete), pq não sumiu.
  it('incomplete + interactedAfterReminder=true: credita igual complete (Luciana 30/05)', () => {
    // Caso Luciana 30/05: cal=1527, target=1106, balance=+421, dd=500 → 500-421 = 79
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'incomplete_no_response',
        caloriesConsumed: 1527,
        caloriesTarget: 1106,
        dailyBalance: 421,
        designDeficit: 500,
        interactedAfterReminder: true,
      }),
    ).toBe(79)
  })
  it('incomplete + interactedAfterReminder=false: mantém comportamento conservador antigo', () => {
    // Mesmo input mas SEM interação após reminder → max(0, -421) = 0
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'incomplete_no_response',
        caloriesConsumed: 1527,
        caloriesTarget: 1106,
        dailyBalance: 421,
        designDeficit: 500,
        interactedAfterReminder: false,
      }),
    ).toBe(0)
  })
  it('user_skipped: credita normal mesmo com consumo baixo (Roberto 19/05 = 832)', () => {
    expect(creditDayToBloco({ ...base, dayStatus: 'user_skipped', caloriesConsumed: 2076, dailyBalance: -332 })).toBe(832)
  })
  it('excedente leve (dd absorve): dd 500, balance +357 → 143 (fiel ao computeProgress)', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 2200, dailyBalance: 357 })).toBe(143)
  })
  // MODELO LÍQUIDO (Roberto 2026-05-28): excedente que supera o designDeficit
  // gera crédito NEGATIVO — o dia ruim subtrai do cofrinho acumulado. Antes
  // era max(0, ...) → cofrinho só subia. Floor passou pro accumulateBloco.
  it('excedente grande (> designDeficit): dd 500, balance +700 → -200 (modelo líquido)', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 2600, dailyBalance: 700 })).toBe(-200)
  })
  it('superávit extremo: dd 500, balance +2000 → -1500 (subtrai pesado)', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 3900, dailyBalance: 2000 })).toBe(-1500)
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
  // MODELO LÍQUIDO (Roberto 2026-05-28): credits negativos subtraem do total.
  it('caso Roberto: cofrinho em 2000 + dia ruim -500 → 1500', () => {
    expect(accumulateBloco([2000, -500])).toEqual({ deficitBlock: 1500, blocksCompleted: 0 })
  })
  it('clamp: sequência grande de dia ruim NÃO deixa cofrinho negativo', () => {
    expect(accumulateBloco([300, -500, -200])).toEqual({ deficitBlock: 0, blocksCompleted: 0 })
  })
  it('décimos bons cruzam bloco; dia ruim grande retrocede', () => {
    // 8000 (= 1 bloco + 300) + dia ruim -500 → 7500 (0 bloco + 7500 no atual)
    expect(accumulateBloco([8000, -500])).toEqual({ deficitBlock: 7500, blocksCompleted: 0 })
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
