export interface DedupableMealItem {
  food_name: string
  quantity_g: number
  user_kcal?: number | null
  approved_nutrition?: {
    food_db_id?: number | null
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }
}

export interface MealItemDuplicate {
  food_name: string
  repeated: number
  result_g: number
  strategy: 'collapsed_identical' | 'summed_distinct_quantities'
}

export interface MealItemDedupOptions {
  patientText?: string
}

function normalizeFoodName(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function sumApprovedNutrition(items: DedupableMealItem[]) {
  const approved = items.map((item) => item.approved_nutrition)
  if (approved.some((nutrition) => nutrition == null)) return undefined
  const values = approved.filter(
    (nutrition): nutrition is NonNullable<DedupableMealItem['approved_nutrition']> =>
      nutrition != null,
  )
  const foodDbIds = new Set(values.map((nutrition) => nutrition.food_db_id ?? null))
  return {
    food_db_id: foodDbIds.size === 1 ? (values[0]?.food_db_id ?? null) : null,
    kcal: values.reduce((sum, nutrition) => sum + nutrition.kcal, 0),
    protein_g: values.reduce((sum, nutrition) => sum + nutrition.protein_g, 0),
    carbs_g: values.reduce((sum, nutrition) => sum + nutrition.carbs_g, 0),
    fat_g: values.reduce((sum, nutrition) => sum + nutrition.fat_g, 0),
  }
}

const COUNT_WORDS: Record<string, number> = {
  dois: 2,
  duas: 2,
  tres: 3,
  quatro: 4,
  cinco: 5,
  seis: 6,
  sete: 7,
  oito: 8,
  nove: 9,
  dez: 10,
}

function singularToken(token: string): string {
  return token.length > 3 && token.endsWith('s') ? token.slice(0, -1) : token
}

function hasExplicitMultiplicity(
  patientText: string | undefined,
  foodName: string,
  repeated: number,
): boolean {
  if (!patientText || repeated < 2) return false
  const text = normalizeFoodName(patientText)
  const foodTokens = new Set(
    normalizeFoodName(foodName)
      .split(' ')
      .filter((token) => token.length >= 3)
      .map(singularToken),
  )
  if (foodTokens.size === 0) return false

  const countPattern = /\b(\d{1,2}|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez)\b/g
  for (const match of text.matchAll(countPattern)) {
    const count = /^\d+$/.test(match[1] ?? '')
      ? Number(match[1])
      : (COUNT_WORDS[match[1] ?? ''] ?? 0)
    if (count < repeated || match.index == null) continue
    const followingTokens = text
      .slice(match.index + match[0].length)
      .split(' ')
      .filter(Boolean)
      .slice(0, 6)
      .map(singularToken)
    if (followingTokens.some((token) => foodTokens.has(token))) return true
  }

  const pairedPortionPattern =
    /\b(?:um|uma)\b([^.!?]{0,80})\b(?:e\s+)?(?:(?:mais|depois|ai|tambem)\s+){0,3}(?:um|uma|outro|outra)\b/g
  for (const match of text.matchAll(pairedPortionPattern)) {
    const middleTokens = (match[1] ?? '').split(' ').filter(Boolean).map(singularToken)
    if (middleTokens.some((token) => foodTokens.has(token))) return true
  }
  return false
}

function nutritionSignature(item: DedupableMealItem): string {
  const nutrition = item.approved_nutrition
  return JSON.stringify({
    user_kcal: item.user_kcal ?? null,
    approved_nutrition: nutrition
      ? {
          food_db_id: nutrition.food_db_id ?? null,
          kcal: nutrition.kcal,
          protein_g: nutrition.protein_g,
          carbs_g: nutrition.carbs_g,
          fat_g: nutrition.fat_g,
        }
      : null,
  })
}

export function dedupeMealItems<T extends DedupableMealItem>(
  items: T[],
  options: MealItemDedupOptions = {},
): {
  items: T[]
  duplicates: MealItemDuplicate[]
} {
  const groups = new Map<
    string,
    { first: T; originalCount: number; quantities: Map<string, T>; all: T[] }
  >()

  for (const item of items) {
    const key = normalizeFoodName(item.food_name)
    const quantityKey = Number(item.quantity_g).toFixed(3)
    const existing = groups.get(key)
    if (existing) {
      existing.originalCount += 1
      existing.all.push(item)
      if (!existing.quantities.has(quantityKey)) existing.quantities.set(quantityKey, item)
      continue
    }
    groups.set(key, {
      first: item,
      originalCount: 1,
      quantities: new Map([[quantityKey, item]]),
      all: [item],
    })
  }

  const deduped: T[] = []
  const duplicates: MealItemDuplicate[] = []
  for (const group of groups.values()) {
    const uniqueItems = [...group.quantities.values()]
    if (
      uniqueItems.length === 1 &&
      group.originalCount > 1 &&
      hasExplicitMultiplicity(options.patientText, group.first.food_name, group.originalCount)
    ) {
      throw new Error(
        `multiplicidade explícita ambígua para ${group.first.food_name}; informe uma única linha com a quantidade total`,
      )
    }
    if (uniqueItems.length === 1 && group.originalCount > 1) {
      const nutritionSignatures = new Set(group.all.map(nutritionSignature))
      if (nutritionSignatures.size > 1) {
        throw new Error(`conflito nutricional entre cópias de ${group.first.food_name}`)
      }
    }
    const itemsToMerge = uniqueItems
    const quantityG = itemsToMerge.reduce((sum, item) => sum + item.quantity_g, 0)
    const strategy = uniqueItems.length === 1 ? 'collapsed_identical' : 'summed_distinct_quantities'

    let merged: T = group.first
    if (itemsToMerge.length > 1) {
      const userKcalValues = itemsToMerge.map((item) => item.user_kcal)
      const hasCompleteUserKcal = userKcalValues.every(
        (value): value is number => typeof value === 'number' && Number.isFinite(value),
      )
      const approvedNutrition = sumApprovedNutrition(itemsToMerge)
      merged = {
        ...group.first,
        quantity_g: quantityG,
        ...(hasCompleteUserKcal
          ? { user_kcal: userKcalValues.reduce((sum, value) => sum + value, 0) }
          : { user_kcal: undefined }),
        approved_nutrition: approvedNutrition,
      }
    }
    deduped.push(merged)

    if (group.originalCount > 1) {
      duplicates.push({
        food_name: group.first.food_name,
        repeated: group.originalCount,
        result_g: quantityG,
        strategy,
      })
    }
  }

  return { items: deduped, duplicates }
}
