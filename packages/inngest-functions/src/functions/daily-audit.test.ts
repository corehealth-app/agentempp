import { describe, expect, it } from 'vitest'
import {
  countEducationalRotationAnomalies,
  countImpossibleMealDensities,
  countNutritionAnomalies,
  decideBlocoAutofix,
  SNAPSHOT_INTEGRITY_TOL_KCAL,
  snapshotIntegrityGap,
} from './daily-audit.js'

describe('countImpossibleMealDensities — redundância nutricional', () => {
  it('detecta total da refeição atribuído a uma porção pequena', () => {
    expect(
      countImpossibleMealDensities([
        { quantity_g: 15, kcal: 593 },
        { quantity_g: 120, kcal: 252 },
        { quantity_g: 100, kcal: 900 },
      ]),
    ).toBe(1)
  })

  it('trata números inválidos como anomalia em vez de ignorá-los', () => {
    expect(
      countImpossibleMealDensities([
        { quantity_g: 0, kcal: 100 },
        { quantity_g: null, kcal: 100 },
        { quantity_g: 100, kcal: null },
      ]),
    ).toBe(3)
  })
})

describe('countNutritionAnomalies — proveniência e macros', () => {
  it('separa densidade, massa de macros, referência ausente e drift canônico', () => {
    const result = countNutritionAnomalies([
      {
        quantity_g: 120,
        kcal: 252,
        protein_g: 4.2,
        carbs_g: 28.8,
        fat_g: 13.2,
        source: 'canonical_exact',
        food_db_id: 379,
        food_db: { kcal_per_100g: 210, protein_g: 3.5, carbs_g: 24, fat_g: 11 },
      },
      {
        quantity_g: 15,
        kcal: 593,
        protein_g: 1,
        carbs_g: 100,
        fat_g: 18,
        source: 'user_kcal',
        food_db_id: null,
        food_db: null,
      },
      {
        quantity_g: 100,
        kcal: 100,
        protein_g: 80,
        carbs_g: 50,
        fat_g: 10,
        source: 'llm_estimate',
        food_db_id: null,
        food_db: null,
      },
      {
        quantity_g: 100,
        kcal: 100,
        protein_g: 10,
        carbs_g: 10,
        fat_g: 2,
        source: 'canonical_exact',
        food_db_id: null,
        food_db: null,
      },
      {
        quantity_g: 100,
        kcal: 70,
        protein_g: 1,
        carbs_g: 15,
        fat_g: 0,
        source: 'canonical_exact',
        food_db_id: 500,
        food_db: { kcal_per_100g: 210, protein_g: 3.5, carbs_g: 24, fat_g: 11 },
      },
    ])

    expect(result).toEqual({
      impossibleDensity: 1,
      impossibleMacroMass: 2,
      canonicalMissingFoodDbId: 1,
      canonicalDrift: 1,
    })
  })
})

describe('countEducationalRotationAnomalies', () => {
  it('detecta fallback legado e repetição imediata após esgotamento com alternativas', () => {
    const result = countEducationalRotationAnomalies([
      {
        user_id: 'user-1',
        occurred_at: '2026-07-13T10:00:00.000Z',
        properties: {
          anchor: 'leite com whey',
          phrase_id: 'phrase-1',
          reason: 'selected',
          compatible_count: 8,
        },
      },
      {
        user_id: 'user-1',
        occurred_at: '2026-07-13T11:00:00.000Z',
        properties: {
          anchor: 'leite com whey',
          phrase_id: 'phrase-1',
          reason: 'selected_least_recent_after_exhaustion',
          compatible_count: 8,
        },
      },
      {
        user_id: 'user-2',
        occurred_at: '2026-07-13T12:00:00.000Z',
        properties: {
          anchor: 'whey protein',
          phrase_id: 'phrase-2',
          reason: 'selected_all_recent',
          compatible_count: 1,
        },
      },
    ])

    expect(result).toEqual({ immediateRepeatAfterExhaustion: 1, selectedAllRecent: 1 })
  })
})

describe('snapshotIntegrityGap — integridade snapshot vs meal_logs por consumed_at', () => {
  it('bate exato → gap 0 (dentro da tolerância)', () => {
    expect(snapshotIntegrityGap(1843, 1843)).toBe(0)
  })

  it('diferença pequena fica DENTRO da tolerância de 50 kcal (arredondamento)', () => {
    // calories_consumed é Math.round() no closer; logs cruus podem ter casas.
    const gap = snapshotIntegrityGap(1843, 1818)
    expect(gap).toBe(25)
    expect(gap).toBeLessThanOrEqual(SNAPSHOT_INTEGRITY_TOL_KCAL)
  })

  it('divergência real > 50 kcal é detectada', () => {
    const gap = snapshotIntegrityGap(2000, 1200)
    expect(gap).toBe(800)
    expect(gap).toBeGreaterThan(SNAPSHOT_INTEGRITY_TOL_KCAL)
  })

  it('FALSO-POSITIVO eliminado: soma correta por consumed_at bate com o snapshot', () => {
    // Cenário do bug: um meal_log de 600 kcal tinha snapshot_id linkado ao dia
    // ERRADO (backfill). A soma POR snapshot_id daria 1243 (faltando 600) e
    // acusaria divergência fantasma. A soma correta POR consumed_at (na data
    // local do snapshot) inclui os 600 e bate com calories_consumed=1843.
    const consumedNoSnapshot = 1843
    const somaPorConsumedAt = 1243 + 600 // log linkado errado, mas consumed_at certo
    expect(snapshotIntegrityGap(consumedNoSnapshot, somaPorConsumedAt)).toBe(0)
  })

  it('é simétrica (snapshot maior ou menor que os logs dá o mesmo |gap|)', () => {
    expect(snapshotIntegrityGap(2000, 1900)).toBe(snapshotIntegrityGap(1900, 2000))
  })

  it('trata valores não-numéricos como 0 (robustez)', () => {
    // @ts-expect-error — testando entrada inválida proposital
    expect(snapshotIntegrityGap(undefined, 100)).toBe(100)
    // @ts-expect-error — testando entrada inválida proposital
    expect(snapshotIntegrityGap(100, null)).toBe(100)
  })
})

describe('decideBlocoAutofix — auditoria read-only por padrão', () => {
  it('não aplica correção quando a flag está desligada, mesmo com divergência', () => {
    expect(decideBlocoAutofix(3, 8, false)).toEqual({
      canApply: false,
      circuitBroke: false,
      disabled: true,
    })
  })

  it('aplica quando a flag está ligada e a divergência cabe no limite', () => {
    expect(decideBlocoAutofix(3, 8, true)).toEqual({
      canApply: true,
      circuitBroke: false,
      disabled: false,
    })
  })

  it('bloqueia por circuit breaker quando passa do limite', () => {
    expect(decideBlocoAutofix(9, 8, true)).toEqual({
      canApply: false,
      circuitBroke: true,
      disabled: false,
    })
  })
})
