import type { Json, ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import {
  cancelOpenPendingRegistrations,
  createPendingRegistration,
  loadRecentEditedMealPending,
  loadRecentPendingMeal,
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
