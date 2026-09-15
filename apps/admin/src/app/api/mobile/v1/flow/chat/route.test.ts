import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { FlowChatDependencies } from '@/lib/mobile-api/flow-chat-service'
import type { MobileApiError } from '@/lib/mobile-api/http'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { type FlowChatRouteDependencies, handleFlowChatGet, handleFlowChatPost } from './handler'

const userId = '00000000-0000-0000-0000-000000000511'

function context(method: 'GET' | 'POST', body?: unknown, query = ''): MobileRouteContext {
  return {
    request: new Request(`https://performe.test/api/mobile/v1/flow/chat${query}`, {
      method,
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: 'request-flow-0511',
    supabase: {} as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: '00000000-0000-0000-0000-000000000512',
      userId,
      identity: {
        id: 'auth',
        email: 'synthetic@example.test',
        emailConfirmedAt: '2026-09-14T00:00:00Z',
      },
      patient: {
        id: userId,
        authUserId: '00000000-0000-0000-0000-000000000512',
        email: 'synthetic@example.test',
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

function dependencies(): FlowChatRouteDependencies {
  const chat: FlowChatDependencies = {
    store: {} as FlowChatDependencies['store'],
    agent: {} as FlowChatDependencies['agent'],
  }
  return {
    createChatDependencies: vi.fn(() => chat),
    loadHistory: vi.fn(async () => ({ conversation_id: 'flow' as const, messages: [] })),
    sendMessage: vi.fn(async () => ({
      conversation_id: 'flow' as const,
      message: {
        id: 'assistant-1',
        conversation_id: 'flow' as const,
        role: 'assistant' as const,
        content: 'Olá!',
        state: 'completed' as const,
        request_id: 'request-flow-0511',
        created_at: '2026-09-14T20:00:00.000Z',
      },
    })),
    executeIdempotent: vi.fn(async (_context, _payload, operation) => operation('flow-key-0001')),
    now: () => new Date('2026-09-14T20:00:00.000Z'),
  }
}

describe('mobile Flow chat route', () => {
  it('loads bounded history for the authenticated user', async () => {
    const deps = dependencies()
    const response = await handleFlowChatGet(context('GET', undefined, '?limit=20'), deps)

    expect(response.status).toBe(200)
    expect(deps.loadHistory).toHaveBeenCalledWith(expect.anything(), userId, 20)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
  })

  it('rejects unrecognized history query controls with a typed client error', async () => {
    const deps = dependencies()

    await expect(
      handleFlowChatGet(context('GET', undefined, '?user_id=other'), deps),
    ).rejects.toMatchObject({
      name: 'MobileApiError',
      status: 422,
      code: 'validation_failed',
      message: 'Unexpected query parameter',
    } satisfies Partial<MobileApiError>)
    expect(deps.loadHistory).not.toHaveBeenCalled()
  })

  it('sends inside the existing idempotency boundary with server ownership', async () => {
    const deps = dependencies()
    const routeContext = context('POST', { text: ' Olá, Flow ' })
    const response = await handleFlowChatPost(routeContext, deps)

    expect(response.status).toBe(201)
    expect(deps.executeIdempotent).toHaveBeenCalledOnce()
    expect(deps.sendMessage).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId,
        text: 'Olá, Flow',
        idempotencyKey: 'flow-key-0001',
        requestId: 'request-flow-0511',
      }),
    )
  })

  it('rejects ownership fields before persistence', async () => {
    const deps = dependencies()
    await expect(
      handleFlowChatPost(context('POST', { text: 'oi', user_id: 'other' }), deps),
    ).rejects.toThrow()
    expect(deps.sendMessage).not.toHaveBeenCalled()
  })
})
