/**
 * App-only household reference, requested by Eduardo on 2026-10-22.
 * These are editable assumptions, not the weight of every caneca/dosador.
 * Milk uses FAO/INFOODS v2 whole liquid milk(TB),1.03g/mL; https://www.fao.org/4/ap815e/ap815e.pdf
 * No legacy/Flow engine entry point invokes this resolver.
 */
export type HouseholdQuantityBasis = 'stated' | 'visual_estimate' | 'portion_reference'

export interface HouseholdDrinkPart {
  food_name: string
  quantity_g: number
  quantity_basis: HouseholdQuantityBasis
}

function normalizeDrinkName(name: string): string {
  return name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/[.!]$/, '')
}

/**29Oct compact proposal: its quantity is the beverage TOTAL, not milk alone.
 * Split only this exact generic recipe on explicit app calculation/edit. Both
 * parts are derived assumptions. No extra mass, brand, or historical rewrite.
 * The original caneca contract below deliberately has a different meaning.
 */
export function mobileMilkWheyTotalPortions(
  name: string,
  total: { quantity_g: number; quantity_basis?: HouseholdQuantityBasis },
): [HouseholdDrinkPart, HouseholdDrinkPart] | null {
  if (!/^leite(?: integral)? com (?:1|uma) (?:medida|dose) de whey$/.test(normalizeDrinkName(name)))
    return null
  if (!Number.isFinite(total.quantity_g) || total.quantity_g <= 30 || total.quantity_g > 9999)
    return null
  return [
    {
      food_name: 'leite integral',
      quantity_g: total.quantity_g - 30,
      quantity_basis: 'portion_reference',
    },
    { food_name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference' },
  ]
}

/**
 * Exact generic recipe only: no brand, other milk, negation or explicit
 * ingredient weights may be swallowed by the default. The caller supplies
 * New cup reference:200mL ×1.03g/mL =206g (FAO/INFOODS v2, whole milk TB).
 * milk grams only when the patient already entered/reviewed them.
 */
export function mobileMilkWheyPortions(
  name: string,
  milk?: { quantity_g: number; quantity_basis?: HouseholdQuantityBasis },
): HouseholdDrinkPart[] | null {
  const normalized = normalizeDrinkName(name)
  if (
    !/^(?:(?:eu )?(?:tomei|bebi|consumi|ingeri) )?(?:1|uma) caneca de leite com (?:1|uma) (?:medida|dose) de whey$/.test(
      normalized,
    )
  )
    return null
  const grams = milk?.quantity_g ?? 206
  if (!Number.isFinite(grams) || grams <= 0 || grams > 9999) return null
  return [
    {
      food_name: 'leite integral',
      quantity_g: grams,
      quantity_basis: milk?.quantity_basis ?? (milk ? 'stated' : 'portion_reference'),
    },
    { food_name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference' },
  ]
}
