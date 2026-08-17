import { describe, expect, it } from 'vitest'
import { transitionPendingStatus } from './pending-status-transition.js'

type MockOptions = {
  data?: { id: string } | null
  error?: { message: string } | null
}

function makeClient(options: MockOptions = {}) {
  const calls: Array<{ payload: Record<string, unknown>; filters: Array<[string, string]> }> = []

  return {
    calls,
    client: {
      from(table: string) {
        expect(table).toBe('pending_registrations')
        return {
          update(payload: Record<string, unknown>) {
            const call = { payload, filters: [] as Array<[string, string]> }
            calls.push(call)
            const chain = {
              eq(column: string, value: string) {
                call.filters.push([column, value])
                return chain
              },
              select() {
                return {
                  maybeSingle: async () => ({
                    data: options.data === undefined ? { id: 'pending-1' } : options.data,
                    error: options.error ?? null,
                  }),
                }
              },
            }
            return chain
          },
        }
      },
    },
  }
}

describe('transitionPendingStatus', () => {
  it('faz compare-and-swap e confirma a linha alterada', async () => {
    const db = makeClient()

    await transitionPendingStatus(db.client as never, {
      pendingId: 'pending-1',
      from: 'pending',
      to: 'confirmed',
      resolvedAt: '2026-07-12T19:00:00.000Z',
    })

    expect(db.calls).toEqual([
      {
        payload: { status: 'confirmed', resolved_at: '2026-07-12T19:00:00.000Z' },
        filters: [
          ['id', 'pending-1'],
          ['status', 'pending'],
        ],
      },
    ])
  })

  it('propaga o erro retornado pelo Supabase', async () => {
    const db = makeClient({ error: { message: 'database unavailable' } })

    await expect(
      transitionPendingStatus(db.client as never, {
        pendingId: 'pending-1',
        from: 'pending',
        to: 'edited',
        resolvedAt: '2026-07-12T19:00:00.000Z',
      }),
    ).rejects.toThrow('database unavailable')
  })

  it('falha quando nenhuma linha estava mais no estado esperado', async () => {
    const db = makeClient({ data: null })

    await expect(
      transitionPendingStatus(db.client as never, {
        pendingId: 'pending-1',
        from: 'pending',
        to: 'expired',
        resolvedAt: '2026-07-12T19:00:00.000Z',
      }),
    ).rejects.toThrow('pending status transition lost race')
  })
})
