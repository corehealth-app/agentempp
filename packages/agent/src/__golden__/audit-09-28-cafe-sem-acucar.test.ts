/**
 * Golden test — "café sem açúcar" estimated as a sweet, staging device gate
 * of 2026-09-28 (QA account A, iPhone, text registration, backend 20a09fe).
 *
 * Exact scenario: the patient wrote
 *   "Arroz branco 150 g, feijão carioca 86,5 g, frango grelhado 120 g e um café sem açúcar"
 * the text extractor returned "café sem açúcar", the patient typed 50 g, and
 * the proposal (pending 318a4b6c…) showed
 *   café sem açúcar  50 g  130 kcal · P 1,5 g · C 22,5 g · G 4 g  (llm_estimate, food_db null)
 * i.e. the "doce" estimate (260 kcal/100 g): the word "açúcar" matched the
 * sweets rule although the patient said there was NO sugar.
 *
 * The food window is the exact staging RPC result of
 * search_food_trgm('café sem açúcar', 0.2, 10, 'BR') on 2026-09-28 (public
 * TACO data). Unsweetened black coffee in TACO: "Café, infusão 10%" 9.07
 * kcal/100 g; the curated "café preto" row is 2 kcal/100 g.
 */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { calcMealMacros, estimateMacros } from '../meal-pipeline.js'

const WINDOW = [
  { id: 637, name_pt: 'Açúcar, cristal', category: 'Produtos açucarados', country_code: 'BR', similarity: 0.347826, kcal_per_100g: 386.85, protein_g: 0.32, carbs_g: 99.61, fat_g: 0, fiber_g: null },
  { id: 638, name_pt: 'Açúcar, mascavo', category: 'Produtos açucarados', country_code: 'BR', similarity: 0.291667, kcal_per_100g: 368.55, protein_g: 0.76, carbs_g: 94.45, fat_g: 0.09, fiber_g: null },
  { id: 639, name_pt: 'Açúcar, refinado', category: 'Produtos açucarados', country_code: 'BR', similarity: 0.28, kcal_per_100g: 386.57, protein_g: 0.32, carbs_g: 99.54, fat_g: 0, fiber_g: null },
  { id: 183, name_pt: 'Cereal matinal, milho, açúcar', category: 'Cereais e derivados', country_code: 'BR', similarity: 0.235294, kcal_per_100g: 376.56, protein_g: 4.74, carbs_g: 88.84, fat_g: 0.67, fiber_g: 2.11 },
  { id: 478, name_pt: 'Carne, bovina, acém, sem gordura, cru', category: 'Carnes e derivados', country_code: 'BR', similarity: 0.230769, kcal_per_100g: 144.03, protein_g: 20.82, carbs_g: 0, fat_g: 6.11, fiber_g: null },
  { id: 477, name_pt: 'Carne, bovina, acém, sem gordura, cozido', category: 'Carnes e derivados', country_code: 'BR', similarity: 0.214286, kcal_per_100g: 214.61, protein_g: 27.27, carbs_g: 0, fat_g: 10.88, fiber_g: null },
]

function stagingMock(): ServiceClient {
  const chain = (rows: unknown): unknown => {
    const obj: Record<string, unknown> = { data: rows, error: null }
    for (const m of ['select', 'eq', 'ilike', 'gte', 'gt', 'lt', 'neq', 'in', 'or', 'order', 'limit']) {
      obj[m] = () => chain(rows)
    }
    obj.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return obj
  }
  return {
    rpc: async (_fn: string, params: { search_term: string }) => ({
      data: params.search_term.toLowerCase().trim() === 'café sem açúcar' ? WINDOW : [],
      error: null,
    }),
    from: (table: string) => {
      if (table === 'product_events') return { insert: () => chain([]) }
      return chain([])
    },
  } as unknown as ServiceClient
}

describe('audit 2026-09-28 — "café sem açúcar" is not a sweet', () => {
  it('the exact item (50 g) is never priced as sugar or as a sweet', async () => {
    const result = await calcMealMacros(stagingMock(), [{ food_name: 'café sem açúcar', quantity_g: 50 }], 'BR')
    const coffee = result.items[0]!
    expect(coffee.matched_taco_id).not.toBe(637)
    expect(coffee.matched_taco_name).not.toMatch(/doce|Açúcar/)
    // Unsweetened black coffee: at most TACO's infusion value (9.07 kcal/100 g).
    expect(coffee.kcal).toBeLessThanOrEqual(4.6)
    expect(coffee.carbs_g).toBeLessThanOrEqual(0.8)
    expect(coffee.fat_g).toBeLessThanOrEqual(0.1)
  })

  it('the estimate for unsweetened coffee phrasings is a zero-calorie drink', () => {
    for (const name of [
      'café sem açúcar',
      'Café sem acucar',
      'cafe sem açúcar',
      'café puro',
      'café expresso',
      'café coado sem açúcar',
      'café, sem açúcar',
      'café-puro',
      'cafe\u0301 sem ac\u0327u\u0301car', // decomposed accents (NFD)
    ]) {
      expect(estimateMacros(name).category, name).toBe('bebida_zero')
    }
  })

  it('sweets keep their estimate, including dense sweets said "sem açúcar"', () => {
    expect(estimateMacros('açúcar').category).toBe('doce')
    expect(estimateMacros('bolo de chocolate').category).toBe('doce')
    for (const name of ['paçoca sem açúcar', 'cocada sem açúcar', 'bala sem açúcar']) {
      expect(estimateMacros(name).category, name).toBe('doce')
    }
  })

  // Adversarial review 2026-09-28: only the drink itself is zero; foods and
  // drinks that merely contain coffee, or coffee with something added, are not.
  it('coffee-flavoured foods, compound items and coffee with additions are not zero', () => {
    for (const name of [
      'bolo de café sem açúcar',
      'pudim de café sem açúcar',
      'sorvete de café sem açúcar',
      'whey sabor café sem açúcar',
      'licor de café puro',
      'tiramisù de café expresso',
      'café da manhã sem açúcar',
      'café sem açúcar e pão',
      'café puro e pão de queijo',
      'café preto c/ açúcar',
      'café expresso + açúcar',
      'café puro com mel',
      'café expresso com chantili',
      'café puro com óleo de coco',
      'café com manteiga sem açúcar',
      'café', // plain "café" keeps its previous estimate: sugar is not ruled out
    ]) {
      expect(estimateMacros(name).category, name).not.toBe('bebida_zero')
    }
  })

  it('coffee with milk or sugar is not treated as a zero-calorie drink', () => {
    for (const name of ['café com leite', 'café com açúcar', 'café com leite sem açúcar', 'cappuccino', 'café com creme']) {
      expect(estimateMacros(name).category, name).not.toBe('bebida_zero')
    }
  })
})
