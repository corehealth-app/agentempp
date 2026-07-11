import {
  normalizePendingFoodCorrections,
  type MealItem,
  type PendingFoodCorrection,
} from '@mpp/agent'

export interface ConfirmedMealProposal {
  mealType?: string
  items: MealItem[]
  corrections?: PendingFoodCorrection[]
}

export interface ConfirmedMealArgs {
  meal_type: string
  items: Array<{
    food_name: string
    quantity_g: number
    display_qty?: number | null
    display_unit?: string | null
    user_kcal?: number
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  replace: boolean
  consumed_date: string
  corrections?: PendingFoodCorrection[]
}

export function buildConfirmedMealArgs(
  proposal: ConfirmedMealProposal,
  effectiveReplace: boolean,
  sourceLocalDate: string,
): ConfirmedMealArgs {
  const corrections = normalizePendingFoodCorrections(proposal.corrections)
  return {
    meal_type: proposal.mealType ?? 'outro',
    items: proposal.items.map((item) => ({
      food_name: item.name,
      quantity_g: item.quantity_g,
      display_qty: item.display_qty,
      display_unit: item.display_unit,
      user_kcal: item.user_kcal ?? undefined,
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
    })),
    replace: effectiveReplace,
    consumed_date: sourceLocalDate,
    ...(corrections.length > 0 ? { corrections } : {}),
  }
}
