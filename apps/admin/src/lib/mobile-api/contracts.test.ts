import { describe, expect, it } from 'vitest'
import {
  createReminderInputSchema,
  historyQuerySchema,
  hydrationInputSchema,
  idempotencyKeySchema,
  markRoutineTakenInputSchema,
  mediaUploadInputSchema,
  mobileDeviceInputSchema,
  notificationPreferencesPatchSchema,
  onboardingInputSchema,
  patchMeInputSchema,
  patchReminderInputSchema,
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

  it('accepts only bounded hexadecimal APNs device tokens', () => {
    expect(
      mobileDeviceInputSchema.parse({
        installation_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
        apns_environment: 'sandbox',
        apns_token: 'A'.repeat(64),
      }),
    ).toMatchObject({ apns_environment: 'sandbox', apns_token: 'a'.repeat(64) })

    expect(() =>
      mobileDeviceInputSchema.parse({
        installation_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
        apns_environment: 'sandbox',
        apns_token: 'g'.repeat(64),
      }),
    ).toThrow()
    expect(() =>
      mobileDeviceInputSchema.parse({
        installation_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
        apns_environment: 'production',
        apns_token: 'a'.repeat(63),
        user_id: 'forbidden',
      }),
    ).toThrow()
  })

  it('treats quiet hours as one atomic preference', () => {
    expect(
      notificationPreferencesPatchSchema.parse({
        quiet_hours: { start: '22:00', end: '07:00' },
        daily_push_limit: 6,
        hydration_target_ml: 2400,
      }),
    ).toEqual({
      quiet_hours: { start: '22:00', end: '07:00' },
      daily_push_limit: 6,
      hydration_target_ml: 2400,
    })
    expect(notificationPreferencesPatchSchema.parse({ quiet_hours: null })).toEqual({
      quiet_hours: null,
    })
    expect(() =>
      notificationPreferencesPatchSchema.parse({ quiet_hours: { start: '22:00' } }),
    ).toThrow()
    expect(() =>
      notificationPreferencesPatchSchema.parse({
        quiet_hours: { start: '22:00', end: '22:00' },
      }),
    ).toThrow()
  })

  it('validates reminder ownership references and unique weekdays', () => {
    expect(
      createReminderInputSchema.parse({
        category: 'meal',
        meal_type: 'jantar',
        local_time: '20:30',
        weekdays: [1, 2, 3, 4, 5],
      }),
    ).toMatchObject({ category: 'meal', meal_type: 'jantar' })
    expect(
      createReminderInputSchema.parse({
        category: 'supplement',
        routine_item_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
        local_time: '08:00',
        weekdays: [0, 6],
      }),
    ).toMatchObject({ category: 'supplement' })

    expect(() =>
      createReminderInputSchema.parse({
        category: 'meal',
        local_time: '20:30',
        weekdays: [1],
      }),
    ).toThrow()
    expect(() =>
      createReminderInputSchema.parse({
        category: 'hydration',
        routine_item_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
        local_time: '08:00',
        weekdays: [1, 1],
      }),
    ).toThrow()
  })

  it('keeps reminder identity immutable while allowing schedule edits', () => {
    expect(
      patchReminderInputSchema.parse({ local_time: '09:15', weekdays: [1, 3, 5], active: false }),
    ).toEqual({ local_time: '09:15', weekdays: [1, 3, 5], active: false })
    expect(() => patchReminderInputSchema.parse({})).toThrow()
    expect(() => patchReminderInputSchema.parse({ category: 'meal' })).toThrow()
  })

  it('bounds hydration and routine adherence timestamps', () => {
    expect(
      hydrationInputSchema.parse({
        amount_ml: 350,
        occurred_at: '2026-07-20T12:00:00-04:00',
      }),
    ).toEqual({ amount_ml: 350, occurred_at: '2026-07-20T12:00:00-04:00' })
    expect(() => hydrationInputSchema.parse({ amount_ml: 350 })).toThrow()
    expect(() => hydrationInputSchema.parse({ amount_ml: 0 })).toThrow()
    expect(() => hydrationInputSchema.parse({ amount_ml: 5001 })).toThrow()
    expect(markRoutineTakenInputSchema.parse({ occurred_at: '2026-07-20T12:00:00-04:00' })).toEqual(
      { occurred_at: '2026-07-20T12:00:00-04:00' },
    )
    expect(() => markRoutineTakenInputSchema.parse({})).toThrow()
    expect(() => markRoutineTakenInputSchema.parse({ occurred_at: 'today' })).toThrow()
  })
})
