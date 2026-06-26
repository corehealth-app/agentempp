/**
 * Tests — computeProgress (audit 06-26 sprint pendentes Item 1).
 *
 * Foco: drift FP acumulado. Simula 30 dias de dayCredit float pra travar que
 * Math.round no acumulado total mantém paridade com accumulateBloco em
 * engine/bloco.ts.
 */
import { describe, expect, it } from 'vitest'
import { computeProgress } from './progress-calc.js'
import type { DailySnapshot, UserProgress } from './types.js'

const baseSnapshot: DailySnapshot = {
  date: new Date('2026-06-26T00:00:00.000Z'),
  caloriesConsumed: 1500,
  caloriesTarget: 1843,
  proteinG: 100,
  proteinTarget: 178,
  exerciseCalories: 0,
  trainingDone: false,
  xpEarned: 10,
  dailyBalance: -343,
}

const basePrev: UserProgress = {
  xpTotal: 0,
  level: 1,
  currentStreak: 0,
  longestStreak: 0,
  blocksCompleted: 0,
  deficitBlock: 0,
  badgesEarned: [],
  lastActiveDate: null,
}

describe('computeProgress — Math.round paridade FP (audit 06-26)', () => {
  it('30 iterações com dayCredit float → deficitBlock e total sempre inteiros', () => {
    let cur = basePrev
    for (let i = 0; i < 30; i++) {
      cur = computeProgress(baseSnapshot, cur, undefined, 343.1)
      // Invariante: totalDeficit = blocos × 7700 + deficitBlock, e tudo é
      // inteiro a cada passo (sem drift FP do reduce flutuante).
      expect(Number.isInteger(cur.deficitBlock)).toBe(true)
      expect(Number.isInteger(cur.blocksCompleted)).toBe(true)
    }
    // Resultado determinístico independente de drift FP — qualquer execução
    // ré-rodada deve dar o mesmo número exato.
    expect(cur.blocksCompleted).toBeGreaterThanOrEqual(1)
    expect(cur.deficitBlock).toBeGreaterThanOrEqual(0)
    expect(cur.deficitBlock).toBeLessThan(7700)
  })

  it('determinismo: 2 chamadas com mesmo input → mesmo output exato', () => {
    const a = computeProgress(baseSnapshot, basePrev, undefined, 343.7)
    const b = computeProgress(baseSnapshot, basePrev, undefined, 343.7)
    expect(a.deficitBlock).toBe(b.deficitBlock)
    expect(a.blocksCompleted).toBe(b.blocksCompleted)
  })

  it('superávit clampa em 0 (bug A audit-06-24 preserve)', () => {
    const cur = computeProgress(baseSnapshot, basePrev, undefined, -500)
    expect(cur.deficitBlock).toBe(0)
    expect(cur.blocksCompleted).toBe(0)
  })

  it('dayCredit=0 → deficitBlock inalterado, blocos inalterados', () => {
    const prev: UserProgress = { ...basePrev, deficitBlock: 1234, blocksCompleted: 2 }
    const cur = computeProgress(baseSnapshot, prev, undefined, 0)
    expect(cur.deficitBlock).toBe(1234)
    expect(cur.blocksCompleted).toBe(2)
  })

  // Audit 06-26 review HIGH 1: NaN/Infinity guard
  it('dayCredit=NaN → clampa em 0, deficitBlock preservado (sem corrupção)', () => {
    const prev: UserProgress = { ...basePrev, deficitBlock: 1234, blocksCompleted: 2 }
    const cur = computeProgress(baseSnapshot, prev, undefined, Number.NaN)
    expect(Number.isFinite(cur.deficitBlock)).toBe(true)
    expect(cur.deficitBlock).toBe(1234) // inalterado
    expect(cur.blocksCompleted).toBe(2)
  })

  it('dayCredit=Infinity → clampa em 0, sem NaN propagado', () => {
    const cur = computeProgress(baseSnapshot, basePrev, undefined, Number.POSITIVE_INFINITY)
    expect(Number.isFinite(cur.deficitBlock)).toBe(true)
    expect(cur.deficitBlock).toBe(0)
  })

  it('dayCredit=-Infinity → clampa em 0 (não vai pra negativo nem NaN)', () => {
    const prev: UserProgress = { ...basePrev, deficitBlock: 500, blocksCompleted: 1 }
    const cur = computeProgress(baseSnapshot, prev, undefined, Number.NEGATIVE_INFINITY)
    expect(Number.isFinite(cur.deficitBlock)).toBe(true)
    expect(cur.deficitBlock).toBe(500) // inalterado pelo clamp
    expect(cur.blocksCompleted).toBe(1)
  })
})
