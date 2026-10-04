import { afterEach, describe, it, expect } from 'vitest'
import {
  DAY_BALANCE_AGAINST_EXPENDITURE,
  dayEnergyBalance,
  eatingBalance,
  netBalance,
  realDailyDeficit,
} from './balance.js'

describe('balanços (regra MPP)', () => {
  it('eatingBalance = consumido − meta (SEM exercício)', () => {
    expect(eatingBalance(1407, 1843)).toBe(-436)
    expect(eatingBalance(2076, 1843)).toBe(233)
  })
  it('netBalance = consumido − meta − exercício (déficit do dia / bloco)', () => {
    expect(netBalance(2076, 1843, 565)).toBe(-332)
    expect(netBalance(1210, 1843, 467)).toBe(-1100)
  })
})

describe('realDailyDeficit (déficit REAL vs manutenção — o que o bloco credita)', () => {
  // = déficit programado − netBalance. Roberto 2026-05-21: comeu +126 vs meta,
  // treinou 523 → netBalance −397; déficit real = 500 − (−397) = 897 (NÃO 397).
  it('caso Roberto: 500 − (−397) = 897', () => {
    expect(realDailyDeficit(500, -397)).toBe(897)
  })
  it('negativo quando comeu acima da MANUTENÇÃO (superávit real)', () => {
    expect(realDailyDeficit(500, 700)).toBe(-200)
  })
  it('protocolo sem déficit programado (0): = −netBalance', () => {
    expect(realDailyDeficit(0, -100)).toBe(100)
  })
})

// Regra dita pelo cliente em 20/01/2026 e 09/03/2026 (texto) e em 22/02/2026
// e 23/02/2026 (áudio); implementada em 2026-10-04 a pedido do Eduardo;
// confirmação do cliente pendente. docs/CALCULO-MPP.md §2c.
//   recomposição: consumido − (BMR × 1,2 + exercício do dia)
//   ganho de massa / manutenção: consumido − (BMR × fator de atividade)
describe('dayEnergyBalance — balanço do dia por protocolo (consumido − gasto do dia)', () => {
  type Switches = Record<keyof typeof DAY_BALANCE_AGAINST_EXPENDITURE, boolean>
  const switches = DAY_BALANCE_AGAINST_EXPENDITURE as Switches
  const original: Switches = { ...DAY_BALANCE_AGAINST_EXPENDITURE }
  afterEach(() => {
    Object.assign(switches, original)
  })

  it('the switch ships ON for the three protocols', () => {
    expect(DAY_BALANCE_AGAINST_EXPENDITURE).toEqual({
      recomposicao: true,
      ganho_massa: true,
      manutencao: true,
    })
  })

  describe('recomposição: against BMR × 1,2 (= meta + déficit programado), WITH exercise', () => {
    it.each([
      // [day, consumed, target, exercise, programmed, legacy net, new balance]
      ['19/05 (2076 / 1843, treino 565)', 2076, 1843, 565, 500, -332, -832],
      ['21/05 (1969 / 1843, treino 523)', 1969, 1843, 523, 500, -397, -897],
      ['22/05 dia aberto (568 / 1843, treino 648)', 568, 1843, 648, 500, -1923, -2423],
      ['20/05 (1407 / 1843, treino 467)', 1407, 1843, 467, 500, -903, -1403],
      ['déficit programado 400', 1600, 1900, 450, 400, -750, -1150],
      ['déficit programado 600', 1600, 1900, 450, 600, -750, -1350],
    ])('%s', (_day, consumed, target, exercise, programmed, legacyNet, expected) => {
      const result = dayEnergyBalance({
        protocol: 'recomposicao',
        caloriesConsumed: consumed,
        caloriesTarget: target,
        exerciseCalories: exercise,
        programmedDeficitKcal: programmed,
      })

      expect(netBalance(consumed, target, exercise)).toBe(legacyNet)
      expect(result).toEqual({
        balance: expected,
        referenceKcal: target + programmed,
        includesExercise: true,
        basis: 'expenditure',
      })
      // = netBalance − programmed deficit = minus the "déficit real do dia"
      // the closer credits (19/05: 832; 21/05: 897).
      expect(result.balance).toBe(legacyNet - programmed)
      expect(result.balance).toBe(0 - realDailyDeficit(programmed, legacyNet))
    })

    it.each([
      undefined,
      null,
      0,
      -500,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ])('programmed deficit %s counts as 0: the reference is the target, nothing is invented', (programmed) => {
      expect(
        dayEnergyBalance({
          protocol: 'recomposicao',
          caloriesConsumed: 2076,
          caloriesTarget: 1843,
          exerciseCalories: 565,
          programmedDeficitKcal: programmed,
        }),
      ).toEqual({
        balance: -332,
        referenceKcal: 1843,
        includesExercise: true,
        basis: 'expenditure',
      })
    })

    it('the gain multiplier is ignored', () => {
      expect(
        dayEnergyBalance({
          protocol: 'recomposicao',
          caloriesConsumed: 2076,
          caloriesTarget: 1843,
          exerciseCalories: 565,
          programmedDeficitKcal: 500,
          gainSurplusMultiplier: 1.05,
        }).balance,
      ).toBe(-832)
    })
  })

  describe('ganho de massa: against meta ÷ multiplicador (= BMR × fator), exercise NOT added', () => {
    it.each([
      // [scenario, consumed, target, exercise, reference, new balance, legacy net]
      ['conta QA (541 / 2980, treino 322)', 541, 2980, 322, 2838, -2297, -2761],
      ['antes do segundo almoço (302)', 302, 2980, 322, 2838, -2536, -3000],
      ['comeu a meta, com treino', 2980, 2980, 322, 2838, 142, -322],
      ['comeu a meta, sem treino', 2980, 2980, 0, 2838, 142, 0],
      ['acima da meta (3200), treino 322', 3200, 2980, 322, 2838, 362, -102],
      ['entre a referência e a meta (2900)', 2900, 2980, 322, 2838, 62, -402],
      ['meta viva 2988 (80,5 kg)', 541, 2988, 322, 2846, -2305, -2769],
      // Recalculated by the audit (81 kg, 180 cm, 44 anos, moderado), NOT a
      // number the client stated.
      ['exemplo derivado 2799 contra 2666, treino 300', 2799, 2799, 300, 2666, 133, -300],
      ['exemplo derivado 2799 contra 2666, sem treino', 2799, 2799, 0, 2666, 133, 0],
    ])('%s', (_scenario, consumed, target, exercise, reference, expected, legacyNet) => {
      const result = dayEnergyBalance({
        protocol: 'ganho_massa',
        caloriesConsumed: consumed,
        caloriesTarget: target,
        exerciseCalories: exercise,
        gainSurplusMultiplier: 1.05,
        // Never used outside recomposição, even if a caller sends it.
        programmedDeficitKcal: 500,
      })

      expect(result).toEqual({
        balance: expected,
        referenceKcal: reference,
        includesExercise: false,
        basis: 'expenditure',
      })
      expect(netBalance(consumed, target, exercise)).toBe(legacyNet)
      // The workout does not move the number.
      expect(
        dayEnergyBalance({
          protocol: 'ganho_massa',
          caloriesConsumed: consumed,
          caloriesTarget: target,
          exerciseCalories: 0,
          gainSurplusMultiplier: 1.05,
        }).balance,
      ).toBe(expected)
    })

    it.each([
      undefined,
      null,
      0,
      -1.05,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ])('invalid multiplier %s: the reference is the target, nothing is invented', (multiplier) => {
      expect(
        dayEnergyBalance({
          protocol: 'ganho_massa',
          caloriesConsumed: 541,
          caloriesTarget: 2980,
          exerciseCalories: 322,
          gainSurplusMultiplier: multiplier,
        }),
      ).toEqual({
        balance: -2439,
        referenceKcal: 2980,
        includesExercise: false,
        basis: 'expenditure',
      })
    })

    it('another configured multiplier moves the reference (1,10 → 2709)', () => {
      expect(
        dayEnergyBalance({
          protocol: 'ganho_massa',
          caloriesConsumed: 2980,
          caloriesTarget: 2980,
          exerciseCalories: 322,
          gainSurplusMultiplier: 1.1,
        }),
      ).toEqual({
        balance: 271,
        referenceKcal: 2709,
        includesExercise: false,
        basis: 'expenditure',
      })
    })
  })

  describe('manutenção: against the target (= BMR × fator), exercise NOT added', () => {
    it.each([
      ['comeu a meta 3044, treino 400', 3044, 3044, 400, 0, -400],
      ['comeu a meta 3044, sem treino', 3044, 3044, 0, 0, 0],
      ['abaixo (2500 / 3044, treino 400)', 2500, 3044, 400, -544, -944],
      ['acima (3300 / 3044, treino 400)', 3300, 3044, 400, 256, -144],
    ])('%s', (_scenario, consumed, target, exercise, expected, legacyNet) => {
      const result = dayEnergyBalance({
        protocol: 'manutencao',
        caloriesConsumed: consumed,
        caloriesTarget: target,
        exerciseCalories: exercise,
        gainSurplusMultiplier: 1.05,
        programmedDeficitKcal: 500,
      })

      expect(result).toEqual({
        balance: expected,
        referenceKcal: target,
        includesExercise: false,
        basis: 'expenditure',
      })
      expect(Object.is(result.balance, -0)).toBe(false)
      expect(netBalance(consumed, target, exercise)).toBe(legacyNet)
    })
  })

  describe("protocol not set or unknown: today's number exactly (netBalance against the target)", () => {
    it.each([
      null,
      undefined,
      '',
      'default',
      'RECOMPOSICAO',
      'ganho',
    ])('protocol %s', (protocol) => {
      for (const [consumed, target, exercise] of [
        [541, 2980, 322],
        [2076, 1843, 565],
        [3044, 3044, 400],
        [0, 1900, 0],
      ] as const) {
        expect(
          dayEnergyBalance({
            protocol,
            caloriesConsumed: consumed,
            caloriesTarget: target,
            exerciseCalories: exercise,
            gainSurplusMultiplier: 1.05,
            programmedDeficitKcal: 500,
          }),
        ).toEqual({
          balance: netBalance(consumed, target, exercise),
          referenceKcal: target,
          includesExercise: true,
          basis: 'target',
        })
      }
    })
  })

  describe("the switch: OFF for a protocol brings today's number back for that protocol only", () => {
    const legacy = (consumed: number, target: number, exercise: number) => ({
      balance: netBalance(consumed, target, exercise),
      referenceKcal: target,
      includesExercise: true,
      basis: 'target',
    })
    const recomp = () =>
      dayEnergyBalance({
        protocol: 'recomposicao',
        caloriesConsumed: 2076,
        caloriesTarget: 1843,
        exerciseCalories: 565,
        programmedDeficitKcal: 500,
      })
    const ganho = () =>
      dayEnergyBalance({
        protocol: 'ganho_massa',
        caloriesConsumed: 541,
        caloriesTarget: 2980,
        exerciseCalories: 322,
        gainSurplusMultiplier: 1.05,
      })
    const manutencao = () =>
      dayEnergyBalance({
        protocol: 'manutencao',
        caloriesConsumed: 3044,
        caloriesTarget: 3044,
        exerciseCalories: 400,
      })

    it('recomposição off: −332 again; the other two keep the rule', () => {
      switches.recomposicao = false

      expect(recomp()).toEqual(legacy(2076, 1843, 565))
      expect(recomp().balance).toBe(-332)
      expect(ganho().balance).toBe(-2297)
      expect(manutencao().balance).toBe(0)
    })

    it('ganho de massa off: −2761 again; the other two keep the rule', () => {
      switches.ganho_massa = false

      expect(ganho()).toEqual(legacy(541, 2980, 322))
      expect(ganho().balance).toBe(-2761)
      expect(recomp().balance).toBe(-832)
      expect(manutencao().balance).toBe(0)
    })

    it('manutenção off: −400 again; the other two keep the rule', () => {
      switches.manutencao = false

      expect(manutencao()).toEqual(legacy(3044, 3044, 400))
      expect(manutencao().balance).toBe(-400)
      expect(recomp().balance).toBe(-832)
      expect(ganho().balance).toBe(-2297)
    })

    it('all three off: every protocol is netBalance against the target', () => {
      Object.assign(switches, { recomposicao: false, ganho_massa: false, manutencao: false })

      expect(recomp().balance).toBe(-332)
      expect(ganho().balance).toBe(-2761)
      expect(manutencao().balance).toBe(-400)
    })
  })

  it('every number published is an integer, and never -0 (the app decodes Int)', () => {
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao']) {
      for (const [consumed, target, exercise] of [
        [541.4, 2980.6, 322.5],
        [2980, 2980, 0],
        [0, 2838, 0],
        [2838, 2980, 0],
      ] as const) {
        const result = dayEnergyBalance({
          protocol,
          caloriesConsumed: consumed,
          caloriesTarget: target,
          exerciseCalories: exercise,
          gainSurplusMultiplier: 1.05,
          programmedDeficitKcal: 0,
        })
        expect(Number.isInteger(result.balance)).toBe(true)
        expect(Number.isInteger(result.referenceKcal)).toBe(true)
        expect(Object.is(result.balance, -0)).toBe(false)
      }
    }
  })

  // Review of 2026-10-04: on the day the protocol changes, the day row still
  // carries the target of the OLD protocol (the RPCs keep the first target of
  // the day). `resolveDayBalanceInputs` says so; the day keeps the legacy number.
  describe('targetMatchesProtocol false: the stored target is of another rule → the legacy number', () => {
    it.each([
      // [protocol now, consumed, stored target, exercise, wrong number of before, legacy]
      ['recomposicao', 2500, 2799, 0, -799, -299],
      ['ganho_massa', 2000, 1564, 0, 510, 436],
      ['recomposicao', 1800, 2666, 0, -1366, -866],
      ['manutencao', 2000, 1564, 300, 436, 136],
    ] as const)('%s, %s / %s, treino %s: %s → %s, against the stored target, with exercise', (protocol, consumed, target, exercise, before, after) => {
      const day = {
        protocol,
        caloriesConsumed: consumed,
        caloriesTarget: target,
        exerciseCalories: exercise,
        gainSurplusMultiplier: 1.05,
        programmedDeficitKcal: protocol === 'recomposicao' ? 500 : 0,
      }

      expect(dayEnergyBalance(day).balance).toBe(before)
      expect(dayEnergyBalance({ ...day, targetMatchesProtocol: true }).balance).toBe(before)
      expect(dayEnergyBalance({ ...day, targetMatchesProtocol: false })).toEqual({
        balance: after,
        referenceKcal: target,
        includesExercise: true,
        basis: 'target',
      })
      expect(after).toBe(netBalance(consumed, target, exercise))
    })
  })

  it('the food line is another function and does not move: eatingBalance stays against the target', () => {
    // QA account: 2439 left before and after, in every protocol.
    expect(eatingBalance(541, 2980)).toBe(-2439)
    // Ganho de massa between the reference and the target: food is still
    // left (−80) while the day is a true surplus against expenditure (+62).
    expect(eatingBalance(2900, 2980)).toBe(-80)
  })
})
