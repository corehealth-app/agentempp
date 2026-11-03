/** Roberto's 31/10 screenshot: "arroz" 200 g and "feijão" 200 g could not
 * be recorded. Eduardo approved cooked, visible, editable mobile defaults
 * on03/11. This policy does not change the09/28 legacy clarification rule.
 * Catalog values below are from migration20260718213529, not an AI estimate.
 */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { calcMealMacros } from '../meal-pipeline.js'

const POLICY = { consumptionPolicy: 'consumed-meal-v1' as const }
const OWNER = '11111111-1111-4111-8111-111111111111'
const foods = [
  {
    id: 160,
    name_pt: 'Arroz, tipo 1, cozido',
    category: 'Cereais e derivados',
    kcal_per_100g: 128.26,
    protein_g: 2.52,
    carbs_g: 28.06,
    fat_g: 0.23,
    fiber_g: 1.56,
  },
  {
    id: 161,
    name_pt: 'Arroz, tipo 1, cru',
    category: 'Cereais e derivados',
    kcal_per_100g: 357.79,
    protein_g: 7.16,
    carbs_g: 78.76,
    fat_g: 0.34,
    fiber_g: 1.64,
  },
  {
    id: 158,
    name_pt: 'Arroz, integral, cozido',
    category: 'Cereais e derivados',
    kcal_per_100g: 123.53,
    protein_g: 2.59,
    carbs_g: 25.81,
    fat_g: 1,
    fiber_g: 2.75,
  },
  {
    id: 159,
    name_pt: 'Arroz, integral, cru',
    category: 'Cereais e derivados',
    kcal_per_100g: 359.68,
    protein_g: 7.32,
    carbs_g: 77.45,
    fat_g: 1.86,
    fiber_g: 4.82,
  },
  {
    id: 703,
    name_pt: 'Feijão, carioca, cozido',
    category: 'Leguminosas e derivados',
    kcal_per_100g: 76.42,
    protein_g: 4.78,
    carbs_g: 13.59,
    fat_g: 0.54,
    fiber_g: 8.51,
  },
  {
    id: 704,
    name_pt: 'Feijão, carioca, cru',
    category: 'Leguminosas e derivados',
    kcal_per_100g: 329.03,
    protein_g: 19.98,
    carbs_g: 61.22,
    fat_g: 1.26,
    fiber_g: 18.42,
  },
  {
    id: 709,
    name_pt: 'Feijão, preto, cozido',
    category: 'Leguminosas e derivados',
    kcal_per_100g: 77.03,
    protein_g: 4.48,
    carbs_g: 14.01,
    fat_g: 0.54,
    fiber_g: 8.4,
  },
  {
    id: 710,
    name_pt: 'Feijão, preto, cru',
    category: 'Leguminosas e derivados',
    kcal_per_100g: 323.57,
    protein_g: 21.34,
    carbs_g: 58.75,
    fat_g: 1.24,
    fiber_g: 21.83,
  },
].map((row) => ({ ...row, country_code: 'BR', similarity: 0.6 }))

type Food = (typeof foods)[number]
type Options = {
  missing?: number
  changed?: number
  failure?: boolean
  correction?: boolean
  correctionName?: string
}
function database(options: Options = {}) {
  const calls: string[] = []
  const chain = (rows: unknown[]) => {
    const builder: Record<string, unknown> = { data: rows, error: null }
    for (const key of ['select', 'eq', 'neq', 'gt', 'gte', 'ilike', 'in', 'or', 'order', 'limit'])
      builder[key] = () => builder
    builder.or = (expression: string) => {
      const name = /^said_name\.eq\.(.*),corrected_to\.eq\.\1$/.exec(expression)?.[1]
      builder.data = rows.filter((row) => {
        const record = row as Record<string, unknown>
        return record.said_name === name || record.corrected_to === name
      })
      return builder
    }
    return builder
  }
  const client = {
    rpc: async (name: string, params: { search_term: string; min_similarity: number }) => {
      expect(name).toBe('search_food_trgm')
      calls.push(params.search_term)
      if (options.failure) return { data: null, error: { message: 'catalog unavailable' } }
      let found: Food[]
      if (params.min_similarity >= 0.9)
        found = foods.filter((row) => row.name_pt.toLowerCase() === params.search_term)
      else if (params.search_term.includes('arroz'))
        found = foods.filter((row) => row.name_pt.startsWith('Arroz'))
      else if (params.search_term.includes('feij'))
        found = foods.filter((row) => row.name_pt.startsWith('Feijão'))
      else found = []
      return {
        data: found
          .filter((row) => row.id !== options.missing)
          .map((row) => ({
            ...row,
            kcal_per_100g: row.id === options.changed ? 999 : row.kcal_per_100g,
          })),
        error: null,
      }
    },
    from: (table: string) =>
      chain(
        table === 'user_food_corrections' && options.correction
          ? [
              {
                said_name: options.correctionName ?? 'arroz',
                corrected_to: 'arroz personalizado',
                status: 'active',
                confirmed_count: 4,
                custom_kcal_per_100g: 100,
                custom_protein_g: 3,
                custom_carbs_g: 20,
                custom_fat_g: 1,
              },
            ]
          : [],
      ),
  }
  return { client: client as unknown as ServiceClient, calls }
}

describe('mobile consumed meal — approved cooked defaults', () => {
  it.each([
    'arroz200g',
    'arroz 200 g',
    'arroz200,0g',
  ])('normalizes a duplicated gram quantity in the known food name %s', async (food_name) => {
    const result = await calcMealMacros(
      database().client,
      [{ food_name, quantity_g: 200 }],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'arroz branco cozido',
      quantity_g: 200,
      kcal: 256.5,
    })
  })
  it('refuses conflicting explicit name/field quantities instead of silently choosing either', async () => {
    await expect(
      calcMealMacros(
        database().client,
        [{ food_name: 'arroz200g', quantity_g: 100 }],
        'BR',
        undefined,
        POLICY,
      ),
    ).rejects.toThrow('consumed_food_quantity_conflict')
  })
  it.each([
    'arroz Tio João',
    'arroz com frango',
    'feijão tropeiro',
    'Rap10 100g',
  ])('keeps branded, composite and SKU inputs outside the cooked default: %s', async (food_name) => {
    const input = [{ food_name, quantity_g: 100 }]
    const legacy = await calcMealMacros(database().client, input, 'BR')
    const scoped = await calcMealMacros(database().client, input, 'BR', undefined, POLICY)
    expect(scoped).toEqual(legacy)
  })
  it('does not apply Brazilian references in a different country', async () => {
    const input = [{ food_name: 'arroz', quantity_g: 100 }]
    expect(await calcMealMacros(database().client, input, 'US', undefined, POLICY)).toEqual(
      await calcMealMacros(database().client, input, 'US'),
    )
  })
  it('calculates the exact reported arroz200g + feijão200g without raw/preparation blockers', async () => {
    const { client } = database()
    const result = await calcMealMacros(
      client,
      [
        { food_name: 'arroz', quantity_g: 200 },
        { food_name: 'feijão', quantity_g: 200 },
      ],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items.map((item) => [item.food_name, item.quantity_g, item.kcal])).toEqual([
      ['arroz branco cozido', 200, 256.5],
      ['feijão carioca cozido', 200, 152.8],
    ])
    expect(result.totals.kcal).toBe(409.3)
    expect(result.items.every((item) => item.preparation_options === undefined)).toBe(true)
    expect(result.user_warnings.join(' ')).toContain('cozido')
    expect(result.user_warnings.join(' ')).toContain('carioca')
    expect(result.user_warnings.join(' ')).not.toContain('Não sei se')
  })

  it.each([
    ['ARROZ  BRANCO', 'arroz branco cozido', 160, 128.3],
    ['arroz integral', 'arroz integral cozido', 158, 123.5],
    ['FEIJÃO  CARIOCA', 'feijão carioca cozido', 703, 76.4],
    ['feijao preto', 'feijão preto cozido', 709, 77],
  ])('preserves the named variety for %s', async (name, shown, id, kcal) => {
    const result = await calcMealMacros(
      database().client,
      [{ food_name: name, quantity_g: 100 }],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items[0]).toMatchObject({ food_name: shown, matched_taco_id: id, kcal })
  })

  it('keeps the old ambiguity policy without explicit consumption capability', async () => {
    const result = await calcMealMacros(database().client, [
      { food_name: 'arroz branco', quantity_g: 200 },
    ])
    expect(result.items[0]).toMatchObject({
      food_name: 'arroz branco',
      source: 'no_match',
      kcal: 0,
    })
    expect(result.items[0]?.preparation_options).toContain('cru')
  })

  it('does not replace an explicitly stated raw preparation', async () => {
    const result = await calcMealMacros(
      database().client,
      [{ food_name: 'arroz integral cru', quantity_g: 100 }],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items[0]?.food_name).toBe('arroz integral cru')
    expect(result.items[0]?.matched_taco_id).toBe(159)
    expect(result.items[0]?.kcal).toBe(359.7)
    expect(result.user_warnings.join(' ')).not.toContain('Considerei')
  })

  it('keeps approved label nutrition ahead of the assumption', async () => {
    const result = await calcMealMacros(
      database().client,
      [
        {
          food_name: 'arroz',
          quantity_g: 100,
          approved_nutrition: {
            source: 'product_label',
            kcal: 140,
            protein_g: 4,
            carbs_g: 28,
            fat_g: 1,
          },
        },
      ],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'arroz',
      source: 'product_label',
      kcal: 140,
    })
  })

  it('keeps active personal correction ahead of the assumption', async () => {
    const result = await calcMealMacros(
      database({ correction: true }).client,
      [{ food_name: 'arroz', quantity_g: 100 }],
      'BR',
      OWNER,
      POLICY,
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'arroz personalizado',
      source: 'user_correction',
      kcal: 100,
    })
  })

  it('looks up the original food identity before normalizing duplicated grams', async () => {
    const result = await calcMealMacros(
      database({ correction: true, correctionName: 'arroz200g' }).client,
      [{ food_name: 'arroz200g', quantity_g: 100 }],
      'BR',
      OWNER,
      POLICY,
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'arroz personalizado',
      source: 'user_correction',
      kcal: 100,
    })
  })

  it('coalesces same assumed food without losing a later candidate mapping', async () => {
    const result = await calcMealMacros(
      database().client,
      [
        { food_name: 'arroz', quantity_g: 100 },
        { food_name: 'arroz branco', quantity_g: 100 },
        { food_name: 'feijão', quantity_g: 100 },
      ],
      'BR',
      undefined,
      POLICY,
    )
    expect(result.items.map((item) => item.quantity_g)).toEqual([200, 100])
    expect(result.input_indexes).toEqual([[0, 1], [2]])
  })

  it.each([
    { missing: 703 },
    { changed: 703 },
  ])('rejects unavailable verified reference %j instead of guessing generic beans or zero', async (options) => {
    await expect(
      calcMealMacros(
        database(options).client,
        [{ food_name: 'feijão', quantity_g: 200 }],
        'BR',
        undefined,
        POLICY,
      ),
    ).rejects.toThrow('consumed_food_reference_unavailable')
  })

  it('propagates catalog failure without creating any result', async () => {
    await expect(
      calcMealMacros(
        database({ failure: true }).client,
        [{ food_name: 'arroz', quantity_g: 200 }],
        'BR',
        undefined,
        POLICY,
      ),
    ).rejects.toThrow('catalog unavailable')
  })
})
