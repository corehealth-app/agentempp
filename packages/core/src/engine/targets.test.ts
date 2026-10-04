import { describe, expect, it } from 'vitest'
import { type CalcConfig, DEFAULT_CALC_CONFIG, RECOMP_PROTEIN_G_PER_KG } from '../calc-config.js'
import { calcProteinTargetG } from '../nutrition.js'
import { computeDailyTargets, type ProfileRow } from './targets.js'

const cfg = DEFAULT_CALC_CONFIG

const completo: ProfileRow = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 175,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  goal_type: 'BF',
  goal_value: 15,
  deficit_level: 500,
}

describe('computeDailyTargets', () => {
  it('perfil null → { null, null }', () => {
    expect(computeDailyTargets(null, cfg)).toEqual({ calories_target: null, protein_target: null })
  })

  it('sem activity_level → { null, null }', () => {
    expect(computeDailyTargets({ ...completo, activity_level: null }, cfg)).toEqual({
      calories_target: null,
      protein_target: null,
    })
  })

  it('recomposição → meta e proteína positivas e inteiras', () => {
    const t = computeDailyTargets(completo, cfg)
    expect(t.calories_target).toBeGreaterThan(0)
    expect(Number.isInteger(t.calories_target)).toBe(true)
    expect(t.protein_target).toBeGreaterThan(0)
  })

  it('switch de protocolo: ganho_massa > manutenção > 0 (mesmo perfil)', () => {
    const ganho = computeDailyTargets({ ...completo, current_protocol: 'ganho_massa' }, cfg)
      .calories_target!
    const manut = computeDailyTargets({ ...completo, current_protocol: 'manutencao' }, cfg)
      .calories_target!
    expect(ganho).toBeGreaterThan(manut)
    expect(manut).toBeGreaterThan(0)
  })

  it('recomp = BMR×1,2 − déficit (déficit maior → meta menor)', () => {
    const d400 = computeDailyTargets({ ...completo, deficit_level: 400 }, cfg).calories_target!
    const d600 = computeDailyTargets({ ...completo, deficit_level: 600 }, cfg).calories_target!
    expect(d400 - d600).toBe(200) // só o déficit muda
  })
})

// ── Protein target per protocol (docs/CALCULO-MPP.md §1b, rule M1) ──────────
//
// Recomposição: weight × 1.5, fixed. Stated by the client on 2026-04-15 and
// 2026-05-15; implemented on 2026-10-04 at Eduardo's request; confirmation
// pending. The other protocols keep the `protein_factors` cascade.

/** `calc.protein_factors` of staging as read on 2026-10-04 (migration 20260507181000). */
const stagingCfg: CalcConfig = {
  ...DEFAULT_CALC_CONFIG,
  protein_factors: {
    muita: 1.6,
    pouca: 1.8,
    moderada: 1.8,
    training_low: 1.7,
    optimal_mid_training: 1.9,
    optimal_high_training: 2.0,
  },
}

const HUNGERS = ['pouca', 'moderada', 'muita', null] as const
const TRAININGS = [null, 0, 1, 2, 3, 4, 5, 6, 7] as const

function protein(row: Partial<ProfileRow>, config: CalcConfig = stagingCfg): number | null {
  return computeDailyTargets({ ...completo, ...row }, config).protein_target
}

describe('computeDailyTargets — proteína da recomposição: 1,5 g/kg fixo', () => {
  it('100 kg → 150 g com QUALQUER fome e QUALQUER frequência de treino (cascata do staging no config)', () => {
    for (const hunger of HUNGERS) {
      for (const training of TRAININGS) {
        expect(
          protein({ weight_kg: 100, hunger_level: hunger, training_frequency: training }),
          `fome ${hunger}, treino ${training}`,
        ).toBe(150)
      }
    }
  })

  it.each([
    // [peso, meta, o que a cascata do staging dava para fome moderada]
    [99, 148.5, 178.2],
    [62.5, 93.8, 112.5],
    [100.9, 151.4, 181.6],
    [103.4, 155.1, 186.1],
    [80, 120, 144],
  ])('%s kg → %s g (a cascata dava %s)', (weight, expected, before) => {
    expect(protein({ weight_kg: weight, hunger_level: 'moderada', training_frequency: 5 })).toBe(
      expected,
    )
    // The previous rule, through the switch: the number this change replaces.
    expect(
      protein(
        { weight_kg: weight, hunger_level: 'moderada', training_frequency: 5 },
        { ...stagingCfg, recomp_protein_g_per_kg: null },
      ),
    ).toBe(before)
  })

  it('a linha calc.protein_factors não move a recomposição: default do código e cascata dão o mesmo', () => {
    for (const hunger of HUNGERS) {
      for (const training of TRAININGS) {
        const row = { weight_kg: 100, hunger_level: hunger, training_frequency: training }
        expect(protein(row, DEFAULT_CALC_CONFIG)).toBe(150)
        expect(protein(row, stagingCfg)).toBe(protein(row, DEFAULT_CALC_CONFIG))
      }
    }
  })

  it('a meta calórica da recomposição não muda com o fator de proteína', () => {
    const row = { ...completo, weight_kg: 100, deficit_level: 500 as const }
    const on = computeDailyTargets(row, stagingCfg)
    const off = computeDailyTargets(row, { ...stagingCfg, recomp_protein_g_per_kg: null })
    expect(on.protein_target).toBe(150)
    expect(off.protein_target).toBe(180)
    expect(on.calories_target).toBe(off.calories_target)
    expect(Object.keys(on).sort()).toEqual(['calories_target', 'protein_target'])
  })

  it('sem peso → null, nunca 0 g (relato C3-37 "Meta de proteína: 0 g")', () => {
    expect(computeDailyTargets({ ...completo, weight_kg: null }, stagingCfg)).toEqual({
      calories_target: null,
      protein_target: null,
    })
  })
})

describe('computeDailyTargets — interruptor recomp_protein_g_per_kg', () => {
  const cases = [
    // [fome, treino, fator da cascata do staging]
    ['moderada', 5, 180],
    ['pouca', 5, 200],
    ['pouca', 4, 190],
    ['muita', 5, 160],
    ['moderada', 2, 170],
  ] as const

  it.each([null, 0])('%s devolve a cascata à recomposição (comportamento anterior)', (off) => {
    for (const [hunger, training, expected] of cases) {
      expect(
        protein(
          { weight_kg: 100, hunger_level: hunger, training_frequency: training },
          { ...stagingCfg, recomp_protein_g_per_kg: off },
        ),
      ).toBe(expected)
    }
  })

  it('config sem a chave (objeto montado à mão) usa o padrão do código: 150', () => {
    const { recomp_protein_g_per_kg: _dropped, ...withoutKey } = stagingCfg
    expect(protein({ weight_kg: 100 }, withoutKey)).toBe(150)
  })

  it('o valor é lido do config: 1,6 → 160 (não há 1,5 escrito na conta)', () => {
    expect(protein({ weight_kg: 100 }, { ...stagingCfg, recomp_protein_g_per_kg: 1.6 })).toBe(160)
  })

  it('o padrão do código é 1,5', () => {
    expect(RECOMP_PROTEIN_G_PER_KG).toBe(1.5)
    expect(DEFAULT_CALC_CONFIG.recomp_protein_g_per_kg).toBe(1.5)
  })

  // Review of 2026-10-04: the database row replaced the constant with no
  // bounds. Profile of the review: recomposição, 100 kg, fome pouca, 5
  // treinos, staging cascade (which gives 200 g with the rule off).
  const reviewProfile = { weight_kg: 100, hunger_level: 'pouca', training_frequency: 5 } as const
  /** The config as the loader builds it: the row value copied whatever its type. */
  const withRowValue = (rowValue: unknown): CalcConfig => {
    const built: Record<string, unknown> = { ...stagingCfg }
    built.recomp_protein_g_per_kg = rowValue
    return built as unknown as CalcConfig
  }

  it.each([
    // [linha, meta antes desta correção, meta agora, valor da linha]
    ['99', 9900, 150, 99],
    ['1e9', 100000000000, 150, 1e9],
    ['texto "1.5"', 200, 150, '1.5'],
    ['-1', 200, 150, -1],
    ['3.01', 301, 150, 3.01],
    ['NaN', 200, 150, Number.NaN],
    ['true', 200, 150, true],
  ])('linha %s: fora da faixa ou de outro tipo → padrão do código (era %s g, agora %s g)', (_label, _before, expected, rowValue) => {
    expect(protein(reviewProfile, withRowValue(rowValue))).toBe(expected)
  })

  it.each([
    // [linha, meta, valor da linha]
    ['null', 200, null],
    ['0', 200, 0],
  ])('linha %s: interruptor explícito → cascata (%s g, como antes da regra)', (_label, expected, rowValue) => {
    expect(protein(reviewProfile, withRowValue(rowValue))).toBe(expected)
  })

  it.each([
    [1.2, 120],
    [1.5, 150],
    [3, 300],
  ])('linha %s (dentro de 0 < v ≤ 3) troca o fator → %s g', (rowValue, expected) => {
    expect(protein(reviewProfile, withRowValue(rowValue))).toBe(expected)
  })
})

describe('computeDailyTargets — ganho de massa, manutenção e protocolo não definido NÃO mudaram', () => {
  // Expected = weight × the staging cascade, the numbers before this change.
  it.each([
    ['ganho_massa', 80, 'moderada', 4, 144], // QA A, 2026-10-01
    ['ganho_massa', 80.5, 'moderada', 4, 144.9], // QA A, 2026-10-04
    ['ganho_massa', 103.4, 'moderada', 4, 186.1], // QA A snapshot before the 80 kg measurement
    ['ganho_massa', 100, 'pouca', 5, 200],
    ['ganho_massa', 100, 'pouca', 4, 190],
    ['ganho_massa', 100, 'muita', 5, 160],
    ['ganho_massa', 100, 'moderada', 2, 170],
    ['manutencao', 100, 'pouca', 5, 200],
    ['manutencao', 100, 'moderada', 4, 180],
    ['manutencao', 100, 'muita', 4, 160],
    ['manutencao', 100, 'moderada', 2, 170],
    [null, 100, 'moderada', 4, 180],
    [null, 100, 'pouca', 5, 200],
    [null, 100, 'muita', 5, 160],
    [null, 100, 'moderada', 2, 170],
    [null, 100, null, 4, 180], // no hunger yet → 'moderada'
  ] as const)('%s, %s kg, fome %s, treino %s → %s g', (protocol, weight, hunger, training, expected) => {
    const row = {
      current_protocol: protocol,
      weight_kg: weight,
      hunger_level: hunger,
      training_frequency: training,
    }
    expect(protein(row)).toBe(expected)
    // Same number as the function that computed it before this change.
    expect(protein(row)).toBe(
      Math.round(calcProteinTargetG(weight, hunger ?? 'moderada', stagingCfg, training) * 10) / 10,
    )
    // And the recomposição switch does not reach these protocols.
    expect(protein(row, { ...stagingCfg, recomp_protein_g_per_kg: null })).toBe(expected)
    expect(protein(row, { ...stagingCfg, recomp_protein_g_per_kg: 3 })).toBe(expected)
  })

  it('default do código (sem linha no banco): 80 kg → 120 g e 100 kg → 150 g nos três casos', () => {
    for (const protocol of ['ganho_massa', 'manutencao', null] as const) {
      expect(protein({ current_protocol: protocol, weight_kg: 80 }, DEFAULT_CALC_CONFIG)).toBe(120)
      expect(protein({ current_protocol: protocol, weight_kg: 100 }, DEFAULT_CALC_CONFIG)).toBe(150)
    }
  })
})
