/**
 * Gamificação: XP, level, streak, blocos 7700, badges.
 * Replica a lógica do nó "Code Calcula Avanço" do n8n original.
 *
 * Todas as funções aceitam um CalcConfig opcional. Sem ele usa
 * DEFAULT_CALC_CONFIG.
 */
import type { DailySnapshot, UserProgress } from './types.js'
import {
  DEFAULT_CALC_CONFIG,
  type BadgeDef,
  type CalcConfig,
  type LevelDef,
} from './calc-config.js'

/** @deprecated use config.kcal_block */
export const KCAL_BLOCK = DEFAULT_CALC_CONFIG.kcal_block

/** @deprecated use config.levels */
export const LEVELS = DEFAULT_CALC_CONFIG.levels

export function levelForXP(
  xp: number,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): { level: number; name: string } {
  const levels = config.levels
  for (let i = levels.length - 1; i >= 0; i--) {
    const l = levels[i] as LevelDef | undefined
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

function badgeMatches(badge: BadgeDef, p: UserProgress): boolean {
  switch (badge.type) {
    case 'streak':
      return p.currentStreak >= badge.threshold
    case 'blocks':
      return p.blocksCompleted >= badge.threshold
    case 'xp':
      return p.xpTotal >= badge.threshold
    default:
      return false
  }
}

/**
 * Aplica um snapshot diário ao progresso anterior, retornando o próximo estado.
 */
export function computeProgress(
  snapshot: DailySnapshot,
  prev: UserProgress,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): UserProgress {
  // XP e level
  const xpTotal = prev.xpTotal + snapshot.xpEarned
  const { level } = levelForXP(xpTotal, config)

  // Streak
  const yesterday = subDays(snapshot.date, 1)
  const continuesStreak =
    prev.lastActiveDate !== null && isSameDay(prev.lastActiveDate, yesterday)
  const currentStreak = continuesStreak ? prev.currentStreak + 1 : 1
  const longestStreak = Math.max(currentStreak, prev.longestStreak)

  // Bloco 7700: déficit acumulado dentro do bloco atual
  const newDeficit = Math.max(0, -snapshot.dailyBalance)
  const totalDeficit = prev.deficitBlock + newDeficit
  const blocksDelta = Math.floor(totalDeficit / config.kcal_block)
  const blocksCompleted = prev.blocksCompleted + blocksDelta
  const deficitBlock = totalDeficit % config.kcal_block

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

  for (const badge of config.badges) {
    if (!next.badgesEarned.includes(badge.key) && badgeMatches(badge, next)) {
      next.badgesEarned.push(badge.key)
    }
  }

  return next
}

/**
 * Calcula XP a ser ganho num dia, dado se treinou e quanta proteína consumiu.
 * Antes era hardcoded `10 + (training ? 5 : 0) + (protein >= 100 ? 5 : 0)`.
 */
export function calcDailyXP(
  args: { trainingDone: boolean; proteinG: number },
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): number {
  const r = config.xp_rules
  return (
    r.base +
    (args.trainingDone ? r.training_bonus : 0) +
    (args.proteinG >= r.protein_threshold_g ? r.protein_bonus : 0)
  )
}
