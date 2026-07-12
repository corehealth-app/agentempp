import {
  type MealItem,
  normalizePendingFoodCorrections,
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
    approved_nutrition: {
      kcal: number
      protein_g: number
      carbs_g: number
      fat_g: number
    }
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  replace: boolean
  consumed_date: string
  corrections?: PendingFoodCorrection[]
}

interface EffectiveReplaceGuardInput {
  effectiveReplace: boolean
  hasPriorMealOfSameType: boolean
  hasPriorEditedPending: boolean
  inferredReplace: boolean
  replaceEvidence?: string | null
}

export function shouldBlockEffectiveReplace(input: EffectiveReplaceGuardInput): boolean {
  if (!input.effectiveReplace) return false
  if (!input.hasPriorMealOfSameType || !input.hasPriorEditedPending) return false
  if (input.inferredReplace) return false

  // This evidence is created only after the cancelled->pending CAS succeeds.
  // The old rows must remain until register_meal_atomic replaces them.
  return input.replaceEvidence !== 'lossy_cancellation_recovery'
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
      approved_nutrition: {
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
      },
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
