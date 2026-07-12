import { describe, expect, it } from 'vitest'
import { finalizeDailyClose } from './daily-close-finalizer.js'

const input = {
  userId: 'user-1',
  snapshotId: 'snapshot-1',
  dayStatus: 'user_skipped' as const,
  xpTotal: 125,
  level: 2,
  currentStreak: 3,
  longestStreak: 4,
  blocksCompleted: 1,
  deficitBlock: 250,
  badgesEarned: ['Primeiro Bloco'],
  lastActiveDate: '2026-07-11',
  closedAt: '2026-07-12T04:30:00.000Z',
}

describe('finalizeDailyClose', () => {
  it('envia todo o estado para uma única RPC e retorna applied', async () => {
    const calls: Array<{ name: string; params: Record<string, unknown> }> = []
    const supabase = {
      rpc: async (name: string, params: Record<string, unknown>) => {
        calls.push({ name, params })
        return { data: { applied: true, snapshot_id: 'snapshot-1' }, error: null }
      },
    }

    await expect(finalizeDailyClose(supabase as never, input)).resolves.toMatchObject({
      applied: true,
    })
    expect(calls).toEqual([
      {
        name: 'finalize_daily_close_atomic',
        params: expect.objectContaining({
          p_snapshot_id: 'snapshot-1',
          p_day_status: 'user_skipped',
          p_xp_total: 125,
          p_deficit_block: 250,
        }),
      },
    ])
  })

  it('propaga erro da RPC para permitir retry do worker', async () => {
    const supabase = {
      rpc: async () => ({ data: null, error: { message: 'database unavailable' } }),
    }

    await expect(finalizeDailyClose(supabase as never, input)).rejects.toThrow(
      'database unavailable',
    )
  })
})
