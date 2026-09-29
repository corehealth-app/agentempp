/**
 * Golden test — Flow diet proposal refused by meal_type labels, staging
 * device gate 2026-09-29 08:49 local (QA account A, backend d00d757).
 *
 * Exact scenario: after the tool-schema fix the proposal reached the diet
 * generator, which answered with display labels and was refused:
 *   daily_meals.0.meal_type received 'Café da manhã'
 *   daily_meals.1.meal_type received 'Almoço'
 *   daily_meals.2.meal_type received 'Lanche da tarde'
 *   daily_meals.3.meal_type received (cut in the event; the fourth meal)
 * The prompt listed the key without its allowed codes. The Flow request now
 * states the codes, and unambiguous Portuguese labels are read as their code.
 * A bare "Lanche" (morning or afternoon?) is not guessed.
 */
import type { OpenRouterLLM } from '@mpp/providers'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { generateDietPlan, normalizeGeneratedDiet, type DietGeneratorInput } from '../diet-generator.js'

const meal = (meal_type: string) => ({
  meal_type,
  items: [{ food_name: 'arroz', quantity_g: 100, kcal: 128, protein_g: 2.5, carbs_g: 28, fat_g: 0.2 }],
  total_kcal: 128,
  total_protein_g: 2.5,
})
const types = (raw: unknown) =>
  (normalizeGeneratedDiet(raw) as { daily_meals: Array<{ meal_type: string }> }).daily_meals.map((m) => m.meal_type)

describe('audit 2026-09-29 — diet meal_type labels', () => {
  it('the device labels become their codes', () => {
    const raw = { daily_meals: ['Café da manhã', 'Almoço', 'Lanche da tarde', 'Jantar'].map(meal), shopping_list: [] }
    expect(types(raw)).toEqual(['cafe', 'almoco', 'lanche_tarde', 'jantar'])
  })

  it('accent, case and spacing variants are read; codes stay codes', () => {
    const raw = {
      daily_meals: ['cafe da manha', 'LANCHE DA MANHÃ', 'almoço ', 'lanche  da tarde', 'Ceia', 'cafe', 'lanche_manha'].map(meal),
      shopping_list: [],
    }
    expect(types(raw)).toEqual(['cafe', 'lanche_manha', 'almoco', 'lanche_tarde', 'ceia', 'cafe', 'lanche_manha'])
  })

  it('an ambiguous or unknown label is left as is (still refused by validation)', () => {
    const raw = { daily_meals: ['Lanche', 'Pré-treino'].map(meal), shopping_list: [] }
    expect(types(raw)).toEqual(['Lanche', 'Pré-treino'])
  })

  it('the Flow request states the allowed meal_type codes', async () => {
    const calls: Array<{ messages: Array<{ content: unknown }> }> = []
    const llm = {
      complete: async (params: { messages: Array<{ content: unknown }> }) => {
        calls.push(params)
        return { content: 'x', model: 'm', finishReason: 'stop' }
      },
    } as unknown as OpenRouterLLM
    const supabase = { from: () => ({ insert: async () => ({ error: null }) }) } as unknown as ServiceClient
    const input = {
      userId: 'qa-a',
      identity: 'flow',
      profile: { name: null, sex: null, age: null, weight_kg: null, height_cm: null, activity_level: null, protocol: 'ganho_massa', meta_kcal: 3361, meta_protein_g: 186.1, bf_percent: null, restrictions: [], preferences: [] },
      historical_foods: [],
    } as unknown as DietGeneratorInput
    await generateDietPlan(llm, supabase, input)
    expect(String(calls[0]!.messages[0]!.content)).toMatch(/meal_type.*cafe.*lanche_manha.*almoco.*lanche_tarde.*jantar.*ceia/)
  })
})
