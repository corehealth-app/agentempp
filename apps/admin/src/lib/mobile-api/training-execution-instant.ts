/** Pure feature leaf: training must not load the meal journal's codecs/writers
 * merely to compare timestamps. Same calendar/offset/nanosecond semantics. */
import { z } from 'zod'
import { MobileApiError } from './http'

const clock = z
  .string()
  .datetime({ offset: true })
  .refine((raw) => {
    const date = raw.slice(0, 10),
      parsed = new Date(`${date}T00:00:00Z`)
    return (
      !raw.startsWith('0000') &&
      Number.isFinite(Date.parse(raw)) &&
      Number.isFinite(parsed.getTime()) &&
      parsed.toISOString().slice(0, 10) === date &&
      !/\.\d{10}/u.test(raw)
    )
  })
export function trainingExecutionInstant(raw: string): bigint {
  if (!clock.safeParse(raw).success)
    throw new MobileApiError(
      503,
      'training_execution_state_unavailable',
      'The training execution clock is unavailable.',
    )
  const fraction = /\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/u.exec(raw)?.[1] ?? ''
  return BigInt(Math.floor(Date.parse(raw) / 1000)) * 1000000000n + BigInt(fraction.padEnd(9, '0'))
}
