import type { TrustedVisionNutritionLabel } from './types.js'

interface VisionNutritionMealItem {
  food_name: string
  quantity_g: number
  user_kcal?: number | null
  approved_nutrition?: {
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }
}

const IGNORED_TOKENS = new Set(['a', 'ao', 'com', 'da', 'de', 'do', 'e', 'em', 'para', 'sabor'])
const DISTINCTIVE_PRODUCT_TOKENS = new Set(['kefir', 'koumiss', 'kumis', 'kumys', 'skyr'])

function normalizeName(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function namesMatch(foodName: string, productName: string | null): boolean {
  if (!productName) return false
  const food = normalizeName(foodName)
  const product = normalizeName(productName)
  if (!food || !product) return false
  if (food === product) return true
  if (
    Math.min(food.length, product.length) >= 4 &&
    (food.includes(product) || product.includes(food))
  ) {
    return true
  }

  const foodTokens = new Set(food.split(' ').filter((token) => !IGNORED_TOKENS.has(token)))
  const productTokens = new Set(product.split(' ').filter((token) => !IGNORED_TOKENS.has(token)))
  const smallerSize = Math.min(foodTokens.size, productTokens.size)
  if (smallerSize === 0) return false
  const sharedTokens = [...foodTokens].filter((token) => productTokens.has(token))
  if (sharedTokens.some((token) => DISTINCTIVE_PRODUCT_TOKENS.has(token))) return true
  const overlap = sharedTokens.length
  const minimumOverlap = smallerSize === 1 ? 1 : 2
  return overlap >= minimumOverlap && overlap / smallerSize >= 0.6
}

function scale(value: number, quantityG: number): number {
  return Math.round(value * (quantityG / 100) * 100) / 100
}

function matchesDeclaredServing(
  quantityG: number,
  servingSizeG: number | null | undefined,
): boolean {
  if (
    servingSizeG == null ||
    !Number.isFinite(servingSizeG) ||
    servingSizeG <= 0 ||
    !Number.isFinite(quantityG) ||
    quantityG <= 0
  ) {
    return false
  }
  return Math.abs(quantityG - servingSizeG) <= Math.max(0.5, servingSizeG * 0.01)
}

export function attachTrustedVisionNutrition<T extends VisionNutritionMealItem>(
  items: T[],
  labels: TrustedVisionNutritionLabel[],
): Array<T & { approved_nutrition?: VisionNutritionMealItem['approved_nutrition'] }> {
  return items.map((item) => {
    if (item.user_kcal != null || item.approved_nutrition) return item
    let matchingLabels = labels.filter((label) => namesMatch(item.food_name, label.productName))
    if (matchingLabels.length === 0) {
      matchingLabels = labels.filter((label) => {
        if (!matchesDeclaredServing(item.quantity_g, label.servingSizeG)) return false
        const itemsAtServing = items.filter((candidate) =>
          matchesDeclaredServing(candidate.quantity_g, label.servingSizeG),
        )
        return itemsAtServing.length === 1
      })
    }
    if (matchingLabels.length !== 1) return item

    const [label] = matchingLabels
    if (!label) return item
    return {
      ...item,
      approved_nutrition: {
        kcal: scale(label.per100g.kcal, item.quantity_g),
        protein_g: scale(label.per100g.protein_g, item.quantity_g),
        carbs_g: scale(label.per100g.carbs_g, item.quantity_g),
        fat_g: scale(label.per100g.fat_g, item.quantity_g),
      },
    }
  })
}
