import { describe, expect, it } from 'vitest'
import { KCAL_BLOCK, computeProgress, levelForXP } from '../src/progress-calc.js'
import type { DailySnapshot, UserProgress } from '../src/types.js'

const emptyProgress: UserProgress = {
  xpTotal: 0,
  level: 1,
  currentStreak: 0,
  longestStreak: 0,
  blocksCompleted: 0,
  deficitBlock: 0,
  badgesEarned: [],
  lastActiveDate: null,
}

function snapshot(overrides: Partial<DailySnapshot> = {}): DailySnapshot {
  return {
    date: new Date('2026-05-01'),
    caloriesConsumed: 1800,
    caloriesTarget: 2400,
    proteinG: 150,
    proteinTarget: 180,
    exerciseCalories: 200,
    trainingDone: true,
    xpEarned: 30,
    dailyBalance: 1800 - 2400 - 200, // -800
    ...overrides,
  }
}

describe('levelForXP', () => {
  it('mapeia faixas corretamente (oficial Notion: 0/100/300/600/1000/1500/2200/3000)', () => {
    expect(levelForXP(0).level).toBe(1)
    expect(levelForXP(99).level).toBe(1)
    expect(levelForXP(100).level).toBe(2)
    expect(levelForXP(299).level).toBe(2)
    expect(levelForXP(300).level).toBe(3)
    expect(levelForXP(599).level).toBe(3)
    expect(levelForXP(600).level).toBe(4)
    expect(levelForXP(1000).level).toBe(5)
    expect(levelForXP(1500).level).toBe(6)
    expect(levelForXP(2200).level).toBe(7)
    expect(levelForXP(3000).level).toBe(8)
    expect(levelForXP(99999).level).toBe(8)
  })

  it('retorna nome do nível', () => {
    expect(levelForXP(0).name).toBe('Início')
    expect(levelForXP(100).name).toBe('Constância')
    expect(levelForXP(2200).name).toBe('Elite MPP')
    expect(levelForXP(3000).name).toBe('Lenda MPP')
  })
})

describe('computeProgress — XP e level', () => {
  it('soma XP e mantém em nível 1 se < 100', () => {
    const next = computeProgress(snapshot({ xpEarned: 50 }), emptyProgress)
    expect(next.xpTotal).toBe(50)
    expect(next.level).toBe(1)
  })

  it('passa de nível ao cruzar threshold', () => {
    const next = computeProgress(snapshot({ xpEarned: 100 }), emptyProgress)
    expect(next.level).toBe(2)
  })
})

describe('computeProgress — streak', () => {
  it('inicia streak em 1 quando lastActiveDate é null', () => {
    const next = computeProgress(snapshot(), emptyProgress)
    expect(next.currentStreak).toBe(1)
    expect(next.longestStreak).toBe(1)
  })

  it('incrementa quando snapshot é dia seguinte ao último', () => {
    const prev: UserProgress = {
      ...emptyProgress,
      currentStreak: 5,
      longestStreak: 5,
      lastActiveDate: new Date('2026-04-30'),
    }
    const next = computeProgress(snapshot({ date: new Date('2026-05-01') }), prev)
    expect(next.currentStreak).toBe(6)
  })

  it('reseta para 1 se gap > 1 dia', () => {
    const prev: UserProgress = {
      ...emptyProgress,
      currentStreak: 10,
      longestStreak: 10,
      lastActiveDate: new Date('2026-04-25'),
    }
    const next = computeProgress(snapshot({ date: new Date('2026-05-01') }), prev)
    expect(next.currentStreak).toBe(1)
    expect(next.longestStreak).toBe(10) // preserva máximo
  })
})

describe('computeProgress — bloco 7700 kcal', () => {
  it('acumula déficit dentro do bloco', () => {
    const next = computeProgress(snapshot({ dailyBalance: -500 }), emptyProgress)
    expect(next.deficitBlock).toBe(500)
    expect(next.blocksCompleted).toBe(0)
  })

  it('completa bloco quando atinge 7700', () => {
    const prev: UserProgress = { ...emptyProgress, deficitBlock: 7500 }
    const next = computeProgress(snapshot({ dailyBalance: -300 }), prev)
    expect(next.blocksCompleted).toBe(1)
    expect(next.deficitBlock).toBe(100) // 7800 - 7700
  })

  it('saldo positivo (surplus) não diminui bloco existente', () => {
    const prev: UserProgress = { ...emptyProgress, deficitBlock: 1000 }
    const next = computeProgress(snapshot({ dailyBalance: 500 }), prev)
    expect(next.deficitBlock).toBe(1000)
  })

  it('múltiplos blocos num único dia (caso extremo)', () => {
    const next = computeProgress(snapshot({ dailyBalance: -KCAL_BLOCK * 2 - 100 }), emptyProgress)
    expect(next.blocksCompleted).toBe(2)
    expect(next.deficitBlock).toBe(100)
  })
})

describe('computeProgress — badges', () => {
  it('Primeira Semana ao chegar em streak 7', () => {
    const prev: UserProgress = {
      ...emptyProgress,
      currentStreak: 6,
      lastActiveDate: new Date('2026-04-30'),
    }
    const next = computeProgress(snapshot({ date: new Date('2026-05-01') }), prev)
    expect(next.currentStreak).toBe(7)
    expect(next.badgesEarned).toContain('Primeira Semana')
  })

  it('Primeiro Bloco ao completar primeiro bloco', () => {
    const prev: UserProgress = { ...emptyProgress, deficitBlock: 7500 }
    const next = computeProgress(snapshot({ dailyBalance: -300 }), prev)
    expect(next.badgesEarned).toContain('Primeiro Bloco')
  })

  it('XP Master em 1000 XP', () => {
    const prev: UserProgress = { ...emptyProgress, xpTotal: 980 }
    const next = computeProgress(snapshot({ xpEarned: 30 }), prev)
    expect(next.xpTotal).toBe(1010)
    expect(next.badgesEarned).toContain('XP Master')
  })

  it('não duplica badges já conquistadas', () => {
    const prev: UserProgress = {
      ...emptyProgress,
      currentStreak: 7,
      badgesEarned: ['Primeira Semana'],
      lastActiveDate: new Date('2026-04-30'),
    }
    const next = computeProgress(snapshot({ date: new Date('2026-05-01') }), prev)
    expect(next.badgesEarned.filter((b) => b === 'Primeira Semana')).toHaveLength(1)
  })
})
