import {
  ConsumedFoodQuantityConflictError,
  ConsumedFoodReferenceUnavailableError,
  calcMealMacros,
  type MealItemInput,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'

/** The explicit app consumption boundary; legacy-created pending edits keep
 * their previous resolver. Source outages never masquerade as missing input. */
export async function calculateMobileConsumedMeal(
  db: ServiceClient,
  items: MealItemInput[],
  country: string,
  userId: string,
  enabled = true,
) {
  try {
    return enabled
      ? await calcMealMacros(db, items, country, userId, { consumptionPolicy: 'consumed-meal-v1' })
      : await calcMealMacros(db, items, country, userId)
  } catch (error) {
    if (error instanceof ConsumedFoodQuantityConflictError) {
      throw new MobileApiError(
        422,
        'meal_quantity_conflict',
        'O peso escrito no nome difere da quantidade informada. Ajuste a quantidade deste alimento.',
      )
    }
    if (error instanceof ConsumedFoodReferenceUnavailableError) {
      throw new MobileApiError(
        503,
        'nutrition_reference_unavailable',
        'A referência nutricional está temporariamente indisponível. Tente novamente; nenhum registro foi criado.',
      )
    }
    throw error
  }
}
