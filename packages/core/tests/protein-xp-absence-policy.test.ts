/** Eduardo26Oct: keep the existing protein XP rule even when clinical policy
 * hides/suspends targets. This characterizes reuse; no new target or XP formula. */
import { describe, expect, it } from 'vitest'
import { DEFAULT_CALC_CONFIG } from '../src/calc-config.js'
import { calcDailyXP } from '../src/progress-calc.js'

describe('existing protein XP when no target is offered', () => {
  const legacy = {
    ...DEFAULT_CALC_CONFIG,
    xp_rules: { base: 10, training_bonus: 5, protein_bonus: 5, protein_threshold_g: 100 },
  }
  const mpp = {
    ...legacy,
    xp_rules: { ...legacy.xp_rules, meal_xp: 2, protein_meta_xp: 7 },
  }
  it.each([
    { mode: 'legacy', config: legacy, protein: 99, target: undefined, want: 10 },
    { mode: 'legacy', config: legacy, protein: 100, target: undefined, want: 15 },
    { mode: 'MPP', config: mpp, protein: 99, target: undefined, want: 6 },
    { mode: 'MPP', config: mpp, protein: 100, target: undefined, want: 13 },
    { mode: 'MPP', config: mpp, protein: 100, target: 150, want: 6 },
    { mode: 'MPP', config: mpp, protein: 150, target: 150, want: 13 },
  ])('$mode keeps $want XP for $protein g with target $target', ({
    config,
    protein,
    target,
    want,
  }) => {
    expect(
      calcDailyXP(
        { trainingDone: false, proteinG: protein, proteinTarget: target, mealsLogged: 3 },
        config,
      ),
    ).toBe(want)
  })
})
