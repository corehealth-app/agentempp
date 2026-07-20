import { describe, expect, it } from 'vitest'
import {
  buildDailyState,
  DAILY_STATE_CALCULATION_VERSION,
  type DailyStateInput,
} from './daily-state.js'

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

  it('exposes configured routine items with today adherence and no invented dose data', () => {
    const state = buildDailyState(
      input({
        routineItems: [
          {
            id: 'supplement-1',
            itemType: 'supplement',
            name: 'Creatina',
            adherenceStatus: 'taken',
            occurredAt: '2026-07-20T12:00:00.000Z',
            snoozedUntil: null,
            updatedAt: '2026-07-20T12:00:00.000Z',
          },
          {
            id: 'medication-1',
            itemType: 'medication',
            name: 'Item cadastrado',
            adherenceStatus: 'not_recorded',
            occurredAt: null,
            snoozedUntil: null,
            updatedAt: '2026-07-20T11:00:00.000Z',
          },
        ],
      }),
    )

    expect(state.supplements).toEqual({
      availability: 'available',
      items: [
        {
          id: 'supplement-1',
          name: 'Creatina',
          status: 'taken',
          occurred_at: '2026-07-20T12:00:00.000Z',
          snoozed_until: null,
        },
      ],
    })
    expect(state.medications).toEqual({
      availability: 'available',
      items: [
        {
          id: 'medication-1',
          name: 'Item cadastrado',
          status: 'not_recorded',
          occurred_at: null,
          snoozed_until: null,
        },
      ],
    })
    expect(JSON.stringify(state)).not.toContain('dose')
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
