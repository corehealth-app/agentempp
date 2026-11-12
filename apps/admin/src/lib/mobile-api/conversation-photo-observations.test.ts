import { describe, expect, it } from 'vitest'
import {
  conversationMealMediaAnalysis,
  conversationPhotoDomainAllowed,
} from './conversation-photo-observations'

const meal = {
  schema: 'conversation.image-result.v1',
  status: 'ready',
  classification: 'meal',
  analysis: { type: 'meal', items: [{ name: 'arroz', quantity_g_estimate: 100, confidence: 0.9 }] },
}
const label = {
  schema: 'conversation.image-result.v1',
  status: 'ready',
  classification: 'nutrition_label',
  analysis: {
    type: 'nutrition_label',
    product_name: 'whey',
    serving_size_g: 30,
    per_serving: { kcal: 120, protein_g: 24, carbs_g: 3, fat_g: 1 },
    per_100g: { kcal: 400, protein_g: 80, carbs_g: 10, fat_g: 3.3 },
    confidence: 0.9,
  },
}
describe('ordinary picture observations never replace frozen processing or consumed amount', () => {
  it('extracts the validated meal while leaving the complete original envelope unchanged', () => {
    const raw = structuredClone(meal),
      before = JSON.stringify(raw)
    expect(
      conversationMealMediaAnalysis({ kind: 'conversation_photo', processing_result: raw }),
    ).toEqual(meal.analysis)
    expect(JSON.stringify(raw)).toBe(before)
    expect(conversationPhotoDomainAllowed('conversation_photo', raw, 'meal.report')).toBe(true)
    expect(conversationPhotoDomainAllowed('conversation_photo', raw, 'workout.report')).toBe(false)
  })
  it('never uses a printed serving as a consumed amount or discards its consent-bearing label', () => {
    const raw = structuredClone(label),
      before = JSON.stringify(raw)
    expect(
      conversationMealMediaAnalysis({ kind: 'conversation_photo', processing_result: raw }),
    ).toEqual({
      type: 'meal',
      items: [{ name: 'whey', quantity_g_estimate: 0, confidence: 0.9 }],
      nutrition_label_visible: true,
      nutrition_label: label.analysis,
    })
    expect(JSON.stringify(raw)).toBe(before)
  })
  it.each([
    'body',
    'scale',
    'other',
    'unknown',
  ])('refuses unsupported %s as either domain', (classification) => {
    const raw = {
      schema: 'conversation.image-result.v1',
      status: 'unsupported',
      classification,
      reason: 'image_not_supported_for_conversation',
    }
    expect(conversationPhotoDomainAllowed('conversation_photo', raw, 'meal.report')).toBe(false)
    expect(conversationPhotoDomainAllowed('conversation_photo', raw, 'workout.report')).toBe(false)
    expect(() =>
      conversationMealMediaAnalysis({ kind: 'conversation_photo', processing_result: raw }),
    ).toThrow()
  })
  it.each([
    {},
    { ...meal, schema: 'unapproved' },
    { ...meal, classification: 'equipment' },
    { ...meal, signed_url: 'https://unit.invalid/private' },
  ])('refuses malformed or widened envelope %#', (raw) => {
    expect(conversationPhotoDomainAllowed('conversation_photo', raw, 'meal.report')).toBe(false)
    expect(() =>
      conversationMealMediaAnalysis({ kind: 'conversation_photo', processing_result: raw }),
    ).toThrow()
  })
  it('preserves older raw processing unchanged and does not promote clinical media', () => {
    expect(
      conversationMealMediaAnalysis({ kind: 'meal_photo', processing_result: meal.analysis }),
    ).toEqual(meal.analysis)
    for (const domain of ['meal.report', 'workout.report'] as const)
      expect(conversationPhotoDomainAllowed('body_checkin_photo', meal, domain)).toBe(false)
    expect(conversationPhotoDomainAllowed('meal_photo', meal.analysis, 'workout.report')).toBe(
      false,
    )
  })
})

it.each([
  null,
  '',
  ' ',
  'x'.repeat(241),
])('does not admit a label without usable product identity (%#)', (product_name) => {
  expect(
    conversationPhotoDomainAllowed(
      'conversation_photo',
      { ...label, analysis: { ...label.analysis, product_name } },
      'meal.report',
    ),
  ).toBe(false)
})
