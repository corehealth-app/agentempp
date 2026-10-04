import { describe, expect, it } from 'vitest'
import {
  type CalcConfig,
  DEFAULT_CALC_CONFIG,
  IMC_GOAL_STEP_POINTS,
  IMC_GOAL_STEP_POINTS_SANITY_MAX,
} from '../src/calc-config.js'
import { computeMetrics } from '../src/nutrition.js'
import {
  calcBFGoal,
  calcIMCGoal,
  imcGoalStepPoints,
  resolveProtocol,
} from '../src/protocol-router.js'
import type { UserMetrics, UserProfile } from '../src/types.js'

const baseProfile: UserProfile = {
  sex: 'masculino',
  birthDate: new Date('1990-01-01'),
  heightCm: 180,
  weightKg: 90,
  bodyFatPercent: null,
  activityLevel: 'moderado',
  trainingFrequency: 5,
  waterIntake: 'moderado',
  hungerLevel: 'moderada',
  currentProtocol: null,
  goalType: null,
  goalValue: null,
  deficitLevel: null,
  // Critérios novos pra Ganho de Massa (sono ≥6h30 + alimentação estruturada).
  bedTime: '23:00',
  wakeTime: '07:00',
  foodOrganization: 'sim',
}

const baseMetrics: UserMetrics = {
  age: 36,
  bmr: 2000,
  activityFactor: 1.55,
  lbm: 72,
  imc: 22,
  proteinFactor: 1.8,
}

describe('calcBFGoal — escada progressiva', () => {
  it('BF > 30 → BF - 10 (arredondado)', () => {
    expect(calcBFGoal(35)).toBe(25)
    expect(calcBFGoal(45.5)).toBe(36)
  })

  it('escada: 30 → 20 → 18 → 15 → 10', () => {
    expect(calcBFGoal(28)).toBe(20)
    expect(calcBFGoal(22)).toBe(20)
    expect(calcBFGoal(20)).toBe(18)
    expect(calcBFGoal(18.5)).toBe(18)
    expect(calcBFGoal(17)).toBe(15)
    expect(calcBFGoal(14)).toBe(10)
  })
})

// R3 (docs/CALCULO-MPP.md §8a). Stated by the client on 2026-01-26 (typed) and
// in his manual 9.4.3.1; on 2026-02-07 he typed "10 pontos" once. Implemented
// on 2026-10-04 at Eduardo's request; the client's confirmation is pending.

/** `global_config` as read on staging on 2026-10-04: `calc.imc_goal_steps` and
 * `calc.imc_limit_recomp` rows, and NO row for `calc.imc_goal_step_points`, so
 * the loader keeps the default of the new key. */
const STAGING_SHAPE: CalcConfig = {
  ...DEFAULT_CALC_CONFIG,
  imc_goal_steps: [30, 25, 23, 22, 21],
  imc_limit_recomp: 25,
}

/** The revert switch: the row `calc.imc_goal_step_points` = null. */
const PREVIOUS_LADDER: CalcConfig = { ...STAGING_SHAPE, imc_goal_step_points: null }

function chain(start: number, config: CalcConfig): number[] {
  const out = [start]
  let current = start
  for (let i = 0; i < 12; i++) {
    const next = calcIMCGoal(current, config)
    if (next >= current) break
    out.push(next)
    current = next
  }
  return out
}

describe('calcIMCGoal — 5 pontos por vez até 25, depois 23→22→21', () => {
  it('abaixo de 31 nada muda (asserções da escada anterior)', () => {
    expect(calcIMCGoal(30)).toBe(25)
    expect(calcIMCGoal(28)).toBe(25)
    expect(calcIMCGoal(24)).toBe(23)
    expect(calcIMCGoal(23.5)).toBe(22)
    expect(calcIMCGoal(22)).toBe(21)
  })

  it('IMC já saudável retorna meta mínima', () => {
    expect(calcIMCGoal(20)).toBe(21)
  })

  it('o padrão do código é passo 5 com os degraus que estão no banco', () => {
    expect(DEFAULT_CALC_CONFIG.imc_goal_step_points).toBe(5)
    expect(DEFAULT_CALC_CONFIG.imc_goal_steps).toEqual([30, 25, 23, 22, 21])
  })

  it.each([
    // [IMC, meta nova, meta da escada anterior]
    [32.7, 27.7, 30], // C3-03 / C2-49: o print dizia "reduzir para 30.0"
    [31, 26, 30], // manual 9.4.3.1
    [34, 29, 30], // manual 9.4.3.1
    [35, 30, 30], // manual 9.4.3.1
    [36, 31, 30],
    [45, 40, 30],
    [30.1, 25, 25], // C2-50: o print dizia "Meta de IMC: 30.0 (redução de ~0.1 ponto)"
    [27, 25, 25],
    [25.4, 23, 23],
    [25.0, 23, 23],
  ])('IMC %s → meta %s (antes %s), com a config no formato do banco', (imc, goal, before) => {
    expect(calcIMCGoal(imc, STAGING_SHAPE)).toBe(goal)
    expect(calcIMCGoal(imc)).toBe(goal)
    expect(calcIMCGoal(imc, PREVIOUS_LADDER)).toBe(before)
  })

  it('cadeias: 32.7 → 27.7 → 25 → 23 → 22 → 21 e 45 → 40 → 35 → 30 → 25 → …', () => {
    expect(chain(32.7, STAGING_SHAPE)).toEqual([32.7, 27.7, 25, 23, 22, 21])
    expect(chain(45, STAGING_SHAPE)).toEqual([45, 40, 35, 30, 25, 23, 22, 21])
    expect(chain(32.7, PREVIOUS_LADDER)).toEqual([32.7, 30, 25, 23, 22, 21])
  })

  it('varredura: de 15.0 a 30.9 (0,1 em 0,1) a meta é a mesma de antes; de 31.0 em diante é IMC − 5', () => {
    for (let i = 150; i <= 309; i++) {
      const imc = i / 10
      expect([imc, calcIMCGoal(imc, STAGING_SHAPE)]).toEqual([
        imc,
        calcIMCGoal(imc, PREVIOUS_LADDER),
      ])
    }
    for (let i = 310; i <= 600; i++) {
      const imc = i / 10
      expect([imc, calcIMCGoal(imc, STAGING_SHAPE)]).toEqual([imc, Math.round((imc - 5) * 10) / 10])
      expect([imc, calcIMCGoal(imc, PREVIOUS_LADDER)]).toEqual([imc, 30])
    }
  })

  it('IMC sem arredondar: a meta acompanha o IMC de uma casa que o paciente vê', () => {
    // 100 kg / 1,75 m = 32.653… (mostrado 32.7) → 27.7
    expect(calcIMCGoal(100 / 1.75 ** 2, STAGING_SHAPE)).toBe(27.7)
    // 30.96 é mostrado como 31.0 → 26, como o exemplo 31 → 26 do manual.
    // É a única faixa abaixo de 31 que muda (30.95 a 30.99; antes 25).
    expect(calcIMCGoal(30.96, STAGING_SHAPE)).toBe(26)
    expect(calcIMCGoal(30.96, PREVIOUS_LADDER)).toBe(25)
    // 30.94 é mostrado como 30.9 → 25, como antes.
    expect(calcIMCGoal(30.94, STAGING_SHAPE)).toBe(25)
    // 25.96 é mostrado como 26.0, mas está a menos de 1 ponto de 25 → 23, como antes.
    expect(calcIMCGoal(25.96, STAGING_SHAPE)).toBe(23)
    expect(calcIMCGoal(25.96, PREVIOUS_LADDER)).toBe(23)
  })

  it('interruptor: null ou 0 devolvem a escada anterior inteira', () => {
    for (const off of [null, 0]) {
      const config: CalcConfig = { ...STAGING_SHAPE, imc_goal_step_points: off }
      expect(calcIMCGoal(32.7, config)).toBe(30)
      expect(calcIMCGoal(45, config)).toBe(30)
      expect(calcIMCGoal(30.1, config)).toBe(25)
      expect(calcIMCGoal(25.4, config)).toBe(23)
      expect(calcIMCGoal(20, config)).toBe(21)
    }
  })

  // Second review of 2026-10-04 (LOW): through the real loader, the staging
  // rows plus { key: 'calc.imc_goal_step_points', value: '5' } gave the
  // previous ladder (32.7 → 30) from 10.00 to 65.00, with no error and no log.
  // The loader copies the row value as it is, so the config is built here the
  // same way: the value is not a `number | null`.
  const withRowValue = (value: unknown): CalcConfig =>
    ({ ...STAGING_SHAPE, imc_goal_step_points: value }) as CalcConfig

  it.each([
    ['o texto "5" (o caso do revisor)', '5'],
    ['o texto "5,0"', '5,0'],
    ['texto que não é número', 'abc'],
    ['texto vazio', ''],
    ['negativo', -5],
    ['acima do limite de digitação (20)', 20.5],
    ['50', 50],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
    ['true', true],
    ['false', false],
    ['objeto', { points: 5 }],
    ['lista', [5]],
    ['chave ausente', undefined],
  ])('valor inválido na linha — %s: vale o padrão do código (5), a regra NÃO desliga', (_label, value) => {
    const config = withRowValue(value)
    expect(imcGoalStepPoints(config)).toBe(5)
    expect(calcIMCGoal(32.7, config)).toBe(27.7)
    expect(calcIMCGoal(31, config)).toBe(26)
    expect(calcIMCGoal(45, config)).toBe(40)
    expect(calcIMCGoal(30.1, config)).toBe(25)
    expect(calcIMCGoal(25.4, config)).toBe(23)
    for (let i = 1000; i <= 6500; i += 7) {
      const imc = i / 100
      expect([imc, calcIMCGoal(imc, config)]).toEqual([imc, calcIMCGoal(imc, STAGING_SHAPE)])
    }
  })

  it('só null e 0 explícitos desligam a regra', () => {
    expect(imcGoalStepPoints(withRowValue(null))).toBeNull()
    expect(imcGoalStepPoints(withRowValue(0))).toBeNull()
    // -0 === 0: also off. The text "0" is not the switch: it is the default.
    expect(imcGoalStepPoints(withRowValue(-0))).toBeNull()
    expect(imcGoalStepPoints(withRowValue('0'))).toBe(5)
    expect(imcGoalStepPoints(withRowValue('null'))).toBe(5)
    expect(imcGoalStepPoints()).toBe(5)
    expect(IMC_GOAL_STEP_POINTS).toBe(5)
  })

  it.each([
    [0.5, 32.2],
    [1, 31.7],
    [5, 27.7],
    [10, 25],
    [20, 25],
  ])('um número em (0, 20] é o passo: passo %s → IMC 32,7 vira %s', (step, goal) => {
    const config = withRowValue(step)
    expect(imcGoalStepPoints(config)).toBe(step)
    expect(calcIMCGoal(32.7, config)).toBe(goal)
    expect(IMC_GOAL_STEP_POINTS_SANITY_MAX).toBe(20)
  })

  it('o conflito de 07/02/2026 ("10 pontos") é uma troca de valor, não de código', () => {
    const ten: CalcConfig = { ...STAGING_SHAPE, imc_goal_step_points: 10 }
    expect(calcIMCGoal(32.7, ten)).toBe(25)
    expect(calcIMCGoal(45, ten)).toBe(35)
    expect(calcIMCGoal(27, ten)).toBe(25)
    expect(calcIMCGoal(25.4, ten)).toBe(23)
  })

  it('os degraus de 25 para cima do array do banco não são usados pela regra nova', () => {
    const older: CalcConfig = { ...STAGING_SHAPE, imc_goal_steps: [25, 23, 22, 21] }
    for (const imc of [45, 32.7, 31, 30.1, 27, 25.4, 25, 24, 22, 20]) {
      expect([imc, calcIMCGoal(imc, older)]).toEqual([imc, calcIMCGoal(imc, STAGING_SHAPE)])
    }
  })
})

describe('resolveProtocol — com BF', () => {
  it('homem com BF >= 20 → recomp obrigatória', () => {
    const decision = resolveProtocol({ ...baseProfile, bodyFatPercent: 25 }, baseMetrics)
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.length).toBeGreaterThan(0)
    expect(decision.goalType).toBe('BF')
    expect(decision.goalValue).toBe(20)
  })

  it('mulher com BF >= 28 → recomp obrigatória', () => {
    const decision = resolveProtocol(
      { ...baseProfile, sex: 'feminino', bodyFatPercent: 30 },
      baseMetrics,
    )
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
  })

  it('homem com BF <= 19 + treino >= 3 → pode escolher', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: 17, trainingFrequency: 5 },
      baseMetrics,
    )
    expect(decision.canChoose).toBe(true)
    expect(decision.blockers).toEqual([])
  })

  it('homem com BF baixo mas treino insuficiente → recomp com blockers', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: 15, trainingFrequency: 1 },
      baseMetrics,
    )
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.some((b) => b.includes('musculação'))).toBe(true)
  })
})

describe('resolveProtocol — sem BF (fallback IMC)', () => {
  it('IMC >= 25 → recomp obrigatória', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null },
      { ...baseMetrics, imc: 27 },
    )
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.goalType).toBe('IMC')
  })

  // C3-03 (2026-02-07) and C2-49 (2026-01-25): test profile without photos,
  // BMI 32.7. The prints carry no weight or height, so the BMI of the print
  // goes straight into the function.
  it('IMC 32.7 sem gordura no perfil → meta IMC 27.7, nunca 30 (recomp obrigatória)', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null },
      { ...baseMetrics, imc: 32.7 },
      STAGING_SHAPE,
    )
    expect(decision).toEqual({
      protocol: 'recomposicao',
      canChoose: false,
      blockers: ['IMC acima do limite saudável para ganho de massa'],
      goalType: 'IMC',
      goalValue: 27.7,
    })
    const before = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null },
      { ...baseMetrics, imc: 32.7 },
      PREVIOUS_LADDER,
    )
    expect(before).toEqual({ ...decision, goalValue: 30 })
  })

  it('IMC < 25 + treino OK → pode escolher', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null, trainingFrequency: 4 },
      { ...baseMetrics, imc: 22 },
    )
    expect(decision.canChoose).toBe(true)
    expect(decision.goalType).toBe('IMC')
  })

  it('IMC < 25 mas treino insuficiente → recomp', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null, trainingFrequency: 0 },
      { ...baseMetrics, imc: 22 },
    )
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.length).toBeGreaterThan(0)
  })
})

describe('resolveProtocol — integração com computeMetrics', () => {
  it('fluxo end-to-end: perfil real → métrica real → decisão', () => {
    const profile: UserProfile = {
      sex: 'masculino',
      birthDate: new Date('1985-06-15'),
      heightCm: 175,
      weightKg: 95,
      bodyFatPercent: 28,
      activityLevel: 'sedentario',
      trainingFrequency: 1,
      waterIntake: 'pouco',
      hungerLevel: 'muita',
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
    }
    const metrics = computeMetrics(profile, new Date('2026-05-01'))
    const decision = resolveProtocol(profile, metrics)

    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.goalType).toBe('BF')
    expect(decision.goalValue).toBe(20)
  })
})
