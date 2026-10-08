import { describe, expect, it } from 'vitest'
import { DEFAULT_CALC_CONFIG } from './calc-config.js'
import { creditDayToBloco } from './engine/bloco.js'
import { computeProgress } from './progress-calc.js'
import type { DailySnapshot, UserProgress } from './types.js'

const disabled = { version: 'flow-recomposition-v1', enabled: false } as const
const enabled = { version: 'flow-recomposition-v1', enabled: true } as const
const day = {
  hasActivity: true,
  dayStatus: 'complete',
  caloriesConsumed: 2600,
  caloriesTarget: 2498,
  dailyBalance: -198,
  designDeficit: 0,
} as const
const snapshot: DailySnapshot = {
  date: new Date('2026-10-04T00:00:00.000Z'),
  caloriesConsumed: 2600,
  caloriesTarget: 2498,
  proteinG: 140,
  proteinTarget: 120,
  exerciseCalories: 300,
  trainingDone: true,
  xpEarned: 20,
  dailyBalance: -198,
}
const previous: UserProgress = {
  xpTotal: 980,
  level: 4,
  currentStreak: 6,
  longestStreak: 6,
  blocksCompleted: 0,
  deficitBlock: 7600,
  badgesEarned: [],
  lastActiveDate: new Date('2026-10-03T00:00:00.000Z'),
}

describe('Flow C3 — crédito e conquistas fora da recomposição', () => {
  it.each([
    ['crédito positivo', -198, 198],
    ['débito por excedente', 502, -502],
  ] as const)('%s é zero apenas com política desabilitada explícita', (_label, balance, legacy) => {
    const input = { ...day, dailyBalance: balance }
    expect(creditDayToBloco(input, disabled)).toBe(0)
    expect(creditDayToBloco(input)).toBe(legacy)
  })

  it.each([
    'complete',
    'user_skipped',
    'incomplete_no_response',
    null,
  ] as const)('nenhum ramo de status %s pode ultrapassar o gate Flow', (status) => {
    expect(creditDayToBloco({ ...day, dayStatus: status, designDeficit: 500 }, disabled)).toBe(0)
  })

  it('recomposição mantém crédito832 e sub-registro500', () => {
    expect(creditDayToBloco({ ...day, dailyBalance: -332, designDeficit: 500 }, enabled)).toBe(832)
    expect(
      creditDayToBloco(
        { ...day, caloriesConsumed: 700, caloriesTarget: 1576, designDeficit: 500 },
        enabled,
      ),
    ).toBe(500)
  })

  it.each([
    198,
    -502,
    0,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('preserva saldo7600 e blocos0 mesmo com crédito recebido%s', (credit) => {
    const before = structuredClone(previous)
    const next = computeProgress(snapshot, previous, DEFAULT_CALC_CONFIG, credit, disabled)
    expect(next).toMatchObject({
      deficitBlock: 7600,
      blocksCompleted: 0,
      xpTotal: 1000,
      level: 5,
      currentStreak: 7,
      longestStreak: 7,
      badgesEarned: ['Primeira Semana', 'XP Master'],
      lastActiveDate: snapshot.date,
    })
    expect(previous).toEqual(before)
  })

  it('um bloco histórico sem medalha não adquire Primeiro Bloco em ganho/manutenção', () => {
    const next = computeProgress(
      snapshot,
      { ...previous, deficitBlock: 300, blocksCompleted: 1 },
      undefined,
      0,
      disabled,
    )
    expect(next).toMatchObject({
      deficitBlock: 300,
      blocksCompleted: 1,
      badgesEarned: ['Primeira Semana', 'XP Master'],
    })
  })

  it('medalha antiga permanece e saldo histórico fora da forma normal não é normalizado', () => {
    const next = computeProgress(
      snapshot,
      { ...previous, deficitBlock: 8000.5, blocksCompleted: 2, badgesEarned: ['Primeiro Bloco'] },
      undefined,
      198,
      disabled,
    )
    expect(next).toMatchObject({
      deficitBlock: 8000.5,
      blocksCompleted: 2,
      badgesEarned: ['Primeiro Bloco', 'Primeira Semana', 'XP Master'],
    })
  })

  it.each([
    undefined,
    enabled,
  ])('recomposição e default legado continuam cruzando o bloco', (policy) => {
    const next = computeProgress(snapshot, previous, undefined, 832, policy)
    expect(next).toMatchObject({
      deficitBlock: 732,
      blocksCompleted: 1,
      badgesEarned: ['Primeira Semana', 'Primeiro Bloco', 'XP Master'],
    })
  })
})
