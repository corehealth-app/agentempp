import { DEFAULT_CALC_CONFIG, fixedRecompProteinFactor } from '@mpp/core'
import { beforeEach, describe, expect, it } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from './calc-config-loader.js'

function makeClient(result: {
  data: Array<{ key: string; value: unknown }> | null
  error: { message: string } | null
}) {
  return {
    from: () => ({
      select: () => ({
        like: async () => result,
      }),
    }),
  }
}

describe('loadCalcConfig', () => {
  beforeEach(() => clearCalcConfigCache())

  it('não cacheia defaults quando a leitura da configuração falha', async () => {
    const client = makeClient({ data: null, error: { message: 'calc config unavailable' } })

    await expect(loadCalcConfig(client)).rejects.toThrow('calc config unavailable')
  })

  it('usa defaults quando a consulta funciona e não existem overrides', async () => {
    const client = makeClient({ data: [], error: null })

    await expect(loadCalcConfig(client)).resolves.toEqual(DEFAULT_CALC_CONFIG)
  })

  it('mescla override válido sobre a configuração canônica', async () => {
    const client = makeClient({
      data: [{ key: 'calc.kcal_block', value: 8000 }],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.kcal_block).toBe(8000)
  })

  // Rule M1 (docs/CALCULO-MPP.md §1b). The staging row, as read on 2026-10-04.
  const STAGING_PROTEIN_FACTORS = {
    muita: 1.6,
    pouca: 1.8,
    moderada: 1.8,
    training_low: 1.7,
    optimal_mid_training: 1.9,
    optimal_high_training: 2,
  }

  it('a linha calc.protein_factors em cascata não altera recomp_protein_g_per_kg (1.5 do código)', async () => {
    const client = makeClient({
      data: [{ key: 'calc.protein_factors', value: STAGING_PROTEIN_FACTORS }],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.protein_factors).toEqual(STAGING_PROTEIN_FACTORS)
    expect(result.recomp_protein_g_per_kg).toBe(1.5)
    // The default object is never mutated by an override.
    expect(DEFAULT_CALC_CONFIG.protein_factors.moderada).toBe(1.5)
    expect(DEFAULT_CALC_CONFIG.recomp_protein_g_per_kg).toBe(1.5)
  })

  it('sem nenhuma linha calc.*, recomp_protein_g_per_kg é 1.5', async () => {
    const client = makeClient({ data: [], error: null })

    expect((await loadCalcConfig(client)).recomp_protein_g_per_kg).toBe(1.5)
  })

  it('interruptor: a linha calc.recomp_protein_g_per_kg = null chega como null (sem deploy)', async () => {
    const client = makeClient({
      data: [
        { key: 'calc.protein_factors', value: STAGING_PROTEIN_FACTORS },
        { key: 'calc.recomp_protein_g_per_kg', value: null },
      ],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.recomp_protein_g_per_kg).toBeNull()
    expect(result.protein_factors).toEqual(STAGING_PROTEIN_FACTORS)
    expect(fixedRecompProteinFactor(result)).toBeNull()
  })

  // docs/CALCULO-MPP.md §1b: `global_config.value` is jsonb NOT NULL, so the
  // row the doc recommends writing is 0.
  it('interruptor recomendado: a linha calc.recomp_protein_g_per_kg = 0 chega como 0 e desliga a regra', async () => {
    const client = makeClient({
      data: [
        { key: 'calc.protein_factors', value: STAGING_PROTEIN_FACTORS },
        { key: 'calc.recomp_protein_g_per_kg', value: 0 },
      ],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.recomp_protein_g_per_kg).toBe(0)
    expect(fixedRecompProteinFactor(result)).toBeNull()
  })

  it.each([
    ['texto "1.5"', '1.5'],
    ['99', 99],
  ])('linha inválida (%s) chega como está e a regra usa o padrão do código (1.5), não a cascata', async (_label, value) => {
    const client = makeClient({
      data: [
        { key: 'calc.protein_factors', value: STAGING_PROTEIN_FACTORS },
        { key: 'calc.recomp_protein_g_per_kg', value },
      ],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.recomp_protein_g_per_kg).toBe(value)
    expect(fixedRecompProteinFactor(result)).toBe(1.5)
  })
})
