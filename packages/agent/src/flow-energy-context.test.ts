import { eatingBalance, netBalance } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { flowEnergyContextLines, flowEnergyNumbers } from './flow-energy-context.js'

// iPhone, staging, 2026-10-04: day row at the turn of the report — target
// 2980, consumed 541, exercise 322, generated daily_balance -2761.
const REPORT = { caloriesTarget: 2980, caloriesConsumed: 541, exerciseCalories: 322 }

describe('flowEnergyNumbers', () => {
  it('the report: food balance -2439 (2439 left) and net balance -2761, from the core functions', () => {
    const n = flowEnergyNumbers(REPORT)

    expect(n).toEqual({ target: 2980, consumed: 541, exercise: 322, food: -2439, net: -2761 })
    expect(n.food).toBe(eatingBalance(541, 2980))
    expect(n.net).toBe(netBalance(541, 2980, 322))
    // The two never coincide when there is exercise: that gap is the defect.
    expect((n.food ?? 0) - (n.net ?? 0)).toBe(322)
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
    ).toEqual({ target: 2980, consumed: 0, exercise: 0, food: -2980, net: -2980 })
  })
})

describe('flowEnergyContextLines', () => {
  it('the report (ganho_massa): the exact four lines the Flow model reads', () => {
    expect(
      flowEnergyContextLines({ ...REPORT, protocol: 'ganho_massa', hasSnapshot: true }),
    ).toEqual([
      '- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2439 kcal',
      '- Exercício hoje: 322 kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida',
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -2761 kcal (negativo=déficit, positivo=superávit) — NÃO é o que resta para comer',
      '- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; o que o paciente pode comer é só o que está na linha "Para COMIDA". Se ele perguntar se pode comer a mais porque treinou, diga que o treino não muda isso e mostre meta, consumido e o que resta para comida; o gasto do treino fica à parte.',
    ])
  })

  it('keeps the legacy prefixes as substrings (shared rules in the database may cite them)', () => {
    const text = flowEnergyContextLines({
      ...REPORT,
      protocol: 'ganho_massa',
      hasSnapshot: true,
    }).join('\n')

    expect(text).toContain('Exercício hoje: 322 kcal queimadas')
    expect(text).toContain('Balanço calórico de hoje')
    // …but never the unlabeled legacy line.
    expect(text).not.toContain('- Balanço calórico de hoje: ')
  })

  it('over the target: the food line is an excess even when exercise makes the net negative', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 3200,
      exerciseCalories: 322,
      protocol: 'ganho_massa',
      hasSnapshot: true,
    })

    expect(lines[0]).toBe(
      '- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de 220 kcal acima da meta',
    )
    expect(lines[2]).toContain('COM exercício (consumido − meta − exercício): -102 kcal')
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
      protocol: 'recomposicao',
      hasSnapshot: true,
    })
    expect(recomp[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 436 kcal')
    expect(recomp[2]).toBe(
      '- Balanço calórico de hoje COM exercício (consumido − meta − exercício): -903 kcal (negativo=déficit, positivo=superávit) — o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer',
    )
    expect(recomp[3]?.endsWith('o gasto do treino fica à parte (acelera o bloco 7700).')).toBe(true)

    for (const protocol of ['ganho_massa', 'manutencao', null, undefined]) {
      const text = flowEnergyContextLines({ ...REPORT, protocol, hasSnapshot: true }).join('\n')
      expect(text).not.toContain('7700')
      expect(text).not.toContain('7.700')
    }
  })

  it('recomposição: the net balance is never presented as the block credit', () => {
    // Review 2026-10-04, round 2: the line said "é o número que o fechamento
    // do dia usa no bloco 7700". The credit is planned deficit − this number
    // (docs/CALCULO-MPP.md §3): 500 − (−903) = 1.403, not 903; and in the
    // morning (200 consumed → −2110) the closer may credit nothing at all.
    for (const caloriesConsumed of [1407, 200, 2000]) {
      const line = flowEnergyContextLines({
        caloriesTarget: 1843,
        caloriesConsumed,
        exerciseCalories: 467,
        protocol: 'recomposicao',
        hasSnapshot: true,
      })[2]

      expect(line).not.toContain('é o número que o fechamento')
      expect(line).not.toMatch(/usa no bloco/)
      expect(line).toContain(
        'só é calculado no fechamento do dia (déficit programado − este número)',
      )
      expect(line).toContain('até lá o valor é provisório')
      expect(line?.endsWith('NÃO é o que resta para comer')).toBe(true)
    }
  })

  it('no day row yet: only the food line and the rule — no exercise line, no net balance', () => {
    const lines = flowEnergyContextLines({
      caloriesTarget: 2980,
      caloriesConsumed: 0,
      exerciseCalories: 0,
      protocol: 'ganho_massa',
      hasSnapshot: false,
    })

    expect(lines).toHaveLength(2)
    expect(lines[0]).toBe('- Para COMIDA hoje (meta − consumido, SEM exercício): restam 2980 kcal')
    expect(lines[1]?.startsWith('- REGRA: exercício NÃO libera comida nem apaga excedente.')).toBe(
      true,
    )
    expect(lines.join('\n')).not.toContain('COM exercício')
    expect(lines.join('\n')).not.toContain('-2980')
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
    // and the day-balance claim is Roberto's open decision outside recomposição.
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao']) {
      const text = flowEnergyContextLines({ ...REPORT, protocol, hasSnapshot: true }).join('\n')
      expect(text).not.toContain('a resposta é não')
      expect(text).not.toContain('entra apenas no balanço do dia')
    }
  })
})
