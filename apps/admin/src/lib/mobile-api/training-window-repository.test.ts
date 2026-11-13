import { describe, expect, it } from 'vitest'
import { nutritionWindowDates } from './nutrition-window-service'
import {
  createTrainingWindowCapture,
  type TrainingWindowQuery,
  type TrainingWindowReadPort,
} from './training-window-repository'

const OWNER = 'a1111111-1111-4111-8111-111111111111'
function harness(result: { data: unknown[] | null; count: number | null; error: unknown | null }) {
  const calls: Array<{ method: string; args: unknown[] }> = []
  const port: TrainingWindowReadPort = {
    from(table) {
      calls.push({ method: 'from', args: [table] })
      let q: TrainingWindowQuery
      const step =
        (method: string) =>
        (...args: unknown[]) => {
          calls.push({ method, args })
          return q
        }
      q = Object.assign(Promise.resolve(result), {
        select: step('select'),
        eq: step('eq'),
        gte: step('gte'),
        lt: step('lt'),
        order: step('order'),
        limit: step('limit'),
      })
      return q
    },
  }
  return { port, calls }
}
describe('Bounded owned recorded workout capture', () => {
  it('uses exact complete count, original owner and DST civil bounds with deterministic ordering', async () => {
    const f = harness({ data: [], count: 0, error: null }),
      window = nutritionWindowDates('America/New_York', '2026-11-01')
    expect(await createTrainingWindowCapture(f.port, OWNER)(window)).toEqual({
      workouts: [],
      count: 0,
    })
    expect(f.calls).toEqual([
      { method: 'from', args: ['workout_logs'] },
      {
        method: 'select',
        args: [
          'id, user_id, workout_type, duration_min, estimated_kcal, intensity, performed_at',
          { count: 'exact' },
        ],
      },
      { method: 'eq', args: ['user_id', OWNER] },
      { method: 'gte', args: ['performed_at', '2026-10-26T04:00:00.000Z'] },
      { method: 'lt', args: ['performed_at', '2026-11-02T05:00:00.000Z'] },
      { method: 'order', args: ['performed_at', { ascending: true }] },
      { method: 'order', args: ['id', { ascending: true }] },
      { method: 'limit', args: [1001] },
    ])
  })
  for (const [label, result] of [
    ['truncation', { data: [], count: 10, error: null }],
    ['count unavailable', { data: [], count: null, error: null }],
    ['query error', { data: [], count: 0, error: { message: 'private' } }],
    ['data unavailable', { data: null, count: 0, error: null }],
    ['too many', { data: Array.from({ length: 1001 }, () => ({})), count: 1001, error: null }],
  ] as const)
    it(`refuses ${label}`, async () => {
      const f = harness({ ...result, data: result.data === null ? null : [...result.data] })
      await expect(
        createTrainingWindowCapture(f.port, OWNER)(nutritionWindowDates('UTC', '2026-11-04')),
      ).rejects.toMatchObject({ status: 503 })
    })
  it('rejects an invalid owner before invoking the port', () => {
    const f = harness({ data: [], count: 0, error: null })
    expect(() => createTrainingWindowCapture(f.port, 'not-an-owner')).toThrow()
    expect(f.calls).toEqual([])
  })
})
