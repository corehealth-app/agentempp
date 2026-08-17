import { describe, expect, it } from 'vitest'
import type { ServiceClient } from '@mpp/db'
import {
  pickAnchorFood,
  inferTags,
  isTemporallyCompatible,
  selectCuratedPhrase,
} from './curated-phrase-selector.js'

function mockSupabase(rows: Array<{
  id: string
  phrase: string
  tags: Record<string, unknown> | null
  usage_count: number
  last_used_at: string | null
}>, opts: { recentPhraseIds?: string[]; cooldownError?: Error } = {}): ServiceClient {
  // Mock thenable chain pra .from('user_phrase_cooldown')...{select,eq,...}
  const cooldownChain = {
    select: () => cooldownChain,
    eq: () => cooldownChain,
    gte: () => cooldownChain,
    in: async () => {
      if (opts.cooldownError) return { data: null, error: opts.cooldownError }
      return { data: (opts.recentPhraseIds ?? []).map((phrase_id) => ({ phrase_id })) }
    },
    upsert: async () => ({ data: null }), // upsert no-op
  }
  const updateChain = {
    update: () => updateChain,
    eq: async () => ({ data: null }),
  }
  const selectChain = {
    select: () => selectChain,
    eq: () => selectChain,
    ilike: () => selectChain,
    in: () => selectChain,
    order: () => selectChain,
    limit: async () => ({ data: rows }),
  }
  return {
    from: (t: string) => {
      if (t === 'food_education_phrases') return { ...selectChain, ...updateChain }
      if (t === 'user_phrase_cooldown') return cooldownChain
      return updateChain
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  } as any
}

describe('pickAnchorFood', () => {
  it('escolhe item com mais kcal e proteína densa', () => {
    const r = pickAnchorFood([
      { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
      { food_name: 'frango assado', kcal: 200, protein_g: 30, carbs_g: 0, fat_g: 8 },
    ])
    expect(r?.food_name).toBe('frango assado')
  })

  it('escolhe gordura densa quando kcal igual', () => {
    const r = pickAnchorFood([
      { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
      { food_name: 'azeite', kcal: 130, protein_g: 0, carbs_g: 0, fat_g: 14 },
    ])
    expect(r?.food_name).toBe('azeite')
  })

  it('items vazio → null', () => {
    expect(pickAnchorFood([])).toBeNull()
  })

  it('1 item só → ele é o anchor', () => {
    const r = pickAnchorFood([
      { food_name: 'banana', kcal: 100, protein_g: 1, carbs_g: 25, fat_g: 0 },
    ])
    expect(r?.food_name).toBe('banana')
  })
})

describe('inferTags', () => {
  it('vazio quando sem state', () => {
    expect(inferTags()).toEqual([])
  })

  it('recomp + protein_low quando déficit + proteína baixa', () => {
    const tags = inferTags({ protocol: 'recomposicao', protein_pct: 30 })
    expect(tags).toContain('recomp')
    expect(tags).toContain('protein_low')
  })

  it('protein_high quando proteína >= 80%', () => {
    const tags = inferTags({ protein_pct: 85 })
    expect(tags).toContain('protein_high')
    expect(tags).not.toContain('protein_low')
  })

  it('block_near_close quando bloco >= 90%', () => {
    const tags = inferTags({ deficit_block_pct: 95 })
    expect(tags).toContain('block_near_close')
  })

  it('ganho_massa + kcal_high', () => {
    const tags = inferTags({ protocol: 'ganho_massa', kcal_pct: 85 })
    expect(tags).toContain('ganho_massa')
    expect(tags).toContain('kcal_high')
  })
})

describe('selectCuratedPhrase — substitui {alimento}', () => {
  it('troca {alimento} pelo food_name original do anchor', async () => {
    const supa = mockSupabase([
      {
        id: 'p-1',
        phrase: '{alimento} é uma escolha saborosa, com atenção às porções.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'Chocolate', kcal: 500, protein_g: 5, carbs_g: 60, fat_g: 30 }],
    })
    expect(result.phrase).toBe('Chocolate é uma escolha saborosa, com atenção às porções.')
    expect(result.reason).toBe('selected')
  })

  it('capitaliza primeira letra quando food_name vem lowercase (caso comum em prod)', async () => {
    const supa = mockSupabase([
      {
        id: 'p-cap',
        phrase: '{alimento} é uma escolha saborosa.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'chocolate', kcal: 500, protein_g: 5, carbs_g: 60, fat_g: 30 }],
    })
    expect(result.phrase).toBe('Chocolate é uma escolha saborosa.')
  })

  it('preserva acentos do food_name original', async () => {
    const supa = mockSupabase([
      {
        id: 'p-2',
        phrase: '{alimento} é uma ótima fonte de fibras.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'Maçã', kcal: 80, protein_g: 1, carbs_g: 20, fat_g: 0 }],
    })
    expect(result.phrase).toContain('Maçã')
  })

  it('multiplas ocorrências: 1ª capitalizada, demais lowercase', async () => {
    const supa = mockSupabase([
      {
        id: 'p-3',
        phrase: '{alimento} hoje, {alimento} amanhã. Vale moderar.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'brigadeiro', kcal: 90, protein_g: 1, carbs_g: 15, fat_g: 3 }],
    })
    expect(result.phrase).toBe('Brigadeiro hoje, brigadeiro amanhã. Vale moderar.')
  })

  it('food_name com caracteres especiais ($, &) não é interpretado como regex replacement', async () => {
    // Bug do String.replace: se replacement string contém $1, $&, $`, etc,
    // são interpretados como backrefs. Selector usa função pra evitar isso.
    const supa = mockSupabase([
      {
        id: 'p-esp',
        phrase: '{alimento} é caro.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'doce r$10', kcal: 100, protein_g: 1, carbs_g: 20, fat_g: 1 }],
    })
    // Espera "Doce r$10 é caro" — sem interpretação de $10 como backref
    expect(result.phrase).toBe('Doce r$10 é caro.')
  })

  it('frase sem placeholder fica intacta', async () => {
    const supa = mockSupabase([
      {
        id: 'p-4',
        phrase: 'Excelente escolha! Proteína magra ajuda na saciedade.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'frango', kcal: 200, protein_g: 30, carbs_g: 0, fat_g: 8 }],
    })
    expect(result.phrase).toBe('Excelente escolha! Proteína magra ajuda na saciedade.')
  })

  it('retorna no_anchor quando items vazio', async () => {
    const supa = mockSupabase([])
    const result = await selectCuratedPhrase(supa, { userId: 'u-1', items: [] })
    expect(result.reason).toBe('no_anchor')
    expect(result.phrase).toBeNull()
  })

  it('retorna no_anchor quando TODOS items têm kcal=0 (água, chá puro)', async () => {
    const supa = mockSupabase([])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [
        { food_name: 'água', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
        { food_name: 'chá verde', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
      ],
    })
    expect(result.reason).toBe('no_anchor')
  })

  it('ignora items com kcal=0 e escolhe anchor entre os scorables (azeite no salada)', async () => {
    const supa = mockSupabase([
      {
        id: 'p',
        phrase: '{alimento} é uma escolha saborosa.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [
        { food_name: 'água', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
        { food_name: 'salada', kcal: 50, protein_g: 2, carbs_g: 10, fat_g: 0 },
      ],
    })
    expect(result.phrase).toBe('Salada é uma escolha saborosa.')
  })

  it('capitaliza após pontuação inicial ("— {alimento}…")', async () => {
    const supa = mockSupabase([
      {
        id: 'p',
        phrase: '— {alimento} é uma escolha equilibrada.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'frango', kcal: 200, protein_g: 30, carbs_g: 0, fat_g: 8 }],
    })
    expect(result.phrase).toBe('— Frango é uma escolha equilibrada.')
  })

  it('capitaliza após aspas ("{alimento}…")', async () => {
    const supa = mockSupabase([
      {
        id: 'p',
        phrase: '"{alimento}" tem boa saciedade.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const result = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'ovo', kcal: 70, protein_g: 6, carbs_g: 0, fat_g: 5 }],
    })
    expect(result.phrase).toContain('Ovo')
  })
})

describe('pickAnchorFood — filter kcal=0', () => {
  it('retorna null quando TODOS items são kcal=0', () => {
    expect(pickAnchorFood([
      { food_name: 'água', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
      { food_name: 'sal', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
    ])).toBeNull()
  })

  it('filtra kcal=0 e retorna o melhor scorable', () => {
    const r = pickAnchorFood([
      { food_name: 'chá', kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
      { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
    ])
    expect(r?.food_name).toBe('arroz')
  })
})

describe('isTemporallyCompatible — Nível 1 defensivo (bug I3 2026-06-14)', () => {
  // Bug exato: frase id=3166910f... "Whey de manhã é o tipo de hábito…"
  // foi renderizada no JANTAR do Roberto em 2026-06-14 22:27.
  it('bug I3: "Whey de manhã…" REJEITADA em jantar', () => {
    const r = isTemporallyCompatible(
      'Whey de manhã é o tipo de hábito que separa quem leva o processo a sério de quem só pensa em emagrecer.',
      'jantar',
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toMatch(/manha_only_in_jantar/)
  })

  it('"Café com whey logo cedo trava a fome…" REJEITADA em jantar', () => {
    const r = isTemporallyCompatible(
      'Café com whey logo cedo trava a fome até o almoço — 20g de proteína num item só, escolha sólida pra recomp.',
      'jantar',
    )
    expect(r.ok).toBe(false)
  })

  it('"Whey de manhã…" ACEITA em cafe', () => {
    expect(
      isTemporallyCompatible('Whey de manhã é o tipo de hábito…', 'cafe').ok,
    ).toBe(true)
  })

  it('frase universal (3+ slots) PASSA em qualquer meal', () => {
    const versatil =
      'Acelga pode aparecer em quase todas as refeições principais — almoço, jantar, e até em vitaminas verdes no café da manhã.'
    expect(isTemporallyCompatible(versatil, 'cafe').ok).toBe(true)
    expect(isTemporallyCompatible(versatil, 'almoco').ok).toBe(true)
    expect(isTemporallyCompatible(versatil, 'jantar').ok).toBe(true)
    expect(isTemporallyCompatible(versatil, 'ceia').ok).toBe(true)
  })

  it('"proteína leve para o jantar" ACEITA em jantar, REJEITADA em cafe', () => {
    const phrase = 'Salmao é uma proteína de digestão geralmente mais leve, opção para o jantar.'
    expect(isTemporallyCompatible(phrase, 'jantar').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'cafe').ok).toBe(false)
  })

  it('"antes de dormir" REJEITADA em cafe/almoco/lanche', () => {
    const phrase = 'Cuidado com castanha antes de dormir — gordura demora a digerir.'
    expect(isTemporallyCompatible(phrase, 'cafe').ok).toBe(false)
    expect(isTemporallyCompatible(phrase, 'almoco').ok).toBe(false)
    expect(isTemporallyCompatible(phrase, 'lanche').ok).toBe(false)
    expect(isTemporallyCompatible(phrase, 'ceia').ok).toBe(true)
  })

  it('frase neutra (sem palavra temporal) PASSA em qualquer slot', () => {
    const phrase = 'Frango é proteína magra de alto valor biológico.'
    expect(isTemporallyCompatible(phrase, 'cafe').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'almoco').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'jantar').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'ceia').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'lanche').ok).toBe(true)
  })

  it('mealKind ausente ou "outro"/"treino" → no-op (sempre passa)', () => {
    const phrase = 'Whey de manhã é hábito de quem leva a sério.'
    expect(isTemporallyCompatible(phrase, undefined).ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'outro').ok).toBe(true)
    expect(isTemporallyCompatible(phrase, 'treino').ok).toBe(true)
  })

  it('case-insensitive: "MANHÃ" maiúsculo também detecta', () => {
    expect(isTemporallyCompatible('Whey de MANHÃ é hábito…', 'jantar').ok).toBe(false)
  })
})

describe('selectCuratedPhrase — filtro temporal integrado', () => {
  it('reason=no_temporally_compatible_phrase quando todas frases são incompatíveis', async () => {
    const supa = mockSupabase([
      {
        id: 'p-whey-manha',
        phrase: 'Whey de manhã é o tipo de hábito que separa…',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const r = await selectCuratedPhrase(supa, {
      userId: 'roberto-prod',
      items: [{ food_name: 'leite com whey', kcal: 200, protein_g: 25, carbs_g: 8, fat_g: 5 }],
      mealKind: 'jantar',
    })
    expect(r.phrase).toBeNull()
    expect(r.reason).toBe('no_temporally_compatible_phrase')
  })

  it('escolhe a única frase compatível quando há mix', async () => {
    const supa = mockSupabase([
      {
        id: 'p-incompat',
        phrase: 'Whey de manhã é o tipo de hábito…',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
      {
        id: 'p-neutral',
        phrase: '{alimento} é proteína de qualidade.',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const r = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'leite com whey', kcal: 200, protein_g: 25, carbs_g: 8, fat_g: 5 }],
      mealKind: 'jantar',
    })
    expect(r.phrase).toBe('Leite com whey é proteína de qualidade.')
    expect(r.phrase_id).toBe('p-neutral')
  })

  it('mealKind ausente = sem filtro (compat com call sites antigos)', async () => {
    const supa = mockSupabase([
      {
        id: 'p-whey',
        phrase: 'Whey de manhã é hábito…',
        tags: null,
        usage_count: 0,
        last_used_at: null,
      },
    ])
    const r = await selectCuratedPhrase(supa, {
      userId: 'u-1',
      items: [{ food_name: 'whey', kcal: 100, protein_g: 20, carbs_g: 2, fat_g: 1 }],
      // sem mealKind
    })
    expect(r.phrase).toBe('Whey de manhã é hábito…')
  })
})

describe('selectCuratedPhrase — cooldown forte por paciente', () => {
  it('caso Roberto: frase recente em cooldown + alternativa elegível → escolhe alternativa', async () => {
    const supa = mockSupabase(
      [
        {
          id: 'p-whey-repetida',
          phrase:
            'Whey de manhã é o tipo de hábito que separa quem leva o processo a sério de quem só pensa em emagrecer.',
          tags: {},
          usage_count: 18,
          last_used_at: '2026-07-06T13:20:42.144Z',
        },
        {
          id: 'p-whey-alternativa',
          phrase:
            'Café com whey logo cedo trava a fome até o almoço — 20g de proteína num item só, escolha sólida pra recomp.',
          tags: { recomp: true },
          usage_count: 1,
          last_used_at: '2026-06-14T13:51:02.804Z',
        },
      ],
      { recentPhraseIds: ['p-whey-repetida'] },
    )

    const result = await selectCuratedPhrase(supa, {
      userId: 'roberto-prod',
      items: [{ food_name: 'leite com whey', kcal: 228, protein_g: 24, carbs_g: 12, fat_g: 7.2 }],
      state: { protocol: 'recomposicao' },
      mealKind: 'cafe',
    })

    expect(result.phrase_id).toBe('p-whey-alternativa')
    expect(result.phrase).toBe(
      'Café com whey logo cedo trava a fome até o almoço — 20g de proteína num item só, escolha sólida pra recomp.',
    )
    expect(result.reason).toBe('selected_after_cooldown')
  })

  it('todas as frases em cooldown → permite repetir com reason explícito', async () => {
    const supa = mockSupabase(
      [
        {
          id: 'p-unica',
          phrase: 'Whey de manhã é hábito de quem leva a sério.',
          tags: {},
          usage_count: 18,
          last_used_at: '2026-07-06T13:20:42.144Z',
        },
      ],
      { recentPhraseIds: ['p-unica'] },
    )

    const result = await selectCuratedPhrase(supa, {
      userId: 'roberto-prod',
      items: [{ food_name: 'leite com whey', kcal: 228, protein_g: 24, carbs_g: 12, fat_g: 7.2 }],
      state: { protocol: 'recomposicao' },
      mealKind: 'cafe',
    })

    expect(result.phrase_id).toBe('p-unica')
    expect(result.reason).toBe('selected_all_recent')
  })

  it('erro ao consultar cooldown → retorna null para cair no Haiku', async () => {
    const supa = mockSupabase(
      [
        {
          id: 'p-whey',
          phrase: 'Whey de manhã é hábito de quem leva a sério.',
          tags: {},
          usage_count: 18,
          last_used_at: '2026-07-06T13:20:42.144Z',
        },
      ],
      { cooldownError: new Error('permission denied') },
    )

    const result = await selectCuratedPhrase(supa, {
      userId: 'roberto-prod',
      items: [{ food_name: 'leite com whey', kcal: 228, protein_g: 24, carbs_g: 12, fat_g: 7.2 }],
      state: { protocol: 'recomposicao' },
      mealKind: 'cafe',
    })

    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('cooldown_lookup_failed')
  })
})
