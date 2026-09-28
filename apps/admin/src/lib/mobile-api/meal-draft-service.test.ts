import { describe, expect, it } from 'vitest'
import { mealDraftInputSchema } from './contracts'
import {
  createMealDraft,
  type MealDraftDependencies,
  type MealTextExtractor,
} from './meal-draft-service'
import type { MediaAssetRecord } from './media-service'

const assetId = '0d0d0d0d-0000-4000-8000-0000000000a1'

function asset(over: Partial<MediaAssetRecord>): MediaAssetRecord {
  return {
    id: assetId,
    user_id: 'patient-a',
    kind: 'meal_photo',
    status: 'processed',
    processing_result: null,
    ...over,
  } as MediaAssetRecord
}

function deps(options: {
  assets?: MediaAssetRecord[]
  extractor?: MealTextExtractor | null
}): MealDraftDependencies & { lookups: Array<[string, string]> } {
  const lookups: Array<[string, string]> = []
  return {
    lookups,
    media: {
      async findOwned(userId, id) {
        lookups.push([userId, id])
        return (
          (options.assets ?? []).find((item) => item.id === id && item.user_id === userId) ?? null
        )
      },
    },
    extractor: options.extractor ?? null,
    confidenceThreshold: async () => 0.6,
  }
}

describe('meal draft contract', () => {
  it('accepts text or one media asset, nothing else', () => {
    expect(mealDraftInputSchema.safeParse({ source: 'text', text: '2 ovos' }).success).toBe(true)
    expect(mealDraftInputSchema.safeParse({ source: 'media', media_asset_id: assetId }).success).toBe(true)
    for (const invalid of [
      { source: 'text', text: '   ' },
      { source: 'text', text: 'x'.repeat(2001) },
      { source: 'text', text: '2 ovos', items: [{ name: 'ovo', kcal: 70 }] },
      { source: 'media', media_asset_id: 'not-a-uuid' },
      { source: 'media', media_asset_id: assetId, user_id: 'patient-b' },
      { source: 'photo', media_asset_id: assetId },
    ]) {
      expect(mealDraftInputSchema.safeParse(invalid).success).toBe(false)
    }
  })
})

describe('meal draft from text', () => {
  it('reads "alimento + gramas" without any provider call', async () => {
    let called = false
    const draft = await createMealDraft(
      deps({
        extractor: {
          async extract() {
            called = true
            return { items: [], model: 'x' }
          },
        },
      }),
      'patient-a',
      { source: 'text', text: 'Arroz branco 150 g\nFeijão carioca 86,5 g' },
    )
    expect(called).toBe(false)
    expect(draft.extraction).toEqual({ method: 'deterministic', model: null })
    expect(draft.items).toMatchObject([
      { name: 'Arroz branco', quantity_g: 150, quantity_basis: 'stated' },
      { name: 'Feijão carioca', quantity_g: 86.5, quantity_basis: 'stated' },
    ])
    expect(JSON.stringify(draft)).not.toMatch(/kcal/)
  })

  it('"2 ovos e 1 prato de feijoada": reference for the egg, no invented grams for the dish', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {
      source: 'text',
      text: '2 ovos e 1 prato de feijoada',
    })
    expect(draft.items).toMatchObject([
      { name: 'ovos', quantity_g: 100, quantity_basis: 'portion_reference', needs_review: true },
      { name: 'prato de feijoada', quantity_g: null, quantity_basis: 'missing' },
    ])
  })

  it('sends only the unread part to the extractor and distrusts its quantities', async () => {
    const seen: string[] = []
    const draft = await createMealDraft(
      deps({
        extractor: {
          async extract({ text }) {
            seen.push(text)
            return {
              model: 'anthropic/claude-haiku-4.5',
              items: [
                { name: 'ovo mexido', count: 2, unit: 'unidade' },
                { name: 'pão francês', count: 1, grams_stated: 80 },
                { name: 'pizza', grams_stated: 300 },
              ],
            }
          },
        },
      }),
      'patient-a',
      { source: 'text', text: 'Frango 120 g; comi 2 ovos mexidos com um pão francês' },
    )
    expect(seen).toEqual(['comi 2 ovos mexidos com um pão francês'])
    expect(draft.extraction).toEqual({ method: 'llm_text', model: 'anthropic/claude-haiku-4.5' })
    expect(draft.items).toMatchObject([
      { name: 'Frango', quantity_g: 120, quantity_basis: 'stated' },
      { name: 'ovo mexido', quantity_g: 100, quantity_basis: 'portion_reference', count: 2 },
      // 80 g was never said: the reference applies, not the extractor's number.
      { name: 'pão francês', quantity_g: 50, quantity_basis: 'portion_reference', count: 1 },
    ])
  })

  it('a provider failure is a typed error, never an empty meal', async () => {
    await expect(
      createMealDraft(
        deps({
          extractor: {
            async extract() {
              throw new Error('provider secret detail')
            },
          },
        }),
        'patient-a',
        { source: 'text', text: 'comi bem no almoço' },
      ),
    ).rejects.toMatchObject({ status: 502, code: 'meal_extraction_failed', message: 'Meal extraction failed' })
  })
})

describe('meal draft from media', () => {
  const photo = asset({
    processing_result: {
      type: 'meal',
      meal_context: 'almoço em casa',
      nutrition_label_visible: true,
      items: [
        { name: 'iogurte natural', quantity_g_estimate: 170, confidence: 0.9 },
        { name: 'granola', quantity_g_estimate: 0, confidence: 0 },
      ],
      nutrition_label: {
        product_name: 'Iogurte Natural Integral',
        serving_size_g: 170,
        per_serving: { kcal: 110, protein_g: 6, carbs_g: 9, fat_g: 5.5 },
        per_100g: { kcal: null, protein_g: null, carbs_g: null, fat_g: null },
        confidence: 0.92,
      },
    },
  })

  it('maps the photo result and ties the label to the one matching candidate', async () => {
    const draft = await createMealDraft(deps({ assets: [photo] }), 'patient-a', {
      source: 'media',
      media_asset_id: assetId,
    })
    expect(draft).toMatchObject({
      source: 'photo',
      media_asset_id: assetId,
      context_note: 'almoço em casa',
      extraction: { method: 'vision', model: null },
    })
    expect(draft.items).toMatchObject([
      { name: 'iogurte natural', quantity_g: 170, quantity_basis: 'visual_estimate' },
      { name: 'granola', quantity_g: null, quantity_basis: 'missing' },
    ])
    expect(draft.nutrition_label).toMatchObject({
      product_name: 'Iogurte Natural Integral',
      applies_to_candidate_id: draft.items[0]?.candidate_id,
    })
  })

  it('reads the transcript of a recording and shows it back', async () => {
    const audio = asset({
      kind: 'audio_note',
      processing_result: { text: 'comi 2 ovos e 150 g de arroz', language: 'pt', duration: 4.2 },
    })
    const draft = await createMealDraft(deps({ assets: [audio] }), 'patient-a', {
      source: 'media',
      media_asset_id: assetId,
    })
    expect(draft.source).toBe('audio')
    expect(draft.transcript).toBe('comi 2 ovos e 150 g de arroz')
    expect(draft.items).toMatchObject([
      { name: 'arroz', quantity_g: 150, quantity_basis: 'stated' },
      { quantity_basis: 'portion_reference', quantity_g: 100 },
    ])
  })

  it("another patient's asset does not exist for this patient", async () => {
    const dependencies = deps({ assets: [photo] })
    await expect(
      createMealDraft(dependencies, 'patient-b', { source: 'media', media_asset_id: assetId }),
    ).rejects.toMatchObject({ status: 404, code: 'media_asset_not_found' })
    expect(dependencies.lookups).toEqual([['patient-b', assetId]])
  })

  it.each([
    [{ status: 'processing' }, 409, 'media_not_processed'],
    [{ status: 'uploaded' }, 409, 'media_not_processed'],
    [{ status: 'failed' }, 409, 'media_not_processed'],
    [{ status: 'deleted' }, 404, 'media_asset_not_found'],
    [{ kind: 'body_checkin_photo' }, 422, 'media_kind_not_supported'],
    [{ kind: 'gym_photo' }, 422, 'media_kind_not_supported'],
  ])('refuses %j', async (over, status, code) => {
    await expect(
      createMealDraft(deps({ assets: [asset(over as never)] }), 'patient-a', {
        source: 'media',
        media_asset_id: assetId,
      }),
    ).rejects.toMatchObject({ status, code })
  })

  it('an empty recording is refused', async () => {
    const audio = asset({ kind: 'audio_note', processing_result: { text: '   ' } })
    await expect(
      createMealDraft(deps({ assets: [audio] }), 'patient-a', {
        source: 'media',
        media_asset_id: assetId,
      }),
    ).rejects.toMatchObject({ status: 422, code: 'meal_draft_empty' })
  })
})
