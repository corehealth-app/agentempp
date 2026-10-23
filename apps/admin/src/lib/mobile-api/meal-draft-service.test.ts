import { describe, expect, it, vi } from 'vitest'
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
  it.each([
    'macarrao espaguete cozido 200 g; carne desfiada com molho e milho 180 g',
    'macarrão espaguete cozido 200 g\ncarne desfiada com molho e milho 180 g',
    'macarrao espaguete cozido 200 g, 180 g de carne desfiada com molho e milho',
  ])('Roberto23Oct text entry preserves the whole180g prepared dish: %s', async text => {
    const extract = vi.fn(async () => { throw new Error('unexpected extraction') })
    const draft = await createMealDraft(deps({ extractor: { extract } }), 'patient-a', { source: 'text', text })
    expect(extract).not.toHaveBeenCalled()
    expect(draft.items.map(item => [item.name, item.quantity_g, item.quantity_basis])).toEqual([
      [text.includes('macarrão') ? 'macarrão espaguete cozido' : 'macarrao espaguete cozido', 200, 'stated'],
      ['carne desfiada com molho e milho', 180, 'stated'],
    ])
    expect(new Set(draft.items.map(item => item.candidate_id)).size).toBe(2)
    expect(draft.extraction).toEqual({ method: 'deterministic', model: null })
    expect(JSON.stringify(draft)).not.toMatch(/kcal|protein_g/)
  })

  it('preserves a stated compound from owned audio without allocating its grams to milho', async () => {
    const extract = vi.fn(async () => { throw new Error('unexpected extraction') })
    const recording = asset({ kind: 'audio_note', processing_result: { text: '180,5 g de carne desfiada com molho e milho' } })
    const draft = await createMealDraft(deps({ assets: [recording], extractor: { extract } }), 'patient-a', { source: 'media', media_asset_id: assetId })
    expect(draft.items).toMatchObject([{ name: 'carne desfiada com molho e milho', quantity_g: 180.5, quantity_basis: 'stated' }])
    expect(draft.items).toHaveLength(1)
    expect(extract).not.toHaveBeenCalled()
  })

  it('keeps compound, counted foods and milk/whey in their original order', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', { source: 'text', text: '2 ovos e 1 pão francês; carne desfiada com molho e milho 180 g; 1 caneca de leite com uma medida de whey' })
    expect(draft.items.map(item => [item.name, item.quantity_g])).toEqual([
      ['ovos', 100], ['pão francês', 50], ['carne desfiada com molho e milho', 180], ['leite integral', 206], ['whey protein em pó', 30],
    ])
    expect(new Set(draft.items.map(item => item.candidate_id)).size).toBe(5)
  })

  it('does not extend the prepared-dish exception to an unknown ingredient or ambiguous additional weight', async () => {
    for (const text of ['carne desfiada com molho e zzunknown 180 g', 'carne desfiada com molho e milho 180 g 50 g']) {
      const seen: string[] = []
      const draft = await createMealDraft(deps({ extractor: { async extract({ text }) { seen.push(text); return { items: [], model: 'synthetic' } } } }), 'patient-a', { source: 'text', text })
      expect(draft.items).not.toContainEqual(expect.objectContaining({ name: 'carne desfiada com molho e milho', quantity_basis: 'stated' }))
      expect(seen.length + draft.items.length).toBeGreaterThan(0)
    }
  })

  it('never reassigns an internal ingredient weight to the whole prepared dish', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', { source: 'text', text: 'carne desfiada com molho 180 g e milho' })
    expect(draft.items.map(item => [item.name, item.quantity_g])).toEqual([
      ['carne desfiada com molho', 180], ['milho', null],
    ])
  })

  it.each(['-180 g', '-0,18 kg', '180 g 50 g'])('does not admit a negative or fragmented whole-dish weight: %s', async weight => {
    const draft = await createMealDraft(deps({}), 'patient-a', { source: 'text', text: `carne desfiada com molho e milho ${weight}` })
    expect(draft.items).not.toContainEqual(expect.objectContaining({ name: 'carne desfiada com molho e milho', quantity_basis: 'stated' }))
  })

  it('Roberto: a new household cup is200mL, not200g; whey remains30g powder', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {source:'text',text:'1 caneca de leite com uma medida de whey'})
    expect(draft.items[0]).toMatchObject({quantity_g:206,quantity_display:{unit:'mL',grams_per_unit:1.03,reference_id:'fao-infoods-v2-whole-milk-tb',estimated:true}})
    // New23/10 requirement: powder gets a scoop reference, never milk density.
    expect(draft.items[1]).toHaveProperty('quantity_display', {unit:'scoop',grams_per_unit:30,reference_id:'app-household-whey-scoop-v1',estimated:true})
    expect(draft.items[1]).toMatchObject({name:'whey protein em pó',quantity_g:30})
  })
  it('converts explicitly stated milk volume once, keeping a density reference basis', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {source:'text',text:'200 ml de leite'})
    expect(draft.items).toMatchObject([{quantity_g:206,quantity_basis:'portion_reference',count:200,unit_label:'ml',quantity_display:{unit:'mL',grams_per_unit:1.03}}])
  })
  it('does not reinterpret an old explicit200g as200mL', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {source:'text',text:'leite200g'})
    expect(draft.items).toMatchObject([{quantity_g:200,quantity_basis:'stated',quantity_display:{unit:'mL',grams_per_unit:1.03}}])
  })
  it('an unknown liquid volume never borrows whole milk density or becomes grams1:1', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {source:'text',text:'200ml de leite de coco'})
    expect(draft.items[0]).toMatchObject({quantity_g:null,quantity_basis:'missing',needs_review:true,review_reason:'missing_quantity'})
    expect(draft.items[0]).not.toHaveProperty('quantity_display')
  })

  it('Roberto 22/10: a caneca of milk with one whey measure yields two editable reference portions', async () => {
    const draft = await createMealDraft(deps({}), 'patient-a', {
      source: 'text', text: '1 caneca de leite com uma medida de whey',
    })
    expect(draft.items).toMatchObject([
      { name: 'leite integral', quantity_g: 206, quantity_basis: 'portion_reference', needs_review: true, review_reason: 'estimated_quantity' },
      { name: 'whey protein em pó', quantity_g: 30, quantity_basis: 'portion_reference', needs_review: true, review_reason: 'estimated_quantity' },
    ])
    expect(draft.items).toHaveLength(2)
    expect(new Set(draft.items.map(item => item.candidate_id)).size).toBe(2)
    expect(draft.extraction).toEqual({ method: 'deterministic', model: null })
  })

  it('the same literal household phrase from an owned audio transcript needs no invented extractor grams', async () => {
    const recording = asset({ kind: 'audio_note', processing_result: { text: '1 caneca de leite com uma medida de whey' } })
    const draft = await createMealDraft(deps({ assets: [recording] }), 'patient-a', { source: 'media', media_asset_id: assetId })
    expect(draft.source).toBe('audio')
    expect(draft.items.map(item => [item.name,item.quantity_g,item.quantity_basis,item.needs_review])).toEqual([
      ['leite integral',206,'portion_reference',true],['whey protein em pó',30,'portion_reference',true],
    ])
  })

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

  it('keeps the household drink before or after stated foods, with unique global candidate IDs', async () => {
    for(const [sourceText,names] of [
      ['1 caneca de leite com uma medida de whey; banana100g',['leite integral','whey protein em pó','banana']],
      ['banana100g;1 caneca de leite com uma medida de whey;Arroz150g',['banana','leite integral','whey protein em pó','Arroz']],
    ] as const) {
      const draft=await createMealDraft(deps({}),'patient-a',{source:'text',text:sourceText})
      expect(draft.items.map(item=>item.name)).toEqual(names)
      expect(new Set(draft.items.map(item=>item.candidate_id)).size).toBe(draft.items.length)
    }
  })

  it('keeps unread blocks around the drink in order without inventing a mapping for model output', async () => {
    const draft=await createMealDraft(deps({extractor:{async extract({text}) {
      if(text==='uma maçã') return {items:[{name:'maçã',count:1}],model:'synthetic-model'}
      if(text==='uma banana') return {items:[{name:'banana',count:1}],model:'synthetic-model'}
      return {items:[{name:'maçã',count:1},{name:'banana',count:1}],model:'synthetic-model'}
    }}}),'patient-a',{source:'text',text:'uma maçã;1 caneca de leite com uma medida de whey;uma banana'})
    expect(draft.items.map(item=>item.name)).toEqual(['maçã','leite integral','whey protein em pó','banana'])
    expect(new Set(draft.items.map(item=>item.candidate_id)).size).toBe(4)
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

  it('an SDK error class is logged by its class name even when .name is the generic "Error"', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      class APIConnectionTimeoutError extends Error {}
      await expect(
        createMealDraft(
          deps({
            extractor: {
              async extract() {
                throw new APIConnectionTimeoutError('timed out with detail')
              },
            },
          }),
          'patient-a',
          { source: 'text', text: 'comi bem no almoço' },
        ),
      ).rejects.toMatchObject({ code: 'meal_extraction_failed' })
      expect(spy.mock.calls[0]?.[1]).toEqual({
        error_name: 'APIConnectionTimeoutError',
        error_code: 'unknown',
        provider_status: null,
      })
    } finally {
      spy.mockRestore()
    }
  })

  it('a provider failure is logged by class and code only, never with the text or the detail', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const providerError = Object.assign(new Error('provider secret detail'), { status: 400 })
      await expect(
        createMealDraft(
          deps({
            extractor: {
              async extract() {
                throw providerError
              },
            },
          }),
          'patient-a',
          { source: 'text', text: 'comi bem no almoço' },
        ),
      ).rejects.toMatchObject({ code: 'meal_extraction_failed' })
      expect(spy).toHaveBeenCalledTimes(1)
      expect(spy.mock.calls[0]).toEqual([
        '[mobile-meal-drafts] extraction_failed',
        { error_name: 'Error', error_code: 'unknown', provider_status: 400 },
      ])
      const logged = JSON.stringify(spy.mock.calls)
      expect(logged).not.toContain('secret')
      expect(logged).not.toContain('almoço')
    } finally {
      spy.mockRestore()
    }
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
