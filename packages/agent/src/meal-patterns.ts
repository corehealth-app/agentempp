/**
 * Detecção de padrão de refeição do paciente.
 *
 * Roberto levantou (sessão 2026-05-16): paciente esquece de registrar jantar
 * e bloco 7700 credita falsamente como se ele tivesse comido pouco. Pra
 * resolver, precisamos saber QUAIS refeições são "esperadas" pra esse
 * paciente — alguns fazem jejum 16/8 e nunca tomam café, outros fazem 4x/dia.
 *
 * Política:
 *   - Janela: últimos 14 dias.
 *   - "Dia ativo" = dia com ≥1 meal_log registrado.
 *   - Refeição é "esperada" se aparece em ≥50% dos dias ativos.
 *   - Fallback (<5 dias ativos = paciente novo): assume café+almoço+jantar.
 */

import type { ServiceClient } from '@mpp/db'
import { getLocalDateString, getLocalDateMinusDays } from './timezone-utils.js'

export type MealType = 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'

export interface MealPattern {
  /** Set de meal_types esperados pra esse paciente, com frequência ≥ threshold. */
  expected: Set<MealType>
  /** Quantos dias ativos foram analisados (0-14). */
  activeDays: number
  /** Estatística por meal_type: # de dias que apareceu. */
  countByType: Record<MealType, number>
  /** Threshold usado (0-1). */
  threshold: number
  /** Se true, o expected vem do fallback (paciente novo). */
  fallbackUsed: boolean
}

const DEFAULT_THRESHOLD = 0.5
const MIN_ACTIVE_DAYS_FOR_PATTERN = 5
const FALLBACK_EXPECTED: Set<MealType> = new Set(['cafe', 'almoco', 'jantar'])

export async function getMealPattern(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  options: { thresholdPct?: number; windowDays?: number } = {},
): Promise<MealPattern> {
  const threshold = options.thresholdPct ?? DEFAULT_THRESHOLD
  const windowDays = options.windowDays ?? 14

  const startDate = getLocalDateMinusDays(userTimezone, windowDays)
  const endDate = getLocalDateMinusDays(userTimezone, 1) // ontem (não inclui hoje)

  // Busca via snapshot_id (snapshots têm date local correta) → meal_logs.
  const { data: snapshots } = await supabase
    .from('daily_snapshots')
    .select('id, date')
    .eq('user_id', userId)
    .gte('date', startDate)
    .lte('date', endDate)

  const snapIds = (snapshots ?? []).map((s) => (s as { id: string }).id)
  if (snapIds.length === 0) {
    return {
      expected: FALLBACK_EXPECTED,
      activeDays: 0,
      countByType: { cafe: 0, almoco: 0, lanche: 0, jantar: 0, ceia: 0 },
      threshold,
      fallbackUsed: true,
    }
  }

  const { data: logs } = await supabase
    .from('meal_logs')
    .select('snapshot_id, meal_type')
    .in('snapshot_id', snapIds)
    .not('meal_type', 'is', null)

  // Conta dias ativos (snapshots que TÊM ≥1 meal_log) e dias-com-meal-type
  const daysByMealType: Record<MealType, Set<string>> = {
    cafe: new Set(),
    almoco: new Set(),
    lanche: new Set(),
    jantar: new Set(),
    ceia: new Set(),
  }
  const activeDaysSet = new Set<string>()
  for (const log of (logs ?? []) as Array<{ snapshot_id: string; meal_type: string }>) {
    activeDaysSet.add(log.snapshot_id)
    const mt = log.meal_type as MealType
    if (mt in daysByMealType) {
      daysByMealType[mt].add(log.snapshot_id)
    }
  }

  const activeDays = activeDaysSet.size
  const countByType: Record<MealType, number> = {
    cafe: daysByMealType.cafe.size,
    almoco: daysByMealType.almoco.size,
    lanche: daysByMealType.lanche.size,
    jantar: daysByMealType.jantar.size,
    ceia: daysByMealType.ceia.size,
  }

  if (activeDays < MIN_ACTIVE_DAYS_FOR_PATTERN) {
    return {
      expected: FALLBACK_EXPECTED,
      activeDays,
      countByType,
      threshold,
      fallbackUsed: true,
    }
  }

  const expected = new Set<MealType>()
  for (const mt of Object.keys(countByType) as MealType[]) {
    if (countByType[mt] / activeDays >= threshold) {
      expected.add(mt)
    }
  }

  return { expected, activeDays, countByType, threshold, fallbackUsed: false }
}

/**
 * Identifica quais refeições esperadas ainda NÃO foram registradas hoje.
 * Usado pelo cron daily-gap-checker e pelo daily-closer.
 */
export async function getTodayGap(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  options: { thresholdPct?: number } = {},
): Promise<{
  pattern: MealPattern
  registeredToday: Set<MealType>
  skippedToday: Set<MealType>
  gap: Set<MealType>
}> {
  const pattern = await getMealPattern(supabase, userId, userTimezone, options)
  const today = getLocalDateString(userTimezone)

  // Snapshot de hoje (pode não existir ainda)
  const { data: snap } = await supabase
    .from('daily_snapshots')
    .select('id')
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()

  const snapId = (snap as { id: string } | null)?.id ?? null
  const registeredToday = new Set<MealType>()
  if (snapId) {
    const { data: logs } = await supabase
      .from('meal_logs')
      .select('meal_type')
      .eq('snapshot_id', snapId)
      .not('meal_type', 'is', null)
    for (const l of (logs ?? []) as Array<{ meal_type: string }>) {
      registeredToday.add(l.meal_type as MealType)
    }
  }

  // Refeições marcadas como "pulei" hoje (product_events meal.user_skipped)
  const startOfDay = `${today}T00:00:00`
  const { data: skipEvents } = await supabase
    .from('product_events')
    .select('properties')
    .eq('user_id', userId)
    .eq('event', 'meal.user_skipped')
    .gte('occurred_at', startOfDay)
  const skippedToday = new Set<MealType>()
  for (const e of (skipEvents ?? []) as Array<{ properties: Record<string, unknown> }>) {
    const mt = e.properties?.meal_type as MealType | undefined
    if (mt) skippedToday.add(mt)
  }

  // Gap = esperado MAS não registrado E não marcado como pulado
  const gap = new Set<MealType>()
  for (const mt of pattern.expected) {
    if (!registeredToday.has(mt) && !skippedToday.has(mt)) {
      gap.add(mt)
    }
  }

  return { pattern, registeredToday, skippedToday, gap }
}
