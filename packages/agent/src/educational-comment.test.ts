import { describe, it, expect } from 'vitest'
import { generateEducationalComment, hasPhantomFoodMention } from './educational-comment.js'

describe('hasPhantomFoodMention', () => {
  const cafe = [
    { food_name: 'leite com whey' },
    { food_name: 'ovo frito' },
    { food_name: 'pao frances' },
    { food_name: 'geleia de morango' },
    { food_name: 'queijo mussarela' },
  ]

  it('flag quando comentário sugere reduzir MANTEIGA inexistente (caso Roberto 2026-06-09)', () => {
    const comment = 'Café com 39g de proteína — começo forte. A gordura ficou elevada (19.6g) — da próxima, se reduzir um pouco da manteiga ou do óleo que tempera os itens, você mantém a saciedade.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('flag quando sugere reduzir AÇÚCAR inexistente', () => {
    const comment = 'Bom café. Da próxima, reduz o açúcar pra equilibrar mais.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('NÃO flaga quando sugere reduzir item que ESTÁ na lista', () => {
    const comment = 'Café sólido. O pão francês puxou carboidrato — na próxima reduz pela metade.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(false)
  })

  it('NÃO flaga menção genérica sem verbo de orientação (manteiga em contexto abstrato)', () => {
    const comment = 'Manteiga e óleo costumam disparar a gordura — você manteve baixo nesse café, parabéns.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(false)
  })

  it('NÃO flaga quando item está na lista mesmo com variação', () => {
    const itemsComMussarela = [{ food_name: 'queijo mussarela' }]
    const comment = 'O queijo mussarela puxou a gordura — reduz pela metade na próxima.'
    expect(hasPhantomFoodMention(comment, itemsComMussarela)).toBe(false)
  })

  it('flaga BACON quando não está na lista', () => {
    const comment = 'Boa proteína. Da próxima, tira o bacon pra reduzir gordura.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('NÃO flaga BACON quando está na lista', () => {
    const itemsComBacon = [{ food_name: 'bacon' }, { food_name: 'ovo frito' }]
    const comment = 'Da próxima, reduz o bacon — fica menos gorduroso.'
    expect(hasPhantomFoodMention(comment, itemsComBacon)).toBe(false)
  })

  it('flaga normalmente mesmo lista vazia (caller filtra antes)', () => {
    // Garantia documental: a função em si não defende contra lista vazia.
    // O caller (generateEducationalComment) só chama se items.length > 0.
    const comment = 'reduz a manteiga'
    expect(hasPhantomFoodMention(comment, [])).toBe(true)
  })
})

function mockEduSupabase(
  rows: Array<{
    id: string
    phrase: string
    tags: Record<string, unknown> | null
    usage_count: number
    last_used_at: string | null
  }>,
  opts: { recentPhraseIds?: string[]; cooldownError?: Error } = {},
) {
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const updates: unknown[] = []
  const upserts: unknown[] = []

  const foodSelectChain = {
    eq: () => foodSelectChain,
    in: () => foodSelectChain,
    order: () => foodSelectChain,
    limit: async () => ({ data: rows }),
  }
  const foodUpdateChain = {
    eq: async () => ({ data: null }),
  }
  const cooldownSelectChain = {
    eq: () => cooldownSelectChain,
    gte: () => cooldownSelectChain,
    in: async () => {
      if (opts.cooldownError) return { data: null, error: opts.cooldownError }
      return { data: (opts.recentPhraseIds ?? []).map((phrase_id) => ({ phrase_id })) }
    },
  }

  const supabase = {
    from: (table: string) => {
      if (table === 'food_education_phrases') {
        return {
          select: () => foodSelectChain,
          update: (value: unknown) => {
            updates.push(value)
            return foodUpdateChain
          },
        }
      }
      if (table === 'user_phrase_cooldown') {
        return {
          select: () => cooldownSelectChain,
          upsert: async (value: unknown) => {
            upserts.push(value)
            return { data: null }
          },
        }
      }
      if (table === 'product_events') {
        return {
          insert: async (value: { event: string; properties: Record<string, unknown> }) => {
            events.push(value)
            return { data: null }
          },
        }
      }
      throw new Error(`unexpected table: ${table}`)
    },
  }

  return { supabase, events, updates, upserts }
}

describe('generateEducationalComment — telemetria curated/cooldown', () => {
  it('curated_hit inclui metadados de pool, cooldown e phrase_id', async () => {
    const { supabase, events } = mockEduSupabase(
      [
        {
          id: 'p-repetida',
          phrase:
            'Whey de manhã é o tipo de hábito que separa quem leva o processo a sério de quem só pensa em emagrecer.',
          tags: {},
          usage_count: 18,
          last_used_at: '2026-07-06T13:20:42.144Z',
        },
        {
          id: 'p-alternativa',
          phrase:
            'Café com whey logo cedo trava a fome até o almoço — 20g de proteína num item só, escolha sólida pra recomp.',
          tags: { recomp: true },
          usage_count: 1,
          last_used_at: '2026-06-14T13:51:02.804Z',
        },
      ],
      { recentPhraseIds: ['p-repetida'] },
    )
    const llm = { complete: async () => ({ content: 'não deveria chamar haiku' }) }

    const comment = await generateEducationalComment(
      llm as never,
      {
        kind: 'cafe',
        items: [
          {
            food_name: 'leite com whey',
            quantity_g: 240,
            kcal: 228,
            protein_g: 24,
            carbs_g: 12,
            fat_g: 7.2,
          },
        ],
        totals: { kcal: 228, protein_g: 24, carbs_g: 12, fat_g: 7.2 },
        protocol: 'recomposicao',
      },
      {
        supabase,
        userId: 'roberto-prod',
        state: { protocol: 'recomposicao' },
      },
    )

    expect(comment).toBe(
      'Café com whey logo cedo trava a fome até o almoço — 20g de proteína num item só, escolha sólida pra recomp.',
    )
    const hit = events.find((e) => e.event === 'edu_comment.curated_hit')
    expect(hit?.properties).toMatchObject({
      phrase_id: 'p-alternativa',
      candidate_count: 2,
      compatible_count: 2,
      cooldown_count: 1,
      selected_after_cooldown: true,
      reason: 'selected_after_cooldown',
    })
  })

  it('falha no lookup de cooldown emite cooldown_error e cai para Haiku', async () => {
    const { supabase, events } = mockEduSupabase(
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
    const llm = { complete: async () => ({ content: 'Fallback Haiku seguro.' }) }

    const comment = await generateEducationalComment(
      llm as never,
      {
        kind: 'cafe',
        items: [
          {
            food_name: 'leite com whey',
            quantity_g: 240,
            kcal: 228,
            protein_g: 24,
            carbs_g: 12,
            fat_g: 7.2,
          },
        ],
        totals: { kcal: 228, protein_g: 24, carbs_g: 12, fat_g: 7.2 },
        protocol: 'recomposicao',
      },
      {
        supabase,
        userId: 'roberto-prod',
        state: { protocol: 'recomposicao' },
      },
    )

    expect(comment).toBe('Fallback Haiku seguro.')
    expect(events.find((e) => e.event === 'edu_comment.cooldown_error')?.properties).toMatchObject({
      reason: 'cooldown_lookup_failed',
      anchor: 'leite com whey',
      candidate_count: 1,
      compatible_count: 1,
    })
  })
})
