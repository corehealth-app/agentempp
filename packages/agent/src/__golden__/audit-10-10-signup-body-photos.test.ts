/**
 * Exact photo scenario reported in audit10-04: only front26 had been read.
 * Sign-up must wait for all THREE SLOT poses; the model's view is irrelevant.
 * D1 Eduardo2026-10-11: arithmetic mean, equal weights. D2 confirmed enters
 * objective/targets through the existing rules. These pure tests prove D1;
 * confirmation, receipts, UI/model/Storage and D2 integration are separate.
 * No physician approval or accuracy assertion is inferred.
 */
import {
  computeDailyTargets,
  DEFAULT_CALC_CONFIG,
  decideSignupEligibility,
  type ProfileRow,
} from '@mpp/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  estimateSignupBodyFat,
  rawSignupBodyFatMean,
  type SignupBodyFatReading,
} from '../signup-body-fat-estimate.js'

const readings = (values: readonly (number | null)[]): SignupBodyFatReading[] =>
  (['front', 'side', 'back'] as const).map((pose, index) => ({
    pose,
    bodyFatPercent: values[index] ?? null,
  }))

function profile(
  bodyFatPercent: number | null,
  sex: 'masculino' | 'feminino' = 'masculino',
): ProfileRow {
  return {
    sex,
    birth_date: '1982-01-01',
    height_cm: 180,
    weight_kg: 81,
    body_fat_percent: bodyFatPercent,
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    current_protocol: 'recomposicao',
    goal_type: null,
    goal_value: null,
    deficit_level: 500,
  }
}

describe('existing rules with a supplied BF: effect coverage, not D2 confirmation integration', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-10-11T15:00:00.000Z'))
  })
  afterEach(() => vi.useRealTimers())

  it.each([
    [null, 1564],
    [22, 1582],
    [24, 1540],
    [30, 1414],
  ] as const)('P25 EXACT male81kg180cm44years BF%s gives%s kcal and121.5g by the real targets', (bf, calories) => {
    expect(computeDailyTargets(profile(bf), DEFAULT_CALC_CONFIG)).toEqual({
      calories_target: calories,
      protein_target: 121.5,
    })
  })
  it('mean24 uses the current sex-specific cuts; no new cut or BMI fallback is invented', () => {
    const joined = estimateSignupBodyFat(readings([18, 24, 30]))
    expect(joined).not.toBeNull()
    for (const sex of ['masculino', 'feminino'] as const) {
      const mean = joined?.by_sex[sex]
      expect(mean?.usable).toBe(true)
      if (!mean?.usable) throw new Error('expected usable synthetic mean')
      const result = decideSignupEligibility({
        sex,
        heightCm: 180,
        weightKg: 81,
        bodyFatPercent: mean.body_fat_percent,
        trainingFrequency: 4,
      })
      expect(result).toMatchObject({
        basis: 'BF',
        outcome: sex === 'masculino' ? 'assigned' : 'choice',
      })
      expect(computeDailyTargets(profile(mean.body_fat_percent, sex), DEFAULT_CALC_CONFIG)).toEqual(
        { calories_target: 1540, protein_target: 121.5 },
      )
    }
  })
  it('configured cuts are consumed by the existing function, never hardcoded in the mean', () => {
    const config = {
      ...DEFAULT_CALC_CONFIG,
      bf_limits: { masculino: { recomp: 25, gain: 24 }, feminino: { recomp: 23, gain: 22 } },
    }
    for (const sex of ['masculino', 'feminino'] as const) {
      expect(
        decideSignupEligibility(
          { sex, heightCm: 180, weightKg: 81, bodyFatPercent: 24, trainingFrequency: 4 },
          config,
        ),
      ).toMatchObject({ outcome: sex === 'masculino' ? 'choice' : 'assigned' })
    }
  })
})

describe('signup body photos D1 arithmetic mean, not legacy weighting', () => {
  it('P01 EXACT only front26: no estimate and no filling missing slots', () => {
    expect(estimateSignupBodyFat([{ pose: 'front', bodyFatPercent: 26 }])).toBeNull()
  })
  it('P02 exact18/24/30:24 for both sexes even across existing clinical cuts', () => {
    expect(estimateSignupBodyFat(readings([18, 24, 30]))).toEqual({
      is_estimate: true,
      readings: [
        { pose: 'front', body_fat_percent: 18 },
        { pose: 'side', body_fat_percent: 24 },
        { pose: 'back', body_fat_percent: 30 },
      ],
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
    })
  })
  it('P03 exact21/24/22:67/3 raw; unequal confidence cannot give legacy22.1 or lowest21', () => {
    const slots = [
      { pose: 'front' as const, bodyFatPercent: 21, confidence: 0.9, view: 'unknown' },
      { pose: 'side' as const, bodyFatPercent: 24, confidence: 0.6, view: 'unknown' },
      { pose: 'back' as const, bodyFatPercent: 22, confidence: 0.7, view: 'front' },
    ]
    expect(rawSignupBodyFatMean(slots)).toBe(67 / 3)
    expect(estimateSignupBodyFat(slots)?.by_sex).toEqual({
      masculino: { usable: true, body_fat_percent: 22.33 },
      feminino: { usable: true, body_fat_percent: 22.33 },
    })
  })
  it.each([
    ['unknown', 'unknown', 'unknown'],
    ['front', 'front', 'back'],
    ['unknown', 'unknown', 'front'],
    ['front', 'front', 'front'],
  ])('P04 model views%s/%s/%s never replace the slot identity or lose a reading', (front, side, back) => {
    const slots = readings([18, 24, 30]).map((entry, index) => ({
      ...entry,
      view: [front, side, back][index],
    }))
    expect(estimateSignupBodyFat(slots)?.by_sex.masculino).toEqual({
      usable: true,
      body_fat_percent: 24,
    })
  })
  it.each([
    null,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
  ])('P05 missing/nonfinite reading%s gives no estimate', (value) => {
    expect(estimateSignupBodyFat(readings([18, value, 30]))).toBeNull()
  })
  it.each([
    2.99, 60.01, -1, 100,
  ])('P06 reading%s outside existing3–60 prevents usage even if the mean would be in range', (value) => {
    expect(estimateSignupBodyFat(readings([18, value, 30]))?.by_sex).toEqual({
      masculino: { usable: false, reason: 'out_of_range' },
      feminino: { usable: false, reason: 'out_of_range' },
    })
  })
  it.each([3, 60])('P07 exact range endpoint%s is usable', (value) => {
    expect(estimateSignupBodyFat(readings([value, value, value]))?.by_sex.masculino).toEqual({
      usable: true,
      body_fat_percent: value,
    })
  })
  it('P10 three rows but repeated front and missing back gives no estimate', () => {
    expect(
      estimateSignupBodyFat([
        { pose: 'front', bodyFatPercent: 18 },
        { pose: 'front', bodyFatPercent: 24 },
        { pose: 'side', bodyFatPercent: 30 },
      ]),
    ).toBeNull()
  })
  it('slot order is canonical and the input is preserved', () => {
    const slots = readings([18, 24, 30]).reverse()
    const before = structuredClone(slots)
    expect(estimateSignupBodyFat(slots)?.readings.map((entry) => entry.pose)).toEqual([
      'front',
      'side',
      'back',
    ])
    expect(slots).toEqual(before)
  })
  it('additional valid row cannot silently form a four-photo estimate', () => {
    expect(
      estimateSignupBodyFat([...readings([18, 24, 30]), { pose: 'front', bodyFatPercent: 21 }]),
    ).toBeNull()
  })
  it('P14 a decimal half is retained before the profile normalizes it:19.995 remains19.995', () => {
    expect(rawSignupBodyFatMean(readings([19.995, 19.995, 19.995]))).toBe(19.995)
    expect(estimateSignupBodyFat(readings([19.995, 19.995, 19.995]))?.by_sex.masculino).toEqual({
      usable: true,
      body_fat_percent: 20,
    })
  })
  it('exact decimal just below19.995 must remain19.99, even when binary average rounds to the half', () => {
    expect(
      estimateSignupBodyFat(readings([19.994999999999997, 19.995, 19.995000000000001]))?.by_sex
        .masculino,
    ).toEqual({ usable: true, body_fat_percent: 19.99 })
  })
  it('caller result mutation cannot change input or the other sex result', () => {
    const slots = readings([18, 24, 30])
    const result = estimateSignupBodyFat(slots)
    expect(result).not.toBeNull()
    if (!result) throw new Error('missing estimate')
    const firstReading = result.readings[0]
    const firstInput = slots[0]
    if (!firstReading || !firstInput) throw new Error('missing front in the synthetic triad')
    firstReading.body_fat_percent = 50
    if (result.by_sex.masculino.usable) result.by_sex.masculino.body_fat_percent = 51
    expect(firstInput.bodyFatPercent).toBe(18)
    expect(result.by_sex.feminino).toEqual({ usable: true, body_fat_percent: 24 })
  })
})
