import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  createNutritionWindowCapture,
  type NutritionWindowQuery,
  type NutritionWindowReadPort,
} from './nutrition-window-repository'
import { nutritionWindowDates } from './nutrition-window-service'

const OWNER = 'a1111111-1111-4111-8111-111111111111'
type UnitRead = { owner_id: string; items: Array<{ meal: Record<string, unknown> }> }
function harness(badCount = false, units?: UnitRead) {
  const calls: Array<{ table: string; method: string; args: unknown[] }> = []
  const port: NutritionWindowReadPort = {
    rpc: async (name, args) => {
      calls.push({ table: 'rpc', method: name, args: [args] })
      return { data: units, error: null }
    },
    from(table) {
      const response = Promise.resolve({
        data: table === 'meal_logs' && units ? units.items.map((u) => u.meal) : [],
        error: null,
        count:
          badCount && table === 'meal_logs'
            ? 1
            : table === 'meal_logs' && units
              ? units.items.length
              : 0,
      })
      let q: NutritionWindowQuery
      const chain =
        (method: string) =>
        (...args: unknown[]) => {
          calls.push({ table, method, args })
          return q
        }
      q = {
        select: chain('select'),
        eq: chain('eq'),
        gte: chain('gte'),
        lt: chain('lt'),
        lte: chain('lte'),
        in: chain('in'),
        or: chain('or'),
        order: chain('order'),
        limit: chain('limit'),
        // biome-ignore lint/suspicious/noThenProperty: this implements the actual PostgREST PromiseLike query contract
        then: response.then.bind(response),
      }
      return q
    },
  }
  return { port, calls }
}
describe('Owned bounded nutrition capture has only read capabilities', () => {
  it('uses the exact server week bounds and exact-count owner filters for every table', async () => {
    const f = harness(),
      window = nutritionWindowDates('America/New_York', '2026-11-01')
    const value = await createNutritionWindowCapture(f.port, OWNER)(window)
    expect(value).toMatchObject({
      meals: [],
      snapshots: [],
      prescriptions: [],
      counts: { meals: 0, snapshots: 0, prescriptions: 0 },
    })
    expect(new Set(f.calls.map((c) => c.table))).toEqual(
      new Set(['meal_logs', 'daily_snapshots', 'prescriptions']),
    )
    for (const table of ['meal_logs', 'daily_snapshots', 'prescriptions']) {
      expect(
        f.calls.some(
          (c) =>
            c.table === table &&
            c.method === 'eq' &&
            c.args[0] === 'user_id' &&
            c.args[1] === OWNER,
        ),
      ).toBe(true)
      expect(
        f.calls.some(
          (c) =>
            c.table === table &&
            c.method === 'select' &&
            (c.args[1] as { count: string })?.count === 'exact',
        ),
      ).toBe(true)
    }
    expect(
      f.calls.some(
        (c) => c.table === 'meal_logs' && c.method === 'gte' && c.args[1] === window.startUTC,
      ),
    ).toBe(true)
    expect(
      f.calls.some(
        (c) => c.table === 'meal_logs' && c.method === 'lt' && c.args[1] === window.endUTC,
      ),
    ).toBe(true)
  })
  it('binds the one service-only readonly unit RPC to the exact owned current meal set', async () => {
    const root = JSON.parse(
      readFileSync(
        new URL(
          '../../../../ios/BodyFlow/BodyFlowTests/Fixtures/NutritionWindowUnitsSQLPieces.json',
          import.meta.url,
        ),
        'utf8',
      ),
    ) as { pieces: Array<{ observation: UnitRead }> }
    const units = root.pieces[0].observation,
      f = harness(false, units)
    const result = await createNutritionWindowCapture(
      f.port,
      units.owner_id,
    )(nutritionWindowDates('UTC', '2026-11-05'))
    expect(result.units).toHaveLength(1)
    expect(f.calls.filter((c) => c.table === 'rpc')).toEqual([
      {
        table: 'rpc',
        method: 'read_nutrition_window_units',
        args: [{ p_user_id: units.owner_id, p_meal_ids: units.items.map((u) => u.meal.id) }],
      },
    ])
    expect(result.units[0].meal).toEqual(units.items[0].meal)
  })
  it('refuses incomplete count results instead of publishing a fake empty week', async () => {
    const f = harness(true)
    await expect(
      createNutritionWindowCapture(f.port, OWNER)(nutritionWindowDates('UTC', '2026-11-04')),
    ).rejects.toThrow()
  })
})
