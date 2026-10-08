import { describe, expect, it } from 'vitest'
import { buildDailyState, type DailyStateInput } from './daily-state.js'
import type { Protocol } from './types.js'

function input(active: Protocol | null, historical: Protocol): DailyStateInput {
  return {
    localDate: '2026-10-04',
    generatedAt: '2026-10-05T11:02:00.000Z',
    protocol: active,
    calculatedTargets: { calories_target: 2_498, protein_target: 120 },
    programmedDeficitKcal: historical === 'recomposicao' ? 500 : 0,
    snapshot: {
      caloriesConsumed: 2_076,
      caloriesTarget: 1_843,
      proteinG: 59.03,
      proteinTarget: 144,
      carbsG: 110,
      fatG: 42,
      exerciseCalories: 565,
      waterConsumedMl: 1_500,
      protocol: historical,
      dayClosed: true,
      dayStatus: 'complete',
      updatedAt: '2026-10-05T11:01:00.000Z',
    },
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
    progress: { deficitBlock: 3_850, blocksCompleted: 2, updatedAt: null },
  }
}

describe('Flow block presentation uses the current official objective', () => {
  it.each([
    ['ganho_massa', 'recomposicao', false],
    ['manutencao', 'recomposicao', false],
    ['recomposicao', 'ganho_massa', true],
    ['recomposicao', 'manutencao', true],
    [null, 'recomposicao', false],
    ['recomposicao', 'recomposicao', true],
  ] as const)('active %s, historical %s: enabled %s without changing day energy', (active, historical, enabled) => {
    const source = input(active, historical)
    const original = structuredClone(source)
    const state = buildDailyState(source)

    expect(state.block_7700.enabled).toBe(enabled)
    expect(state).toMatchObject({ current_protocol: active, protocol: historical })
    expect(state.block_7700).toEqual({
      enabled,
      availability: 'available',
      target_kcal: 7_700,
      current_kcal: 3_850,
      percentage: 50,
      completed_blocks: 2,
      total_credited_kcal: 19_250,
      source: 'user_progress',
    })
    expect(state.targets).toMatchObject({ calories_kcal: 1_843, protein_g: 144 })
    expect(state.consumed).toMatchObject({ calories_kcal: 2_076, protein_g: 59.03 })
    expect(state.food_excess_kcal).toBe(233)
    expect(state.exercise_kcal).toBe(565)
    expect(state.daily_balance_kcal).toBe(
      historical === 'recomposicao' ? -832 : historical === 'ganho_massa' ? 321 : 233,
    )
    expect(state.daily_balance_reference_kcal).toBe(
      historical === 'recomposicao' ? 2_343 : historical === 'ganho_massa' ? 1_755 : 1_843,
    )
    expect(state.daily_balance_includes_exercise).toBe(historical === 'recomposicao')
    expect(state.daily_balance_status).toBe('final')
    expect(source).toEqual(original)
  })

  it('missing progress remains unavailable, and cannot become a fabricated zero', () => {
    const state = buildDailyState({ ...input('ganho_massa', 'recomposicao'), progress: null })
    expect(state).toMatchObject({ current_protocol: 'ganho_massa' })
    expect(state.block_7700).toMatchObject({
      enabled: false,
      availability: 'unavailable',
      current_kcal: null,
      completed_blocks: null,
      total_credited_kcal: null,
      percentage: null,
    })
  })
})
