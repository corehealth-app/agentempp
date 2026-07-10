export interface MealRegistrationRow {
  id: string
  food_name: string
  kcal: number | string
  consumed_at: string
  raw_provider_message_id?: string | null
}

export interface MealRegistrationGroup {
  key: string
  rows: MealRegistrationRow[]
}

export type MealRegistrationSelection =
  | { status: 'selected'; key: string; rows: MealRegistrationRow[] }
  | { status: 'not_found' }
  | { status: 'ambiguous'; groups: MealRegistrationGroup[] }

function normalize(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
}

function groupRows(rows: MealRegistrationRow[]): MealRegistrationGroup[] {
  const grouped = new Map<string, MealRegistrationRow[]>()
  for (const row of rows) {
    const key = row.raw_provider_message_id
      ? `provider:${row.raw_provider_message_id}`
      : `time:${row.consumed_at}`
    const group = grouped.get(key) ?? []
    group.push(row)
    grouped.set(key, group)
  }
  return Array.from(grouped, ([key, groupRows]) => ({ key, rows: groupRows }))
}

/** Um hint identifica o grupo; a atualizacao sempre inclui todos os seus itens. */
export function selectMealRegistrationGroup(
  rows: MealRegistrationRow[],
  foodHint?: string | null,
): MealRegistrationSelection {
  const groups = groupRows(rows)
  const normalizedHint = normalize(foodHint ?? '')
  const candidates = normalizedHint
    ? groups.filter((group) =>
        group.rows.some((row) => normalize(row.food_name).includes(normalizedHint)),
      )
    : groups

  if (candidates.length === 0) return { status: 'not_found' }
  if (candidates.length > 1) return { status: 'ambiguous', groups: candidates }
  const selected = candidates[0]!
  return { status: 'selected', key: selected.key, rows: selected.rows }
}
