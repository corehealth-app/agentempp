/**
 * The sign-up eligibility check, without the HTTP layer: the rounding to what
 * the profile stores, and which text goes with each result. The rule itself is
 * pinned in packages/agent/src/__golden__/audit-10-07-signup-eligibility.test.ts
 * and every text, word for word, in audit-10-07-protocol-messages.test.ts.
 * No patient here: every number is a cut of the rule or a neighbour of one.
 */
import {
  type CalcConfig,
  DEFAULT_CALC_CONFIG,
  decideSignupEligibility,
  gainBlockedAboveRangeMessage,
  gainUnavailableBodyFatReason,
  gainUnavailableTrainingReason,
  signupAssignedNotice,
} from '@mpp/core'
import { describe, expect, it } from 'vitest'
import type { OnboardingEligibilityInput } from './contracts'
import { asStoredBodyValue, resolveOnboardingEligibility } from './protocol-eligibility-service'

/** Homem, 180 cm, 80 kg (IMC 24,69), sem gordura informada, musculação 3x. */
function man(patch: Partial<OnboardingEligibilityInput> = {}): OnboardingEligibilityInput {
  return {
    locale: 'pt-BR',
    sex: 'masculino',
    height_cm: 180,
    weight_kg: 80,
    training_frequency: 3,
    ...patch,
  }
}

/** Mulher, 165 cm, 62 kg (IMC 22,77), sem gordura informada, musculação 3x. */
function woman(patch: Partial<OnboardingEligibilityInput> = {}): OnboardingEligibilityInput {
  return {
    locale: 'pt-BR',
    sex: 'feminino',
    height_cm: 165,
    weight_kg: 62,
    training_frequency: 3,
    ...patch,
  }
}

function resolve(input: OnboardingEligibilityInput, config: CalcConfig = DEFAULT_CALC_CONFIG) {
  return resolveOnboardingEligibility(input, config)
}

const AVAILABLE = { status: 'available', reasons: [], message: [] }

describe('asStoredBodyValue: the value as numeric(5,2) / numeric(4,2) keeps it', () => {
  // What Postgres stores for each decimal text: rounded to two places, half
  // away from zero. Written by hand; no database is read here.
  it.each([
    [19.995, 20],
    [19.994, 19.99],
    [19.005, 19.01],
    [19.025, 19.03],
    [27.005, 27.01],
    [64.085, 64.09],
    [19.985, 19.99],
    [19.9849, 19.98],
    [27.995, 28],
    [27.994, 27.99],
    [80.999, 81],
    [80.994, 80.99],
    [80.995, 81],
    [64.005, 64.01],
    [64.004, 64],
    [160.004, 160],
    [160.005, 160.01],
    [3.004, 3],
    [59.995, 60],
    [299.995, 300],
    [100.0049999, 100],
    [19.994999999999997, 19.99],
  ])('%s is stored as %s', (sent, stored) => {
    expect(asStoredBodyValue(sent)).toBe(stored)
  })

  it.each([
    180, 62, 20, 19.5, 62.25, 79.38, 99.96, 24.9, 3, 300,
  ])('%s has at most two decimal places and is kept as it is', (value) => {
    expect(asStoredBodyValue(value)).toBe(value)
  })

  it('rounds on the decimal text, where binary floating point gets the half wrong', () => {
    // 19.025 × 100 is 1902.4999999999998 in binary floating point.
    expect(Math.round(19.025 * 100) / 100).toBe(19.02)
    expect(Number((19.025).toFixed(2))).toBe(19.02)
    expect(asStoredBodyValue(19.025)).toBe(19.03)
    // A woman's 27.005% is stored above her cut of 27.
    expect(Number((27.005).toFixed(2))).toBe(27)
    expect(asStoredBodyValue(27.005)).toBe(27.01)
  })

  it('never returns more than two decimal places, and a stored value is stored as itself', () => {
    for (let step = 0; step < 4000; step++) {
      const value = 3 + step * 0.0743 + step / 9973
      const stored = asStoredBodyValue(value)
      expect(String(stored)).toMatch(/^\d+(?:\.\d{1,2})?$/)
      expect(Math.abs(stored - value)).toBeLessThanOrEqual(0.005 + 1e-9)
      expect(asStoredBodyValue(stored)).toBe(stored)
    }
  })
})

describe('resolveOnboardingEligibility: the decision, with the text of each result', () => {
  it('man with 20.0% of body fat: placed in recomposição, the notice and the blocking phrase by body fat', () => {
    expect(resolve(man({ body_fat_percent: 20 }))).toEqual({
      decision: 'assigned',
      basis: 'body_fat',
      objective: 'recomposicao',
      notice: signupAssignedNotice('pt-BR'),
      options: [
        { objective: 'recomposicao', ...AVAILABLE },
        {
          objective: 'ganho_massa',
          status: 'blocked',
          reasons: ['gain_composition'],
          message: gainBlockedAboveRangeMessage('BF', 'pt-BR'),
        },
        { objective: 'manutencao', status: 'not_offered', reasons: [], message: [] },
      ],
    })
  })

  it('no body fat, 64 kg / 160 cm (BMI 25.0): placed in recomposição, the blocking phrase by BMI', () => {
    const result = resolve(woman({ height_cm: 160, weight_kg: 64 }))
    expect(result).toMatchObject({ decision: 'assigned', basis: 'bmi', objective: 'recomposicao' })
    expect(result.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition'],
      message: gainBlockedAboveRangeMessage('IMC', 'pt-BR'),
    })
    expect(result.options[1]?.message[0]).toContain('seu IMC atual coloca você')
  })

  it('placed in recomposição with 2 sessions: both reasons, and still only the blocking phrase', () => {
    const result = resolve(man({ body_fat_percent: 22, training_frequency: 2 }))
    expect(result.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition', 'gain_training'],
      message: gainBlockedAboveRangeMessage('BF', 'pt-BR'),
    })
    expect(result.options[1]?.message).toHaveLength(1)
    expect(result.options[1]?.message.join(' ')).not.toContain('por semana')
  })

  it('woman with 27.0% and 3 sessions: chooses among the three, no text anywhere', () => {
    expect(resolve(woman({ body_fat_percent: 27 }))).toEqual({
      decision: 'choice',
      basis: 'body_fat',
      objective: null,
      notice: null,
      options: [
        { objective: 'recomposicao', ...AVAILABLE },
        { objective: 'ganho_massa', ...AVAILABLE },
        { objective: 'manutencao', ...AVAILABLE },
      ],
    })
  })

  it('man with 19.5%: chooses; ganho de massa unavailable, with the cut of his sex (19) and never the blocking phrase', () => {
    const result = resolve(man({ body_fat_percent: 19.5 }))
    expect(result).toMatchObject({ decision: 'choice', basis: 'body_fat', notice: null })
    expect(result.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition'],
      message: gainUnavailableBodyFatReason(19, 'pt-BR'),
    })
    expect(result.options[1]?.message[0]).toContain('de até 19%')
    expect(result.options[1]?.message[0]).not.toContain('recomposição')
    expect(result.options[2]).toEqual({ objective: 'manutencao', ...AVAILABLE })
  })

  it('woman with 27.5%: the cut of her sex (27)', () => {
    expect(resolve(woman({ body_fat_percent: 27.5 })).options[1]?.message).toEqual(
      gainUnavailableBodyFatReason(27, 'pt-BR'),
    )
  })

  it('man with 19.0% and 2 sessions: ganho de massa unavailable by training, with the minimum and what he informed', () => {
    const result = resolve(man({ body_fat_percent: 19, training_frequency: 2 }))
    expect(result.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_training'],
      message: gainUnavailableTrainingReason(3, 2, 'pt-BR'),
    })
    expect(result.options[1]?.message[0]).toContain('pelo menos 3 vezes por semana')
    expect(result.options[1]?.message[0]).toContain('Você informou 2 por semana.')
  })

  it('man with 19.5% and 0 sessions: the two reasons, composition first', () => {
    expect(resolve(man({ body_fat_percent: 19.5, training_frequency: 0 })).options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition', 'gain_training'],
      message: [
        ...gainUnavailableBodyFatReason(19, 'pt-BR'),
        ...gainUnavailableTrainingReason(3, 0, 'pt-BR'),
      ],
    })
  })

  it('en-US: the same decision, every text in English', () => {
    const assigned = resolve(man({ locale: 'en-US', body_fat_percent: 20 }))
    expect(assigned.notice).toEqual(signupAssignedNotice('en-US'))
    expect(assigned.options[1]?.message).toEqual(gainBlockedAboveRangeMessage('BF', 'en-US'))
    const choice = resolve(man({ locale: 'en-US', body_fat_percent: 19.5, training_frequency: 2 }))
    expect(choice.options[1]?.message).toEqual([
      ...gainUnavailableBodyFatReason(19, 'en-US'),
      ...gainUnavailableTrainingReason(3, 2, 'en-US'),
    ])
    for (const text of [...(assigned.notice ?? []), ...(choice.options[1]?.message ?? [])]) {
      expect(text).not.toMatch(/você|musculação|gordura/)
    }
  })

  it('the cuts in the texts are the ones of the config that decided', () => {
    const config: CalcConfig = {
      ...DEFAULT_CALC_CONFIG,
      bf_limits: { ...DEFAULT_CALC_CONFIG.bf_limits, masculino: { recomp: 20, gain: 18 } },
      training_min: 4,
    }
    const result = resolve(man({ body_fat_percent: 18.5, training_frequency: 3 }), config)
    expect(result.options[1]?.reasons).toEqual(['gain_composition', 'gain_training'])
    expect(result.options[1]?.message[0]).toContain('de até 18%')
    expect(result.options[1]?.message[1]).toContain('pelo menos 4 vezes por semana')
    expect(result.options[1]?.message[1]).toContain('Você informou 3 por semana.')
    // The same person under the code default: within both criteria.
    expect(resolve(man({ body_fat_percent: 18.5 })).options[1]).toEqual({
      objective: 'ganho_massa',
      ...AVAILABLE,
    })
  })
})

describe('resolveOnboardingEligibility: decided on the value the profile will store', () => {
  /** The pure function on the values as they were sent, with no rounding. */
  function unrounded(input: OnboardingEligibilityInput) {
    return decideSignupEligibility({
      sex: input.sex,
      heightCm: input.height_cm,
      weightKg: input.weight_kg,
      bodyFatPercent: input.body_fat_percent ?? null,
      trainingFrequency: input.training_frequency,
    }).outcome
  }

  it('man with 19.995%: stored as 20.00 → placed in recomposição (unrounded, he would choose)', () => {
    expect(unrounded(man({ body_fat_percent: 19.995 }))).toBe('choice')
    expect(resolve(man({ body_fat_percent: 19.995 }))).toEqual(
      resolve(man({ body_fat_percent: 20 })),
    )
    expect(resolve(man({ body_fat_percent: 19.995 })).decision).toBe('assigned')
  })

  it('man with 19.994%: stored as 19.99 → chooses, ganho de massa unavailable by composition', () => {
    const result = resolve(man({ body_fat_percent: 19.994 }))
    expect(result.decision).toBe('choice')
    expect(result.options[1]?.reasons).toEqual(['gain_composition'])
  })

  it('woman with 27.995%: stored as 28.00 → placed in recomposição', () => {
    expect(unrounded(woman({ body_fat_percent: 27.995 }))).toBe('choice')
    expect(resolve(woman({ body_fat_percent: 27.995 })).decision).toBe('assigned')
  })

  it('woman with 27.004%: stored as 27.00 → ganho de massa available (unrounded, it would be blocked)', () => {
    expect(resolve(woman({ body_fat_percent: 27.004 })).options[1]).toEqual({
      objective: 'ganho_massa',
      ...AVAILABLE,
    })
  })

  it('woman with 27.005%: stored as 27.01 → ganho de massa unavailable by composition', () => {
    expect(resolve(woman({ body_fat_percent: 27.005 })).options[1]).toMatchObject({
      status: 'blocked',
      reasons: ['gain_composition'],
    })
  })

  it('no body fat, 80.999 kg / 180 cm: stored as 81.00 kg (BMI 25.0) → placed in recomposição', () => {
    expect(unrounded(man({ weight_kg: 80.999 }))).toBe('choice')
    expect(resolve(man({ weight_kg: 80.999 }))).toEqual(resolve(man({ weight_kg: 81 })))
    expect(resolve(man({ weight_kg: 80.999 }))).toMatchObject({
      decision: 'assigned',
      basis: 'bmi',
    })
  })

  it('no body fat, 80.994 kg / 180 cm: stored as 80.99 kg → chooses among the three', () => {
    expect(resolve(man({ weight_kg: 80.994 }))).toMatchObject({ decision: 'choice', basis: 'bmi' })
  })

  it('no body fat, 64 kg / 160.004 cm: the height is stored as 160.00 (BMI 25.0) → placed in recomposição', () => {
    expect(unrounded(woman({ height_cm: 160.004, weight_kg: 64 }))).toBe('choice')
    expect(resolve(woman({ height_cm: 160.004, weight_kg: 64 })).decision).toBe('assigned')
  })
})

describe('resolveOnboardingEligibility: what it never does', () => {
  it('returns no body value: only the decision, the reasons and the texts', () => {
    const input = man({ height_cm: 181.37, weight_kg: 77.31, body_fat_percent: 19.37 })
    const result = resolve(input)
    expect(Object.keys(result).sort()).toEqual([
      'basis',
      'decision',
      'notice',
      'objective',
      'options',
    ])
    for (const option of result.options) {
      expect(Object.keys(option).sort()).toEqual(['message', 'objective', 'reasons', 'status'])
    }
    const serialized = JSON.stringify(result)
    for (const value of ['181.37', '77.31', '19.37', '181,37', '77,31', '19,37']) {
      expect(serialized).not.toContain(value)
    }
  })

  it('does not change the request it was given', () => {
    const input = man({ body_fat_percent: 19.995, weight_kg: 80.999 })
    const before = structuredClone(input)
    resolve(input)
    expect(input).toEqual(before)
  })

  it('a value the rule cannot read is refused, never answered with a guess', () => {
    // Outside the request contract on purpose (the schema lets no zero in).
    expect(() => resolve(man({ height_cm: 0 }))).toThrowError(
      expect.objectContaining({
        status: 422,
        code: 'validation_failed',
        details: {
          fields: [
            {
              path: 'height_cm',
              code: 'custom',
              message: 'The objective cannot be decided on this value',
            },
          ],
        },
      }),
    )
  })
})
