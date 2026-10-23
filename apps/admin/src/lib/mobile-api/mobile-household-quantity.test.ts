import { resolveDraftItem } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import { createMealDraft, type MealDraftDependencies } from './meal-draft-service'
import type { MediaAssetRecord } from './media-service'
import { mobileDraftQuantity, mobileQuantityFields } from './mobile-quantity-display'

const whey = {
  unit: 'scoop',
  grams_per_unit: 30,
  reference_id: 'app-household-whey-scoop-v1',
  estimated: true,
}
const bread = {
  unit: 'unit',
  grams_per_unit: 30,
  reference_id: 'app-household-cheese-bread-unit-v1',
  estimated: true,
}
const milk = {
  unit: 'mL',
  grams_per_unit: 1.03,
  reference_id: 'fao-infoods-v2-whole-milk-tb',
  estimated: true,
}
const assetID = '0d0d0d0d-0000-4000-8000-0000000000a1'

function dependencies(kind?: 'meal_photo' | 'audio_note', result?: unknown): MealDraftDependencies {
  return {
    media: {
      async findOwned(userId, id) {
        return kind && userId === 'patient-a' && id === assetID
          ? ({
              id,
              user_id: userId,
              kind,
              status: 'processed',
              processing_result: result,
            } as MediaAssetRecord)
          : null
      },
    },
    extractor: null,
    confidenceThreshold: async () => 0.6,
  }
}

describe('Roberto23/10 exact household measure screenshots, mobile only', () => {
  it('pão de queijo com requeijão240g/8unidades keeps mass and exposes an editable30g unit reference', () => {
    const candidate = resolveDraftItem(
      { name: 'pão de queijo com requeijão', grams_stated: 240, count: 8, unit: 'unidade' },
      0,
    )!
    expect(mobileDraftQuantity(candidate)).toMatchObject({
      quantity_g: 240,
      count: 8,
      quantity_basis: 'stated',
      quantity_display: bread,
    })
  })

  it.each([
    '1 caneca de leite',
    'uma caneca de leite',
  ])('standalone %s needs no patient knowledge of grams', async (text) => {
    const draft = await createMealDraft(dependencies(), 'patient-a', { source: 'text', text })
    expect(draft.items).toMatchObject([
      {
        name: 'leite',
        quantity_g: 206,
        quantity_basis: 'portion_reference',
        quantity_display: milk,
        needs_review: true,
      },
    ])
  })

  it.each([
    '1 medida de whey',
    'uma medida de whey',
    '1 dose de whey',
  ])('standalone %s uses an editable scoop, not a universal brand weight', async (text) => {
    const draft = await createMealDraft(dependencies(), 'patient-a', { source: 'text', text })
    expect(draft.items).toMatchObject([
      {
        name: 'whey',
        quantity_g: 30,
        quantity_basis: 'portion_reference',
        quantity_display: whey,
        needs_review: true,
      },
    ])
  })

  it('owned audio with separate caneca and medida keeps both ingredient identities', async () => {
    const draft = await createMealDraft(
      dependencies('audio_note', { text: '1 caneca de leite;1 medida de whey' }),
      'patient-a',
      { source: 'media', media_asset_id: assetID },
    )
    expect(draft.items).toMatchObject([
      { name: 'leite', quantity_g: 206, quantity_display: milk },
      { name: 'whey', quantity_g: 30, quantity_display: whey },
    ])
  })

  it('photo literal leite stays leite, gets volume presentation and never guesses missing amounts', async () => {
    const draft = await createMealDraft(
      dependencies('meal_photo', {
        items: [
          { name: 'leite', quantity_g_estimate: 206, confidence: 0.9 },
          { name: 'whey', confidence: 0.9 },
        ],
      }),
      'patient-a',
      { source: 'media', media_asset_id: assetID },
    )
    expect(draft.items).toMatchObject([
      { name: 'leite', quantity_g: 206, quantity_basis: 'visual_estimate', quantity_display: milk },
      { name: 'whey', quantity_g: null, quantity_basis: 'missing', quantity_display: whey },
    ])
  })

  it('explicit25g whey and old200g milk never become default30g or206g', () => {
    for (const [name, grams, display] of [
      ['whey', 25, whey],
      ['leite', 200, milk],
    ] as const) {
      expect(
        mobileDraftQuantity(
          resolveDraftItem(
            { name, grams_stated: grams, count: 1, unit: name === 'whey' ? 'medida' : 'caneca' },
            0,
          )!,
        ),
      ).toMatchObject({
        name,
        quantity_g: grams,
        quantity_basis: 'stated',
        quantity_display: display,
      })
    }
  })

  it('two measures are60g; an unknown spoon or brand still has no inferred mass', async () => {
    const draft = await createMealDraft(dependencies(), 'patient-a', {
      source: 'text',
      text: '2 medidas de whey',
    })
    expect(draft.items).toMatchObject([{ quantity_g: 60, quantity_display: whey }])
    for (const [name, unit] of [
      ['arroz', 'colher'],
      ['whey Marca X', 'medida'],
      ['leite de coco', 'caneca'],
    ]) {
      expect(mobileDraftQuantity(resolveDraftItem({ name, count: 1, unit }, 0)!)).toMatchObject({
        quantity_g: null,
        quantity_basis: 'missing',
      })
      expect(mobileQuantityFields(name)).toEqual({})
    }
  })

  it('canonical projection only adds presentation: never assumes a serving from the name', () => {
    expect(mobileQuantityFields('pão de queijo com requeijão')).toEqual({ quantity_display: bread })
    expect(mobileDraftQuantity(resolveDraftItem({ name: 'whey' }, 0)!)).toMatchObject({
      quantity_g: null,
      quantity_basis: 'missing',
    })
  })

  it.each([
    ['1 medida de whey Marca X', 'whey', 'medida'],
    ['1 caneca de leite de coco', 'leite', 'caneca'],
    ['1 porção de whey', 'whey', 'medida'],
  ])('an extractor cannot create household reference provenance from %s', async (text, name, unit) => {
    const deps = dependencies()
    deps.extractor = {
      async extract() {
        return { model: 'synthetic-test', items: [{ name, count: 1, unit }] }
      },
    }
    const draft = await createMealDraft(deps, 'patient-a', { source: 'text', text })
    expect(draft.items).toMatchObject([{ quantity_g: null, quantity_basis: 'missing' }])
  })
})
