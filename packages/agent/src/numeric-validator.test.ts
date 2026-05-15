import { describe, it, expect } from 'vitest'
import { validateNumericClaims } from './numeric-validator.js'

const ctx = { protein_target: 178.2, calories_target: 1843 }

describe('validateNumericClaims protein_target — false positive fix', () => {
  it('NÃO dispara em proteína per-refeição', () => {
    expect(validateNumericClaims('Total refeição: 447 kcal | 11g proteína', ctx)).toEqual([])
    expect(validateNumericClaims('Total refeição: 596 kcal | 67g proteína', ctx)).toEqual([])
    expect(validateNumericClaims('• Frango (200g): 380 kcal | 58g P', ctx)).toEqual([])
  })

  it('dispara quando LLM inventa meta diária errada', () => {
    const r1 = validateNumericClaims('tua meta de proteína é 220g por dia', ctx)
    expect(r1.length).toBeGreaterThan(0)
    expect(r1[0]?.field).toBe('protein_target')

    const r2 = validateNumericClaims('alvo de 250g de proteína', ctx)
    expect(r2.length).toBeGreaterThan(0)

    const r3 = validateNumericClaims('💪 Proteína: 125 / 250g (50%)', ctx)
    expect(r3.length).toBeGreaterThan(0)
  })

  it('NÃO dispara quando o card mostra meta correta', () => {
    expect(validateNumericClaims('💪 Proteína: 125 / 178g (70%)', ctx)).toEqual([])
    expect(validateNumericClaims('meta de 178g de proteína', ctx)).toEqual([])
  })
})

describe('validateNumericClaims deficit_block (bloco 7700) — bug do Roberto 2026-05-15', () => {
  const blocoCtx = { deficit_block: 2110 }

  it('dispara quando LLM zera o bloco erroneamente (caso Roberto)', () => {
    const r = validateNumericClaims(
      '📊 Bloco 7700: **0 / 7.700 kcal (0%)**',
      blocoCtx,
    )
    expect(r.length).toBeGreaterThan(0)
    expect(r[0]?.field).toBe('deficit_block')
    expect(r[0]?.claimed).toBe(0)
    expect(r[0]?.real).toBe(2110)
  })

  it('dispara em outras inconsistências (LLM inventa 5000)', () => {
    const r = validateNumericClaims('Bloco 7700: 5.000 / 7.700 kcal (65%)', blocoCtx)
    expect(r.length).toBeGreaterThan(0)
  })

  it('NÃO dispara quando o valor está correto', () => {
    expect(validateNumericClaims('📊 Bloco 7700: 2.110 / 7.700 kcal (27%)', blocoCtx)).toEqual([])
    expect(validateNumericClaims('Bloco 7700: 2110 / 7700 kcal', blocoCtx)).toEqual([])
    expect(
      validateNumericClaims('Bloco 7700 em andamento: **2110 kcal de 7700**', blocoCtx),
    ).toEqual([])
  })

  it('tolera diferença pequena (dentro de 10% ou ±30)', () => {
    expect(validateNumericClaims('Bloco 7700: 2100 / 7.700 kcal', blocoCtx)).toEqual([])
    expect(validateNumericClaims('Bloco 7700: 2150 / 7.700 kcal', blocoCtx)).toEqual([])
  })

  it('NÃO dispara quando deficit_block real é null no contexto', () => {
    const r = validateNumericClaims('Bloco 7700: 999 / 7.700 kcal', { deficit_block: null })
    expect(r).toEqual([])
  })

  it('NÃO confunde o "7.700" target com o valor atual', () => {
    // O regex deve casar só com o lado esquerdo da fração, não com 7.700 (target)
    const r = validateNumericClaims('Bloco 7700: 2.110 / 7.700 kcal (27%)', blocoCtx)
    expect(r).toEqual([]) // 2110 está correto
  })
})
