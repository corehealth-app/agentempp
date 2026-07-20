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
        },
      ],
      totals: { kcal: 130, protein_g: 2.5, carbs_g: 28, fat_g: 0.3 },
    })
  })

  it('returns a minimal safe shape for malformed legacy proposals', () => {
    expect(sanitizePendingProposal({ source_text: 'hidden' })).toEqual({ kind: 'unknown' })
  })
})
