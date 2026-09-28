import { describe, expect, it } from 'vitest'
import { sanitizePendingProposal } from './read-model'

describe('mobile read model', () => {
  it('removes transport and internal evidence from pending meal proposals', () => {
    expect(
      sanitizePendingProposal({
        kind: 'meal',
        mealType: 'jantar',
        source_text: 'private raw message',
        source_msg_id: 'message-id',
        replace_evidence: 'internal evidence',
        items: [
          {
            name: 'arroz',
            quantity_g: 100,
            kcal: 130,
            protein_g: 2.5,
            carbs_g: 28,
            fat_g: 0.3,
            food_db_id: 42,
            audit_warnings: ['internal'],
          },
        ],
        totals: { kcal: 130, protein_g: 2.5, carbs_g: 28, fat_g: 0.3 },
        userWarnings: ['Confirme o preparo antes de registrar.'],
      }),
    ).toEqual({
      kind: 'meal',
      meal_type: 'jantar',
      items: [
        {
          name: 'arroz',
          quantity_g: 100,
          kcal: 130,
          protein_g: 2.5,
          carbs_g: 28,
          fat_g: 0.3,
          user_kcal: null,
          nutrition_source: null,
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: null,
        },
      ],
      totals: { kcal: 130, protein_g: 2.5, carbs_g: 28, fat_g: 0.3 },
      source: { channel: 'mobile', media_asset_id: null },
      warnings: ['Confirme o preparo antes de registrar.'],
    })
  })

  it('exposes each item calorie origin exactly as stored: patient value and applied source', () => {
    const proposal = sanitizePendingProposal({
      kind: 'meal',
      mealType: 'almoco',
      items: [
        {
          name: 'wrap',
          quantity_g: 43,
          kcal: 70,
          protein_g: 2,
          carbs_g: 12,
          fat_g: 1.5,
          user_kcal: 70,
          nutrition_source: 'user_kcal',
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: null,
          food_db_id: 7,
        },
        {
          name: 'arroz',
          quantity_g: 100,
          kcal: 130,
          protein_g: 2.5,
          carbs_g: 28,
          fat_g: 0.3,
          user_kcal: null,
          nutrition_source: 'canonical_exact',
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: null,
        },
        {
          name: 'queijo',
          quantity_g: 30,
          kcal: 96,
          protein_g: 7,
          carbs_g: 0.3,
          fat_g: 7.5,
          user_kcal: 900,
          nutrition_source: 'canonical_fuzzy',
        },
      ],
      totals: { kcal: 296, protein_g: 11.5, carbs_g: 40.3, fat_g: 9.3 },
      userWarnings: [],
    })

    expect(proposal).toMatchObject({
      items: [
        { name: 'wrap', kcal: 70, user_kcal: 70, nutrition_source: 'user_kcal' },
        { name: 'arroz', kcal: 130, user_kcal: null, nutrition_source: 'canonical_exact' },
        // The patient value the server rejected stays visible as input, but
        // the applied source shows the calorie is not the patient's.
        { name: 'queijo', kcal: 96, user_kcal: 900, nutrition_source: 'canonical_fuzzy' },
      ],
    })
    expect(JSON.stringify(proposal)).not.toContain('food_db_id')
  })

  it('reports an absent origin as null rather than inventing a source', () => {
    const proposal = sanitizePendingProposal({
      kind: 'meal',
      mealType: 'jantar',
      items: [{ name: 'arroz', quantity_g: 100, kcal: 130, protein_g: 2.5, carbs_g: 28, fat_g: 0.3 }],
      totals: null,
      userWarnings: [],
    })

    expect(proposal).toMatchObject({
      items: [{ name: 'arroz', user_kcal: null, nutrition_source: null }],
    })
  })

  it('returns a minimal safe shape for malformed legacy proposals', () => {
    expect(sanitizePendingProposal({ source_text: 'hidden' })).toEqual({ kind: 'unknown' })
  })
})
