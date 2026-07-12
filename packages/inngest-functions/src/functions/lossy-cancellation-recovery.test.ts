import { describe, expect, it } from 'vitest'
import { reopenLossyCancellationPending } from './lossy-cancellation-recovery.js'

function makeSupabase(options: { reopened?: boolean; updateError?: string } = {}) {
  const touchedTables: string[] = []
  const events: Array<Record<string, unknown>> = []

  return {
    touchedTables,
    events,
    client: {
      from(table: string) {
        touchedTables.push(table)
        if (table === 'pending_registrations') {
          const terminal = {
            maybeSingle: async () => ({
              data: options.reopened === false ? null : { id: 'pending-1' },
              error: options.updateError ? { message: options.updateError } : null,
            }),
          }
          return {
            update: () => ({
              eq: () => ({
                eq: () => ({
                  select: () => terminal,
                }),
              }),
            }),
          }
        }
        if (table === 'product_events') {
          return {
            insert: async (event: Record<string, unknown>) => {
              events.push(event)
              return { error: null }
            },
          }
        }
        throw new Error(`unexpected table mutation: ${table}`)
      },
    },
  }
}

describe('lossy cancellation recovery', () => {
  it('reabre o pending sem subtrair snapshot nem apagar meal_logs antes do registro atômico', async () => {
    const db = makeSupabase()

    const reopened = await reopenLossyCancellationPending(db.client as never, {
      userId: 'user-1',
      pendingId: 'pending-1',
      subsetMealLogIds: ['meal-1'],
      subsetKcalTotal: 120,
      proposalKcalTotal: 420,
      subsetMatchRatio: 1,
      resolvedAtAgeMs: 30_000,
    })

    expect(reopened).toBe(true)
    expect(db.touchedTables).toEqual(['pending_registrations', 'product_events'])
    expect(db.events[0]).toMatchObject({
      event: 'pending.recovered_from_lossy_cancellation',
      properties: {
        pendingId: 'pending-1',
        deletion_deferred_to_atomic_register: true,
      },
    })
  })

  it('não sinaliza recuperação quando o CAS perdeu a corrida', async () => {
    const db = makeSupabase({ reopened: false })

    const reopened = await reopenLossyCancellationPending(db.client as never, {
      userId: 'user-1',
      pendingId: 'pending-1',
      subsetMealLogIds: ['meal-1'],
      subsetKcalTotal: 120,
      proposalKcalTotal: 420,
      subsetMatchRatio: 1,
      resolvedAtAgeMs: 30_000,
    })

    expect(reopened).toBe(false)
    expect(db.touchedTables).toEqual(['pending_registrations'])
  })

  it('propaga erro do CAS em vez de prosseguir com estado parcial', async () => {
    const db = makeSupabase({ updateError: 'database unavailable' })

    await expect(
      reopenLossyCancellationPending(db.client as never, {
        userId: 'user-1',
        pendingId: 'pending-1',
        subsetMealLogIds: ['meal-1'],
        subsetKcalTotal: 120,
        proposalKcalTotal: 420,
        subsetMatchRatio: 1,
        resolvedAtAgeMs: 30_000,
      }),
    ).rejects.toThrow('database unavailable')
  })
})
