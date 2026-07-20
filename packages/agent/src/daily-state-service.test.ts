import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { loadOfficialDailyState } from './daily-state-service.js'

interface FakeTable {
  rows?: unknown[]
  single?: unknown | null
  error?: { message: string } | null
}

class FakeQuery {
  constructor(private readonly table: FakeTable) {}

  select() {
    return this
  }

  eq() {
    return this
  }

  gt() {
    return this
  }

  order() {
    return this
  }

  limit() {
    return this
  }

  async maybeSingle() {
    return { data: this.table.single ?? null, error: this.table.error ?? null }
  }

  // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
  then<TResult1 = { data: unknown[]; error: { message: string } | null }, TResult2 = never>(
    onfulfilled?:
      | ((value: { data: unknown[]; error: { message: string } | null }) => TResult1)
      | null,
    onrejected?: ((reason: unknown) => TResult2) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve({ data: this.table.rows ?? [], error: this.table.error ?? null }).then(
      onfulfilled,
      onrejected,
    )
  }
}

function fakeSupabase(tables: Record<string, FakeTable>) {
  const queries: string[] = []
  return {
    queries,
    client: {
      from(table: string) {
        queries.push(table)
        const config = tables[table]
        if (!config) throw new Error(`unexpected table: ${table}`)
        return new FakeQuery(config)
      },
    },
  }
}

const dependencies = {
  loadConfig: async () => DEFAULT_CALC_CONFIG,
  loadGap: async () => ({
    pattern: {
      expected: new Set(['cafe', 'almoco', 'jantar'] as const),
      activeDays: 10,
      countByType: { cafe: 10, almoco: 10, lanche: 2, jantar: 9, ceia: 0 },
      threshold: 0.5,
      fallbackUsed: false,
    },
    registered: new Set(['cafe', 'almoco'] as const),
    skipped: new Set<'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'>(),
    gap: new Set(['jantar'] as const),
  }),
}

describe('loadOfficialDailyState', () => {
  it('assembles the official state and exposes only safe pending metadata', async () => {
    const db = fakeSupabase({
      user_profiles: {
        single: {
          sex: 'masculino',
          birth_date: '1990-01-01',
          height_cm: 180,
          weight_kg: 82,
          body_fat_percent: 18,
          activity_level: 'moderado',
          training_frequency: 4,
          water_intake: 'moderado',
          hunger_level: 'moderada',
          current_protocol: 'recomposicao',
          goal_type: 'BF',
          goal_value: 15,
          deficit_level: 500,
        },
      },
      daily_snapshots: {
        single: {
          id: 'snapshot-1',
          calories_consumed: 1_200,
          calories_target: 1_935,
          protein_g: 90,
          protein_target: 148,
          carbs_g: 110,
          fat_g: 42,
          exercise_calories: 300,
          water_consumed_ml: 1_500,
          current_protocol: 'recomposicao',
          day_closed: false,
          day_status: 'pending_close',
          updated_at: '2026-07-20T14:00:00.000Z',
        },
      },
      user_progress: {
        single: {
          deficit_block: 2_500,
          blocks_completed: 1,
          updated_at: '2026-07-20T14:01:00.000Z',
        },
      },
      pending_registrations: {
        rows: [
          {
            id: 'pending-1',
            proposal: {
              kind: 'meal',
              mealType: 'jantar',
              source_text: 'must never leave the backend',
              items: [{ name: 'private detail' }],
            },
            status: 'pending',
            created_at: '2026-07-20T14:02:00.000Z',
            expires_at: '2026-07-20T16:00:00.000Z',
          },
          {
            id: 'pending-legacy',
            proposal: {
              kind: 'meal',
              mealType: 'private free-form text',
            },
            status: 'pending',
            created_at: '2026-07-20T14:01:30.000Z',
            expires_at: '2026-07-20T16:00:00.000Z',
          },
        ],
      },
      meal_logs: {
        rows: [
          {
            id: 'meal-1',
            meal_type: 'almoco',
            food_name: 'arroz',
            quantity_g: 100,
            kcal: 130,
            protein_g: 2.5,
            carbs_g: 28,
            fat_g: 0.3,
            consumed_at: '2026-07-20T13:00:00.000Z',
            source: 'canonical_exact',
          },
        ],
      },
      workout_logs: {
        rows: [
          {
            id: 'workout-1',
            workout_type: 'musculacao',
            duration_min: 40,
            estimated_kcal: 300,
            intensity: 'moderada',
            performed_at: '2026-07-20T13:30:00.000Z',
          },
        ],
      },
    })

    const state = await loadOfficialDailyState(
      db.client as never,
      'user-1',
      'America/New_York',
      new Date('2026-07-20T15:00:00.000Z'),
      dependencies,
    )

    expect(state.targets).toEqual({
      calories_kcal: 1_935,
      protein_g: 148,
      source: 'daily_snapshot',
      calories_source: 'daily_snapshot',
      protein_source: 'daily_snapshot',
    })
    expect(state.remaining_food_kcal).toBe(735)
    expect(state.daily_balance_kcal).toBe(-1_035)
    expect(state.meals[0]).toMatchObject({ nutrition_source: 'canonical_exact' })
    expect(state.pending_actions.registrations).toEqual([
      {
        id: 'pending-1',
        kind: 'meal',
        meal_type: 'jantar',
        created_at: '2026-07-20T14:02:00.000Z',
        expires_at: '2026-07-20T16:00:00.000Z',
      },
      {
        id: 'pending-legacy',
        kind: 'meal',
        meal_type: null,
        created_at: '2026-07-20T14:01:30.000Z',
        expires_at: '2026-07-20T16:00:00.000Z',
      },
    ])
    expect(JSON.stringify(state)).not.toContain('must never leave the backend')
    expect(JSON.stringify(state)).not.toContain('private free-form text')
    expect(state.completion_status.status).toBe('pending_information')
  })

  it('does not query item logs when no snapshot exists', async () => {
    const db = fakeSupabase({
      user_profiles: { single: null },
      daily_snapshots: { single: null },
      user_progress: { single: null },
      pending_registrations: { rows: [] },
    })

    const state = await loadOfficialDailyState(
      db.client as never,
      'user-1',
      'UTC',
      new Date('2026-07-20T15:00:00.000Z'),
      dependencies,
    )

    expect(state.meals).toEqual([])
    expect(state.workouts).toEqual([])
    expect(db.queries).not.toContain('meal_logs')
    expect(db.queries).not.toContain('workout_logs')
  })
})
