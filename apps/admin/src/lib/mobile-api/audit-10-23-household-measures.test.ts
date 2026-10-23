/** Exact Roberto screenshots23/10. Mobile integration golden deliberately invokes
 * the actual mobile adapter; no legacy parser or WhatsApp behavior is changed.
 * UI entry/edit/toggle assertions live in MealHouseholdQuantityTests. */

import { draftFromVisionItems, resolveDraftItem } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import { createMealDraft } from './meal-draft-service'
import { mobileDraftQuantity } from './mobile-quantity-display'

describe('audit23/10 exact food/serving identities at the mobile boundary', () => {
  it('pão de queijo com requeijão240g,8×unidade keeps240g and exposes30g/unit', () => {
    const candidate = resolveDraftItem(
      { name: 'pão de queijo com requeijão', grams_stated: 240, count: 8, unit: 'unidade' },
      0,
    )!
    expect(mobileDraftQuantity(candidate)).toMatchObject({
      quantity_g: 240,
      count: 8,
      unit_label: 'unidade',
      quantity_display: { unit: 'unit', grams_per_unit: 30 },
    })
  })
  it('separate leite1×caneca and whey1×medida are206g and30g, editable references', async () => {
    const draft = await createMealDraft(
      {
        media: { findOwned: async () => null },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      'synthetic',
      { source: 'text', text: '1 caneca de leite;1 medida de whey' },
    )
    const [milk, whey] = draft.items
    expect(milk).toMatchObject({
      name: 'leite',
      quantity_g: 206,
      quantity_basis: 'portion_reference',
      quantity_display: { unit: 'mL' },
    })
    expect(whey).toMatchObject({
      name: 'whey',
      quantity_g: 30,
      quantity_basis: 'portion_reference',
      quantity_display: { unit: 'scoop' },
    })
  })
  it('photo plain leite206g stays distinct from whey; missing whey amount is not guessed', () => {
    const result = draftFromVisionItems(
      [
        { name: 'leite', quantity_g_estimate: 206, confidence: 0.9 },
        { name: 'whey', confidence: 0.9 },
      ],
      0.6,
    ).map(mobileDraftQuantity)
    expect(result).toMatchObject([
      { name: 'leite', quantity_g: 206, quantity_display: { unit: 'mL' } },
      { name: 'whey', quantity_g: null, quantity_basis: 'missing' },
    ])
  })
})
