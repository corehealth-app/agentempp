import type { MealDraftCandidate } from '@mpp/agent'

/** Current food reference, not a recovered original serving or a measurement.
 * FAO/INFOODS Density Database v2 (2012), liquid whole milk, TB,1.030g/mL.
 * https://www.fao.org/4/ap815e/ap815e.pdf (PDF page13).
 * Exact food names only: powders, brands and mixtures never inherit density.
 */
export interface MobileQuantityDisplay {
  unit: 'mL'
  grams_per_unit: number
  reference_id: string
  estimated: true
}

// FAO table sources: milkTB1.030; brewedcoffee/teaFNDDS4.1(1);
// waterCG(1); orangejuiceS&W(1.038). Reference densities, not measurements.
const LIQUID_REFERENCES = [
  { names: ['leite integral'], grams_per_unit: 1.03, reference_id: 'fao-infoods-v2-whole-milk-tb' },
  {
    names: ['cafe coado', 'cafe preparado', 'cafe expresso', 'cafe espresso'],
    grams_per_unit: 1,
    reference_id: 'fao-infoods-v2-coffee-fndds4-1',
  },
  {
    names: ['cha preparado', 'cha liquido'],
    grams_per_unit: 1,
    reference_id: 'fao-infoods-v2-tea-fndds4-1',
  },
  { names: ['agua'], grams_per_unit: 1, reference_id: 'fao-infoods-v2-water-cg' },
  {
    names: ['suco de laranja'],
    grams_per_unit: 1.038,
    reference_id: 'fao-infoods-v2-orange-juice-sw',
  },
] as const

export function mobileQuantityDisplay(name: string): MobileQuantityDisplay | null {
  const food = name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
  const reference = LIQUID_REFERENCES.find((row) => row.names.some((name) => name === food))
  if (!reference) return null
  return {
    unit: 'mL',
    grams_per_unit: reference.grams_per_unit,
    reference_id: reference.reference_id,
    estimated: true,
  }
}

export function mobileQuantityFields(name: string) {
  const display = mobileQuantityDisplay(name)
  return display ? { quantity_display: display } : {}
}

/** Only draft candidates still carry their original explicit volume. Never
 * run on canonical requests/records: repeated reads must not multiply grams.
 */
export function mobileDraftQuantity(
  candidate: MealDraftCandidate,
): MealDraftCandidate & { quantity_display?: MobileQuantityDisplay } {
  const genericName = candidate.name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
  const display = mobileQuantityDisplay(genericName === 'leite' ? 'leite integral' : candidate.name)
  if (
    candidate.quantity_basis !== 'stated' &&
    candidate.unit_label?.toLowerCase() === 'ml' &&
    candidate.count != null
  ) {
    const grams = display ? Math.round(candidate.count * display.grams_per_unit * 1e6) / 1e6 : null
    if (grams == null || !Number.isFinite(grams) || grams <= 0 || grams > 9999) {
      return {
        ...candidate,
        quantity_g: null,
        quantity_basis: 'missing',
        needs_review: true,
        review_reason: 'missing_quantity',
      }
    }
    return {
      ...candidate,
      quantity_g: grams,
      quantity_basis: 'portion_reference',
      needs_review: true,
      review_reason: 'estimated_quantity',
      ...(display ? { quantity_display: display } : {}),
    }
  }
  return { ...candidate, ...(display ? { quantity_display: display } : {}) }
}
