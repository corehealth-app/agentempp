import { describe, expect, it } from 'vitest'
import { classifyWeightGoal } from './weight-goal-classifier.js'

describe('classifyWeightGoal', () => {
  it('meta saudável + ritmo razoável → ideal', () => {
    const r = classifyWeightGoal({ currentWeightKg: 80, targetWeightKg: 75, heightCm: 175 })
    expect(r.classification).toBe('ideal')
    expect(r.imcAlvo).toBeCloseTo(24.5, 1)
    expect(r.direction).toBe('perder')
    expect(r.semanasParaMetaSeguro).not.toBeNull()
  })

  it('meta abaixo do saudável (IMC < 18.5) → unhealthy_low', () => {
    // Mulher 1.65m querendo 48kg → IMC 17.6
    const r = classifyWeightGoal({ currentWeightKg: 65, targetWeightKg: 48, heightCm: 165 })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.imcAlvo).toBeLessThan(18.5)
    expect(r.pesoMinimoSaudavelKg).toBeCloseTo(50.4, 1)
    expect(r.message).toContain('abaixo do saudável')
    expect(r.semanasParaMetaSeguro).toBeNull()
  })

  it('meta ainda em sobrepeso (IMC 25-29.9) → overweight_remaining', () => {
    // Homem 1.75m, atual 100kg, meta 80kg → IMC alvo 26.1
    const r = classifyWeightGoal({ currentWeightKg: 100, targetWeightKg: 80, heightCm: 175 })
    expect(r.classification).toBe('overweight_remaining')
    expect(r.imcAlvo).toBeCloseTo(26.1, 1)
  })

  it('meta ainda em obesidade (IMC ≥ 30) → obesity_remaining', () => {
    // Homem 1.75m, atual 120kg, meta 95kg → IMC alvo 31.0
    const r = classifyWeightGoal({ currentWeightKg: 120, targetWeightKg: 95, heightCm: 175 })
    expect(r.classification).toBe('obesity_remaining')
    expect(r.imcAlvo).toBeCloseTo(31, 1)
    expect(r.message).toContain('obesidade')
  })

  it('meta saudável mas perda > 15% → aggressive_pace', () => {
    // Homem 1.75m, 100kg → 70kg = -30% do peso atual
    const r = classifyWeightGoal({ currentWeightKg: 100, targetWeightKg: 70, heightCm: 175 })
    expect(r.classification).toBe('aggressive_pace')
    expect(r.deltaKg).toBe(30)
  })

  it('meta ≈ peso atual (±2%) → maintenance', () => {
    const r = classifyWeightGoal({ currentWeightKg: 75, targetWeightKg: 76, heightCm: 175 })
    expect(r.classification).toBe('maintenance')
    expect(r.direction).toBe('manter')
  })

  it('quer GANHAR peso em faixa saudável', () => {
    const r = classifyWeightGoal({ currentWeightKg: 60, targetWeightKg: 68, heightCm: 175 })
    expect(r.direction).toBe('ganhar')
    expect(r.classification).toBe('ideal')
  })
})
