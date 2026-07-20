import {
  buildConfirmedMealArgs,
  type MealItem,
  type MealTotals,
  type RegistrationEntry,
} from '@mpp/agent'

export { buildConfirmedMealArgs }

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
