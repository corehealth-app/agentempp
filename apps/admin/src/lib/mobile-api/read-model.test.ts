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

  // iPhone, 2026-10-04 (QA A): weight 80.5 kg registered at 09:09 showed
  // under "Medidas" while the chart still ended at 80.0 kg on 3 Oct.
  it('adds the weight registered in the app on the day it was measured', () => {
    const reevaluations = [
      { evaluation_date: '2026-09-19', weight_kg: '79.20' },
      { evaluation_date: '2026-09-26', weight_kg: '79.60' },
      { evaluation_date: '2026-10-03', weight_kg: '80.00' },
    ]
    const shaped = shapeTrends([], reevaluations, 14, {
      weight: {
        weight_kg: '80.50',
        weight_measured_at: '2026-10-04T12:09:12.243+00:00',
        weight_instant_source: 'measured',
      },
      timezone: 'America/Sao_Paulo',
    })
    expect(shaped.weights).toEqual([
      { date: '2026-09-19', weight_kg: 79.2 },
      { date: '2026-09-26', weight_kg: 79.6 },
      { date: '2026-10-03', weight_kg: 80 },
      { date: '2026-10-04', weight_kg: 80.5 },
    ])
  })

  it('dates the app weight on the patient calendar, not in UTC', () => {
    // 01:30 UTC on 5 Oct is still 22:30 on 4 Oct in São Paulo.
    const shaped = shapeTrends([], [], 14, {
      weight: { weight_kg: 80.5, weight_measured_at: '2026-10-05T01:30:00Z', weight_instant_source: 'measured' },
      timezone: 'America/Sao_Paulo',
    })
    expect(shaped.weights).toEqual([{ date: '2026-10-04', weight_kg: 80.5 }])
  })

  it('replaces a reevaluation of the same day and never rewrites an older point', () => {
    const sameDay = shapeTrends([], [{ evaluation_date: '2026-10-04', weight_kg: '80.00' }], 14, {
      weight: { weight_kg: '80.50', weight_measured_at: '2026-10-04T12:09:12Z', weight_instant_source: 'measured' },
      timezone: 'America/Sao_Paulo',
    })
    expect(sameDay.weights).toEqual([{ date: '2026-10-04', weight_kg: 80.5 }])

    // A profile weight older than the last reevaluation is not the newest
    // reading: the series stays as the reevaluations tell it.
    const older = shapeTrends([], [{ evaluation_date: '2026-10-03', weight_kg: '80.00' }], 14, {
      weight: { weight_kg: '103.00', weight_measured_at: '2026-10-01T16:15:33Z', weight_instant_source: 'measured' },
      timezone: 'America/Sao_Paulo',
    })
    expect(older.weights).toEqual([{ date: '2026-10-03', weight_kg: 80 }])
  })

  it('leaves out an undated or missing profile weight', () => {
    const base = [{ evaluation_date: '2026-10-03', weight_kg: '80.00' }]
    const measured = { weight_instant_source: 'measured' }
    for (const weight of [
      null,
      { ...measured, weight_kg: null, weight_measured_at: '2026-10-04T12:00:00Z' },
      { ...measured, weight_kg: '80.50', weight_measured_at: null },
      { ...measured, weight_kg: '80.50', weight_measured_at: 'not a date' },
      // Only the time the value was written is known: not the measurement day.
      { weight_kg: '80.50', weight_measured_at: '2026-10-04T12:00:00Z', weight_instant_source: 'recorded' },
      { weight_kg: '80.50', weight_measured_at: '2026-10-04T12:00:00Z', weight_instant_source: null },
    ]) {
      expect(shapeTrends([], base, 14, { weight, timezone: 'America/Sao_Paulo' }).weights).toEqual([
        { date: '2026-10-03', weight_kg: 80 },
      ])
    }
    expect(
      shapeTrends([], base, 14, {
        weight: { ...measured, weight_kg: '80.50', weight_measured_at: '2026-10-04T12:00:00Z' },
        timezone: 'Not/AZone',
      }).weights,
    ).toEqual([{ date: '2026-10-03', weight_kg: 80 }])
    // An empty timezone falls back to UTC instead of dropping the point.
    expect(
      shapeTrends([], base, 14, {
        weight: { ...measured, weight_kg: '80.50', weight_measured_at: '2026-10-04T12:00:00Z' },
        timezone: '',
      }).weights.at(-1),
    ).toEqual({ date: '2026-10-04', weight_kg: 80.5 })
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


describe('Roberto liquid quantity presentation', () => {
  it('projects reference volume without trusting legacy display or changing canonical grams/macros', () => {
    const proposal=sanitizePendingProposal({kind:'meal',items:[{name:'leite integral',quantity_g:200,kcal:122,display_qty:200,display_unit:'ml'},{name:'whey protein em pó',quantity_g:30,kcal:105.6}]})
    expect(proposal.items?.[0]).toMatchObject({quantity_g:200,kcal:122,quantity_display:{unit:'mL',grams_per_unit:1.03,reference_id:'fao-infoods-v2-whole-milk-tb',estimated:true}})
    expect(proposal.items?.[1]).toMatchObject({
      quantity_g:30,
      kcal:105.6,
      quantity_display:{unit:'scoop',grams_per_unit:30,reference_id:'app-household-whey-scoop-v1',estimated:true},
    })
  })
})
