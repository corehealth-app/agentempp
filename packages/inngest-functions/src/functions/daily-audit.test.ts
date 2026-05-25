import { describe, expect, it } from 'vitest'
import { SNAPSHOT_INTEGRITY_TOL_KCAL, snapshotIntegrityGap } from './daily-audit.js'

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
