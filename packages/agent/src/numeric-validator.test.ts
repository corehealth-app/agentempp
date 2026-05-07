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
