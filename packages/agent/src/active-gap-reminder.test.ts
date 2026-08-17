import { describe, expect, it } from 'vitest'
import type { ServiceClient } from '@mpp/db'
import {
  loadActiveGapReminderMealTypes,
  resolveActiveGapReminderMealTypes,
} from './active-gap-reminder.js'

function gapReminderClient(results: Record<string, {
  data: unknown
  error: { message: string } | null
}>): ServiceClient {
  const chain = (result: { data: unknown; error: { message: string } | null }): unknown => {
    const value: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'gte', 'order', 'limit', 'maybeSingle']) {
      value[method] = () => chain(result)
    }
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are awaitable thenables.
    value.then = (
      resolve: (result: { data: unknown; error: { message: string } | null }) => unknown,
    ) => Promise.resolve(resolve(result))
    return value
  }
  return {
    from: (table: string) => chain(results[table] ?? { data: null, error: null }),
  } as unknown as ServiceClient
}

describe('resolveActiveGapReminderMealTypes', () => {
  const reference = new Date('2026-07-10T02:30:00.000Z')

  it('retorna apenas gaps do lembrete ativo enviado antes da mensagem', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: '2026-07-10T02:00:00.000Z' },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['almoco', 'jantar'] } }],
        reference,
      ),
    ).toEqual(['almoco', 'jantar'])
  })

  it('ignora snapshot apenas aberto sem lembrete', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: null },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['jantar'] } }],
        reference,
      ),
    ).toEqual([])
  })

  it('ignora lembrete que ocorreu depois do timestamp da mensagem', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: '2026-07-10T03:00:00.000Z' },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['jantar'] } }],
        reference,
      ),
    ).toEqual([])
  })

  it('propaga falha ao consultar o snapshot do lembrete', async () => {
    const client = gapReminderClient({
      daily_snapshots: { data: null, error: { message: 'gap snapshot unavailable' } },
    })

    await expect(
      loadActiveGapReminderMealTypes(client, 'user-test', '2026-07-09', reference),
    ).rejects.toThrow('gap snapshot unavailable')
  })

  it('propaga falha ao consultar a mensagem que contém o gap', async () => {
    const client = gapReminderClient({
      daily_snapshots: {
        data: {
          day_status: 'pending_close',
          gap_reminder_sent_at: '2026-07-10T02:00:00.000Z',
        },
        error: null,
      },
      messages: { data: null, error: { message: 'gap message unavailable' } },
    })

    await expect(
      loadActiveGapReminderMealTypes(client, 'user-test', '2026-07-09', reference),
    ).rejects.toThrow('gap message unavailable')
  })
})
