import { describe, expect, it, vi } from 'vitest'
import type { OnboardingCompletionInput } from './contracts'
import {
  completeOnboarding,
  getOnboardingState,
  type OnboardingRepository,
} from './onboarding-service'

const USER_ID = '00000000-0000-4000-8000-000000000951'

function input(): OnboardingCompletionInput {
  return {
    name: 'Synthetic User',
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
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  }
}

function repository(overrides: Partial<OnboardingRepository> = {}): OnboardingRepository {
  return {
    load: vi.fn(async () => ({
      locale: 'pt-BR' as const,
      completed: false,
      completedAt: null,
      documents: [],
      acceptedActions: [],
      draft: null,
    })),
    complete: vi.fn(async () => ({
      userId: USER_ID,
      completed: true as const,
      completedAt: '2026-09-15T15:00:00.000Z',
      objective: 'recomposicao' as const,
      persona: 'focus' as const,
      documentActions: [],
    })),
    ...overrides,
  }
}

describe('server-owned onboarding service', () => {
  it('fails closed without published required documents while preserving official completion', async () => {
    const result = await getOnboardingState(repository(), USER_ID, 'pt-BR')

    expect(result).toEqual({
      completion: { completed: false, completed_at: null },
      locale: 'pt-BR',
      requirements: {
        available: false,
        blocking_reason: 'documents_unavailable',
        documents: [],
      },
      accepted_actions: [],
      draft: null,
    })
  })

  it('returns exact immutable document identities and distinct required actions', async () => {
    const repo = repository({
      load: vi.fn(async () => ({
        locale: 'pt-BR' as const,
        completed: false,
        completedAt: null,
        documents: [
          {
            documentKey: 'terms_of_service',
            version: '2026-09-15.1',
            locale: 'pt-BR',
            body: 'Synthetic terms for tests only',
            contentUrl: null,
            contentHash: 'a'.repeat(64),
            purpose: 'synthetic_terms_test',
            action: 'acceptance' as const,
            required: true,
            effectiveAt: '2026-09-15T00:00:00.000Z',
          },
          {
            documentKey: 'privacy_policy',
            version: '2026-09-15.1',
            locale: 'pt-BR',
            body: null,
            contentUrl: 'https://legal.example.invalid/privacy',
            contentHash: 'b'.repeat(64),
            purpose: 'synthetic_privacy_test',
            action: 'acknowledgement' as const,
            required: true,
            effectiveAt: '2026-09-15T00:00:00.000Z',
          },
        ],
        acceptedActions: [],
        draft: {
          name: 'Synthetic User',
          locale: 'pt-BR' as const,
          country: 'BR',
          timezone: 'America/Sao_Paulo',
          sex: 'masculino' as const,
          birthDate: '1990-01-01',
          heightCm: 180,
          weightKg: 80,
          bodyFatPercent: null,
          objective: 'recomposicao' as const,
          activityLevel: 'moderado' as const,
          trainingFrequency: 4,
          waterIntake: 'moderado' as const,
          hungerLevel: 'moderada' as const,
          wakeTime: '07:00',
          bedtime: '23:00',
          foodOrganization: 'sim' as const,
          persona: 'focus' as const,
        },
      })),
    })

    const result = await getOnboardingState(repo, USER_ID, 'pt-BR')

    expect(result.requirements.available).toBe(true)
    expect(result.requirements.blocking_reason).toBeNull()
    expect(result.requirements.documents).toEqual([
      expect.objectContaining({
        document_key: 'terms_of_service',
        action: 'acceptance',
        content_hash: 'a'.repeat(64),
      }),
      expect.objectContaining({
        document_key: 'privacy_policy',
        action: 'acknowledgement',
        content_url: 'https://legal.example.invalid/privacy',
      }),
    ])
    expect(result.draft).toMatchObject({
      name: 'Synthetic User',
      birth_date: '1990-01-01',
      current_step: 'consent',
    })
  })

  it('derives ownership at the caller without exposing the internal domain user id', async () => {
    const repo = repository()

    const result = await completeOnboarding(repo, USER_ID, input())

    expect(repo.complete).toHaveBeenCalledWith(USER_ID, input())
    expect(result).toMatchObject({
      onboarding_completed: true,
      completed_at: '2026-09-15T15:00:00.000Z',
    })
    expect(result).not.toHaveProperty('user_id')
  })

  it('fails closed before returning a bootstrap larger than the mobile transport limit', async () => {
    const repo = repository({
      load: vi.fn(async () => ({
        locale: 'pt-BR' as const,
        completed: false,
        completedAt: null,
        documents: [
          {
            documentKey: 'terms_of_service',
            version: '2026-09-15.1',
            locale: 'pt-BR',
            body: 'x'.repeat(64_000),
            contentUrl: null,
            contentHash: 'a'.repeat(64),
            purpose: 'synthetic_oversized_response_test',
            action: 'acceptance' as const,
            required: true,
            effectiveAt: '2026-09-15T00:00:00.000Z',
          },
        ],
        acceptedActions: [],
        draft: null,
      })),
    })

    await expect(getOnboardingState(repo, USER_ID, 'pt-BR')).rejects.toMatchObject({
      status: 503,
      code: 'onboarding_documents_unavailable',
    })
  })
})
