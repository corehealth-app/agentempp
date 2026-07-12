import type { MealItem } from '@mpp/agent'

export type PendingMealItemAction =
  | 'proceed'
  | 'reject_empty'
  | 'block'
  | 'register_valid_only'
  | 'reject_all'

export interface PendingMealItemDecision {
  action: PendingMealItemAction
  validItems: MealItem[]
  suspiciousItems: MealItem[]
}

const ZERO_CAL_NAME_RE =
  /\b(agua|gelo|gelos|cha|chas|cafe\s+preto|cafe\s+sem\s+acucar|mostarda|vinagre|limao|shoyu|molho\s+shoyu|sal|pimenta|gengibre|alho|acafrao|canela|oregano|salsinha|cebolinha|coentro|manjericao|hortela|aji-no-moto|caldo\s+knorr|caldo\s+de\s+galinha|caldo\s+de\s+legumes)\b/
const ZERO_CAL_DRINK_QUALIFIER_RE = /\b(zero|diet|sem\s+acucar)\b/
const DRINK_KEYWORD_RE =
  /\b(refri\w*|refrigerante|coca|coca-cola|guarana|pepsi|sprite|fanta|schweppes|powerade|gatorade|red\s*bull|tonica|isotonico|energetico|soda|h2o|monster|burn)\b/

function normalizeName(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
}

function isLegitimateZeroCalorieItem(item: MealItem): boolean {
  const name = normalizeName(String(item.name ?? ''))
  if (ZERO_CAL_NAME_RE.test(name)) return true
  return ZERO_CAL_DRINK_QUALIFIER_RE.test(name) && DRINK_KEYWORD_RE.test(name)
}

export function decidePendingMealItems(
  items: MealItem[],
  wasPreviouslyBlocked: boolean,
): PendingMealItemDecision {
  if (items.length === 0) {
    return { action: 'reject_empty', validItems: [], suspiciousItems: [] }
  }

  const suspiciousItems = items.filter((item) => {
    const kcal = Number(item.kcal)
    return (!Number.isFinite(kcal) || kcal <= 0) && !isLegitimateZeroCalorieItem(item)
  })
  const suspiciousSet = new Set(suspiciousItems)
  const validItems = items.filter((item) => !suspiciousSet.has(item))

  if (suspiciousItems.length === 0) {
    return { action: 'proceed', validItems, suspiciousItems }
  }
  if (!wasPreviouslyBlocked) {
    return { action: 'block', validItems, suspiciousItems }
  }
  if (validItems.length > 0) {
    return { action: 'register_valid_only', validItems, suspiciousItems }
  }
  return { action: 'reject_all', validItems, suspiciousItems }
}
