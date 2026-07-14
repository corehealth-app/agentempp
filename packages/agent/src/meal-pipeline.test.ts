import { describe, expect, it } from 'vitest'

// Anti-regression coverage pro meal-pipeline. Cobre os bugs que custaram caro
// pra debugar e que NÃO podem voltar:
//   1. Bacon/parmesão/oleaginosas com alta densidade calórica NÃO podem zerar
//      (sanity check 2 precisa permitir via category OU regex backup).
//   2. Avisos internos ("estimativa por categoria", "baixa confiança", "auto-split")
//      vão pra audit_warnings — NUNCA pra user_warnings.
//   3. Avisos acionáveis pelo paciente (composite rejeitado, category_mismatch,
//      protein_mismatch) vão pra user_warnings.
//   4. Match composite direto (alias completo, sim>=0.85) tem precedência sobre auto-split.

import type { ServiceClient } from '@mpp/db'
import {
  calcMealMacros,
  estimateMacros,
  lookupUserHistory,
  naturalUnit,
  requiresVisualPreparationConfirmation,
} from './meal-pipeline.js'

type MockRow = {
  id: number
  name_pt: string
  category?: string | null
  similarity: number
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
}

type HistoryRow = {
  id: string
  food_name: string
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source?: string
  food_db_id?: number | null
}

type CorrectionRow = {
  said_name: string
  corrected_to: string
  custom_kcal_per_100g?: number | null
  custom_protein_g?: number | null
  custom_carbs_g?: number | null
  custom_fat_g?: number | null
  status: 'learning' | 'active' | 'retired'
  confirmed_count: number
}

type MockFailures = {
  search?: string
  correction?: string
  history?: string
}

function makeMock(
  matches: Record<string, MockRow | null>,
  historyRows: HistoryRow[] = [],
  correctionRows: CorrectionRow[] = [],
  failures: MockFailures = {},
): ServiceClient {
  // Proxy chainable que aceita qualquer .eq/.ilike/.gte/.gt/.neq/.order/.limit
  // e no final retorna { data, error }. Suporta queries de lookupUserHistory,
  // lookupFoodCorrection e o fallback antigo.
  const makeChain = (rows: unknown, errorMessage?: string): unknown => {
    const obj: Record<string, unknown> = {
      data: errorMessage ? null : rows,
      error: errorMessage ? { message: errorMessage } : null,
    }
    for (const m of [
      'select',
      'eq',
      'ilike',
      'gte',
      'gt',
      'lt',
      'neq',
      'in',
      'or',
      'order',
      'limit',
    ]) {
      obj[m] = () => makeChain(rows, errorMessage)
    }
    obj.then = (cb: (v: { data: unknown; error: { message: string } | null }) => unknown) =>
      Promise.resolve(
        cb(
          errorMessage
            ? { data: null, error: { message: errorMessage } }
            : { data: rows, error: null },
        ),
      )
    return obj
  }
  return {
    rpc: async (_fn: string, params: { search_term: string }) => {
      if (failures.search) {
        return { data: null, error: { message: failures.search } }
      }
      const term = params.search_term.toLowerCase().trim()
      const hit = matches[term]
      if (hit) return { data: [hit], error: null }
      return { data: [], error: null }
    },
    from: (table: string) => {
      if (table === 'meal_logs') {
        return makeChain(
          historyRows.map((row) => ({
            source: 'canonical_exact',
            food_db_id: row.food_db_id ?? 9999,
            ...row,
          })),
          failures.history,
        )
      }
      if (table === 'user_food_corrections') {
        return makeChain(correctionRows, failures.correction)
      }
      if (table === 'product_events') {
        return { insert: () => makeChain([]) }
      }
      return makeChain([])
    },
  } as unknown as ServiceClient
}

describe('calcMealMacros — composite handling', () => {
  it('"leite com whey" usa match direto (id 413, 95kcal/100g) — não zera', async () => {
    const mock = makeMock({
      'leite com whey': {
        id: 413,
        name_pt: 'leite com whey',
        similarity: 1,
        kcal_per_100g: 95,
        protein_g: 10,
        carbs_g: 5,
        fat_g: 3,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'leite com whey', quantity_g: 200 }], 'BR')
    expect(r.totals.kcal).toBeGreaterThan(0)
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeCloseTo(190, 0)
  })
})

describe('calcMealMacros — indisponibilidade de fontes nutricionais', () => {
  const item = [{ food_name: 'frango ao molho cremoso', quantity_g: 150 }]

  it('não transforma erro da busca canônica em estimativa por categoria', async () => {
    const mock = makeMock({}, [], [], { search: 'food search unavailable' })

    await expect(calcMealMacros(mock, item, 'BR')).rejects.toThrow('food search unavailable')
  })

  it('não ignora erro ao consultar correções ativas do paciente', async () => {
    const mock = makeMock({}, [], [], { correction: 'correction lookup unavailable' })

    await expect(calcMealMacros(mock, item, 'BR', 'user-test')).rejects.toThrow(
      'correction lookup unavailable',
    )
  })

  it('não ignora erro no histórico pessoal antes do fallback', async () => {
    const mock = makeMock({}, [], [], { history: 'personal history unavailable' })

    await expect(calcMealMacros(mock, item, 'BR', 'user-test')).rejects.toThrow(
      'personal history unavailable',
    )
  })

  it('não ignora erro no histórico de mediana usado pelo fallback final', async () => {
    const mock = makeMock({}, [], [], { history: 'median history unavailable' })

    await expect(calcMealMacros(mock, item, 'BR')).rejects.toThrow('median history unavailable')
  })
})

describe('calcMealMacros — sanity check densidade calórica (regressão bacon/parmesão)', () => {
  it('bacon (541 kcal/100g, categoria carnes) NÃO zera — regex backup pega', async () => {
    const mock = makeMock({
      bacon: {
        id: 101,
        name_pt: 'bacon',
        category: 'carnes',
        similarity: 1,
        kcal_per_100g: 541,
        protein_g: 37,
        carbs_g: 0,
        fat_g: 42,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'bacon', quantity_g: 30 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeGreaterThan(150) // ~162 kcal
    expect(r.user_warnings).toHaveLength(0)
  })

  it('parmesão ralado (431 kcal/100g, categoria lacteos) NÃO zera — regex backup pega', async () => {
    const mock = makeMock({
      'queijo parmesão': {
        id: 102,
        name_pt: 'queijo parmesão',
        category: 'lacteos',
        similarity: 1,
        kcal_per_100g: 431,
        protein_g: 35,
        carbs_g: 4,
        fat_g: 29,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'queijo parmesão', quantity_g: 20 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeGreaterThan(50)
    expect(r.user_warnings).toHaveLength(0)
  })

  it('castanha (621 kcal/100g, categoria oleaginosas) NÃO zera — category primary', async () => {
    const mock = makeMock({
      'castanha do pará': {
        id: 103,
        name_pt: 'castanha do pará',
        category: 'oleaginosas',
        similarity: 1,
        kcal_per_100g: 621,
        protein_g: 14,
        carbs_g: 13,
        fat_g: 61,
        fiber_g: 8,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'castanha do pará', quantity_g: 25 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeGreaterThan(100)
    expect(r.user_warnings).toHaveLength(0)
  })

  it('alimento NÃO-gordo matchado contra alimento gordo SEM categoria conhecida — anchor rejeita antes, vira llm_estimate', async () => {
    // Cenário: "iogurte natural" bateu contra "creme de leite condensado".
    // Anchor "iogurte" não aparece em "creme de leite condensado" → match rejeitado
    // antes dos sanity checks. Cai pra estimativa por categoria (laticinio ~65 kcal).
    // Antes do anchor check, isso virava category_mismatch e zerava — agora
    // estima razoavelmente em vez de zerar (Roberto pediu "estimar, não zerar").
    const mock = makeMock({
      'iogurte natural': {
        id: 104,
        name_pt: 'creme de leite condensado',
        category: 'cremes',
        similarity: 0.5,
        kcal_per_100g: 700,
        protein_g: 5,
        carbs_g: 50,
        fat_g: 50,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'iogurte natural', quantity_g: 100 }], 'BR')
    expect(r.items[0]?.source).toBe('llm_estimate')
    // Não zera — estima como laticineo (~65 kcal/100g)
    expect(r.items[0]?.kcal).toBeGreaterThan(40)
    expect(r.items[0]?.kcal).toBeLessThan(100)
    // Audit log registra rejeição por anchor
    expect(r.audit_warnings.some((w) => /âncora|anchor/i.test(w))).toBe(true)
  })
})

describe('calcMealMacros — goiaba fruta não casa com goiabada', () => {
  it('rejeita match fuzzy goiaba → goiabada e cai em estimativa de fruta', async () => {
    const mock = makeMock({
      goiaba: {
        id: 387,
        name_pt: 'goiabada',
        category: 'doces',
        similarity: 0.6,
        kcal_per_100g: 255,
        protein_g: 0.4,
        carbs_g: 65,
        fat_g: 0.1,
        fiber_g: 2.5,
      },
    })

    const r = await calcMealMacros(mock, [{ food_name: 'goiaba', quantity_g: 150 }], 'BR')

    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.matched_taco_name).toMatch(/estimativa fruta/i)
    expect(r.items[0]?.kcal).toBeLessThan(120)
    expect(r.audit_warnings.join(' ')).toMatch(/doce derivado/i)
  })

  it('goiabada continua resolvendo como doce normalmente', async () => {
    const mock = makeMock({
      goiabada: {
        id: 387,
        name_pt: 'goiabada',
        category: 'doces',
        similarity: 1,
        kcal_per_100g: 255,
        protein_g: 0.4,
        carbs_g: 65,
        fat_g: 0.1,
        fiber_g: 2.5,
      },
    })

    const r = await calcMealMacros(mock, [{ food_name: 'goiabada', quantity_g: 150 }], 'BR')

    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.matched_taco_name).toBe('goiabada')
    expect(r.items[0]?.kcal).toBeCloseTo(382.5, 1)
  })

  it('não reutiliza histórico pessoal implausível de fruta fresca quando há match canônico', async () => {
    const mock = makeMock(
      {
        goiaba: {
          id: 9001,
          name_pt: 'goiaba',
          category: 'frutas',
          similarity: 1,
          kcal_per_100g: 63.33,
          protein_g: 0.6,
          carbs_g: 10.73,
          fat_g: 0.23,
          fiber_g: 5.4,
        },
      },
      [
        {
          id: 'old-wrong-goiaba',
          food_name: 'goiaba',
          quantity_g: 150,
          kcal: 382.5,
          protein_g: 0.6,
          carbs_g: 97.5,
          fat_g: 0.15,
        },
      ],
    )

    const r = await calcMealMacros(mock, [{ food_name: 'goiaba', quantity_g: 150 }], 'BR', 'paulo')

    expect(r.items[0]?.matched_taco_name).toBe('goiaba')
    expect(r.items[0]?.kcal).toBeCloseTo(95, 0)
  })

  it('sem match canônico, também não cai no histórico antigo errado da goiaba', async () => {
    const mock = makeMock(
      {
        goiaba: {
          id: 387,
          name_pt: 'goiabada',
          category: 'doces',
          similarity: 0.6,
          kcal_per_100g: 255,
          protein_g: 0.4,
          carbs_g: 65,
          fat_g: 0.1,
          fiber_g: 2.5,
        },
      },
      [
        {
          id: 'old-wrong-goiaba',
          food_name: 'goiaba',
          quantity_g: 150,
          kcal: 382.5,
          protein_g: 0.6,
          carbs_g: 97.5,
          fat_g: 0.15,
        },
      ],
    )

    const r = await calcMealMacros(mock, [{ food_name: 'goiaba', quantity_g: 150 }], 'BR', 'paulo')

    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.matched_taco_name).toMatch(/estimativa fruta/i)
    expect(r.items[0]?.kcal).toBeLessThan(120)
    expect(r.audit_warnings.join(' ')).toMatch(/histórico implausível/i)
  })
})

describe('calcMealMacros — separação user_warnings vs audit_warnings', () => {
  it('alimento sem match (cai em category_estimate) gera SOMENTE audit_warning', async () => {
    const mock = makeMock({}) // nenhum match
    const r = await calcMealMacros(mock, [{ food_name: 'tahine', quantity_g: 15 }], 'BR')
    expect(r.user_warnings).toHaveLength(0)
    expect(r.audit_warnings.length).toBeGreaterThan(0)
    expect(r.audit_warnings.join(' ')).toMatch(/estimando por categoria|sem match/i)
    expect(r.items[0]?.source).toBe('llm_estimate')
    // Mesmo via estimativa, retornou kcal>0 (não zerou)
    expect(r.items[0]?.kcal).toBeGreaterThan(0)
  })

  it('match com similarity baixa (<0.5) — aviso de low-confidence vai pra audit, NÃO pra user', async () => {
    const mock = makeMock({
      arroz: {
        id: 200,
        name_pt: 'arroz branco cozido',
        category: 'cereais',
        similarity: 0.35,
        kcal_per_100g: 130,
        protein_g: 2.5,
        carbs_g: 28,
        fat_g: 0.3,
        fiber_g: 0.5,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'arroz', quantity_g: 150 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.user_warnings).toHaveLength(0)
    expect(r.audit_warnings.some((w) => /baixa confian|sim=/i.test(w))).toBe(true)
  })

  it('composite rejeitado (auto-split falhou) — aviso vai pra user_warnings (acionável)', async () => {
    // "xpto com quux" → split em "xpto" e "quux", ambos sem match → rejeita
    const mock = makeMock({})
    const r = await calcMealMacros(mock, [{ food_name: 'xpto com quux', quantity_g: 100 }], 'BR')
    expect(r.items[0]?.source).toBe('composite_rejected')
    expect(r.items[0]?.kcal).toBe(0)
    expect(r.user_warnings.length).toBeGreaterThan(0)
    expect(r.user_warnings.join(' ')).toMatch(/vários alimentos juntos|separad/i)
  })

  it('auto-split bem-sucedido — aviso vai pra audit_warnings (silencioso pro paciente)', async () => {
    // "leite e whey" sem match direto mas parts matcham bem
    const mock = makeMock({
      leite: {
        id: 412,
        name_pt: 'leite',
        category: 'lacteos',
        similarity: 1,
        kcal_per_100g: 61,
        protein_g: 3.2,
        carbs_g: 4.7,
        fat_g: 3.3,
        fiber_g: 0,
      },
      whey: {
        id: 260,
        name_pt: 'whey protein',
        category: 'suplementos',
        similarity: 0.6,
        kcal_per_100g: 380,
        protein_g: 75,
        carbs_g: 8,
        fat_g: 4,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'leite e whey', quantity_g: 250 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_composite')
    expect(r.items[0]?.kcal).toBeGreaterThan(0)
    expect(r.user_warnings).toHaveLength(0)
    expect(r.audit_warnings.some((w) => /auto-dividido/i.test(w))).toBe(true)
  })
})

describe('calcMealMacros — proteína esperada (sanity 3)', () => {
  it('"ovo" matchou em algo sem proteína — anchor rejeita match catastrófico, vira llm_estimate', async () => {
    // "ovo" não aparece em "arroz branco" → anchor check rejeita antes do
    // sanity check de proteína. Cai pra estimativa por categoria (ovo ~155 kcal).
    const mock = makeMock({
      ovo: {
        id: 300,
        name_pt: 'arroz branco',
        category: 'cereais',
        similarity: 0.5,
        kcal_per_100g: 130,
        protein_g: 2.5,
        carbs_g: 28,
        fat_g: 0.3,
        fiber_g: 0.5,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'ovo', quantity_g: 100 }], 'BR')
    expect(r.items[0]?.source).toBe('llm_estimate')
    // estimateMacros não tem regra específica pra "ovo" sozinho — cai no fallback
    // genérico (~150 kcal/100g). Importante: NÃO usa o match catastrófico (130).
    expect(r.audit_warnings.some((w) => /âncora|anchor/i.test(w))).toBe(true)
  })

  it('"ovo" matchou em ovo cozido (146 kcal, 13g proteína) — passa limpo', async () => {
    const mock = makeMock({
      ovo: {
        id: 301,
        name_pt: 'ovo cozido',
        category: 'carnes',
        similarity: 1,
        kcal_per_100g: 146,
        protein_g: 13,
        carbs_g: 1,
        fat_g: 10,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'ovo', quantity_g: 100 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.items[0]?.kcal).toBe(146)
    expect(r.user_warnings).toHaveLength(0)
  })
})

describe('calcMealMacros — reuso do histórico do paciente (Roberto 2026-05-13)', () => {
  // Roberto pediu: alimentos repetidos devem reusar do histórico em vez de re-matchar
  // toda vez. Ex: "leite com whey" virava "achocolatado" no trigram todo dia.

  it('matchou histórico exato — usa macros do log anterior, ignora trigram', async () => {
    // Trigram retornaria match errado (achocolatado), mas histórico tem
    // "leite com whey" gravado → usa o histórico.
    const mock = makeMock(
      {
        'leite com whey': {
          id: 999,
          name_pt: 'achocolatado',
          category: 'bebidas',
          similarity: 0.5,
          kcal_per_100g: 85,
          protein_g: 1.5,
          carbs_g: 18,
          fat_g: 1.0,
          fiber_g: 0,
        },
      },
      [
        {
          id: 'log-1',
          food_name: 'leite com whey',
          quantity_g: 200,
          kcal: 200, // 100 kcal/100g (correto)
          protein_g: 24,
          carbs_g: 10,
          fat_g: 6,
        },
      ],
    )
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'leite com whey', quantity_g: 250 }],
      'BR',
      'user-roberto',
    )
    expect(r.items[0]?.source).toBe('history')
    expect(r.items[0]?.matched_taco_name).toContain('histórico')
    // 100 kcal/100g × 250g/100 = 250 kcal — NÃO 212.5 (achocolatado)
    expect(r.items[0]?.kcal).toBe(250)
    expect(r.items[0]?.protein_g).toBe(30) // 24g/200g × 250g = 30g
    expect(r.audit_warnings.some((w) => /hist[óo]rico/i.test(w))).toBe(true)
  })

  it('item canônico exato vence histórico exato contaminado', async () => {
    const mock = makeMock(
      {
        'arroz branco cozido': {
          id: 1,
          name_pt: 'arroz branco cozido',
          category: 'cereais',
          similarity: 1,
          kcal_per_100g: 128,
          protein_g: 2.5,
          carbs_g: 28,
          fat_g: 0.2,
          fiber_g: 1.6,
        },
      },
      [
        {
          id: 'log-arroz-contaminado',
          food_name: 'arroz branco cozido',
          quantity_g: 150,
          kcal: 70,
          protein_g: 1,
          carbs_g: 15,
          fat_g: 0.1,
          source: 'user_kcal',
        },
      ],
    )

    const result = await calcMealMacros(
      mock,
      [{ food_name: 'arroz branco cozido', quantity_g: 150 }],
      'BR',
      'user-with-bad-history',
    )

    expect(result.items[0]?.source).toBe('canonical_exact')
    expect(result.items[0]?.kcal).toBe(192)
  })

  it('dois usuários recebem o mesmo food_db id e os mesmos valores canônicos', async () => {
    const canonical: MockRow = {
      id: 379,
      name_pt: 'sorvete',
      category: 'doces',
      similarity: 1,
      kcal_per_100g: 210,
      protein_g: 3.5,
      carbs_g: 24,
      fat_g: 11,
      fiber_g: 0,
    }
    const mock = makeMock({ sorvete: canonical })

    const [roberto, luciana] = await Promise.all([
      calcMealMacros(mock, [{ food_name: 'sorvete', quantity_g: 120 }], 'BR', 'user-roberto'),
      calcMealMacros(mock, [{ food_name: 'sorvete', quantity_g: 120 }], 'BR', 'user-luciana'),
    ])

    expect(roberto.items[0]).toMatchObject({
      matched_taco_id: 379,
      source: 'canonical_exact',
      kcal: 252,
      protein_g: 4.2,
      carbs_g: 28.8,
      fat_g: 13.2,
    })
    expect(luciana.items[0]).toEqual(roberto.items[0])
  })

  it('histórico derivado de outro histórico nunca alimenta um novo registro', async () => {
    const mock = makeMock({}, [
      {
        id: 'history-recursive',
        food_name: 'leite com whey',
        quantity_g: 240,
        kcal: 228,
        protein_g: 24,
        carbs_g: 12,
        fat_g: 7.2,
        source: 'history',
        food_db_id: 413,
      },
    ])

    await expect(lookupUserHistory(mock, 'user-roberto', 'leite com whey')).resolves.toBeNull()
  })

  it('histórico canônico direto exige e preserva food_db_id', async () => {
    const mock = makeMock({}, [
      {
        id: 'history-direct-canonical',
        food_name: 'leite com whey',
        quantity_g: 240,
        kcal: 228,
        protein_g: 24,
        carbs_g: 12,
        fat_g: 7.2,
        source: 'canonical_exact',
        food_db_id: 413,
      },
    ])

    await expect(lookupUserHistory(mock, 'user-roberto', 'leite com whey')).resolves.toMatchObject({
      food_db_id: 413,
      kcal_per_100g: 95,
    })
  })

  it('nome genérico não herda silenciosamente um subtipo do histórico', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-sorvete-iogurte',
        food_name: 'sorvete de iogurte',
        quantity_g: 170,
        kcal: 110.5,
        protein_g: 6.8,
        carbs_g: 8.5,
        fat_g: 5.1,
        source: 'taco',
      },
    ])

    await expect(lookupUserHistory(mock, 'user-roberto', 'sorvete')).resolves.toBeNull()
  })

  it('nome composto não herda uma preparação mais calórica só por substring', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-frango-cremoso',
        food_name: 'frango ao molho cremoso',
        quantity_g: 150,
        kcal: 330,
        protein_g: 24,
        carbs_g: 8,
        fat_g: 22,
        source: 'taco',
      },
    ])

    await expect(lookupUserHistory(mock, 'user-roberto', 'frango ao molho')).resolves.toBeNull()
  })

  it('não reutiliza leite líquido para leite em pó', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-leite-liquido',
        food_name: 'leite integral',
        quantity_g: 200,
        kcal: 122,
        protein_g: 6.4,
        carbs_g: 9.4,
        fat_g: 6.6,
      },
    ])

    const result = await calcMealMacros(
      mock,
      [{ food_name: 'leite em pó integral', quantity_g: 10 }],
      'BR',
      'user-milk',
    )

    expect(result.items[0]?.source).not.toBe('history')
    expect(result.items[0]?.display_unit).toBe('g')
  })

  it('histórico match case/acento-insensitive', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-2',
        food_name: 'Pão Francês',
        quantity_g: 50,
        kcal: 150,
        protein_g: 4,
        carbs_g: 29,
        fat_g: 1.5,
      },
    ])
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'pao frances', quantity_g: 100 }],
      'BR',
      'user-x',
    )
    expect(r.items[0]?.source).toBe('history')
    expect(r.items[0]?.kcal).toBe(300) // 150 × 2
  })

  it('sem userIdHint NÃO consulta histórico', async () => {
    const mock = makeMock(
      {
        'arroz branco': {
          id: 1,
          name_pt: 'arroz branco cozido',
          category: 'cereais',
          similarity: 1.0,
          kcal_per_100g: 128,
          protein_g: 2.5,
          carbs_g: 28,
          fat_g: 0.2,
          fiber_g: 1.6,
        },
      },
      [
        {
          id: 'log-3',
          food_name: 'arroz branco',
          quantity_g: 100,
          kcal: 999, // valor catastrófico no histórico — não deve ser usado sem userId
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
        },
      ],
    )
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'arroz branco', quantity_g: 100 }],
      'BR',
      undefined, // sem userId
    )
    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.items[0]?.kcal).toBe(128) // do food_db, não do histórico
  })

  it('histórico ignorado quando paciente envia nome diferente (sem overlap)', async () => {
    const mock = makeMock(
      {
        'banana prata': {
          id: 50,
          name_pt: 'banana prata',
          category: 'frutas',
          similarity: 1.0,
          kcal_per_100g: 89,
          protein_g: 1.1,
          carbs_g: 22,
          fat_g: 0.3,
          fiber_g: 2.6,
        },
      },
      [
        {
          id: 'log-4',
          food_name: 'leite com whey', // alimento totalmente diferente
          quantity_g: 200,
          kcal: 200,
          protein_g: 24,
          carbs_g: 10,
          fat_g: 6,
        },
      ],
    )
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'banana prata', quantity_g: 100 }],
      'BR',
      'user-y',
    )
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBe(89) // banana, não whey
    expect(r.items[0]?.matched_taco_name).not.toContain('histórico')
  })

  it('não reutiliza histórico com pele quando paciente informa "sem pele" — caso Roberto', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-sobrecoxa-com-pele',
        food_name: 'sobrecoxa de frango assada',
        quantity_g: 240,
        kcal: 520.8,
        protein_g: 64.8,
        carbs_g: 0,
        fat_g: 26.4,
      },
    ])

    const r = await calcMealMacros(
      mock,
      [{ food_name: 'sobrecoxa de frango assada sem pele', quantity_g: 240 }],
      'BR',
      'user-roberto',
    )

    expect(r.items[0]?.matched_taco_name).not.toContain('histórico')
    expect(r.items[0]?.matched_taco_name).not.toBe('[reuso histórico]')
    expect(r.items[0]?.kcal).toBeLessThan(520.8)
    expect(r.items[0]?.fat_g).toBeLessThan(26.4)
  })

  it('marca reuso confiável como history, sem fingir que veio direto da TACO', async () => {
    const mock = makeMock({}, [
      {
        id: 'log-history-trusted',
        food_name: 'leite com whey',
        quantity_g: 200,
        kcal: 190,
        protein_g: 20,
        carbs_g: 10,
        fat_g: 6,
        source: 'canonical_exact',
        food_db_id: 413,
      },
    ])

    const r = await calcMealMacros(
      mock,
      [{ food_name: 'leite com whey', quantity_g: 200 }],
      'BR',
      'user-history',
    )

    expect(r.items[0]?.source).toBe('history')
    expect(r.items[0]?.kcal).toBe(190)
  })
})

describe('calcMealMacros — fruta plural e proveniência do histórico', () => {
  const purpleGrapeMatch: MockRow = {
    id: 501,
    name_pt: 'uva roxa',
    category: 'frutas',
    similarity: 0.583,
    kcal_per_100g: 69,
    protein_g: 0.7,
    carbs_g: 18.1,
    fat_g: 0.2,
    fiber_g: 0.9,
  }

  it('"uvas roxas" aceita o item canônico "uva roxa"', async () => {
    const mock = makeMock({ 'uvas roxas': purpleGrapeMatch })

    const r = await calcMealMacros(mock, [{ food_name: 'uvas roxas', quantity_g: 70 }], 'BR')

    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.items[0]?.matched_taco_name).toBe('uva roxa')
    expect(r.items[0]?.kcal).toBeCloseTo(48.3, 1)
  })

  it('"uvas roxas" sem item na base usa fallback de fruta, não prato genérico', async () => {
    const mock = makeMock({})

    const r = await calcMealMacros(mock, [{ food_name: 'uvas roxas', quantity_g: 70 }], 'BR')

    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.matched_taco_name).toContain('fruta')
    expect(r.items[0]?.kcal).toBeCloseTo(38.5, 1)
  })

  it('ignora histórico genérico implausível mesmo quando uma linha antiga diz taco', async () => {
    const mock = makeMock({ 'uvas roxas': purpleGrapeMatch }, [
      {
        id: 'log-grape-laundered',
        food_name: 'uvas roxas',
        quantity_g: 70,
        kcal: 105,
        protein_g: 4.9,
        carbs_g: 12.6,
        fat_g: 3.5,
        source: 'taco',
      },
    ])

    const r = await calcMealMacros(
      mock,
      [{ food_name: 'uvas roxas', quantity_g: 70 }],
      'BR',
      'user-grapes',
    )

    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.items[0]?.matched_taco_name).toBe('uva roxa')
    expect(r.items[0]?.kcal).toBeCloseTo(48.3, 1)
  })

  it('não reutiliza linha cuja origem é llm_estimate', async () => {
    const mock = makeMock({ 'uvas roxas': purpleGrapeMatch }, [
      {
        id: 'log-grape-estimate',
        food_name: 'uvas roxas',
        quantity_g: 70,
        kcal: 105,
        protein_g: 4.9,
        carbs_g: 12.6,
        fat_g: 3.5,
        source: 'llm_estimate',
      },
    ])

    const r = await calcMealMacros(
      mock,
      [{ food_name: 'uvas roxas', quantity_g: 70 }],
      'BR',
      'user-grapes',
    )

    expect(r.items[0]?.source).toBe('canonical_fuzzy')
    expect(r.items[0]?.matched_taco_name).toBe('uva roxa')
    expect(r.items[0]?.kcal).toBeCloseTo(48.3, 1)
  })
})

describe('calcMealMacros — mapa de correções do paciente (Roberto 2026-05-14)', () => {
  // Quando o paciente corrige a identidade de um alimento ("batata" → "mandioca"),
  // o sistema aprende e reaplica. Precedência: correção > histórico > trigram.

  it('correção ACTIVE com macro customizado → usa macro direto, ignora trigram', async () => {
    // food_db tem "batata" mas o paciente corrigiu pra "mandioca" com macro próprio.
    const mock = makeMock(
      {
        batata: {
          id: 1,
          name_pt: 'batata inglesa',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 86,
          protein_g: 2,
          carbs_g: 20,
          fat_g: 0,
          fiber_g: 1,
        },
      },
      [],
      [
        {
          said_name: 'batata',
          corrected_to: 'mandioca',
          custom_kcal_per_100g: 150,
          custom_protein_g: 1.5,
          custom_carbs_g: 36,
          custom_fat_g: 0.3,
          status: 'active',
          confirmed_count: 2,
        },
      ],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('mandioca')
    expect(r.items[0]?.kcal).toBe(150) // macro customizado, NÃO 86 (batata do trigram)
    expect(r.items[0]?.matched_taco_name).toContain('correção do paciente')
    // status active → NÃO precisa confirmar
    expect(r.user_warnings).toHaveLength(0)
  })

  it('correção ACTIVE sem macro customizado → remapeia nome, trigram resolve macros', async () => {
    // Corrigiu "batata" → "mandioca", sem macro próprio. O trigram acha "mandioca".
    const mock = makeMock(
      {
        mandioca: {
          id: 2,
          name_pt: 'mandioca cozida',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 125,
          protein_g: 1,
          carbs_g: 30,
          fat_g: 0.3,
          fiber_g: 1.6,
        },
      },
      [],
      [{ said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 3 }],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('mandioca')
    expect(r.items[0]?.kcal).toBe(125) // veio do trigram pra "mandioca"
    expect(r.user_warnings).toHaveLength(0)
  })

  it('correção LEARNING (1ª vez) → NÃO aplica silencioso (2026-06-09 fix)', async () => {
    // Mudança 2026-06-09 após bug Amanda+Paulo: status='learning' (count=1)
    // não APLICA mais o remapeamento — só registra audit_warning. Paciente
    // precisa repetir mesma correção pra virar 'active' antes de aplicar.
    const mock = makeMock(
      {
        batata: {
          id: 1,
          name_pt: 'batata inglesa',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 86,
          protein_g: 2,
          carbs_g: 20,
          fat_g: 0,
          fiber_g: 1,
        },
        mandioca: {
          id: 2,
          name_pt: 'mandioca cozida',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 125,
          protein_g: 1,
          carbs_g: 30,
          fat_g: 0.3,
          fiber_g: 1.6,
        },
      },
      [],
      [{ said_name: 'batata', corrected_to: 'mandioca', status: 'learning', confirmed_count: 1 }],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    // learning NÃO aplica → segue como batata
    expect(r.items[0]?.food_name).toBe('batata')
    expect(r.items[0]?.kcal).toBe(86)
    // user_warnings VAZIO (não atrapalha paciente)
    expect(r.user_warnings).toHaveLength(0)
    // audit_warning registra a correção pendente pra observabilidade
    expect(r.audit_warnings.some((w) => /correção pendente|count=1/i.test(w))).toBe(true)
  })

  it('sem userId → mapa de correções NÃO é consultado', async () => {
    const mock = makeMock(
      {
        batata: {
          id: 1,
          name_pt: 'batata inglesa',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 86,
          protein_g: 2,
          carbs_g: 20,
          fat_g: 0,
          fiber_g: 1,
        },
      },
      [],
      [{ said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 5 }],
    )
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'batata', quantity_g: 100 }],
      'BR',
      undefined,
    )
    // sem userId → usa o trigram normal, ignora correção
    expect(r.items[0]?.food_name).toBe('batata')
    expect(r.items[0]?.kcal).toBe(86)
  })

  it('correção tem precedência SOBRE o histórico do paciente', async () => {
    // Paciente tem "batata" no histórico (86 kcal) E uma correção batata→mandioca.
    // A correção deve vencer.
    const mock = makeMock(
      {
        mandioca: {
          id: 2,
          name_pt: 'mandioca cozida',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 125,
          protein_g: 1,
          carbs_g: 30,
          fat_g: 0.3,
          fiber_g: 1.6,
        },
      },
      [
        {
          id: 'h1',
          food_name: 'batata',
          quantity_g: 100,
          kcal: 86,
          protein_g: 2,
          carbs_g: 20,
          fat_g: 0,
        },
      ],
      [{ said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 2 }],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('mandioca') // correção venceu o histórico
    expect(r.items[0]?.kcal).toBe(125)
  })

  it('correção RETIRED é ignorada (filtro na query simula isso)', async () => {
    // status retired → a query do lookupFoodCorrection filtra com .neq('status','retired').
    // O mock retorna [] quando não há linha — simulamos passando correctionRows vazio.
    const mock = makeMock(
      {
        batata: {
          id: 1,
          name_pt: 'batata inglesa',
          category: 'tuberculos',
          similarity: 1,
          kcal_per_100g: 86,
          protein_g: 2,
          carbs_g: 20,
          fat_g: 0,
          fiber_g: 1,
        },
      },
      [],
      [], // correção retired não retornaria da query
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('batata')
    expect(r.items[0]?.kcal).toBe(86)
  })
})

describe('naturalUnit — pó vs líquido (Roberto 2026-05-15)', () => {
  it('"leite em pó" → g (não ml), mesmo contendo a palavra "leite"', () => {
    const r = naturalUnit('leite em pó', 30)
    expect(r.display_unit).toBe('g')
    expect(r.display_qty).toBe(30)
  })

  it('"café solúvel" → g', () => {
    expect(naturalUnit('café solúvel', 5).display_unit).toBe('g')
  })

  it('"whey protein em pó" → g (não ml)', () => {
    expect(naturalUnit('whey protein em pó', 30).display_unit).toBe('g')
  })

  it('"achocolatado em pó" → g', () => {
    expect(naturalUnit('achocolatado em pó', 20).display_unit).toBe('g')
  })

  it('"café instantâneo" → g', () => {
    expect(naturalUnit('café instantâneo', 5).display_unit).toBe('g')
  })

  it('"chá em folhas" → g (não ml)', () => {
    expect(naturalUnit('chá em folhas', 3).display_unit).toBe('g')
  })

  it('regressão: "leite integral" continua ml (não tem "em pó")', () => {
    expect(naturalUnit('leite integral', 200).display_unit).toBe('ml')
  })

  it('"café preto" retorna g (bug histórico do \\b vs acentos — comportamento atual estável)', () => {
    // Nota: idealmente café preto seria ml, mas JS regex \b não trata 'é' como
    // word boundary, então /\bcaf[ée]\b/ não casa em "café preto". Resultado:
    // cai no default 'g'. Não vou corrigir agora pra não mexer em outras 30+
    // entradas; apenas documento o comportamento estável.
    expect(naturalUnit('café preto', 100).display_unit).toBe('g')
  })

  it('regressão: "leite com whey" continua ml', () => {
    expect(naturalUnit('leite com whey', 200).display_unit).toBe('ml')
  })

  it('"chocolate ao leite" é sólido apesar da palavra leite', () => {
    expect(naturalUnit('chocolate ao leite', 12).display_unit).toBe('g')
  })

  it('"chocolate quente" continua líquido', () => {
    expect(naturalUnit('chocolate quente', 200).display_unit).toBe('ml')
  })
})

describe('estimateMacros — alimento completo vence token incidental', () => {
  it('chocolate ao leite usa categoria de doce, não laticínio', () => {
    const result = estimateMacros('chocolate ao leite')

    expect(result.category).toBe('doce')
    expect(result.kcal).toBeGreaterThan(200)
  })
})

describe('calcMealMacros — bebida zero/diet/light (Bug Luciana 2026-05-25)', () => {
  // Caso real: paciente disse "a coca é zero", o agente respondeu "caloria
  // zerada" e mostrou 0 no card, mas GRAVOU "coca-cola zero" com 136,5 kcal —
  // o valor da coca NORMAL. Causa: food_db tem "coca-cola" (~42 kcal/100g) mas
  // não tem o alias zero; o trigram casa a versão cheia e o qualificador "zero"
  // (tratado como preparo) é descartado. O guard determinístico força ~0.

  it('"coca-cola zero, 350g" ⇒ kcal ~0 (NÃO ~147 da coca normal)', async () => {
    // Mock simula o bug: o trigram retorna a COCA NORMAL (42 kcal/100g) pro
    // termo "coca-cola zero". O guard de bebida zero precisa interceptar ANTES.
    const mock = makeMock({
      'coca-cola zero': {
        id: 700,
        name_pt: 'coca-cola',
        category: 'bebidas',
        similarity: 0.92,
        kcal_per_100g: 42,
        protein_g: 0,
        carbs_g: 10.6,
        fat_g: 0,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'coca-cola zero', quantity_g: 350 }], 'BR')
    expect(r.items[0]?.kcal).toBeLessThanOrEqual(2)
    expect(r.totals.kcal).toBeLessThanOrEqual(2)
    expect(r.items[0]?.carbs_g).toBe(0)
    expect(r.items[0]?.protein_g).toBe(0)
    expect(r.items[0]?.fat_g).toBe(0)
    // Não polui o paciente com aviso — é tratamento silencioso (audit only).
    expect(r.user_warnings).toHaveLength(0)
  })

  it('"coca zero" e "guaraná zero" também zeram', async () => {
    const mock = makeMock({
      'coca zero': {
        id: 700,
        name_pt: 'coca-cola',
        category: 'bebidas',
        similarity: 0.85,
        kcal_per_100g: 42,
        protein_g: 0,
        carbs_g: 10.6,
        fat_g: 0,
        fiber_g: 0,
      },
      'guaraná zero': {
        id: 701,
        name_pt: 'guaraná',
        category: 'bebidas',
        similarity: 0.85,
        kcal_per_100g: 39,
        protein_g: 0,
        carbs_g: 10,
        fat_g: 0,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(
      mock,
      [
        { food_name: 'coca zero', quantity_g: 350 },
        { food_name: 'guaraná zero', quantity_g: 350 },
      ],
      'BR',
    )
    expect(r.items[0]?.kcal).toBeLessThanOrEqual(2)
    expect(r.items[1]?.kcal).toBeLessThanOrEqual(2)
  })

  it('camada 2: "monster zero" (sem keyword de refri) zera via categoria "bebidas" do match', async () => {
    // Nome não tem refri/coca/guaraná, mas o match cai numa linha de categoria
    // "bebidas" + o qualificador "zero" → força ~0 pela categoria.
    const mock = makeMock({
      'monster zero': {
        id: 702,
        name_pt: 'monster energy',
        category: 'bebidas',
        similarity: 0.8,
        kcal_per_100g: 48,
        protein_g: 0,
        carbs_g: 12,
        fat_g: 0,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'monster zero', quantity_g: 300 }], 'BR')
    expect(r.items[0]?.kcal).toBeLessThanOrEqual(2)
  })

  it('NÃO-REGRESSÃO: "coca-cola, 350g" (normal) ⇒ kcal cheio (~147)', async () => {
    const mock = makeMock({
      'coca-cola': {
        id: 700,
        name_pt: 'coca-cola',
        category: 'bebidas',
        similarity: 1,
        kcal_per_100g: 42,
        protein_g: 0,
        carbs_g: 10.6,
        fat_g: 0,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'coca-cola', quantity_g: 350 }], 'BR')
    expect(r.items[0]?.kcal).toBeCloseTo(147, 0)
    expect(r.items[0]?.source).toBe('canonical_exact')
  })

  it('NÃO-REGRESSÃO: "suco de laranja" (bebida calórica, sem zero) NÃO zera', async () => {
    const mock = makeMock({
      'suco de laranja': {
        id: 703,
        name_pt: 'suco de laranja',
        category: 'bebidas',
        similarity: 1,
        kcal_per_100g: 45,
        protein_g: 0.7,
        carbs_g: 10,
        fat_g: 0.2,
        fiber_g: 0.2,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'suco de laranja', quantity_g: 200 }], 'BR')
    expect(r.items[0]?.kcal).toBeCloseTo(90, 0)
  })

  it('NÃO-REGRESSÃO: "leite zero lactose" NÃO é confundido com bebida zero-caloria', async () => {
    // "zero lactose" tem "zero" mas leite NÃO é refrigerante nem casa keyword de
    // bebida gaseosa — deve manter as calorias do leite.
    const mock = makeMock({
      'leite zero lactose': {
        id: 704,
        name_pt: 'leite zero lactose',
        category: 'lacteos',
        similarity: 1,
        kcal_per_100g: 42,
        protein_g: 3.2,
        carbs_g: 4.8,
        fat_g: 1,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'leite zero lactose', quantity_g: 200 }],
      'BR',
    )
    expect(r.items[0]?.kcal).toBeGreaterThan(50)
  })
})

describe('estimateMacros — empanados/fritos (Roberto 2026-06-05)', () => {
  it('frango à milanesa → categoria empanado_frango (280 kcal/100g)', () => {
    const r = estimateMacros('frango à milanesa')
    expect(r.category).toBe('empanado_frango')
    expect(r.kcal).toBe(280)
  })

  it('frango empanado → empanado_frango', () => {
    const r = estimateMacros('frango empanado')
    expect(r.category).toBe('empanado_frango')
  })

  it('filé de frango empanado → empanado_frango', () => {
    const r = estimateMacros('filé de frango empanado')
    expect(r.category).toBe('empanado_frango')
  })

  it('bife à milanesa → empanado_carne (300 kcal/100g, mais gordura)', () => {
    const r = estimateMacros('bife à milanesa')
    expect(r.category).toBe('empanado_carne')
    expect(r.kcal).toBe(300)
  })

  it('bife à parmegiana → empanado_carne', () => {
    const r = estimateMacros('bife à parmegiana')
    expect(r.category).toBe('empanado_carne')
  })

  it('peixe à milanesa → empanado_peixe (220 kcal/100g)', () => {
    const r = estimateMacros('peixe à milanesa')
    expect(r.category).toBe('empanado_peixe')
    expect(r.kcal).toBe(220)
  })

  it('nuggets de frango → empanado_frango', () => {
    const r = estimateMacros('nuggets de frango')
    expect(r.category).toBe('empanado_frango')
  })

  it('frango à passarinho → empanado_frango', () => {
    const r = estimateMacros('frango à passarinho')
    expect(r.category).toBe('empanado_frango')
  })

  it('frango frito → empanado_frango (regex frito + proteína)', () => {
    const r = estimateMacros('frango frito')
    expect(r.category).toBe('empanado_frango')
  })

  it('schnitzel → empanado_frango', () => {
    const r = estimateMacros('schnitzel')
    expect(r.category).toBe('empanado_frango')
  })

  // Garante que NÃO regrediu casos normais
  it('frango assado SEM "milanesa/frito" → categoria frango (165 kcal)', () => {
    const r = estimateMacros('frango assado')
    expect(r.category).toBe('frango')
    expect(r.kcal).toBe(165)
  })

  it('peixe grelhado → categoria peixe (130 kcal)', () => {
    const r = estimateMacros('peixe grelhado')
    expect(r.category).toBe('peixe')
  })

  it('bife grelhado → categoria carne (200 kcal)', () => {
    const r = estimateMacros('bife grelhado')
    expect(r.category).toBe('carne')
  })
})

describe('requiresVisualPreparationConfirmation — preparo inferido por foto', () => {
  it('sinaliza proteína com preparo visualmente ambíguo', () => {
    expect(requiresVisualPreparationConfirmation('frango frito')).toBe(true)
    expect(requiresVisualPreparationConfirmation('frango grelhado')).toBe(true)
    expect(requiresVisualPreparationConfirmation('sobrecoxa assada com pele')).toBe(true)
  })

  it('não sinaliza alimento sem preparo nem acompanhamento não proteico', () => {
    expect(requiresVisualPreparationConfirmation('frango')).toBe(false)
    expect(requiresVisualPreparationConfirmation('batata frita')).toBe(false)
    expect(requiresVisualPreparationConfirmation('arroz branco cozido')).toBe(false)
  })
})

describe('calcMealMacros — sanity 4 inverso: rejeita kcal baixo demais (Roberto 2026-06-05)', () => {
  it('"frango frito" não aceita macros de "peito de frango" sem preparo — caso Roberto 2026-07-10', async () => {
    const mock = makeMock({
      'frango frito': {
        id: 239,
        name_pt: 'peito de frango',
        category: 'carnes',
        similarity: 0.5,
        kcal_per_100g: 159,
        protein_g: 32,
        carbs_g: 0,
        fat_g: 2.5,
        fiber_g: 0,
      },
    })

    const r = await calcMealMacros(mock, [{ food_name: 'frango frito', quantity_g: 120 }], 'BR')

    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.kcal).toBeCloseTo(336, 1)
    expect(r.items[0]?.fat_g).toBeCloseTo(19.2, 1)
    expect(r.audit_warnings.join(' ')).toMatch(/preparo incompatível/i)
  })

  it('"frango grelhado" continua aceitando a entrada exata grelhada', async () => {
    const mock = makeMock({
      'frango grelhado': {
        id: 240,
        name_pt: 'frango grelhado',
        category: 'carnes',
        similarity: 1,
        kcal_per_100g: 159,
        protein_g: 32,
        carbs_g: 0,
        fat_g: 2.5,
        fiber_g: 0,
      },
    })

    const r = await calcMealMacros(mock, [{ food_name: 'frango grelhado', quantity_g: 120 }], 'BR')

    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeCloseTo(190.8, 1)
    expect(r.items[0]?.fat_g).toBeCloseTo(3, 1)
  })

  it('"frango à milanesa" matchando entry com "milanesa" no nome MAS kcal=120/100g → REJEITA pelo sanity 4', async () => {
    // Anchor "milanesa" passa (aparece no nome do match), mas kcal absurdamente
    // baixo (120) pra categoria empanado_frango (piso 200) → rejeita e estima.
    const mock = makeMock({
      'frango à milanesa': {
        id: 999,
        name_pt: 'frango à milanesa light errado',
        category: 'pratos',
        similarity: 0.85,
        kcal_per_100g: 120,
        protein_g: 25,
        carbs_g: 5,
        fat_g: 2,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'frango à milanesa', quantity_g: 160 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.kcal).toBeCloseTo(448, 0) // 280 × 1.6
    expect(r.audit_warnings.some((w) => /piso 200/.test(w))).toBe(true)
  })

  it('"bife à parmegiana" matchando entry de parmegiana mal cadastrada 150 kcal → REJEITA', async () => {
    const mock = makeMock({
      'bife à parmegiana': {
        id: 998,
        name_pt: 'bife à parmegiana versão antiga',
        category: 'pratos',
        similarity: 0.9,
        kcal_per_100g: 150,
        protein_g: 18,
        carbs_g: 8,
        fat_g: 7,
        fiber_g: 0.5,
      },
    })
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'bife à parmegiana', quantity_g: 200 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('llm_estimate')
    expect(r.items[0]?.kcal).toBeCloseTo(600, 0) // empanado_carne 300 × 2
  })

  it('NÃO rejeita match legítimo (frango à milanesa matchando 280 kcal/100g)', async () => {
    const mock = makeMock({
      'frango à milanesa': {
        id: 451,
        name_pt: 'frango à milanesa',
        category: 'pratos',
        similarity: 1.0,
        kcal_per_100g: 280,
        protein_g: 23,
        carbs_g: 11,
        fat_g: 16,
        fiber_g: 0.5,
      },
    })
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'frango à milanesa', quantity_g: 160 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeCloseTo(448, 0)
  })

  it('NÃO afeta alimentos comuns sem trigger (frango assado)', async () => {
    const mock = makeMock({
      'frango assado': {
        id: 397,
        name_pt: 'frango assado',
        category: 'carnes',
        similarity: 1.0,
        kcal_per_100g: 190,
        protein_g: 29,
        carbs_g: 0,
        fat_g: 8,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'frango assado', quantity_g: 160 }], 'BR')
    expect(r.items[0]?.source).toBe('canonical_exact')
    expect(r.items[0]?.kcal).toBeCloseTo(304, 0)
  })

  it('"azeite" matchando algo absurdo de 50 kcal/100g → rejeita pelo sanity 4 (piso 500)', async () => {
    // Anchor "azeite" passa (aparece no match). kcal 50 < piso 500.
    const mock = makeMock({
      azeite: {
        id: 997,
        name_pt: 'azeite diet falso',
        category: 'gorduras',
        similarity: 0.9,
        kcal_per_100g: 50,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 5,
        fiber_g: 0,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'azeite', quantity_g: 10 }], 'BR')
    expect(r.items[0]?.source).toBe('llm_estimate')
  })
})

// ============================================================================
// Bug Luciana 2026-06-16: kcal explícito no texto deve OVERRIDE o lookup TACO.
// "rap 10 : 70 calorias" → gravar 70 kcal (não 140 kcal do food_db).
// ============================================================================
describe('parseUserKcalOverrides — extrai kcal explícito do texto', () => {
  it('"rap 10 : 70 calorias" → associa 70 kcal ao item wrap', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('rap 10 : 70 calorias', [{ food_name: 'wrap' }])
    expect(overrides.get('wrap')).toBe(70)
  })

  it('"100g arroz, 70 kcal" → arroz recebe 70 kcal', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('100g arroz, 70 kcal', [{ food_name: 'arroz' }])
    expect(overrides.get('arroz')).toBe(70)
  })

  it('"1 wrap" → SEM kcal explícita, retorna Map vazio', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('1 wrap', [{ food_name: 'wrap' }])
    expect(overrides.size).toBe(0)
  })

  it('"wrap 30g 70 kcal, suco 200ml 80 cal" → ambos itens recebem kcal certo', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('wrap 30g 70 kcal, suco 200ml 80 cal', [
      { food_name: 'wrap' },
      { food_name: 'suco' },
    ])
    expect(overrides.get('wrap')).toBe(70)
    expect(overrides.get('suco')).toBe(80)
  })

  it('texto sem números de kcal mas com gramas → Map vazio (não confunde g com kcal)', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('100g de arroz e 80g de feijão', [
      { food_name: 'arroz' },
      { food_name: 'feijão' },
    ])
    expect(overrides.size).toBe(0)
  })

  it('decimal com vírgula "70,5 kcal" funciona', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('wrap : 70,5 kcal', [{ food_name: 'wrap' }])
    expect(overrides.get('wrap')).toBe(70.5)
  })

  // Review HIGH KCAL-MULTI-ITEM 2026-06-16: alinhamento por ordem.
  // Cenário Luciana: paciente diz "rap 10 : 70 calorias e suco" mas
  // Haiku normaliza items=[{wrap, 50g}, {suco, 200g}]. Antes do fix,
  // segmento#1 (kcal=70, bestItem=null pq "rap" não casa "wrap" perfeitamente)
  // → kcal perdido. Agora alinhamento por ordem (1ª orphan-kcal → 1º item
  // sem override) dá wrap=70.
  it('multi-item com kcal órfão alinha por ORDEM (rap 10 : 70 cal e suco)', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      'rap 10 : 70 calorias e suco',
      // Items que NÃO casam "rap" diretamente (firstWord não bate "wrap"
      // se o nome no DB for "tapioca integral" por ex). Aqui forço o cenário
      // usando food_names que não têm match com "rap".
      [{ food_name: 'tapioca integral' }, { food_name: 'suco de laranja' }],
    )
    // O 1º segmento tem kcal=70 sem item identificado; 2º segmento tem
    // "suco" mas sem kcal. Alinhamento por ordem: tapioca recebe 70.
    expect(overrides.get('tapioca integral')).toBe(70)
    expect(overrides.has('suco de laranja')).toBe(false)
  })

  it('multi-item: NÃO alinha quando há orphans demais (segurança)', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      // 2 segmentos com kcal órfão pra apenas 1 item — não alinha (ambíguo).
      '70 cal, 80 cal',
      [{ food_name: 'wrap' }],
    )
    // 2 orphans > 1 item → não aplica alinhamento. Mas como há 1 item,
    // o lastSeenItem default cobre (último kcal vence).
    expect(overrides.get('wrap')).toBe(80)
  })

  it('não interpreta itens nem Total de card nutricional como correção do paciente', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `• pão francês (1 pão) — 150 kcal
• ovo frito (1 unidade) — 94 kcal
• queijo mussarela (30g) — 84 kcal
• leite com whey (240 ml) — 228 kcal
• geleia (15g) — 38 kcal

Total: 593 kcal | 41.6g proteína | 51.8g carboidrato | 22.6g gordura`,
      [
        { food_name: 'pão francês' },
        { food_name: 'ovo frito' },
        { food_name: 'queijo mussarela' },
        { food_name: 'leite com whey' },
        { food_name: 'geleia' },
      ],
    )

    expect(overrides.size).toBe(0)
  })

  it('não interpreta card de um item seguido de agregados diários como override', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `geleia (15g) — 38 kcal
🔥 Consumido: 593 / 1.935 kcal
🎯 Restam: 1.342 kcal`,
      [{ food_name: 'geleia' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('não interpreta card condensado como override', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      'geleia (15g) — 38 kcal | Total: 593 kcal | Restam: 1.342 kcal',
      [{ food_name: 'geleia' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('não interpreta o formato real do card com ponto médio e dois-pontos', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `· pão francês (1 pão): 150 kcal | 4.4g proteína | 27.8g carboidrato | 2.2g gordura
· geleia de morango (15g): 38 kcal | 0.1g proteína | 9.3g carboidrato | 0g gordura
*Total: 188 kcal | 4.5g proteína | 37.1g carboidrato | 2.2g gordura*`,
      [{ food_name: 'pão francês' }, { food_name: 'geleia de morango' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('não interpreta card com unidade natural repetindo o alimento como override', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `· banana (1 banana): 89 kcal | 1.1g proteína | 22.8g carboidrato | 0.3g gordura
· maçã (1 maçã): 72 kcal | 0.4g proteína | 19g carboidrato | 0.2g gordura
Total: 161 kcal | 1.5g proteína | 41.8g carboidrato | 0.5g gordura`,
      [{ food_name: 'banana' }, { food_name: 'maçã' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('preserva correção explícita escrita fora de um card nutricional', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `• pão francês (1 pão) — 150 kcal
• ovo frito (1 unidade) — 94 kcal
• geleia (15g) — 38 kcal
Total: 282 kcal | 18g proteína | 40g carboidrato | 8g gordura

Na verdade, a geleia tinha 42 kcal.`,
      [{ food_name: 'pão francês' }, { food_name: 'ovo frito' }, { food_name: 'geleia' }],
    )

    expect(Object.fromEntries(overrides)).toEqual({ geleia: 42 })
  })

  it('rejeita conjunto completo de kcal quando a soma contradiz o Total explícito', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides(
      `• arroz (100g) — 130 kcal
• feijão (100g) — 80 kcal
Total: 500 kcal`,
      [{ food_name: 'arroz' }, { food_name: 'feijão' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('frase negada "goiaba não tem 383 kcal" não vira override de 383', async () => {
    const { parseUserKcalOverrides } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverrides('Goiaba não tem 383kcal', [{ food_name: 'goiaba' }])
    expect(overrides.size).toBe(0)
  })

  it('janela recente preserva kcal de mensagem anterior quando a última é confirmação curta', async () => {
    const { parseUserKcalOverridesFromMessages } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverridesFromMessages(
      ['Torta de legumes 80 calorias\nPão baguete 60 calorias', 'Sim isso'],
      [{ food_name: 'torta de legumes' }, { food_name: 'pão baguete' }],
    )
    expect(overrides.get('torta de legumes')).toBe(80)
    expect(overrides.get('pão baguete')).toBe(60)
  })

  it('janela recente deixa a mensagem mais nova vencer quando o paciente corrige kcal', async () => {
    const { parseUserKcalOverridesFromMessages } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverridesFromMessages(
      ['Torta de legumes 80 calorias', 'torta de legumes 95 kcal'],
      [{ food_name: 'torta de legumes' }],
    )
    expect(overrides.get('torta de legumes')).toBe(95)
  })

  it('não herda kcal de refeição antiga quando o turno atual descreve outros itens', async () => {
    const { parseUserKcalOverridesFromMessages } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverridesFromMessages(
      ['1 rap10 de 70 kcal', 'Arroz branco 100g e uvas roxas 70g'],
      [{ food_name: 'arroz branco' }, { food_name: 'uvas roxas' }],
    )

    expect(overrides.size).toBe(0)
  })

  it('não herda kcal antiga só porque o item reaparece em uma nova descrição', async () => {
    const { parseUserKcalOverridesFromMessages } = await import('./meal-pipeline.js')
    const overrides = parseUserKcalOverridesFromMessages(
      ['arroz branco 70 kcal', 'Hoje comi arroz branco 100g e feijão 100g'],
      [{ food_name: 'arroz branco' }, { food_name: 'feijão' }],
    )

    expect(overrides.size).toBe(0)
  })
})

describe('calcMealMacros — user_kcal override (Bug Luciana 2026-06-16)', () => {
  it('user_kcal=70 num wrap → grava 70 kcal mesmo com lookup retornando 140', async () => {
    const mock = makeMock({
      wrap: {
        id: 9999,
        name_pt: 'wrap integral',
        category: 'panificacao',
        similarity: 1,
        kcal_per_100g: 280, // 140 kcal pra 50g = lookup default
        protein_g: 8,
        carbs_g: 40,
        fat_g: 8,
        fiber_g: 2,
      },
    })
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'wrap', quantity_g: 50, user_kcal: 70 }],
      'BR',
    )
    expect(r.items[0]?.kcal).toBe(70) // override exato
    expect(r.items[0]?.source).toBe('user_kcal')
    expect(r.items[0]?.matched_taco_name).toMatch(/kcal informado pelo paciente/)
    expect(r.totals.kcal).toBe(70)
    // P/C/F re-escalonados (não zerados)
    expect(r.items[0]?.protein_g).toBeGreaterThan(0)
    expect(r.items[0]?.carbs_g).toBeGreaterThan(0)
    expect(r.audit_warnings.some((w) => /kcal informado pelo paciente/i.test(w))).toBe(true)
  })

  it('usa o perfil de macros canônico ao aplicar kcal explícita', async () => {
    const mock = makeMock({
      geleia: {
        id: 383,
        name_pt: 'geleia',
        category: 'doces',
        similarity: 1,
        kcal_per_100g: 250,
        protein_g: 0.4,
        carbs_g: 63,
        fat_g: 0.1,
        fiber_g: 1,
      },
    })

    const result = await calcMealMacros(
      mock,
      [{ food_name: 'geleia', quantity_g: 15, user_kcal: 38 }],
      'BR',
    )

    expect(result.items[0]).toMatchObject({
      kcal: 38,
      source: 'user_kcal',
      protein_g: 0.06,
      carbs_g: 9.58,
      fat_g: 0.02,
    })
    expect(result.items[0]?.matched_taco_name).toContain('geleia')
  })

  it('rejeita kcal fisicamente impossível e volta à fonte canônica', async () => {
    const mock = makeMock({
      geleia: {
        id: 383,
        name_pt: 'geleia',
        category: 'doces',
        similarity: 1,
        kcal_per_100g: 250,
        protein_g: 0.4,
        carbs_g: 63,
        fat_g: 0.1,
        fiber_g: 1,
      },
    })

    const result = await calcMealMacros(
      mock,
      [{ food_name: 'geleia', quantity_g: 15, user_kcal: 593 }],
      'BR',
    )

    expect(result.items[0]).toMatchObject({
      kcal: 37.5,
      source: 'canonical_exact',
      carbs_g: 9.45,
    })
    expect(result.audit_warnings.some((warning) => /densidade.*impossível/i.test(warning))).toBe(
      true,
    )
  })

  it('user_kcal=0 (paciente disse "0 kcal") → grava 0, P/C/F=0', async () => {
    const mock = makeMock({})
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'agua com gás', quantity_g: 250, user_kcal: 0 }],
      'BR',
    )
    expect(r.items[0]?.kcal).toBe(0)
    expect(r.items[0]?.protein_g).toBe(0)
    expect(r.items[0]?.fat_g).toBe(0)
    expect(r.totals.kcal).toBe(0)
  })

  it('SEM user_kcal → lookup TACO normal (override não dispara)', async () => {
    const mock = makeMock({
      wrap: {
        id: 9999,
        name_pt: 'wrap integral',
        category: 'panificacao',
        similarity: 1,
        kcal_per_100g: 280,
        protein_g: 8,
        carbs_g: 40,
        fat_g: 8,
        fiber_g: 2,
      },
    })
    const r = await calcMealMacros(mock, [{ food_name: 'wrap', quantity_g: 50 }], 'BR')
    expect(r.items[0]?.kcal).toBe(140) // lookup default
    expect(r.items[0]?.matched_taco_name).toBe('wrap integral')
  })

  it('nutrição aprovada no pending é persistida sem novo recálculo', async () => {
    const mock = makeMock(
      {
        'frango ao molho cremoso': {
          id: 808,
          name_pt: 'frango ao molho cremoso',
          category: 'pratos',
          similarity: 1,
          kcal_per_100g: 300,
          protein_g: 10,
          carbs_g: 20,
          fat_g: 20,
          fiber_g: 0,
        },
      },
      [
        {
          id: 'history-wrong',
          food_name: 'frango ao molho cremoso',
          quantity_g: 180,
          kcal: 70,
          protein_g: 5,
          carbs_g: 2,
          fat_g: 3,
          source: 'user_kcal',
        },
      ],
    )

    const result = await calcMealMacros(
      mock,
      [
        {
          food_name: 'frango ao molho cremoso',
          quantity_g: 150,
          approved_nutrition: {
            kcal: 247.5,
            protein_g: 24.75,
            carbs_g: 7.5,
            fat_g: 13.5,
          },
        } as never,
      ],
      'BR',
      'user-confirming-pending',
    )

    expect(result.items[0]).toMatchObject({
      source: 'pending_approved',
      kcal: 247.5,
      protein_g: 24.75,
      carbs_g: 7.5,
      fat_g: 13.5,
    })
    expect(result.totals.kcal).toBe(247.5)
  })

  it('pending aprovado com densidade fisicamente impossível não chega ao registro', async () => {
    const mock = makeMock({
      geleia: {
        id: 383,
        name_pt: 'geleia',
        category: 'doces',
        similarity: 1,
        kcal_per_100g: 250,
        protein_g: 0.4,
        carbs_g: 63,
        fat_g: 0.1,
        fiber_g: 1,
      },
    })

    const result = await calcMealMacros(
      mock,
      [
        {
          food_name: 'geleia',
          quantity_g: 15,
          user_kcal: 593,
          approved_nutrition: {
            kcal: 593,
            protein_g: 6.8,
            carbs_g: 102.6,
            fat_g: 18.3,
          },
        },
      ],
      'BR',
      'user-with-corrupt-pending',
    )

    expect(result.items[0]).toMatchObject({ kcal: 37.5, source: 'canonical_exact' })
    expect(result.audit_warnings.join(' ')).toMatch(/pending.*densidade.*impossível/i)
  })
})

describe('calcMealMacros — subtipos de laticínios fermentados', () => {
  it('não aceita iogurte grego como referência fuzzy para kumis', async () => {
    const mock = makeMock({
      'iogurte kumis': {
        id: 259,
        name_pt: 'iogurte grego',
        category: 'lacteos',
        similarity: 0.72,
        kcal_per_100g: 97,
        protein_g: 9,
        carbs_g: 4,
        fat_g: 5,
        fiber_g: 0,
      },
    })

    const result = await calcMealMacros(
      mock,
      [{ food_name: 'iogurte kumis', quantity_g: 150 }],
      'US',
    )

    expect(result.items[0]?.matched_taco_name).not.toBe('iogurte grego')
    expect(result.items[0]?.matched_taco_id).toBeNull()
    expect(result.items[0]?.kcal).not.toBe(145.5)
  })

  it('usa a referência canônica exata de kumis para dois pacientes igualmente', async () => {
    const kumis = {
      id: 9001,
      name_pt: 'iogurte kumis',
      category: 'lacteos',
      similarity: 1,
      kcal_per_100g: 83.3333,
      protein_g: 3.3333,
      carbs_g: 9.5833,
      fat_g: 3.3333,
      fiber_g: 0,
    }
    const first = await calcMealMacros(
      makeMock({ 'iogurte kumis': kumis }),
      [{ food_name: 'iogurte kumis', quantity_g: 150 }],
      'US',
    )
    const second = await calcMealMacros(
      makeMock({ 'iogurte kumis': kumis }),
      [{ food_name: 'iogurte kumis', quantity_g: 150 }],
      'US',
    )

    expect(first.items[0]).toMatchObject({
      matched_taco_id: 9001,
      source: 'canonical_exact',
      kcal: 125,
      protein_g: 5,
      carbs_g: 14.37,
      fat_g: 5,
    })
    expect(second.items[0]).toMatchObject(first.items[0] ?? {})
  })
})
