import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { loadDeterministicDailyState, loadReevaluationGate } from './pipeline-state-store.js'

type QueryResult = {
  data: unknown
  error: { message: string } | null
}

function makeClient(results: Record<string, QueryResult>): ServiceClient {
  const chain = (result: QueryResult): unknown => {
    const value: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'gte', 'order', 'limit', 'maybeSingle']) {
      value[method] = () => chain(result)
    }
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are awaitable thenables.
    value.then = (resolve: (result: QueryResult) => unknown) => Promise.resolve(resolve(result))
    return value
  }

  return {
    from: (table: string) => chain(results[table] ?? { data: null, error: null }),
  } as unknown as ServiceClient
}

describe('pipeline state store', () => {
  it('não renderiza card com snapshot parcialmente indisponível', async () => {
    const client = makeClient({
      daily_snapshots: { data: null, error: { message: 'snapshot unavailable' } },
      user_progress: { data: { deficit_block: 100 }, error: null },
    })

    await expect(loadDeterministicDailyState(client, 'user-test', '2026-07-12')).rejects.toThrow(
      'snapshot unavailable',
    )
  })

  it('não converte falha de progresso em bloco 7700 igual a zero', async () => {
    const client = makeClient({
      daily_snapshots: { data: { calories_consumed: 500 }, error: null },
      user_progress: { data: null, error: { message: 'progress unavailable' } },
    })

    await expect(loadDeterministicDailyState(client, 'user-test', '2026-07-12')).rejects.toThrow(
      'progress unavailable',
    )
  })

  it('propaga falha ao verificar se a reavaliação está devida', async () => {
    const client = makeClient({
      product_events: { data: null, error: { message: 'reevaluation events unavailable' } },
      user_profiles: { data: { current_protocol: 'recomposicao' }, error: null },
    })

    await expect(
      loadReevaluationGate(client, 'user-test', new Date('2026-07-12T20:00:00.000Z')),
    ).rejects.toThrow('reevaluation events unavailable')
  })

  it('propaga falha de perfil em vez de compor protocolo potencialmente antigo', async () => {
    const client = makeClient({
      product_events: { data: [{ id: 'due' }], error: null },
      user_profiles: { data: null, error: { message: 'reevaluation profile unavailable' } },
    })

    await expect(
      loadReevaluationGate(client, 'user-test', new Date('2026-07-12T20:00:00.000Z')),
    ).rejects.toThrow('reevaluation profile unavailable')
  })
})
