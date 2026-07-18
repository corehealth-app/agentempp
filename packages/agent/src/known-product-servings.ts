export interface ProductServingItem {
  food_name: string
  quantity_g: number
}

export interface ProductServingAdjustment {
  food_name: string
  previous_quantity_g: number
  quantity_g: number
  servings: number
  source: 'mission_carb_balance_label'
}

function normalize(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function missionRap10ServingCount(text: string): number | null {
  const normalized = normalize(text)
  if (/\brap\s*10\s*(?:de\s*)?\d+(?:[.,]\d+)?\s*g\b/.test(normalized)) return null
  if (/\b\d+(?:[.,]\d+)?\s*g\s*(?:de\s*)?rap\s*10\b/.test(normalized)) return null

  const match = normalized.match(/\b(\d{1,2})\s*(?:x\s*)?rap\s*10\b/)
  if (!match) return null
  const servings = Number(match[1])
  return Number.isInteger(servings) && servings > 0 && servings <= 10 ? servings : null
}

/**
 * Applies serving weights only when both the product and count are explicit.
 * This closes the gap where the model converted "1 rap10" to a generic 35 g
 * wrap despite the verified Mission label declaring 43 g per tortilla.
 */
export function applyKnownProductServingQuantities<T extends ProductServingItem>(
  items: T[],
  patientText: string,
  country: string,
): { items: T[]; adjustments: ProductServingAdjustment[] } {
  if (country.toUpperCase() !== 'US') return { items, adjustments: [] }

  const servings = missionRap10ServingCount(patientText)
  if (servings == null) return { items, adjustments: [] }

  const adjustments: ProductServingAdjustment[] = []
  const adjusted = items.map((item) => {
    if (!/^rap\s*10$/i.test(normalize(item.food_name))) return item
    const quantity = servings * 43
    if (Math.abs(item.quantity_g - quantity) < 0.01) return item
    adjustments.push({
      food_name: item.food_name,
      previous_quantity_g: item.quantity_g,
      quantity_g: quantity,
      servings,
      source: 'mission_carb_balance_label',
    })
    return { ...item, quantity_g: quantity }
  })

  return { items: adjusted, adjustments }
}
