import { describe, expect, it } from 'vitest'
import { applyKnownProductServingQuantities } from './known-product-servings.js'

describe('applyKnownProductServingQuantities', () => {
  it('usa 43 g para uma unidade de Rap10/Mission nos EUA', () => {
    const result = applyKnownProductServingQuantities(
      [{ food_name: 'rap10', quantity_g: 35 }],
      '1 rap 10 com queijo',
      'US',
    )

    expect(result.items[0]?.quantity_g).toBe(43)
    expect(result.adjustments[0]).toMatchObject({ servings: 1, quantity_g: 43 })
  })

  it('multiplica a porção quando o paciente declara duas unidades', () => {
    const result = applyKnownProductServingQuantities(
      [{ food_name: 'rap10', quantity_g: 70 }],
      '2 rap10 com frango',
      'US',
    )

    expect(result.items[0]?.quantity_g).toBe(86)
  })

  it('preserva gramas explicitamente informadas pelo paciente', () => {
    const result = applyKnownProductServingQuantities(
      [{ food_name: 'rap10', quantity_g: 70 }],
      'rap10 de 70g com queijo',
      'US',
    )

    expect(result.items[0]?.quantity_g).toBe(70)
    expect(result.adjustments).toHaveLength(0)
  })

  it('não aplica o rótulo americano fora dos EUA', () => {
    const result = applyKnownProductServingQuantities(
      [{ food_name: 'rap10', quantity_g: 35 }],
      '1 rap10 com queijo',
      'BR',
    )

    expect(result.items[0]?.quantity_g).toBe(35)
  })
})
