import { describe, expect, it } from 'vitest'
import { confirmedMealDeleteInputSchema, confirmedMealPatchInputSchema } from './contracts'

const id = 'c1110000-0000-4000-8000-000000000003'
const sibling = 'c1110000-0000-4000-8000-000000000004'
const selection = { expected_version: `v1:${'a'.repeat(64)}`, item_ids: [id] }
const item = { food_name: 'iogurte natural', quantity_g: 170 }

describe('confirmed meal mutation input', () => {
  it('accepts one selected food with several replacement ingredients and retains existing item validation', () => {
    expect(
      confirmedMealPatchInputSchema.parse({
        ...selection,
        items: [item, { food_name: 'arroz cozido', quantity_g: 50, user_kcal: 65 }],
      }),
    ).toEqual({
      ...selection,
      items: [item, { food_name: 'arroz cozido', quantity_g: 50, user_kcal: 65 }],
    })
  })

  it.each([
    { ...selection, item_ids: [id, sibling], items: [item] },
    { ...selection, item_ids: [], items: [item] },
    { ...selection, items: [] },
    { ...selection, items: Array(31).fill(item) },
    { ...selection, items: [{ ...item, quantity_g: 0 }] },
    { ...selection, items: [{ ...item, quantity_g: 10_000 }] },
    { ...selection, items: [{ ...item, food_name: '' }] },
    { ...selection, items: [{ ...item, user_kcal: -1 }] },
    { ...selection, items: [{ ...item, kcal: 123 }] },
    { ...selection, items: [{ ...item, use_nutrition_label: true }] },
    { ...selection, items: [item], expected_state: {} },
    { ...selection, items: [item], nutrition_mode: 'quantity_only' },
    { ...selection, items: [item], consumed_at: '2026-10-09T20:00:00Z' },
    { ...selection, items: [item], expected_version: 'a'.repeat(64) },
  ])('refuses invalid PATCH input %# before any ledger claim', (input) => {
    expect(confirmedMealPatchInputSchema.safeParse(input).success).toBe(false)
  })

  it('permits finite explicit DELETE selection of several foods', () => {
    expect(confirmedMealDeleteInputSchema.parse({ ...selection, item_ids: [id, sibling] })).toEqual(
      { ...selection, item_ids: [id, sibling] },
    )
  })

  it.each([
    { ...selection, item_ids: [id, id.toUpperCase()] },
    { ...selection, item_ids: [] },
    { ...selection, item_ids: [null] },
    { ...selection, item_ids: ['not-a-uuid'] },
    {
      ...selection,
      item_ids: Array.from(
        { length: 31 },
        (_, index) => `c1110000-0000-4000-8000-${String(index).padStart(12, '0')}`,
      ),
    },
    { ...selection, items: [item] },
    { ...selection, user_id: sibling },
  ])('refuses invalid DELETE input %# before any ledger claim', (input) => {
    expect(confirmedMealDeleteInputSchema.safeParse(input).success).toBe(false)
  })
})
