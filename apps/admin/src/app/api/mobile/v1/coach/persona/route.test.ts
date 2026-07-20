import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { CoachDependencies, CoachPersonaState } from '@/lib/mobile-api/coach-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  type CoachPersonaRouteDependencies,
  handleCoachPersonaGet,
  handleCoachPersonaPatch,
} from './route'

const userId = '00000000-0000-0000-0000-000000000921'

const state: CoachPersonaState = {
  selected: 'focus',
  effective: 'focus',
  options: [
    { code: 'focus', name: 'Focus', description: 'Direct and objective.' },
    { code: 'impulse', name: 'Impulse', description: 'Energetic and positive.' },
    { code: 'zen', name: 'Zen', description: 'Calm and clear.' },
  ],
  mascot: { state: 'active', changed_at: '2026-07-20T13:00:00.000Z' },
  contract_version: 'bodyflow.coach-persona.v1',
}

function createContext(body?: unknown, locale: string | null = 'en-US'): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/coach/persona', {
      method: body === undefined ? 'GET' : 'PATCH',
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: 'request-coach-921',
    supabase: {} as ServiceClient,
    auth: {
      accessToken: 'redacted-test-token',
      authUserId: '00000000-0000-0000-0000-000000000922',
      userId,
      identity: {
        id: '00000000-0000-0000-0000-000000000922',
        email: 'synthetic@example.com',
        emailConfirmedAt: '2026-07-20T12:00:00.000Z',
      },
      patient: {
        id: userId,
        authUserId: '00000000-0000-0000-0000-000000000922',
        email: 'synthetic@example.com',
        name: 'Synthetic',
        locale,
        timezone: 'America/New_York',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function createDependencies(repository: CoachDependencies['repository']) {
  const executeIdempotent = vi.fn(async (_context, _payload, operation) =>
    operation('persona-change-921'),
  )
  return {
    createCoachDependencies: vi.fn(() => ({ repository })),
    executeIdempotent,
  } satisfies CoachPersonaRouteDependencies
}

describe('mobile coach persona route', () => {
  it('loads the authenticated patient state in the patient locale', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }
    const response = await handleCoachPersonaGet(createContext(), createDependencies(repository))

    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toMatchObject({
      data: {
        selected: 'focus',
        effective: 'focus',
        contract_version: 'bodyflow.coach-persona.v1',
      },
    })
    expect(repository.getPersonaState).toHaveBeenCalledWith(userId, 'en-US')
  })

  it('changes only the authenticated patient persona inside the idempotency boundary', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }
    const deps = createDependencies(repository)
    const response = await handleCoachPersonaPatch(createContext({ persona: 'focus' }), deps)

    expect(response.status).toBe(200)
    expect(deps.executeIdempotent).toHaveBeenCalledOnce()
    expect(repository.setPersona).toHaveBeenCalledWith(userId, 'focus')
    expect(repository.getPersonaState).toHaveBeenCalledWith(userId, 'en-US')
  })

  it('returns an idempotent replay without applying the personality again', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }
    const deps = createDependencies(repository)
    deps.executeIdempotent.mockResolvedValueOnce(
      Response.json({ data: state, meta: { api_version: 'v1', request_id: 'replayed' } }),
    )

    const response = await handleCoachPersonaPatch(createContext({ persona: 'impulse' }), deps)

    expect(response.status).toBe(200)
    expect(repository.setPersona).not.toHaveBeenCalled()
  })

  it('defaults an unset profile locale to pt-BR', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }

    await handleCoachPersonaGet(createContext(undefined, null), createDependencies(repository))

    expect(repository.getPersonaState).toHaveBeenCalledWith(userId, 'pt-BR')
  })

  it('fails closed for a profile locale without a translated catalog', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }

    await expect(
      handleCoachPersonaGet(createContext(undefined, 'es-ES'), createDependencies(repository)),
    ).rejects.toMatchObject({ status: 409, code: 'coach_locale_unsupported' })
    expect(repository.getPersonaState).not.toHaveBeenCalled()
  })

  it('rejects internal balanced and caller-supplied ownership fields', async () => {
    const repository: CoachDependencies['repository'] = {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
    }
    const deps = createDependencies(repository)

    await expect(
      handleCoachPersonaPatch(createContext({ persona: 'balanced' }), deps),
    ).rejects.toThrow()
    await expect(
      handleCoachPersonaPatch(createContext({ persona: 'zen', user_id: 'another-user' }), deps),
    ).rejects.toThrow()
    expect(repository.setPersona).not.toHaveBeenCalled()
  })
})
