import { describe, expect, it } from 'vitest'
import { validateMarcaRefeicaoPulada } from './marca_refeicao_pulada-guard.js'

function mockSupabase(
  options: {
    existingMealLogsCount?: number
    existingSkipCount?: number
    snapshotId?: string | null
  } = {},
) {
  const queries: Array<{ table: string; filters: Record<string, unknown> }> = []
  // biome-ignore lint/suspicious/noExplicitAny: fluent Supabase mock
  const from = (table: string): any => {
    const query = { table, filters: {} as Record<string, unknown> }
    queries.push(query)
    const result = () => {
      if (table === 'daily_snapshots') {
        return {
          data: options.snapshotId === null ? null : { id: options.snapshotId ?? 'snapshot-1' },
          error: null,
        }
      }
      if (table === 'product_events') {
        return { data: null, count: options.existingSkipCount ?? 0, error: null }
      }
      return { data: null, count: options.existingMealLogsCount ?? 0, error: null }
    }
    const chain: Record<string, unknown> = {}
    for (const method of ['select', 'gte', 'lte', 'lt', 'filter', 'limit']) {
      chain[method] = () => chain
    }
    chain.eq = (column: string, value: unknown) => {
      query.filters[column] = value
      return chain
    }
    chain.maybeSingle = async () => result()
    // biome-ignore lint/suspicious/noThenProperty: Supabase queries are intentionally thenable
    chain.then = (resolve: (value: ReturnType<typeof result>) => unknown) =>
      Promise.resolve(result()).then(resolve)
    return chain
  }
  return { client: { from }, queries }
}

describe('validateMarcaRefeicaoPulada — guard pós-LLM', () => {
  it('passa quando sem vision pendente e sem meal_logs', async () => {
    const db = mockSupabase()
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      { supabase: db.client as never, userId: 'u1' },
    )
    expect(r.ok).toBe(true)
  })

  it('S1: vision pendente recente do MESMO meal_type → reject', async () => {
    const db = mockSupabase()
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: db.client as never,
        userId: 'u1',
        visionPending: {
          mealContext: 'jantar com pão e queijo',
          ageMinutes: 30,
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('skip_blocked_vision_pending')
  })

  it('S1: vision contexto diferente do skip → permite', async () => {
    const db = mockSupabase()
    // foto de café, paciente pula jantar — refeições diferentes, OK skip
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: db.client as never,
        userId: 'u1',
        visionPending: {
          mealContext: 'café da manhã com pão',
          ageMinutes: 30,
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(true)
  })

  it('S1: vision > 4h → considera abandonada, permite skip', async () => {
    const db = mockSupabase()
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: db.client as never,
        userId: 'u1',
        visionPending: {
          mealContext: 'jantar com pão',
          ageMinutes: 300, // 5h
          items: [{ name: 'pão' }],
        },
      },
    )
    expect(r.ok).toBe(true)
  })

  it('S3: já há meal_logs do mesmo meal_type hoje → reject skip_after_registration', async () => {
    const db = mockSupabase({ existingMealLogsCount: 3 })
    const r = await validateMarcaRefeicaoPulada(
      { meal_type: 'almoco' },
      { supabase: db.client as never, userId: 'u1' },
    )
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toBe('skip_after_registration')
  })

  it('usa snapshot da data local da mensagem em Orlando, não o dia UTC', async () => {
    const db = mockSupabase()
    await validateMarcaRefeicaoPulada(
      { meal_type: 'ceia' },
      {
        supabase: db.client as never,
        userId: 'u1',
        userTimezone: 'America/New_York',
        referenceTimestamp: new Date('2026-07-11T03:30:00.000Z'),
      },
    )

    const snapshotQuery = db.queries.find((query) => query.table === 'daily_snapshots')
    expect(snapshotQuery?.filters.date).toBe('2026-07-10')
  })

  it('S2: skip já marcado na mesma data local → reject duplicate_skip', async () => {
    const db = mockSupabase({ existingSkipCount: 1 })
    const result = await validateMarcaRefeicaoPulada(
      { meal_type: 'jantar' },
      {
        supabase: db.client as never,
        userId: 'u1',
        userTimezone: 'America/New_York',
        referenceTimestamp: new Date('2026-07-11T03:30:00.000Z'),
      },
    )

    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.reason).toBe('duplicate_skip')
  })
})
