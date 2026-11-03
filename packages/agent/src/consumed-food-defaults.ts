import { type EverydayFoodDefault, normalizeEverydayFoodName } from './everyday-food-defaults.js'

/** Explicit mobile consumption policy approved03/11/2026. Not a global
 * replacement for the legacy preparation question. Values identify existing
 * verified TACO rows; they are never used as a substitute for the catalog.
 */
export const CONSUMED_FOOD_DEFAULTS: readonly EverydayFoodDefault[] = [
  {
    said: ['arroz', 'arroz branco', 'arroz branco cozido', 'arroz cozido'],
    shown_as: 'arroz branco cozido',
    catalog_name: 'Arroz, tipo 1, cozido',
    source_ref: 'TACO4:3',
    per_100g: { kcal: 128.26, protein_g: 2.52, carbs_g: 28.06, fat_g: 0.23 },
    stated_on: '03/11/2026 — consumo no app: assumir cozido, mostrando a referência editável',
    status: 'confirmed',
  },
  {
    said: ['arroz integral', 'arroz integral cozido'],
    shown_as: 'arroz integral cozido',
    catalog_name: 'Arroz, integral, cozido',
    source_ref: 'TACO4:1',
    per_100g: { kcal: 123.53, protein_g: 2.59, carbs_g: 25.81, fat_g: 1 },
    stated_on: '03/11/2026 — preparo cozido; preservar variedade explicitamente informada',
    status: 'confirmed',
  },
  {
    said: ['feijao', 'feijao cozido', 'feijao carioca', 'feijao carioca cozido'],
    shown_as: 'feijão carioca cozido',
    catalog_name: 'Feijão, carioca, cozido',
    source_ref: 'TACO4:561',
    per_100g: { kcal: 76.42, protein_g: 4.78, carbs_g: 13.59, fat_g: 0.54 },
    stated_on:
      '03/11/2026 — cozido; feijão genérico usa referência carioca declarada, não variedade observada',
    status: 'confirmed',
  },
  {
    said: ['feijao preto', 'feijao preto cozido'],
    shown_as: 'feijão preto cozido',
    catalog_name: 'Feijão, preto, cozido',
    source_ref: 'TACO4:567',
    per_100g: { kcal: 77.03, protein_g: 4.48, carbs_g: 14.01, fat_g: 0.54 },
    stated_on: '03/11/2026 — preparo cozido; preservar variedade explicitamente informada',
    status: 'confirmed',
  },
]

export function consumedFoodDefault(name: string, country: string): EverydayFoodDefault | null {
  if (country.toUpperCase() !== 'BR') return null
  const normalized = normalizeEverydayFoodName(name)
  return CONSUMED_FOOD_DEFAULTS.find((entry) => entry.said.includes(normalized)) ?? null
}

/** Normalize only known whole food names with a duplicated gram suffix.
 * Never treat arbitrary letter/number product identifiers (Rap10) as grams.
 * Both explicit quantities must agree before either one can be recorded. */
export function normalizeConsumedFoodQuantity(
  name: string,
  grams: number,
  country: string,
): string {
  if (name.length > 160) return name
  const match = /^(.*?)\s*(\d+(?:[.,]\d+)?)\s*(?:g|gramas?)$/iu.exec(name.trim())
  if (!match || !consumedFoodDefault(match[1] ?? '', country)) return name
  if (Number((match[2] ?? '').replace(',', '.')) !== grams) {
    throw new ConsumedFoodQuantityConflictError()
  }
  return (match[1] ?? '').trim()
}

export class ConsumedFoodQuantityConflictError extends Error {
  constructor() {
    super('consumed_food_quantity_conflict')
    this.name = 'ConsumedFoodQuantityConflictError'
  }
}

/** A missing reference is operational unavailability, never an instruction to
 * ask raw/cooked again or to publish zero/generic-dish calories as resolved. */
export class ConsumedFoodReferenceUnavailableError extends Error {
  constructor() {
    super('consumed_food_reference_unavailable')
    this.name = 'ConsumedFoodReferenceUnavailableError'
  }
}
