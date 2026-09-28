import { describe, expect, it } from 'vitest'
import { registrationProposalInputSchema } from './contracts'
import { sanitizePendingProposal } from './read-model'
import { buildMealPendingProposal, mealItemsForCalculation } from './registration-service'

const patientA = '11111111-1111-4111-8111-111111111111'
const patientB = '22222222-2222-4222-8222-222222222222'
const photoId = '0d0d0d0d-0000-4000-8000-0000000000a1'

const label = {
  product_name: 'Iogurte Natural Integral',
  serving_size_g: 170,
  per_serving: { kcal: 110, protein_g: 6, carbs_g: 9, fat_g: 5.5 },
  per_100g: { kcal: null, protein_g: null, carbs_g: null, fat_g: null },
  confidence: 0.92,
}

function mediaRow(over: Record<string, unknown> = {}) {
  return {
    id: photoId,
    user_id: patientA,
    kind: 'meal_photo',
    bucket_id: 'meal-photos',
    object_path: `${patientA}/${photoId}.jpg`,
    mime_type: 'image/jpeg',
    declared_size_bytes: 1000,
    actual_size_bytes: 1000,
    status: 'processed',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: '2026-10-28T00:00:00+00:00',
    uploaded_at: '2026-09-28T00:00:00+00:00',
    processed_at: '2026-09-28T00:00:10+00:00',
    deleted_at: null,
    processing_result: { type: 'meal', items: [], nutrition_label: label },
    created_at: '2026-09-28T00:00:00+00:00',
    updated_at: '2026-09-28T00:00:10+00:00',
    ...over,
  }
}

/** A service client that only knows the rows it was given, filtered like the real query. */
function supabase(rows: Array<Record<string, unknown>>, threshold: unknown = null) {
  const queries: Array<Record<string, string>> = []
  return {
    queries,
    client: {
      from(table: string) {
        const filters: Record<string, string> = { table }
        const builder = {
          select: () => builder,
          eq(column: string, value: string) {
            filters[column] = value
            return builder
          },
          async maybeSingle() {
            queries.push(filters)
            if (table === 'global_config') {
              return { data: threshold == null ? null : { value: threshold }, error: null }
            }
            const row = rows.find(
              (item) => item.id === filters.id && item.user_id === filters.user_id,
            )
            return { data: row ?? null, error: null }
          },
        }
        return builder
      },
    } as never,
  }
}

function meal(over: Record<string, unknown>) {
  const parsed = registrationProposalInputSchema.parse({
    kind: 'meal',
    meal_type: 'lanche',
    items: [{ food_name: 'iogurte natural', quantity_g: 170 }],
    ...over,
  })
  if (parsed.kind !== 'meal') throw new Error('test setup')
  return parsed
}

describe('meal proposal contract with source', () => {
  const base = { kind: 'meal', meal_type: 'lanche', items: [{ food_name: 'ovo', quantity_g: 100 }] }

  it('stays compatible with a request without source', () => {
    expect(registrationProposalInputSchema.safeParse(base).success).toBe(true)
  })

  it.each([
    [{ source: { channel: 'text' } }, true],
    [{ source: { channel: 'camera', media_asset_id: photoId } }, true],
    [{ source: { channel: 'audio_import', media_asset_id: photoId } }, true],
    [{ source: { channel: 'text', media_asset_id: photoId } }, false],
    [{ source: { channel: 'gallery' } }, false],
    [{ source: { channel: 'whatsapp' } }, false],
    [{ source: { channel: 'camera', media_asset_id: photoId, user_id: patientB } }, false],
  ])('%j -> %s', (over, valid) => {
    expect(registrationProposalInputSchema.safeParse({ ...base, ...over }).success).toBe(valid)
  })

  it('never accepts macros from the client and allows the label on one photo item only', () => {
    const photo = { channel: 'gallery', media_asset_id: photoId }
    const item = { food_name: 'iogurte', quantity_g: 170 }
    const parse = (value: unknown) => registrationProposalInputSchema.safeParse(value).success

    expect(parse({ ...base, items: [{ ...item, kcal: 110 }] })).toBe(false)
    expect(parse({ ...base, items: [{ ...item, protein_g: 6 }] })).toBe(false)
    expect(parse({ ...base, source: photo, items: [{ ...item, use_nutrition_label: true }] })).toBe(true)
    expect(parse({ ...base, source: photo, items: [{ ...item, use_nutrition_label: false }] })).toBe(false)
    expect(
      parse({
        ...base,
        source: photo,
        items: [
          { ...item, use_nutrition_label: true },
          { food_name: 'granola', quantity_g: 30, use_nutrition_label: true },
        ],
      }),
    ).toBe(false)
    expect(parse({ ...base, items: [{ ...item, use_nutrition_label: true }] })).toBe(false)
    expect(
      parse({
        ...base,
        source: { channel: 'audio_recording', media_asset_id: photoId },
        items: [{ ...item, use_nutrition_label: true }],
      }),
    ).toBe(false)
  })
})

describe('meal items for calculation', () => {
  it('passes items through untouched when there is no media', async () => {
    const { client, queries } = supabase([])
    await expect(
      mealItemsForCalculation(client, patientA, meal({ source: { channel: 'text' } })),
    ).resolves.toEqual([{ food_name: 'iogurte natural', quantity_g: 170 }])
    expect(queries).toEqual([])
  })

  it('applies the label the server reads again, only to the chosen item', async () => {
    const { client } = supabase([mediaRow()])
    const items = await mealItemsForCalculation(
      client,
      patientA,
      meal({
        source: { channel: 'camera', media_asset_id: photoId },
        items: [
          { food_name: 'granola', quantity_g: 30 },
          { food_name: 'iogurte natural', quantity_g: 85, use_nutrition_label: true },
        ],
      }),
    )
    expect(items).toEqual([
      { food_name: 'granola', quantity_g: 30 },
      {
        food_name: 'iogurte natural',
        quantity_g: 85,
        // 110 kcal per 170 g -> 64.71 per 100 g -> 85 g
        approved_nutrition: {
          source: 'product_label',
          kcal: 55,
          protein_g: 3,
          carbs_g: 4.5,
          fat_g: 2.75,
        },
      },
    ])
  })

  it("another patient's media does not exist", async () => {
    const { client, queries } = supabase([mediaRow()])
    await expect(
      mealItemsForCalculation(
        client,
        patientB,
        meal({ source: { channel: 'camera', media_asset_id: photoId } }),
      ),
    ).rejects.toMatchObject({ status: 404, code: 'media_asset_not_found' })
    expect(queries[0]).toMatchObject({ id: photoId, user_id: patientB })
  })

  it.each([
    [{ status: 'processing', processed_at: null }, { channel: 'camera' }, 409, 'media_not_processed'],
    [{ status: 'deleted' }, { channel: 'camera' }, 404, 'media_asset_not_found'],
    [{ kind: 'audio_note' }, { channel: 'gallery' }, 422, 'media_kind_not_supported'],
    [{}, { channel: 'audio_recording' }, 422, 'media_kind_not_supported'],
    [{ kind: 'gym_photo' }, { channel: 'camera' }, 422, 'media_kind_not_supported'],
  ])('refuses media %j on %j', async (row, source, status, code) => {
    const { client } = supabase([mediaRow(row)])
    await expect(
      mealItemsForCalculation(
        client,
        patientA,
        meal({ source: { ...source, media_asset_id: photoId } }),
      ),
    ).rejects.toMatchObject({ status, code })
  })

  it.each([
    ['no label in the photo', { type: 'meal', items: [] }],
    ['low confidence', { nutrition_label: { ...label, confidence: 0.4 } }],
    [
      'incomplete values',
      {
        nutrition_label: {
          ...label,
          per_serving: { kcal: 110, protein_g: null, carbs_g: 9, fat_g: 5.5 },
        },
      },
    ],
  ])('a label that cannot be trusted refuses the proposal (%s)', async (_name, result) => {
    const { client } = supabase([mediaRow({ processing_result: result })])
    await expect(
      mealItemsForCalculation(
        client,
        patientA,
        meal({
          source: { channel: 'gallery', media_asset_id: photoId },
          items: [{ food_name: 'iogurte natural', quantity_g: 170, use_nutrition_label: true }],
        }),
      ),
    ).rejects.toMatchObject({ status: 422, code: 'nutrition_label_not_applicable' })
  })

  it("the label and the patient's own calories cannot both apply", async () => {
    const { client } = supabase([mediaRow()])
    await expect(
      mealItemsForCalculation(
        client,
        patientA,
        meal({
          source: { channel: 'gallery', media_asset_id: photoId },
          items: [
            { food_name: 'iogurte', quantity_g: 170, user_kcal: 90, use_nutrition_label: true },
          ],
        }),
      ),
    ).rejects.toMatchObject({ status: 422, code: 'nutrition_label_not_applicable' })
  })
})

describe('pending proposal keeps the origin', () => {
  it('stores and exposes channel, media and quantity basis; nothing internal', () => {
    const input = meal({
      source: { channel: 'gallery', media_asset_id: photoId },
      items: [
        {
          food_name: 'iogurte natural',
          quantity_g: 170,
          quantity_basis: 'visual_estimate',
          candidate_id: 'c1-0a1b2c3d',
          use_nutrition_label: true,
        },
        { food_name: 'ovo', quantity_g: 100, quantity_basis: 'portion_reference' },
      ],
    })
    const calculated = (name: string, quantity: number, kcal: number, source: string) => ({
      food_name: name,
      matched_taco_name: name,
      matched_taco_id: null,
      quantity_g: quantity,
      kcal,
      protein_g: 1,
      carbs_g: 1,
      fat_g: 1,
      fiber_g: 0,
      similarity: 1,
      source,
    })
    const proposal = buildMealPendingProposal(
      input,
      {
        items: [
          calculated('iogurte natural', 170, 110, 'product_label'),
          calculated('ovo', 100, 143, 'canonical_exact'),
        ],
        totals: { kcal: 253, protein_g: 2, carbs_g: 2, fat_g: 2, fiber_g: 0 },
        warnings: [],
        user_warnings: [],
        audit_warnings: ['internal'],
      } as never,
      {
        requestKey: 'key-12345678',
        timestamp: '2026-09-28T12:00:00.000Z',
        timezone: 'America/Sao_Paulo',
        localDate: '2026-09-28',
      },
    )
    expect(proposal).toMatchObject({
      sourceContentType: 'gallery',
      source_media_asset_id: photoId,
    })

    const dto = sanitizePendingProposal(proposal as never) as {
      source: unknown
      items: Array<Record<string, unknown>>
    }
    expect(dto.source).toEqual({ channel: 'gallery', media_asset_id: photoId })
    expect(dto.items.map((item) => [item.nutrition_source, item.quantity_basis])).toEqual([
      ['product_label', 'visual_estimate'],
      ['canonical_exact', 'portion_reference'],
    ])
    expect(JSON.stringify(dto)).not.toMatch(/internal|key-12345678|candidate_id/)
  })
})
