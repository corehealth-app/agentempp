import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { DailyStateLoadError, loadOfficialDailyState } from './daily-state-service.js'

interface FakeTable {
  rows?: unknown[]
  rowsSequence?: unknown[][]
  rowReads?: number
  single?: unknown | null
  singleSequence?: Array<unknown | null>
  singleReads?: number
  error?: { message: string } | null
}

interface FakeRpc {
  results: Array<{ data: unknown; error: { message: string } | null }>
  reads?: number
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

  gte() {
    return this
  }

  lt() {
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
    const sequence = this.table.rowsSequence
    const read = this.table.rowReads ?? 0
    if (sequence && sequence.length > 0) this.table.rowReads = read + 1
    const rows = sequence ? sequence[Math.min(read, sequence.length - 1)] : this.table.rows
    return Promise.resolve({ data: rows ?? [], error: this.table.error ?? null }).then(
      onfulfilled,
      onrejected,
    )
  }
}

function fakeSupabase(tables: Record<string, FakeTable>, rpcs: Record<string, FakeRpc> = {}) {
  const queries: string[] = []
  const rpcCalls: Array<{ functionName: string; params: Record<string, unknown> }> = []
  const optionalTables: Record<string, FakeTable> = {
    notification_preferences: { single: null },
    routine_items: { rows: [] },
    routine_adherence_logs: { rows: [] },
  }
  return {
    queries,
    rpcCalls,
    client: {
      from(table: string) {
        queries.push(table)
        const config = tables[table] ?? optionalTables[table]
        if (!config) throw new Error(`unexpected table: ${table}`)
        return new FakeQuery(config)
      },
      async rpc(functionName: string, params: Record<string, unknown>) {
        rpcCalls.push({ functionName, params })
        const key = `${functionName}:${String(params.p_item_type ?? '')}`
        const config = rpcs[key]
        if (!config) {
          return { data: { local_date: '2026-07-20', items: [] }, error: null }
        }
        const read = config.reads ?? 0
        config.reads = read + 1
        return config.results[Math.min(read, config.results.length - 1)]
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

const SUPPLEMENT_ID = '00000000-0000-0000-0000-000000000601'
const MEDICATION_ID = '00000000-0000-0000-0000-000000000602'
const MORNING_RULE_ID = '00000000-0000-0000-0000-000000000611'
const EVENING_RULE_ID = '00000000-0000-0000-0000-000000000612'
const MEDICATION_RULE_ID = '00000000-0000-0000-0000-000000000613'

function routineItem(input: {
  id: string
  itemType: 'supplement' | 'medication'
  name: string
  doseText: string
  origin: 'user' | 'professional' | 'protocol' | 'other'
  schedules: unknown[]
}) {
  return {
    id: input.id,
    item_type: input.itemType,
    name: input.name,
    dose_text: input.doseText,
    origin: input.origin,
    reminders_enabled: true,
    active: true,
    archived_at: null,
    version: 2,
    created_at: '2026-07-18T10:00:00.000Z',
    updated_at: '2026-07-19T10:00:00.000Z',
    schedules: input.schedules,
  }
}

function routineSchedule(input: {
  id: string
  localTime: string
  scheduledFor: string
  status: 'pending' | 'taken' | 'snoozed' | 'skipped' | 'missed'
  lastActionAt?: string | null
  snoozedUntil?: string | null
}) {
  return {
    id: input.id,
    local_time: input.localTime,
    weekdays: [0, 1, 2, 3, 4, 5, 6],
    occurrence: {
      occurrence_key: input.id.endsWith('11') ? 'a'.repeat(64) : 'b'.repeat(64),
      scheduled_for: input.scheduledFor,
      status: input.status,
      last_action_at: input.lastActionAt ?? null,
      snoozed_until: input.snoozedUntil ?? null,
    },
  }
}

describe('loadOfficialDailyState', () => {
  it('loads exact occurrences for both literal types from the canonical stored-timezone read model', async () => {
    const supplementPage = {
      local_date: '2026-07-20',
      items: [
        routineItem({
          id: SUPPLEMENT_ID,
          itemType: 'supplement',
          name: 'Creatina',
          doseText: '3 g',
          origin: 'professional',
          schedules: [
            routineSchedule({
              id: MORNING_RULE_ID,
              localTime: '08:00',
              scheduledFor: '2026-07-19T12:00:00.000Z',
              status: 'taken',
              lastActionAt: '2026-07-19T12:04:00.000Z',
            }),
            routineSchedule({
              id: EVENING_RULE_ID,
              localTime: '20:00',
              scheduledFor: '2026-07-20T00:00:00.000Z',
              status: 'pending',
            }),
          ],
        }),
      ],
    }
    const medicationPage = {
      local_date: '2026-07-20',
      items: [
        routineItem({
          id: MEDICATION_ID,
          itemType: 'medication',
          name: 'Item cadastrado',
          doseText: '1 unidade',
          origin: 'user',
          schedules: [
            routineSchedule({
              id: MEDICATION_RULE_ID,
              localTime: '07:00',
              scheduledFor: '2026-07-19T11:00:00.000Z',
              status: 'missed',
            }),
          ],
        }),
      ],
    }
    const db = fakeSupabase(
      {
        user_profiles: { single: null },
        daily_snapshots: { single: null },
        user_progress: { single: null },
        pending_registrations: { rows: [] },
      },
      {
        'list_mobile_routine_items:supplement': {
          results: [{ data: supplementPage, error: null }],
        },
        'list_mobile_routine_items:medication': {
          results: [{ data: medicationPage, error: null }],
        },
      },
    )
    const now = new Date('2026-07-20T01:00:00.000Z')

    const state = await loadOfficialDailyState(
      db.client as never,
      'user-1',
      'Pacific/Kiritimati',
      now,
      dependencies,
    )

    expect(state.local_date).toBe('2026-07-20')
    expect(db.queries).not.toContain('routine_items')
    expect(db.queries).not.toContain('routine_adherence_logs')
    expect(db.rpcCalls).toEqual([
      {
        functionName: 'list_mobile_routine_items',
        params: {
          p_user_id: 'user-1',
          p_item_type: 'supplement',
          p_include_archived: false,
          p_now: now.toISOString(),
        },
      },
      {
        functionName: 'list_mobile_routine_items',
        params: {
          p_user_id: 'user-1',
          p_item_type: 'medication',
          p_include_archived: false,
          p_now: now.toISOString(),
        },
      },
      {
        functionName: 'list_mobile_routine_items',
        params: {
          p_user_id: 'user-1',
          p_item_type: 'supplement',
          p_include_archived: false,
          p_now: now.toISOString(),
        },
      },
      {
        functionName: 'list_mobile_routine_items',
        params: {
          p_user_id: 'user-1',
          p_item_type: 'medication',
          p_include_archived: false,
          p_now: now.toISOString(),
        },
      },
    ])
    expect(state.supplements.items).toEqual([
      {
        id: SUPPLEMENT_ID,
        name: 'Creatina',
        dose_text: '3 g',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [
          { id: MORNING_RULE_ID, local_time: '08:00', weekdays: [0, 1, 2, 3, 4, 5, 6] },
          { id: EVENING_RULE_ID, local_time: '20:00', weekdays: [0, 1, 2, 3, 4, 5, 6] },
        ],
        occurrences: [
          {
            reminder_rule_id: MORNING_RULE_ID,
            scheduled_for: '2026-07-19T12:00:00.000Z',
            status: 'taken',
            last_action_at: '2026-07-19T12:04:00.000Z',
            snoozed_until: null,
          },
          {
            reminder_rule_id: EVENING_RULE_ID,
            scheduled_for: '2026-07-20T00:00:00.000Z',
            status: 'pending',
            last_action_at: null,
            snoozed_until: null,
          },
        ],
      },
    ])
    expect(state.medications.items[0]?.occurrences).toEqual([
      {
        reminder_rule_id: MEDICATION_RULE_ID,
        scheduled_for: '2026-07-19T11:00:00.000Z',
        status: 'missed',
        last_action_at: null,
        snoozed_until: null,
      },
    ])
    expect(JSON.stringify(state)).not.toContain('occurrence_key')
  })

  it.each([
    ['supplement and medication RPC dates disagree', '2026-07-20', '2026-07-19'],
    ['both RPC dates disagree with the official date', '2026-07-19', '2026-07-19'],
  ])('fails closed when %s', async (_name, supplementDate, medicationDate) => {
    const db = fakeSupabase(
      {
        user_profiles: { single: null },
        daily_snapshots: { single: null },
        user_progress: { single: null },
        pending_registrations: { rows: [] },
      },
      {
        'list_mobile_routine_items:supplement': {
          results: [{ data: { local_date: supplementDate, items: [] }, error: null }],
        },
        'list_mobile_routine_items:medication': {
          results: [{ data: { local_date: medicationDate, items: [] }, error: null }],
        },
      },
    )

    await expect(
      loadOfficialDailyState(
        db.client as never,
        'user-1',
        'UTC',
        new Date('2026-07-20T15:00:00.000Z'),
        dependencies,
      ),
    ).rejects.toEqual(new DailyStateLoadError('daily state routine items lookup'))
  })

  it.each([
    [
      'malformed supplement payload',
      { data: { local_date: '2026-07-19', items: [{}] }, error: null },
    ],
    ['failed medication RPC', { data: null, error: { message: 'private database detail' } }],
  ])('fails closed on a %s', async (_name, failedResult) => {
    const db = fakeSupabase(
      {
        user_profiles: { single: null },
        daily_snapshots: { single: null },
        user_progress: { single: null },
        pending_registrations: { rows: [] },
      },
      {
        'list_mobile_routine_items:supplement': {
          results: [
            failedResult.error
              ? { data: { local_date: '2026-07-19', items: [] }, error: null }
              : failedResult,
          ],
        },
        'list_mobile_routine_items:medication': {
          results: [
            failedResult.error
              ? failedResult
              : { data: { local_date: '2026-07-19', items: [] }, error: null },
          ],
        },
      },
    )

    await expect(
      loadOfficialDailyState(
        db.client as never,
        'user-1',
        'UTC',
        new Date('2026-07-19T15:00:00.000Z'),
        dependencies,
      ),
    ).rejects.toEqual(new DailyStateLoadError('daily state routine items lookup'))
  })

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
      notification_preferences: {
        single: {
          hydration_target_ml: 2_200,
          updated_at: '2026-07-20T14:03:00.000Z',
        },
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
    expect(state.hydration).toEqual({
      consumed_ml: 1_500,
      target_ml: 2_200,
      remaining_ml: 700,
      percentage: 68,
      status: 'in_progress',
    })
    expect(state.supplements).toEqual({ availability: 'not_configured', items: [] })
    expect(state.medications).toEqual({ availability: 'not_configured', items: [] })
    expect(state.updated_at).toBe('2026-07-20T14:03:00.000Z')
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
    expect(state.hydration).toMatchObject({ target_ml: null, status: 'not_recorded' })
    expect(state.supplements).toEqual({ availability: 'not_configured', items: [] })
    expect(state.medications).toEqual({ availability: 'not_configured', items: [] })
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

  it('retries instead of returning a routine page that changes during the state read', async () => {
    const snapshot = {
      id: 'snapshot-1',
      calories_consumed: 0,
      calories_target: 1_900,
      protein_g: 0,
      protein_target: 140,
      carbs_g: 0,
      fat_g: 0,
      exercise_calories: 0,
      water_consumed_ml: 0,
      current_protocol: 'recomposicao',
      day_closed: false,
      day_status: 'complete',
      updated_at: '2026-07-20T14:00:00.000Z',
      meal_logs: [],
      workout_logs: [],
    }
    const item = (name: string) =>
      routineItem({
        id: SUPPLEMENT_ID,
        itemType: 'supplement',
        name,
        doseText: '3 g',
        origin: 'user',
        schedules: [],
      })
    const oldPage = {
      local_date: '2026-07-20',
      items: [{ ...item('Nome antigo'), updated_at: '2026-07-20T13:00:00.000Z' }],
    }
    const newPage = {
      local_date: '2026-07-20',
      items: [{ ...item('Nome atual'), updated_at: '2026-07-20T14:01:00.000Z' }],
    }
    const db = fakeSupabase(
      {
        user_profiles: { single: null },
        daily_snapshots: { single: snapshot },
        user_progress: { single: null },
        pending_registrations: { rows: [] },
      },
      {
        'list_mobile_routine_items:supplement': {
          results: [
            { data: oldPage, error: null },
            { data: newPage, error: null },
            { data: newPage, error: null },
            { data: newPage, error: null },
          ],
        },
      },
    )

    const state = await loadOfficialDailyState(
      db.client as never,
      'user-1',
      'UTC',
      new Date('2026-07-20T15:00:00.000Z'),
      dependencies,
    )

    expect(state.supplements.items).toEqual([
      {
        id: SUPPLEMENT_ID,
        name: 'Nome atual',
        dose_text: '3 g',
        origin: 'user',
        reminders_enabled: true,
        schedules: [],
        occurrences: [],
      },
    ])
    expect(db.rpcCalls.filter((call) => call.params.p_item_type === 'supplement')).toHaveLength(4)
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
