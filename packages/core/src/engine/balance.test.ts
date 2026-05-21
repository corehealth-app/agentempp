import { describe, it, expect } from 'vitest'
import { eatingBalance, netBalance } from './balance.js'

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
