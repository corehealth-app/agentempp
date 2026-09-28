import {
  contentListQuerySchema,
  contentReadInputSchema,
  contentSaveInputSchema,
  encodeContentCursor,
} from '@mpp/core'
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
  onboardingCompletionInputSchema,
  onboardingInputSchema,
  patchMeInputSchema,
  patchReminderInputSchema,
  personaInputSchema,
  registrationProposalInputSchema,
  resourceIdSchema,
} from './contracts'

describe('plan document upload', () => {
  it('accepts what the document reader handles and nothing else', () => {
    for (const mime of ['application/pdf', 'image/jpeg', 'image/png', 'image/webp']) {
      expect(
        mediaUploadInputSchema.safeParse({ kind: 'plan_document', mime_type: mime, size_bytes: 1024 })
          .success,
        mime,
      ).toBe(true)
    }
    for (const mime of ['image/heic', 'image/heif', 'text/html', 'audio/mp4']) {
      expect(
        mediaUploadInputSchema.safeParse({ kind: 'plan_document', mime_type: mime, size_bytes: 1024 })
          .success,
        mime,
      ).toBe(false)
    }
    expect(
      mediaUploadInputSchema.safeParse({
        kind: 'plan_document',
        mime_type: 'application/pdf',
        size_bytes: 20 * 1024 * 1024 + 1,
      }).success,
    ).toBe(false)
  })
})

describe('mobile API v1 contracts', () => {
  it('reserves strict educational content query, mutation, and resource contracts', () => {
    expect(contentListQuerySchema.parse({})).toEqual({ surface: 'library', limit: 20 })
    expect(contentReadInputSchema.parse({ event: 'opened', origin: 'today', version: 3 })).toEqual({
      event: 'opened',
      origin: 'today',
      version: 3,
    })
    expect(contentSaveInputSchema.parse({ saved: true, version: 3 })).toEqual({
      saved: true,
      version: 3,
    })
    expect(resourceIdSchema.parse('00000000-0000-0000-0000-000000000603')).toBe(
      '00000000-0000-0000-0000-000000000603',
    )

    expect(() => contentListQuerySchema.parse({ locale: 'pt-BR' })).toThrow()
    expect(() =>
      contentReadInputSchema.parse({
        event: 'opened',
        origin: 'today',
        version: 3,
        user_id: '00000000-0000-0000-0000-000000000601',
      }),
    ).toThrow()
    expect(() =>
      contentSaveInputSchema.parse({ saved: true, version: 3, origin: 'push' }),
    ).toThrow()
  })

  it('uses the shared strict educational content query contract', () => {
    const cursor = encodeContentCursor({
      publishAt: '2026-07-21T12:00:00.000Z',
      publicationId: '00000000-0000-0000-0000-000000000421',
    })

    expect(contentListQuerySchema.parse({})).toEqual({ surface: 'library', limit: 20 })
    expect(
      contentListQuerySchema.parse({
        surface: 'saved',
        category: 'nutrition',
        limit: '50',
        cursor,
      }),
    ).toEqual({ surface: 'saved', category: 'nutrition', limit: 50, cursor })
    expect(() => contentListQuerySchema.parse({ locale: 'pt-BR' })).toThrow()
    expect(() => contentListQuerySchema.parse({ limit: 51 })).toThrow()
  })

  it('keeps content read and save bodies strict and server-owned', () => {
    expect(contentReadInputSchema.parse({ event: 'opened', origin: 'today', version: 2 })).toEqual({
      event: 'opened',
      origin: 'today',
      version: 2,
    })
    expect(contentSaveInputSchema.parse({ saved: true, version: 2 })).toEqual({
      saved: true,
      version: 2,
    })
    expect(() =>
      contentReadInputSchema.parse({
        event: 'opened',
        origin: 'today',
        version: 2,
        user_id: 'forbidden',
      }),
    ).toThrow()
    expect(() =>
      contentSaveInputSchema.parse({ saved: true, version: 2, origin: 'push' }),
    ).toThrow()
  })

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

  it('keeps decimal quantities, a patient kcal and a legitimate zero exactly as sent', () => {
    // Incident matrix 2026-09-28: decimal quantities were once truncated, and a
    // 0 kcal item was once treated as a missing calculation.
    const parsed = registrationProposalInputSchema.parse({
      kind: 'meal',
      meal_type: 'almoco',
      items: [
        { food_name: 'arroz branco cozido', quantity_g: 150.5 },
        { food_name: 'feijão carioca cozido', quantity_g: 86.5, user_kcal: 66.1 },
        { food_name: 'café sem açúcar', quantity_g: 50, user_kcal: 0 },
      ],
    })

    expect(parsed.kind === 'meal' && parsed.items).toEqual([
      { food_name: 'arroz branco cozido', quantity_g: 150.5 },
      { food_name: 'feijão carioca cozido', quantity_g: 86.5, user_kcal: 66.1 },
      { food_name: 'café sem açúcar', quantity_g: 50, user_kcal: 0 },
    ])
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

  it('accepts only public coach personalities', () => {
    expect(personaInputSchema.parse({ persona: 'focus' })).toEqual({ persona: 'focus' })
    expect(() => personaInputSchema.parse({ persona: 'balanced' })).toThrow()
    expect(() => personaInputSchema.parse({ persona: 'zen', user_id: 'forbidden' })).toThrow()
  })

  it('bounds mobile history pagination', () => {
    expect(historyQuerySchema.parse({}).limit).toBe(30)
    expect(historyQuerySchema.parse({ limit: '100' }).limit).toBe(100)
    expect(() => historyQuerySchema.parse({ limit: '101' })).toThrow()
  })

  it('accepts one complete onboarding submission with exact document actions', () => {
    const input = {
      name: 'Paciente Teste',
      locale: 'pt-BR',
      country: 'BR',
      timezone: 'America/Sao_Paulo',
      sex: 'feminino',
      birth_date: '1990-06-15',
      height_cm: 168,
      weight_kg: 64,
      body_fat_percent: 24,
      objective: 'recomposicao',
      activity_level: 'moderado',
      training_frequency: 0,
      water_intake: 'moderado',
      hunger_level: 'moderada',
      wake_time: '07:30',
      bedtime: '23:00',
      food_organization: 'sim',
      persona: 'focus',
      document_actions: [
        {
          document_key: 'terms_of_service',
          version: '2026-09-15.1',
          locale: 'pt-BR',
          content_hash: 'a'.repeat(64),
          action: 'acceptance',
        },
        {
          document_key: 'privacy_policy',
          version: '2026-09-15.1',
          locale: 'pt-BR',
          content_hash: 'b'.repeat(64),
          action: 'acknowledgement',
        },
      ],
    } as const

    expect(onboardingCompletionInputSchema.parse(input)).toEqual(input)
  })

  it('rejects partial onboarding, stale-shaped identity, and client-owned completion fields', () => {
    expect(() => onboardingCompletionInputSchema.parse({ height_cm: 180 })).toThrow()
    expect(() =>
      onboardingCompletionInputSchema.parse({
        name: 'Paciente Teste',
        locale: 'pt-BR',
        country: 'BR',
        timezone: 'America/Sao_Paulo',
        sex: 'feminino',
        birth_date: '1990-06-15',
        height_cm: 168,
        weight_kg: 64,
        objective: 'recomposicao',
        activity_level: 'moderado',
        training_frequency: 3,
        water_intake: 'moderado',
        hunger_level: 'moderada',
        wake_time: '07:30',
        bedtime: '23:00',
        food_organization: 'sim',
        persona: 'focus',
        document_actions: [
          {
            document_key: 'dev_terms_v1',
            version: '1',
            locale: 'pt-BR',
            content_hash: 'a'.repeat(64),
            action: 'acceptance',
          },
        ],
        user_id: '00000000-0000-0000-0000-000000000001',
        onboarding_completed: true,
        accepted_at: '2026-09-15T12:00:00.000Z',
      }),
    ).toThrow()
  })

  it('preserves safe legacy partial onboarding updates without caller-owned completion', () => {
    expect(onboardingInputSchema.parse({ height_cm: 180, onboarding_step: 2 })).toEqual({
      height_cm: 180,
      onboarding_step: 2,
    })
    expect(() => onboardingInputSchema.parse({ onboarding_completed: true })).toThrow()
    expect(() => onboardingInputSchema.parse({ document_actions: [] })).toThrow()
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

  it('accepts only controlled routine notification preview modes', () => {
    expect(notificationPreferencesPatchSchema.parse({ routine_preview_mode: 'private' })).toEqual({
      routine_preview_mode: 'private',
    })
    expect(notificationPreferencesPatchSchema.parse({ routine_preview_mode: 'name' })).toEqual({
      routine_preview_mode: 'name',
    })
    expect(
      notificationPreferencesPatchSchema.parse({ routine_preview_mode: 'name_and_dose' }),
    ).toEqual({ routine_preview_mode: 'name_and_dose' })
    expect(() =>
      notificationPreferencesPatchSchema.parse({ routine_preview_mode: 'full' }),
    ).toThrow()
    expect(() =>
      notificationPreferencesPatchSchema.parse({
        routine_preview_mode: 'private',
        item_name: 'Private supplement',
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
