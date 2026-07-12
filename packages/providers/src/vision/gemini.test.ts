import { describe, expect, it } from 'vitest'
import {
  normalizeMealOutputItems,
  normalizeNonNegativeVisionNumber,
  normalizeVisionConfidence,
} from './gemini.js'

describe('vision output normalization', () => {
  it('trata items com shape inválido como lista vazia em vez de quebrar', () => {
    expect(normalizeMealOutputItems({ name: 'frango' })).toEqual([])
    expect(normalizeMealOutputItems(null)).toEqual([])
  })

  it('remove nomes inválidos e força confirmação para quantidades impossíveis', () => {
    expect(
      normalizeMealOutputItems([
        { name: 42, quantity_g_estimate: 100, confidence: 0.9 },
        { name: 'frango grelhado', quantity_g_estimate: -120, confidence: 9 },
        { food_name: 'arroz', grams: '150', conf: '0.8' },
      ]),
    ).toEqual([
      {
        name: 'frango grelhado',
        quantity_g_estimate: 0,
        confidence: 0,
        notes: undefined,
      },
      {
        name: 'arroz',
        quantity_g_estimate: 150,
        confidence: 0.8,
        notes: undefined,
      },
    ])
  })

  it('limita confiança ao intervalo de 0 a 1', () => {
    expect(normalizeVisionConfidence(5)).toBe(1)
    expect(normalizeVisionConfidence(-1)).toBe(0)
    expect(normalizeVisionConfidence('0,75')).toBe(0.75)
    expect(normalizeVisionConfidence('incerto')).toBe(0)
  })

  it('rejeita números nutricionais negativos ou não finitos', () => {
    expect(normalizeNonNegativeVisionNumber('12,5')).toBe(12.5)
    expect(normalizeNonNegativeVisionNumber(0)).toBe(0)
    expect(normalizeNonNegativeVisionNumber(-3)).toBeNull()
    expect(normalizeNonNegativeVisionNumber('NaN')).toBeNull()
    expect(normalizeNonNegativeVisionNumber(null)).toBeNull()
  })
})
