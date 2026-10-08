import {
  DAY_BALANCE_AGAINST_EXPENDITURE,
  DEFAULT_CALC_CONFIG,
  dayEnergyBalance,
  eatingBalance,
  netBalance,
} from '@mpp/core'
import { afterEach, describe, expect, it } from 'vitest'
import {
  flowDayBalanceInputs,
  flowEnergyContextLines,
  flowEnergyNumbers,
} from './flow-energy-context.js'

// iPhone, staging, 2026-10-04: day row at the turn of the report — target
// 2980, consumed 541, exercise 322, generated daily_balance -2761.
const REPORT = { caloriesTarget: 2980, caloriesConsumed: 541, exerciseCalories: 322 }
// What the pipeline adds for that account (ganho de massa, multiplier 1,05).
const GANHO = { protocol: 'ganho_massa', gainSurplusMultiplier: 1.05, programmedDeficitKcal: 0 }
// Roberto's recomposição days: the closer's programmed deficit is 500.
const RECOMP = { protocol: 'recomposicao', gainSurplusMultiplier: 1.05, programmedDeficitKcal: 500 }

describe('flowEnergyNumbers', () => {
  it('the report with no protocol given: food balance -2439 (2439 left) and the legacy net balance -2761, from the core functions', () => {
    const n = flowEnergyNumbers(REPORT)

    // 2026-10-04 (§2c): three fields were added to the result; the numbers of
    // a caller that gives no protocol are the ones of before.
    expect(n).toEqual({
      target: 2980,
      consumed: 541,
      exercise: 322,
      food: -2439,
      net: -2761,
      reference: 2980,
      netIncludesExercise: true,
      netBasis: 'target',
    })
    expect(n.food).toBe(eatingBalance(541, 2980))
    expect(n.net).toBe(netBalance(541, 2980, 322))
    // The two never coincide when there is exercise: that gap is the defect.
    expect((n.food ?? 0) - (n.net ?? 0)).toBe(322)
  })

  it('the report as the pipeline sends it (ganho_massa): the same food balance, the day balance -2297 against 2838, no exercise', () => {
    const n = flowEnergyNumbers({ ...REPORT, ...GANHO })

    expect(n).toEqual({
      target: 2980,
      consumed: 541,
      exercise: 322,
      food: -2439,
      net: -2297,
      reference: 2838,
      netIncludesExercise: false,
      netBasis: 'expenditure',
    })
    // The same core function the Today screen uses.
    expect(n.net).toBe(
      dayEnergyBalance({
        protocol: 'ganho_massa',
        caloriesConsumed: 541,
        caloriesTarget: 2980,
        exerciseCalories: 322,
        gainSurplusMultiplier: 1.05,
      }).balance,
    )
  })

  it('recomposição 19/05 (2076 / 1843, treino 565, déficit 500): -832 against 2343, with exercise', () => {
    expect(
      flowEnergyNumbers({
        caloriesTarget: 1843,
        caloriesConsumed: 2076,
        exerciseCalories: 565,
        ...RECOMP,
      }),
    ).toEqual({
      target: 1843,
      consumed: 2076,
      exercise: 565,
      food: 233,
      net: -832,
      reference: 2343,
      netIncludesExercise: true,
      netBasis: 'expenditure',
    })
  })

  it('rounds, and a target met exactly is 0, never -0', () => {
    const met = flowEnergyNumbers({
      caloriesTarget: 2980,
      caloriesConsumed: 2980,
      exerciseCalories: 0,
    })
    expect(Object.is(met.food, 0)).toBe(true)
    expect(Object.is(met.net, 0)).toBe(true)

    const fractional = flowEnergyNumbers({
      caloriesTarget: 2980.4,
      caloriesConsumed: 541.2,
      exerciseCalories: 322,
    })
    expect(fractional.food).toBe(-2439)
    expect(fractional.net).toBe(-2761)
  })

  it.each([
    null,
    undefined,
    0,
    -100,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('target %s gives no balance at all', (caloriesTarget) => {
    expect(flowEnergyNumbers({ ...REPORT, caloriesTarget })).toMatchObject({
      target: null,
      food: null,
      net: null,
    })
  })

  it('a non-finite consumed or exercise counts as 0', () => {
    expect(
      flowEnergyNumbers({
        caloriesTarget: 2980,
        caloriesConsumed: Number.NaN,
        exerciseCalories: Number.NaN,
      }),
    ).toEqual({
      target: 2980,
      consumed: 0,
      exercise: 0,
      food: -2980,
      net: -2980,
      reference: 2980,
      netIncludesExercise: true,
      netBasis: 'target',
    })
  })
})

describe('flowDayBalanceInputs', () => {
  it("the programmed deficit is the daily closer's expression: recomposição ? (deficit_level ?? 500) : 0", () => {
    const config = { ganho_massa_surplus_multiplier: 1.05 }
    expect(
      flowDayBalanceInputs({ currentProtocol: 'recomposicao', deficitLevel: 400 }, config),
    ).toEqual({
      protocol: 'recomposicao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 400,
      // Review of 2026-10-04: one field more (the verdict about the day's
      // stored target). With no day row given nothing is checked: true.
      targetMatchesProtocol: true,
    })
    expect(
      flowDayBalanceInputs({ currentProtocol: 'recomposicao', deficitLevel: null }, config),
    ).toEqual({
      protocol: 'recomposicao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 500,
      targetMatchesProtocol: true,
    })
    for (const currentProtocol of ['ganho_massa', 'manutencao', null]) {
      expect(flowDayBalanceInputs({ currentProtocol, deficitLevel: 600 }, config)).toEqual({
        protocol: currentProtocol,
        gainSurplusMultiplier: 1.05,
        programmedDeficitKcal: 0,
        targetMatchesProtocol: true,
      })
    }
  })

  it('the multiplier comes from the loaded calc config; without one, the default', () => {
    const profile = { currentProtocol: 'ganho_massa', deficitLevel: null }
    expect(
      flowDayBalanceInputs(profile, { ganho_massa_surplus_multiplier: 1.1 }).gainSurplusMultiplier,
    ).toBe(1.1)
    expect(flowDayBalanceInputs(profile).gainSurplusMultiplier).toBe(
      DEFAULT_CALC_CONFIG.ganho_massa_surplus_multiplier,
    )
    expect(DEFAULT_CALC_CONFIG.ganho_massa_surplus_multiplier).toBe(1.05)
  })

  it('a multiplier saved as the JSON text "1.05" is read as the number 1,05', () => {
    // Review of 2026-10-04: the loader copies the JSON value untouched; the
    // target was computed with 1,05 (JS coercion) and the reference was not.
    const asText = { ganho_massa_surplus_multiplier: '1.05' } as unknown as {
      ganho_massa_surplus_multiplier: number
    }
    const inputs = flowDayBalanceInputs(
      { currentProtocol: 'ganho_massa', deficitLevel: null },
      asText,
    )

    expect(inputs.gainSurplusMultiplier).toBe(1.05)
    expect(
      flowEnergyNumbers({
        caloriesTarget: 2799,
        caloriesConsumed: 2800,
        exerciseCalories: 0,
        ...inputs,
      }),
    ).toMatchObject({ net: 134, reference: 2666, netBasis: 'expenditure' })
  })

  // homem, 81 kg, 180 cm, 44 anos, moderado (the review's profile): what the
  // profile gives now under each rule.
  const TARGETS = { recomposicao: 1564, ganho_massa: 2799, manutencao: 2666 }

  it('the day row is handed to the same core function the Today screen uses: effective protocol and stored target', () => {
    // Day of a protocol change: 2799 stored in the morning (ganho de massa),
    // recomposição at noon → the stored target is of another rule.
    expect(
      flowDayBalanceInputs({ currentProtocol: 'recomposicao', deficitLevel: 500 }, undefined, {
        protocol: null,
        storedTargetKcal: 2799,
        targetByProtocol: TARGETS,
      }),
    ).toEqual({
      protocol: 'recomposicao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 500,
      targetMatchesProtocol: false,
    })
    // Closed day row in recomposição under a profile now in ganho de massa:
    // the row's protocol and the programmed deficit of THAT protocol.
    expect(
      flowDayBalanceInputs({ currentProtocol: 'ganho_massa', deficitLevel: null }, undefined, {
        protocol: 'recomposicao',
        storedTargetKcal: 1564,
        targetByProtocol: TARGETS,
      }),
    ).toEqual({
      protocol: 'recomposicao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 500,
      targetMatchesProtocol: true,
    })
    // No day row, or a row with no stored target: the profile protocol.
    for (const day of [
      null,
      { protocol: null, storedTargetKcal: null, targetByProtocol: TARGETS },
    ]) {
      expect(
        flowDayBalanceInputs(
          { currentProtocol: 'recomposicao', deficitLevel: 500 },
          undefined,
          day,
        ),
      ).toMatchObject({ protocol: 'recomposicao', targetMatchesProtocol: true })
    }
  })
})

describe('flowEnergyContextLines — day of a protocol change (review of 2026-10-04)', () => {
  it('ganho de massa in the morning (2799 stored), recomposição at noon, 2500 consumed: the legacy number -299, and no block-credit claim', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2799,
      caloriesConsumed: 2500,
      exerciseCalories: 0,
      protocol: 'recomposicao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 500,
      targetMatchesProtocol: false,
      hasSnapshot: true,
    })

    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 299 kcal')
    // Before: "…gasto do dia = 3299 kcal de gasto de referência + 0 kcal de
    // exercício): -799 kcal … é o déficit ou superávit real do dia até agora".
    // The closer replaces the day's target at closing, so the recomposição
    // wording "déficit programado − este número" is not used on this day.
    expect(lines[2]).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -299 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
    expect(lines.join('\n')).not.toContain('3299')
    expect(lines.join('\n')).not.toContain('-799')
    expect(lines.join('\n')).not.toContain('déficit ou superávit real do dia')
    // The rule line is the protocol's, unchanged.
    expect(lines[3]).toContain('o gasto do treino fica à parte (acelera o bloco 7700).')
  })

  it('the inverse (1564 stored in recomposição, ganho de massa at noon, 2000 consumed): +436, with exercise, against the stored target', () => {
    const input = {
      caloriesTarget: 1564,
      caloriesConsumed: 2000,
      exerciseCalories: 0,
      protocol: 'ganho_massa',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 0,
      targetMatchesProtocol: false,
    }

    expect(flowEnergyNumbers(input)).toMatchObject({
      food: 436,
      net: 436,
      reference: 1564,
      netIncludesExercise: true,
      netBasis: 'target',
    })
    // Before: +510 against 1490.
    expect(flowEnergyContextLines({ ...input, hasSnapshot: true })[2]).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): 436 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
  })

  it('targetMatchesProtocol true or absent: the protocol line, as before', () => {
    const day = { caloriesTarget: 1843, caloriesConsumed: 2076, exerciseCalories: 565, ...RECOMP }

    expect(
      flowEnergyContextLines({ ...day, targetMatchesProtocol: true, hasSnapshot: true }),
    ).toEqual(flowEnergyContextLines({ ...day, hasSnapshot: true }))
    expect(flowEnergyNumbers({ ...day, targetMatchesProtocol: true }).net).toBe(-832)
  })
})

describe('flowEnergyContextLines', () => {
  it('the report (ganho_massa): the exact four lines the Flow model reads', () => {
    // 2026-10-04 (§2c): the third line was "COM exercício (consumido − meta −
    // exercício): -2761 kcal". In ganho de massa the day's balance is against
    // the reference expenditure (2980 ÷ 1,05 = 2838) and the workout is not
    // added. The food line, the exercise line and the rule did not change.
    expect(flowEnergyContextLines({ ...REPORT, ...GANHO, hasSnapshot: true })).toEqual([
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
      '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
      '- Balanço calórico de hoje (consumido − gasto de referência de 2838 kcal; o exercício já está considerado neste valor e não é somado): -2297 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
      '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só o que está na linha "Para COMIDA". Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o que resta para comida; o gasto do treino fica à parte.',
    ])
  })

  it('keeps the legacy prefixes as substrings (shared rules in the database may cite them)', () => {
    for (const balance of [GANHO, { ...GANHO, protocol: 'manutencao' }, RECOMP, {}]) {
      const text = flowEnergyContextLines({ ...REPORT, ...balance, hasSnapshot: true }).join('\n')

      expect(text).toContain('Exercício hoje: 322 kcal queimadas')
      expect(text).toContain('Balanço calórico de hoje')
      // …but never the unlabeled legacy line.
      expect(text).not.toContain('- Balanço calórico de hoje: ')
    }
  })

  it('over the target: the food line is an excess even when exercise makes the net negative', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 3200,
      exerciseCalories: 322,
      ...GANHO,
      hasSnapshot: true,
    })

    expect(lines[0]).toBe(
      '- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de 220 kcal acima da meta',
    )
    // 2026-10-04 (§2c): was "COM exercício (…): -102 kcal" — a deficit shown
    // to someone 220 kcal over the target. Against 2838, no exercise: +362.
    expect(lines[2]).toBe(
      '- Balanço calórico de hoje (consumido − gasto de referência de 2838 kcal; o exercício já está considerado neste valor e não é somado): 362 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
  })

  it('ganho de massa between the reference and the target: food is still left AND the day is a surplus', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 2900,
      exerciseCalories: 322,
      ...GANHO,
      hasSnapshot: true,
    })

    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 80 kcal')
    expect(lines[2]).toContain('não é somado): 62 kcal (negativo=déficit, positivo=superávit)')
  })

  it.each([
    322, 0,
  ])('ganho de massa eating exactly the target with a %s kcal workout: +142 both', (exerciseCalories) => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 2980,
      exerciseCalories,
      ...GANHO,
      hasSnapshot: true,
    })

    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 0 kcal')
    expect(lines[2]).toContain('gasto de referência de 2838 kcal')
    expect(lines[2]).toContain('não é somado): 142 kcal (negativo=déficit, positivo=superávit)')
  })

  it('manutenção (3044 / 3044, treino 400): the balance is 0, never -400 and never "-0"', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 3044,
      caloriesConsumed: 3044,
      exerciseCalories: 400,
      protocol: 'manutencao',
      gainSurplusMultiplier: 1.05,
      programmedDeficitKcal: 0,
      hasSnapshot: true,
    })

    expect(lines[2]).toBe(
      '- Balanço calórico de hoje (consumido − gasto de referência de 3044 kcal; o exercício já está considerado neste valor e não é somado): 0 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
    expect(lines.join('\n')).not.toContain('-400')
    expect(lines.join('\n')).not.toContain('-0')
  })

  it('the derived example (2799 against 2666): +133 with or without a 300 kcal workout — a recalculation of the audit, not a number of the client', () => {
    for (const exerciseCalories of [300, 0]) {
      const lines = flowEnergyContextLines({
        caloriesTarget: 2799,
        caloriesConsumed: 2799,
        exerciseCalories,
        ...GANHO,
        hasSnapshot: true,
      })
      expect(lines[2]).toContain('gasto de referência de 2666 kcal')
      expect(lines[2]).toContain('não é somado): 133 kcal')
    }
  })

  it('over the target: the rule asks for the excess, never for "o que resta"', () => {
    // Review 2026-10-04, round 2 (1843 / 2000 / 565): the rule said "mostre
    // meta, consumido e o que resta para comida" next to a line with an
    // excess — a number the context does not have.
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao']) {
      const lines = flowEnergyContextLines({
        caloriesTarget: 1843,
        caloriesConsumed: 2000,
        exerciseCalories: 565,
        protocol,
        hasSnapshot: true,
      })
      const block = protocol === 'recomposicao' ? ' (acelera o bloco 7700)' : ''

      expect(lines[0]).toBe(
        '- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de 157 kcal acima da meta',
      )
      expect(lines[3]).toBe(
        `- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; a linha "Para COMIDA" mostra excedente, então não resta nada para comida hoje. Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o excedente; o gasto do treino fica à parte${block}.`,
      )
      expect(lines[3]).not.toContain('o que resta para comida')
      expect(lines[3]).not.toContain('pode comer é só')
    }
  })

  it('under the target or exactly on it: the rule still asks for what is left', () => {
    for (const caloriesConsumed of [541, 2980]) {
      const rule = flowEnergyContextLines({
        ...REPORT,
        caloriesConsumed,
        protocol: 'ganho_massa',
        hasSnapshot: true,
      })[3]

      expect(rule).toContain('mostre meta, consumido e o que resta para comida')
      expect(rule).not.toContain('excedente;')
      expect(rule).not.toContain('não resta nada')
    }
  })

  it('target met exactly reads "restam 0 kcal", never "-0"', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 2980,
      exerciseCalories: 322,
      protocol: 'manutencao',
      hasSnapshot: true,
    })

    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 0 kcal')
    expect(lines.join('\n')).not.toContain('-0')
  })

  it('the 7700 block is named only in recomposição', () => {
    const recomp = flowEnergyContextLines({
      caloriesTarget: 1843,
      caloriesConsumed: 1407,
      exerciseCalories: 467,
      ...RECOMP,
      hasSnapshot: true,
    })
    expect(recomp[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 436 kcal')
    // 2026-10-04 (§2c): was "(consumido − meta − exercício): -903 kcal … o
    // crédito do bloco 7700 só é calculado no fechamento do dia (déficit
    // programado − este número)". The number is now that subtraction already
    // done: 1407 − (1843 + 500) − 467 = −1403, the real deficit of the day.
    expect(recomp[2]).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − gasto do dia; gasto do dia = 2343 kcal de gasto de referência + 467 kcal de exercício): -1403 kcal (negativo=déficit, positivo=superávit) — é o déficit ou superávit real do dia até agora, provisório até o dia fechar; o crédito no bloco 7700 só acontece no fechamento do dia e este número NÃO é o que resta para comer',
    )
    expect(recomp[3]?.endsWith('o gasto do treino fica à parte (acelera o bloco 7700).')).toBe(true)

    for (const balance of [
      GANHO,
      { ...GANHO, protocol: 'manutencao' },
      { ...GANHO, protocol: null },
      { ...GANHO, protocol: undefined },
    ]) {
      const text = flowEnergyContextLines({ ...REPORT, ...balance, hasSnapshot: true }).join('\n')
      expect(text).not.toContain('7700')
      expect(text).not.toContain('7.700')
      expect(text).not.toMatch(/bloco/i)
    }
  })

  it('recomposição, the days the client wrote about: 19/05 → -832, 21/05 → -897, open day 22/05 → -2423', () => {
    // 20/05/2026 08:39: "O déficit de ontem deveria ser 500 - 233=267 + 565 = 832".
    // 21/05/2026 22:11: "500-126=374 / 374+523=897 kcal de déficit hj".
    for (const [caloriesConsumed, exerciseCalories, before, after] of [
      [2076, 565, -332, -832],
      [1969, 523, -397, -897],
      [568, 648, -1923, -2423],
    ] as const) {
      const line = flowEnergyContextLines({
        caloriesTarget: 1843,
        caloriesConsumed,
        exerciseCalories,
        ...RECOMP,
        hasSnapshot: true,
      })[2]

      expect(netBalance(caloriesConsumed, 1843, exerciseCalories)).toBe(before)
      expect(line).toContain(
        `gasto do dia = 2343 kcal de gasto de referência + ${exerciseCalories} kcal de exercício): ${after} kcal (negativo=déficit, positivo=superávit)`,
      )
    }
  })

  it('recomposição: the day balance is provisional, and the block is credited only at closing', () => {
    // Review 2026-10-04, round 2: the line said "é o número que o fechamento
    // do dia usa no bloco 7700" next to the balance against the TARGET, and
    // the model quoted 903 as the credit (the credit was 1.403). Since §2c
    // the number is the real deficit itself (−1403); it is still not a
    // credit: in the morning (200 consumed) the closer may credit only the
    // programmed deficit, or nothing at all (docs/CALCULO-MPP.md §3).
    for (const caloriesConsumed of [1407, 200, 2000]) {
      const line = flowEnergyContextLines({
        caloriesTarget: 1843,
        caloriesConsumed,
        exerciseCalories: 467,
        ...RECOMP,
        hasSnapshot: true,
      })[2]

      expect(line).not.toContain('é o número que o fechamento')
      expect(line).not.toMatch(/usa no bloco/)
      expect(line).not.toContain('déficit programado − este número')
      expect(line).toContain('provisório até o dia fechar')
      expect(line).toContain('o crédito no bloco 7700 só acontece no fechamento do dia')
      expect(line?.endsWith('NÃO é o que resta para comer')).toBe(true)
    }
  })

  it('no day row yet: only the food line and the rule — no exercise line, no net balance', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 0,
      exerciseCalories: 0,
      ...GANHO,
      hasSnapshot: false,
    })

    expect(lines).toHaveLength(2)
    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2980 kcal')
    expect(lines[1]?.startsWith('- REGRA: exercício NÃO libera comida nem apaga excedente.')).toBe(
      true,
    )
    expect(lines.join('\n')).not.toContain('COM exercício')
    expect(lines.join('\n')).not.toContain('Balanço calórico de hoje')
    expect(lines.join('\n')).not.toContain('-2980')
    expect(lines.join('\n')).not.toContain('-2838')
  })

  it.each([
    null,
    0,
    Number.NaN,
  ])('target %s: no numeric balance line, and the rule does not point to a line that is not there', (caloriesTarget) => {
    const lines = flowEnergyContextLines({
      caloriesTarget,
      caloriesConsumed: 541,
      exerciseCalories: 322,
      protocol: null,
      hasSnapshot: true,
    })

    expect(lines).toEqual([
      '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
      '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só meta − consumido, sem exercício. Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso; o gasto do treino fica à parte.',
    ])
  })

  it('is plain text: no Markdown emphasis, no italics note, no backtick', () => {
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao']) {
      for (const hasSnapshot of [true, false]) {
        const text = flowEnergyContextLines({ ...REPORT, protocol, hasSnapshot }).join('\n')
        expect(text).not.toContain('**')
        expect(text).not.toContain('_(')
        expect(text).not.toContain('`')
      }
    }
  })

  it('never says a bare "a resposta é não" nor that exercise "entra apenas no balanço do dia"', () => {
    // Review of the design: in ganho de massa the patient is 2439 kcal BELOW
    // the target; a flat "não" would be the opposite of the protocol's goal,
    // and outside recomposição the exercise is NOT added to the day balance
    // (docs/CALCULO-MPP.md §2c: ganho de massa and manutenção measure consumed
    // against BMR × activity factor; rule stated by the client, confirmation
    // pending), so "entra apenas no balanço do dia" would be false there.
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao']) {
      const text = flowEnergyContextLines({ ...REPORT, protocol, hasSnapshot: true }).join('\n')
      expect(text).not.toContain('a resposta é não')
      expect(text).not.toContain('entra apenas no balanço do dia')
    }
  })
})

// The switch of docs/CALCULO-MPP.md §2c. Off = the lines of before 2026-10-04.
describe('flowEnergyContextLines — DAY_BALANCE_AGAINST_EXPENDITURE off', () => {
  type Switches = Record<keyof typeof DAY_BALANCE_AGAINST_EXPENDITURE, boolean>
  const switches = DAY_BALANCE_AGAINST_EXPENDITURE as Switches
  const original: Switches = { ...DAY_BALANCE_AGAINST_EXPENDITURE }
  afterEach(() => {
    Object.assign(switches, original)
  })

  it('ganho de massa and manutenção: the legacy "COM exercício (consumido − meta − exercício)" line, byte for byte', () => {
    Object.assign(switches, { ganho_massa: false, manutencao: false })

    expect(flowEnergyContextLines({ ...REPORT, ...GANHO, hasSnapshot: true })[2]).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -2761 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
    expect(
      flowEnergyContextLines({
        caloriesTarget: 3044,
        caloriesConsumed: 3044,
        exerciseCalories: 400,
        ...GANHO,
        protocol: 'manutencao',
        hasSnapshot: true,
      })[2],
    ).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -400 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
  })

  it('recomposição: the legacy line with the block wording, byte for byte', () => {
    switches.recomposicao = false

    expect(
      flowEnergyContextLines({
        caloriesTarget: 1843,
        caloriesConsumed: 1407,
        exerciseCalories: 467,
        ...RECOMP,
        hasSnapshot: true,
      })[2],
    ).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -903 kcal (negativo=déficit, positivo=superávit) — o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer',
    )
  })

  it('protocol not set: the legacy line with the switch ON too (never changed)', () => {
    expect(
      flowEnergyContextLines({ ...REPORT, ...GANHO, protocol: null, hasSnapshot: true })[2],
    ).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -2761 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
    )
  })
})
