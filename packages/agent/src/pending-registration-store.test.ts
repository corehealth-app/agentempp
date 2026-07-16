import type { Json, ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import {
  cancelOpenPendingRegistrations,
  createPendingRegistration,
  loadRecentConfirmedMealPending,
  loadRecentEditedMealPending,
  loadRecentPendingMeal,
  loadRecentRegisteredMeal,
} from './pending-registration-store.js'

type QueryResult = {
  data: unknown
  error: { message: string } | null
}

type RecordedCall = {
  method: string
  args: unknown[]
}

function makeClient(results: { select?: QueryResult; update?: QueryResult; rpc?: QueryResult }) {
  const calls: RecordedCall[] = []
  const defaultResult: QueryResult = { data: null, error: null }

  const chain = (result: QueryResult): unknown => {
    const value: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'gte', 'order', 'limit', 'maybeSingle', 'single']) {
      value[method] = (...args: unknown[]) => {
        calls.push({ method, args })
        return chain(result)
      }
    }
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are awaitable thenables.
    value.then = (resolve: (result: QueryResult) => unknown) => Promise.resolve(resolve(result))
    return value
  }

  const client = {
    from: (table: string) => {
      calls.push({ method: 'from', args: [table] })
      return {
        ...(chain(results.select ?? defaultResult) as object),
        update: (...args: unknown[]) => {
          calls.push({ method: 'update', args })
          return chain(results.update ?? defaultResult)
        },
      }
    },
    rpc: async (name: string, params: Record<string, unknown>) => {
      calls.push({ method: 'rpc', args: [name, params] })
      return results.rpc ?? defaultResult
    },
  } as unknown as ServiceClient

  return { client, calls }
}

describe('pending registration store', () => {
  const now = new Date('2026-07-12T20:00:00.000Z')

  it('falha fechada quando não consegue consultar pending recente', async () => {
    const { client } = makeClient({
      select: { data: null, error: { message: 'pending lookup unavailable' } },
    })

    await expect(loadRecentPendingMeal(client, 'user-test', now)).rejects.toThrow(
      'pending lookup unavailable',
    )
  })

  it('isola a edição recente pelo tipo da refeição atual', async () => {
    const { client, calls } = makeClient({
      select: {
        data: { id: 'pending-edited', proposal: { kind: 'meal' }, resolved_at: now.toISOString() },
        error: null,
      },
    })

    await loadRecentEditedMealPending(client, 'user-test', 'jantar', now)

    expect(calls).toContainEqual({
      method: 'eq',
      args: ['proposal->>mealType', 'jantar'],
    })
  })

  it('carrega somente o pending confirmado recente da mesma refeição', async () => {
    const { client, calls } = makeClient({
      select: {
        data: {
          id: 'pending-confirmed',
          proposal: { kind: 'meal', mealType: 'jantar', items: [] },
          resolved_at: now.toISOString(),
        },
        error: null,
      },
    })

    await loadRecentConfirmedMealPending(client, 'user-test', 'jantar', now)

    expect(calls).toContainEqual({ method: 'eq', args: ['status', 'confirmed'] })
    expect(calls).toContainEqual({
      method: 'eq',
      args: ['proposal->>mealType', 'jantar'],
    })
    expect(calls).toContainEqual({ method: 'gte', args: ['resolved_at', expect.any(String)] })
  })

  it('escolhe o registro confirmado que contém o alimento corrigido', async () => {
    const { client } = makeClient({
      select: {
        data: [
          {
            id: 'pending-mais-recente-mas-diferente',
            proposal: {
              kind: 'meal',
              mealType: 'jantar',
              items: [{ name: 'iogurte', quantity_g: 120 }],
            },
            resolved_at: now.toISOString(),
          },
          {
            id: 'pending-com-salame',
            proposal: {
              kind: 'meal',
              mealType: 'jantar',
              items: [{ name: 'salame fatiado', quantity_g: 60 }],
            },
            resolved_at: now.toISOString(),
          },
        ],
        error: null,
      },
    })

    const result = await loadRecentConfirmedMealPending(client, 'user-test', 'jantar', now, [
      'salame fatiado',
    ])

    expect(result?.id).toBe('pending-com-salame')
  })

  it('recupera do banco a refeição registrada que contém o item corrigido', async () => {
    const { client } = makeClient({
      select: {
        data: [
          {
            id: 'log-iogurte',
            food_name: 'iogurte',
            quantity_g: 120,
            kcal: 80,
            protein_g: 4,
            carbs_g: 8,
            fat_g: 3,
            source: 'canonical_exact',
            food_db_id: 10,
            consumed_at: '2026-07-12T19:58:00.000Z',
            created_at: '2026-07-12T19:58:00.000Z',
            raw_provider_message_id: 'provider-newer',
          },
          {
            id: 'log-rap10',
            food_name: 'rap10',
            quantity_g: 35,
            kcal: 70,
            protein_g: 3.3,
            carbs_g: 8.4,
            fat_g: 2.3,
            source: 'pending_approved',
            food_db_id: null,
            consumed_at: '2026-07-12T19:40:00.000Z',
            created_at: '2026-07-12T19:40:00.000Z',
            raw_provider_message_id: 'provider-dinner',
          },
          {
            id: 'log-salame',
            food_name: 'salame fatiado',
            quantity_g: 60,
            kcal: 201.6,
            protein_g: 13.2,
            carbs_g: 1.2,
            fat_g: 16.2,
            source: 'canonical_fuzzy',
            food_db_id: 301,
            consumed_at: '2026-07-12T19:40:00.000Z',
            created_at: '2026-07-12T19:40:00.000Z',
            raw_provider_message_id: 'provider-dinner',
          },
        ],
        error: null,
      },
    })

    const result = await loadRecentRegisteredMeal(client, 'user-test', 'jantar', now, [
      'salame fatiado',
    ])

    expect(result?.groupKey).toBe('provider:provider-dinner')
    expect(result?.items).toEqual([
      expect.objectContaining({ name: 'rap10', kcal: 70, nutrition_source: 'pending_approved' }),
      expect.objectContaining({
        name: 'salame fatiado',
        kcal: 201.6,
        food_db_id: 301,
        nutrition_source: 'canonical_fuzzy',
      }),
    ])
  })

  it('falha fechada quando não consegue recuperar a refeição já registrada', async () => {
    const { client } = makeClient({
      select: { data: null, error: { message: 'meal history unavailable' } },
    })

    await expect(
      loadRecentRegisteredMeal(client, 'user-test', 'jantar', now, ['salame']),
    ).rejects.toThrow('meal history unavailable')
  })

  it('não prossegue quando o cancelamento dos pendings antigos falha', async () => {
    const { client } = makeClient({
      update: { data: null, error: { message: 'pending cancellation unavailable' } },
    })

    await expect(cancelOpenPendingRegistrations(client, 'user-test', now)).rejects.toThrow(
      'pending cancellation unavailable',
    )
  })

  it('não trata RPC sem id como pending criado', async () => {
    const { client } = makeClient({
      rpc: { data: null, error: null },
    })

    await expect(
      createPendingRegistration(client, {
        userId: 'user-test',
        proposal: { kind: 'meal' } as Json,
        expiresAt: '2026-07-13T20:00:00.000Z',
        requestKey: 'provider-message-1',
      }),
    ).rejects.toThrow('pending registration insert returned no id')
  })

  it('propaga erro da transação em vez de cair no registro automático', async () => {
    const { client } = makeClient({
      rpc: { data: null, error: { message: 'pending insert unavailable' } },
    })

    await expect(
      createPendingRegistration(client, {
        userId: 'user-test',
        proposal: { kind: 'workout' } as Json,
        expiresAt: '2026-07-13T20:00:00.000Z',
        requestKey: 'provider-message-2',
      }),
    ).rejects.toThrow('pending insert unavailable')
  })

  it('envia a chave da mensagem para tornar retries idempotentes', async () => {
    const { client, calls } = makeClient({
      rpc: { data: { pending_id: 'pending-created', created: true }, error: null },
    })

    await expect(
      createPendingRegistration(client, {
        userId: 'user-test',
        proposal: { kind: 'meal' } as Json,
        expiresAt: '2026-07-13T20:00:00.000Z',
        requestKey: 'provider-message-3',
      }),
    ).resolves.toBe('pending-created')
    expect(calls).toContainEqual({
      method: 'rpc',
      args: [
        'replace_pending_registration_atomic',
        expect.objectContaining({ p_request_key: 'provider-message-3' }),
      ],
    })
  })
})
