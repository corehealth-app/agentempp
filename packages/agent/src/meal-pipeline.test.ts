import { describe, it, expect } from 'vitest'

// Anti-regression coverage pro meal-pipeline. Cobre os bugs que custaram caro
// pra debugar e que NÃO podem voltar:
//   1. Bacon/parmesão/oleaginosas com alta densidade calórica NÃO podem zerar
//      (sanity check 2 precisa permitir via category OU regex backup).
//   2. Avisos internos ("estimativa por categoria", "baixa confiança", "auto-split")
//      vão pra audit_warnings — NUNCA pra user_warnings.
//   3. Avisos acionáveis pelo paciente (composite rejeitado, category_mismatch,
//      protein_mismatch) vão pra user_warnings.
//   4. Match composite direto (alias completo, sim>=0.85) tem precedência sobre auto-split.

import { calcMealMacros } from './meal-pipeline.js'
import type { ServiceClient } from '@mpp/db'

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

function makeMock(
  matches: Record<string, MockRow | null>,
  historyRows: HistoryRow[] = [],
  correctionRows: CorrectionRow[] = [],
): ServiceClient {
  // Proxy chainable que aceita qualquer .eq/.ilike/.gte/.gt/.neq/.order/.limit
  // e no final retorna { data, error }. Suporta queries de lookupUserHistory,
  // lookupFoodCorrection e o fallback antigo.
  const makeChain = (rows: unknown): unknown => {
    const obj: Record<string, unknown> = {
      data: rows,
      error: null,
    }
    for (const m of ['select', 'eq', 'ilike', 'gte', 'gt', 'lt', 'neq', 'order', 'limit']) {
      obj[m] = () => makeChain(rows)
    }
    obj.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return obj
  }
  return {
    rpc: async (_fn: string, params: { search_term: string }) => {
      const term = params.search_term.toLowerCase().trim()
      const hit = matches[term]
      if (hit) return { data: [hit], error: null }
      return { data: [], error: null }
    },
    from: (table: string) => {
      if (table === 'meal_logs') return makeChain(historyRows)
      if (table === 'user_food_corrections') return makeChain(correctionRows)
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
    expect(r.items[0]?.source).toBe('taco')
    expect(r.items[0]?.kcal).toBeCloseTo(190, 0)
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
    expect(r.items[0]?.source).toBe('taco')
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
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'queijo parmesão', quantity_g: 20 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('taco')
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
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'castanha do pará', quantity_g: 25 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('taco')
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
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'iogurte natural', quantity_g: 100 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('llm_estimate')
    // Não zera — estima como laticineo (~65 kcal/100g)
    expect(r.items[0]?.kcal).toBeGreaterThan(40)
    expect(r.items[0]?.kcal).toBeLessThan(100)
    // Audit log registra rejeição por anchor
    expect(r.audit_warnings.some((w) => /âncora|anchor/i.test(w))).toBe(true)
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
    expect(r.items[0]?.source).toBe('taco')
    expect(r.user_warnings).toHaveLength(0)
    expect(r.audit_warnings.some((w) => /baixa confian|sim=/i.test(w))).toBe(true)
  })

  it('composite rejeitado (auto-split falhou) — aviso vai pra user_warnings (acionável)', async () => {
    // "xpto com quux" → split em "xpto" e "quux", ambos sem match → rejeita
    const mock = makeMock({})
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'xpto com quux', quantity_g: 100 }],
      'BR',
    )
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
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'leite e whey', quantity_g: 250 }],
      'BR',
    )
    expect(r.items[0]?.source).toBe('taco')
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
    expect(r.items[0]?.source).toBe('taco')
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
    expect(r.items[0]?.source).toBe('taco')
    expect(r.items[0]?.matched_taco_name).toContain('histórico')
    // 100 kcal/100g × 250g/100 = 250 kcal — NÃO 212.5 (achocolatado)
    expect(r.items[0]?.kcal).toBe(250)
    expect(r.items[0]?.protein_g).toBe(30) // 24g/200g × 250g = 30g
    expect(r.audit_warnings.some((w) => /hist[óo]rico/i.test(w))).toBe(true)
  })

  it('histórico match case/acento-insensitive', async () => {
    const mock = makeMock(
      {},
      [
        {
          id: 'log-2',
          food_name: 'Pão Francês',
          quantity_g: 50,
          kcal: 150,
          protein_g: 4,
          carbs_g: 29,
          fat_g: 1.5,
        },
      ],
    )
    const r = await calcMealMacros(
      mock,
      [{ food_name: 'pao frances', quantity_g: 100 }],
      'BR',
      'user-x',
    )
    expect(r.items[0]?.source).toBe('taco')
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
    expect(r.items[0]?.source).toBe('taco')
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
    expect(r.items[0]?.source).toBe('taco')
    expect(r.items[0]?.kcal).toBe(89) // banana, não whey
    expect(r.items[0]?.matched_taco_name).not.toContain('histórico')
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
          id: 1, name_pt: 'batata inglesa', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 86, protein_g: 2, carbs_g: 20, fat_g: 0, fiber_g: 1,
        },
      },
      [],
      [
        {
          said_name: 'batata', corrected_to: 'mandioca',
          custom_kcal_per_100g: 150, custom_protein_g: 1.5, custom_carbs_g: 36, custom_fat_g: 0.3,
          status: 'active', confirmed_count: 2,
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
          id: 2, name_pt: 'mandioca cozida', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 125, protein_g: 1, carbs_g: 30, fat_g: 0.3, fiber_g: 1.6,
        },
      },
      [],
      [
        { said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 3 },
      ],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('mandioca')
    expect(r.items[0]?.kcal).toBe(125) // veio do trigram pra "mandioca"
    expect(r.user_warnings).toHaveLength(0)
  })

  it('correção LEARNING (1ª vez) → aplica MAS pede confirmação via user_warning', async () => {
    const mock = makeMock(
      {
        mandioca: {
          id: 2, name_pt: 'mandioca cozida', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 125, protein_g: 1, carbs_g: 30, fat_g: 0.3, fiber_g: 1.6,
        },
      },
      [],
      [
        { said_name: 'batata', corrected_to: 'mandioca', status: 'learning', confirmed_count: 1 },
      ],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', 'user-1')
    expect(r.items[0]?.food_name).toBe('mandioca')
    // learning → DEVE ter user_warning pedindo confirmação
    expect(r.user_warnings.length).toBeGreaterThan(0)
    expect(r.user_warnings.join(' ')).toMatch(/corrigiu isso antes|me avisa/i)
  })

  it('sem userId → mapa de correções NÃO é consultado', async () => {
    const mock = makeMock(
      {
        batata: {
          id: 1, name_pt: 'batata inglesa', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 86, protein_g: 2, carbs_g: 20, fat_g: 0, fiber_g: 1,
        },
      },
      [],
      [
        { said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 5 },
      ],
    )
    const r = await calcMealMacros(mock, [{ food_name: 'batata', quantity_g: 100 }], 'BR', undefined)
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
          id: 2, name_pt: 'mandioca cozida', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 125, protein_g: 1, carbs_g: 30, fat_g: 0.3, fiber_g: 1.6,
        },
      },
      [
        { id: 'h1', food_name: 'batata', quantity_g: 100, kcal: 86, protein_g: 2, carbs_g: 20, fat_g: 0 },
      ],
      [
        { said_name: 'batata', corrected_to: 'mandioca', status: 'active', confirmed_count: 2 },
      ],
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
          id: 1, name_pt: 'batata inglesa', category: 'tuberculos',
          similarity: 1, kcal_per_100g: 86, protein_g: 2, carbs_g: 20, fat_g: 0, fiber_g: 1,
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
