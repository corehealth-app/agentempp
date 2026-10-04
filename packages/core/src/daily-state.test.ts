import { afterEach, describe, expect, it } from 'vitest'
import {
  buildDailyState,
  DAILY_STATE_CALCULATION_VERSION,
  type DailyStateInput,
  type DailyStateSnapshotInput,
} from './daily-state.js'
import { DAY_BALANCE_AGAINST_EXPENDITURE } from './engine/balance.js'

const NOW = '2026-07-20T15:00:00.000Z'

function input(overrides: Partial<DailyStateInput> = {}): DailyStateInput {
  return {
    localDate: '2026-07-20',
    generatedAt: NOW,
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: 1_900, protein_target: 140 },
    snapshot: null,
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    mealGap: {
      expected: ['cafe', 'almoco', 'jantar'],
      registered: [],
      skipped: [],
      open: ['cafe', 'almoco', 'jantar'],
      reliable: false,
      activeDays: 0,
    },
    progress: null,
    ...overrides,
  }
}

describe('buildDailyState', () => {
  it('returns an official zero state for a day without records', () => {
    const state = buildDailyState(input())

    expect(state).toMatchObject({
      local_date: '2026-07-20',
      targets: {
        calories_kcal: 1_900,
        protein_g: 140,
        source: 'profile_calculation',
      },
      consumed: {
        calories_kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        source: 'empty_day',
      },
      remaining_food_kcal: 1_900,
      food_excess_kcal: 0,
      exercise_kcal: 0,
      daily_balance_kcal: -1_900,
      daily_balance_status: 'provisional',
      protein_status: {
        consumed_g: 0,
        target_g: 140,
        remaining_g: 140,
        percentage: 0,
        status: 'below_target',
      },
      hydration: {
        consumed_ml: 0,
        target_ml: null,
        remaining_ml: null,
        percentage: null,
        status: 'not_recorded',
      },
      supplements: { availability: 'not_configured', items: [] },
      medications: { availability: 'not_configured', items: [] },
      completion_status: {
        status: 'open',
        day_closed: false,
        has_sufficient_data: null,
      },
      calculation_version: DAILY_STATE_CALCULATION_VERSION,
      updated_at: null,
      generated_at: NOW,
    })
    expect(state.pending_actions.meal_gaps).toMatchObject({
      reliable: false,
      source: 'new_user_fallback',
    })
    expect(state.sources.hydration_target).toBe('unavailable')
    expect(state.block_7700).toMatchObject({
      availability: 'unavailable',
      current_kcal: null,
      percentage: null,
      completed_blocks: null,
      total_credited_kcal: null,
      source: 'unavailable',
    })
  })

  it('keeps food remaining separate from the final net balance on a complete day', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_800,
          caloriesTarget: 1_900,
          proteinG: 145,
          proteinTarget: 140,
          carbsG: 180,
          fatG: 62,
          exerciseCalories: 300,
          waterConsumedMl: 2_000,
          protocol: 'recomposicao',
          dayClosed: true,
          dayStatus: 'complete',
          updatedAt: '2026-07-20T14:55:00.000Z',
        },
      }),
    )

    expect(state.remaining_food_kcal).toBe(100)
    expect(state.food_excess_kcal).toBe(0)
    expect(state.daily_balance_kcal).toBe(-400)
    expect(state.daily_balance_status).toBe('final')
    expect(state.protein_status).toMatchObject({
      remaining_g: 0,
      percentage: 104,
      status: 'target_reached',
    })
    expect(state.completion_status).toEqual({
      status: 'complete',
      day_closed: true,
      has_sufficient_data: true,
    })
  })

  it('derives hydration progress only when an explicit target is available', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 0,
          caloriesTarget: 1_900,
          proteinG: 0,
          proteinTarget: 140,
          carbsG: 0,
          fatG: 0,
          exerciseCalories: 0,
          waterConsumedMl: 1_500,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-07-20T14:00:00.000Z',
        },
        hydrationTarget: {
          targetMl: 2_000,
          updatedAt: '2026-07-20T14:05:00.000Z',
        },
      }),
    )

    expect(state.hydration).toEqual({
      consumed_ml: 1_500,
      target_ml: 2_000,
      remaining_ml: 500,
      percentage: 75,
      status: 'in_progress',
    })
    expect(state.calculation_version).toBe(DAILY_STATE_CALCULATION_VERSION)
    expect(state.sources.hydration_target).toBe('notification_preferences')
    expect(state.updated_at).toBe('2026-07-20T14:05:00.000Z')
  })

  it('exposes exact routine occurrences independently with stable metadata and ordering', () => {
    const routineItems: DailyStateInput['routineItems'] = [
      {
        id: 'medication-1',
        itemType: 'medication',
        name: 'Item cadastrado',
        doseText: null,
        origin: null,
        remindersEnabled: false,
        schedules: [
          { id: 'rule-snoozed', localTime: '09:00', weekdays: [1] },
          { id: 'rule-missed', localTime: '07:00', weekdays: [1] },
        ],
        occurrences: [
          {
            reminderRuleId: 'rule-snoozed',
            scheduledFor: '2026-07-20T13:00:00.000Z',
            status: 'snoozed',
            lastActionAt: '2026-07-20T13:02:00.000Z',
            snoozedUntil: '2026-07-20T13:32:00.000Z',
          },
          {
            reminderRuleId: 'rule-missed',
            scheduledFor: '2026-07-20T11:00:00.000Z',
            status: 'missed',
            lastActionAt: null,
            snoozedUntil: null,
          },
        ],
        updatedAt: '2026-07-21T04:05:00.000Z',
      },
      {
        id: 'supplement-1',
        itemType: 'supplement',
        name: 'Creatina',
        doseText: '3 g',
        origin: 'professional',
        remindersEnabled: true,
        schedules: [
          { id: 'rule-08-z', localTime: '08:00', weekdays: [1, 3, 5] },
          { id: 'rule-20', localTime: '20:00', weekdays: [1, 3, 5] },
          { id: 'rule-08-a', localTime: '08:00', weekdays: [1, 3, 5] },
        ],
        occurrences: [
          {
            reminderRuleId: 'rule-08-z',
            scheduledFor: '2026-07-20T08:00:00.000-04:00',
            status: 'taken',
            lastActionAt: '2026-07-20T12:05:00.000Z',
            snoozedUntil: null,
          },
          {
            reminderRuleId: 'rule-20',
            scheduledFor: '2026-07-21T00:00:00.000Z',
            status: 'pending',
            lastActionAt: null,
            snoozedUntil: null,
          },
          {
            reminderRuleId: 'rule-08-a',
            scheduledFor: '2026-07-20T12:00:00.000Z',
            status: 'pending',
            lastActionAt: null,
            snoozedUntil: null,
          },
        ],
        updatedAt: '2026-07-20T12:05:00.000Z',
      },
      {
        id: 'supplement-0',
        itemType: 'supplement',
        name: 'Sem horários',
        doseText: null,
        origin: 'user',
        remindersEnabled: false,
        schedules: [],
        occurrences: [],
        updatedAt: '2026-07-20T10:00:00.000Z',
      },
    ]

    const state = buildDailyState(input({ routineItems }))

    expect(state.supplements).toEqual({
      availability: 'available',
      items: [
        {
          id: 'supplement-0',
          name: 'Sem horários',
          dose_text: null,
          origin: 'user',
          reminders_enabled: false,
          schedules: [],
          occurrences: [],
        },
        {
          id: 'supplement-1',
          name: 'Creatina',
          dose_text: '3 g',
          origin: 'professional',
          reminders_enabled: true,
          schedules: [
            { id: 'rule-08-a', local_time: '08:00', weekdays: [1, 3, 5] },
            { id: 'rule-08-z', local_time: '08:00', weekdays: [1, 3, 5] },
            { id: 'rule-20', local_time: '20:00', weekdays: [1, 3, 5] },
          ],
          occurrences: [
            {
              reminder_rule_id: 'rule-08-a',
              scheduled_for: '2026-07-20T12:00:00.000Z',
              status: 'pending',
              last_action_at: null,
              snoozed_until: null,
            },
            {
              reminder_rule_id: 'rule-08-z',
              scheduled_for: '2026-07-20T08:00:00.000-04:00',
              status: 'taken',
              last_action_at: '2026-07-20T12:05:00.000Z',
              snoozed_until: null,
            },
            {
              reminder_rule_id: 'rule-20',
              scheduled_for: '2026-07-21T00:00:00.000Z',
              status: 'pending',
              last_action_at: null,
              snoozed_until: null,
            },
          ],
        },
      ],
    })
    expect(state.medications).toEqual({
      availability: 'available',
      items: [
        {
          id: 'medication-1',
          name: 'Item cadastrado',
          dose_text: null,
          origin: null,
          reminders_enabled: false,
          schedules: [
            { id: 'rule-missed', local_time: '07:00', weekdays: [1] },
            { id: 'rule-snoozed', local_time: '09:00', weekdays: [1] },
          ],
          occurrences: [
            {
              reminder_rule_id: 'rule-missed',
              scheduled_for: '2026-07-20T11:00:00.000Z',
              status: 'missed',
              last_action_at: null,
              snoozed_until: null,
            },
            {
              reminder_rule_id: 'rule-snoozed',
              scheduled_for: '2026-07-20T13:00:00.000Z',
              status: 'snoozed',
              last_action_at: '2026-07-20T13:02:00.000Z',
              snoozed_until: '2026-07-20T13:32:00.000Z',
            },
          ],
        },
      ],
    })
    // v3 since 2026-10-04: `daily_balance_kcal` is per protocol (§2c).
    expect(state.calculation_version).toBe('bodyflow.daily-state.v3')
    expect(JSON.stringify(state)).not.toContain('occurrence_key')
    expect(routineItems.map((item) => item.id)).toEqual([
      'medication-1',
      'supplement-1',
      'supplement-0',
    ])
    expect(routineItems[0]?.schedules.map((schedule) => schedule.id)).toEqual([
      'rule-snoozed',
      'rule-missed',
    ])
    expect(routineItems[0]?.occurrences.map((occurrence) => occurrence.reminderRuleId)).toEqual([
      'rule-snoozed',
      'rule-missed',
    ])
    expect(routineItems[1]?.schedules.map((schedule) => schedule.id)).toEqual([
      'rule-08-z',
      'rule-20',
      'rule-08-a',
    ])
    expect(routineItems[1]?.occurrences.map((occurrence) => occurrence.reminderRuleId)).toEqual([
      'rule-08-z',
      'rule-20',
      'rule-08-a',
    ])
  })

  it('marks a reliable open gap as pending information without treating it as failure', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_200,
          caloriesTarget: 1_900,
          proteinG: 90,
          proteinTarget: 140,
          carbsG: 120,
          fatG: 45,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: 'pending_close',
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
        mealGap: {
          expected: ['cafe', 'almoco', 'jantar'],
          registered: ['cafe', 'almoco'],
          skipped: [],
          open: ['jantar'],
          reliable: true,
          activeDays: 12,
        },
      }),
    )

    expect(state.completion_status).toEqual({
      status: 'pending_information',
      day_closed: false,
      has_sufficient_data: null,
    })
    expect(state.daily_balance_status).toBe('provisional')
    expect(state.pending_actions.meal_gaps).toEqual({
      expected: ['cafe', 'almoco', 'jantar'],
      registered: ['cafe', 'almoco'],
      skipped: [],
      open: ['jantar'],
      reliable: true,
      source: 'personalized_pattern',
      active_days: 12,
    })
  })

  it('keeps a normal in-progress gap open until the close reminder is active', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 600,
          caloriesTarget: 1_900,
          proteinG: 40,
          proteinTarget: 140,
          carbsG: 60,
          fatG: 20,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: 'complete',
          updatedAt: '2026-07-20T12:00:00.000Z',
        },
        mealGap: {
          expected: ['cafe', 'almoco', 'jantar'],
          registered: ['cafe'],
          skipped: [],
          open: ['almoco', 'jantar'],
          reliable: true,
          activeDays: 12,
        },
      }),
    )

    expect(state.completion_status.status).toBe('open')
    expect(state.pending_actions.meal_gaps.open).toEqual(['almoco', 'jantar'])
  })

  it('clears pending information when the reminded gap is resolved by registration', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_600,
          caloriesTarget: 1_900,
          proteinG: 120,
          proteinTarget: 140,
          carbsG: 150,
          fatG: 50,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: 'pending_close',
          updatedAt: '2026-07-20T22:30:00.000Z',
        },
        mealGap: {
          expected: ['cafe', 'almoco', 'jantar'],
          registered: ['cafe', 'almoco', 'jantar'],
          skipped: [],
          open: [],
          reliable: true,
          activeDays: 12,
        },
      }),
    )

    expect(state.completion_status.status).toBe('open')
    expect(state.pending_actions.meal_gaps.open).toEqual([])
  })

  it('clears pending information when the reminded gap is explicitly skipped', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_300,
          caloriesTarget: 1_900,
          proteinG: 100,
          proteinTarget: 140,
          carbsG: 120,
          fatG: 45,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: 'pending_close',
          updatedAt: '2026-07-20T22:30:00.000Z',
        },
        mealGap: {
          expected: ['cafe', 'almoco', 'jantar'],
          registered: ['cafe', 'almoco'],
          skipped: ['jantar'],
          open: [],
          reliable: true,
          activeDays: 12,
        },
      }),
    )

    expect(state.completion_status.status).toBe('open')
    expect(state.pending_actions.meal_gaps.skipped).toEqual(['jantar'])
  })

  it('represents an explicitly skipped meal as a valid completed day', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_450,
          caloriesTarget: 1_900,
          proteinG: 130,
          proteinTarget: 140,
          carbsG: 140,
          fatG: 50,
          exerciseCalories: 200,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: true,
          dayStatus: 'user_skipped',
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
        mealGap: {
          expected: ['cafe', 'almoco', 'jantar'],
          registered: ['cafe', 'almoco'],
          skipped: ['jantar'],
          open: [],
          reliable: true,
          activeDays: 12,
        },
      }),
    )

    expect(state.completion_status).toEqual({
      status: 'complete_with_explicit_skip',
      day_closed: true,
      has_sufficient_data: true,
    })
    expect(state.daily_balance_status).toBe('final')
  })

  it('marks a closed incomplete day as insufficient data and non-creditable', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 800,
          caloriesTarget: 1_900,
          proteinG: 60,
          proteinTarget: 140,
          carbsG: 80,
          fatG: 25,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: true,
          dayStatus: 'incomplete_no_response',
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
      }),
    )

    expect(state.completion_status).toEqual({
      status: 'insufficient_data',
      day_closed: true,
      has_sufficient_data: false,
    })
    expect(state.daily_balance_status).toBe('insufficient_data')
  })

  it('marks incomplete_no_response as insufficient before the atomic close finishes', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 800,
          caloriesTarget: 1_900,
          proteinG: 60,
          proteinTarget: 140,
          carbsG: 80,
          fatG: 25,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: 'incomplete_no_response',
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
      }),
    )

    expect(state.completion_status).toEqual({
      status: 'insufficient_data',
      day_closed: false,
      has_sufficient_data: false,
    })
    expect(state.daily_balance_status).toBe('insufficient_data')
  })

  it('does not label a closed day without observed activity as complete', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 0,
          caloriesTarget: 1_900,
          proteinG: 0,
          proteinTarget: 140,
          carbsG: 0,
          fatG: 0,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: true,
          dayStatus: 'complete',
          updatedAt: '2026-07-20T23:59:00.000Z',
        },
      }),
    )

    expect(state.completion_status.status).toBe('insufficient_data')
    expect(state.daily_balance_status).toBe('insufficient_data')
  })

  it('exposes workouts and applies exercise only to the net balance', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_600,
          caloriesTarget: 1_900,
          proteinG: 120,
          proteinTarget: 140,
          carbsG: 150,
          fatG: 50,
          exerciseCalories: 450,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
        workouts: [
          {
            id: 'workout-1',
            workout_type: 'musculacao',
            duration_min: 40,
            estimated_kcal: 450,
            intensity: 'moderada',
            performed_at: '2026-07-20T13:00:00.000Z',
          },
        ],
      }),
    )

    expect(state.remaining_food_kcal).toBe(300)
    expect(state.daily_balance_kcal).toBe(-750)
    expect(state.workouts).toHaveLength(1)
  })

  it('reflects a meal edit from the recalculated snapshot instead of summing stale values', () => {
    const before = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 500,
          caloriesTarget: 1_900,
          proteinG: 30,
          proteinTarget: 140,
          carbsG: 40,
          fatG: 20,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-07-20T14:00:00.000Z',
        },
      }),
    )
    const after = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 350,
          caloriesTarget: 1_900,
          proteinG: 25,
          proteinTarget: 140,
          carbsG: 25,
          fatG: 15,
          exerciseCalories: 0,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-07-20T14:05:00.000Z',
        },
      }),
    )

    expect(before.consumed.calories_kcal).toBe(500)
    expect(after.consumed.calories_kcal).toBe(350)
    expect(after.remaining_food_kcal).toBe(1_550)
  })

  it('exposes persisted block progress without projecting an unclosed day credit', () => {
    const state = buildDailyState(
      input({
        snapshot: {
          caloriesConsumed: 1_600,
          caloriesTarget: 1_900,
          proteinG: 120,
          proteinTarget: 140,
          carbsG: 150,
          fatG: 50,
          exerciseCalories: 450,
          waterConsumedMl: 0,
          protocol: 'recomposicao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-07-20T14:30:00.000Z',
        },
        progress: {
          deficitBlock: 3_850,
          blocksCompleted: 2,
          updatedAt: '2026-07-20T14:31:00.000Z',
        },
      }),
    )

    expect(state.block_7700).toEqual({
      enabled: true,
      availability: 'available',
      target_kcal: 7_700,
      current_kcal: 3_850,
      percentage: 50,
      completed_blocks: 2,
      total_credited_kcal: 19_250,
      source: 'user_progress',
    })
    expect(state.updated_at).toBe('2026-07-20T14:31:00.000Z')
  })
})

// docs/CALCULO-MPP.md §2c — dito pelo cliente em 20/01/2026, 22/02/2026,
// 23/02/2026 e 09/03/2026; implementado em 2026-10-04 a pedido do Eduardo;
// confirmação do cliente pendente.
describe('buildDailyState — daily_balance_kcal per protocol (v3)', () => {
  type Switches = Record<keyof typeof DAY_BALANCE_AGAINST_EXPENDITURE, boolean>
  const switches = DAY_BALANCE_AGAINST_EXPENDITURE as Switches
  const original: Switches = { ...DAY_BALANCE_AGAINST_EXPENDITURE }
  afterEach(() => {
    Object.assign(switches, original)
  })

  const day = (
    protocol: DailyStateSnapshotInput['protocol'],
    caloriesConsumed: number,
    caloriesTarget: number | null,
    exerciseCalories: number,
  ): DailyStateSnapshotInput => ({
    caloriesConsumed,
    caloriesTarget,
    proteinG: 0,
    proteinTarget: 140,
    carbsG: 0,
    fatG: 0,
    exerciseCalories,
    waterConsumedMl: 0,
    protocol,
    dayClosed: false,
    dayStatus: null,
    updatedAt: '2026-07-20T14:30:00.000Z',
  })
  const energy = (state: ReturnType<typeof buildDailyState>) => ({
    remaining_food_kcal: state.remaining_food_kcal,
    food_excess_kcal: state.food_excess_kcal,
    exercise_kcal: state.exercise_kcal,
    daily_balance_kcal: state.daily_balance_kcal,
    daily_balance_reference_kcal: state.daily_balance_reference_kcal,
    daily_balance_includes_exercise: state.daily_balance_includes_exercise,
  })

  it('the version is v3', () => {
    expect(DAILY_STATE_CALCULATION_VERSION).toBe('bodyflow.daily-state.v3')
  })

  it('recomposição 19/05 (2076 / 1843, treino 565, déficit 500): −332 → −832, against 2343', () => {
    const state = buildDailyState(
      input({ snapshot: day(null, 2_076, 1_843, 565), programmedDeficitKcal: 500 }),
    )

    expect(energy(state)).toEqual({
      remaining_food_kcal: 0,
      food_excess_kcal: 233,
      exercise_kcal: 565,
      daily_balance_kcal: -832,
      daily_balance_reference_kcal: 2_343,
      daily_balance_includes_exercise: true,
    })
    expect(state.block_7700.enabled).toBe(true)
  })

  it('recomposição, morning with no record (target 1900, déficit 500): −1900 → −2400', () => {
    const state = buildDailyState(input({ programmedDeficitKcal: 500 }))

    expect(energy(state)).toEqual({
      remaining_food_kcal: 1_900,
      food_excess_kcal: 0,
      exercise_kcal: 0,
      daily_balance_kcal: -2_400,
      daily_balance_reference_kcal: 2_400,
      daily_balance_includes_exercise: true,
    })
    expect(state.daily_balance_status).toBe('provisional')
  })

  it('recomposição without the programmed deficit input: the number of before (netBalance)', () => {
    const state = buildDailyState(input({ snapshot: day(null, 2_076, 1_843, 565) }))

    expect(state.daily_balance_kcal).toBe(-332)
    expect(state.daily_balance_reference_kcal).toBe(1_843)
    expect(state.daily_balance_includes_exercise).toBe(true)
  })

  it('ganho de massa, QA account (541 / 2980, treino 322): −2761 → −2297 against 2838; 2439 left as before', () => {
    const state = buildDailyState(
      input({
        protocol: 'ganho_massa',
        snapshot: day(null, 541, 2_980, 322),
        gainSurplusMultiplier: 1.05,
        // The service sends 0 outside recomposição; even a stray 500 is ignored.
        programmedDeficitKcal: 500,
      }),
    )

    expect(energy(state)).toEqual({
      remaining_food_kcal: 2_439,
      food_excess_kcal: 0,
      exercise_kcal: 322,
      daily_balance_kcal: -2_297,
      daily_balance_reference_kcal: 2_838,
      daily_balance_includes_exercise: false,
    })
    expect(state.protocol).toBe('ganho_massa')
    expect(state.block_7700.enabled).toBe(false)
  })

  it.each([
    322, 0,
  ])('ganho de massa eating exactly 2980 with a %s kcal workout: +142', (exercise) => {
    const state = buildDailyState(
      input({ protocol: 'ganho_massa', snapshot: day(null, 2_980, 2_980, exercise) }),
    )

    expect(energy(state)).toEqual({
      remaining_food_kcal: 0,
      food_excess_kcal: 0,
      exercise_kcal: exercise,
      daily_balance_kcal: 142,
      daily_balance_reference_kcal: 2_838,
      daily_balance_includes_exercise: false,
    })
  })

  it('ganho de massa without the multiplier input: the default 1,05 of the calc config', () => {
    const state = buildDailyState(
      input({ protocol: 'ganho_massa', snapshot: day(null, 541, 2_980, 322) }),
    )

    expect(state.daily_balance_reference_kcal).toBe(2_838)
    expect(state.daily_balance_kcal).toBe(-2_297)
  })

  it('manutenção (3044 / 3044, treino 400): −400 → 0', () => {
    const state = buildDailyState(
      input({ protocol: 'manutencao', snapshot: day(null, 3_044, 3_044, 400) }),
    )

    expect(energy(state)).toEqual({
      remaining_food_kcal: 0,
      food_excess_kcal: 0,
      exercise_kcal: 400,
      daily_balance_kcal: 0,
      daily_balance_reference_kcal: 3_044,
      daily_balance_includes_exercise: false,
    })
    expect(Object.is(state.daily_balance_kcal, -0)).toBe(false)
  })

  it('protocol not set: unchanged (netBalance against the target, exercise included)', () => {
    const state = buildDailyState(
      input({
        protocol: null,
        snapshot: day(null, 541, 2_980, 322),
        gainSurplusMultiplier: 1.05,
        programmedDeficitKcal: 500,
      }),
    )

    expect(energy(state)).toEqual({
      remaining_food_kcal: 2_439,
      food_excess_kcal: 0,
      exercise_kcal: 322,
      daily_balance_kcal: -2_761,
      daily_balance_reference_kcal: 2_980,
      daily_balance_includes_exercise: true,
    })
  })

  it('the protocol of the day row wins over the profile, as in the published `protocol`', () => {
    const state = buildDailyState(
      input({
        protocol: 'recomposicao',
        snapshot: day('manutencao', 3_044, 3_044, 400),
        programmedDeficitKcal: 500,
      }),
    )

    expect(state.protocol).toBe('manutencao')
    expect(state.daily_balance_kcal).toBe(0)
    expect(state.daily_balance_includes_exercise).toBe(false)
  })

  it('day of a protocol change (stored target of another rule): the legacy number, against the stored target, with exercise', () => {
    // Review of 2026-10-04: morning in ganho de massa stores 2799, the profile
    // becomes recomposição/500 at noon, consumed 2500. Before: −799 against
    // 3299 (a deficit) when the client's rule gives +436 (a surplus).
    const changed = input({
      protocol: 'recomposicao',
      snapshot: day(null, 2_500, 2_799, 0),
      programmedDeficitKcal: 500,
    })

    expect(buildDailyState(changed).daily_balance_kcal).toBe(-799)
    expect(buildDailyState({ ...changed, dayTargetMatchesProtocol: true }).daily_balance_kcal).toBe(
      -799,
    )
    const state = buildDailyState({ ...changed, dayTargetMatchesProtocol: false })
    expect(energy(state)).toEqual({
      remaining_food_kcal: 299,
      food_excess_kcal: 0,
      exercise_kcal: 0,
      daily_balance_kcal: -299,
      daily_balance_reference_kcal: 2_799,
      daily_balance_includes_exercise: true,
    })
    // Only the balance falls back: the protocol published is still the profile's.
    expect(state.protocol).toBe('recomposicao')
    expect(state.block_7700.enabled).toBe(true)
  })

  it('the reference is published as an integer on the legacy path too (the app decodes Int)', () => {
    // Review of 2026-10-04: protocol null and a target of 2980,4 published
    // daily_balance_reference_kcal 2980,4. The three protocols already
    // rounded; the legacy balance itself is left as it was.
    const legacy = buildDailyState(
      input({ protocol: null, snapshot: day(null, 541, 2_980.4, 322) }),
    )

    expect(legacy.daily_balance_reference_kcal).toBe(2_980)
    expect(legacy.daily_balance_includes_exercise).toBe(true)
    expect(legacy.daily_balance_kcal).toBeCloseTo(-2_761.4, 6)

    const up = buildDailyState(input({ protocol: null, snapshot: day(null, 541, 2_980.5, 322) }))
    expect(up.daily_balance_reference_kcal).toBe(2_981)

    // Same on the fallback of a protocol-change day and with the switch off.
    const fallback = buildDailyState(
      input({
        protocol: 'ganho_massa',
        snapshot: day(null, 541, 2_980.4, 322),
        dayTargetMatchesProtocol: false,
      }),
    )
    expect(fallback.daily_balance_reference_kcal).toBe(2_980)
    Object.assign(switches, { recomposicao: false, ganho_massa: false, manutencao: false })
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao'] as const) {
      const off = buildDailyState(input({ protocol, snapshot: day(null, 541, 2_980.4, 322) }))
      expect(Number.isInteger(off.daily_balance_reference_kcal)).toBe(true)
      expect(off.daily_balance_reference_kcal).toBe(2_980)
    }
  })

  it('no target at all: the balance and its two companions are null, never 0', () => {
    const state = buildDailyState(
      input({
        protocol: 'ganho_massa',
        calculatedTargets: { calories_target: null, protein_target: null },
        snapshot: day(null, 541, null, 322),
      }),
    )

    expect(state.remaining_food_kcal).toBeNull()
    expect(state.daily_balance_kcal).toBeNull()
    expect(state.daily_balance_reference_kcal).toBeNull()
    expect(state.daily_balance_includes_exercise).toBeNull()
  })

  it('switch off: the three protocols publish the numbers of v2', () => {
    Object.assign(switches, { recomposicao: false, ganho_massa: false, manutencao: false })

    const recomp = buildDailyState(
      input({ snapshot: day(null, 2_076, 1_843, 565), programmedDeficitKcal: 500 }),
    )
    const ganho = buildDailyState(
      input({ protocol: 'ganho_massa', snapshot: day(null, 541, 2_980, 322) }),
    )
    const manutencao = buildDailyState(
      input({ protocol: 'manutencao', snapshot: day(null, 3_044, 3_044, 400) }),
    )

    expect(recomp.daily_balance_kcal).toBe(-332)
    expect(ganho.daily_balance_kcal).toBe(-2_761)
    expect(manutencao.daily_balance_kcal).toBe(-400)
    for (const state of [recomp, ganho, manutencao]) {
      expect(state.daily_balance_includes_exercise).toBe(true)
      expect(state.daily_balance_reference_kcal).toBe(state.targets.calories_kcal)
    }
  })

  it('nothing else of the energy block moves: food line, exercise, status and block are the same on and off', () => {
    const build = () =>
      buildDailyState(
        input({
          protocol: 'ganho_massa',
          snapshot: day(null, 3_200, 2_980, 322),
          progress: { deficitBlock: 3_850, blocksCompleted: 2, updatedAt: null },
        }),
      )
    const on = build()
    Object.assign(switches, { recomposicao: false, ganho_massa: false, manutencao: false })
    const off = build()

    expect(on.daily_balance_kcal).toBe(362)
    expect(off.daily_balance_kcal).toBe(-102)
    const {
      daily_balance_kcal: _a,
      daily_balance_reference_kcal: _b,
      daily_balance_includes_exercise: _c,
      ...restOn
    } = on
    const {
      daily_balance_kcal: _d,
      daily_balance_reference_kcal: _e,
      daily_balance_includes_exercise: _f,
      ...restOff
    } = off
    expect(restOn).toEqual(restOff)
    expect(on.food_excess_kcal).toBe(220)
    expect(on.block_7700.current_kcal).toBe(3_850)
  })
})
