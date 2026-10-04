import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type CalcConfig, DEFAULT_CALC_CONFIG } from '../calc-config.js'
import { dayEnergyBalance } from './balance.js'
import {
  DAY_BALANCE_DAY_ROW_GUARD,
  dailyTargetByProtocol,
  resolveDayBalanceInputs,
} from './day-balance-inputs.js'
import type { ProfileRow } from './targets.js'

// Review of 2026-10-04 (balance lens) of the per-protocol day balance
// (docs/CALCULO-MPP.md §2c). The reviewer's profile: homem, 81 kg, 180 cm,
// 44 anos, moderado → BMR 1720; manutenção 2666; ganho de massa 2799;
// recomposição/500 = 1720 × 1,2 − 500 = 1564.
const REVIEW_PROFILE: ProfileRow = {
  sex: 'masculino',
  birth_date: '1982-01-15',
  height_cm: 180,
  weight_kg: 81,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}
// QA account A (staging, 2026-10-04): 185 cm, moderado; the day row stored
// 2980 before the weight of the day (80,5 kg) was registered.
const QA_PROFILE: ProfileRow = {
  ...REVIEW_PROFILE,
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80.5,
}

const guard = DAY_BALANCE_DAY_ROW_GUARD as { enabled: boolean }

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-10-04T15:03:40.503Z'))
})
afterEach(() => {
  guard.enabled = true
  vi.useRealTimers()
})

const resolve = (
  profile: ProfileRow,
  day: { rowProtocol?: string | null; storedTargetKcal?: number | null } = {},
  config: CalcConfig = DEFAULT_CALC_CONFIG,
) =>
  resolveDayBalanceInputs({
    profileProtocol: profile.current_protocol,
    deficitLevel: profile.deficit_level,
    gainSurplusMultiplier: config.ganho_massa_surplus_multiplier,
    dayRowProtocol: day.rowProtocol,
    storedTargetKcal: day.storedTargetKcal,
    targetByProtocol: dailyTargetByProtocol(profile, config),
  })

describe('dailyTargetByProtocol', () => {
  it('the target the same profile gives under each of the three rules', () => {
    expect(dailyTargetByProtocol(REVIEW_PROFILE, DEFAULT_CALC_CONFIG)).toEqual({
      recomposicao: 1564,
      ganho_massa: 2799,
      manutencao: 2666,
    })
    // The profile's own protocol does not matter, and deficit_level does.
    expect(
      dailyTargetByProtocol(
        { ...REVIEW_PROFILE, current_protocol: 'recomposicao', deficit_level: 400 },
        DEFAULT_CALC_CONFIG,
      ),
    ).toEqual({ recomposicao: 1664, ganho_massa: 2799, manutencao: 2666 })
  })

  it('no profile, or a profile that cannot be computed: null for the three', () => {
    const none = { recomposicao: null, ganho_massa: null, manutencao: null }

    expect(dailyTargetByProtocol(null, DEFAULT_CALC_CONFIG)).toEqual(none)
    expect(
      dailyTargetByProtocol({ ...REVIEW_PROFILE, height_cm: null }, DEFAULT_CALC_CONFIG),
    ).toEqual(none)
  })
})

describe('resolveDayBalanceInputs — the switch ships ON', () => {
  it('DAY_BALANCE_DAY_ROW_GUARD.enabled is true', () => {
    expect(DAY_BALANCE_DAY_ROW_GUARD).toEqual({ enabled: true })
  })
})

describe('resolveDayBalanceInputs — day of a protocol change (stored target of another rule)', () => {
  it('morning in ganho de massa (2799 stored), recomposição/500 at noon: the stored target is not a recomposição target', () => {
    const profile: ProfileRow = {
      ...REVIEW_PROFILE,
      current_protocol: 'recomposicao',
      deficit_level: 500,
    }

    expect(resolve(profile, { storedTargetKcal: 2799 })).toEqual({
      protocol: 'recomposicao',
      programmedDeficitKcal: 500,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: false,
    })
    // Before: 2500 − (2799 + 500) − 0 = −799 "against 3299", a deficit, when
    // the client's rule gives 2500 − 2064 = +436. Now the legacy number.
    expect(
      dayEnergyBalance({
        ...resolve(profile, { storedTargetKcal: 2799 }),
        caloriesConsumed: 2500,
        caloriesTarget: 2799,
        exerciseCalories: 0,
      }),
    ).toEqual({ balance: -299, referenceKcal: 2799, includesExercise: true, basis: 'target' })
  })

  it('the inverse: recomposição stored 1564, ganho de massa at noon', () => {
    const inputs = resolve(REVIEW_PROFILE, { storedTargetKcal: 1564 })

    expect(inputs.targetMatchesProtocol).toBe(false)
    // Before: 2000 − round(1564 ÷ 1,05) = +510 "against 1490", a surplus,
    // when the client's rule gives 2000 − 2666 = −666.
    expect(
      dayEnergyBalance({
        ...inputs,
        caloriesConsumed: 2000,
        caloriesTarget: 1564,
        exerciseCalories: 0,
      }),
    ).toEqual({ balance: 436, referenceKcal: 1564, includesExercise: true, basis: 'target' })
  })

  it('first day: 2666 stored with no protocol yet (the manutenção rule), then recomposição', () => {
    const profile: ProfileRow = { ...REVIEW_PROFILE, current_protocol: 'recomposicao' }
    const inputs = resolve(profile, { storedTargetKcal: 2666 })

    expect(inputs.targetMatchesProtocol).toBe(false)
    // Before: 1800 − (2666 + 500) = −1366 "against 3166".
    expect(
      dayEnergyBalance({
        ...inputs,
        caloriesConsumed: 1800,
        caloriesTarget: 2666,
        exerciseCalories: 0,
      }).balance,
    ).toBe(-866)
  })

  it.each([
    ['recomposicao', 1564],
    ['ganho_massa', 2799],
    ['manutencao', 2666],
  ] as const)('%s with its own target stored (%s): the protocol rule stands', (protocol, stored) => {
    const profile: ProfileRow = { ...REVIEW_PROFILE, current_protocol: protocol }

    expect(resolve(profile, { storedTargetKcal: stored }).targetMatchesProtocol).toBe(true)
  })

  it('first day, no protocol stored 2666, then manutenção: the same rule wrote it, the protocol stands', () => {
    const profile: ProfileRow = { ...REVIEW_PROFILE, current_protocol: 'manutencao' }

    expect(resolve(profile, { storedTargetKcal: 2666 }).targetMatchesProtocol).toBe(true)
  })
})

describe('resolveDayBalanceInputs — a new weight is NOT a change of protocol', () => {
  it('QA account, 2026-10-04: stored 2980 (at 80 kg), profile at 80,5 kg gives 2988 → still ganho de massa', () => {
    const now = dailyTargetByProtocol(QA_PROFILE, DEFAULT_CALC_CONFIG)

    expect(now).toEqual({ recomposicao: 1704, ganho_massa: 2988, manutencao: 2846 })
    expect(resolve(QA_PROFILE, { storedTargetKcal: 2980 }).targetMatchesProtocol).toBe(true)
    expect(
      dayEnergyBalance({
        ...resolve(QA_PROFILE, { storedTargetKcal: 2980 }),
        caloriesConsumed: 541,
        caloriesTarget: 2980,
        exerciseCalories: 322,
      }),
    ).toEqual({
      balance: -2297,
      referenceKcal: 2838,
      includesExercise: false,
      basis: 'expenditure',
    })
  })

  it('a tie between two rules keeps the protocol', () => {
    // 2732,5 is not reachable (targets are integers); 2733 is 66 from ganho
    // (2799) and 67 from manutenção (2666): ganho de massa stands, and one
    // kcal lower it does not.
    expect(resolve(REVIEW_PROFILE, { storedTargetKcal: 2733 }).targetMatchesProtocol).toBe(true)
    expect(resolve(REVIEW_PROFILE, { storedTargetKcal: 2732 }).targetMatchesProtocol).toBe(false)
    // An exact tie: with a multiplier of 1 ganho and manutenção are the same target.
    const flat: CalcConfig = { ...DEFAULT_CALC_CONFIG, ganho_massa_surplus_multiplier: 1 }
    expect(resolve(REVIEW_PROFILE, { storedTargetKcal: 2666 }, flat).targetMatchesProtocol).toBe(
      true,
    )
  })
})

describe('resolveDayBalanceInputs — nothing to compare: the protocol stands', () => {
  it.each([null, undefined, 0, -10, Number.NaN])('stored target %s', (stored) => {
    const profile: ProfileRow = { ...REVIEW_PROFILE, current_protocol: 'recomposicao' }

    expect(resolve(profile, { storedTargetKcal: stored }).targetMatchesProtocol).toBe(true)
  })

  it('a profile that cannot be computed (no height)', () => {
    const profile: ProfileRow = {
      ...REVIEW_PROFILE,
      current_protocol: 'recomposicao',
      height_cm: null,
    }

    expect(resolve(profile, { storedTargetKcal: 2799 }).targetMatchesProtocol).toBe(true)
  })

  it('no table of targets given, protocol not set, or a protocol that is not one of the three', () => {
    expect(
      resolveDayBalanceInputs({
        profileProtocol: 'recomposicao',
        deficitLevel: 500,
        storedTargetKcal: 2799,
      }).targetMatchesProtocol,
    ).toBe(true)
    expect(
      resolve({ ...REVIEW_PROFILE, current_protocol: null }, { storedTargetKcal: 1564 }),
    ).toEqual({
      protocol: null,
      programmedDeficitKcal: 0,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: true,
    })
    expect(resolve(REVIEW_PROFILE, { rowProtocol: 'cutting', storedTargetKcal: 1564 })).toEqual({
      protocol: 'cutting',
      programmedDeficitKcal: 0,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: true,
    })
  })
})

describe('resolveDayBalanceInputs — effective protocol: the day row first, else the profile', () => {
  it('closed day row in recomposição, profile today in ganho de massa: recomposição and ITS programmed deficit', () => {
    // The reviewer's case: the app used the row protocol with the profile
    // protocol's deficit (0) and the Flow used ganho de massa.
    expect(resolve(QA_PROFILE, { rowProtocol: 'recomposicao', storedTargetKcal: 1843 })).toEqual({
      protocol: 'recomposicao',
      programmedDeficitKcal: 500,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: true,
    })
    expect(
      resolve(
        { ...QA_PROFILE, deficit_level: 600 },
        { rowProtocol: 'recomposicao', storedTargetKcal: 1843 },
      ).programmedDeficitKcal,
    ).toBe(600)
  })

  it('the inverse: closed day row in ganho de massa, profile today in recomposição/500 → no programmed deficit', () => {
    const profile: ProfileRow = {
      ...QA_PROFILE,
      current_protocol: 'recomposicao',
      deficit_level: 500,
    }

    expect(resolve(profile, { rowProtocol: 'ganho_massa', storedTargetKcal: 2980 })).toEqual({
      protocol: 'ganho_massa',
      programmedDeficitKcal: 0,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: true,
    })
  })

  it('no protocol on the day row (open day): the profile protocol and the closer expression', () => {
    for (const [protocol, level, expected] of [
      ['recomposicao', 400, 400],
      ['recomposicao', null, 500],
      ['ganho_massa', 600, 0],
      ['manutencao', 600, 0],
      [null, 600, 0],
    ] as const) {
      const inputs = resolveDayBalanceInputs({ profileProtocol: protocol, deficitLevel: level })

      expect(inputs.protocol).toBe(protocol)
      expect(inputs.programmedDeficitKcal).toBe(expected)
    }
  })
})

describe('resolveDayBalanceInputs — the multiplier is read as a number', () => {
  const multiplier = (value: unknown) =>
    resolveDayBalanceInputs({
      profileProtocol: 'ganho_massa',
      deficitLevel: null,
      gainSurplusMultiplier: value,
    }).gainSurplusMultiplier

  it('a config row saved as the JSON text "1.05" is 1,05, as in the target computation', () => {
    expect(multiplier('1.05')).toBe(1.05)
    expect(multiplier(1.1)).toBe(1.1)
    // Before: Number.isFinite('1.05') is false → the reference fell to the
    // target itself (2799, +1) while the target had been computed with 1,05.
    expect(
      dayEnergyBalance({
        protocol: 'ganho_massa',
        caloriesConsumed: 2800,
        caloriesTarget: 2799,
        exerciseCalories: 0,
        gainSurplusMultiplier: multiplier('1.05'),
      }),
    ).toEqual({ balance: 134, referenceKcal: 2666, includesExercise: false, basis: 'expenditure' })
  })

  it('absent or null: the default 1,05', () => {
    expect(multiplier(undefined)).toBe(1.05)
    expect(multiplier(null)).toBe(1.05)
  })

  it('a text that is not a number never invents a reference: the target stands in', () => {
    expect(Number.isNaN(multiplier('cinco por cento'))).toBe(true)
    expect(
      dayEnergyBalance({
        protocol: 'ganho_massa',
        caloriesConsumed: 2800,
        caloriesTarget: 2799,
        exerciseCalories: 0,
        gainSurplusMultiplier: multiplier('cinco por cento'),
      }).referenceKcal,
    ).toBe(2799)
  })
})

describe('resolveDayBalanceInputs — DAY_BALANCE_DAY_ROW_GUARD off: what it did before', () => {
  it('the stored target is not checked: the wrong-sign number of the review comes back', () => {
    guard.enabled = false
    const profile: ProfileRow = {
      ...REVIEW_PROFILE,
      current_protocol: 'recomposicao',
      deficit_level: 500,
    }
    const inputs = resolve(profile, { storedTargetKcal: 2799 })

    expect(inputs.targetMatchesProtocol).toBe(true)
    expect(
      dayEnergyBalance({
        ...inputs,
        caloriesConsumed: 2500,
        caloriesTarget: 2799,
        exerciseCalories: 0,
      }),
    ).toEqual({ balance: -799, referenceKcal: 3299, includesExercise: true, basis: 'expenditure' })
  })

  it('the day row protocol is ignored: the profile protocol and the profile protocol deficit', () => {
    guard.enabled = false

    expect(resolve(QA_PROFILE, { rowProtocol: 'recomposicao', storedTargetKcal: 1843 })).toEqual({
      protocol: 'ganho_massa',
      programmedDeficitKcal: 0,
      gainSurplusMultiplier: 1.05,
      targetMatchesProtocol: true,
    })
  })
})
