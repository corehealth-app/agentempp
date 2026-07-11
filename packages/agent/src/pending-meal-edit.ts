import type { MealItem, MealTotals } from './post-registration-message.js'

export interface PendingMealEditAdjustment {
  food_name: string
  previous_quantity_g: number
  quantity_g: number
  previous_kcal: number
  kcal: number
  reason: 'quantity_scaled'
}

function normalizeFoodName(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals
  return Math.round((value + Number.EPSILON) * factor) / factor
}

function totalsFor(items: MealItem[]): MealTotals {
  const totals = items.reduce(
    (acc, item) => ({
      kcal: acc.kcal + Number(item.kcal),
      protein_g: acc.protein_g + Number(item.protein_g),
      carbs_g: acc.carbs_g + Number(item.carbs_g),
      fat_g: acc.fat_g + Number(item.fat_g),
    }),
    { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
  )
  return {
    kcal: round(totals.kcal, 1),
    protein_g: round(totals.protein_g, 2),
    carbs_g: round(totals.carbs_g, 2),
    fat_g: round(totals.fat_g, 2),
  }
}

/**
 * Keeps the nutrition density that was shown in the previous pending when the
 * patient edits only quantity. Identity/preparation edits use the fresh
 * deterministic resolution. A new explicit calorie statement always wins.
 */
export function reconcilePendingMealEdit(input: {
  previousItems: MealItem[]
  resolvedItems: MealItem[]
  currentExplicitKcalFoods: ReadonlySet<string>
}): { items: MealItem[]; totals: MealTotals; adjustments: PendingMealEditAdjustment[] } {
  const previousByName = new Map(
    input.previousItems.map((item) => [normalizeFoodName(item.name), item]),
  )
  const explicitNames = new Set(
    [...input.currentExplicitKcalFoods].map(normalizeFoodName),
  )
  const adjustments: PendingMealEditAdjustment[] = []

  const items = input.resolvedItems.map((resolved) => {
    const normalizedName = normalizeFoodName(resolved.name)
    const previous = previousByName.get(normalizedName)
    if (
      !previous ||
      explicitNames.has(normalizedName) ||
      !Number.isFinite(previous.quantity_g) ||
      previous.quantity_g <= 0 ||
      !Number.isFinite(resolved.quantity_g) ||
      resolved.quantity_g <= 0
    ) {
      return resolved
    }

    const ratio = resolved.quantity_g / previous.quantity_g
    const reconciled: MealItem = {
      ...resolved,
      kcal: round(previous.kcal * ratio, 1),
      protein_g: round(previous.protein_g * ratio, 2),
      carbs_g: round(previous.carbs_g * ratio, 2),
      fat_g: round(previous.fat_g * ratio, 2),
      ...(previous.user_kcal != null
        ? { user_kcal: round(previous.user_kcal * ratio, 1) }
        : { user_kcal: null }),
    }

    if (Math.abs(resolved.quantity_g - previous.quantity_g) > 0.001) {
      adjustments.push({
        food_name: resolved.name,
        previous_quantity_g: previous.quantity_g,
        quantity_g: resolved.quantity_g,
        previous_kcal: previous.kcal,
        kcal: reconciled.kcal,
        reason: 'quantity_scaled',
      })
    }
    return reconciled
  })

  return { items, totals: totalsFor(items), adjustments }
}
