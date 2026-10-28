import { describe, expect, it } from 'vitest'
import { ageOnClinicalDate, evaluateReevaluationSafety } from './reevaluation-clinical-safety.js'

const base = {
  date: '2026-10-25',
  birthDate: '1990-10-25',
  heightCm: 170,
  weightKg: 70,
  bodyFatPercent: 24,
  hold: { active: false, items: [] },
}
describe('n10 clinical safeguards, explicit authoritative date and no writes', () => {
  it('does not classify exact decimal BMI18.5 as low because of floating-point division', () => {
    expect(
      evaluateReevaluationSafety({ ...base, heightCm: 160, weightKg: 47.36 }).guards.lowWeight,
    ).toBe(false)
    expect(
      evaluateReevaluationSafety({ ...base, heightCm: 160, weightKg: 47.35 }).guards.lowWeight,
    ).toBe(true)
  })
  it.each([
    [53.4, 170, true],
    [53.5, 170, false],
    [47.36, 160, false],
    [74, 200, false],
    [73.99, 200, true],
  ])('raw BMI safety boundary %s/%s -> %s', (weightKg, heightCm, expected) => {
    const state = evaluateReevaluationSafety({ ...base, weightKg, heightCm })
    expect(state.guards.lowWeight).toBe(expected)
    expect(state.pauseWeightLossGuidance).toBe(expected)
    expect(state.automaticTargetChangeAllowed).toBe(!expected)
    expect(state.neutralExitAllowed).toBe(false)
    expect(state).not.toHaveProperty('caloriesTarget')
    expect(state).not.toHaveProperty('newPhase')
  })
  it.each([
    [10, true],
    [10.01, false],
    [20, false],
  ])('BF<=10 safety %s -> %s', (bodyFatPercent, expected) => {
    const state = evaluateReevaluationSafety({ ...base, bodyFatPercent })
    expect(state.guards.lowBodyFat).toBe(expected)
    expect(state.pauseWeightLossGuidance).toBe(expected)
  })
  it('a corrected value lifts data guard without modifying prior input/history', () => {
    const input = { ...base, bodyFatPercent: 10 }
    const before = structuredClone(input)
    expect(evaluateReevaluationSafety(input).automaticTargetChangeAllowed).toBe(false)
    expect(
      evaluateReevaluationSafety({ ...input, bodyFatPercent: 20 }).automaticTargetChangeAllowed,
    ).toBe(true)
    expect(input).toEqual(before)
  })
  it.each([
    ['2026-10-24', 17, true],
    ['2026-10-25', 18, false],
  ])('age18 boundary on %s', (date, age, noPlan) => {
    const state = evaluateReevaluationSafety({ ...base, birthDate: '2008-10-25', date })
    expect(state.age).toBe(age)
    expect(state.noPlan).toBe(noPlan)
    expect(state.hide).toEqual({
      objective: noPlan,
      calories: noPlan,
      protein: noPlan,
      balance: noPlan,
      block: noPlan,
      budget: noPlan,
    })
  })
  it('civil birthday has no dependency on host timezone, clock or parsing UTC as yesterday', () => {
    expect(ageOnClinicalDate('2008-01-01', '2026-01-01')).toBe(18)
    expect(ageOnClinicalDate('2008-02-29', '2026-02-28')).toBe(17)
    expect(ageOnClinicalDate('2008-02-29', '2026-03-01')).toBe(18)
  })
  it('pregnancy/breastfeeding withholds all numbers and keeps recording available', () => {
    const state = evaluateReevaluationSafety({
      ...base,
      hold: { active: true, items: ['pregnant_or_breastfeeding'] },
    })
    expect(state.noPlan).toBe(true)
    expect(Object.values(state.hide)).toEqual(Array(6).fill(true))
    expect(state.recordingAllowed).toBe(true)
    expect(state.neutralExitAllowed).toBe(false)
  })
  it('professional diet hides protein, keeps other existing numbers and suspends automation', () => {
    const state = evaluateReevaluationSafety({
      ...base,
      hold: { active: true, items: ['professional_diet'] },
    })
    expect(state.hide.protein).toBe(true)
    expect(state.hide.calories).toBe(false)
    expect(state.automaticTargetChangeAllowed).toBe(false)
    expect(state.neutralExitAllowed).toBe(true)
    expect(state.professionalAssessmentRecommended).toBe(true)
  })
  it('low BMI/BF veto neutral exit even when another HOLD is active', () => {
    for (const patch of [{ weightKg: 50 }, { bodyFatPercent: 10 }]) {
      const state = evaluateReevaluationSafety({
        ...base,
        ...patch,
        hold: { active: true, items: ['reduced_intake'] },
      })
      expect(state.neutralExitAllowed).toBe(false)
      expect(state.automaticTargetChangeAllowed).toBe(false)
      expect(state.pauseWeightLossGuidance).toBe(true)
    }
  })
  it('does not clear a HOLD based on a draft, None or a fabricated clear property', () => {
    expect(() => evaluateReevaluationSafety({ ...base, healthCheck: 'none' })).toThrow()
    expect(() =>
      evaluateReevaluationSafety({ ...base, hold: { active: true, items: [] } }),
    ).toThrow()
    expect(() =>
      evaluateReevaluationSafety({
        ...base,
        hold: { active: false, items: ['professional_diet'] },
      }),
    ).toThrow()
  })
  it.each([
    'birthDate',
    'weightKg',
    'heightCm',
  ])('missing %s does not authorize automatic changes', (key) => {
    const state = evaluateReevaluationSafety({ ...base, [key]: null })
    expect(state.assessment).toBe('incomplete')
    expect(state.missing).toContain(key)
    expect(state.automaticTargetChangeAllowed).toBe(false)
    expect(state.neutralExitAllowed).toBe(false)
  })
  it('absent BF remains absent, without inventing a report or low-fat diagnosis', () => {
    const state = evaluateReevaluationSafety({ ...base, bodyFatPercent: null })
    expect(state.guards.lowBodyFat).toBe(null)
    expect(state.automaticTargetChangeAllowed).toBe(true)
  })
  it.each([
    { date: '2026-02-30' },
    { date: '0000-01-01' },
    { date: '2026-10-25T00:00:00Z' },
    { birthDate: '2027-01-01' },
    { weightKg: NaN },
    { heightCm: 0 },
    { bodyFatPercent: Infinity },
    { hold: { active: true, items: ['unknown'] } },
    { hold: { active: true, items: ['reduced_intake', 'reduced_intake'] } },
  ])('invalid clinical context fails instead of producing permission %#', (patch) => {
    expect(() => evaluateReevaluationSafety({ ...base, ...patch })).toThrow()
  })
})
