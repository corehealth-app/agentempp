import { describe, it, expect } from 'vitest'

// Smoke test do isComposite logic — verifica que "leite com whey" 
// pega match direto antes do auto-split.

import { calcMealMacros } from './meal-pipeline.js'
import type { ServiceClient } from '@mpp/db'

// Mock simples do supabase com search_food_trgm que retorna match perfeito
// pra "leite com whey" (id 413, 95 kcal/100g) e fraco pra "whey" sozinho.
const mockSupabase = {
  rpc: async (_fn: string, params: { search_term: string }) => {
    const term = params.search_term.toLowerCase()
    if (term === 'leite com whey') {
      return {
        data: [{ id: 413, name_pt: 'leite com whey', similarity: 1, kcal_per_100g: 95, protein_g: 10, carbs_g: 5, fat_g: 3, fiber_g: 0 }],
        error: null,
      }
    }
    if (term === 'leite') {
      return { data: [{ id: 412, name_pt: 'leite', similarity: 1, kcal_per_100g: 61, protein_g: 3.2, carbs_g: 4.7, fat_g: 3.3, fiber_g: 0 }], error: null }
    }
    if (term === 'whey') {
      return { data: [{ id: 260, name_pt: 'whey protein', similarity: 0.38, kcal_per_100g: 380, protein_g: 75, carbs_g: 8, fat_g: 4, fiber_g: 0 }], error: null }
    }
    return { data: [], error: null }
  },
  from: () => ({ select: () => ({ eq: () => ({ ilike: () => ({ gte: () => ({ neq: () => ({ neq: () => ({ order: () => ({ limit: () => ({ data: null, error: null }) }) }) }) }) }) }) }) }),
} as unknown as ServiceClient

describe('calcMealMacros — composite handling', () => {
  it('"leite com whey" usa match direto (id 413, 95kcal/100g) — não zera', async () => {
    const r = await calcMealMacros(mockSupabase, [{ food_name: 'leite com whey', quantity_g: 200 }], 'BR')
    expect(r.totals.kcal).toBeGreaterThan(0)
    expect(r.items[0]?.source).toBe('taco')
    expect(r.items[0]?.kcal).toBeCloseTo(190, 0) // 95 * 2
  })
})
