export interface ReplacementMealLog {
  id: string
  food_name: string
  meal_type: string
  consumed_at: string
  raw_provider_message_id?: string | null
  kcal?: number | string | null
}

export interface ReplacementCorrection {
  de?: string | null
  para?: string | null
}

export type MealReplacementTarget =
  | {
      status: 'selected'
      logIds: string[]
      rows: ReplacementMealLog[]
      registrationRows: ReplacementMealLog[]
      mealType: string
      groupKey: string
      overlapRatio: number
    }
  | { status: 'not_found'; overlapRatio: 0 }
  | { status: 'ambiguous'; overlapRatio: number; groupKeys: string[] }

const FOOD_QUALIFIERS = new Set([
  'assada',
  'assado',
  'cozida',
  'cozido',
  'com',
  'desnatada',
  'desnatado',
  'frita',
  'frito',
  'grelhada',
  'grelhado',
  'integral',
  'gordura',
  'pele',
  'semi',
  'sem',
])

function normalize(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function foodTokens(value: string): string[] {
  return normalize(value)
    .split(/\s+/)
    .map((token) => (token.length >= 4 && token.endsWith('s') ? token.slice(0, -1) : token))
    .filter((token) => token.length >= 3 && !FOOD_QUALIFIERS.has(token))
}

export function foodNamesReferToSameItem(left: string, right: string): boolean {
  return foodNameMatchScore(left, right) > 0
}

function foodNameMatchScore(left: string, right: string): number {
  const a = normalize(left)
  const b = normalize(right)
  if (!a || !b) return 0
  if (a === b) return 1
  if (a.includes(b) || b.includes(a)) return 0.95
  const aTokens = foodTokens(a)
  const bTokens = foodTokens(b)
  if (aTokens.length === 0 || bTokens.length === 0) return 0
  const bSet = new Set(bTokens)
  const intersection = new Set(aTokens.filter((token) => bSet.has(token))).size
  const ratio = intersection / Math.max(new Set(aTokens).size, new Set(bTokens).size)
  return ratio >= 2 / 3 ? Math.round(ratio * 80) / 100 : 0
}

function registrationKey(row: ReplacementMealLog): string {
  return row.raw_provider_message_id
    ? `provider:${row.raw_provider_message_id}`
    : `time:${row.consumed_at}`
}

export function selectMealReplacementTarget(input: {
  recentLogs: ReplacementMealLog[]
  newFoodNames: string[]
  corrections?: ReplacementCorrection[] | null
}): MealReplacementTarget {
  const correctionHints = (input.corrections ?? [])
    .map((correction) => correction.de?.trim() ?? '')
    .filter(Boolean)
  const hints = correctionHints.length > 0 ? correctionHints : input.newFoodNames.filter(Boolean)
  if (hints.length === 0 || input.recentLogs.length === 0) {
    return { status: 'not_found', overlapRatio: 0 }
  }

  const groups = new Map<string, ReplacementMealLog[]>()
  for (const row of input.recentLogs) {
    if (!row.id) continue
    const key = registrationKey(row)
    const current = groups.get(key) ?? []
    current.push(row)
    groups.set(key, current)
  }

  const candidates = Array.from(groups, ([groupKey, rows]) => {
    const hintMatches = hints.map((hint) => {
      const scored = rows
        .map((row) => ({ row, score: foodNameMatchScore(hint, row.food_name) }))
        .filter((candidate) => candidate.score > 0)
      const bestScore = Math.max(0, ...scored.map((candidate) => candidate.score))
      const bestRows = scored
        .filter((candidate) => candidate.score === bestScore)
        .map((candidate) => candidate.row)
      return { bestScore, bestRows }
    })
    const matchedHints = hintMatches.filter((match) => match.bestRows.length > 0)
    const matchedRows = Array.from(
      new Map(matchedHints.flatMap((match) => match.bestRows).map((row) => [row.id, row])).values(),
    )
    const overlapRatio = matchedHints.length / hints.length
    const matchScore =
      matchedHints.length > 0
        ? matchedHints.reduce((sum, match) => sum + match.bestScore, 0) / matchedHints.length
        : 0
    const ambiguousWithinGroup = matchedHints.some((match) => match.bestRows.length > 1)
    const timestamp = Math.max(...rows.map((row) => Date.parse(row.consumed_at) || 0))
    return {
      groupKey,
      rows: matchedRows,
      registrationRows: rows,
      overlapRatio,
      matchScore,
      ambiguousWithinGroup,
      timestamp,
    }
  })
    .filter((candidate) => candidate.overlapRatio >= 0.5 && candidate.rows.length > 0)
    .sort(
      (a, b) =>
        b.overlapRatio - a.overlapRatio || b.matchScore - a.matchScore || b.timestamp - a.timestamp,
    )

  const selected = candidates[0]
  if (!selected) return { status: 'not_found', overlapRatio: 0 }
  if (selected.ambiguousWithinGroup) {
    return {
      status: 'ambiguous',
      overlapRatio: selected.overlapRatio,
      groupKeys: [selected.groupKey],
    }
  }
  const equallyLikely = candidates.filter(
    (candidate) =>
      candidate.groupKey !== selected.groupKey &&
      candidate.overlapRatio === selected.overlapRatio &&
      candidate.matchScore === selected.matchScore &&
      candidate.timestamp === selected.timestamp,
  )
  if (equallyLikely.length > 0) {
    return {
      status: 'ambiguous',
      overlapRatio: selected.overlapRatio,
      groupKeys: [selected.groupKey, ...equallyLikely.map((candidate) => candidate.groupKey)],
    }
  }

  return {
    status: 'selected',
    logIds: [...new Set(selected.rows.map((row) => row.id))],
    rows: selected.rows,
    registrationRows: selected.registrationRows,
    mealType: selected.rows[0]?.meal_type ?? 'outro',
    groupKey: selected.groupKey,
    overlapRatio: Math.round(selected.overlapRatio * 100) / 100,
  }
}

export function hasExplicitWholeMealReplacementIntent(messages: string[]): boolean {
  const text = normalize(messages.join(' '))
  const action = '(?:corrig|substitu|troc|refa|reformul)'
  const whole = '(?:tod[oa]|inteir[oa]|complet[oa])'
  const meal = '(?:cafe|almoco|lanche|jantar|ceia|refeicao)'
  const wholeMeal = String.raw`(?:${meal}\s+${whole}|${whole}\s+(?:o\s+|a\s+)?${meal})`
  return (
    new RegExp(`\\b${action}\\w*\\b.{0,60}\\b${wholeMeal}\\b`).test(text) ||
    new RegExp(`\\b${wholeMeal}\\b.{0,60}\\b${action}\\w*\\b`).test(text)
  )
}
