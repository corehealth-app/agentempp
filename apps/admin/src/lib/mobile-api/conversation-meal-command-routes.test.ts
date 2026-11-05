import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { writerCommand, writerEpoch } from './__fixtures__/conversation-meal-writer'
import {
  conversationMealCommandsEnabled,
  createConversationMealCommandRoutes,
} from './conversation-meal-command-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

const command = writerCommand(),
  url = 'https://app.invalid/api/mobile/v1/conversation/meal-commands'
function fixture() {
  const submit = vi
      .fn()
      .mockResolvedValue({ status: 'saved', schema: 'conversation.meal-command-result.v1' }),
    read = vi
      .fn()
      .mockResolvedValue({ status: 'pending', schema: 'conversation.meal-command-state.v1' }),
    session = vi.fn().mockResolvedValue({
      schema: 'conversation.session.v1',
      owner_id: command.ownerId,
      epoch: writerEpoch,
      observed_at: '2026-11-04T12:00:00Z',
      meal_command_protocol: 'conversation.command.v1',
    }),
    service = vi.fn(() => ({ submit, read, session })),
    enabled = vi.fn(() => true),
    db = {} as ServiceClient
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => db,
    authenticate: vi.fn(async () => candidateAuth),
    authorizeEntitlement: vi.fn(async () => {}),
    createRequestId: () => 'command-route-test',
  }
  return {
    submit,
    session,
    read,
    service,
    enabled,
    runtime,
    routes: createConversationMealCommandRoutes({ enabled, service }, runtime),
  }
}
function request(
  method = 'POST',
  body: unknown = command.command,
  headers: Record<string, string> = {},
) {
  return new Request(method === 'GET' ? `${url}/${command.commandId}` : url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': `cmsg1:${command.commandId}`,
      'X-Conversation-Epoch': writerEpoch,
      'X-Conversation-Owner': command.ownerId,
      'X-Conversation-Input-Hash': command.inputHash,
      ...headers,
    },
    ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
  })
}
describe('new authenticated conversation meal command routes', () => {
  it.each([
    'POST',
    'GET',
  ])('negotiates presentation2 on %s without changing protocol or authority', async (method) => {
    const f = fixture(),
      r = request(method, command.command, { 'X-Conversation-Feedback-Presentation': '2' })
    const response =
      method === 'POST'
        ? await f.routes.POST(r)
        : await f.routes.GET(r, { params: Promise.resolve({ commandId: command.commandId }) })
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
    expect(response.headers.get('Vary')).toBe('Authorization, X-Conversation-Feedback-Presentation')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-command-v1')
    expect((method === 'POST' ? f.submit : f.read).mock.calls[0].at(-1)).toBe('2')
  })
  it.each(['unknown', '3', '02', '2, 2'])('retains old root negotiation for %s', async (value) => {
    const f = fixture(),
      response = await f.routes.POST(
        request('POST', command.command, { 'X-Conversation-Feedback-Presentation': value }),
      )
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBeNull()
    expect(f.submit).toHaveBeenCalledWith(
      candidateAuth,
      `cmsg1:${command.commandId}`,
      command.command,
      writerEpoch,
    )
  })
  it('requires the same auth/entitlement for current server session observation', async () => {
    const f = fixture(),
      response = await f.routes.SESSION(
        new Request('https://app.invalid/api/mobile/v1/conversation/session'),
      )
    expect(response.status).toBe(200)
    expect(f.session).toHaveBeenCalledWith(candidateAuth)
    expect(f.submit).not.toHaveBeenCalled()
    expect(f.read).not.toHaveBeenCalled()
  })
  it('requires auth/entitlement and passes the exact body/key/originalepoch to the new service', async () => {
    const f = fixture(),
      response = await f.routes.POST(request())
    expect(response.status).toBe(200)
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(f.submit).toHaveBeenCalledWith(
      candidateAuth,
      `cmsg1:${command.commandId}`,
      command.command,
      writerEpoch,
    )
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect((await response.json()).meta).toEqual({
      api_version: 'v1',
      request_id: 'command-route-test',
    })
  })
  it('reconciles through GET read only with the exact original hash and epoch', async () => {
    const f = fixture(),
      response = await f.routes.GET(request('GET'), {
        params: Promise.resolve({ commandId: command.commandId }),
      })
    expect(response.status).toBe(202)
    expect(f.read).toHaveBeenCalledWith(
      candidateAuth,
      command.commandId,
      command.inputHash,
      writerEpoch,
    )
    expect(f.submit).not.toHaveBeenCalled()
  })
  it('refuses a changed authenticated patient before any service despite a matching epoch', async () => {
    const f = fixture(),
      headers = { 'X-Conversation-Owner': '10000000-0000-4000-8000-000000000099' }
    const post = await f.routes.POST(request('POST', command.command, headers))
    expect(post.status).toBe(409)
    expect((await post.json()).error.code).toBe('conversation_patient_changed')
    const get = await f.routes.GET(request('GET', undefined, headers), {
      params: Promise.resolve({ commandId: command.commandId }),
    })
    expect(get.status).toBe(409)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('requires an explicit canonical original patient precondition, never the auth subject as a substitute', async () => {
    const f = fixture(),
      req = request()
    req.headers.delete('X-Conversation-Owner')
    expect((await f.routes.POST(req)).status).toBe(422)
    expect(
      (await f.routes.POST(request('POST', command.command, { 'X-Conversation-Owner': 'invalid' })))
        .status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('does not build services or initialize providers when capability is disabled', async () => {
    const f = fixture()
    f.enabled.mockReturnValue(false)
    expect((await f.routes.POST(request())).status).toBe(503)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'owner_id',
    'epoch',
    'calories',
    'expected_state',
    'receipt',
  ])('rejects extra client authority %s before service construction', async (key) => {
    const f = fixture(),
      response = await f.routes.POST(
        request('POST', { ...command.command, [key]: 'not authority' }),
      )
    expect(response.status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'Idempotency-Key',
    'X-Conversation-Epoch',
  ])('rejects invalid %s before service calls', async (key) => {
    const f = fixture()
    expect(
      (await f.routes.POST(request('POST', command.command, { [key]: 'invalid' }))).status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('does not treat arbitrary HTTP success as a saved result; pending and decisions retain their status', async () => {
    const f = fixture()
    f.submit.mockResolvedValue({
      status: 'not_recorded',
      schema: 'conversation.meal-command-state.v1',
    })
    const r = await f.routes.POST(request())
    expect(r.status).toBe(200)
    expect((await r.json()).data.status).toBe('not_recorded')
  })
  it.each([401, 402])('blocks %i before constructing a command service', async (code) => {
    const f = fixture(),
      failure = async () => {
        throw new MobileApiError(code, 'access_denied', 'Access required')
      }
    if (code === 401) f.runtime.authenticate = failure
    else f.runtime.authorizeEntitlement = failure
    const routes = createConversationMealCommandRoutes(
      { enabled: f.enabled, service: f.service },
      f.runtime,
    )
    expect((await routes.POST(request())).status).toBe(code)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects duplicate JSON keys using the shared strict decoder', async () => {
    const f = fixture(),
      req = request(),
      bad = new Request(req.url, {
        method: 'POST',
        headers: req.headers,
        body: '{"command_id":"one","command_id":"two"}',
      })
    expect((await f.routes.POST(bad)).status).toBe(400)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('validates read identity and original hash before accessing a command', async () => {
    const f = fixture()
    expect(
      (
        await f.routes.GET(request('GET', undefined, { 'X-Conversation-Input-Hash': 'invalid' }), {
          params: Promise.resolve({ commandId: command.commandId }),
        })
      ).status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
})

describe('server-owned command capability target', () => {
  const target = {
    MOBILE_CONVERSATION_COMMANDS_ENABLED: 'true',
    MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  }
  it('requires explicit true and the established current staging runtime', () => {
    expect(conversationMealCommandsEnabled(target)).toBe(true)
    for (const flag of [undefined, '', 'TRUE', '1', ' true '])
      expect(
        conversationMealCommandsEnabled({ ...target, MOBILE_CONVERSATION_COMMANDS_ENABLED: flag }),
      ).toBe(false)
    expect(conversationMealCommandsEnabled({})).toBe(false)
  })
  it('never selects protected legacy, another host, local QA or a decorated URL from request/config mistakes', () => {
    for (const url of [
      'https://xuxehkhdvjivitduarvb.supabase.co',
      'http://127.0.0.1:22980',
      'https://xitugspwfxkcluxvrdeg.supabase.co/path',
      'https://xitugspwfxkcluxvrdeg.supabase.co?x=1',
      'https://unrelated.invalid',
    ])
      expect(conversationMealCommandsEnabled({ ...target, NEXT_PUBLIC_SUPABASE_URL: url })).toBe(
        false,
      )
    expect(
      conversationMealCommandsEnabled({
        ...target,
        MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xuxehkhdvjivitduarvb',
      }),
    ).toBe(false)
    expect(
      conversationMealCommandsEnabled({
        ...target,
        MOBILE_CURRENT_CLINICAL_PROJECT_REF: undefined,
      }),
    ).toBe(false)
  })
})
