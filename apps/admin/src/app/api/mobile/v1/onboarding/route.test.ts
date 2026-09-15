import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { OnboardingRepository } from '@/lib/mobile-api/onboarding-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  handleOnboardingGet,
  handleOnboardingPost,
  type OnboardingRouteDependencies,
} from './handler'

const USER_ID = '00000000-0000-4000-8000-000000000951'
const AUTH_USER_ID = '00000000-0000-4000-8000-000000000952'

function context(body?: unknown): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/onboarding', {
      method: body === undefined ? 'GET' : 'POST',
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: 'request-onboarding-951',
    supabase: {} as ServiceClient,
    auth: {
      accessToken: 'redacted-test-token',
      authUserId: AUTH_USER_ID,
      userId: USER_ID,
      identity: {
        id: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        emailConfirmedAt: '2026-09-15T14:00:00.000Z',
      },
      patient: {
        id: USER_ID,
        authUserId: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function dependencies(repository: OnboardingRepository): OnboardingRouteDependencies {
  return {
    createOnboardingRepository: vi.fn(() => repository),
    executeIdempotent: vi.fn(async (_context, _payload, operation) => operation('normalized-key')),
    saveLegacyOnboarding: vi.fn(async () => ({
      profile: null,
      targets: { calories: null, protein_g: null },
    })),
  }
}

function validBody() {
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

function repository(): OnboardingRepository {
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
  }
}

describe('mobile onboarding route', () => {
  it('loads server-owned state for the authenticated user and locale', async () => {
    const repo = repository()
    const response = await handleOnboardingGet(context(), dependencies(repo))

    expect(repo.load).toHaveBeenCalledWith(USER_ID, 'pt-BR')
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
  })

  it('completes inside idempotency using only the authenticated user identity', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const response = await handleOnboardingPost(context(validBody()), deps)

    expect(deps.executeIdempotent).toHaveBeenCalledOnce()
    expect(repo.complete).toHaveBeenCalledWith(USER_ID, validBody())
    expect(response.status).toBe(200)
    const responseBody = await response.json()
    expect(responseBody).toMatchObject({ data: { onboarding_completed: true } })
    expect(responseBody.data).not.toHaveProperty('user_id')
    expect(AUTH_USER_ID).not.toBe(USER_ID)
  })

  it('revalidates current requirements when an exact completion request is replayed', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    deps.executeIdempotent = vi.fn(async (_context, _payload, operation, options) => {
      await operation('normalized-key')
      if (!options.refreshReplay) throw new Error('Expected completion replay revalidation')
      return options.refreshReplay({ action: 'replay', body: {}, status: 200 })
    })

    const response = await handleOnboardingPost(context(validBody()), deps)

    expect(response.status).toBe(200)
    expect(repo.complete).toHaveBeenCalledTimes(2)
  })

  it('rejects caller-owned state before idempotency or persistence', async () => {
    const repo = repository()
    const deps = dependencies(repo)

    await expect(
      handleOnboardingPost(
        context({ ...validBody(), user_id: '00000000-0000-4000-8000-000000000999' }),
        deps,
      ),
    ).rejects.toThrow()
    expect(deps.executeIdempotent).not.toHaveBeenCalled()
    expect(repo.complete).not.toHaveBeenCalled()
  })

  it('preserves the legacy partial update response while forbidding client completion', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const response = await handleOnboardingPost(
      context({ height_cm: 180, onboarding_completed: false }),
      deps,
    )

    expect(deps.saveLegacyOnboarding).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: USER_ID, authUserId: AUTH_USER_ID }),
      { height_cm: 180 },
      'normalized-key',
    )
    expect(repo.complete).not.toHaveBeenCalled()
    await expect(response.json()).resolves.toMatchObject({
      data: {
        profile: null,
        targets: { calories: null, protein_g: null },
      },
    })

    await expect(
      handleOnboardingPost(context({ onboarding_completed: true }), deps),
    ).rejects.toThrow()
  })

  it('fails closed for an unsupported authenticated locale', async () => {
    const repo = repository()
    const requestContext = context()
    requestContext.auth.patient.locale = 'fr-FR'

    await expect(handleOnboardingGet(requestContext, dependencies(repo))).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_locale_unsupported',
    })
    expect(repo.load).not.toHaveBeenCalled()
  })
})
