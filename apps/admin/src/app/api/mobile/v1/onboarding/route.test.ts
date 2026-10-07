import { protocolWelcomeMessage } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { executeIdempotent, type MobileIdempotencyStore } from '@/lib/mobile-api/idempotency'
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

type Objective = 'recomposicao' | 'ganho_massa' | 'manutencao'

/** A repository that records whatever objective the request carries. */
function recordingRepository(): OnboardingRepository {
  return {
    ...repository(),
    complete: vi.fn(async (_userId, input) => ({
      userId: USER_ID,
      completed: true as const,
      completedAt: '2026-09-15T15:00:00.000Z',
      objective: input.objective,
      persona: 'focus' as const,
      documentActions: [],
    })),
  }
}

/** The idempotency ledger in memory, behind the real `executeIdempotent`. */
function ledger() {
  const claims = new Map<string, { hash: string; status: number | null; body: unknown }>()
  const stored: Array<{ status: number; body: unknown }> = []
  const store: MobileIdempotencyStore = {
    async claim(input) {
      const key = [input.userId, input.method, input.route, input.idempotencyKey].join('|')
      const existing = claims.get(key)
      if (!existing) {
        claims.set(key, { hash: input.requestHash, status: null, body: null })
        return { action: 'claimed', claimId: key }
      }
      if (existing.hash !== input.requestHash) return { action: 'conflict' }
      if (existing.status === null) return { action: 'in_progress' }
      return { action: 'replay', status: existing.status, body: existing.body }
    },
    async complete(claimId, _userId, status, body) {
      const claim = claims.get(claimId)
      if (!claim) throw new Error('unknown claim')
      claim.status = status
      claim.body = body
      stored.push({ status, body })
    },
    async fail(claimId) {
      claims.delete(claimId)
    },
  }
  const execute: OnboardingRouteDependencies['executeIdempotent'] = (
    requestContext,
    payload,
    operation,
    options,
  ) => executeIdempotent(requestContext, payload, store, operation, options)
  return { execute, stored }
}

function completionContext(body: unknown, idempotencyKey: string): MobileRouteContext {
  const requestContext = context(body)
  requestContext.request = new Request('https://bodyflow.test/api/mobile/v1/onboarding', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': idempotencyKey },
    body: JSON.stringify(body),
  })
  return requestContext
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

  // The words of each entry message are pinned, in both languages, in
  // packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts.
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('returns the entry message of the recorded objective: %s', async (objective: Objective) => {
    const repo = recordingRepository()
    const body = { ...validBody(), objective }

    const response = await handleOnboardingPost(context(body), dependencies(repo))

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
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
  })

  it('writes the entry message in the language of the request and with the name it carries', async () => {
    const repo = recordingRepository()
    const body = { ...validBody(), name: '  Ana Clara  ', locale: 'en-US', objective: 'manutencao' }

    const response = await handleOnboardingPost(context(body), dependencies(repo))

    const { data } = await response.json()
    expect(data.protocol_welcome).toEqual({
      protocol: 'manutencao',
      paragraphs: protocolWelcomeMessage('manutencao', 'Ana Clara', 'en-US'),
    })
    expect(data.protocol_welcome.paragraphs[0]).toMatch(
      /^Ana Clara, you are now entering the maintenance phase /,
    )
    // The account's own name and locale are not consulted: the request's are.
    expect(data.protocol_welcome.paragraphs[0]).not.toContain('Synthetic')
  })

  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('keeps the entry message out of the idempotency record and returns it again on every replay: %s', async (objective: Objective) => {
    const repo = recordingRepository()
    const deps = dependencies(repo)
    const { execute, stored } = ledger()
    deps.executeIdempotent = execute
    const body = { ...validBody(), objective }
    const key = `onboarding-welcome-${objective}`

    const first = await handleOnboardingPost(completionContext(body, key), deps)
    const firstBody = await first.json()

    expect(first.status).toBe(200)
    expect(first.headers.get('idempotency-replayed')).toBeNull()
    expect(firstBody.data.protocol_welcome).toEqual({
      protocol: objective,
      paragraphs: protocolWelcomeMessage(objective, 'Synthetic User', 'pt-BR'),
    })
    // What the ledger keeps is the response as it was before this field
    // existed: no entry message, and so no name of the person.
    expect(stored).toEqual([
      {
        status: 200,
        body: {
          data: {
            onboarding_completed: true,
            completed_at: '2026-09-15T15:00:00.000Z',
            objective,
            persona: 'focus',
            document_actions: [],
          },
          meta: { api_version: 'v1', request_id: 'request-onboarding-951' },
        },
      },
    ])
    expect(JSON.stringify(stored)).not.toContain('Synthetic User')
    expect(JSON.stringify(stored)).not.toContain('protocol_welcome')

    for (const attempt of [2, 3]) {
      const replay = await handleOnboardingPost(completionContext(body, key), deps)

      expect(replay.status).toBe(200)
      expect(replay.headers.get('idempotency-replayed')).toBe('true')
      expect(await replay.json()).toEqual(firstBody)
      expect(repo.complete).toHaveBeenCalledTimes(attempt)
    }
    expect(stored).toHaveLength(1)
  })

  it('a replay with another payload under the same key is still a conflict', async () => {
    const repo = recordingRepository()
    const deps = dependencies(repo)
    deps.executeIdempotent = ledger().execute
    const key = 'onboarding-welcome-conflict'

    await handleOnboardingPost(completionContext(validBody(), key), deps)

    await expect(
      handleOnboardingPost(
        completionContext({ ...validBody(), objective: 'manutencao' }, key),
        deps,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
    expect(repo.complete).toHaveBeenCalledTimes(1)
  })

  it('the legacy partial update carries no entry message and its record is stored whole', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const { execute, stored } = ledger()
    deps.executeIdempotent = execute

    const response = await handleOnboardingPost(
      completionContext({ height_cm: 180 }, 'onboarding-legacy-partial'),
      deps,
    )
    const body = await response.json()

    expect(body.data).toEqual({ profile: null, targets: { calories: null, protein_g: null } })
    expect(stored).toEqual([{ status: 200, body }])
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
