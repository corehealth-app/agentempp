import { describe, expect, it } from 'vitest'
import { reclassificaRefeicao } from './tools.js'

describe('reclassifica_refeicao por grupo de registro', () => {
  it('caso Roberto: hint em um alimento move os quatro itens da mensagem', async () => {
    const updatedIds: string[] = []
    const rows = [
      {
        id: '1',
        food_name: 'rap10',
        kcal: 100,
        meal_type: 'lanche',
        consumed_at: '2026-07-10T00:13:00Z',
        raw_provider_message_id: 'wamid-1',
      },
      {
        id: '2',
        food_name: 'frango',
        kcal: 200,
        meal_type: 'lanche',
        consumed_at: '2026-07-10T00:13:00Z',
        raw_provider_message_id: 'wamid-1',
      },
      {
        id: '3',
        food_name: 'queijo',
        kcal: 80,
        meal_type: 'lanche',
        consumed_at: '2026-07-10T00:13:00Z',
        raw_provider_message_id: 'wamid-1',
      },
      {
        id: '4',
        food_name: 'salada',
        kcal: 20,
        meal_type: 'lanche',
        consumed_at: '2026-07-10T00:13:00Z',
        raw_provider_message_id: 'wamid-1',
      },
    ]
    const chain = (data: unknown): Record<string, unknown> => {
      const value: Record<string, unknown> = { data, error: null }
      for (const method of ['select', 'eq', 'limit', 'order']) value[method] = () => chain(data)
      value.maybeSingle = () => Promise.resolve({ data, error: null })
      // biome-ignore lint/suspicious/noThenProperty: mock fiel ao query builder awaitable do Supabase
      value.then = (resolve: (result: { data: unknown; error: null }) => unknown) =>
        Promise.resolve(resolve({ data, error: null }))
      return value
    }
    const supabase = {
      from: (table: string) => {
        if (table === 'daily_snapshots') return chain({ id: 'snapshot-1' })
        if (table === 'meal_logs') {
          return {
            ...chain(rows),
            update: () => ({
              in: (_column: string, ids: string[]) => {
                updatedIds.push(...ids)
                return Promise.resolve({ error: null })
              },
            }),
          }
        }
        return { insert: () => Promise.resolve({ error: null }) }
      },
    }

    const result = await reclassificaRefeicao.execute(
      {
        from_meal_type: 'lanche',
        to_meal_type: 'jantar',
        food_hint: 'rap10',
      },
      {
        supabase,
        userId: 'user-1',
        userWpp: 'masked',
        userTimezone: 'America/New_York',
        referenceTimestamp: new Date('2026-07-10T00:13:00Z'),
      } as never,
    )

    expect(result).toMatchObject({ success: true, moved_count: 4, total_kcal: 400 })
    expect(updatedIds).toEqual(['1', '2', '3', '4'])
  })
})
