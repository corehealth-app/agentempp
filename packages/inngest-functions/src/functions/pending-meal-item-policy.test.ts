import { describe, expect, it } from 'vitest'
import { decidePendingMealItems } from './pending-meal-item-policy.js'

const normalItem = {
  name: 'arroz branco',
  quantity_g: 100,
  kcal: 130,
  protein_g: 2.7,
  carbs_g: 28,
  fat_g: 0.3,
}

describe('decidePendingMealItems', () => {
  it('rejeita proposta vazia em vez de confirmar registro inexistente', () => {
    expect(decidePendingMealItems([], false)).toMatchObject({ action: 'reject_empty' })
  })

  it('considera chocolate pequeno com zero kcal suspeito', () => {
    expect(
      decidePendingMealItems(
        [
          {
            name: 'chocolate ao leite',
            quantity_g: 8,
            kcal: 0,
            protein_g: 0,
            carbs_g: 0,
            fat_g: 0,
          },
        ],
        false,
      ),
    ).toMatchObject({ action: 'block', suspiciousItems: [{ name: 'chocolate ao leite' }] })
  })

  it('mantém água, café preto e refrigerante zero como zeros legítimos', () => {
    const decision = decidePendingMealItems(
      [
        { ...normalItem, name: 'água', kcal: 0 },
        { ...normalItem, name: 'café preto sem açúcar', kcal: 0 },
        { ...normalItem, name: 'Coca-Cola Zero', kcal: 0 },
      ],
      false,
    )

    expect(decision.action).toBe('proceed')
    expect(decision.suspiciousItems).toEqual([])
  })

  it('no retry misto registra somente os itens calculados', () => {
    const decision = decidePendingMealItems(
      [normalItem, { ...normalItem, name: 'macarronada', quantity_g: 350, kcal: 0 }],
      true,
    )

    expect(decision.action).toBe('register_valid_only')
    expect(decision.validItems.map((item) => item.name)).toEqual(['arroz branco'])
  })

  it('no retry com todos os itens suspeitos não registra refeição de zero kcal', () => {
    const decision = decidePendingMealItems(
      [{ ...normalItem, name: 'macarronada', quantity_g: 350, kcal: 0 }],
      true,
    )

    expect(decision.action).toBe('reject_all')
    expect(decision.validItems).toEqual([])
  })
})
