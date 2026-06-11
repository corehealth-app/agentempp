import { describe, expect, it } from 'vitest'
import { pickAnchorFood, inferTags } from './curated-phrase-selector.js'

describe('pickAnchorFood', () => {
  it('escolhe item com mais kcal e proteína densa', () => {
    const r = pickAnchorFood([
      { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
      { food_name: 'frango assado', kcal: 200, protein_g: 30, carbs_g: 0, fat_g: 8 },
    ])
    expect(r?.food_name).toBe('frango assado')
  })

  it('escolhe gordura densa quando kcal igual', () => {
    const r = pickAnchorFood([
      { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
      { food_name: 'azeite', kcal: 130, protein_g: 0, carbs_g: 0, fat_g: 14 },
    ])
    expect(r?.food_name).toBe('azeite')
  })

  it('items vazio → null', () => {
    expect(pickAnchorFood([])).toBeNull()
  })

  it('1 item só → ele é o anchor', () => {
    const r = pickAnchorFood([
      { food_name: 'banana', kcal: 100, protein_g: 1, carbs_g: 25, fat_g: 0 },
    ])
    expect(r?.food_name).toBe('banana')
  })
})

describe('inferTags', () => {
  it('vazio quando sem state', () => {
    expect(inferTags()).toEqual([])
  })

  it('recomp + protein_low quando déficit + proteína baixa', () => {
    const tags = inferTags({ protocol: 'recomposicao', protein_pct: 30 })
    expect(tags).toContain('recomp')
    expect(tags).toContain('protein_low')
  })

  it('protein_high quando proteína >= 80%', () => {
    const tags = inferTags({ protein_pct: 85 })
    expect(tags).toContain('protein_high')
    expect(tags).not.toContain('protein_low')
  })

  it('block_near_close quando bloco >= 90%', () => {
    const tags = inferTags({ deficit_block_pct: 95 })
    expect(tags).toContain('block_near_close')
  })

  it('ganho_massa + kcal_high', () => {
    const tags = inferTags({ protocol: 'ganho_massa', kcal_pct: 85 })
    expect(tags).toContain('ganho_massa')
    expect(tags).toContain('kcal_high')
  })
})
