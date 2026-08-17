export interface FoodDbGapLog {
  food_name: string
  kcal: number | null
  quantity_g: number | null
  user_id: string
}

export interface FoodDbGapRow {
  food_name: string
  logs: number
  patients: number
  avg_kcal_per_100g: number
}

export interface FoodDbGapSummary {
  total_logs: number
  fallback_logs: number
  fallback_pct: number
}

export function normalizeFoodName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

export function aggregateFoodDbGaps(
  logs: FoodDbGapLog[],
  knownFoodNames: Array<string | null>,
  limit = 15,
): { gaps: FoodDbGapRow[]; summary: FoodDbGapSummary } {
  const knownNames = new Set(
    knownFoodNames.map((name) => normalizeFoodName(name ?? '')).filter(Boolean),
  )
  const byName = new Map<
    string,
    {
      displayName: string
      logs: number
      patients: Set<string>
      kcalPer100gSum: number
      kcalCount: number
    }
  >()
  let fallbackLogs = 0

  for (const row of logs) {
    const key = normalizeFoodName(row.food_name)
    if (knownNames.has(key)) continue
    fallbackLogs++
    if (!key) continue

    const entry = byName.get(key) ?? {
      displayName: row.food_name.trim(),
      logs: 0,
      patients: new Set<string>(),
      kcalPer100gSum: 0,
      kcalCount: 0,
    }
    entry.logs++
    entry.patients.add(row.user_id)

    const kcal = Number(row.kcal)
    const quantityG = Number(row.quantity_g)
    if (Number.isFinite(kcal) && kcal > 0 && Number.isFinite(quantityG) && quantityG > 0) {
      entry.kcalPer100gSum += (kcal / quantityG) * 100
      entry.kcalCount++
    }
    byName.set(key, entry)
  }

  const gaps = Array.from(byName.values())
    .map((entry) => ({
      food_name: entry.displayName,
      logs: entry.logs,
      patients: entry.patients.size,
      avg_kcal_per_100g:
        entry.kcalCount > 0 ? Number((entry.kcalPer100gSum / entry.kcalCount).toFixed(1)) : 0,
    }))
    .sort(
      (a, b) =>
        b.logs - a.logs || b.patients - a.patients || a.food_name.localeCompare(b.food_name),
    )
    .slice(0, Math.max(0, limit))

  const totalLogs = logs.length
  return {
    gaps,
    summary: {
      total_logs: totalLogs,
      fallback_logs: fallbackLogs,
      fallback_pct: totalLogs > 0 ? Math.round((fallbackLogs / totalLogs) * 100) : 0,
    },
  }
}

export async function collectPages<T>(
  loadPage: (from: number, to: number) => Promise<T[]>,
  pageSize = 1_000,
): Promise<T[]> {
  if (!Number.isInteger(pageSize) || pageSize <= 0) {
    throw new Error('pageSize must be a positive integer')
  }

  const rows: T[] = []
  for (let from = 0; ; from += pageSize) {
    const page = await loadPage(from, from + pageSize - 1)
    rows.push(...page)
    if (page.length < pageSize) return rows
  }
}
