/** Backend-only historical adapter. SQL owns the civil clock and exact close
 * evidence; this never reads legacy snapshots directly or writes/closes days. */
import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { currentClinicalError } from './current-clinical-state'
import type { CurrentFlowClinicalDependencies } from './current-flow-clinical-port'

const amount = z.number().finite().min(0).max(9999.99)
const row = z
  .object({
    date,
    calories_consumed: z.number().int().min(0).max(2147483647).nullable(),
    protein_g: amount.nullable(),
    day_status: z.enum(['complete', 'user_skipped', 'incomplete_no_response']).nullable(),
    daily_balance: z.number().int().min(-2147483648).max(2147483647).nullable(),
    balance_proven: z.boolean(),
  })
  .strict()
  .refine((v) => v.balance_proven === (v.daily_balance !== null))
const packet = z
  .object({
    version: z.literal(1),
    period: z.enum(['semana', 'mes']),
    from: date,
    to: date,
    observed_at: instant,
    rows: z.array(row).max(30),
  })
  .strict()
function record(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === 'object' && !Array.isArray(v)
}
type Rpc = (
  name: 'get_mobile_clinical_flow_period',
  args: {
    p_user_id: string
    p_period: 'semana' | 'mes'
    p_expected_from: string
    p_expected_to: string
  },
) => PromiseLike<unknown>
export const readSupabaseCurrentFlowPeriodRows: CurrentFlowClinicalDependencies['periodRows'] =
  async (client: ServiceClient, owner: string, from: string, to: string) => {
    let input: Parameters<Rpc>[1]
    try {
      const first = date.parse(from),
        last = date.parse(to)
      const days =
        (Date.parse(`${last}T00:00:00Z`) - Date.parse(`${first}T00:00:00Z`)) / 86400000 + 1
      if (days !== 7 && days !== 30) throw new Error('invalid window')
      input = Object.freeze({
        p_user_id: z.string().uuid().parse(owner),
        p_period: days === 7 ? 'semana' : 'mes',
        p_expected_from: first,
        p_expected_to: last,
      })
    } catch {
      throw currentClinicalError('invalid_response')
    }
    const rpc = client.rpc.bind(client) as unknown as Rpc
    let raw: unknown
    try {
      raw = await rpc('get_mobile_clinical_flow_period', input)
    } catch {
      throw currentClinicalError('unavailable')
    }
    if (!record(raw) || raw.error !== null) {
      const code = record(raw) && record(raw.error) ? raw.error.code : null
      throw currentClinicalError(
        code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
      )
    }
    try {
      const data = packet.parse(structuredClone(raw.data))
      if (
        data.period !== input.p_period ||
        data.from !== input.p_expected_from ||
        data.to !== input.p_expected_to
      )
        throw new Error('scope mismatch')
      let previous = ''
      for (const item of data.rows) {
        if (item.date < data.from || item.date > data.to || item.date <= previous)
          throw new Error('invalid day')
        previous = item.date
      }
      return data.rows.map((item) => Object.freeze(item))
    } catch {
      throw currentClinicalError('invalid_response')
    }
  }
