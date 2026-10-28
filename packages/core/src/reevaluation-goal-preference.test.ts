import { describe, expect, it } from 'vitest'
import { evaluateReevaluationGoalPreference } from './reevaluation-goal-preference.js'

const context = { sex: 'masculino', heightCm: 180 }
const change = (value: unknown) => ({ action: 'change', value })
describe('n21 personal preference is not a prescription', () => {
  it.each([
    null,
    { action: 'keep' },
    { action: 'skip' },
  ])('preserves the current preference for %j', (preference) => {
    expect(evaluateReevaluationGoalPreference({ preference, ...context })).toMatchObject({
      status: 'unchanged',
    })
  })
  it('removes only the separate preference', () => {
    expect(
      evaluateReevaluationGoalPreference({ preference: { action: 'remove' }, ...context }),
    ).toEqual({
      status: 'removed',
      reason: null,
      missing: [],
      normalizedPreference: { action: 'remove' },
    })
  })
  it.each([
    'regular_training',
    'more_energy',
    'organized_food',
    'maintain_weight',
  ])('accepts the closed routine preference %s', (value) => {
    const preference = change({ kind: 'routine', value })
    expect(evaluateReevaluationGoalPreference({ preference, ...context })).toMatchObject({
      status: 'accepted',
      normalizedPreference: preference,
    })
  })
  it.each([
    { kind: 'follow_app' },
    { kind: 'professional' },
    { kind: 'weight', kg: 75 },
    { kind: 'body_fat', percent: 12 },
  ])('accepts %j without setting a clinical goal', (value) => {
    const result = evaluateReevaluationGoalPreference({ preference: change(value), ...context })
    expect(result.status).toBe('accepted')
    expect(result).not.toHaveProperty('goal_type')
    expect(result).not.toHaveProperty('targetKcal')
  })
  it.each([
    3, 9.99,
  ])('refuses %s%% for every sex and strips the value before persistence', (percent) => {
    for (const sex of ['masculino', 'feminino', null])
      expect(
        evaluateReevaluationGoalPreference({
          preference: change({ kind: 'body_fat', percent }),
          heightCm: null,
          sex,
        }),
      ).toEqual({
        status: 'refused',
        reason: 'body_fat_floor',
        missing: [],
        normalizedPreference: null,
      })
  })
  it.each([10, 11.999])('does not save a woman’s %s%% preference', (percent) => {
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'body_fat', percent }),
        sex: 'feminino',
        heightCm: 180,
      }),
    ).toMatchObject({ status: 'refused', normalizedPreference: null })
  })
  it('does not infer sex when the 10–12% refusal depends on it', () => {
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'body_fat', percent: 11 }),
        sex: null,
        heightCm: 180,
      }),
    ).toEqual({
      status: 'missing',
      reason: 'dependent_context',
      missing: ['sex'],
      normalizedPreference: null,
    })
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'body_fat', percent: 12 }),
        sex: null,
        heightCm: null,
      }).status,
    ).toBe('accepted')
  })
  it.each([30, 73.99])('refuses any weight %s kg whose target BMI is below 18.5', (kg) => {
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'weight', kg }),
        sex: 'masculino',
        heightCm: 200,
      }),
    ).toMatchObject({ status: 'refused', reason: 'weight_bmi_floor', normalizedPreference: null })
  })
  it('uses the requested weight and unrounded BMI, never current weight or a gain exception', () => {
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'weight', kg: 74 }),
        sex: null,
        heightCm: 200,
      }).status,
    ).toBe('accepted')
    expect(
      evaluateReevaluationGoalPreference({
        preference: change({ kind: 'weight', kg: 80 }),
        sex: null,
        heightCm: null,
      }),
    ).toMatchObject({ status: 'missing', missing: ['heightCm'], normalizedPreference: null })
  })
  it('compares decimal values exactly at BMI18.5 without an epsilon or a rounded BMI', () => {
    for (const [heightCm, kg] of [
      [180, 59.94],
      [183, 61.95465],
    ] as const) {
      expect(
        evaluateReevaluationGoalPreference({
          preference: change({ kind: 'weight', kg }),
          sex: null,
          heightCm,
        }).status,
      ).toBe('accepted')
      expect(
        evaluateReevaluationGoalPreference({
          preference: change({ kind: 'weight', kg: kg - 0.00001 }),
          sex: null,
          heightCm,
        }).status,
      ).toBe('refused')
    }
  })
  it.each([
    change({ kind: 'weight', kg: 29 }),
    change({ kind: 'weight', kg: '75' }),
    change({ kind: 'body_fat', percent: 61 }),
    change({ kind: 'routine', value: 'anything' }),
    { action: 'keep', goal_type: 'peso_kg' },
  ])('rejects malformed or authority-bearing preference %j', (preference) => {
    expect(() => evaluateReevaluationGoalPreference({ preference, ...context })).toThrow()
  })
})
