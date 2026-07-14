import { describe, expect, it, vi } from 'vitest'
import {
  GeminiVision,
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

describe('GeminiVision — rótulo visível dentro de foto classificada como refeição', () => {
  it('faz OCR nutricional secundário e anexa o rótulo à análise da refeição', async () => {
    const vision = new GeminiVision({ apiKey: 'test-key' })
    const create = vi
      .fn()
      .mockResolvedValueOnce({
        choices: [
          {
            message: {
              content: JSON.stringify({
                items: [{ name: 'iogurte kumis', quantity_g_estimate: 150, confidence: 0.95 }],
                meal_context: 'Produto industrializado com rótulo visível',
                nutrition_label_visible: true,
              }),
            },
          },
        ],
        usage: { prompt_tokens: 10, completion_tokens: 10 },
      })
      .mockResolvedValueOnce({
        choices: [
          {
            message: {
              content: JSON.stringify({
                product_name: 'Yokey Kumis',
                serving_size_g: 240,
                per_serving: { kcal: 200, protein_g: 8, carbs_g: 23, fat_g: 8 },
                per_100g: { kcal: 83.33, protein_g: 3.33, carbs_g: 9.58, fat_g: 3.33 },
                confidence: 0.98,
              }),
            },
          },
        ],
        usage: { prompt_tokens: 10, completion_tokens: 10 },
      })
    ;(
      vision as unknown as { client: { chat: { completions: { create: typeof create } } } }
    ).client = {
      chat: { completions: { create } },
    }

    const result = await vision.analyzeImage('data:image/jpeg;base64,test', {
      hint: 'meal',
      userMessage: '150 ml dessert iogurte',
    })

    expect(result.type).toBe('meal')
    if (result.type !== 'meal') throw new Error('expected meal analysis')
    expect(result.nutrition_label_visible).toBe(true)
    expect(result.nutrition_label).toMatchObject({
      type: 'nutrition_label',
      product_name: 'Yokey Kumis',
      serving_size_g: 240,
      per_serving: { kcal: 200, protein_g: 8, carbs_g: 23, fat_g: 8 },
    })
    expect(create).toHaveBeenCalledTimes(2)
  })
})
