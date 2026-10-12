import { describe, expect, it, vi } from 'vitest'
import { onboardingCompletionInputSchema } from './contracts'
import type { MobileRouteContext } from './route'
import {
  prepareSignupPhotoConfirmation,
  type SignupPhotoSnapshot,
} from './signup-body-photo-confirmation'

const OWNER = '00000000-0000-4000-8000-000000000951'
const AUTH = '00000000-0000-4000-8000-000000000952'
const SOURCES = {
  front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
}
const FINGERPRINT = 'a'.repeat(64)
const NOW = new Date('2026-10-12T01:00:00.000Z')
const context: Pick<MobileRouteContext, 'auth'> = {
  auth: {
    accessToken: 'synthetic-test-token',
    authUserId: AUTH,
    userId: OWNER,
    identity: { id: AUTH, email: null, emailConfirmedAt: null },
    patient: {
      id: OWNER,
      authUserId: AUTH,
      email: null,
      name: 'Synthetic',
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  },
}

function input() {
  return onboardingCompletionInputSchema.parse({
    name: 'Synthetic',
    locale: 'pt-BR',
    country: 'BR',
    timezone: 'America/Sao_Paulo',
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    objective: 'recomposicao',
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms_of_service',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        content_hash: 'b'.repeat(64),
        action: 'acceptance',
      },
    ],
    body_photo_confirmation: { decision: 'accept', source_ids: SOURCES, fingerprint: FINGERPRINT },
  })
}

function snapshot(): SignupPhotoSnapshot {
  return {
    version: 1,
    user_id: OWNER,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    poses: (['front', 'side', 'back'] as const).map((pose) => ({
      pose,
      photo: { id: SOURCES[pose], status: 'read', created_at: '2026-10-11T22:00:00.000Z' },
    })),
    remaining_uploads: 6,
    consent: {
      legal_document_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      document_key: 'body_photo_estimate_consent',
      version: 'synthetic-v1',
      locale: 'pt-BR',
      body: 'Synthetic consent, not published.',
      body_hash: 'c'.repeat(64),
      accepted_at: '2026-10-11T22:00:00.000Z',
    },
    estimate: {
      is_estimate: true,
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
    },
    candidate: {
      method: 'arithmetic_mean_v1',
      body_fat_percent: 24,
      source_ids: SOURCES,
      fingerprint: FINGERPRINT,
    },
    confirmation: null,
  }
}

describe('D2 preclaim preparation from one official snapshot', () => {
  it('preserves a genuine historical decline and its manual value with photos OFF', async () => {
    const current = snapshot()
    current.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-11T23:00:00.000Z',
      receipt_count: 1,
    }
    current.poses = []
    current.remaining_uploads = 0
    current.consent = null
    current.estimate = null
    current.candidate = null
    current.confirmation = {
      decision: 'declined',
      method: null,
      source_ids: null,
      fingerprint: null,
      confirmed_body_fat_percent: null,
      decided_at: '2026-10-11T23:00:00.000Z',
      invalidated_at: null,
      active: false,
    }
    const original = {
      ...input(),
      body_fat_percent: 24,
      body_photo_confirmation: { decision: 'decline' as const },
    }
    const loadSnapshot = vi.fn(async () => current)
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      {
        targetAllowed: true,
        photosEnabled: false,
        loadSnapshot,
      },
      NOW,
    )
    expect(result.mode).toBe('decline')
    expect(result.effectiveSubmission).toMatchObject({ body_fat_percent: 24 })
    expect(result.effectiveSubmission).not.toHaveProperty('body_photo_confirmation')
    expect(result.original).toBe(original)
    expect(loadSnapshot).toHaveBeenCalledWith(OWNER, false)
    expect(loadSnapshot).toHaveBeenCalledTimes(1)
  })

  it.each([
    0, 2,
  ])('refuses a historical decline without a current declined receipt (history count %s)', async (receiptCount) => {
    const current = snapshot()
    current.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-11T23:00:00.000Z',
      receipt_count: receiptCount,
    }
    current.poses = []
    current.consent = null
    current.estimate = null
    current.candidate = null
    const original = {
      ...input(),
      body_fat_percent: 24,
      body_photo_confirmation: { decision: 'decline' as const },
    }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        { targetAllowed: true, photosEnabled: false, loadSnapshot: async () => current },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'body_photo_confirmation_unavailable' })
    expect(original.body_fat_percent).toBe(24)
    expect(current.confirmation).toBeNull()
  })

  it.each(
    (['fresh', 'historic'] as const).flatMap((mode) =>
      [Number.NaN, Number.POSITIVE_INFINITY, 2, 60.01, 19.995].map(
        (value) => [mode, value] as const,
      ),
    ),
  )('refuses a nonfinite, outside-range or noncanonical trusted %s value %s without applying it', async (mode, value) => {
    const observed = snapshot()
    if (mode === 'fresh') {
      if (!observed.candidate) throw new Error('Expected the fixture candidate')
      observed.candidate.body_fat_percent = value
    } else {
      observed.generation_token = {
        onboarding_completed: true,
        onboarding_completed_at: '2026-10-11T22:30:00.000Z',
        receipt_count: 1,
      }
      observed.confirmation = {
        decision: 'accepted',
        method: 'arithmetic_mean_v1',
        source_ids: SOURCES,
        fingerprint: FINGERPRINT,
        confirmed_body_fat_percent: value,
        decided_at: '2026-10-11T22:30:00.000Z',
        invalidated_at: null,
        active: true,
      }
    }
    const original = input()
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => observed,
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 500, code: 'data_access_failed' })
    expect(original).not.toHaveProperty('body_fat_percent')
  })

  it('missing published photo text does not become a locale mismatch or an inferred acceptance', async () => {
    const observed = snapshot()
    observed.consent = null
    observed.candidate = null
    observed.estimate = null
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        input(),
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => observed,
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 404, code: 'body_photos_unavailable' })
  })

  it('18/24/30 confirmed: derives24 for the objective without changing the original payload/hash', async () => {
    const original = input()
    const originalCopy = structuredClone(original)
    const observed = snapshot()
    const loadSnapshot = vi.fn(async () => observed)
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      { targetAllowed: true, photosEnabled: true, loadSnapshot },
      NOW,
    )

    expect(result.effectiveSubmission.body_fat_percent).toBe(24)
    expect(result.mode).toBe('fresh_accept')
    expect(result.effectiveSubmission).not.toHaveProperty('body_photo_confirmation')
    expect(result.original).toBe(original)
    expect(original).toEqual(originalCopy)
    expect(result.snapshot).toBe(observed)
    expect(loadSnapshot).toHaveBeenCalledTimes(1)
    expect(loadSnapshot).toHaveBeenCalledWith(OWNER, true)
  })

  it.each([
    ['stale fingerprint', { fingerprint: 'b'.repeat(64) }],
    [
      'swapped slots',
      { source_ids: { front: SOURCES.side, side: SOURCES.front, back: SOURCES.back } },
    ],
  ])('refuses %s from the same owner before any completion', async (_case, change) => {
    const original = input()
    original.body_photo_confirmation = {
      decision: 'accept',
      source_ids: SOURCES,
      fingerprint: FINGERPRINT,
      ...change,
    }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => snapshot(),
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'body_photo_confirmation_stale' })
  })

  it('refuses a finite in-range mean24 when the official triad contains2/24/46', async () => {
    const observed = snapshot()
    observed.candidate = null
    observed.estimate = {
      is_estimate: true,
      by_sex: {
        masculino: { usable: false, reason: 'out_of_range' },
        feminino: { usable: false, reason: 'out_of_range' },
      },
    }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        input(),
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => observed,
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'body_photo_confirmation_unavailable' })
  })

  it('refuses missing exact consent acceptance even if the same version was accepted in another locale', async () => {
    const observed = snapshot()
    if (!observed.consent) throw new Error('Expected the fixture consent')
    observed.consent.accepted_at = null
    observed.consent.locale = 'en-US'
    observed.locale = 'en-US'
    const original = { ...input(), locale: 'en-US' as const }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => observed,
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 403, code: 'body_photo_consent_required' })
  })

  it('uses stored Sao_Paulo date17 rather than submitted Auckland date18 at the birthday boundary', async () => {
    const original = { ...input(), birth_date: '2008-10-12', timezone: 'Pacific/Auckland' }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => snapshot(),
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 403, code: 'body_photo_age_not_allowed' })
  })

  it('does not take an already completed account without a receipt as proof of acceptance', async () => {
    const observed = snapshot()
    observed.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-11T22:30:00.000Z',
      receipt_count: 0,
    }
    observed.candidate = null
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        input(),
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => observed,
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'body_photo_confirmation_unavailable' })
  })

  it('refuses a different manual percent23.99; does not silently replace it with24', async () => {
    const original = { ...input(), body_fat_percent: 23.99 }
    await expect(
      prepareSignupPhotoConfirmation(
        context,
        original,
        {
          targetAllowed: true,
          photosEnabled: true,
          loadSnapshot: async () => snapshot(),
        },
        NOW,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'body_photo_confirmation_value_mismatch' })
    expect(original.body_fat_percent).toBe(23.99)
  })

  it('accepts manual23.995 only because its stored numeric value matches the official24', async () => {
    const original = { ...input(), body_fat_percent: 23.995 }
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      {
        targetAllowed: true,
        photosEnabled: true,
        loadSnapshot: async () => snapshot(),
      },
      NOW,
    )
    expect(result.effectiveSubmission.body_fat_percent).toBe(24)
    expect(result.original.body_fat_percent).toBe(23.995)
  })

  it('manual24 with no metadata remains manual and uses only the generation snapshot for CAS', async () => {
    const { body_photo_confirmation: _intent, ...official } = input()
    const original = { ...official, body_fat_percent: 24 }
    const observed = snapshot()
    observed.consent = null
    observed.candidate = null
    observed.estimate = null
    observed.poses = []
    const loadSnapshot = vi.fn(async () => observed)
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      {
        targetAllowed: true,
        photosEnabled: false,
        loadSnapshot,
      },
      NOW,
    )
    expect(result.mode).toBe('manual')
    expect(result.effectiveSubmission).toEqual(original)
    expect(result.snapshot).toBe(observed)
    expect(loadSnapshot).toHaveBeenCalledTimes(1)
    expect(loadSnapshot).toHaveBeenCalledWith(OWNER, false)
  })

  it('an explicit decline preserves manual24 even with photosOFF and never asks for photo readings', async () => {
    const original = {
      ...input(),
      body_fat_percent: 24,
      body_photo_confirmation: { decision: 'decline' as const },
    }
    const observed = snapshot()
    observed.consent = null
    observed.candidate = null
    observed.estimate = null
    observed.poses = []
    const loadSnapshot = vi.fn(async () => observed)
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      {
        targetAllowed: true,
        photosEnabled: false,
        loadSnapshot,
      },
      NOW,
    )
    expect(result.mode).toBe('decline')
    expect(result.effectiveSubmission.body_fat_percent).toBe(24)
    expect(result.effectiveSubmission).not.toHaveProperty('body_photo_confirmation')
    expect(loadSnapshot).toHaveBeenCalledWith(OWNER, false)
  })

  it('historic invalidated proof can establish replayOFF after cleanup without reactivating the source', async () => {
    const observed = snapshot()
    observed.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-11T22:30:00.000Z',
      receipt_count: 1,
    }
    observed.consent = null
    observed.candidate = null
    observed.estimate = null
    observed.poses = []
    observed.confirmation = {
      decision: 'accepted',
      method: 'arithmetic_mean_v1',
      source_ids: SOURCES,
      fingerprint: FINGERPRINT,
      confirmed_body_fat_percent: 24,
      decided_at: '2026-10-11T22:30:00.000Z',
      invalidated_at: '2026-10-11T23:00:00.000Z',
      active: false,
    }
    const original = input()
    const before = structuredClone(observed)
    const loadSnapshot = vi.fn(async () => observed)
    const result = await prepareSignupPhotoConfirmation(
      context,
      original,
      {
        targetAllowed: true,
        photosEnabled: false,
        loadSnapshot,
      },
      NOW,
    )
    expect(result.mode).toBe('historic_accept')
    expect(result.effectiveSubmission.body_fat_percent).toBe(24)
    expect(observed).toEqual(before)
    expect(observed.confirmation?.active).toBe(false)
    expect(loadSnapshot).toHaveBeenCalledWith(OWNER, false)
  })
})
