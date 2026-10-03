import { describe, expect, it } from 'vitest'
import { sanitizePendingProposal, shapeTrends } from './read-model'

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

describe('trends read model', () => {
  it('returns stored days ascending, never filling the gaps, and dated weights only', () => {
    const shaped = shapeTrends(
      [
        {
          date: '2026-07-20',
          calories_consumed: 1200,
          calories_target: 1935,
          exercise_calories: 100,
          protein_g: '90.50',
          protein_target: null,
          water_consumed_ml: 1250,
          deficit_accumulated: 2464,
          xp_earned: 40,
          day_closed: false,
        },
        {
          date: '2026-07-18',
          calories_consumed: 2100,
          calories_target: 1935,
          exercise_calories: 0,
          protein_g: '120',
          protein_target: '186.10',
          water_consumed_ml: 2000,
          deficit_accumulated: 2364,
          xp_earned: 60,
          day_closed: true,
        },
      ],
      [
        { evaluation_date: '2026-07-15', weight_kg: '79.10' },
        { evaluation_date: '2026-07-01', weight_kg: '80.00' },
        { evaluation_date: '2026-06-17', weight_kg: null },
      ],
      14,
    )
    expect(shaped.days).toBe(14)
    expect(shaped.daily.map((row) => row.date)).toEqual(['2026-07-18', '2026-07-20'])
    expect(shaped.daily[0]).toMatchObject({ protein_g: 120, protein_target: 186.1, day_closed: true })
    expect(shaped.daily[1]).toMatchObject({ protein_g: 90.5, protein_target: null, day_closed: false })
    expect(shaped.weights).toEqual([
      { date: '2026-07-01', weight_kg: 80 },
      { date: '2026-07-15', weight_kg: 79.1 },
    ])
  })

  it('keeps only the last `days` rows when more are given', () => {
    const rows = Array.from({ length: 20 }, (_, index) => ({
      date: `2026-07-${String(index + 1).padStart(2, '0')}`,
      calories_consumed: 0,
      calories_target: null,
      exercise_calories: 0,
      protein_g: 0,
      protein_target: null,
      water_consumed_ml: 0,
      deficit_accumulated: 0,
      xp_earned: 0,
      day_closed: false,
    }))
    const shaped = shapeTrends(rows, [], 7)
    expect(shaped.daily).toHaveLength(7)
    expect(shaped.daily[0].date).toBe('2026-07-14')
    expect(shaped.daily[6].date).toBe('2026-07-20')
  })
})
