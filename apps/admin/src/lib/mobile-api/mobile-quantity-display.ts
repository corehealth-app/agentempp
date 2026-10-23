import type { MealDraftCandidate, MealDraftRawItem } from '@mpp/agent'

/** Current food reference, not a recovered original serving or a measurement.
 * FAO/INFOODS Density Database v2 (2012), liquid whole milk, TB,1.030g/mL.
 * https://www.fao.org/4/ap815e/ap815e.pdf (PDF page13).
 * Exact food names only: powders, brands and mixtures never inherit density.
 */
export interface MobileQuantityDisplay {
  unit: 'mL' | 'unit' | 'scoop'
  grams_per_unit: number
  reference_id: string
  estimated: true
}

// FAO table sources: milkTB1.030; brewedcoffee/teaFNDDS4.1(1);
// waterCG(1); orangejuiceS&W(1.038). Reference densities, not measurements.
const LIQUID_REFERENCES = [
  {
    names: ['leite', 'leite integral'],
    grams_per_unit: 1.03,
    reference_id: 'fao-infoods-v2-whole-milk-tb',
  },
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

// Existing editable app references, not measured product or serving weights.
// Exact names only; e.g. a brand-specific scoop has no implied30g weight.
const PORTION_REFERENCES = [
  {
    names: ['whey', 'whey protein', 'whey protein em po'],
    unit: 'scoop',
    grams_per_unit: 30,
    reference_id: 'app-household-whey-scoop-v1',
  },
  {
    names: ['pao de queijo', 'paes de queijo', 'pao de queijo com requeijao'],
    unit: 'unit',
    grams_per_unit: 30,
    reference_id: 'app-household-cheese-bread-unit-v1',
  },
  {
    names: ['ovo', 'ovos', 'ovo de galinha', 'ovos de galinha'],
    unit: 'unit',
    grams_per_unit: 50,
    reference_id: 'app-household-egg-unit-v1',
  },
  {
    names: ['pao frances', 'paes franceses', 'paozinho'],
    unit: 'unit',
    grams_per_unit: 50,
    reference_id: 'app-household-french-bread-unit-v1',
  },
  {
    names: ['banana', 'bananas'],
    unit: 'unit',
    grams_per_unit: 100,
    reference_id: 'app-household-banana-unit-v1',
  },
  {
    names: ['maca', 'macas'],
    unit: 'unit',
    grams_per_unit: 150,
    reference_id: 'app-household-apple-unit-v1',
  },
] as const

function normalize(name: string): string {
  return name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

export function mobileQuantityDisplay(name: string): MobileQuantityDisplay | null {
  const food = normalize(name)
  const portion = PORTION_REFERENCES.find((row) => row.names.some((name) => name === food))
  if (portion)
    return {
      unit: portion.unit,
      grams_per_unit: portion.grams_per_unit,
      reference_id: portion.reference_id,
      estimated: true,
    }
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

/** Mobile text boundary only. Never change the shared/legacy parser. Unknown
 * recipes, brands, negations and explicit masses stay on the existing path. */
export function mobileHouseholdTextItem(text: string): MealDraftRawItem | null {
  const match =
    /^(?:(?:eu )?(?:tomei|bebi|consumi|ingeri) )?(1|um|uma|2|dois|duas|\d+(?:[.,]\d+)?) (canecas?|medidas?|doses?) de (.+?)[.!]?$/.exec(
      normalize(text),
    )
  if (!match) return null
  const count = ['um', 'uma'].includes(match[1]!)
    ? 1
    : ['dois', 'duas'].includes(match[1]!)
      ? 2
      : Number(match[1]!.replace(',', '.'))
  const name = match[3]!
  const display = mobileQuantityDisplay(name)
  const cup = match[2]!.startsWith('caneca')
  if (
    !display ||
    !(count > 0 && count <= 100) ||
    (cup ? display.reference_id !== 'fao-infoods-v2-whole-milk-tb' : display.unit !== 'scoop')
  )
    return null
  const grams =
    Math.round(count * (cup ? 200 * display.grams_per_unit : display.grams_per_unit) * 1e6) / 1e6
  if (!Number.isFinite(grams) || grams <= 0 || grams > 9999) return null
  // These grams come ONLY from the exact original segment above. A simplified
  // extractor candidate is insufficient evidence of a caneca or scoop.
  return { name, count, unit: cup ? 'caneca' : 'medida', grams_stated: grams }
}

/** Only draft candidates still carry their original explicit volume. Never
 * run on canonical requests/records: repeated reads must not multiply grams.
 */
export function mobileDraftQuantity(
  candidate: MealDraftCandidate,
): MealDraftCandidate & { quantity_display?: MobileQuantityDisplay } {
  const display = mobileQuantityDisplay(candidate.name)
  const unit = normalize(candidate.unit_label ?? '')
  if (candidate.quantity_basis !== 'stated' && unit === 'ml' && candidate.count != null) {
    const grams =
      display?.unit === 'mL'
        ? Math.round(candidate.count * display.grams_per_unit * 1e6) / 1e6
        : null
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
