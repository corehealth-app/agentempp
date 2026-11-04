import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { calcMealMacros } from './meal-pipeline.js'

const OWNER = 'c3a00000-0000-4000-8000-000000000001'
const AS_OF = '2026-11-03T12:00:00.123456Z'
const history = (name = 'iogurte da casa', kcal = 80, protein = 6, carbs = 10, fat = 2) => ({
  id: 'c3a00000-0000-4000-8000-000000000002',
  user_id: OWNER,
  created_at: '2026-11-02T12:00:00.000000+00:00',
  food_name: name,
  food_db_id: 777,
  quantity_g: 100,
  kcal,
  protein_g: protein,
  carbs_g: carbs,
  fat_g: fat,
  source: 'canonical_exact',
  food_db: { is_verified: true },
})
type History = ReturnType<typeof history>
const food = (name = 'queijo parmesao') => ({
  id: 888,
  name_pt: name,
  category: 'laticinios',
  similarity: 1,
  country_code: 'BR',
  kcal_per_100g: 453,
  protein_g: 35,
  carbs_g: 0,
  fat_g: 34,
  fiber_g: 0,
})
function service(
  options: {
    foods?: ReturnType<typeof food>[]
    corrections?: unknown[]
    legacyHistory?: History[]
    correctionGate?: { promise: Promise<unknown[]>; started: () => void }
  } = {},
) {
  const reads: string[] = [],
    lookbacks: string[] = [],
    events: unknown[] = []
  const chain = (rows: unknown[], correction: boolean) => {
    if (correction && options.correctionGate) options.correctionGate.started()
    const pending =
      correction && options.correctionGate ? options.correctionGate.promise : Promise.resolve(rows)
    const q = pending.then((data) => ({ data, error: null })) as Promise<unknown> &
      Record<string, unknown>
    for (const method of ['select', 'eq', 'or', 'neq', 'order', 'limit', 'in', 'gt', 'ilike'])
      q[method] = () => q
    q.gte = (_field: string, value: string) => {
      if (correction) lookbacks.push(value)
      return q
    }
    return q
  }
  const db = {
    rpc: async () => ({ data: options.foods ?? [], error: null }),
    from(table: string) {
      reads.push(table)
      if (table === 'user_food_corrections') return chain(options.corrections ?? [], true)
      if (table === 'meal_logs') {
        if (!options.legacyHistory) throw new Error('unexpected live history read')
        return chain(options.legacyHistory, false)
      }
      if (table === 'product_events')
        return {
          insert: async (value: unknown) => {
            events.push(value)
            return { data: null, error: null }
          },
        }
      throw new Error(`unexpected table ${table}`)
    },
  } as unknown as ServiceClient
  return { db, reads, lookbacks, events }
}
function reader(rows: History[] = [history()]) {
  const queries: Array<{ kind: string; foodName: string | null }> = []
  return {
    ownerId: OWNER,
    asOf: AS_OF,
    queries,
    async read(kind: 'trusted_recent' | 'exact_median', foodName: string | null) {
      queries.push({ kind, foodName })
      return rows
    },
  }
}

describe('meal calculation with a bound real-source port', () => {
  it('calculates trusted history facts from the port without consulting live meal rows', async () => {
    const state = service(),
      source = reader()
    const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
    const result = await calcMealMacros(
      state.db,
      [{ food_name: 'iogurte da casa', quantity_g: 200 }],
      'BR',
      OWNER,
      options,
    )
    expect(result.items).toMatchObject([
      { source: 'history', matched_taco_id: 777, kcal: 160, protein_g: 12, carbs_g: 20, fat_g: 4 },
    ])
    expect(state.reads).not.toContain('meal_logs')
    expect(source.queries).toEqual([{ kind: 'trusted_recent', foodName: null }])
    expect(state.lookbacks).toEqual(['2026-10-04T12:00:00.123Z'])
  })

  it('uses the actual median row set after a frozen trusted-history miss and collects its audit', async () => {
    const state = service(),
      queries: Array<{ kind: string; foodName: string | null }> = [],
      audits: unknown[] = []
    const source = {
      ownerId: OWNER,
      asOf: AS_OF,
      async read(kind: 'trusted_recent' | 'exact_median', foodName: string | null) {
        queries.push({ kind, foodName })
        return kind === 'trusted_recent'
          ? []
          : [
              history('creme da casa', 100, 2, 10, 1),
              {
                ...history('creme da casa', 300, 6, 30, 3),
                id: 'c3a00000-0000-4000-8000-000000000003',
              },
            ]
      },
    }
    const options = {
      consumptionPolicy: 'consumed-meal-v1' as const,
      sourceReader: source,
      auditSink: (event: unknown) => {
        audits.push(event)
      },
    }
    const result = await calcMealMacros(
      state.db,
      [{ food_name: 'creme da casa', quantity_g: 50 }],
      'BR',
      OWNER,
      options,
    )
    expect(result.items).toMatchObject([
      { source: 'history', kcal: 100, protein_g: 2, carbs_g: 10, fat_g: 1 },
    ])
    expect(queries).toEqual([
      { kind: 'trusted_recent', foodName: null },
      { kind: 'exact_median', foodName: 'creme da casa' },
    ])
    expect(audits).toMatchObject([
      {
        event: 'meal_calc.history_reused',
        properties: { source_log_count: 2, kcal_per_100g_median: 200, kcal_result: 100 },
      },
    ])
    expect(state.events).toEqual([])
  })

  it('pins policy and input facts before the first await', async () => {
    let ready!: () => void, release!: (rows: unknown[]) => void
    const started = new Promise<void>((resolve) => {
      ready = resolve
    })
    const gate = new Promise<unknown[]>((resolve) => {
      release = resolve
    })
    const rice = {
      ...food('Arroz, tipo 1, cozido'),
      id: 160,
      kcal_per_100g: 128.26,
      protein_g: 2.52,
      carbs_g: 28.06,
      fat_g: 0.23,
    }
    const state = service({
      foods: [rice],
      correctionGate: { promise: gate, started: () => ready() },
    })
    const source = reader([]),
      input = { food_name: 'arroz', quantity_g: 100 },
      items = [input]
    const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
    const pending = calcMealMacros(state.db, items, 'BR', OWNER, options)
    await started
    Object.assign(options, {
      consumptionPolicy: undefined,
      sourceReader: {
        ownerId: 'foreign',
        asOf: 'bad',
        read: async () => {
          throw new Error('swapped source')
        },
      },
    })
    Object.assign(source, {
      ownerId: 'foreign',
      asOf: 'bad',
      read: async () => {
        throw new Error('swapped reader')
      },
    })
    input.food_name = 'arroz cru'
    input.quantity_g = 1000
    release([])
    const result = await pending
    expect(result.items).toMatchObject([
      {
        food_name: 'arroz branco cozido',
        quantity_g: 100,
        kcal: 128.3,
        protein_g: 2.52,
        carbs_g: 28.06,
        fat_g: 0.23,
      },
    ])
    expect(state.lookbacks).toEqual(['2026-10-04T12:00:00.123Z'])
  })

  it('rejects a foreign owner or invalid source clock before any database I/O', async () => {
    for (const change of [
      { ownerId: 'c3a00000-0000-4000-8000-000000000099' },
      { asOf: '2026-02-30T12:00:00Z' },
      { asOf: 'invalid' },
    ]) {
      const state = service(),
        source = Object.assign(reader(), change)
      const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
      await expect(
        calcMealMacros(
          state.db,
          [{ food_name: 'iogurte da casa', quantity_g: 100 }],
          'BR',
          OWNER,
          options,
        ),
      ).rejects.toMatchObject({ name: 'ConsumedFoodReferenceUnavailableError' })
      expect(state.reads).toEqual([])
    }
  })

  it('a failed optional audit collector does not fail nutrition or fall back to a database write', async () => {
    const state = service({ foods: [food()] }),
      source = reader([])
    const options = {
      consumptionPolicy: 'consumed-meal-v1' as const,
      sourceReader: source,
      auditSink: () => {
        throw new Error('private collector failure')
      },
    }
    const result = await calcMealMacros(
      state.db,
      [
        {
          food_name: 'queijo parmesao',
          quantity_g: 100,
          approved_nutrition: { kcal: 100000, protein_g: 0, carbs_g: 0, fat_g: 0 },
        },
      ],
      'BR',
      OWNER,
      options,
    )
    expect(result.items).toMatchObject([{ kcal: 453, protein_g: 35, carbs_g: 0, fat_g: 34 }])
    expect(state.events).toEqual([])
  })
  it('keeps the original bound reader and correction clock across callback alias mutation', async () => {
    let ready!: () => void, release!: (rows: unknown[]) => void
    const started = new Promise<void>((resolve) => {
      ready = resolve
    })
    const gate = new Promise<unknown[]>((resolve) => {
      release = resolve
    })
    const state = service({ correctionGate: { promise: gate, started: () => ready() } }),
      source = reader()
    const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
    const pending = calcMealMacros(
      state.db,
      [
        { food_name: 'iogurte da casa', quantity_g: 100 },
        { food_name: 'iogurte da casa', quantity_g: 100 },
      ],
      'BR',
      OWNER,
      options,
    )
    await started
    Object.assign(source, {
      ownerId: 'foreign',
      asOf: 'bad',
      read: async () => {
        throw new Error('swapped source')
      },
    })
    release([])
    const result = await pending
    expect(result.totals).toMatchObject({ kcal: 160, protein_g: 12, carbs_g: 20, fat_g: 4 })
    expect(state.lookbacks).toEqual(['2026-10-04T12:00:00.123Z', '2026-10-04T12:00:00.123Z'])
  })

  it('fails a real source outage instead of substituting a live query or invented estimate', async () => {
    const state = service(),
      source = reader()
    source.read = async () => {
      throw new Error('synthetic source unavailable')
    }
    const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
    await expect(
      calcMealMacros(
        state.db,
        [{ food_name: 'iogurte da casa', quantity_g: 100 }],
        'BR',
        OWNER,
        options,
      ),
    ).rejects.toThrow('synthetic source unavailable')
    expect(state.reads).not.toContain('meal_logs')
    expect(state.events).toEqual([])
  })

  it('rejects foreign-owned historical rows returned by an otherwise bound source', async () => {
    const state = service(),
      source = reader([{ ...history(), user_id: 'c3a00000-0000-4000-8000-000000000099' }])
    const options = { consumptionPolicy: 'consumed-meal-v1' as const, sourceReader: source }
    await expect(
      calcMealMacros(
        state.db,
        [{ food_name: 'iogurte da casa', quantity_g: 100 }],
        'BR',
        OWNER,
        options,
      ),
    ).rejects.toMatchObject({ name: 'ConsumedFoodReferenceUnavailableError' })
    expect(state.reads).not.toContain('meal_logs')
  })

  it('retains default legacy history reads, current clock and database audit effects', async () => {
    const now = vi.spyOn(Date, 'now').mockReturnValue(Date.parse('2035-01-01T00:00:00Z'))
    try {
      const state = service({ legacyHistory: [history()] })
      const result = await calcMealMacros(
        state.db,
        [{ food_name: 'iogurte da casa', quantity_g: 200 }],
        'BR',
        OWNER,
      )
      expect(result.totals).toMatchObject({ kcal: 160, protein_g: 12, carbs_g: 20, fat_g: 4 })
      expect(state.reads).toContain('meal_logs')
      expect(state.lookbacks).toEqual(['2034-12-02T00:00:00.000Z'])
      const audit = service({ foods: [food()] })
      const ordinary = await calcMealMacros(
        audit.db,
        [{ food_name: 'queijo parmesao', quantity_g: 100, user_kcal: 100000 }],
        'BR',
        OWNER,
      )
      expect(ordinary.totals).toMatchObject({ kcal: 453, protein_g: 35, carbs_g: 0, fat_g: 34 })
      expect(audit.events).toMatchObject([{ event: 'meal_calc.user_kcal_rejected' }])
    } finally {
      now.mockRestore()
    }
  })
})
