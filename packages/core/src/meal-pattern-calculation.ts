/** Pure extracted meal-pattern rules. Row selection, civil windows and errors
 * remain with each trusted reader; no database, cache, timezone or host clock. */
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

export function deriveMealPatternFromRows(
  snapshots: readonly { id: string }[],
  logs: readonly { snapshot_id: string; meal_type: string }[],
  options: { thresholdPct?: number } = {},
): MealPattern {
  const threshold = options.thresholdPct ?? DEFAULT_THRESHOLD
  if (snapshots.length === 0) {
    return {
      expected: new Set(FALLBACK_EXPECTED),
      activeDays: 0,
      countByType: { cafe: 0, almoco: 0, lanche: 0, jantar: 0, ceia: 0 },
      threshold,
      fallbackUsed: true,
    }
  }
  // Conta dias ativos (snapshots que TÊM ≥1 meal_log) e dias-com-meal-type
  const daysByMealType: Record<MealType, Set<string>> = {
    cafe: new Set(),
    almoco: new Set(),
    lanche: new Set(),
    jantar: new Set(),
    ceia: new Set(),
  }
  const activeDaysSet = new Set<string>()
  for (const log of logs) {
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
      expected: new Set(FALLBACK_EXPECTED),
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

/** Candidates were already selected by date or the historical civil interval. */
export function deriveSkippedMealsFromCandidates(
  dateStr: string,
  events: readonly { properties?: Record<string, unknown> | null }[],
): Set<MealType> {
  const skipped = new Set<MealType>()
  for (const event of events) {
    const eventLocalDate = event.properties?.local_date
    if (typeof eventLocalDate === 'string' && eventLocalDate !== dateStr) continue
    const mealType = event.properties?.meal_type
    if (typeof mealType === 'string' && MEAL_TYPES.has(mealType as MealType)) {
      skipped.add(mealType as MealType)
    }
  }
  return skipped
}

export function deriveMealGap(
  pattern: MealPattern,
  meals: readonly { meal_type: string }[],
  skipped: Set<MealType>,
) {
  const registered = new Set(meals.map((row) => row.meal_type as MealType))
  const gap = new Set<MealType>()
  for (const mt of pattern.expected) {
    if (!registered.has(mt) && !skipped.has(mt)) gap.add(mt)
  }
  return { pattern, registered, skipped, gap }
}
