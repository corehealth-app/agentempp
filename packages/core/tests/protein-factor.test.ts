import { describe, expect, it } from 'vitest'
import {
  DEFAULT_CALC_CONFIG,
  RECOMP_PROTEIN_G_PER_KG,
  RECOMP_PROTEIN_G_PER_KG_SANITY_MAX,
} from '../src/calc-config.js'
import {
  calcProteinTargetG,
  computeMetrics,
  fixedRecompProteinFactor,
  resolveProteinFactor,
  resolveProteinFactorForProtocol,
} from '../src/nutrition.js'
import type { UserProfile } from '../src/types.js'

// Roberto pediu (2026-05-15): protein_factors agora é flat 1.5 g/kg.
// Os testes do CASCATA mantêm cobertura usando um config explícito com os
// valores antigos — a LÓGICA da cascata continua válida pra qualquer config.
// O teste do default novo valida o valor de produção flat.
const cascadeCfg = {
  ...DEFAULT_CALC_CONFIG,
  protein_factors: {
    muita: 1.6,
    moderada: 1.8,
    pouca: 1.8,
    training_low: 1.7,
    optimal_mid_training: 1.9,
    optimal_high_training: 2.0,
  },
}

describe('resolveProteinFactor — cascata (lógica preservada)', () => {
  it('Priority 1: muita fome → factors.muita (perfil difícil)', () => {
    expect(resolveProteinFactor('muita', 5, cascadeCfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', null, cascadeCfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', 0, cascadeCfg)).toBe(1.6)
  })

  it('Priority 2: training < 3 → factors.training_low (mesmo se moderada/pouca)', () => {
    expect(resolveProteinFactor('moderada', 2, cascadeCfg)).toBe(1.7)
    expect(resolveProteinFactor('pouca', 1, cascadeCfg)).toBe(1.7)
    expect(resolveProteinFactor('moderada', 0, cascadeCfg)).toBe(1.7)
  })

  it('Priority 3: pouca + training ≥ 5 → factors.optimal_high_training', () => {
    expect(resolveProteinFactor('pouca', 5, cascadeCfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 6, cascadeCfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 7, cascadeCfg)).toBe(2.0)
  })

  it('Priority 4: pouca + training = 4 → factors.optimal_mid_training', () => {
    expect(resolveProteinFactor('pouca', 4, cascadeCfg)).toBe(1.9)
  })

  it('Default: moderada → factors.moderada', () => {
    expect(resolveProteinFactor('moderada', 3, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', 5, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', null, cascadeCfg)).toBe(1.8)
  })

  it('Pouca sem training info → factors.moderada (não atinge optimal)', () => {
    expect(resolveProteinFactor('pouca', null, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('pouca', undefined, cascadeCfg)).toBe(1.8)
  })

  it('Pouca + training=3 → factors.moderada (não atingiu threshold de 4)', () => {
    expect(resolveProteinFactor('pouca', 3, cascadeCfg)).toBe(1.8)
  })
})

describe('protein_factors — default de produção (2026-05-15: flat 1.5 g/kg)', () => {
  it('todos os fatores são 1.5 — Roberto pediu pra simplificar', () => {
    const f = DEFAULT_CALC_CONFIG.protein_factors
    expect(f.muita).toBe(1.5)
    expect(f.moderada).toBe(1.5)
    expect(f.pouca).toBe(1.5)
    expect(f.training_low).toBe(1.5)
    expect(f.optimal_mid_training).toBe(1.5)
    expect(f.optimal_high_training).toBe(1.5)
  })

  it('resolveProteinFactor retorna 1.5 pra qualquer combinação no default', () => {
    const cfg = DEFAULT_CALC_CONFIG
    expect(resolveProteinFactor('muita', 5, cfg)).toBe(1.5)
    expect(resolveProteinFactor('moderada', 2, cfg)).toBe(1.5)
    expect(resolveProteinFactor('pouca', 6, cfg)).toBe(1.5)
    expect(resolveProteinFactor('moderada', null, cfg)).toBe(1.5)
  })
})

describe('calcProteinTargetG — peso × fator (com cascadeCfg pra preservar variação)', () => {
  it('Roberto (99kg, moderada, 5 treinos) = 178.2g', () => {
    expect(calcProteinTargetG(99, 'moderada', cascadeCfg, 5)).toBeCloseTo(178.2, 1)
  })

  it('Luan-style (81kg, pouca, 5 treinos) = 162g (factor 2.0)', () => {
    expect(calcProteinTargetG(81, 'pouca', cascadeCfg, 5)).toBeCloseTo(162, 0)
  })

  it('Paciente sedentário (70kg, muita fome, 1 treino) = 112g (factor 1.6)', () => {
    expect(calcProteinTargetG(70, 'muita', cascadeCfg, 1)).toBeCloseTo(112, 0)
  })

  it('Paciente sem trainingFrequency (90kg, pouca) = 162g default', () => {
    expect(calcProteinTargetG(90, 'pouca', cascadeCfg)).toBeCloseTo(162, 0)
  })

  it('Default novo flat 1.5 — 62.5kg × 1.5 = 93.75g (caso Erika)', () => {
    expect(calcProteinTargetG(62.5, 'moderada', DEFAULT_CALC_CONFIG, 6)).toBeCloseTo(93.75, 1)
  })
})

// Rule M1 (docs/CALCULO-MPP.md §1b): recomposição is fixed at 1.5 g/kg. Stated
// by the client on 2026-04-15 and 2026-05-15; implemented on 2026-10-04 at
// Eduardo's request; confirmation pending. The other protocols are unchanged.
describe('resolveProteinFactorForProtocol — recomposição fixa, o resto na cascata', () => {
  const HUNGERS = ['pouca', 'moderada', 'muita'] as const
  const TRAININGS = [null, undefined, 0, 2, 3, 4, 5, 7]

  it('recomposição → 1.5 pra qualquer fome e treino, com a cascata no config', () => {
    for (const hunger of HUNGERS) {
      for (const training of TRAININGS) {
        expect(resolveProteinFactorForProtocol('recomposicao', hunger, training, cascadeCfg)).toBe(
          1.5,
        )
      }
    }
  })

  it('ganho_massa, manutencao, null e undefined → exatamente resolveProteinFactor', () => {
    for (const protocol of ['ganho_massa', 'manutencao', null, undefined] as const) {
      for (const hunger of HUNGERS) {
        for (const training of TRAININGS) {
          for (const cfg of [cascadeCfg, DEFAULT_CALC_CONFIG]) {
            expect(resolveProteinFactorForProtocol(protocol, hunger, training, cfg)).toBe(
              resolveProteinFactor(hunger, training, cfg),
            )
          }
        }
      }
    }
  })

  it('interruptor: só null e 0 explícitos devolvem a cascata à recomposição', () => {
    for (const off of [null, 0, -0]) {
      const cfg = { ...cascadeCfg, recomp_protein_g_per_kg: off }
      expect(fixedRecompProteinFactor(cfg)).toBeNull()
      expect(resolveProteinFactorForProtocol('recomposicao', 'moderada', 5, cfg)).toBe(1.8)
      expect(resolveProteinFactorForProtocol('recomposicao', 'pouca', 5, cfg)).toBe(2.0)
      expect(resolveProteinFactorForProtocol('recomposicao', 'muita', 5, cfg)).toBe(1.6)
      expect(resolveProteinFactorForProtocol('recomposicao', 'moderada', 2, cfg)).toBe(1.7)
    }
  })

  // The loader copies the `global_config` row value as it is, whatever its
  // JSON type; `rowValue` builds the config the way the loader does.
  const withRowValue = (rowValue: unknown): typeof cascadeCfg => {
    const cfg: Record<string, unknown> = { ...cascadeCfg }
    cfg.recomp_protein_g_per_kg = rowValue
    return cfg as unknown as typeof cascadeCfg
  }

  it.each([
    // [valor da linha, fator usado]
    [0.1, 0.1],
    [1.2, 1.2],
    [1.5, 1.5],
    [1.6, 1.6],
    [3, 3],
  ])('linha numérica dentro da faixa (0 < v ≤ 3): %s → %s', (rowValue, factor) => {
    expect(fixedRecompProteinFactor(withRowValue(rowValue))).toBe(factor)
    expect(
      resolveProteinFactorForProtocol('recomposicao', 'pouca', 5, withRowValue(rowValue)),
    ).toBe(factor)
  })

  it.each([
    ['99 (revisão: virava 9900 g com 100 kg)', 99],
    ['1e9 (revisão: virava 100000000000 g)', 1e9],
    ['3.01, logo acima do limite', 3.01],
    ['negativo', -1],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
    ['texto "1.5" (revisão: desligava a regra em silêncio)', '1.5'],
    ['texto "0"', '0'],
    ['texto vazio', ''],
    ['booleano false', false],
    ['booleano true', true],
    ['objeto', { value: 1.5 }],
    ['lista', [1.5]],
    ['chave ausente (undefined)', undefined],
  ])('linha fora da faixa ou de outro tipo cai no padrão do código, nunca na cascata: %s → 1.5', (_label, rowValue) => {
    const cfg = withRowValue(rowValue)
    expect(fixedRecompProteinFactor(cfg)).toBe(1.5)
    // With the cascade in the config the answer would be 2.0 / 1.8 / 1.6 / 1.7.
    expect(resolveProteinFactorForProtocol('recomposicao', 'pouca', 5, cfg)).toBe(1.5)
    expect(resolveProteinFactorForProtocol('recomposicao', 'moderada', 5, cfg)).toBe(1.5)
    expect(resolveProteinFactorForProtocol('recomposicao', 'muita', 5, cfg)).toBe(1.5)
    expect(resolveProteinFactorForProtocol('recomposicao', 'moderada', 2, cfg)).toBe(1.5)
    // And the row never reaches the other protocols.
    expect(resolveProteinFactorForProtocol('ganho_massa', 'pouca', 5, cfg)).toBe(2.0)
    expect(resolveProteinFactorForProtocol(null, 'moderada', 5, cfg)).toBe(1.8)
  })

  it('o padrão do código e o limite da faixa são os declarados', () => {
    expect(RECOMP_PROTEIN_G_PER_KG).toBe(1.5)
    expect(RECOMP_PROTEIN_G_PER_KG_SANITY_MAX).toBe(3)
    expect(fixedRecompProteinFactor()).toBe(1.5)
    expect(fixedRecompProteinFactor(DEFAULT_CALC_CONFIG)).toBe(1.5)
  })

  it('sem config explícito usa o default (1.5 nos dois caminhos)', () => {
    expect(resolveProteinFactorForProtocol('recomposicao', 'pouca', 5)).toBe(1.5)
    expect(resolveProteinFactorForProtocol('ganho_massa', 'pouca', 5)).toBe(1.5)
  })
})

describe('computeMetrics.proteinFactor — mesmo fator da meta', () => {
  const base: UserProfile = {
    sex: 'masculino',
    birthDate: new Date('1982-01-01'),
    heightCm: 187,
    weightKg: 100,
    bodyFatPercent: null,
    activityLevel: 'moderado',
    trainingFrequency: 5,
    waterIntake: 'moderado',
    hungerLevel: 'pouca',
    currentProtocol: 'recomposicao',
    goalType: null,
    goalValue: null,
    deficitLevel: 600,
  }
  const today = new Date('2026-10-04T12:00:00.000Z')

  it('recomposição com a cascata no config → 1.5 (a cascata daria 2.0)', () => {
    expect(computeMetrics(base, today, cascadeCfg).proteinFactor).toBe(1.5)
  })

  it('recomposição sem fome informada → 1.5 (o fator fixo não depende da fome)', () => {
    expect(computeMetrics({ ...base, hungerLevel: null }, today, cascadeCfg).proteinFactor).toBe(
      1.5,
    )
  })

  it('ganho_massa, manutencao e protocolo null → a cascata, como antes', () => {
    for (const currentProtocol of ['ganho_massa', 'manutencao', null] as const) {
      expect(computeMetrics({ ...base, currentProtocol }, today, cascadeCfg).proteinFactor).toBe(
        2.0,
      )
      expect(
        computeMetrics({ ...base, currentProtocol, hungerLevel: null }, today, cascadeCfg)
          .proteinFactor,
      ).toBeNull()
    }
  })

  it('interruptor desligado: recomposição volta à cascata (2.0) e a null sem fome', () => {
    const off = { ...cascadeCfg, recomp_protein_g_per_kg: null }
    expect(computeMetrics(base, today, off).proteinFactor).toBe(2.0)
    expect(computeMetrics({ ...base, hungerLevel: null }, today, off).proteinFactor).toBeNull()
  })
})
