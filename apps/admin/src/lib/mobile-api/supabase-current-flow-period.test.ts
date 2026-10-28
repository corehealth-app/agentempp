import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { readSupabaseCurrentFlowPeriodRows } from './supabase-current-flow-period'
import { consentAuth } from './testing/reevaluation-photo-consent-fixture'

function setup() {
  const data = {
    version: 1,
    period: 'semana',
    from: '2026-10-21',
    to: '2026-10-27',
    observed_at: '2026-10-27T12:00:00.000000Z',
    rows: [
      {
        date: '2026-10-26',
        calories_consumed: 1600,
        protein_g: 100,
        day_status: 'complete',
        daily_balance: -400 as number | null,
        balance_proven: true,
      },
    ],
  }
  const rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => ({
    data: structuredClone(data) as unknown,
    error: null as unknown,
  }))
  const client = { rpc } as unknown as ServiceClient
  return {
    data,
    rpc,
    client,
    read: () => readSupabaseCurrentFlowPeriodRows(client, consentAuth.userId, data.from, data.to),
  }
}
describe('Supabase current Flow period adapter', () => {
  it('calls the sole bounded backend RPC and returns only the detached historical rows', async () => {
    const s = setup(),
      rows = await s.read()
    s.data.rows[0].calories_consumed = 9
    expect(rows[0].calories_consumed).toBe(1600)
    expect(Object.isFrozen(rows[0])).toBe(true)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('get_mobile_clinical_flow_period', {
      p_user_id: consentAuth.userId,
      p_period: 'semana',
      p_expected_from: '2026-10-21',
      p_expected_to: '2026-10-27',
    })
    expect(JSON.stringify(rows)).not.toMatch(/operation_key|context_hash|epoch|user_id/)
  })
  it('keeps an unproved legacy day with intake and completeness, never a fabricated balance', async () => {
    const s = setup()
    s.data.rows[0].balance_proven = false
    s.data.rows[0].daily_balance = null
    expect(await s.read()).toEqual(s.data.rows)
    s.data.rows[0].daily_balance = -400
    await expect(s.read()).rejects.toThrow()
  })
  it('supports exactly thirty days and no caller-supplied clock', async () => {
    const s = setup()
    s.data.period = 'mes'
    s.data.from = '2026-09-28'
    expect((await s.read()).length).toBe(1)
    expect(s.rpc).toHaveBeenCalledWith(
      'get_mobile_clinical_flow_period',
      expect.objectContaining({ p_period: 'mes' }),
    )
    expect(s.rpc.mock.calls[0][1]).not.toHaveProperty('p_observed_at')
  })
  it.each(['2026-10-22', '2026-02-30'])('refuses invalid window %s before RPC', async (from) => {
    const s = setup()
    s.data.from = from
    await expect(s.read()).rejects.toThrow()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it.each([
    '40001',
    '55P03',
    '42501',
  ])('maps %s without provider text, fallback query or retry', async (code) => {
    const s = setup()
    s.rpc.mockResolvedValueOnce({ data: null, error: { code, message: 'PRIVATE PROVIDER DETAIL' } })
    await expect(s.read()).rejects.not.toThrow('PRIVATE PROVIDER DETAIL')
    expect(s.rpc).toHaveBeenCalledTimes(1)
  })
  it('refuses mismatched scope, duplicate days, unknown status and unsafe numbers', async () => {
    const s = setup()
    s.rpc.mockResolvedValueOnce({ data: { ...s.data, to: '2026-10-26' }, error: null })
    await expect(s.read()).rejects.toThrow()
    s.data.rows.push({ ...s.data.rows[0] })
    await expect(s.read()).rejects.toThrow()
    s.data.rows.pop()
    s.data.rows[0].protein_g = Number.NaN
    await expect(s.read()).rejects.toThrow()
    s.data.rows[0].protein_g = 100
    s.data.rows[0].day_status = 'unrecognised'
    await expect(s.read()).rejects.toThrow()
  })
})
