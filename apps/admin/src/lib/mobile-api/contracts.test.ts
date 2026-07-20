import { describe, expect, it } from 'vitest'
import {
  historyQuerySchema,
  idempotencyKeySchema,
  mediaUploadInputSchema,
  onboardingInputSchema,
  patchMeInputSchema,
  registrationProposalInputSchema,
} from './contracts'

describe('mobile API v1 contracts', () => {
  it('accepts a structured meal proposal without client supplied macros', () => {
    const parsed = registrationProposalInputSchema.parse({
      kind: 'meal',
      meal_type: 'jantar',
      items: [{ food_name: 'arroz branco cozido', quantity_g: 120 }],
    })

    expect(parsed).toEqual({
      kind: 'meal',
      meal_type: 'jantar',
      items: [{ food_name: 'arroz branco cozido', quantity_g: 120 }],
    })
  })

  it('rejects nutrition totals supplied by the mobile client', () => {
    expect(() =>
      registrationProposalInputSchema.parse({
        kind: 'meal',
        meal_type: 'jantar',
        items: [{ food_name: 'arroz', quantity_g: 120, kcal: 999 }],
      }),
    ).toThrow()
  })

  it('accepts only the public editable me fields', () => {
    expect(
      patchMeInputSchema.parse({
        name: 'Paciente Teste',
        locale: 'pt-BR',
        timezone: 'America/New_York',
        country: 'US',
      }),
    ).toEqual({
      name: 'Paciente Teste',
      locale: 'pt-BR',
      timezone: 'America/New_York',
      country: 'US',
    })

    expect(() => patchMeInputSchema.parse({ admin_notes: 'forbidden' })).toThrow()
  })

  it('requires opaque bounded idempotency keys', () => {
    expect(idempotencyKeySchema.parse('mobile-018f2c34-abcdef')).toBe('mobile-018f2c34-abcdef')
    expect(() => idempotencyKeySchema.parse('short')).toThrow()
    expect(() => idempotencyKeySchema.parse('line\nbreak-123')).toThrow()
  })

  it('bounds mobile history pagination', () => {
    expect(historyQuerySchema.parse({}).limit).toBe(30)
    expect(historyQuerySchema.parse({ limit: '100' }).limit).toBe(100)
    expect(() => historyQuerySchema.parse({ limit: '101' })).toThrow()
  })

  it('validates onboarding measurements at the public boundary', () => {
    expect(
      onboardingInputSchema.parse({
        height_cm: 180,
        weight_kg: 82,
        training_frequency: 0,
        wake_time: '07:30',
      }),
    ).toMatchObject({ training_frequency: 0 })
    expect(() => onboardingInputSchema.parse({ height_cm: 70 })).toThrow()
    expect(() => onboardingInputSchema.parse({ wake_time: '27:00' })).toThrow()
  })

  it('accepts bounded patient media uploads with optional photo context', () => {
    expect(
      mediaUploadInputSchema.parse({
        kind: 'meal_photo',
        mime_type: 'image/jpeg',
        size_bytes: 2_048_000,
        context_text: 'Jantar: frango grelhado com arroz.',
      }),
    ).toEqual({
      kind: 'meal_photo',
      mime_type: 'image/jpeg',
      size_bytes: 2_048_000,
      context_text: 'Jantar: frango grelhado com arroz.',
    })
  })

  it('keeps content covers and mismatched media outside the patient upload contract', () => {
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'content_cover',
        mime_type: 'image/jpeg',
        size_bytes: 100,
      }),
    ).toThrow()
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'audio_note',
        mime_type: 'image/jpeg',
        size_bytes: 100,
      }),
    ).toThrow()
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'meal_photo',
        mime_type: 'image/svg+xml',
        size_bytes: 100,
      }),
    ).toThrow()
  })

  it('rejects oversized media, unbounded context, and unknown fields', () => {
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'meal_photo',
        mime_type: 'image/jpeg',
        size_bytes: 15 * 1024 * 1024 + 1,
      }),
    ).toThrow()
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'audio_note',
        mime_type: 'audio/mpeg',
        size_bytes: 25 * 1024 * 1024 + 1,
      }),
    ).toThrow()
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'gym_photo',
        mime_type: 'image/png',
        size_bytes: 100,
        context_text: 'x'.repeat(1001),
      }),
    ).toThrow()
    expect(() =>
      mediaUploadInputSchema.parse({
        kind: 'gym_photo',
        mime_type: 'image/png',
        size_bytes: 100,
        user_id: 'forbidden',
      }),
    ).toThrow()
  })
})
