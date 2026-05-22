import { describe, it, expect } from 'vitest'
import { eatingBalance, netBalance, realDailyDeficit } from './balance.js'

describe('balanços (regra MPP)', () => {
  it('eatingBalance = consumido − meta (SEM exercício)', () => {
    expect(eatingBalance(1407, 1843)).toBe(-436)
    expect(eatingBalance(2076, 1843)).toBe(233)
  })
  it('netBalance = consumido − meta − exercício (déficit do dia / bloco)', () => {
    expect(netBalance(2076, 1843, 565)).toBe(-332)
    expect(netBalance(1210, 1843, 467)).toBe(-1100)
  })
})

describe('realDailyDeficit (déficit REAL vs manutenção — o que o bloco credita)', () => {
  // = déficit programado − netBalance. Roberto 2026-05-21: comeu +126 vs meta,
  // treinou 523 → netBalance −397; déficit real = 500 − (−397) = 897 (NÃO 397).
  it('caso Roberto: 500 − (−397) = 897', () => {
    expect(realDailyDeficit(500, -397)).toBe(897)
  })
  it('negativo quando comeu acima da MANUTENÇÃO (superávit real)', () => {
    expect(realDailyDeficit(500, 700)).toBe(-200)
  })
  it('protocolo sem déficit programado (0): = −netBalance', () => {
    expect(realDailyDeficit(0, -100)).toBe(100)
  })
})
