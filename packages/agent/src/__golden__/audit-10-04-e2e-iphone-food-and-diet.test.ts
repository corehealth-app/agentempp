/**
 * Golden regressions from the iPhone end-to-end round of 2026-10-04
 * (QA account A, staging, build b92fb28, 09:00–09:35 BRT).
 *
 * F1/F24 — text meal "2 ovos mexidos, 1 pao frances e 200 ml de cafe sem
 * acucar": the extractor returned "ovo mexido", 100 g, and meal_logs stored
 *   ovo mexido 100 g  150 kcal · P 7 · C 18 · G 5  (llm_estimate, food_db null)
 * i.e. the generic prepared dish. Second meal, "… 1 colher de sopa de azeite,
 * 2 ovos cozidos e 200 ml de leite integral": pending_registrations
 * (12:31:56Z) held
 *   azeite 13 g        19.5 kcal · G 0.65          (llm_estimate)
 *   ovo cozido 100 g   150 kcal · P 7 · C 18 · G 5 (llm_estimate)
 *   leite integral 200 g  224.9 kcal · C 47.26     (food_db 177, "Canjica, com leite integral")
 *   whey 30 g          0 kcal                      (protein_mismatch, food_db 4112)
 *
 * The food windows are the exact staging RPC results of search_food_trgm on
 * 2026-10-04.
 *
 * > RC F23 — "leite integral" 200 ml (224.9 kcal, "Canjica, com leite
 * > integral") and "whey" 30 g (protein_mismatch, 0 kcal) NOT covered by this
 * > change (pending from the audit 2026-10-04). They need audited catalog
 * > aliases; a first set was withdrawn after the adversarial review showed
 * > that exact "azeite"/"whey" rows make the composed-name split price half
 * > of "salada com azeite" as oil, that "ovo cozido" + "ovo frito" turn a
 * > bare "ovo" into a cru/cozido question, and that "arroz branco cozido"
 * > removes the preparation question of 2026-09-28. Catalog decision pending.
 * > RC F25 — "1 scoop de whey" and "1 colher de sopa de azeite" (household
 * > measures not converted) NOT covered: the fixtures enter with the grams
 * > typed on the phone (30 g, 13 g).
 * > RC — "arroz branco" 150 g and "feijão" 100 g of the same lunch still ask
 * > cru/cozido (by design since 2026-09-28) and are NOT changed here.
 * > RC — the typed phrases do not go through the text extractor in these
 * > fixtures; plural names ("ovos fritos") reach the egg estimate (146 kcal),
 * > not a fried-egg value.
 *
 * F14 — Flow turn "Sim, pode sugerir" (12:13:47Z): attempt 1
 * zod_validation_failed, daily_meals.0.items.0.{quantity_g,kcal,protein_g,
 * carbs_g,fat_g} "Expected number, received string"; attempt 2
 * protein_drift_exceeded, 200 g against 144.9 g (38%). The model outputs were
 * not retained: the fixtures reproduce the recorded paths and totals, not
 * unobserved food choices.
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it } from 'vitest'
import { type DietGeneratorInput, generateDietPlan, normalizeGeneratedDiet } from '../diet-generator.js'
import { calcMealMacros, estimateMacros } from '../meal-pipeline.js'

type Row = {
  id: number
  name_pt: string
  category: string
  country_code: string
  similarity: number
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number | null
}

const row = (
  id: number,
  name_pt: string,
  similarity: number,
  kcal: number,
  protein: number,
  carbs: number,
  fat: number,
  category = 'x',
  country_code = 'BR',
): Row => ({ id, name_pt, category, country_code, similarity, kcal_per_100g: kcal, protein_g: protein, carbs_g: carbs, fat_g: fat, fiber_g: null })

// search_food_trgm(term, 0.2, …, 'BR') on staging, 2026-10-04, before the migration.
const BEFORE: Record<string, Row[]> = {
  'ovo mexido': [],
  'ovo cozido': [
    row(250, 'Cará, cozido', 0.47, 77.58, 1.5, 18.9, 0.1),
    row(266, 'Chuchu, cozido', 0.44, 18.54, 0.4, 4.8, 0),
    row(725, 'Pinhão, cozido', 0.39, 174.37, 3, 43.9, 0.7),
  ],
  azeite: [],
  'leite integral': [
    row(177, 'Canjica, com leite integral', 0.576923, 112.46, 2.36, 23.63, 1.24, 'Cereais e derivados'),
    row(605, 'Leite, de vaca, integral, pó', 0.576923, 496.65, 25.42, 39.18, 26.9, 'Leite e derivados'),
    row(159, 'Arroz, integral, cru', 0.36, 359.68, 7.32, 77.45, 1.86, 'Cereais e derivados'),
  ],
  whey: [
    row(4112, 'Whey, acid, fluid', 0.333333, 24, 0.76, 5.12, 0.09, 'Dairy and Egg Products', 'US'),
    row(4508, 'Whey, acid, dried', 0.3125, 339, 11.73, 73.45, 0.54, 'Dairy and Egg Products', 'US'),
  ],
}

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
    rpc: async (_fn: string, params: { search_term: string }) => {
      const term = params.search_term.toLowerCase().trim()
      return { data: BEFORE[term] ?? [], error: null }
    },
    from: (table: string) => {
      if (table === 'product_events') return { insert: () => chain([]) }
      return chain([])
    },
  } as unknown as ServiceClient
}

describe('audit 2026-10-04 — an egg or an oil is never the generic dish', () => {
  it('"ovo mexido" 100 g without any catalog match is priced as egg, not as 18 g of carbohydrate', async () => {
    const result = await calcMealMacros(stagingMock(), [{ food_name: 'ovo mexido', quantity_g: 100 }], 'BR')
    const egg = result.items[0]!
    expect(egg.matched_taco_name).not.toContain('prato_genérico')
    expect(egg.carbs_g).toBeLessThanOrEqual(2)
    expect(egg.protein_g).toBeGreaterThanOrEqual(9.9)
    expect(egg.kcal).toBeGreaterThanOrEqual(140)
    expect(egg.kcal).toBeLessThanOrEqual(160)
  })

  it('"ovo cozido" 100 g rejects "Cará, cozido" and is still priced as egg', async () => {
    const result = await calcMealMacros(stagingMock(), [{ food_name: 'ovo cozido', quantity_g: 100 }], 'BR')
    const egg = result.items[0]!
    expect(egg.matched_taco_id).not.toBe(250)
    expect(egg.carbs_g).toBeLessThanOrEqual(2)
    expect(egg.protein_g).toBeGreaterThanOrEqual(13)
  })

  it('"azeite" 13 g is about 115 kcal of fat, not 19.5 kcal', async () => {
    const result = await calcMealMacros(stagingMock(), [{ food_name: 'azeite', quantity_g: 13 }], 'BR')
    const oil = result.items[0]!
    expect(oil.kcal).toBeGreaterThanOrEqual(110)
    expect(oil.kcal).toBeLessThanOrEqual(120)
    expect(oil.fat_g).toBeGreaterThanOrEqual(12.5)
    expect(oil.carbs_g).toBe(0)
  })

  it('the estimate categories: eggs anywhere, fat and whey only when the item IS the fat or the powder', () => {
    expect(estimateMacros('ovo mexido')).toMatchObject({ category: 'ovo', kcal: 146, carbs: 0.6 })
    expect(estimateMacros('2 ovos')).toMatchObject({ category: 'ovo' })
    expect(estimateMacros('omelete')).toMatchObject({ category: 'ovo' })
    expect(estimateMacros('ovo de codorna')).toMatchObject({ category: 'ovo' })
    expect(estimateMacros('azeite')).toMatchObject({ category: 'gordura_pura', kcal: 884, fat: 100 })
    expect(estimateMacros('azeite de oliva')).toMatchObject({ category: 'gordura_pura', kcal: 884 })
    expect(estimateMacros('fio de azeite')).toMatchObject({ category: 'gordura_pura', kcal: 884 })
    expect(estimateMacros('colher de sopa de azeite')).toMatchObject({ category: 'gordura_pura', kcal: 884 })
    expect(estimateMacros('óleo de coco')).toMatchObject({ category: 'gordura_pura', kcal: 884 })
    expect(estimateMacros('manteiga')).toMatchObject({ category: 'gordura_pura', kcal: 726 })
    expect(estimateMacros('whey')).toMatchObject({ category: 'whey', protein: 78 })
    expect(estimateMacros('whey protein isolado')).toMatchObject({ category: 'whey' })
    // Composed foods keep their own category.
    expect(estimateMacros('macarrão com ovos').category).toBe('massa')
    expect(estimateMacros('pão com manteiga').category).toBe('panificação')
    expect(estimateMacros('arroz com azeite').category).toBe('arroz')
    expect(estimateMacros('bolo de ovos').category).toBe('doce')
    expect(estimateMacros('leite com whey').category).toBe('laticineo')
    // A chocolate egg is not an egg; an olive is not oil.
    expect(estimateMacros('ovo de páscoa').category).not.toBe('ovo')
    expect(estimateMacros('azeitona').category).toBe('prato_genérico')
  })

  // Adversarial review, 2026-10-04: a dish that merely mentions the fat or
  // the powder must never be priced as pure fat or pure powder.
  it('a dish cooked in fat, a bean variety or a ready drink is not pure fat or powder', () => {
    for (const dish of [
      'legumes salteados no azeite',
      'legumes na manteiga',
      'legumes amanteigados',
      'abóbora manteiga',
      'feijão manteiga',
      'salada com azeite',
      'refogado no azeite',
      'quinoa no azeite',
      'shake de whey',
      'vitamina de whey',
      'whey pronto',
      'barra de whey',
    ]) {
      const estimate = estimateMacros(dish)
      expect(estimate.category, dish).not.toBe('gordura_pura')
      expect(estimate.category, dish).not.toBe('whey')
      expect(estimate.kcal, dish).toBeLessThanOrEqual(300)
    }
  })
})

// ───────────────────────────── F14 — Flow menu ─────────────────────────────

const input: DietGeneratorInput = {
  userId: 'qa-a',
  identity: 'flow',
  profile: {
    name: null,
    sex: 'masculino',
    age: null,
    weight_kg: 80.5,
    height_cm: 185,
    activity_level: 'moderado',
    protocol: 'ganho_massa',
    meta_kcal: 2980,
    meta_protein_g: 144.9,
    bf_percent: null,
    restrictions: [],
    preferences: [],
  },
  historical_foods: [],
}

function output(kcal: number, protein: number, quoteNumbers = false): string {
  const number = (value: number) => (quoteNumbers ? String(value) : value)
  const meals = ['cafe', 'almoco', 'lanche_tarde', 'jantar'].map((meal_type) => ({
    meal_type,
    items: [
      {
        food_name: 'alimento de teste',
        quantity_g: number(100),
        kcal: number(kcal / 4),
        protein_g: number(protein / 4),
        carbs_g: number(1),
        fat_g: number(1),
      },
    ],
    total_kcal: kcal / 4,
    total_protein_g: protein / 4,
  }))
  return JSON.stringify({ daily_meals: meals, shopping_list: [] })
}

function harness(responses: string[]) {
  const calls: Array<{ messages: Array<{ content: unknown }> }> = []
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const llm = {
    complete: async (params: { messages: Array<{ content: unknown }> }) => {
      calls.push(params)
      return { content: responses[calls.length - 1], model: 'mock', finishReason: 'stop' }
    },
  } as unknown as OpenRouterLLM
  const supabase = {
    from: () => ({
      insert: async (event: { event: string; properties: Record<string, unknown> }) => {
        events.push(event)
        return { error: null }
      },
    }),
  } as unknown as ServiceClient
  return { llm, supabase, calls, events }
}

describe('audit 2026-10-04 — Flow menu: numbers written between quotes', () => {
  it('accepts the first answer whose item numbers came as strings (the exact refused paths)', async () => {
    const h = harness([output(2980, 144.8, true), output(2980, 144.9)])
    const plan = await generateDietPlan(h.llm, h.supabase, input)
    expect(plan).not.toBeNull()
    expect(h.calls).toHaveLength(1)
    expect(h.events).toHaveLength(0)
    const first = plan!.daily_meals[0]!.items[0]!
    expect(first).toMatchObject({ quantity_g: 100, kcal: 745, protein_g: 36.2, carbs_g: 1, fat_g: 1 })
  })

  it('reads only strings that are nothing but a number; the value is never changed', () => {
    const shaped = normalizeGeneratedDiet({
      daily_meals: [
        {
          meal_type: 'almoco',
          total_kcal: '650',
          total_protein_g: '45,5',
          items: [
            { food_name: 'a', quantity_g: ' 150 ', kcal: '195.5', protein_g: '4', carbs_g: '42,1', fat_g: '0.4' },
            { food_name: 'b', quantity_g: '150 g', kcal: 'aprox. 30', protein_g: '', carbs_g: '1,500', fat_g: '-1' },
            { food_name: '3', quantity_g: '1.500', kcal: '1e3', protein_g: '12.', carbs_g: '.5', fat_g: '9'.repeat(400) },
          ],
        },
      ],
      shopping_list: [{ category: 'outros', food_name: 'a', quantity_g: '300' }],
    }) as { daily_meals: Array<Record<string, unknown> & { items: Array<Record<string, unknown>> }>; shopping_list: Array<Record<string, unknown>> }
    const meal = shaped.daily_meals[0]!
    expect(meal.total_kcal).toBe(650)
    expect(meal.total_protein_g).toBe(45.5)
    expect(meal.items[0]).toMatchObject({ quantity_g: 150, kcal: 195.5, protein_g: 4, carbs_g: 42.1, fat_g: 0.4 })
    // Not plain numbers: left as written, so the schema still refuses them.
    expect(meal.items[1]).toMatchObject({ quantity_g: '150 g', kcal: 'aprox. 30', protein_g: '', carbs_g: '1,500', fat_g: '-1' })
    // Ambiguous or not a plain number: "1.500" may be a thousand.
    expect(meal.items[2]).toMatchObject({ food_name: '3', quantity_g: '1.500', kcal: '1e3', protein_g: '12.', carbs_g: '.5' })
    expect(typeof meal.items[2]!.fat_g).toBe('string')
    expect(shaped.shopping_list[0]!.quantity_g).toBe(300)
  })

  it('still refuses a quantity that is not a number, with the path, and retries once', async () => {
    const bad = JSON.parse(output(2980, 144.9)) as { daily_meals: Array<{ items: Array<Record<string, unknown>> }> }
    bad.daily_meals[0]!.items[0]!.quantity_g = '150 g'
    const h = harness([JSON.stringify(bad), output(2980, 144.9)])
    expect(await generateDietPlan(h.llm, h.supabase, input)).not.toBeNull()
    expect(h.calls).toHaveLength(2)
    expect(h.events[0]?.properties.reason).toBe('zod_validation_failed')
    expect(String(h.calls[1]?.messages[0]?.content)).toContain('daily_meals.0.items.0.quantity_g')
  })
})

describe('audit 2026-10-04 — Flow menu: 200 g of protein against 144.9 g', () => {
  it('states the ceiling up front and tells the retry what to change', async () => {
    const h = harness([output(2980, 200), output(2980, 144.9)])
    const plan = await generateDietPlan(h.llm, h.supabase, input)
    expect(plan).not.toBeNull()
    expect(h.calls).toHaveLength(2)
    const first = String(h.calls[0]?.messages[0]?.content)
    expect(first).toContain('entre 116 e 173 g de proteína')
    expect(first).toContain('NÃO pode passar de 173 g')
    expect(first).toContain('complete as calorias com carboidratos e gorduras')
    const retry = String(h.calls[1]?.messages[0]?.content)
    expect(retry).toContain('200 g vs meta 144.9 g')
    expect(retry).toContain('38%')
    expect(retry).toContain('reduza as porções das fontes de proteína')
    expect(h.events[0]?.properties).toMatchObject({ reason: 'protein_drift_exceeded', day_protein_g: 200, drift_pct: 38 })
  })

  // The recorded sequence: answer 1 had quoted numbers (refused then, read
  // now); answer 2 had 200 g. With quoted numbers read, an answer 1 that
  // also carries 200 g is refused for protein and the retry is told so.
  it('quoted numbers AND 200 g in the first answer: the retry is about protein, not about types', async () => {
    const h = harness([output(2980, 200, true), output(2980, 144.9)])
    expect(await generateDietPlan(h.llm, h.supabase, input)).not.toBeNull()
    expect(h.calls).toHaveLength(2)
    expect(h.events.map((event) => event.properties.reason)).toEqual(['protein_drift_exceeded'])
    const retry = String(h.calls[1]?.messages[0]?.content)
    expect(retry).toContain('200 g vs meta 144.9 g')
    expect(retry).not.toContain('Expected number')
  })

  it('the accepted window itself is unchanged: 200 g twice is still refused', async () => {
    const h = harness([output(2980, 200), output(2980, 200)])
    expect(await generateDietPlan(h.llm, h.supabase, input)).toBeNull()
    expect(h.calls).toHaveLength(2)
  })

  it('too little protein is told to go up, not down', async () => {
    const h = harness([output(2980, 100), output(2980, 144.9)])
    expect(await generateDietPlan(h.llm, h.supabase, input)).not.toBeNull()
    expect(String(h.calls[1]?.messages[0]?.content)).toContain('aumente as porções das fontes de proteína')
  })

  it('the WhatsApp generator keeps its single call and its prompt', async () => {
    const h = harness([output(2980, 200), output(2980, 144.9)])
    expect(await generateDietPlan(h.llm, h.supabase, { ...input, identity: 'legacy' })).toBeNull()
    expect(h.calls).toHaveLength(1)
    expect(String(h.calls[0]?.messages[0]?.content)).not.toContain('NÃO pode passar de')
  })
})
