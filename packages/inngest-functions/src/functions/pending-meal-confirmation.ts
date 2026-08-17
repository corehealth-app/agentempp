import {
  type MealItem,
  type MealTotals,
  normalizePendingFoodCorrections,
  type PendingFoodCorrection,
  type RegistrationEntry,
} from '@mpp/agent'

export interface ConfirmedMealProposal {
  mealType?: string
  items: MealItem[]
  writeItems?: MealItem[]
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
      source?: string | null
      food_db_id?: number | null
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

interface ConfirmedMealRegistrationProposal {
  mealType?: string
  items?: MealItem[]
  writeItems?: MealItem[]
  totals?: MealTotals
}

interface ConfirmedMealResult {
  already_logged?: boolean
  meal?: { items?: MealItem[]; totals?: MealTotals }
}

interface EffectiveReplaceGuardInput {
  effectiveReplace: boolean
  hasPriorMealOfSameType: boolean
  hasPriorEditedPending: boolean
  inferredReplace: boolean
  replaceEvidence?: string | null
}

function normalizeFoodName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

export function selectValidatedWriteItems(
  writeItems: MealItem[] | undefined,
  validItems: MealItem[],
): MealItem[] | null | undefined {
  if (writeItems == null) return undefined
  if (writeItems.length === 0) return null

  const selected: MealItem[] = []
  for (const writeItem of writeItems) {
    const matches = validItems.filter(
      (validItem) =>
        normalizeFoodName(validItem.name) === normalizeFoodName(writeItem.name) &&
        Math.abs(Number(validItem.quantity_g) - Number(writeItem.quantity_g)) <= 0.01,
    )
    const match = matches[0]
    if (matches.length !== 1 || match === undefined || selected.includes(match)) return null
    selected.push(match)
  }
  return selected
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
  const writeItems = proposal.writeItems ?? proposal.items
  return {
    meal_type: proposal.mealType ?? 'outro',
    items: writeItems.map((item) => ({
      food_name: item.name,
      quantity_g: item.quantity_g,
      display_qty: item.display_qty,
      display_unit: item.display_unit,
      user_kcal: item.user_kcal ?? undefined,
      approved_nutrition: {
        source: item.nutrition_source ?? null,
        food_db_id: item.food_db_id ?? null,
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

export function buildConfirmedMealRegistrationEntry(
  proposal: ConfirmedMealRegistrationProposal,
  result: ConfirmedMealResult | null,
): RegistrationEntry {
  const itemScopedPatch = (proposal.writeItems?.length ?? 0) > 0
  return {
    tool: 'registra_refeicao',
    mealType: proposal.mealType ?? 'outro',
    items: itemScopedPatch ? (proposal.items ?? []) : (result?.meal?.items ?? proposal.items ?? []),
    totals: itemScopedPatch
      ? (proposal.totals ?? { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 })
      : (result?.meal?.totals ??
        proposal.totals ?? { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 }),
    alreadyLogged: result?.already_logged === true,
  }
}
