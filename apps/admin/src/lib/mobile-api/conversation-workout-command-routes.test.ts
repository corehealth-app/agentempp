import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { writerEpoch } from './__fixtures__/conversation-meal-writer'
import {
  conversationWorkoutCommandsEnabled,
  createConversationWorkoutCommandRoutes,
} from './conversation-workout-command-routes'
import { bindConversationWorkoutCommand } from './conversation-workout-contracts'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

const command = bindConversationWorkoutCommand(
    candidateAuth.userId,
    'cmsg1:198c0000-0000-4000-8000-000000000001',
    {
      command_protocol: 'conversation.command.v1',
      command_id: '198c0000-0000-4000-8000-000000000001',
      kind: 'workout.report',
      source: { channel: 'text', text: 'Fiz 30 minutos de caminhada leve' },
    },
  ),
  url = 'https://app.invalid/api/mobile/v1/conversation/workout-commands'
function fixture() {
  const submit = vi
      .fn()
      .mockResolvedValue({ schema: 'conversation.workout-command-state.v1', status: 'pending' }),
    read = vi
      .fn()
      .mockResolvedValue({ schema: 'conversation.workout-command-state.v1', status: 'absent' }),
    session = vi.fn().mockResolvedValue({
      schema: 'conversation.workout-session.v1',
      owner_id: candidateAuth.userId,
      epoch: writerEpoch,
    }),
    service = vi.fn(() => ({ submit, read, session })),
    enabled = vi.fn(() => true),
    db = {} as ServiceClient
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => db,
    authenticate: vi.fn(async () => candidateAuth),
    authorizeEntitlement: vi.fn(async () => {}),
    createRequestId: () => 'workout-route-test',
  }
  return {
    submit,
    read,
    session,
    service,
    enabled,
    runtime,
    routes: createConversationWorkoutCommandRoutes({ service, enabled }, runtime),
  }
}
function request(
  method = 'POST',
  body: unknown = command.command,
  extra: Record<string, string> = {},
) {
  return new Request(method === 'GET' ? `${url}/${command.commandId}` : url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': `cmsg1:${command.commandId}`,
      'X-Conversation-Owner': command.ownerId,
      'X-Conversation-Epoch': writerEpoch,
      'X-Conversation-Input-Hash': command.inputHash,
      ...extra,
    },
    ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
  })
}
describe('separate authenticated workout command HTTP routes', () => {
  it('uses normal Auth/entitlement and preserves the exact submitted workout identity', async () => {
    const h = fixture(),
      response = await h.routes.POST(request())
    expect(response.status).toBe(202)
    expect(response.headers.get('X-Conversation-Protocol')).toBe('workout-command-v1')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(h.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(h.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(h.submit).toHaveBeenCalledWith(
      candidateAuth,
      `cmsg1:${command.commandId}`,
      command.command,
      writerEpoch,
    )
    expect(h.read).not.toHaveBeenCalled()
  })
  it('reconciles by the original hash and epoch without submitting or enriching', async () => {
    const h = fixture(),
      response = await h.routes.GET(request('GET'), {
        params: Promise.resolve({ commandId: command.commandId }),
      })
    expect(response.status).toBe(200)
    expect(h.read).toHaveBeenCalledWith(
      candidateAuth,
      command.commandId,
      command.inputHash,
      writerEpoch,
    )
    expect(h.submit).not.toHaveBeenCalled()
    expect(h.session).not.toHaveBeenCalled()
  })
  it('offers a separate existing-account session without constructing a workout command', async () => {
    const h = fixture(),
      response = await h.routes.SESSION(
        new Request('https://app.invalid/api/mobile/v1/conversation/workout-session'),
      )
    expect(response.status).toBe(200)
    expect(h.session).toHaveBeenCalledWith(candidateAuth)
    expect(h.submit).not.toHaveBeenCalled()
    expect(h.read).not.toHaveBeenCalled()
  })
  it('does not construct any service when the server capability is off', async () => {
    const h = fixture()
    h.enabled.mockReturnValue(false)
    expect((await h.routes.POST(request())).status).toBe(503)
    expect(
      (await h.routes.SESSION(new Request('https://app.invalid/workout-session'))).status,
    ).toBe(503)
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([401, 402])('refuses %s before constructing the service', async (status) => {
    const h = fixture(),
      deny = async () => {
        throw new MobileApiError(status, 'access_denied', 'Access required')
      }
    if (status === 401) h.runtime.authenticate = deny
    else h.runtime.authorizeEntitlement = deny
    const routes = createConversationWorkoutCommandRoutes(
      { service: h.service, enabled: h.enabled },
      h.runtime,
    )
    expect((await routes.POST(request())).status).toBe(status)
    expect(h.service).not.toHaveBeenCalled()
  })
  it('rejects another owner and an Auth subject supplied instead of the patient', async () => {
    const h = fixture(),
      subject = '198c0000-0000-4000-8000-000000000099',
      mapped = {
        ...candidateAuth,
        authUserId: subject,
        identity: { ...candidateAuth.identity, id: subject },
        patient: { ...candidateAuth.patient, authUserId: subject },
      },
      wrong = { 'X-Conversation-Owner': subject }
    h.runtime.authenticate = vi.fn(async () => mapped)
    expect(subject).not.toBe(command.ownerId)
    expect((await h.routes.POST(request('POST', command.command, wrong))).status).toBe(409)
    expect(
      (
        await h.routes.GET(request('GET', undefined, wrong), {
          params: Promise.resolve({ commandId: command.commandId }),
        })
      ).status,
    ).toBe(409)
    expect(h.service).not.toHaveBeenCalled()
  })
  it.each([
    'owner_id',
    'epoch',
    'estimated_kcal',
    'receipt',
    'feedback',
  ])('refuses client authority field %s', async (field) => {
    const h = fixture()
    expect(
      (await h.routes.POST(request('POST', { ...command.command, [field]: 'untrusted' }))).status,
    ).toBe(422)
    expect(h.service).not.toHaveBeenCalled()
  })
  it('does not reinterpret a meal as a workout or replace the original idempotency key', async () => {
    const h = fixture()
    expect(
      (await h.routes.POST(request('POST', { ...command.command, kind: 'meal.report' }))).status,
    ).toBe(422)
    expect(
      (await h.routes.POST(request('POST', command.command, { 'Idempotency-Key': 'another-key' })))
        .status,
    ).toBe(422)
    expect(h.service).not.toHaveBeenCalled()
  })
})
describe('trusted workout capability selection', () => {
  const staging = {
    NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
    MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    MOBILE_CONVERSATION_COMMANDS_ENABLED: 'true',
  }
  it('does not activate this new transport merely because the old meal and workout features are on', () => {
    expect(conversationWorkoutCommandsEnabled(staging)).toBe(false)
  })
  it('requires its own capability and the existing switches on the one current staging target', () => {
    const enabled = { ...staging, MOBILE_CONVERSATION_WORKOUT_COMMANDS_ENABLED: 'true' }
    expect(conversationWorkoutCommandsEnabled(enabled)).toBe(true)
    for (const field of [
      'MOBILE_CONVERSATION_WORKOUT_COMMANDS_ENABLED',
      'MOBILE_CURRENT_CLINICAL_PROJECT_REF',
      'MOBILE_WORKOUT_REGISTRATION_PROJECT_REF',
      'MOBILE_CONVERSATION_COMMANDS_ENABLED',
    ])
      expect(conversationWorkoutCommandsEnabled({ ...enabled, [field]: '' })).toBe(false)
    expect(
      conversationWorkoutCommandsEnabled({
        ...enabled,
        MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: 'xitugspwfxkcluxvrdeg,xuxehkhdvjivitduarvb',
      }),
    ).toBe(false)
    expect(
      conversationWorkoutCommandsEnabled({
        ...enabled,
        NEXT_PUBLIC_SUPABASE_URL: 'https://xuxehkhdvjivitduarvb.supabase.co',
      }),
    ).toBe(false)
  })
})

it.each([
  'POST',
  'GET',
] as const)('negotiates only presentation2 in workout %s and retains Auth variance', async (method) => {
  const h = fixture(),
    req = request(method, command.command, { 'X-Conversation-Feedback-Presentation': '2' }),
    response =
      method === 'POST'
        ? await h.routes.POST(req)
        : await h.routes.GET(req, { params: Promise.resolve({ commandId: command.commandId }) })
  expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
  expect(response.headers.get('Vary')).toBe('Authorization, X-Conversation-Feedback-Presentation')
  expect(response.headers.get('Cache-Control')).toBe('no-store')
  expect(response.headers.get('X-Conversation-Protocol')).toBe('workout-command-v1')
  const call = method === 'POST' ? h.submit : h.read
  expect(call.mock.calls[0]?.[4]).toBe('2')
})
