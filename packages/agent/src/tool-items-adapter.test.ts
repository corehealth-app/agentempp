/**
 * Testes do adapter de items: tool result (chave `name`) → EduCommentInput
 * (chave `food_name`). Cobre o bug histórico do shape mismatch (P0 audit
 * 2026-06-13: cast TS escondia food_name=undefined em runtime; 36h+
 * invisível porque catch silencioso + tests usavam fixtures "ideais" com
 * food_name no shape).
 *
 * Princípio: as fixtures aqui imitam o shape REAL que tools.ts:1359 retorna,
 * NÃO o shape "ideal" do tipo. Se amanhã alguém mudar o adapter ou remover,
 * estes testes detectam ANTES do bug chegar em prod.
 */
import { describe, expect, it } from 'vitest'
import { adaptToolItemsToEduInput } from './educational-comment.js'

describe('adaptToolItemsToEduInput — shape real da tool', () => {
  it('mapeia items com chave `name` (shape de tools.ts:1359) pro shape food_name', () => {
    // ESTA é a forma exata em que registra_refeicao retorna em produção.
    const toolItems = [
      {
        name: 'aveia em flocos',
        quantity_g: 40,
        kcal: 152,
        protein_g: 5.6,
        carbs_g: 27,
        fat_g: 2.8,
      },
      {
        name: 'banana',
        quantity_g: 100,
        kcal: 89,
        protein_g: 1.1,
        carbs_g: 22.8,
        fat_g: 0.3,
      },
    ]
    const result = adaptToolItemsToEduInput(toolItems)
    expect(result).toEqual([
      {
        food_name: 'aveia em flocos',
        quantity_g: 40,
        kcal: 152,
        protein_g: 5.6,
        carbs_g: 27,
        fat_g: 2.8,
      },
      {
        food_name: 'banana',
        quantity_g: 100,
        kcal: 89,
        protein_g: 1.1,
        carbs_g: 22.8,
        fat_g: 0.3,
      },
    ])
  })

  it('aceita items que já têm `food_name` (compatibilidade com callers legacy)', () => {
    const eduItems = [
      {
        food_name: 'ovo cozido',
        quantity_g: 50,
        kcal: 78,
        protein_g: 6.5,
        carbs_g: 0.5,
        fat_g: 5.3,
      },
    ]
    const result = adaptToolItemsToEduInput(eduItems)
    expect(result?.[0]?.food_name).toBe('ovo cozido')
  })

  it('preferência: `name` ganha de `food_name` quando ambos presentes (tool result é fonte autoritativa)', () => {
    const ambiguous = [
      {
        name: 'iogurte natural',
        food_name: 'iogurte zero',
        quantity_g: 170,
        kcal: 100,
        protein_g: 10,
        carbs_g: 8,
        fat_g: 3,
      },
    ]
    const result = adaptToolItemsToEduInput(ambiguous)
    expect(result?.[0]?.food_name).toBe('iogurte natural')
  })

  it('item sem `name` NEM `food_name` cai pra string vazia — hardening do selector pega', () => {
    const broken = [
      {
        quantity_g: 100,
        kcal: 200,
        protein_g: 10,
        carbs_g: 20,
        fat_g: 5,
      } as { quantity_g: number; kcal: number; protein_g: number; carbs_g: number; fat_g: number },
    ]
    const result = adaptToolItemsToEduInput(broken)
    expect(result?.[0]?.food_name).toBe('')
  })

  it('undefined / null → undefined (degradação graciosa, NÃO crash)', () => {
    expect(adaptToolItemsToEduInput(undefined)).toBe(undefined)
    expect(adaptToolItemsToEduInput(null)).toBe(undefined)
  })

  it('macros opcionais (kcal/protein/carbs/fat) caem pra 0 — pickAnchorFood não quebra', () => {
    const minimal = [
      { name: 'agua', quantity_g: 500 },
    ]
    const result = adaptToolItemsToEduInput(minimal)
    expect(result?.[0]).toEqual({
      food_name: 'agua',
      quantity_g: 500,
      kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    })
  })

  it('regressão guard: o tipo retornado tem `food_name` (não `name`) — protege contra rename futuro do EduCommentInput', () => {
    const toolItems = [
      { name: 'frango grelhado', quantity_g: 100, kcal: 165, protein_g: 31, carbs_g: 0, fat_g: 3.6 },
    ]
    const result = adaptToolItemsToEduInput(toolItems)
    // Se amanhã EduCommentInput.items[].food_name virar items[].name, esta
    // checagem quebra explicitamente em vez de silenciosamente degradar.
    expect(result?.[0]).toHaveProperty('food_name')
    expect(result?.[0]).not.toHaveProperty('name')
  })
})
