import { resolveDraftItem } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import { mobileDraftQuantity, mobileQuantityFields } from './mobile-quantity-display'

describe('app-only quantity references', () => {
  it.each([
    ['café coado', 1, 'fao-infoods-v2-coffee-fndds4-1'],
    ['chá preparado', 1, 'fao-infoods-v2-tea-fndds4-1'],
    ['água', 1, 'fao-infoods-v2-water-cg'],
    ['suco de laranja', 1.038, 'fao-infoods-v2-orange-juice-sw'],
  ])('uses only the documented reference for%s', (name, factor, reference) => {
    const candidate = resolveDraftItem({ name: String(name), count: 200, unit: 'ml' }, 0)!
    expect(mobileDraftQuantity(candidate)).toMatchObject({
      quantity_g: 200 * Number(factor),
      quantity_basis: 'portion_reference',
      quantity_display: {
        unit: 'mL',
        grams_per_unit: factor,
        reference_id: reference,
        estimated: true,
      },
    })
  })

  it('keeps stated210g when original text also carried200ml; never replaces mass with a reference', () => {
    const candidate = resolveDraftItem(
      { name: 'leite integral', grams_stated: 210, count: 200, unit: 'ml' },
      0,
    )!
    expect(candidate.quantity_basis).toBe('stated')
    expect(mobileDraftQuantity(candidate)).toMatchObject({
      quantity_g: 210,
      quantity_basis: 'stated',
      quantity_display: { grams_per_unit: 1.03 },
    })
  })
  it.each([
    'leite em pó',
    'café em pó',
    'chá em folhas',
    'suco de laranja em pó',
    'água tônica',
    'leite de coco',
    'café com leite',
    'leite integral Marca X',
  ])('does not infer density for%s', (name) => {
    expect(mobileQuantityFields(name)).toEqual({})
  })
  it('whey powder has a30g editable scoop reference, never a liquid density', () => {
    expect(mobileQuantityFields('whey protein em pó')).toEqual({
      quantity_display: {
        unit: 'scoop',
        grams_per_unit: 30,
        reference_id: 'app-household-whey-scoop-v1',
        estimated: true,
      },
    })
  })
  it('canonical projections never reconvert old mass from names alone', () => {
    expect(mobileQuantityFields('leite integral')).toEqual({
      quantity_display: {
        unit: 'mL',
        grams_per_unit: 1.03,
        reference_id: 'fao-infoods-v2-whole-milk-tb',
        estimated: true,
      },
    })
  })
})
