import { describe, expect, it } from 'vitest'
import { type CalcConfig, DEFAULT_CALC_CONFIG } from '../src/calc-config.js'
import { calcIMC } from '../src/nutrition.js'
import {
  decideSignupEligibility,
  SIGNUP_IMC_ROUNDING_TOLERANCE,
  type SignupBlockReason,
  type SignupEligibility,
  type SignupEligibilityInput,
  type SignupObjectiveEligibility,
} from '../src/protocol-eligibility.js'

// Homem, 80 kg, 180 cm (IMC 24,69), sem gordura informada, musculação 3x.
const base: SignupEligibilityInput = {
  sex: 'masculino',
  heightCm: 180,
  weightKg: 80,
  bodyFatPercent: null,
  trainingFrequency: 3,
}
const woman: SignupEligibilityInput = { ...base, sex: 'feminino', heightCm: 165, weightKg: 62 }

describe('approved n9/n39 — a fat report never bypasses the gain BMI criterion', () => {
  it.each([
    [180, 84.24, 15, 'masculino'],
    [160, 64, 15, 'masculino'],
    [160, 64, 27, 'feminino'],
  ] as const)('keeps the choice but closes gain at %s cm / %s kg / %s%% (%s)', (heightCm, weightKg, bodyFatPercent, sex) => {
    const result = decide({ ...base, sex, heightCm, weightKg, bodyFatPercent })
    expect(result.outcome).toBe('choice')
    expect(result.objectives.ganho_massa).toEqual(blocked('composition'))
    expect(result.objectives.recomposicao).toEqual(AVAILABLE)
    expect(result.objectives.manutencao).toEqual(AVAILABLE)
  })

  it('requires both gain criteria and applies the configured BMI cut', () => {
    expect(brief({ ...base, weightKg: 84.24, bodyFatPercent: 15 })).toBe(
      'choice blocked composition',
    )
    expect(
      brief(
        { ...base, weightKg: 84.24, bodyFatPercent: 15 },
        { ...DEFAULT_CALC_CONFIG, imc_limit_recomp: 27 },
      ),
    ).toBe('choice available')
    expect(
      brief(
        { ...base, weightKg: 84.24, bodyFatPercent: 15 },
        { ...DEFAULT_CALC_CONFIG, imc_limit_recomp: 26 },
      ),
    ).toBe('choice blocked composition')
    expect(
      brief(
        { ...base, weightKg: 84.23, bodyFatPercent: 15 },
        { ...DEFAULT_CALC_CONFIG, imc_limit_recomp: 26 },
      ),
    ).toBe('choice available')
  })
})

const MAN_LIMITS = { bodyFatRecomp: 20, bodyFatGain: 19, imcRecomp: 25, trainingMin: 3 }
const WOMAN_LIMITS = { bodyFatRecomp: 28, bodyFatGain: 27, imcRecomp: 25, trainingMin: 3 }

const AVAILABLE: SignupObjectiveEligibility = { status: 'available', reasons: [] }
const NOT_OFFERED: SignupObjectiveEligibility = { status: 'not_offered', reasons: [] }
const blocked = (...reasons: SignupBlockReason[]): SignupObjectiveEligibility => ({
  status: 'blocked',
  reasons,
})

type Decided = Exclude<SignupEligibility, { outcome: 'invalid_input' }>

function decide(input: SignupEligibilityInput, config?: CalcConfig): Decided {
  const result = decideSignupEligibility(input, config)
  if (result.outcome === 'invalid_input') {
    throw new Error(`entrada inválida: ${result.invalidFields.join(', ')}`)
  }
  return result
}

/** Resultado e ganho de massa numa linha, para as varreduras de borda. */
function brief(input: SignupEligibilityInput, config?: CalcConfig): string {
  const result = decide(input, config)
  const gain = result.objectives.ganho_massa
  return [result.outcome, gain.status, ...gain.reasons].join(' ')
}

/** Peso que dá o IMC pedido naquela altura (a conta do peso também arredonda). */
function weightFor(imc: number, heightCm: number): number {
  const heightM = heightCm / 100
  return imc * (heightM * heightM)
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const inner of Object.values(value)) deepFreeze(inner)
    Object.freeze(value)
  }
  return value
}

describe('decideSignupEligibility — forma da saída', () => {
  it('colocado em recomposição pela gordura: o objeto inteiro', () => {
    expect(decideSignupEligibility({ ...base, bodyFatPercent: 25, trainingFrequency: 4 })).toEqual({
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis: 'BF',
      imc: calcIMC(80, 180),
      objectives: {
        recomposicao: AVAILABLE,
        ganho_massa: blocked('composition'),
        manutencao: NOT_OFFERED,
      },
      limits: MAN_LIMITS,
    })
  })

  it('colocado em recomposição pelo IMC, sem gordura informada: o objeto inteiro', () => {
    expect(decideSignupEligibility({ ...base, weightKg: 90, trainingFrequency: 4 })).toEqual({
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis: 'IMC',
      imc: calcIMC(90, 180),
      objectives: {
        recomposicao: AVAILABLE,
        ganho_massa: blocked('composition'),
        manutencao: NOT_OFFERED,
      },
      limits: MAN_LIMITS,
    })
  })

  it('pode escolher com os três objetivos disponíveis: o objeto inteiro, sem assignedProtocol', () => {
    const result = decideSignupEligibility({ ...woman, bodyFatPercent: 25 })
    expect(result).toEqual({
      outcome: 'choice',
      basis: 'BF',
      imc: calcIMC(62, 165),
      objectives: { recomposicao: AVAILABLE, ganho_massa: AVAILABLE, manutencao: AVAILABLE },
      limits: WOMAN_LIMITS,
    })
    expect('assignedProtocol' in result).toBe(false)
  })

  it('pode escolher com o ganho barrado: os motivos vêm na ordem composition, training', () => {
    expect(
      decideSignupEligibility({ ...base, bodyFatPercent: 19.5, trainingFrequency: 2 }),
    ).toEqual({
      outcome: 'choice',
      basis: 'BF',
      imc: calcIMC(80, 180),
      objectives: {
        recomposicao: AVAILABLE,
        ganho_massa: blocked('composition', 'training'),
        manutencao: AVAILABLE,
      },
      limits: MAN_LIMITS,
    })
  })

  it('entrada inválida: só outcome e invalidFields, nenhum objetivo', () => {
    expect(decideSignupEligibility({ ...base, heightCm: null })).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['heightCm'],
    })
  })

  it('quem é colocado em recomposição tem sempre composition; training entra junto abaixo do mínimo', () => {
    for (const input of [
      { ...base, bodyFatPercent: 20 },
      { ...base, weightKg: 81 },
      { ...woman, bodyFatPercent: 28 },
    ]) {
      expect(decide({ ...input, trainingFrequency: 5 }).objectives.ganho_massa).toEqual(
        blocked('composition'),
      )
      expect(decide({ ...input, trainingFrequency: 2 }).objectives.ganho_massa).toEqual(
        blocked('composition', 'training'),
      )
    }
  })

  it('varredura: recomposição sempre disponível; manutenção disponível só para quem escolhe; reasons só em blocked', () => {
    const bodyFats = [null, 8, 15, 19, 19.5, 20, 25, 27, 27.5, 28, 35]
    const weights = [45, 60, 77.76, 80, 81, 95]
    for (const sex of ['masculino', 'feminino'] as const) {
      for (const bodyFatPercent of bodyFats) {
        for (const weightKg of weights) {
          for (const trainingFrequency of [0, 2, 3, 7]) {
            const result = decide({ ...base, sex, bodyFatPercent, weightKg, trainingFrequency })
            const { recomposicao, ganho_massa, manutencao } = result.objectives
            expect(recomposicao).toEqual(AVAILABLE)
            expect(manutencao).toEqual(result.outcome === 'choice' ? AVAILABLE : NOT_OFFERED)
            expect(ganho_massa.status).not.toBe('not_offered')
            expect(ganho_massa.reasons.length > 0).toBe(ganho_massa.status === 'blocked')
            expect(result.basis).toBe(bodyFatPercent === null ? 'IMC' : 'BF')
            if (result.outcome === 'assigned') {
              expect(result.assignedProtocol).toBe('recomposicao')
              expect(ganho_massa.reasons[0]).toBe('composition')
            }
          }
        }
      }
    }
  })
})

describe('decideSignupEligibility — os cortes vêm da configuração', () => {
  it('limits repete os cortes de DEFAULT_CALC_CONFIG, por sexo', () => {
    expect(decide(base).limits).toEqual({
      bodyFatRecomp: DEFAULT_CALC_CONFIG.bf_limits.masculino.recomp,
      bodyFatGain: DEFAULT_CALC_CONFIG.bf_limits.masculino.gain,
      imcRecomp: DEFAULT_CALC_CONFIG.imc_limit_recomp,
      trainingMin: DEFAULT_CALC_CONFIG.training_min,
    })
    expect(decide(woman).limits).toEqual({
      bodyFatRecomp: DEFAULT_CALC_CONFIG.bf_limits.feminino.recomp,
      bodyFatGain: DEFAULT_CALC_CONFIG.bf_limits.feminino.gain,
      imcRecomp: DEFAULT_CALC_CONFIG.imc_limit_recomp,
      trainingMin: DEFAULT_CALC_CONFIG.training_min,
    })
    expect(decide(base).limits).toEqual(MAN_LIMITS)
    expect(decide(woman).limits).toEqual(WOMAN_LIMITS)
  })

  it('outra configuração muda cada corte (nenhum número fixo na função)', () => {
    const other: CalcConfig = {
      ...DEFAULT_CALC_CONFIG,
      bf_limits: { masculino: { recomp: 22, gain: 21 }, feminino: { recomp: 30, gain: 29 } },
      imc_limit_recomp: 26,
      training_min: 4,
    }
    expect(decide({ ...base, trainingFrequency: 4 }, other).limits).toEqual({
      bodyFatRecomp: 22,
      bodyFatGain: 21,
      imcRecomp: 26,
      trainingMin: 4,
    })

    // Gordura do homem: 21 passa, 21,5 fica na faixa entre os cortes, 22 entra direto.
    const man = { ...base, trainingFrequency: 4 }
    expect(brief({ ...man, bodyFatPercent: 21 }, other)).toBe('choice available')
    expect(brief({ ...man, bodyFatPercent: 21.5 }, other)).toBe('choice blocked composition')
    expect(brief({ ...man, bodyFatPercent: 22 }, other)).toBe('assigned blocked composition')
    expect(brief({ ...man, bodyFatPercent: 21 })).toBe('assigned blocked composition')

    // Gordura da mulher.
    const woman4 = { ...woman, trainingFrequency: 4 }
    expect(brief({ ...woman4, bodyFatPercent: 29 }, other)).toBe('choice available')
    expect(brief({ ...woman4, bodyFatPercent: 30 }, other)).toBe('assigned blocked composition')
    expect(brief({ ...woman4, bodyFatPercent: 29 })).toBe('assigned blocked composition')

    // IMC sem gordura: 25,5 escolhe com o corte em 26 e entra direto com o corte em 25.
    const imc255 = { ...man, weightKg: weightFor(25.5, 180) }
    expect(brief(imc255, other)).toBe('choice available')
    expect(brief(imc255)).toBe('assigned blocked composition')
    expect(brief({ ...man, weightKg: 84.24 }, other)).toBe('assigned blocked composition')

    // Musculação: 3 não basta com o mínimo em 4.
    expect(brief({ ...base, trainingFrequency: 3 }, other)).toBe('choice blocked training')
    expect(brief({ ...base, trainingFrequency: 3 })).toBe('choice available')
  })

  it('a tolerância acompanha o corte da configuração (84,24 kg / 180 cm dá 25,999999999999996)', () => {
    expect(calcIMC(84.24, 180)).toBe(25.999999999999996)
    const cut26: CalcConfig = { ...DEFAULT_CALC_CONFIG, imc_limit_recomp: 26 }
    expect(decide({ ...base, weightKg: 84.24 }, cut26).outcome).toBe('assigned')
  })

  it('linha que não guarda número (erro de digitação) vale o padrão do código: não abre a escolha nem lança', () => {
    const probes: SignupEligibilityInput[] = [
      { ...base, bodyFatPercent: 20 },
      { ...base, bodyFatPercent: 19.5 },
      { ...base, bodyFatPercent: 19 },
      { ...woman, bodyFatPercent: 28 },
      { ...woman, bodyFatPercent: 27.5 },
      { ...woman, bodyFatPercent: 27 },
      { ...base, weightKg: 81 },
      { ...base, weightKg: 64, heightCm: 160 },
      { ...base, weightKg: 79.38 },
      { ...base, trainingFrequency: 2 },
    ]
    const broken: Array<Record<string, unknown>> = [
      { imc_limit_recomp: '25' },
      { imc_limit_recomp: null },
      { imc_limit_recomp: undefined },
      { imc_limit_recomp: Number.NaN },
      { imc_limit_recomp: Number.POSITIVE_INFINITY },
      { imc_limit_recomp: { value: 25 } },
      { training_min: '3' },
      { training_min: null },
      { training_min: undefined },
      { bf_limits: null },
      { bf_limits: undefined },
      { bf_limits: {} },
      { bf_limits: 'x' },
      { bf_limits: 20 },
      { bf_limits: { masculino: null, feminino: null } },
      { bf_limits: { masculino: 'x', feminino: 28 } },
      { bf_limits: { masculino: { recomp: '20', gain: '19' }, feminino: { recomp: null } } },
      { bf_limits: { masculino: {}, feminino: {} } },
      // Texto DIFERENTE do padrão: também vale o padrão, o texto não vira número.
      { imc_limit_recomp: '26' },
      { imc_limit_recomp: '24' },
      { training_min: '4' },
      { training_min: '2' },
      {
        bf_limits: {
          masculino: { recomp: '22', gain: '21' },
          feminino: { recomp: '30', gain: '29' },
        },
      },
    ]
    for (const patch of broken) {
      const config = { ...DEFAULT_CALC_CONFIG, ...patch } as unknown as CalcConfig
      for (const probe of probes) {
        expect([patch, probe, decideSignupEligibility(probe, config)]).toEqual([
          patch,
          probe,
          decideSignupEligibility(probe),
        ])
      }
    }
  })

  it('linha com TEXTO diferente do padrão ("26", "4", "22"): vale o padrão do código — texto não é convertido em número (§10a)', () => {
    const withRow = (patch: Record<string, unknown>) =>
      ({ ...DEFAULT_CALC_CONFIG, ...patch }) as unknown as CalcConfig

    // calc.imc_limit_recomp = "26" (texto): o corte continua 25, e 81 kg / 180 cm
    // (IMC 25,0) entra direto. Com o NÚMERO 26 a mesma pessoa escolheria.
    const imcAsText = withRow({ imc_limit_recomp: '26' })
    expect(decide({ ...base, weightKg: 81 }, imcAsText).limits.imcRecomp).toBe(25)
    expect(decide({ ...base, weightKg: 81 }, imcAsText).outcome).toBe('assigned')
    expect(brief({ ...base, weightKg: 81 }, imcAsText)).toBe('assigned blocked composition')
    expect(brief({ ...base, weightKg: 81 }, withRow({ imc_limit_recomp: 26 }))).toBe(
      'choice available',
    )

    // calc.training_min = "4" (texto): o mínimo continua 3, e 3 treinos bastam.
    // Com o NÚMERO 4 os mesmos 3 treinos barrariam o ganho.
    const trainingAsText = withRow({ training_min: '4' })
    expect(decide(base, trainingAsText).limits.trainingMin).toBe(3)
    expect(decide(base, trainingAsText).objectives.ganho_massa).toEqual(AVAILABLE)
    expect(brief({ ...base, trainingFrequency: 3 }, trainingAsText)).toBe('choice available')
    expect(brief({ ...base, trainingFrequency: 3 }, withRow({ training_min: 4 }))).toBe(
      'choice blocked training',
    )

    // calc.bf_limits com texto: "22"/"21" e "30"/"29" não movem os cortes (20/19 e 28/27).
    const bodyFatAsText = withRow({
      bf_limits: {
        masculino: { recomp: '22', gain: '21' },
        feminino: { recomp: '30', gain: '29' },
      },
    })
    expect(decide(base, bodyFatAsText).limits).toEqual(MAN_LIMITS)
    expect(decide(woman, bodyFatAsText).limits).toEqual(WOMAN_LIMITS)
    expect(brief({ ...base, bodyFatPercent: 20 }, bodyFatAsText)).toBe(
      'assigned blocked composition',
    )
    expect(brief({ ...base, bodyFatPercent: 19.5 }, bodyFatAsText)).toBe(
      'choice blocked composition',
    )
    expect(brief({ ...woman, bodyFatPercent: 28 }, bodyFatAsText)).toBe(
      'assigned blocked composition',
    )
  })

  it('só o corte errado cai no padrão: os outros da mesma linha continuam valendo', () => {
    const config = {
      ...DEFAULT_CALC_CONFIG,
      bf_limits: { masculino: { recomp: 22, gain: 'vinte' }, feminino: { recomp: 30, gain: 29 } },
    } as unknown as CalcConfig
    expect(decide(base, config).limits).toEqual({ ...MAN_LIMITS, bodyFatRecomp: 22 })
  })
})

describe('decideSignupEligibility — tolerância numérica do IMC (correção de arredondamento)', () => {
  it('a tolerância é 0,000000001', () => {
    expect(SIGNUP_IMC_ROUNDING_TOLERANCE).toBe(1e-9)
  })

  it('64 kg / 160 cm: a conta dá 24,999999999999996 e a pessoa entra direto na recomposição', () => {
    const result = decide({ ...base, weightKg: 64, heightCm: 160 })
    expect(result.imc).toBe(24.999999999999996)
    expect(result.imc >= 25).toBe(false)
    expect(result.outcome).toBe('assigned')
    expect(result.basis).toBe('IMC')
  })

  it('IMC 25,0 exato em toda altura de 140 a 210 cm: sempre recomposição, nunca escolha', () => {
    const computed = new Set<number>()
    for (let heightCm = 140; heightCm <= 210; heightCm++) {
      const weightKg = weightFor(25, heightCm)
      computed.add(calcIMC(weightKg, heightCm))
      expect([heightCm, decide({ ...base, heightCm, weightKg }).outcome]).toEqual([
        heightCm,
        'assigned',
      ])
    }
    // A varredura passa por valores abaixo de 25 no computador: é o caso da tolerância.
    expect([...computed].some((imc) => imc < 25)).toBe(true)
  })

  it('IMC 24,99 em toda altura de 140 a 210 cm: sempre escolha', () => {
    for (let heightCm = 140; heightCm <= 210; heightCm++) {
      const weightKg = weightFor(24.99, heightCm)
      expect([heightCm, decide({ ...base, heightCm, weightKg }).outcome]).toEqual([
        heightCm,
        'choice',
      ])
    }
  })

  it('não é uma faixa clínica: 0,000001 abaixo de 25 escolhe; 0,0000000001 abaixo é lido como 25', () => {
    expect(decide({ ...base, heightCm: 200, weightKg: weightFor(25 - 1e-6, 200) }).outcome).toBe(
      'choice',
    )
    expect(decide({ ...base, heightCm: 200, weightKg: weightFor(25 - 1e-10, 200) }).outcome).toBe(
      'assigned',
    )
    expect(decide({ ...base, weightKg: 80.999 }).outcome).toBe('choice')
  })

  it('a gordura é comparada como foi digitada, sem tolerância', () => {
    expect(brief({ ...base, bodyFatPercent: 20 - 1e-10 })).toBe('choice blocked composition')
    expect(brief({ ...base, bodyFatPercent: 19 + 1e-10 })).toBe('choice blocked composition')
    expect(brief({ ...woman, bodyFatPercent: 28 - 1e-10 })).toBe('choice blocked composition')
  })
})

describe('decideSignupEligibility — musculação por semana', () => {
  it('0, 1 e 2 barram o ganho; 3, 4 e 7 não (sem gordura, IMC 24,69)', () => {
    expect(brief({ ...base, trainingFrequency: 0 })).toBe('choice blocked training')
    expect(brief({ ...base, trainingFrequency: 1 })).toBe('choice blocked training')
    expect(brief({ ...base, trainingFrequency: 2 })).toBe('choice blocked training')
    expect(brief({ ...base, trainingFrequency: 3 })).toBe('choice available')
    expect(brief({ ...base, trainingFrequency: 4 })).toBe('choice available')
    expect(brief({ ...base, trainingFrequency: 7 })).toBe('choice available')
  })

  it('o mesmo com gordura informada dentro do critério', () => {
    expect(brief({ ...base, bodyFatPercent: 15, trainingFrequency: 0 })).toBe(
      'choice blocked training',
    )
    expect(brief({ ...base, bodyFatPercent: 15, trainingFrequency: 2 })).toBe(
      'choice blocked training',
    )
    expect(brief({ ...base, bodyFatPercent: 15, trainingFrequency: 3 })).toBe('choice available')
    expect(brief({ ...base, bodyFatPercent: 15, trainingFrequency: 7 })).toBe('choice available')
  })

  it('musculação não muda quem escolhe nem quem entra direto: só o ganho de massa', () => {
    for (const input of [base, { ...base, weightKg: 90 }, { ...woman, bodyFatPercent: 30 }]) {
      const none = decide({ ...input, trainingFrequency: 0 })
      const daily = decide({ ...input, trainingFrequency: 7 })
      expect(none.outcome).toBe(daily.outcome)
      expect(none.objectives.recomposicao).toEqual(daily.objectives.recomposicao)
      expect(none.objectives.manutencao).toEqual(daily.objectives.manutencao)
    }
  })

  it('valor fracionário é comparado como está (o contrato do app só envia inteiros de 0 a 7)', () => {
    expect(brief({ ...base, trainingFrequency: 2.5 })).toBe('choice blocked training')
    expect(brief({ ...base, trainingFrequency: 9 })).toBe('choice available')
  })
})

describe('decideSignupEligibility — gordura em cada corte, por sexo (musculação 3x)', () => {
  it('homem: até 19 passa; acima de 19 e abaixo de 20 escolhe com o ganho barrado; de 20 em diante entra direto', () => {
    const man = (bodyFatPercent: number) => brief({ ...base, bodyFatPercent })
    expect(man(18.99)).toBe('choice available')
    expect(man(19)).toBe('choice available')
    expect(man(19.01)).toBe('choice blocked composition')
    expect(man(19.5)).toBe('choice blocked composition')
    expect(man(19.99)).toBe('choice blocked composition')
    expect(man(20)).toBe('assigned blocked composition')
    expect(man(20.01)).toBe('assigned blocked composition')
  })

  it('mulher: até 27 passa; acima de 27 e abaixo de 28 escolhe com o ganho barrado; de 28 em diante entra direto', () => {
    const fem = (bodyFatPercent: number) => brief({ ...woman, bodyFatPercent })
    expect(fem(26.99)).toBe('choice available')
    expect(fem(27)).toBe('choice available')
    expect(fem(27.01)).toBe('choice blocked composition')
    expect(fem(27.5)).toBe('choice blocked composition')
    expect(fem(27.99)).toBe('choice blocked composition')
    expect(fem(28)).toBe('assigned blocked composition')
    expect(fem(28.01)).toBe('assigned blocked composition')
  })

  it('o corte é o do sexo informado', () => {
    expect(brief({ ...woman, bodyFatPercent: 19.5 })).toBe('choice available')
    expect(brief({ ...woman, bodyFatPercent: 20 })).toBe('choice available')
    expect(brief({ ...base, bodyFatPercent: 27 })).toBe('assigned blocked composition')
    expect(brief({ ...base, bodyFatPercent: 27.5 })).toBe('assigned blocked composition')
  })
})

describe('decideSignupEligibility — gordura decide o corte; ganho também exige IMC abaixo', () => {
  it('homem 15% com IMC 26: escolhe, ganho fechado pela regra aprovada n9/n39', () => {
    const result = decide({ ...base, bodyFatPercent: 15, weightKg: 84.24 })
    expect([result.outcome, result.basis]).toEqual(['choice', 'BF'])
    expect(result.objectives.ganho_massa).toEqual(blocked('composition'))
  })

  it('homem 22% com IMC 23: recomposição sem perguntar', () => {
    const result = decide({ ...base, bodyFatPercent: 22, weightKg: 74.52 })
    expect([result.outcome, result.basis]).toEqual(['assigned', 'BF'])
  })

  it('gordura ausente, null ou undefined: decide o IMC, com o mesmo resultado', () => {
    const withoutKey: SignupEligibilityInput = {
      sex: base.sex,
      heightCm: base.heightCm,
      weightKg: base.weightKg,
      trainingFrequency: base.trainingFrequency,
    }
    const expected = decide({ ...base, bodyFatPercent: null })
    expect(expected.basis).toBe('IMC')
    expect(decide({ ...base, bodyFatPercent: undefined })).toEqual(expected)
    expect(decide(withoutKey)).toEqual(expected)
  })

  it('sem gordura, abaixo do corte de IMC o ganho depende só da musculação', () => {
    for (const imc of [16, 18.5, 22, 24, 24.5, 24.99]) {
      const weightKg = weightFor(imc, 180)
      expect([imc, brief({ ...base, weightKg })]).toEqual([imc, 'choice available'])
      expect([imc, brief({ ...base, weightKg, trainingFrequency: 2 })]).toEqual([
        imc,
        'choice blocked training',
      ])
    }
  })
})

describe('decideSignupEligibility — entrada inválida: nada é decidido', () => {
  const invalid = (patch: Record<string, unknown>) =>
    decideSignupEligibility({ ...base, ...patch } as unknown as SignupEligibilityInput)

  it('sexo ausente ou fora dos dois valores', () => {
    for (const sex of [null, undefined, '', 'M', 'male', 'MASCULINO', 1]) {
      expect([sex, invalid({ sex })]).toEqual([
        sex,
        { outcome: 'invalid_input', invalidFields: ['sex'] },
      ])
    }
  })

  it('altura ou peso que deixam o IMC indefinido: ausente, zero, negativo, NaN, infinito, texto', () => {
    const values = [
      null,
      undefined,
      0,
      -1,
      Number.NaN,
      Number.POSITIVE_INFINITY,
      Number.NEGATIVE_INFINITY,
      '180',
      {},
    ]
    for (const value of values) {
      expect([value, invalid({ heightCm: value })]).toEqual([
        value,
        { outcome: 'invalid_input', invalidFields: ['heightCm'] },
      ])
      expect([value, invalid({ weightKg: value })]).toEqual([
        value,
        { outcome: 'invalid_input', invalidFields: ['weightKg'] },
      ])
    }
  })

  it('altura e peso são exigidos mesmo quando a gordura decidiria', () => {
    expect(invalid({ bodyFatPercent: 25, heightCm: 0 })).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['heightCm'],
    })
    expect(invalid({ bodyFatPercent: 15, weightKg: null })).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['weightKg'],
    })
  })

  it('gordura informada que não é um número entre 0 e 100: inválida, não vira "sem gordura"', () => {
    for (const bodyFatPercent of [0, -5, 100, 101, Number.NaN, Number.POSITIVE_INFINITY, '20']) {
      expect([bodyFatPercent, invalid({ bodyFatPercent })]).toEqual([
        bodyFatPercent,
        { outcome: 'invalid_input', invalidFields: ['bodyFatPercent'] },
      ])
    }
    // Os extremos que ainda são número dentro do intervalo são comparados como estão.
    expect(brief({ ...base, bodyFatPercent: 0.1 })).toBe('choice available')
    expect(brief({ ...base, bodyFatPercent: 99.9 })).toBe('assigned blocked composition')
  })

  it('musculação ausente, negativa ou que não é número', () => {
    for (const trainingFrequency of [
      null,
      undefined,
      -1,
      Number.NaN,
      Number.POSITIVE_INFINITY,
      '3',
    ]) {
      expect([trainingFrequency, invalid({ trainingFrequency })]).toEqual([
        trainingFrequency,
        { outcome: 'invalid_input', invalidFields: ['trainingFrequency'] },
      ])
    }
  })

  it('vários campos errados: todos listados, na ordem da entrada', () => {
    expect(
      invalid({
        trainingFrequency: -1,
        bodyFatPercent: 0,
        weightKg: 0,
        heightCm: Number.NaN,
        sex: null,
      }),
    ).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['sex', 'heightCm', 'weightKg', 'bodyFatPercent', 'trainingFrequency'],
    })
  })

  it('dois números válidos cuja divisão não fecha (altura quase zero): altura e peso inválidos', () => {
    expect(invalid({ heightCm: 1e-200 })).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['heightCm', 'weightKg'],
    })
    expect(invalid({ weightKg: 1e-320, heightCm: 1e10 })).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['heightCm', 'weightKg'],
    })
  })

  it('valores possíveis de calcular são comparados como estão: plausibilidade é do contrato', () => {
    // Altura digitada em metros (1,8 no campo de centímetros): IMC acima de 246 mil.
    expect(decide({ ...base, heightCm: 1.8 }).outcome).toBe('assigned')
    // Peso muito baixo: nenhum documento do cliente dá o número; nada especial acontece.
    expect(brief({ ...base, weightKg: 45 })).toBe('choice available')
  })
})

describe('decideSignupEligibility — entrada ou configuração ausente (fora do tipo declarado): não lança', () => {
  const ALL_FIELDS = ['sex', 'heightCm', 'weightKg', 'bodyFatPercent', 'trainingFrequency']
  const call = (input: unknown, config?: unknown) =>
    decideSignupEligibility(input as SignupEligibilityInput, config as CalcConfig)

  it('entrada null ou undefined: invalid_input com os cinco campos, nada decidido', () => {
    for (const input of [null, undefined]) {
      expect(() => call(input)).not.toThrow()
      expect([input, call(input)]).toEqual([
        input,
        { outcome: 'invalid_input', invalidFields: ALL_FIELDS },
      ])
    }
    // Sem argumento nenhum.
    expect((decideSignupEligibility as () => SignupEligibility)()).toEqual({
      outcome: 'invalid_input',
      invalidFields: ALL_FIELDS,
    })
  })

  it('entrada que não é objeto (número, texto, booleano): o mesmo', () => {
    for (const input of [0, 80, Number.NaN, '', 'masculino', true, false]) {
      expect([input, call(input)]).toEqual([
        input,
        { outcome: 'invalid_input', invalidFields: ALL_FIELDS },
      ])
    }
  })

  it('objeto sem os campos continua lido campo a campo: gordura ausente é "não informada", não inválida', () => {
    for (const input of [{}, []]) {
      expect([input, call(input)]).toEqual([
        input,
        {
          outcome: 'invalid_input',
          invalidFields: ['sex', 'heightCm', 'weightKg', 'trainingFrequency'],
        },
      ])
    }
  })

  it('a lista dos cinco campos é nova a cada chamada', () => {
    const first = call(null)
    if (first.outcome !== 'invalid_input') throw new Error('esperava invalid_input')
    first.invalidFields.length = 0
    expect(call(null)).toEqual({ outcome: 'invalid_input', invalidFields: ALL_FIELDS })
  })

  it('configuração null: vale o padrão do código, com o mesmo resultado de não passar configuração', () => {
    const probes: SignupEligibilityInput[] = [
      base,
      woman,
      { ...base, bodyFatPercent: 20 },
      { ...base, bodyFatPercent: 19.5 },
      { ...base, bodyFatPercent: 19 },
      { ...woman, bodyFatPercent: 28 },
      { ...woman, bodyFatPercent: 27 },
      { ...base, weightKg: 81 },
      { ...base, weightKg: 64, heightCm: 160 },
      { ...base, trainingFrequency: 2 },
      { ...base, heightCm: null },
    ]
    for (const probe of probes) {
      expect(() => call(probe, null)).not.toThrow()
      expect([probe, call(probe, null)]).toEqual([probe, decideSignupEligibility(probe)])
      expect([probe, call(probe, undefined)]).toEqual([probe, decideSignupEligibility(probe)])
    }
    expect(decide(base, null as unknown as CalcConfig).limits).toEqual(MAN_LIMITS)
    expect(decide(woman, null as unknown as CalcConfig).limits).toEqual(WOMAN_LIMITS)
  })

  it('entrada null com configuração null: invalid_input com os cinco campos', () => {
    expect(call(null, null)).toEqual({ outcome: 'invalid_input', invalidFields: ALL_FIELDS })
    expect(call(undefined, null)).toEqual({ outcome: 'invalid_input', invalidFields: ALL_FIELDS })
  })
})

describe('decideSignupEligibility — função pura', () => {
  it('não altera a entrada nem a configuração', () => {
    const input = deepFreeze({ ...base, bodyFatPercent: 19.5, trainingFrequency: 2 })
    const config = deepFreeze(JSON.parse(JSON.stringify(DEFAULT_CALC_CONFIG)) as CalcConfig)
    expect(decideSignupEligibility(input, config)).toEqual(
      decideSignupEligibility({ ...base, bodyFatPercent: 19.5, trainingFrequency: 2 }),
    )
  })

  it('cada chamada devolve objetos novos', () => {
    const first = decide({ ...base, trainingFrequency: 2 })
    const second = decide({ ...base, trainingFrequency: 2 })
    expect(first).toEqual(second)
    expect(first).not.toBe(second)
    first.objectives.ganho_massa.reasons.push('composition')
    first.objectives.recomposicao.status = 'blocked'
    first.limits.imcRecomp = 99
    expect(decide({ ...base, trainingFrequency: 2 })).toEqual(second)
  })

  it('sono, alimentação e qualquer outro campo não entram na decisão', () => {
    const withRoutine = {
      ...base,
      bedTime: '01:00',
      wakeTime: '05:00',
      foodOrganization: 'nao',
      activityLevel: 'sedentario',
      hungerLevel: 'muita',
      birthDate: new Date('1950-01-01'),
    }
    expect(decideSignupEligibility(withRoutine)).toEqual(decideSignupEligibility(base))
  })
})
