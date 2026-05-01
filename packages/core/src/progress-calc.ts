/**
 * Gamificação: XP, level, streak, blocos 7700, badges.
 * Replica a lógica do nó "Code Calcula Avanço" do n8n original.
 */
import type { DailySnapshot, UserProgress } from './types.js'

export const KCAL_BLOCK = 7700 // 1 kg de gordura

export const LEVELS = [
  { level: 1, name: 'Início', min: 0, max: 99 },
  { level: 2, name: 'Constância', min: 100, max: 249 },
  { level: 3, name: 'Foco', min: 250, max: 499 },
  { level: 4, name: 'Disciplina', min: 500, max: 999 },
  { level: 5, name: 'Performance', min: 1000, max: 1999 },
  { level: 6, name: 'Domínio', min: 2000, max: 3499 },
  { level: 7, name: 'Elite MPP', min: 3500, max: Number.POSITIVE_INFINITY },
] as const

export interface BadgeDefinition {
  key: string
  predicate: (p: UserProgress, blocksCompletedDelta: number) => boolean
}

const BADGE_DEFINITIONS: BadgeDefinition[] = [
  { key: 'Primeira Semana', predicate: (p) => p.currentStreak >= 7 },
  { key: 'Mês de Ferro', predicate: (p) => p.currentStreak >= 30 },
  { key: 'Atleta Real', predicate: (p) => p.currentStreak >= 90 },
  { key: 'Primeiro Bloco', predicate: (p) => p.blocksCompleted >= 1 },
  { key: 'XP Master', predicate: (p) => p.xpTotal >= 1000 },
  { key: 'Elite', predicate: (p) => p.xpTotal >= 3500 },
]

export function levelForXP(xp: number): { level: number; name: string } {
  // Garante que sempre encontra: o último nível tem max = Infinity
  for (let i = LEVELS.length - 1; i >= 0; i--) {
    const l = LEVELS[i]
    if (l && xp >= l.min) return { level: l.level, name: l.name }
  }
  return { level: 1, name: 'Início' }
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  )
}

function subDays(date: Date, days: number): Date {
  const d = new Date(date)
  d.setDate(d.getDate() - days)
  return d
}

/**
 * Aplica um snapshot diário ao progresso anterior, retornando o próximo estado.
 */
export function computeProgress(snapshot: DailySnapshot, prev: UserProgress): UserProgress {
  // XP e level
  const xpTotal = prev.xpTotal + snapshot.xpEarned
  const { level } = levelForXP(xpTotal)

  // Streak
  const yesterday = subDays(snapshot.date, 1)
  const continuesStreak =
    prev.lastActiveDate !== null && isSameDay(prev.lastActiveDate, yesterday)
  const currentStreak = continuesStreak ? prev.currentStreak + 1 : 1
  const longestStreak = Math.max(currentStreak, prev.longestStreak)

  // Bloco 7700: déficit acumulado dentro do bloco atual
  const newDeficit = Math.max(0, -snapshot.dailyBalance)
  const totalDeficit = prev.deficitBlock + newDeficit
  const blocksDelta = Math.floor(totalDeficit / KCAL_BLOCK)
  const blocksCompleted = prev.blocksCompleted + blocksDelta
  const deficitBlock = totalDeficit % KCAL_BLOCK

  // Badges
  const next: UserProgress = {
    xpTotal,
    level,
    currentStreak,
    longestStreak,
    blocksCompleted,
    deficitBlock,
    badgesEarned: [...prev.badgesEarned],
    lastActiveDate: snapshot.date,
  }

  for (const badge of BADGE_DEFINITIONS) {
    if (!next.badgesEarned.includes(badge.key) && badge.predicate(next, blocksDelta)) {
      next.badgesEarned.push(badge.key)
    }
  }

  return next
}
