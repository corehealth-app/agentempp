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
 * Calcula XP a ser ganho num dia, conforme tabela MPP oficial (doc Notion).
 * Cada ação granular vale uma quantia específica:
 *   - registrar peso (+weight_xp)
 *   - cada refeição registrada (×meal_xp)
 *   - enviar foto (+photo_xp)
 *   - bater meta proteína (+protein_meta_xp)
 *   - bater meta calorias (+calories_meta_xp)
 *   - completar treino (+training_xp)
 *   - dia perfeito (+perfect_day_xp) — quando bate proteína E calorias E treino E peso
 *
 * NÃO contabiliza ainda (precisa expansão de tracking):
 *   steps_meta_xp, water_meta_xp, sleep_meta_xp, persistence_xp
 *
 * Compat: se a tabela MPP não estiver populada, cai pro legacy
 * `base + training_bonus + protein_bonus`.
 */
export function calcDailyXP(
  args: {
    trainingDone: boolean
    proteinG: number
    /** kcal_consumido / kcal_target — bate se está na janela MPP (90-105%) */
    caloriesConsumed?: number
    caloriesTarget?: number
    proteinTarget?: number
    /** quantas refeições foram registradas no dia */
    mealsLogged?: number
    /** se enviou foto corporal hoje */
    photoLogged?: boolean
    /** se registrou peso hoje */
    weightLogged?: boolean
  },
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): number {
  const r = config.xp_rules
  // Detecta tabela MPP populada
  const useMPPTable = r.meal_xp != null || r.calories_meta_xp != null
  if (!useMPPTable) {
    // Legacy: 10 + 5 (treino) + 5 (prot >= threshold)
    return (
      r.base +
      (args.trainingDone ? r.training_bonus : 0) +
      (args.proteinG >= r.protein_threshold_g ? r.protein_bonus : 0)
    )
  }
  let xp = 0
  if (args.weightLogged) xp += r.weight_xp ?? 0
  if (args.mealsLogged && args.mealsLogged > 0) xp += (r.meal_xp ?? 0) * args.mealsLogged
  if (args.photoLogged) xp += r.photo_xp ?? 0
  // Meta proteína: ≥ proteinTarget OU fallback ao threshold legacy
  const proteinMet =
    args.proteinTarget != null
      ? args.proteinG >= args.proteinTarget
      : args.proteinG >= r.protein_threshold_g
  if (proteinMet) xp += r.protein_meta_xp ?? 0
  // Meta calórica: dentro da janela MPP 90%-105% do target
  if (args.caloriesConsumed != null && args.caloriesTarget && args.caloriesTarget > 0) {
    const ratio = args.caloriesConsumed / args.caloriesTarget
    if (ratio >= 0.9 && ratio <= 1.05) xp += r.calories_meta_xp ?? 0
  }
  if (args.trainingDone) xp += r.training_xp ?? 0
  // Dia perfeito: peso + ≥3 refeições + foto + proteína + calorias + treino
  const perfect =
    !!args.weightLogged &&
    (args.mealsLogged ?? 0) >= 3 &&
    !!args.photoLogged &&
    proteinMet &&
    args.caloriesConsumed != null &&
    args.caloriesTarget != null &&
    args.caloriesTarget > 0 &&
    args.caloriesConsumed / args.caloriesTarget >= 0.9 &&
    args.caloriesConsumed / args.caloriesTarget <= 1.05 &&
    args.trainingDone
  if (perfect) xp += r.perfect_day_xp ?? 0
  return xp
}
