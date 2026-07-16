import { describe, expect, it } from 'vitest'
import {
  buildConfirmedMealArgs,
  buildConfirmedMealRegistrationEntry,
  selectValidatedWriteItems,
  shouldBlockEffectiveReplace,
} from './pending-meal-confirmation.js'

describe('buildConfirmedMealArgs', () => {
  it('usa somente os itens de escrita na correção por item', () => {
    const rap10 = {
      name: 'rap10',
      quantity_g: 35,
      kcal: 70,
      protein_g: 3.27,
      carbs_g: 8.4,
      fat_g: 2.33,
    }
    const calabresa = {
      name: 'calabresa fatiada',
      food_db_id: 317,
      quantity_g: 60,
      kcal: 186,
      protein_g: 10.8,
      carbs_g: 1.2,
      fat_g: 15.6,
    }
    const fullDinner = [rap10, calabresa]
    const args = buildConfirmedMealArgs(
      {
        mealType: 'jantar',
        items: fullDinner,
        writeItems: [calabresa],
        corrections: [{ de: 'salame fatiado', para: 'calabresa fatiada' }],
      },
      true,
      '2026-07-15',
    )

    expect(args.items.map((item) => item.food_name)).toEqual(['calabresa fatiada'])
  })

  it('propaga correções e macros aprovados no pending para registra_refeicao', () => {
    const args = buildConfirmedMealArgs(
      {
        mealType: 'almoco',
        items: [
          {
            name: 'frango grelhado',
            food_db_id: 321,
            quantity_g: 120,
            kcal: 191,
            protein_g: 38.4,
            carbs_g: 0,
            fat_g: 3,
          },
        ],
        corrections: [
          {
            de: 'frango frito',
            para: 'frango grelhado',
            kcal_per_100g: 159,
            protein_g: 32,
            carbs_g: 0,
            fat_g: 2.5,
          },
        ],
      },
      true,
      '2026-07-10',
    )

    expect(args.corrections).toEqual([
      {
        de: 'frango frito',
        para: 'frango grelhado',
        kcal_per_100g: 159,
        protein_g: 32,
        carbs_g: 0,
        fat_g: 2.5,
      },
    ])
    expect(args.items[0]?.approved_nutrition).toEqual({
      food_db_id: 321,
      kcal: 191,
      protein_g: 38.4,
      carbs_g: 0,
      fat_g: 3,
    })
  })
})

describe('selectValidatedWriteItems', () => {
  it('rejeita correção quando o único item de escrita foi removido pela validação', () => {
    const calabresa = {
      name: 'calabresa fatiada',
      quantity_g: 60,
      kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    }

    expect(selectValidatedWriteItems([calabresa], [])).toBeNull()
  })

  it('usa a versão validada do item e não uma cópia divergente do writeItems', () => {
    const validated = {
      name: 'calabresa fatiada',
      quantity_g: 60,
      kcal: 186,
      protein_g: 10.8,
      carbs_g: 1.2,
      fat_g: 15.6,
    }

    expect(selectValidatedWriteItems([{ ...validated, kcal: 999 }], [validated])).toEqual([
      validated,
    ])
  })
})

describe('shouldBlockEffectiveReplace', () => {
  it('bloqueia replace fraco vindo de uma edição comum', () => {
    expect(
      shouldBlockEffectiveReplace({
        effectiveReplace: true,
        hasPriorMealOfSameType: true,
        hasPriorEditedPending: true,
        inferredReplace: false,
        replaceEvidence: null,
      }),
    ).toBe(true)
  })

  it('preserva replace necessário para concluir recuperação atômica', () => {
    expect(
      shouldBlockEffectiveReplace({
        effectiveReplace: true,
        hasPriorMealOfSameType: true,
        hasPriorEditedPending: true,
        inferredReplace: false,
        replaceEvidence: 'lossy_cancellation_recovery',
      }),
    ).toBe(false)
  })
})

describe('buildConfirmedMealRegistrationEntry', () => {
  it('exibe a refeição completa depois de aplicar somente o patch', () => {
    const rap10 = {
      name: 'rap10',
      quantity_g: 35,
      kcal: 70,
      protein_g: 3.27,
      carbs_g: 8.4,
      fat_g: 2.33,
    }
    const calabresa = {
      name: 'calabresa fatiada',
      quantity_g: 60,
      kcal: 186,
      protein_g: 10.8,
      carbs_g: 1.2,
      fat_g: 15.6,
    }
    const fullDinner = [rap10, calabresa]

    expect(
      buildConfirmedMealRegistrationEntry(
        {
          mealType: 'jantar',
          items: fullDinner,
          writeItems: [calabresa],
          totals: { kcal: 256, protein_g: 14.07, carbs_g: 9.6, fat_g: 17.93 },
        },
        {
          meal: {
            items: [calabresa],
            totals: { kcal: 186, protein_g: 10.8, carbs_g: 1.2, fat_g: 15.6 },
          },
        },
      ),
    ).toMatchObject({
      items: fullDinner,
      totals: { kcal: 256, protein_g: 14.07, carbs_g: 9.6, fat_g: 17.93 },
    })
  })

  it('preserva o sinal de deduplicação em retry da confirmação', () => {
    expect(
      buildConfirmedMealRegistrationEntry(
        {
          mealType: 'almoco',
          items: [],
          totals: { kcal: 435, protein_g: 39, carbs_g: 0, fat_g: 28.5 },
        },
        {
          already_logged: true,
          meal: { items: [], totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 } },
        },
      ),
    ).toMatchObject({
      tool: 'registra_refeicao',
      mealType: 'almoco',
      alreadyLogged: true,
      items: [],
    })
  })
})
