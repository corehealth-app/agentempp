import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { writerEpoch } from './__fixtures__/conversation-meal-writer'
import { bindConversationIntake } from './conversation-intake-contracts'
import {
  conversationIntakesEnabled,
  createConversationIntakeRoutes,
} from './conversation-intake-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

const bound = bindConversationIntake(
    candidateAuth.userId,
    'cintake1:198c0000-0000-4000-8000-000000000001',
    {
      intake_protocol: 'conversation.intake.v1',
      intake_id: '198c0000-0000-4000-8000-000000000001',
      source: { channel: 'text', text: 'Fiz 30 minutos de caminhada leve' },
    },
  ),
  url = 'https://app.invalid/api/mobile/v1/conversation/intakes'
const identity = {
  ownerId: bound.ownerId,
  intakeId: bound.intakeId,
  inputHash: bound.inputHash,
  epoch: writerEpoch,
}
function fixture() {
  const submit = vi.fn().mockResolvedValue({
      schema: 'conversation.intake-result.v1',
      status: 'pending',
      lookup: identity,
      intake: null,
      reason: 'intake_pending',
    }),
    read = vi.fn().mockResolvedValue({
      schema: 'conversation.intake-result.v1',
      status: 'absent',
      lookup: identity,
    }),
    sessionRead = vi.fn().mockResolvedValue({
      schema: 'conversation.intake-session.v1',
      auth_user_id: candidateAuth.authUserId,
      owner_id: bound.ownerId,
      epoch: writerEpoch,
      observed_at: '2026-11-05T10:00:00Z',
      intake_protocol: 'conversation.intake.v1',
    }),
    service = vi.fn(() => ({ submit, read })),
    session = vi.fn(() => ({ read: sessionRead })),
    enabled = vi.fn(() => true),
    db = {} as ServiceClient
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => db,
    authenticate: vi.fn(async () => candidateAuth),
    authorizeEntitlement: vi.fn(async () => {}),
    createRequestId: () => 'intake-route-test',
  }
  return {
    submit,
    read,
    sessionRead,
    service,
    session,
    enabled,
    runtime,
    db,
    routes: createConversationIntakeRoutes({ service, session, enabled }, runtime),
  }
}
function request(method = 'POST', body: unknown = bound.input, extra: Record<string, string> = {}) {
  return new Request(method === 'GET' ? `${url}/${bound.intakeId}` : url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': `cintake1:${bound.intakeId}`,
      'X-Conversation-Owner': bound.ownerId,
      'X-Conversation-Epoch': writerEpoch,
      'X-Conversation-Input-Hash': bound.inputHash,
      ...extra,
    },
    ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
  })
}
describe('genuine neutral intake authenticated HTTP routes', () => {
  it('binds the original neutral body without a meal/workout kind or fabricated typed identity', async () => {
    const h = fixture(),
      response = await h.routes.POST(request())
    expect(response.status).toBe(202)
    expect(response.headers.get('X-Conversation-Protocol')).toBe('intake-v1')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(h.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(h.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(h.service).toHaveBeenCalledWith(h.db, candidateAuth, identity)
    expect(h.submit).toHaveBeenCalledWith(bound, 'legacy')
    expect(h.read).not.toHaveBeenCalled()
    expect(h.session).not.toHaveBeenCalled()
  })
  it('GET observes only the original neutral lookup and never submits', async () => {
    const h = fixture(),
      response = await h.routes.GET(request('GET'), {
        params: Promise.resolve({ intakeId: bound.intakeId }),
      })
    expect(response.status).toBe(200)
    expect(h.service).toHaveBeenCalledWith(h.db, candidateAuth, identity)
    expect(h.read).toHaveBeenCalledWith('legacy')
    expect(h.submit).not.toHaveBeenCalled()
    expect(h.session).not.toHaveBeenCalled()
  })
  it('discovers a genuine neutral session without constructing any command runtime', async () => {
    const h = fixture(),
      response = await h.routes.SESSION(new Request(`${url}/session`))
    expect(response.status).toBe(200)
    expect(response.headers.get('X-Conversation-Protocol')).toBe('intake-v1')
    expect((await response.json()).data.schema).toBe('conversation.intake-session.v1')
    expect(h.sessionRead).toHaveBeenCalledWith(candidateAuth)
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([
    'POST',
    'GET',
    'SESSION',
  ] as const)('refuses %s with capability off before constructing either service', async (method) => {
    const h = fixture()
    h.enabled.mockReturnValue(false)
    const response =
      method === 'GET'
        ? await h.routes.GET(request('GET'), {
            params: Promise.resolve({ intakeId: bound.intakeId }),
          })
        : await h.routes[method](request(method === 'SESSION' ? 'GET' : 'POST'))
    expect(response.status).toBe(503)
    expect(h.service).not.toHaveBeenCalled()
    expect(h.session).not.toHaveBeenCalled()
  })
  it.each([
    401, 402,
  ])('preserves Auth and entitlement refusal %s before construction', async (status) => {
    const h = fixture(),
      deny = async () => {
        throw new MobileApiError(status, 'access_denied', 'Access required')
      }
    if (status === 401) h.runtime.authenticate = deny
    else h.runtime.authorizeEntitlement = deny
    const routes = createConversationIntakeRoutes(
      { service: h.service, session: h.session, enabled: h.enabled },
      h.runtime,
    )
    expect((await routes.POST(request())).status).toBe(status)
    expect(h.service).not.toHaveBeenCalled()
    expect(h.session).not.toHaveBeenCalled()
  })
  it.each([
    'owner_id',
    'epoch',
    'kind',
    'estimated_kcal',
    'receipt',
    'feedback',
    'selection',
  ])('refuses client authority field %s before runtime construction', async (field) => {
    const h = fixture()
    expect(
      (await h.routes.POST(request('POST', { ...bound.input, [field]: 'untrusted' }))).status,
    ).toBe(422)
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([
    '',
    'cmsg1:198c0000-0000-4000-8000-000000000001',
    'cintake1:198c0000-0000-4000-8000-000000000002',
  ])('refuses mismatched or typed key %s', async (key) => {
    const h = fixture()
    expect(
      (await h.routes.POST(request('POST', bound.input, { 'Idempotency-Key': key }))).status,
    ).toBe(422)
    expect(h.service).not.toHaveBeenCalled()
  })
  it('requires patient mapping rather than accepting Auth subject as the owner', async () => {
    const h = fixture(),
      wrong = '198c0000-0000-4000-8000-000000000099'
    expect(
      (await h.routes.POST(request('POST', bound.input, { 'X-Conversation-Owner': wrong }))).status,
    ).toBe(409)
    expect(
      (
        await h.routes.GET(request('GET', undefined, { 'X-Conversation-Owner': wrong }), {
          params: Promise.resolve({ intakeId: bound.intakeId }),
        })
      ).status,
    ).toBe(409)
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([
    'X-Conversation-Owner',
    'X-Conversation-Epoch',
    'X-Conversation-Input-Hash',
  ])('refuses missing/malformed %s on GET', async (header) => {
    const h = fixture()
    expect(
      (
        await h.routes.GET(request('GET', undefined, { [header]: '' }), {
          params: Promise.resolve({ intakeId: bound.intakeId }),
        })
      ).status,
    ).toBe(422)
    expect(h.service).not.toHaveBeenCalled()
  })
  it('rejects duplicate JSON keys before any command or provider construction', async () => {
    const h = fixture(),
      original = request(),
      req = new Request(original.url, {
        method: 'POST',
        headers: original.headers,
        body: `{"intake_protocol":"conversation.intake.v1","intake_id":"${bound.intakeId}","source":{"channel":"text","text":"Comi arroz","text":"Vou comer arroz"}}`,
      })
    const response = await h.routes.POST(req)
    // Duplicate keys are invalid JSON in the established bounded parser.
    expect(response.status).toBe(400)
    expect((await response.json()).error.code).toBe('invalid_json')
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([
    'POST',
    'GET',
  ] as const)('negotiates presentation2 only and preserves variance for %s', async (method) => {
    const h = fixture(),
      req = request(method, bound.input, { 'X-Conversation-Feedback-Presentation': '2' }),
      response =
        method === 'POST'
          ? await h.routes.POST(req)
          : await h.routes.GET(req, { params: Promise.resolve({ intakeId: bound.intakeId }) })
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
    expect(response.headers.get('Vary')).toBe('Authorization, X-Conversation-Feedback-Presentation')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(method === 'POST' ? h.submit.mock.calls[0]?.[1] : h.read.mock.calls[0]?.[0]).toBe('2')
  })
  it.each([
    [{ status: 'pending' }, 202],
    [{ status: 'held' }, 202],
    [{ status: 'selected', result: { status: 'pending' } }, 202],
    [{ status: 'selected', result: { status: 'saved' } }, 200],
    [{ status: 'clarification_required' }, 200],
    [{ status: 'not_recorded' }, 200],
    [{ status: 'absent' }, 200],
  ] as const)('does not mistake a selected or held parent for a completed HTTP effect: %j', async (value, status) => {
    const h = fixture()
    h.submit.mockResolvedValue(value)
    expect((await h.routes.POST(request())).status).toBe(status)
  })
})
describe('trusted neutral intake capability', () => {
  const staging = {
    NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
    MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    MOBILE_CONVERSATION_COMMANDS_ENABLED: 'true',
    MOBILE_CONVERSATION_WORKOUT_COMMANDS_ENABLED: 'true',
  }
  it('keeps neutral transport off despite existing meal/workout capabilities', () => {
    expect(conversationIntakesEnabled(staging)).toBe(false)
  })
  it('requires its own opt-in and all real typed capabilities on the exact staging target', () => {
    const enabled = { ...staging, MOBILE_CONVERSATION_INTAKES_ENABLED: 'true' }
    expect(conversationIntakesEnabled(enabled)).toBe(true)
    for (const field of Object.keys(enabled))
      expect(conversationIntakesEnabled({ ...enabled, [field]: '' })).toBe(false)
    expect(
      conversationIntakesEnabled({
        ...enabled,
        NEXT_PUBLIC_SUPABASE_URL: 'https://xuxehkhdvjivitduarvb.supabase.co',
      }),
    ).toBe(false)
  })
})
