/**
 * Exact report: item 4 "1 caneca de leite com uma medida de whey", milk
 * entered as 200 g, screenshot132.8 kcal/P6.14/C10.5/F7.5 and whey missing.
 * Owner authorized editable household references on22/10. The BFF test
 * registration-service.everyday-defaults.test.ts runs the real calculator,
 * edit and confirmation; the other three foods there are synthetic.
 * This helper is called by the mobile BFF, never legacy processMessage.
 * New cup:200mL→206g with the FAOreference. Old stated200g stays200g.
 * Whey30g is an editable portion, not a universal scoop or a known brand.
 */
import { describe, expect, it } from 'vitest'
import { mobileMilkWheyPortions } from '../mobile-household-drink'

describe('Roberto22/10 household milk+whey, app boundary', () => {
  it('keeps200g milk and adds the powder as an independently editable reference', () => {
    expect(
      mobileMilkWheyPortions('1 caneca de leite com uma medida de whey', {
        quantity_g: 200,
        quantity_basis: 'stated',
      }),
    ).toEqual([
      { food_name: 'leite integral', quantity_g: 200, quantity_basis: 'stated' },
      { food_name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference' },
    ])
  })
  it('free text says the ingredients but does not state the grams', () => {
    expect(mobileMilkWheyPortions('Tomei uma caneca de leite com uma dose de whey')).toEqual([
      { food_name: 'leite integral', quantity_g: 206, quantity_basis: 'portion_reference' },
      { food_name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference' },
    ])
  })
  it.each([
    'não tomei uma caneca de leite com uma dose de whey',
    '1 caneca de leite sem whey',
    '1 caneca de leite desnatado com uma medida de whey',
    '1 caneca de leite com uma medida de whey Marca X',
    '200g de leite com30g de whey',
    '1 caneca de leite com duas medidas de whey',
    '1 caneca de leite',
    'whey protein em pó',
  ])('does not invent this generic recipe for %s', (name) => {
    expect(mobileMilkWheyPortions(name)).toBeNull()
  })
  it('keeps an already reviewed visual milk quantity and refuses invalid weights', () => {
    expect(
      mobileMilkWheyPortions('1 caneca de leite com uma medida de whey', {
        quantity_g: 250,
        quantity_basis: 'visual_estimate',
      })?.[0],
    ).toEqual({ food_name: 'leite integral', quantity_g: 250, quantity_basis: 'visual_estimate' })
    for (const grams of [0, -1, 10_000, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(
        mobileMilkWheyPortions('1 caneca de leite com uma medida de whey', { quantity_g: grams }),
      ).toBeNull()
    }
  })
})
