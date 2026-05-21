import { describe, it, expect } from 'vitest'
import {
  evaluateGainSafety,
  evaluateGainVelocity,
  computeMaintenanceAdjustment,
} from './protocols.js'

describe('evaluateGainSafety — tetos de ganho (BF/IMC)', () => {
  const base = { sex: 'masculino' as const, bfStart: 15, bfNow: 16, imcStart: 24, imcNow: 24.5 }

  it('dentro dos limites → continuar', () => {
    const r = evaluateGainSafety(base)
    expect(r.withinLimits).toBe(true)
    expect(r.action).toBe('continuar')
  })

  it('homem +3,1pp de BF → pausar_ganho', () => {
    const r = evaluateGainSafety({ ...base, bfNow: 18.1 })
    expect(r.bfCeilingExceeded).toBe(true)
    expect(r.action).toBe('pausar_ganho')
  })

  it('mulher: teto é +4pp (não pausa em +3)', () => {
    const r = evaluateGainSafety({ sex: 'feminino', bfStart: 25, bfNow: 28, imcStart: 23, imcNow: 23.5 })
    expect(r.bfCeilingExceeded).toBe(false)
    expect(r.action).toBe('continuar')
  })

  it('IMC +1,6 → revisar_fase (mais grave que BF)', () => {
    const r = evaluateGainSafety({ ...base, bfNow: 18.5, imcNow: 25.6 })
    expect(r.imcCeilingExceeded).toBe(true)
    expect(r.action).toBe('revisar_fase')
  })
})

describe('evaluateGainVelocity — +0,25% a +0,5%/semana', () => {
  it('80kg ganhando 0,3kg/semana → ideal', () => {
    // 80 → 80.6 em 14 dias = +0,75% em 2 semanas = 0,375%/semana
    const r = evaluateGainVelocity(80, 80.6, 14)
    expect(r.status).toBe('ideal')
    expect(r.minSafeKgWeek).toBe(0.2)
    expect(r.maxSafeKgWeek).toBe(0.4)
  })
  it('ganho rápido (>0,5%/sem) → rapido', () => {
    const r = evaluateGainVelocity(80, 81.5, 14) // ~0,94%/sem
    expect(r.status).toBe('rapido')
  })
  it('ganho lento (<0,25%/sem) → lento', () => {
    const r = evaluateGainVelocity(80, 80.1, 14)
    expect(r.status).toBe('lento')
  })
})

describe('computeMaintenanceAdjustment — −150/treino a menos, cap −300', () => {
  it('1 treino a menos → −150', () => {
    expect(computeMaintenanceAdjustment(5, 4).adjustmentKcal).toBe(-150)
  })
  it('3 treinos a menos → cap em −300', () => {
    expect(computeMaintenanceAdjustment(5, 2).adjustmentKcal).toBe(-300)
  })
  it('frequência mantida → 0', () => {
    expect(computeMaintenanceAdjustment(4, 4).adjustmentKcal).toBe(0)
  })
  it('treinou MAIS → sem ajuste negativo (0)', () => {
    expect(computeMaintenanceAdjustment(4, 5).adjustmentKcal).toBe(0)
  })
})
