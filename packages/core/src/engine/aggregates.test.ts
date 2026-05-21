import { describe, it, expect } from 'vitest'
import { computePeriodSummary, type SnapshotForAgg } from './aggregates.js'

const day = (o: Partial<SnapshotForAgg>): SnapshotForAgg => ({
  calories_consumed: 1500,
  protein_g: 120,
  daily_balance: -300,
  day_status: 'complete',
  ...o,
})

describe('computePeriodSummary', () => {
  it('janela vazia → tudo zero', () => {
    expect(computePeriodSummary([])).toEqual({
      days: 0,
      avgConsumed: 0,
      avgProtein: 0,
      avgNetBalance: 0,
      completeDays: 0,
      adherencePct: 0,
    })
  })

  it('médias e aderência', () => {
    const s = [
      day({ calories_consumed: 1400, protein_g: 100, daily_balance: -400, day_status: 'complete' }),
      day({ calories_consumed: 1600, protein_g: 140, daily_balance: -200, day_status: 'complete' }),
      day({ calories_consumed: 1500, protein_g: 120, daily_balance: -300, day_status: 'incomplete_no_response' }),
    ]
    const r = computePeriodSummary(s)
    expect(r.days).toBe(3)
    expect(r.avgConsumed).toBe(1500)
    expect(r.avgProtein).toBe(120)
    expect(r.avgNetBalance).toBe(-300)
    expect(r.completeDays).toBe(2)
    expect(r.adherencePct).toBe(67)
  })

  it('trata nulls como 0', () => {
    const r = computePeriodSummary([day({ calories_consumed: null, protein_g: null, daily_balance: null })])
    expect(r.avgConsumed).toBe(0)
    expect(r.avgProtein).toBe(0)
    expect(r.avgNetBalance).toBe(0)
  })
})
