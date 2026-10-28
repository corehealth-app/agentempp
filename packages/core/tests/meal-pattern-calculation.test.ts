import { describe, expect, it } from 'vitest'
import {
  deriveMealGap,
  deriveMealPatternFromRows,
  deriveSkippedMealsFromCandidates,
} from '../src/meal-pattern-calculation.js'

const snapshots = Array.from({ length: 6 }, (_, n) => ({ id: `snapshot-${n}` }))
const meals = (count: number, meal_type: string) =>
  snapshots.slice(0, count).map((s) => ({ snapshot_id: s.id, meal_type }))

describe('shared unchanged meal pattern and gap calculation', () => {
  it('uses the fallback immediately when no snapshots were selected', () => {
    const p = deriveMealPatternFromRows([], meals(6, 'almoco'))
    expect([...p.expected]).toEqual(['cafe', 'almoco', 'jantar'])
    expect(p.activeDays).toBe(0)
    expect(p.fallbackUsed).toBe(true)
  })
  it('counts distinct snapshot IDs, preserves statistics, and falls back below five active days', () => {
    const rows = [...meals(4, 'ceia'), ...meals(4, 'ceia')]
    const p = deriveMealPatternFromRows(snapshots, rows)
    expect(p.activeDays).toBe(4)
    expect(p.countByType.ceia).toBe(4)
    expect([...p.expected]).toEqual(['cafe', 'almoco', 'jantar'])
  })
  it('uses the inclusive 50 percent threshold and canonical category order', () => {
    const p = deriveMealPatternFromRows(snapshots, [
      ...meals(6, 'almoco'),
      ...meals(3, 'cafe'),
      ...meals(2, 'jantar'),
    ])
    expect(p.fallbackUsed).toBe(false)
    expect([...p.expected]).toEqual(['cafe', 'almoco'])
  })
  it('counts unknown non-null types in the denominator without creating a known category', () => {
    const p = deriveMealPatternFromRows(snapshots, [...meals(6, 'unknown'), ...meals(2, 'cafe')])
    expect(p.activeDays).toBe(6)
    expect([...p.expected]).toEqual([])
  })
  it('keeps explicit thresholds unchanged, including zero-frequency categories at zero', () => {
    expect([
      ...deriveMealPatternFromRows(snapshots, meals(5, 'almoco'), { thresholdPct: 1 }).expected,
    ]).toEqual(['almoco'])
    expect([
      ...deriveMealPatternFromRows(snapshots, meals(5, 'almoco'), { thresholdPct: 0 }).expected,
    ]).toEqual(['cafe', 'almoco', 'lanche', 'jantar', 'ceia'])
  })
  it('deduplicates skips and respects explicit dates over interval-selected legacy candidates', () => {
    const skipped = deriveSkippedMealsFromCandidates('2026-10-02', [
      { properties: { local_date: '2026-10-02', meal_type: 'jantar' } },
      { properties: { local_date: '2026-10-02', meal_type: 'jantar' } },
      { properties: { local_date: '2026-10-03', meal_type: 'cafe' } },
      { properties: { local_date: 123, meal_type: 'almoco' } },
      { properties: { meal_type: 'ceia' } },
      { properties: null },
      { properties: { meal_type: 'unknown' } },
    ])
    expect([...skipped]).toEqual(['jantar', 'almoco', 'ceia'])
  })
  it('derives an ordered gap even without a target snapshot and preserves unknown registered strings', () => {
    const pattern = deriveMealPatternFromRows([], [])
    expect([...deriveMealGap(pattern, [], new Set()).gap]).toEqual(['cafe', 'almoco', 'jantar'])
    const r = deriveMealGap(
      pattern,
      [{ meal_type: 'unknown' }, { meal_type: 'almoco' }],
      new Set(['jantar']),
    )
    expect([...r.registered]).toEqual(['unknown', 'almoco'])
    expect([...r.gap]).toEqual(['cafe'])
  })
  it('does not allow one caller to poison the fallback used by another calculation', () => {
    const first = deriveMealPatternFromRows([], [])
    first.expected.clear()
    expect([...deriveMealPatternFromRows([], []).expected]).toEqual(['cafe', 'almoco', 'jantar'])
    expect([...deriveMealPatternFromRows(snapshots, meals(4, 'ceia')).expected]).toEqual([
      'cafe',
      'almoco',
      'jantar',
    ])
  })
})
