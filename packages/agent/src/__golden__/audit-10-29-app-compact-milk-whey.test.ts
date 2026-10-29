import { describe, expect, it } from 'vitest'
import { mobileMilkWheyTotalPortions } from '../mobile-household-drink'

// Exact29Oct report: "Leite com 1 medida de whey",200g, nutrition absent.
// The screenshot did not identify200g as milk alone: it is the compound's
// total. The approved editable30g powder reference must not inflate it to230g.
describe('Roberto29Oct compact milk/whey total, app boundary', () => {
  it.each([
    'stated',
    'visual_estimate',
    'portion_reference',
  ] as const)('keeps the200g total with explicitly derived portions, original basis %s', (quantity_basis) => {
    expect(
      mobileMilkWheyTotalPortions('Leite com 1 medida de whey', {
        quantity_g: 200,
        quantity_basis,
      }),
    ).toEqual([
      { food_name: 'leite integral', quantity_g: 170, quantity_basis: 'portion_reference' },
      { food_name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference' },
    ])
  })

  it('keeps a decimal total without rounding away the stated mass', () => {
    const parts = mobileMilkWheyTotalPortions('leite com uma dose de whey', { quantity_g: 200.125 })
    expect(parts?.map((part) => part.quantity_g)).toEqual([170.125, 30])
  })

  it.each([
    0,
    20,
    30,
    -1,
    10000,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('does not invent extra mass for an invalid or insufficient total %s', (quantity_g) => {
    expect(mobileMilkWheyTotalPortions('Leite com 1 medida de whey', { quantity_g })).toBeNull()
  })

  it.each([
    'leite desnatado com 1 medida de whey',
    'leite com 1 medida de whey Marca X',
    'leite sem whey',
    'não tomei leite com 1 medida de whey',
    'leite com 2 medidas de whey',
    'leite200g com whey30g',
    '1 caneca de leite com uma medida de whey',
    '1 medida de whey',
  ])('keeps other compositions on their existing path: %s', (name) => {
    expect(mobileMilkWheyTotalPortions(name, { quantity_g: 200 })).toBeNull()
  })
})
