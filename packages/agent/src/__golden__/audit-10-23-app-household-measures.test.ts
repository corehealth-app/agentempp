/** Exact Roberto23/10 raw candidates at the shared agent boundary.
 * Mobile behavior is verified1:1 in admin/audit-10-23-household-measures.test.ts;
 * this package must not depend on an application or change the legacy parser. */
import { describe, expect, it } from 'vitest'
import { draftFromVisionItems, portionReferenceGrams, resolveDraftItem } from '../meal-draft'

describe('audit23/10 exact candidate identities before mobile presentation', () => {
  it('pão de queijo com requeijão240g/8unidades preserves the stated mass and existing30g reference', () => {
    expect(
      resolveDraftItem(
        { name: 'pão de queijo com requeijão', grams_stated: 240, count: 8, unit: 'unidade' },
        0,
      ),
    ).toMatchObject({
      name: 'pão de queijo com requeijão',
      quantity_g: 240,
      count: 8,
      unit_label: 'unidade',
      quantity_basis: 'stated',
    })
    expect(portionReferenceGrams('pão de queijo com requeijão', 'unidade')).toBe(30)
  })
  it('caneca and medida remain unresolved in the shared parser; only the mobile source boundary supplies their references', () => {
    expect(resolveDraftItem({ name: 'leite', count: 1, unit: 'caneca' }, 0)).toMatchObject({
      name: 'leite',
      quantity_g: null,
      count: 1,
      unit_label: 'caneca',
      quantity_basis: 'missing',
    })
    expect(resolveDraftItem({ name: 'whey', count: 1, unit: 'medida' }, 1)).toMatchObject({
      name: 'whey',
      quantity_g: null,
      count: 1,
      unit_label: 'medida',
      quantity_basis: 'missing',
    })
  })
  it('photo keeps plain leite206g distinct from whey without an observed amount', () => {
    expect(
      draftFromVisionItems(
        [
          { name: 'leite', quantity_g_estimate: 206, confidence: 0.9 },
          { name: 'whey', confidence: 0.9 },
        ],
        0.6,
      ),
    ).toMatchObject([
      { name: 'leite', quantity_g: 206, quantity_basis: 'visual_estimate' },
      { name: 'whey', quantity_g: null, quantity_basis: 'missing' },
    ])
  })
})
