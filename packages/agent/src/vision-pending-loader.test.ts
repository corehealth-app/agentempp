/**
 * Tests — vision-pending-loader (audit 06-26 Item 6).
 *
 * Cobre a lógica pura deriveVisionPending. Garante que o cenário Roberto
 * 25/06 (2 fotos no mesmo turno) + os 4 fast-paths (pmid match, overlap
 * 50%, dedup intra-bucket, retorno do mais recente pendente) ficam travados.
 */
import { describe, expect, it } from 'vitest'
import { deriveVisionPending, loadVisionPending } from './vision-pending-loader.js'

const NOW = new Date('2026-06-26T18:00:00.000Z').getTime()

const vision = (
  pmid: string | null,
  items: Array<{ name: string; qg?: number }>,
  occurredAt: string,
  type: 'meal' | 'other' = 'meal',
  mealContext: string | null = null,
) => ({
  properties: {
    type,
    provider_message_id: pmid,
    meal_items: items.map((it) => ({
      name: it.name,
      quantity_g_estimate: it.qg ?? 100,
      confidence: 0.8,
    })),
    meal_context: mealContext,
  },
  occurred_at: occurredAt,
})

const meal = (food: string, pmid: string | null, createdAt: string) => ({
  food_name: food,
  provider_message_id: pmid,
  created_at: createdAt,
})

const pend = (id: string, items: string[], createdAt: string) => ({
  id,
  proposal: { items: items.map((name) => ({ name })) },
  created_at: createdAt,
})

describe('deriveVisionPending', () => {
  it('(a) zero visions → null', () => {
    expect(deriveVisionPending([], [], [], NOW)).toBeNull()
  })

  it('(b) 1 vision não consumida (sem meal_log nem pending) → retorna', () => {
    const result = deriveVisionPending(
      [vision('pmid-1', [{ name: 'arroz' }, { name: 'frango' }], '2026-06-26T17:55:00.000Z', 'meal', 'almoço')],
      [],
      [],
      NOW,
    )
    expect(result).not.toBeNull()
    expect(result?.items.map((i) => i.name)).toEqual(['arroz', 'frango'])
    expect(result?.mealContext).toBe('almoço')
    expect(result?.ageMinutes).toBe(5)
  })

  it('(c) vision consumida via pmid match → null (foto já registrada)', () => {
    const result = deriveVisionPending(
      [vision('pmid-1', [{ name: 'arroz' }], '2026-06-26T17:50:00.000Z')],
      [meal('arroz', 'pmid-1', '2026-06-26T17:51:00.000Z')],
      [],
      NOW,
    )
    expect(result).toBeNull()
  })

  it('(d) vision consumida via overlap nome ≥50% → null', () => {
    // Vision 2 itens, meal_log 1 deles = 50% → consumed.
    const result = deriveVisionPending(
      [vision('pmid-2', [{ name: 'arroz' }, { name: 'feijão' }], '2026-06-26T17:50:00.000Z')],
      [meal('arroz', 'outro-pmid', '2026-06-26T17:51:00.000Z')],
      [],
      NOW,
    )
    expect(result).toBeNull()
  })

  it('(e) Roberto 25/06 — 2 visions mesmo pmid (batch) → bucket único com items deduplicados', () => {
    const result = deriveVisionPending(
      [
        vision('pmid-batch', [{ name: 'arroz' }, { name: 'frango' }], '2026-06-26T17:55:00.000Z'),
        vision('pmid-batch', [{ name: 'frango' }, { name: 'salada' }], '2026-06-26T17:55:00.000Z'),
      ],
      [],
      [],
      NOW,
    )
    expect(result).not.toBeNull()
    // Dedup: arroz, frango, salada (não duplica frango).
    expect(result?.items.map((i) => i.name).sort()).toEqual(['arroz', 'frango', 'salada'])
  })

  it('(f) 2 visions pmids diferentes — mais recente pendente é retornada', () => {
    const result = deriveVisionPending(
      [
        vision('pmid-old', [{ name: 'arroz' }], '2026-06-26T16:00:00.000Z'),
        vision('pmid-new', [{ name: 'pizza' }], '2026-06-26T17:50:00.000Z'),
      ],
      [],
      [],
      NOW,
    )
    expect(result?.items.map((i) => i.name)).toEqual(['pizza']) // mais recente
  })

  it('(g) overlap 49% → ainda pendente (threshold é >=50%)', () => {
    // 3 items, 1 match = 33% → pendente
    const result = deriveVisionPending(
      [
        vision(
          'pmid-3',
          [{ name: 'arroz' }, { name: 'feijão' }, { name: 'frango' }],
          '2026-06-26T17:50:00.000Z',
        ),
      ],
      [meal('arroz', 'outro', '2026-06-26T17:51:00.000Z')],
      [],
      NOW,
    )
    expect(result).not.toBeNull()
    expect(result?.items.length).toBe(3)
  })

  it('(h) item duplicado entre 2 fotos mesmo pmid → dedup mantém 1', () => {
    const result = deriveVisionPending(
      [
        vision('pmid-dup', [{ name: 'Pizza', qg: 200 }], '2026-06-26T17:55:00.000Z'),
        vision('pmid-dup', [{ name: 'pizza', qg: 50 }], '2026-06-26T17:55:00.000Z'),
      ],
      [],
      [],
      NOW,
    )
    expect(result?.items.length).toBe(1)
    // Mantém o primeiro inserido (case-insensitive normalization match).
    expect(result?.items[0]?.quantity_g_estimate).toBe(200)
  })

  it('vision com type≠meal é ignorada', () => {
    const result = deriveVisionPending(
      [vision('pmid-x', [{ name: 'arroz' }], '2026-06-26T17:50:00.000Z', 'other')],
      [],
      [],
      NOW,
    )
    expect(result).toBeNull()
  })

  it('vision com meal_items vazio é ignorada (não vira bucket)', () => {
    const result = deriveVisionPending(
      [vision('pmid-empty', [], '2026-06-26T17:50:00.000Z')],
      [],
      [],
      NOW,
    )
    expect(result).toBeNull()
  })

  it('pending com proposal.items cobre overlap igual ao meal_log', () => {
    // Foto pizza+coca, pending registrou só pizza → overlap 50% → consumed.
    const result = deriveVisionPending(
      [vision('pmid-4', [{ name: 'pizza' }, { name: 'coca' }], '2026-06-26T17:50:00.000Z')],
      [],
      [pend('pend-1', ['Pizza'], '2026-06-26T17:51:00.000Z')],
      NOW,
    )
    expect(result).toBeNull() // suprimida pelo pending (50% atinge threshold)
  })

  it('normalização acentos: "Açúcar" vs "acucar" match no overlap', () => {
    const result = deriveVisionPending(
      [vision('pmid-5', [{ name: 'Açúcar' }], '2026-06-26T17:50:00.000Z')],
      [meal('acucar', 'outro', '2026-06-26T17:51:00.000Z')],
      [],
      NOW,
    )
    expect(result).toBeNull() // 100% overlap após normalize
  })
})

function queryChain(result: { data: unknown; error: unknown }) {
  const chain = {
    select: () => chain,
    eq: () => chain,
    gte: () => chain,
    order: () => chain,
    limit: () => chain,
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
    then: <TResult1 = { data: unknown; error: unknown }>(
      onfulfilled?: ((value: { data: unknown; error: unknown }) => TResult1 | PromiseLike<TResult1>) | null,
    ) => Promise.resolve(result).then(onfulfilled),
  }
  return chain
}

describe('loadVisionPending — falhas de banco', () => {
  const visionRow = vision(
    'pmid-db-error',
    [{ name: 'frango' }],
    '2026-06-26T17:55:00.000Z',
  )

  it('propaga erro ao carregar eventos de vision', async () => {
    const supabase = {
      from: () => queryChain({ data: null, error: { message: 'vision lookup failed' } }),
    }

    await expect(loadVisionPending(supabase, 'user-1')).rejects.toThrow(
      'vision lookup failed',
    )
  })

  it('propaga erro ao verificar se a foto já virou refeição', async () => {
    const supabase = {
      from: (table: string) => {
        if (table === 'product_events') return queryChain({ data: [visionRow], error: null })
        if (table === 'meal_logs') {
          return queryChain({ data: null, error: { message: 'meal lookup failed' } })
        }
        return queryChain({ data: [], error: null })
      },
    }

    await expect(loadVisionPending(supabase, 'user-1')).rejects.toThrow('meal lookup failed')
  })
})
