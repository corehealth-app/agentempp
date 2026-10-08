import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  type FlowChatDependencies,
  type FlowMessageDTO,
  loadFlowHistory,
  type StoredFlowMessage,
  scopedFlowProviderMessageId,
  sendFlowMessage,
} from '@/lib/mobile-api/flow-chat-service'
import { MobileApiError } from '@/lib/mobile-api/http'
import { executeIdempotent, type MobileIdempotencyStore } from '@/lib/mobile-api/idempotency'
import { createMobileRoute, type MobileRouteContext } from '@/lib/mobile-api/route'
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
      draft: null,
    })),
    executeIdempotent: vi.fn(async (_context, _payload, operation) => operation('flow-key-0001')),
    loadPresentationContext: vi.fn(async () => ({ currentProtocol: null })),
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

const oldAssistant: FlowMessageDTO = Object.freeze({
  id: 'assistant-old',
  conversation_id: 'flow',
  role: 'assistant',
  content: 'Seu BMR é 1.800 kcal. Meta oficial: 2.800 kcal. BF: 20%.',
  state: 'completed',
  request_id: 'request-original',
  created_at: '2026-09-13T20:00:00.000Z',
})

const objectiveAssistant = Object.freeze({ ...oldAssistant,
  content: [
    'Evite amendoim por sua alergia.', 'Consumido: 541 / 2.980 kcal (18%)',
    'Restam para comida: 2.439 kcal', 'Proteína: 59.0 / 144g (41%)', 'Exercício: 322 kcal',
    'Bloco 7700: 3.120 / 7.700 kcal (41%)', '4 bloco(s) de 7.700 completo(s)',
    'Orçamento 14d: 5.850 / 5.960 kcal (98%) · DAM: 1/2',
    'Reavaliação em 14 dias.', 'Arroz: 150 g, 195 kcal.', 'Revisar sugestão',
  ].join('\n'),
})
function projectedObjectiveAnswer(protocol: string | null) {
  return [
    'Evite amendoim por sua alergia.', 'Consumido: 541 / 2.980 kcal (18%)',
    'Restam para comida: 2.439 kcal', 'Proteína: 59.0 / 144g (41%)', 'Exercício: 322 kcal',
    ...(protocol === 'recomposicao' ? ['Bloco 7700: 3.120 / 7.700 kcal (41%)', '4 bloco(s) de 7.700 completo(s)'] : []),
    'Reavaliação em 14 dias.', 'Arroz: 150 g, 195 kcal.', 'Revisar sugestão',
  ].join('\n') + (protocol === 'ganho_massa' || protocol === 'manutencao'
    ? '\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.' : '')
}

describe('C3/C4 current authenticated objective on Flow reads and replay', () => {
  it.each(['recomposicao', 'ganho_massa', 'manutencao', null] as const)(
    'keeps a relative destination opaque in HTTP replay with objective %s', async (currentProtocol) => {
      const content = 'Veja docs/Bloco7700.md?DAM=1/2#help.'
      const assistant = Object.freeze({ ...oldAssistant, content })
      const { deps, chat, output } = replayDependencies(assistant)
      deps.loadPresentationContext = vi.fn(async () => ({ currentProtocol }))
      const agent = vi.fn(chat.agent.reply); chat.agent.reply = agent
      const response = await handleFlowChatPost(replayContext(), deps)
      const body = await response.json()
      expect(body.data.message).toEqual(assistant)
      expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
      expect(body.meta.request_id).toBe('request-flow-0511')
      expect(response.headers.get('x-request-id')).toBe('request-flow-0511')
      expect(response.headers.get('cache-control')).toBe('no-store')
      expect(response.headers.get('vary')).toBe('Authorization')
      expect(agent).not.toHaveBeenCalled()
      expect(output.content).toBe(content)
    },
  )
  it('keeps historical English feedback when a replay URL contains a Portuguese block token', async () => {
    const content = '7,700 Block: 3,120 kcal.\nhttps://example.invalid/Bloco7700'
    const assistant = Object.freeze({ ...oldAssistant, content })
    const { deps, chat, output } = replayDependencies(assistant)
    deps.loadPresentationContext = vi.fn(async () => ({ currentProtocol: 'ganho_massa' as const }))
    const agent = vi.fn(chat.agent.reply); chat.agent.reply = agent
    const response = await handleFlowChatPost(replayContext('pt-BR'), deps)
    const body = await response.json()
    expect(body.data.message).toEqual({ ...assistant,
      content: 'https://example.invalid/Bloco7700\n\nThe 7,700 Block is displayed only for body recomposition.\n\nYour suggestion is ready to review in the app.',
    })
    expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
    expect(body.meta.request_id).toBe('request-flow-0511')
    expect(response.headers.get('x-request-id')).toBe('request-flow-0511')
    expect(agent).not.toHaveBeenCalled()
    expect(output.content).toBe(content)
  })
  it.each([
    ['Déficit acumulado (bloco 7700): 3120 kcal — evite amendoim por sua alergia.', 'ganho_massa', 'pt-BR', 'evite amendoim por sua alergia.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['Days above target (DAM): 1/2; avoid peanuts because of your allergy.', 'recomposicao', 'en', 'avoid peanuts because of your allergy.\n\nYour suggestion is ready to review in the app.'],
    ['Evite amendoim por sua alergia (Dias acima da meta (dam): 1/2).', 'ganho_massa', 'pt-BR', 'Evite amendoim por sua alergia.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['Avoid peanuts because of your allergy (Days above target (dam): 1/2).', 'recomposicao', 'en', 'Avoid peanuts because of your allergy.\n\nYour suggestion is ready to review in the app.'],
    ['Dias acima da meta (dam): **1/2**; evite amendoim por sua alergia.', 'manutencao', 'pt-BR', 'evite amendoim por sua alergia.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['Days above target (dam): **1/2**; avoid peanuts because of your allergy.', 'recomposicao', 'en', 'avoid peanuts because of your allergy.\n\nYour suggestion is ready to review in the app.'],
    ['Déficit acumulado (bloco 7700): **3120** kcal — evite amendoim por sua alergia.', 'ganho_massa', 'pt-BR', 'evite amendoim por sua alergia.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['Bloco 7700: (3120 kcal). Evite amendoim.', 'ganho_massa', 'pt-BR', 'Evite amendoim.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['Orçamento 14 dias: (5850 / 5960 kcal). Evite amendoim.', 'recomposicao', 'pt-BR', 'Evite amendoim.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['- Dias acima da meta (DAM): 1/2; evite amendoim por sua alergia.', 'ganho_massa', 'pt-BR', 'evite amendoim por sua alergia.\n\nSua sugestão está pronta em "Revisar sugestão".'],
    ['| Dias acima da meta (DAM) | **1/2** |\nEvite amendoim por sua alergia.', 'recomposicao', 'pt-BR', 'Evite amendoim por sua alergia.\n\nSua sugestão está pronta em "Revisar sugestão".'],
  ] as const)('keeps the adjacent allergy in HTTP turn-service replay: %s', async (content, currentProtocol, locale, expected) => {
    const assistant = Object.freeze({ ...oldAssistant, content })
    const { deps, chat, output } = replayDependencies(assistant)
    deps.loadPresentationContext = vi.fn(async () => ({ currentProtocol }))
    const agent = vi.fn(chat.agent.reply); chat.agent.reply = agent
    const response = await handleFlowChatPost(replayContext(locale), deps)
    const body = await response.json()
    expect(body.data.message).toEqual({ ...assistant, content: expected })
    expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
    expect(body.meta.request_id).toBe('request-flow-0511')
    expect(response.headers.get('x-request-id')).toBe('request-flow-0511')
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(agent).not.toHaveBeenCalled()
    expect(output.content).toBe(content)
  })
  it.each([false, true])('projects the %s legacy turn-service replay with today’s objective and no provider work', async (legacy) => {
    const { deps, chat, output } = replayDependencies(objectiveAssistant, legacy)
    deps.loadPresentationContext = vi.fn(async () => ({ currentProtocol: 'ganho_massa' as const }))
    const agent = vi.fn(chat.agent.reply); chat.agent.reply = agent
    const response = await handleFlowChatPost(replayContext(), deps)
    const body = await response.json()
    expect(body.data.message).toEqual({ ...objectiveAssistant, content: projectedObjectiveAnswer('ganho_massa') })
    expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
    expect(agent).not.toHaveBeenCalled()
    expect(output.content).toBe(objectiveAssistant.content)
  })
  it.each(['recomposicao', 'ganho_massa', 'manutencao', null] as const)(
    'projects GET with current objective %s while preserving every DTO field and user text', async (currentProtocol) => {
      const { deps, chat } = replayDependencies(objectiveAssistant)
      const literal = 'Meu bloco 7700 está em 3120? Tenho alergia a amendoim e reavaliação em 14 dias.'
      const rows = [stored(objectiveAssistant), stored({ ...objectiveAssistant, id: 'user-old', role: 'user', content: literal,
        created_at: '2026-09-13T19:59:00.000Z' })]
      const original = JSON.stringify(rows)
      chat.store.loadHistory = async (owner, limit) => {
        expect(owner).toBe(userId); expect(limit).toBe(50); return rows
      }
      const load = vi.fn(async () => ({ currentProtocol }))
      deps.loadPresentationContext = load
      const ctx = context('GET')
      const response = await handleFlowChatGet(ctx, deps)
      const body = await response.json()
      expect(body.data.messages).toEqual([
        { ...objectiveAssistant, id: 'user-old', role: 'user', content: literal, created_at: '2026-09-13T19:59:00.000Z' },
        { ...objectiveAssistant, content: projectedObjectiveAnswer(currentProtocol) },
      ])
      expect(load).toHaveBeenCalledTimes(1)
      expect(load).toHaveBeenCalledWith(ctx)
      expect(JSON.stringify(rows)).toBe(original)
      expect(response.headers.get('cache-control')).toBe('no-store')
      expect(response.headers.get('vary')).toBe('Authorization')
    },
  )

  it('reprojects the same HTTP cache from recomp to gain to recomp without changing cache or repeating provider work', async () => {
    const { deps, cache } = replayDependencies(objectiveAssistant)
    const cached = Object.freeze({
      data: Object.freeze({ conversation_id: 'flow', message: objectiveAssistant,
        draft: Object.freeze({ id: 'draft-original', domain: 'nutrition' }) }),
      meta: Object.freeze({ api_version: 'v1', request_id: 'request-original' }),
    })
    const original = JSON.stringify(cached)
    const send = vi.fn(deps.sendMessage); deps.sendMessage = send
    cache.claim = async () => ({ action: 'replay', status: 201, body: cached })
    let currentProtocol: 'recomposicao' | 'ganho_massa' = 'recomposicao'
    const load = vi.fn(async () => ({ currentProtocol })); deps.loadPresentationContext = load
    for (const protocol of ['recomposicao', 'ganho_massa', 'recomposicao'] as const) {
      currentProtocol = protocol
      const response = await handleFlowChatPost(replayContext(), deps)
      const body = await response.json()
      expect(body.data.message).toEqual({ ...objectiveAssistant, content: projectedObjectiveAnswer(protocol) })
      expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
      expect(response.headers.get('idempotency-replayed')).toBe('true')
      expect(response.headers.get('cache-control')).toBe('no-store')
      expect(body.meta.request_id).toBe('request-flow-0511')
    }
    expect(load).toHaveBeenCalledTimes(3)
    expect(send).not.toHaveBeenCalled()
    expect(JSON.stringify(cached)).toBe(original)
  })

  it('keeps a completed HTTP claim when the later objective read fails, then retries only the read with the same key', async () => {
    const { deps, chat, cache } = replayDependencies(objectiveAssistant)
    let cached: unknown
    const complete = vi.fn(async (_claim, _owner, _status, body) => { cached = body })
    const fail = vi.fn(async () => {})
    cache.complete = complete; cache.fail = fail
    chat.store.findInbound = async () => null; chat.store.findAssistant = async () => null
    chat.store.insertInbound = async (input) => stored({ ...objectiveAssistant, role: 'user', content: input.content })
    chat.store.transitionInbound = async () => true
    const agent = vi.fn(async () => ({ text: objectiveAssistant.content, metadata: {} }))
    chat.agent.reply = agent
    const write = vi.fn(async () => stored(objectiveAssistant)); chat.store.insertAssistant = write
    const load = vi.fn(async () => ({ currentProtocol: 'ganho_massa' as const }))
      .mockRejectedValueOnce(new MobileApiError(500, 'data_access_failed', 'Unable to read Flow presentation context'))
    deps.loadPresentationContext = load
    const ctx = replayContext()
    let nextRequestId = ctx.requestId
    const route = createMobileRoute((requestContext) => handleFlowChatPost(requestContext, deps), {
      authenticate: async () => ctx.auth, authorizeEntitlement: async () => {},
      createServiceClient: () => ctx.supabase, createRequestId: () => nextRequestId,
    })
    const failed = await route(ctx.request)
    expect(failed.status).toBe(500)
    expect(failed.headers.get('cache-control')).toBe('no-store')
    expect(failed.headers.get('vary')).toBe('Authorization')
    const error = await failed.json()
    expect(error.error.code).toBe('data_access_failed')
    expect(error).not.toHaveProperty('data')
    expect(JSON.stringify(error)).not.toContain('3.120')
    expect(complete).toHaveBeenCalledTimes(1)
    expect(agent).toHaveBeenCalledTimes(1)
    expect(write).toHaveBeenCalledTimes(1)
    expect(fail).not.toHaveBeenCalled()
    cache.claim = async () => ({ action: 'replay', status: 201, body: cached })
    nextRequestId = 'request-flow-retry'
    const retry = await route(replayContext().request)
    expect(retry.status).toBe(201)
    const retryBody = await retry.json()
    expect(retryBody.data.message.content).toBe(projectedObjectiveAnswer('ganho_massa'))
    expect(retryBody.data.message).toEqual({ ...objectiveAssistant, content: projectedObjectiveAnswer('ganho_massa') })
    expect(retryBody.meta.request_id).toBe('request-flow-retry')
    expect(retry.headers.get('x-request-id')).toBe('request-flow-retry')
    expect(retry.headers.get('idempotency-replayed')).toBe('true')
    expect(load).toHaveBeenCalledTimes(2)
    expect(agent).toHaveBeenCalledTimes(1)
    expect(write).toHaveBeenCalledTimes(1)
    expect(complete).toHaveBeenCalledTimes(1)
    expect(fail).not.toHaveBeenCalled()
  })
})

// C1 replay: exercise the real handler, turn service and HTTP idempotency;
// only the external storage/provider boundaries are synthetic.


function stored(dto: FlowMessageDTO): StoredFlowMessage {
  return Object.freeze({
    id: dto.id,
    role: dto.role,
    content: dto.content,
    state: dto.state,
    requestId: dto.request_id,
    createdAt: dto.created_at,
  })
}

function replayContext(locale = 'pt-BR'): MobileRouteContext {
  const ctx = context('POST', { text: 'qual é o meu BMR?' })
  ctx.request.headers.set('Idempotency-Key', 'flow-key-old')
  ctx.auth.patient.locale = locale
  return ctx
}

function replayDependencies(assistant = oldAssistant, legacy = false) {
  const input = stored({
    ...assistant,
    id: 'input-old',
    role: 'user',
    content: 'qual é o meu BMR?',
    created_at: '2026-09-13T19:59:00.000Z',
  })
  const output = stored(assistant)
  const turnId = legacy ? 'flow-key-old' : scopedFlowProviderMessageId(userId, 'flow-key-old')
  const replyId = legacy ? 'flow-key-old:assistant' : `${turnId}/assistant`
  const unexpectedWrite = async (): Promise<never> => {
    throw new Error('unexpected message write')
  }
  const chat: FlowChatDependencies = {
    store: {
      loadHistory: async (owner, limit) => {
        if (owner !== userId || limit !== 20) throw new Error('history scope changed')
        return [output, input]
      },
      findInbound: async (owner, key) => (owner === userId && key === turnId ? input : null),
      findAssistant: async (owner, key) => (owner === userId && key === replyId ? output : null),
      countRecentExecutions: async () => 0,
      insertInbound: unexpectedWrite,
      insertAssistant: unexpectedWrite,
      transitionInbound: unexpectedWrite,
      failInbound: unexpectedWrite,
      completeInbound: async () => {},
    },
    agent: { reply: unexpectedWrite },
    drafts: {
      findForTurn: async (owner, key) => {
        if (owner !== userId || key !== turnId) throw new Error('draft scope changed')
        return { id: 'draft-original', domain: 'nutrition' }
      },
    },
  }
  const deps = dependencies()
  deps.createChatDependencies = () => chat
  deps.loadHistory = loadFlowHistory
  deps.sendMessage = sendFlowMessage
  const cache: MobileIdempotencyStore = {
    claim: async () => ({ action: 'claimed', claimId: 'claim-new' }),
    complete: async () => {},
    fail: unexpectedWrite,
  }
  deps.executeIdempotent = (ctx, payload, operation) =>
    executeIdempotent(ctx, payload, cache, operation)
  return { deps, cache, chat, input, output }
}

describe('C1 public presentation of stored Flow messages', () => {
  it('GET preserves the user utterance, IDs, ordering and historical official target without mutating rows', async () => {
    const { deps, input, output } = replayDependencies()
    const original = JSON.stringify([input, output])
    const response = await handleFlowChatGet(context('GET', undefined, '?limit=20'), deps)
    const body = await response.json()

    expect(body.data.messages).toEqual([
      {
        ...oldAssistant,
        id: 'input-old',
        role: 'user',
        content: 'qual é o meu BMR?',
        created_at: '2026-09-13T19:59:00.000Z',
      },
      { ...oldAssistant, content: 'Meta oficial: 2.800 kcal. Gordura corporal: 20%.' },
    ])
    expect(JSON.stringify([input, output])).toBe(original)
    expect(body.meta.request_id).toBe('request-flow-0511')
    expect(response.headers.get('vary')).toBe('Authorization')
  })

  it.each([
    false,
    true,
  ])('POST projects the %s legacy service replay without provider work or replacing the proposal', async (legacy) => {
    const { deps, output } = replayDependencies(oldAssistant, legacy)
    const response = await handleFlowChatPost(replayContext(), deps)
    const body = await response.json()
    expect(response.status).toBe(201)
    expect(body.data.message).toEqual({
      ...oldAssistant,
      content:
        'Meta oficial: 2.800 kcal. Gordura corporal: 20%.\n\nSua sugestão está pronta em "Revisar sugestão".',
    })
    expect(body.data.draft).toEqual({ id: 'draft-original', domain: 'nutrition' })
    expect(output.content).toBe(oldAssistant.content)
  })

  it.each([
    [
      'pt-BR',
      'BMR: 1.800 kcal.',
      'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.',
    ],
    [
      'en',
      'BMR: 1,800 kcal.',
      'Check your official targets in Today and your objective details in Profile.',
    ],
  ])('HTTP cache replay uses a neutral %s fallback without inventing a target or claiming it is absent', async (locale, content, expected) => {
    const { deps, cache } = replayDependencies()
    const cached = Object.freeze({
      data: Object.freeze({
        conversation_id: 'flow',
        message: Object.freeze({ ...oldAssistant, content }),
        draft: null,
      }),
      meta: Object.freeze({ api_version: 'v1', request_id: 'request-original' }),
    })
    const before = JSON.stringify(cached)
    cache.claim = async () => ({ action: 'replay', body: cached, status: 201 })
    deps.sendMessage = async () => {
      throw new Error('HTTP replay reached service')
    }
    const response = await handleFlowChatPost(replayContext(locale), deps)
    const body = await response.json()
    expect(body.data.message).toEqual({ ...oldAssistant, content: expected })
    expect(body.meta).toEqual({ api_version: 'v1', request_id: 'request-flow-0511' })
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(response.headers.get('x-request-id')).toBe('request-flow-0511')
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.status).toBe(201)
    expect(JSON.stringify(cached)).toBe(before)
  })

  it('a new turn stores the original official reply while its public response removes only private clauses', async () => {
    const { deps, chat, cache } = replayDependencies()
    const writes: string[] = []
    const savedBodies: unknown[] = []
    chat.store.findInbound = async () => null
    chat.store.findAssistant = async () => null
    chat.store.insertInbound = async (input) =>
      stored({ ...oldAssistant, role: 'user', content: input.content })
    chat.store.transitionInbound = async () => true
    chat.agent.reply = async () => ({
      text: oldAssistant.content,
      metadata: { modelUsed: 'synthetic' },
    })
    chat.store.insertAssistant = async (input) => {
      writes.push(input.content)
      return stored(oldAssistant)
    }
    cache.complete = async (_claim, _owner, _status, body) => {
      savedBodies.push(body)
    }
    const response = await handleFlowChatPost(replayContext(), deps)
    const body = await response.json()
    expect(body.data.message.content).not.toContain('1.800')
    expect(body.data.message.content).toContain('2.800 kcal')
    expect(writes).toEqual([oldAssistant.content])
    expect(savedBodies).toEqual([
      {
        data: {
          conversation_id: 'flow',
          message: oldAssistant,
          draft: { id: 'draft-original', domain: 'nutrition' },
        },
        meta: { api_version: 'v1', request_id: 'request-flow-0511' },
      },
    ])
    cache.claim = async () => ({ action: 'replay', status: 201, body: savedBodies[0] })
    chat.agent.reply = async () => {
      throw new Error('cached replay repeated provider work')
    }
    const replay = await handleFlowChatPost(replayContext(), deps)
    expect((await replay.json()).data.message).toEqual(body.data.message)
    expect(replay.headers.get('idempotency-replayed')).toBe('true')
  })

  it('keeps public exercise, food, amounts and review text in an old proposal', async () => {
    const content =
      'BMR: 1800 kcal.\nAgachamento: 3 séries de 12 repetições, descanso 60 s.\nArroz: 150 g, 195 kcal.\nRevisar sugestão'
    const { deps } = replayDependencies({ ...oldAssistant, content })
    const response = await handleFlowChatPost(replayContext(), deps)
    const body = await response.json()
    expect(body.data.message.content).toBe(
      'Agachamento: 3 séries de 12 repetições, descanso 60 s.\nArroz: 150 g, 195 kcal.\nRevisar sugestão',
    )
    expect(body.data.draft.id).toBe('draft-original')
  })

  it('refuses malformed successful cache bodies rather than returning an unprojected assistant payload', async () => {
    const { deps, cache } = replayDependencies()
    cache.claim = async () => ({
      action: 'replay',
      status: 201,
      body: {
        data: { conversation_id: 'flow', message: { ...oldAssistant, content: { BMR: 1800 } } },
      },
    })
    await expect(handleFlowChatPost(replayContext(), deps)).rejects.toMatchObject({
      status: 500,
      code: 'flow_response_invalid',
    })
  })

  it('preserves typed errors and their retry headers', async () => {
    const { deps } = replayDependencies()
    deps.executeIdempotent = async () =>
      new Response('{"error":{"code":"flow_rate_limited"}}', {
        status: 429,
        headers: { 'Retry-After': '60', 'X-Request-Id': 'request-flow-0511' },
      })
    const response = await handleFlowChatPost(replayContext(), deps)
    expect(response.status).toBe(429)
    expect(response.headers.get('retry-after')).toBe('60')
    expect(await response.text()).toBe('{"error":{"code":"flow_rate_limited"}}')
    expect(deps.loadPresentationContext).not.toHaveBeenCalled()
  })

  it.each([
    'pt-BR',
    'en',
  ])('GET retains an entirely private assistant as a neutral %s message with the same ID', async (locale) => {
    const { deps } = replayDependencies({ ...oldAssistant, content: 'BMR: 1800 kcal.' })
    const ctx = context('GET', undefined, '?limit=20')
    ctx.auth.patient.locale = locale
    const response = await handleFlowChatGet(ctx, deps)
    const body = await response.json()
    expect(body.data.messages.map((message: FlowMessageDTO) => message.id)).toEqual([
      'input-old',
      'assistant-old',
    ])
    expect(body.data.messages[1].content).toBe(
      locale === 'en'
        ? 'Check your official targets in Today and your objective details in Profile.'
        : 'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.',
    )
  })

  it('does not deduplicate two distinct messages that project to the same text', async () => {
    const { deps, chat } = replayDependencies()
    chat.store.loadHistory = async () => [
      stored({ ...oldAssistant, id: 'second', content: 'BMR: 2000 kcal.' }),
      stored({ ...oldAssistant, content: 'BMR: 1800 kcal.' }),
    ]
    const response = await handleFlowChatGet(context('GET', undefined, '?limit=20'), deps)
    const body = await response.json()
    expect(body.data.messages.map((message: FlowMessageDTO) => message.id)).toEqual([
      'second',
      'assistant-old',
    ])
    expect(body.data.messages[0].content).toBe(body.data.messages[1].content)
    expect(body.data.messages[0].content).not.toContain('2000')
  })

  it('retains all 50 chronological IDs and user contents when many assistant replies become the same fallback', async () => {
    const { deps, chat } = replayDependencies()
    const rows = Array.from({ length: 50 }, (_, index) =>
      stored({
        ...oldAssistant,
        id: `history-${index}`,
        role: index % 2 === 0 ? 'user' : 'assistant',
        content: index % 2 === 0 ? `Meu BMR era ${1800 + index}?` : `BMR: ${1800 + index} kcal.`,
        created_at: new Date(Date.UTC(2026, 8, 13, 20, 0, index)).toISOString(),
      }),
    )
    const before = JSON.stringify(rows)
    chat.store.loadHistory = async (owner, limit) => {
      if (owner !== userId || limit !== 50) throw new Error('bounded history scope changed')
      return [...rows].reverse()
    }
    const response = await handleFlowChatGet(context('GET'), deps)
    const body = await response.json()
    expect(body.data.messages).toHaveLength(50)
    expect(body.data.messages.map((message: FlowMessageDTO) => message.id)).toEqual(
      Array.from({ length: 50 }, (_, index) => `history-${index}`),
    )
    for (let index = 0; index < 50; index += 2) {
      expect(body.data.messages[index].content).toBe(`Meu BMR era ${1800 + index}?`)
      expect(body.data.messages[index + 1].content).toBe(
        'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.',
      )
    }
    expect(JSON.stringify(rows)).toBe(before)
  })

  it('drops an old Content-Length while preserving status, replay and recovery headers', async () => {
    const { deps } = replayDependencies()
    const body = {
      data: { conversation_id: 'flow', message: oldAssistant, draft: null },
      meta: { api_version: 'v1', request_id: 'request-original' },
    }
    deps.executeIdempotent = async () =>
      Response.json(body, {
        status: 201,
        statusText: 'Created',
        headers: { 'Content-Length': '9999', 'Idempotency-Replayed': 'true', 'Retry-After': '7' },
      })
    const response = await handleFlowChatPost(replayContext(), deps)
    expect(response.status).toBe(201)
    expect(response.statusText).toBe('Created')
    expect(response.headers.get('content-length')).toBeNull()
    expect(response.headers.get('retry-after')).toBe('7')
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect((await response.json()).data.message.content).not.toContain('BMR')
  })

  it.each([
    {
      data: { conversation_id: 'flow', message: { ...oldAssistant, role: 'user' } },
      meta: { api_version: 'v1', request_id: 'request-original' },
    },
    { data: { conversation_id: 'flow', message: oldAssistant } },
    {
      data: { conversation_id: 'other', message: oldAssistant },
      meta: { api_version: 'v1', request_id: 'request-original' },
    },
  ])('refuses a successful reply with an invalid POST contract', async (body) => {
    const { deps, cache } = replayDependencies()
    cache.claim = async () => ({ action: 'replay', status: 201, body })
    await expect(handleFlowChatPost(replayContext(), deps)).rejects.toMatchObject({
      status: 500,
      code: 'flow_response_invalid',
    })
  })

  it('refuses a non-JSON successful reply without returning its raw body', async () => {
    const { deps } = replayDependencies()
    deps.executeIdempotent = async () => new Response('BMR: 1800 kcal.', { status: 201 })
    await expect(handleFlowChatPost(replayContext(), deps)).rejects.toMatchObject({
      status: 500,
      code: 'flow_response_invalid',
    })
  })

  it('rejects an array state in a real HTTP cache replay without calling the service or mutating the cache', async () => {
    const { deps, cache } = replayDependencies()
    const cached = {
      data: {
        conversation_id: 'flow',
        message: { ...oldAssistant, state: ['completed'] },
        draft: null,
      },
      meta: { api_version: 'v1', request_id: 'request-original' },
    }
    const before = JSON.stringify(cached)
    cache.claim = async () => ({ action: 'replay', status: 201, body: cached })
    const send = vi.fn(deps.sendMessage)
    deps.sendMessage = send
    await expect(handleFlowChatPost(replayContext(), deps)).rejects.toMatchObject({
      status: 500,
      code: 'flow_response_invalid',
    })
    expect(send).not.toHaveBeenCalled()
    expect(JSON.stringify(cached)).toBe(before)
  })

  it.each([
    ['pt-BR', 'BMR: estimated at 1836 kcal.', 'en'],
    ['en', 'BMR: estimado em 1836 kcal.', 'pt-BR'],
    ['pt-BR', 'Activity factors: sedentary 1.2 and moderate 1.55.', 'en'],
    ['en', 'Fatores de atividade: sedentário 1,2 e moderado 1,55.', 'pt-BR'],
    ['pt-BR', 'BMR: approximately 1836 kcal.', 'en'],
    ['en', 'BMR: aproximadamente 1836 kcal.', 'pt-BR'],
    ['pt-BR', 'Basal metabolism: 1836 kcal.', 'en'],
    ['en', 'Taxa metabólica basal: 1836 kcal.', 'pt-BR'],
  ])('keeps the recognizable language of a fully private cached reply (%s, %s)', async (locale, content, storedLocale) => {
    const { deps, cache } = replayDependencies()
    const cached = {
      data: { conversation_id: 'flow', message: { ...oldAssistant, content }, draft: null },
      meta: { api_version: 'v1', request_id: 'request-original' },
    }
    const before = JSON.stringify(cached)
    cache.claim = async () => ({ action: 'replay', status: 201, body: cached })
    const send = vi.fn(deps.sendMessage)
    deps.sendMessage = send
    const response = await handleFlowChatPost(replayContext(locale), deps)
    const body = await response.json()
    expect(body.data.message).toEqual({
      ...oldAssistant,
      content:
        storedLocale === 'en'
          ? 'Check your official targets in Today and your objective details in Profile.'
          : 'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.',
    })
    expect(body.meta).toEqual({ api_version: 'v1', request_id: 'request-flow-0511' })
    expect(response.status).toBe(201)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(send).not.toHaveBeenCalled()
    expect(JSON.stringify(cached)).toBe(before)
  })

  it.each([
    [
      'pt-BR',
      'Your BMR is 1,800 kcal. Your official target: 2,800 kcal. BF: 20%.',
      'Your official target: 2,800 kcal. Body fat: 20%.',
    ],
    [
      'en',
      'Seu BMR é 1.800 kcal. Sua meta oficial: 2.800 kcal. BF: 20%.',
      'Sua meta oficial: 2.800 kcal. Gordura corporal: 20%.',
    ],
  ])('preserves a recognizable stored language when the account locale is now %s', async (locale, content, expected) => {
    const { deps, cache } = replayDependencies()
    cache.claim = async () => ({
      action: 'replay',
      status: 201,
      body: {
        data: { conversation_id: 'flow', message: { ...oldAssistant, content }, draft: null },
        meta: { api_version: 'v1', request_id: 'request-original' },
      },
    })
    const response = await handleFlowChatPost(replayContext(locale), deps)
    expect((await response.json()).data.message.content).toBe(expected)
  })
})
