import { protocolWelcomeMessage } from '@mpp/core'
import { describe, expect, it, vi } from 'vitest'
import type { OnboardingCompletionInput } from './contracts'
import {
  completeOnboarding,
  getOnboardingState,
  type OnboardingRepository,
  OnboardingRepositoryError,
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
  it.each([
    false,
    true,
  ])('returns unknown water only to a capable client (%s)', async (completed) => {
    const value = input()
    const repo = repository({
      load: vi.fn(async () => ({
        locale: 'pt-BR' as const,
        completed,
        completedAt: '2026-09-15T15:00:00.000Z',
        documents: [],
        acceptedActions: [],
        draft: {
          name: value.name,
          locale: value.locale,
          country: value.country,
          timezone: value.timezone,
          sex: value.sex,
          birthDate: value.birth_date,
          heightCm: value.height_cm,
          weightKg: value.weight_kg,
          bodyFatPercent: null,
          objective: value.objective,
          activityLevel: value.activity_level,
          trainingFrequency: value.training_frequency,
          waterIntake: null,
          hungerLevel: value.hunger_level,
          wakeTime: value.wake_time,
          bedtime: value.bedtime,
          foodOrganization: value.food_organization,
          persona: value.persona,
        },
      })),
    })
    const capable = await getOnboardingState(repo, USER_ID, 'pt-BR', { acceptsUnknownWater: true })
    expect(capable.draft?.water_intake).toBeNull()
    if (completed) {
      const legacy = await getOnboardingState(repo, USER_ID, 'pt-BR')
      expect(legacy.completion.completed).toBe(true)
      expect(legacy.draft).toBeNull()
    } else {
      await expect(getOnboardingState(repo, USER_ID, 'pt-BR')).rejects.toMatchObject({
        status: 409,
        code: 'onboarding_client_update_required',
      })
    }
  })

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

  // The words of each entry message are pinned, in both languages, in
  // packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts.
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('returns the entry message of the recorded objective, with the name of the request: %s', async (objective) => {
    const repo = repository({
      complete: vi.fn(async () => ({
        userId: USER_ID,
        completed: true as const,
        completedAt: '2026-09-15T15:00:00.000Z',
        objective,
        persona: 'focus' as const,
        documentActions: [],
      })),
    })

    const result = await completeOnboarding(repo, USER_ID, { ...input(), objective })

    expect(result).toEqual({
      onboarding_completed: true,
      completed_at: '2026-09-15T15:00:00.000Z',
      objective,
      persona: 'focus',
      document_actions: [],
      protocol_welcome: {
        protocol: objective,
        paragraphs: protocolWelcomeMessage(objective, 'Synthetic User', 'pt-BR'),
      },
    })
    expect(result.protocol_welcome.paragraphs[0]).toMatch(
      /^Synthetic User, (?:a partir de )?agora você entra /,
    )
    expect(result.protocol_welcome.paragraphs).toHaveLength(objective === 'ganho_massa' ? 7 : 4)
  })

  it('writes the entry message in the language of the request', async () => {
    const result = await completeOnboarding(repository(), USER_ID, { ...input(), locale: 'en-US' })

    expect(result.protocol_welcome).toEqual({
      protocol: 'recomposicao',
      paragraphs: protocolWelcomeMessage('recomposicao', 'Synthetic User', 'en-US'),
    })
    expect(result.protocol_welcome.paragraphs[0]).toMatch(
      /^Synthetic User, as of now you are officially entering the body recomposition phase\./,
    )
  })

  it('takes the protocol of the entry message from what was RECORDED, never from the request', async () => {
    // The SQL function never records another objective; this pins the source.
    const repo = repository()

    const result = await completeOnboarding(repo, USER_ID, { ...input(), objective: 'ganho_massa' })

    expect(result.objective).toBe('recomposicao')
    expect(result.protocol_welcome.protocol).toBe('recomposicao')
    expect(result.protocol_welcome.paragraphs).toEqual(
      protocolWelcomeMessage('recomposicao', 'Synthetic User', 'pt-BR'),
    )
  })

  it('returns the same entry message every time the same request is completed', async () => {
    const repo = repository()

    const first = await completeOnboarding(repo, USER_ID, input())
    const second = await completeOnboarding(repo, USER_ID, input())

    expect(second).toEqual(first)
    expect(repo.complete).toHaveBeenCalledTimes(2)
  })

  it('returns no entry message when the completion is refused', async () => {
    const repo = repository({
      complete: vi.fn(async () => {
        throw new OnboardingRepositoryError('already_completed')
      }),
    })

    await expect(completeOnboarding(repo, USER_ID, input())).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_already_completed',
    })
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
