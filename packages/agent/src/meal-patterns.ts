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

import {
  deriveMealGap,
  deriveMealPatternFromRows,
  deriveSkippedMealsFromCandidates,
  type MealPattern,
  type MealType,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import {
  getLocalDateMinusDays,
  getLocalDateString,
  getLocalDayUtcBounds,
} from './timezone-utils.js'

export type { MealPattern, MealType } from '@mpp/core'

export async function getMealPattern(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  options: { thresholdPct?: number; windowDays?: number } = {},
): Promise<MealPattern> {
  const windowDays = options.windowDays ?? 14

  const startDate = getLocalDateMinusDays(userTimezone, windowDays)
  const endDate = getLocalDateMinusDays(userTimezone, 1) // ontem (não inclui hoje)

  // Busca via snapshot_id (snapshots têm date local correta) → meal_logs.
  const { data: snapshots, error: snapshotsError } = await supabase
    .from('daily_snapshots')
    .select('id, date')
    .eq('user_id', userId)
    .gte('date', startDate)
    .lte('date', endDate)
  if (snapshotsError) throw new Error(snapshotsError.message ?? 'meal pattern snapshots failed')

  const snapIds = (snapshots ?? []).map((s) => (s as { id: string }).id)
  if (snapIds.length === 0) return deriveMealPatternFromRows([], [], options)

  const { data: logs, error: logsError } = await supabase
    .from('meal_logs')
    .select('snapshot_id, meal_type')
    .in('snapshot_id', snapIds)
    .not('meal_type', 'is', null)
  if (logsError) throw new Error(logsError.message ?? 'meal pattern logs failed')

  return deriveMealPatternFromRows(
    (snapshots ?? []) as Array<{ id: string }>,
    (logs ?? []) as Array<{ snapshot_id: string; meal_type: string }>,
    options,
  )
}

/** Carrega confirmações explícitas de refeições puladas em uma data local. */
export async function getSkippedMealsForDate(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  dateStr: string,
): Promise<Set<MealType>> {
  // A segunda consulta preserva eventos legados sem `properties.local_date`.
  const { startIso, endExclusiveIso } = getLocalDayUtcBounds(userTimezone, dateStr)
  const [datedSkipResult, legacySkipResult] = await Promise.all([
    supabase
      .from('product_events')
      .select('properties')
      .eq('user_id', userId)
      .eq('event', 'meal.user_skipped')
      .filter('properties->>local_date', 'eq', dateStr),
    supabase
      .from('product_events')
      .select('properties')
      .eq('user_id', userId)
      .eq('event', 'meal.user_skipped')
      .gte('occurred_at', startIso)
      .lt('occurred_at', endExclusiveIso),
  ])
  if (datedSkipResult.error || legacySkipResult.error) {
    throw new Error(
      datedSkipResult.error?.message ??
        legacySkipResult.error?.message ??
        'skip events lookup failed',
    )
  }

  return deriveSkippedMealsFromCandidates(dateStr, [
    ...(datedSkipResult.data ?? []),
    ...(legacySkipResult.data ?? []),
  ] as Array<{ properties: Record<string, unknown> }>)
}

/**
 * Identifica quais refeições esperadas ainda NÃO foram registradas em UMA
 * DATA específica (formato YYYY-MM-DD em fuso local).
 *
 * BUG histórico (Roberto+Paulo+Luciana 2026-05-17): daily-closer chamava
 * getTodayGap() durante o fechamento de "ontem", mas getTodayGap retornava
 * gap de HOJE (dia em curso). Resultado: snapshots de ontem marcados como
 * incomplete_no_response com gap do dia novo (que mal começou) → blocos
 * 7700 NÃO creditados injustamente. Roberto 16/05 e 17/05 marcados errado.
 *
 * Fix: parametrizar a data. daily-closer passa `yesterday`, daily-gap-checker
 * passa `today` (via wrapper getTodayGap abaixo).
 */
export async function getGapForDate(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  dateStr: string,
  options: { thresholdPct?: number } = {},
): Promise<{
  pattern: MealPattern
  registered: Set<MealType>
  skipped: Set<MealType>
  gap: Set<MealType>
}> {
  const pattern = await getMealPattern(supabase, userId, userTimezone, options)

  // Snapshot da data (pode não existir)
  const { data: snap, error: snapError } = await supabase
    .from('daily_snapshots')
    .select('id')
    .eq('user_id', userId)
    .eq('date', dateStr)
    .maybeSingle()
  if (snapError) throw new Error(snapError.message ?? 'gap snapshot lookup failed')

  const snapId = (snap as { id: string } | null)?.id ?? null
  let registeredMeals: Array<{ meal_type: string }> = []
  if (snapId) {
    const { data: logs, error: logsError } = await supabase
      .from('meal_logs')
      .select('meal_type')
      .eq('snapshot_id', snapId)
      .not('meal_type', 'is', null)
    if (logsError) throw new Error(logsError.message ?? 'gap meal logs lookup failed')
    registeredMeals = (logs ?? []) as Array<{ meal_type: string }>
  }

  const skipped = await getSkippedMealsForDate(supabase, userId, userTimezone, dateStr)

  return deriveMealGap(pattern, registeredMeals, skipped)
}

/**
 * Wrapper: gap de HOJE (usado pelo daily-gap-checker pra detectar enquanto
 * paciente ainda pode registrar).
 */
export async function getTodayGap(
  supabase: ServiceClient,
  userId: string,
  userTimezone: string,
  options: { thresholdPct?: number } = {},
): Promise<{
  pattern: MealPattern
  registered: Set<MealType>
  skipped: Set<MealType>
  gap: Set<MealType>
}> {
  return getGapForDate(supabase, userId, userTimezone, getLocalDateString(userTimezone), options)
}
