import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { DailyStateLoadError, loadOfficialDailyState } from './daily-state-service.js'

interface FakeTable {
  rows?: unknown[]
  single?: unknown | null
  singleSequence?: Array<unknown | null>
  singleReads?: number
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
    const sequence = this.table.singleSequence
    if (sequence && sequence.length > 0) {
      const read = this.table.singleReads ?? 0
      this.table.singleReads = read + 1
      return {
        data: sequence[Math.min(read, sequence.length - 1)] ?? null,
        error: this.table.error ?? null,
      }
    }
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
  loadMealPattern: async () => ({
    expected: new Set(['cafe', 'almoco', 'jantar'] as const),
    activeDays: 10,
    countByType: { cafe: 10, almoco: 10, lanche: 2, jantar: 9, ceia: 0 },
    threshold: 0.5,
    fallbackUsed: false,
  }),
  loadSkippedMeals: async () => new Set<'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'>(),
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
          meal_logs: [
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
            {
              id: 'meal-cafe',
              meal_type: 'cafe',
              food_name: 'ovo',
              quantity_g: 50,
              kcal: 72,
              protein_g: 6,
              carbs_g: 0.4,
              fat_g: 5,
              consumed_at: '2026-07-20T09:00:00.000Z',
              source: 'canonical_exact',
            },
          ],
          workout_logs: [
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
    expect(state.meals.map((meal) => meal.id)).toEqual(['meal-cafe', 'meal-1'])
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

  it('retries instead of returning snapshot totals mixed with logs from another write', async () => {
    const oldSnapshot = {
      id: 'snapshot-1',
      calories_consumed: 100,
      calories_target: 1_900,
      protein_g: 10,
      protein_target: 140,
      carbs_g: 12,
      fat_g: 2,
      exercise_calories: 0,
      water_consumed_ml: 0,
      current_protocol: 'recomposicao',
      day_closed: false,
      day_status: 'complete',
      updated_at: '2026-07-20T14:00:00.000Z',
      meal_logs: [
        {
          id: 'meal-1',
          meal_type: 'cafe',
          food_name: 'item antigo',
          quantity_g: 100,
          kcal: 100,
          protein_g: 10,
          carbs_g: 12,
          fat_g: 2,
          consumed_at: '2026-07-20T13:00:00.000Z',
          source: 'canonical_exact',
        },
      ],
      workout_logs: [],
    }
    const newSnapshot = {
      ...oldSnapshot,
      calories_consumed: 250,
      protein_g: 20,
      carbs_g: 30,
      fat_g: 5,
      updated_at: '2026-07-20T14:01:00.000Z',
      meal_logs: [
        ...oldSnapshot.meal_logs,
        {
          id: 'meal-2',
          meal_type: 'almoco',
          food_name: 'item novo',
          quantity_g: 100,
          kcal: 150,
          protein_g: 10,
          carbs_g: 18,
          fat_g: 3,
          consumed_at: '2026-07-20T14:01:00.000Z',
          source: 'canonical_exact',
        },
      ],
    }
    const db = fakeSupabase({
      user_profiles: { single: null },
      daily_snapshots: {
        singleSequence: [oldSnapshot, newSnapshot, newSnapshot, newSnapshot],
      },
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

    expect(state.consumed.calories_kcal).toBe(250)
    expect(state.meals.map((meal) => meal.id)).toEqual(['meal-1', 'meal-2'])
    expect(db.queries.filter((table) => table === 'daily_snapshots')).toHaveLength(4)
  })

  it('fails closed when the snapshot changes during both consistency attempts', async () => {
    const snapshot = (version: number) => ({
      id: 'snapshot-1',
      calories_consumed: version * 100,
      calories_target: 1_900,
      protein_g: version * 10,
      protein_target: 140,
      carbs_g: version * 12,
      fat_g: version * 2,
      exercise_calories: 0,
      water_consumed_ml: 0,
      current_protocol: 'recomposicao',
      day_closed: false,
      day_status: 'complete',
      updated_at: `2026-07-20T14:0${version}:00.000Z`,
      meal_logs: [],
      workout_logs: [],
    })
    const db = fakeSupabase({
      user_profiles: { single: null },
      daily_snapshots: {
        singleSequence: [snapshot(1), snapshot(2), snapshot(3), snapshot(4)],
      },
      user_progress: { single: null },
      pending_registrations: { rows: [] },
    })

    await expect(
      loadOfficialDailyState(
        db.client as never,
        'user-1',
        'UTC',
        new Date('2026-07-20T15:00:00.000Z'),
        dependencies,
      ),
    ).rejects.toEqual(new DailyStateLoadError('daily state consistency'))
    expect(db.queries.filter((table) => table === 'daily_snapshots')).toHaveLength(4)
  })
})
