import { describe, it, expect } from 'vitest'
import {
  generateEducationalComment,
  hasPhantomFoodMention,
} from './educational-comment.js'

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

function makeEducationalSupabase(cooldownError?: string, phraseText?: string) {
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const phraseRows = [
    {
      id: 'phrase-whey-1',
      phrase:
        phraseText ?? '{alimento} ajuda a sustentar uma refeição rica em proteína.',
      tags: null,
      allowed_meal_types: null,
      usage_count: 0,
      last_used_at: null,
    },
  ]

  const chain = (data: unknown, error: { message: string } | null = null): unknown => {
    const value: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'in', 'gte', 'order', 'limit']) {
      value[method] = () => chain(data, error)
    }
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are awaitable thenables.
    value.then = (
      resolve: (result: { data: unknown; error: { message: string } | null }) => unknown,
    ) => Promise.resolve(resolve({ data: error ? null : data, error }))
    return value
  }

  const supabase = {
    from: (table: string) => {
      if (table === 'food_education_phrases') {
        return {
          ...((chain(phraseRows) as object)),
          update: () => chain(null),
        }
      }
      if (table === 'user_phrase_cooldown') {
        return {
          ...((chain([], cooldownError ? { message: cooldownError } : null) as object)),
          upsert: async () => ({ data: null, error: null }),
        }
      }
      if (table === 'product_events') {
        return {
          insert: async (row: { event: string; properties: Record<string, unknown> }) => {
            events.push(row)
            return { data: null, error: null }
          },
        }
      }
      return chain([])
    },
    rpc: async (name: string) => {
      if (name !== 'claim_food_education_phrase') return { data: [], error: null }
      if (cooldownError) return { data: null, error: { message: cooldownError } }
      return {
        data: [
          {
            phrase_id: phraseRows[0]?.id,
            cooldown_count: 0,
            selected_after_cooldown: false,
            exhausted: false,
          },
        ],
        error: null,
      }
    },
  }

  return { supabase, events }
}

describe('generateEducationalComment — telemetria de cooldown', () => {
  const input = {
    kind: 'cafe' as const,
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
  }

  it('inclui id e contagens no evento de frase curada', async () => {
    const { supabase, events } = makeEducationalSupabase()
    let llmCalls = 0
    const llm = {
      complete: async () => {
        llmCalls += 1
        return { content: 'Comentário do Haiku.' }
      },
    }

    const result = await generateEducationalComment(llm as never, input, {
      supabase,
      userId: 'user-test',
      state: { protocol: 'recomposicao' },
    })

    expect(result).toContain('Leite com whey')
    expect(llmCalls).toBe(0)
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'edu_comment.curated_hit',
        properties: expect.objectContaining({
          phrase_id: 'phrase-whey-1',
          candidate_count: 1,
          compatible_count: 1,
          cooldown_count: 0,
          selected_after_cooldown: false,
        }),
      }),
    )
  })

  it('emite cooldown_error e usa Haiku quando a consulta falha', async () => {
    const { supabase, events } = makeEducationalSupabase('cooldown unavailable')
    const llm = {
      complete: async () => ({ content: 'Comentário alternativo do Haiku.' }),
    }

    const result = await generateEducationalComment(llm as never, input, {
      supabase,
      userId: 'user-test',
    })

    expect(result).toBe('Comentário alternativo do Haiku.')
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'edu_comment.cooldown_error',
        properties: expect.objectContaining({ reason: 'cooldown_lookup_failed' }),
      }),
    )
  })

  it('registra tokens, custo, modelo e latência quando usa Haiku', async () => {
    const { supabase, events } = makeEducationalSupabase('force curated fallback')
    const llm = {
      complete: async () => ({
        content: 'Comentário alternativo do Haiku.',
        promptTokens: 321,
        completionTokens: 45,
        totalTokens: 366,
        costUsd: 0.00042,
        model: 'anthropic/claude-haiku-4.5:provider',
        latencyMs: 876,
      }),
    }

    await generateEducationalComment(llm as never, input, {
      supabase,
      userId: 'user-test',
    })

    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'edu_comment.haiku_success',
        properties: expect.objectContaining({
          prompt_tokens: 321,
          completion_tokens: 45,
          total_tokens: 366,
          cost_usd: 0.00042,
          model: 'anthropic/claude-haiku-4.5:provider',
          latency_ms: 876,
        }),
      }),
    )
  })

  it('descarta reforço de identidade moralizante gerado pelo Haiku', async () => {
    const { supabase, events } = makeEducationalSupabase('force curated fallback')
    const llm = {
      complete: async () => ({
        content:
          'Almoço com 33g de proteína só na carne de porco — você está priorizando o que realmente constrói músculo e saciedade. Esse é o padrão de quem leva a recomposição a sério.',
      }),
    }

    const result = await generateEducationalComment(llm as never, input, {
      supabase,
      userId: 'user-test',
    })

    expect(result).toBe('')
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'edu_comment.tone_drop',
        properties: expect.objectContaining({ reason: 'moralizing_identity_language' }),
      }),
    )
  })

  it('descarta frase curada moralizante e usa fallback neutro', async () => {
    const { supabase, events } = makeEducationalSupabase(
      undefined,
      '{alimento} é o padrão de quem leva a recomposição a sério.',
    )
    const llm = {
      complete: async () => ({
        content: 'Leite com whey contribui com proteína e praticidade nessa refeição.',
      }),
    }

    const result = await generateEducationalComment(llm as never, input, {
      supabase,
      userId: 'user-test',
    })

    expect(result).toBe(
      'Leite com whey contribui com proteína e praticidade nessa refeição.',
    )
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'edu_comment.curated_tone_drop',
        properties: expect.objectContaining({ reason: 'moralizing_identity_language' }),
      }),
    )
  })
})
