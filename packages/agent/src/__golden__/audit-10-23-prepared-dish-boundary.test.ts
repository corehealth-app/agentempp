/** Roberto23Oct: exact reported names/weights; empty synthetic catalog, no
 * patient account or network. App opt-in belongs to BFF, never shared routing. */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { calcMealMacros, estimateMacros, genericPreparedDishMacros } from '../meal-pipeline.js'
import { draftFromStatedText } from '../meal-draft.js'

describe('Roberto23Oct prepared dish: shared-engine boundary', () => {
  it('keeps legacy text routing unchanged; the mobile draft service owns the whole-dish interception', () => {
    const parsed = draftFromStatedText('macarrao espaguete cozido 200 g; carne desfiada com molho e milho 180 g')
    expect(parsed).toEqual({ raw: [
      { name: 'macarrao espaguete cozido', grams_stated: 200 },
      { name: 'milho', grams_stated: 180 },
    ], rest: ['carne desfiada com molho'] })
  })
  it('preserves the rejected compound and260kcal pasta without mobile opt-in', async () => {
    const emptyCatalog = {
      rpc: async (fn: string) => {
        if (fn !== 'search_food_trgm') throw new Error(`unexpected RPC: ${fn}`)
        return { data: [], error: null }
      },
      from: (table: string) => {
        if (table !== 'meal_logs') throw new Error(`unexpected table: ${table}`)
        const query = {
          select: () => query, eq: () => query, ilike: () => query,
          gte: () => query, in: () => query, order: () => query,
          limit: async () => ({ data: [], error: null }),
        }
        return query
      },
    } as unknown as ServiceClient
    const result = await calcMealMacros(emptyCatalog, [
      { food_name: 'macarrão espaguete cozido', quantity_g: 200 },
      { food_name: 'carne desfiada com molho e milho', quantity_g: 180 },
    ], 'BR')
    expect(result.items).toMatchObject([
      { food_name: 'macarrão espaguete cozido', quantity_g: 200, kcal: 260, source: 'llm_estimate' },
      { food_name: 'carne desfiada com molho e milho', quantity_g: 180, kcal: 0, source: 'composite_rejected' },
    ])
    expect(result.totals.kcal).toBe(260)
    expect(result.user_warnings).toContainEqual(expect.stringContaining('Não consegui identificar "carne desfiada com molho e milho"'))
  })

  it('reuses the existing generic base without selecting milho as a vegetable', () => {
    expect(genericPreparedDishMacros()).toEqual({ category: 'prato_genérico', kcal: 150, protein: 7, carbs: 18, fat: 5, fiber: 1 })
    expect(estimateMacros('referência sem categoria reconhecida')).toEqual(genericPreparedDishMacros())
    expect(estimateMacros('carne desfiada com molho e milho')).not.toEqual(genericPreparedDishMacros())
  })
})
