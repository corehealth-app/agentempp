import type { ServiceClient } from '@mpp/db'
import { beforeEach, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { createConversationWorkoutCommandRoutes } from './conversation-workout-command-routes'

const ports = vi.hoisted(() => ({
  db: null as ServiceClient | null,
  bootstrap: vi.fn(),
  entitlement: vi.fn(),
}))
vi.mock('../supabase/server', () => ({
  createServiceClient: () => ports.db,
  createPatientBearerClient: () => ({ rpc: ports.bootstrap }),
}))
vi.mock('./entitlement-service', () => ({ authorizeMobileEntitlement: ports.entitlement }))
beforeEach(() => {
  vi.clearAllMocks()
  ports.bootstrap.mockResolvedValue({ data: candidateAuth.userId, error: null })
})

it.each([
  'SESSION',
  'GET',
  'POST',
] as const)('default %s refuses OFF capability without bootstrapping an existing account', async (method) => {
  const p = candidateAuth.patient,
    patient = {
      id: p.id,
      auth_user_id: p.authUserId,
      email: p.email,
      name: p.name,
      locale: p.locale,
      timezone: p.timezone,
      country: p.country,
      country_confirmed: p.countryConfirmed,
      status: p.status,
    },
    from = vi.fn((table: string) => {
      const query = {
        select: vi.fn(() => query),
        eq: vi.fn(() => query),
        maybeSingle: vi.fn(async () => ({ data: table === 'users' ? patient : null, error: null })),
      }
      return query
    })
  ports.db = {
    auth: {
      getUser: vi.fn(async () => ({
        data: {
          user: {
            id: candidateAuth.authUserId,
            email: 'qa-readonly@example.invalid',
            email_confirmed_at: '2026-11-05T12:00:00Z',
          },
        },
        error: null,
      })),
    },
    from,
  } as unknown as ServiceClient
  const service = vi.fn(),
    routes = createConversationWorkoutCommandRoutes({ enabled: () => false, service }),
    request = new Request('https://app.invalid/workout', {
      method: method === 'POST' ? 'POST' : 'GET',
      headers: { Authorization: 'Bearer qa-original-token' },
    })
  const response =
    method === 'GET'
      ? await routes.GET(request, { params: Promise.resolve({ commandId: candidateAuth.userId }) })
      : await routes[method](request)
  expect(response.status).toBe(503)
  expect(ports.bootstrap).not.toHaveBeenCalled()
  expect(service).not.toHaveBeenCalled()
  expect(ports.entitlement).toHaveBeenCalledTimes(1)
})
it('default session refuses an absent patient without creating it', async () => {
  const query = {
    select: vi.fn(() => query),
    eq: vi.fn(() => query),
    maybeSingle: vi.fn(async () => ({ data: null, error: null })),
  }
  ports.db = {
    auth: {
      getUser: vi.fn(async () => ({
        data: {
          user: {
            id: candidateAuth.authUserId,
            email: 'qa-readonly@example.invalid',
            email_confirmed_at: '2026-11-05T12:00:00Z',
          },
        },
        error: null,
      })),
    },
    from: vi.fn(() => query),
  } as unknown as ServiceClient
  const service = vi.fn(),
    response = await createConversationWorkoutCommandRoutes({
      enabled: () => true,
      service,
    }).SESSION(
      new Request('https://app.invalid/workout-session', {
        headers: { Authorization: 'Bearer qa-original-token' },
      }),
    )
  expect(response.status).toBe(403)
  expect(ports.bootstrap).not.toHaveBeenCalled()
  expect(ports.entitlement).not.toHaveBeenCalled()
  expect(service).not.toHaveBeenCalled()
})
