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
import {
  getLocalDateMinusDays,
  getLocalDateString,
  getLocalDayUtcBounds,
} from './timezone-utils.js'

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
const MEAL_TYPES = new Set<MealType>(['cafe', 'almoco', 'lanche', 'jantar', 'ceia'])

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
  const { data: snapshots, error: snapshotsError } = await supabase
    .from('daily_snapshots')
    .select('id, date')
    .eq('user_id', userId)
    .gte('date', startDate)
    .lte('date', endDate)
  if (snapshotsError) throw new Error(snapshotsError.message ?? 'meal pattern snapshots failed')

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

  const { data: logs, error: logsError } = await supabase
    .from('meal_logs')
    .select('snapshot_id, meal_type')
    .in('snapshot_id', snapIds)
    .not('meal_type', 'is', null)
  if (logsError) throw new Error(logsError.message ?? 'meal pattern logs failed')

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

  const skipped = new Set<MealType>()
  const skipEvents = [...(datedSkipResult.data ?? []), ...(legacySkipResult.data ?? [])]
  for (const event of skipEvents as Array<{ properties: Record<string, unknown> }>) {
    const eventLocalDate = event.properties?.local_date
    if (typeof eventLocalDate === 'string' && eventLocalDate !== dateStr) continue
    const mealType = event.properties?.meal_type
    if (typeof mealType === 'string' && MEAL_TYPES.has(mealType as MealType)) {
      skipped.add(mealType as MealType)
    }
  }
  return skipped
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
  const registered = new Set<MealType>()
  if (snapId) {
    const { data: logs, error: logsError } = await supabase
      .from('meal_logs')
      .select('meal_type')
      .eq('snapshot_id', snapId)
      .not('meal_type', 'is', null)
    if (logsError) throw new Error(logsError.message ?? 'gap meal logs lookup failed')
    for (const l of (logs ?? []) as Array<{ meal_type: string }>) {
      registered.add(l.meal_type as MealType)
    }
  }

  const skipped = await getSkippedMealsForDate(supabase, userId, userTimezone, dateStr)

  const gap = new Set<MealType>()
  for (const mt of pattern.expected) {
    if (!registered.has(mt) && !skipped.has(mt)) {
      gap.add(mt)
    }
  }

  return { pattern, registered, skipped, gap }
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
