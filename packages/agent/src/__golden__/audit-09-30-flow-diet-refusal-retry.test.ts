/**
 * Golden regressions from the staging iPhone attempts on 2026-09-30:
 * 17:15Z protein_drift_exceeded, 242 g against 186.1 g (+30%, limit 20%);
 * 17:18Z zod_validation_failed, daily_meals.3.items.6.protein_g Required.
 * The complete model outputs were not retained, so these fixtures reproduce
 * the exact recorded rejection values and path, not unobserved food choices.
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it, vi } from 'vitest'
import { type DietGeneratorInput, generateDietPlan } from '../diet-generator.js'

const input: DietGeneratorInput = {
  userId: 'qa-a',
  identity: 'flow',
  profile: {
    name: null,
    sex: null,
    age: null,
    weight_kg: null,
    height_cm: null,
    activity_level: null,
    protocol: 'ganho_massa',
    meta_kcal: 3361,
    meta_protein_g: 186.1,
    bf_percent: null,
    restrictions: [],
    preferences: [],
  },
  historical_foods: [],
}

function output(kcal: number, protein: number, missingProtein = false): string {
  const meals = ['cafe', 'almoco', 'lanche_tarde', 'jantar'].map((meal_type, mealIndex) => ({
    meal_type,
    items: Array.from({ length: mealIndex === 3 && missingProtein ? 7 : 1 }, (_, itemIndex) => {
      const item: Record<string, unknown> = {
        food_name: 'alimento de teste',
        quantity_g: 100,
        kcal: kcal / 4,
        protein_g: protein / 4,
        carbs_g: 1,
        fat_g: 1,
      }
      if (mealIndex === 3 && itemIndex === 6 && missingProtein) delete item.protein_g
      return item
    }),
    total_kcal: kcal / 4,
    total_protein_g: protein / 4,
  }))
  return JSON.stringify({ daily_meals: meals, shopping_list: [] })
}

function harness(responses: string[], onComplete?: (callNumber: number) => void) {
  const calls: Array<{ messages: Array<{ content: unknown }>; requestTimeoutMs?: number }> = []
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const llm = {
    complete: async (params: {
      messages: Array<{ content: unknown }>
      requestTimeoutMs?: number
    }) => {
      calls.push(params)
      onComplete?.(calls.length)
      return { content: responses[calls.length - 1], model: 'mock', finishReason: 'stop' }
    },
  } as unknown as OpenRouterLLM
  const supabase = {
    from: () => ({
      insert: async (event: { event: string; properties: Record<string, unknown> }) => {
        events.push(event)
        return { error: null }
      },
    }),
  } as unknown as ServiceClient
  return { llm, supabase, calls, events }
}

describe('audit 2026-09-30 — Flow diet refusal feedback', () => {
  it('retries once with the exact 242 g versus 186.1 g protein refusal', async () => {
    const h = harness([output(3361, 242), output(3361, 186.1)])
    const plan = await generateDietPlan(h.llm, h.supabase, input)
    expect(plan).not.toBeNull()
    expect(h.calls).toHaveLength(2)
    const retryPrompt = String(h.calls[1]?.messages[0]?.content)
    expect(retryPrompt).toContain('242')
    expect(retryPrompt).toContain('186.1')
    expect(retryPrompt).toContain('30%')
    expect(h.events[0]?.properties.reason).toBe('protein_drift_exceeded')
  })

  it('retries once with the exact missing daily_meals.3.items.6.protein_g field', async () => {
    const h = harness([output(3361, 186.1, true), output(3361, 186.1)])
    const plan = await generateDietPlan(h.llm, h.supabase, input)
    expect(plan).not.toBeNull()
    expect(h.calls).toHaveLength(2)
    const retryPrompt = String(h.calls[1]?.messages[0]?.content)
    expect(retryPrompt).toContain('daily_meals.3.items.6.protein_g')
    expect(retryPrompt).toContain('Required')
    expect(h.events[0]?.properties.reason).toBe('zod_validation_failed')
  })

  it('does not accept a second rejected answer or make a third call', async () => {
    const h = harness([output(3361, 242), output(3361, 242), output(3361, 186.1)])
    expect(await generateDietPlan(h.llm, h.supabase, input)).toBeNull()
    expect(h.calls).toHaveLength(2)
  })

  it('shares the old 120 s generator budget across both Flow attempts', async () => {
    let now = 1_000_000
    const clock = vi.spyOn(Date, 'now').mockImplementation(() => now)
    try {
      const h = harness([output(3361, 242), output(3361, 186.1)], (call) => {
        if (call === 1) now += 45_000
      })
      expect(await generateDietPlan(h.llm, h.supabase, input)).not.toBeNull()
      expect(h.calls.map((call) => call.requestTimeoutMs)).toEqual([120_000, 75_000])
    } finally {
      clock.mockRestore()
    }
  })

  it('does not start another paid call when the generator budget is exhausted', async () => {
    let now = 1_000_000
    const clock = vi.spyOn(Date, 'now').mockImplementation(() => now)
    try {
      const h = harness([output(3361, 242), output(3361, 186.1)], (call) => {
        if (call === 1) now += 120_000
      })
      expect(await generateDietPlan(h.llm, h.supabase, input)).toBeNull()
      expect(h.calls).toHaveLength(1)
    } finally {
      clock.mockRestore()
    }
  })

  it('leaves the WhatsApp path at one call and the same rejection', async () => {
    const h = harness([output(3361, 242), output(3361, 186.1)])
    expect(await generateDietPlan(h.llm, h.supabase, { ...input, identity: 'legacy' })).toBeNull()
    expect(h.calls).toHaveLength(1)
  })

  it('preserves the existing ±15% kcal window: 2931 kcal versus 3361 remains accepted', async () => {
    const h = harness([output(2931, 212.6)])
    const plan = await generateDietPlan(h.llm, h.supabase, input)
    expect(plan?.daily_meals.reduce((sum, meal) => sum + meal.total_kcal, 0)).toBe(2931)
    expect(h.calls).toHaveLength(1)
  })
})
