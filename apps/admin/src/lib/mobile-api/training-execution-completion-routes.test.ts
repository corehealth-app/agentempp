import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { MobileRouteRuntime } from './route'
import golden from './testing/training-completion-pg-golden.json'
import { createTrainingExecutionCompletionRoutes } from './training-execution-completion-routes'

function setup(enabled = true, replace = false) {
  const owner = golden.begin.scope.owner_id,
    auth = golden.begin.scope.auth_user_id,
    login = '139d0000-0000-4000-8000-000000000005'
  const token = `e30.${Buffer.from(JSON.stringify({ sub: auth, session_id: login })).toString('base64url')}.synthetic`
  let checks = 0
  const current = () =>
    ({
      accessToken: token,
      authUserId: auth,
      userId: owner,
      identity: {
        id: auth,
        email: 'r140-route@example.invalid',
        emailConfirmedAt: '2026-11-14T00:00:00Z',
      },
      patient: {
        id: owner,
        authUserId: auth,
        email: 'r140-route@example.invalid',
        name: 'Synthetic R140 route',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    }) as MobileAuthContext
  const runtime: MobileRouteRuntime = {
    authenticate: async () => {
      const who = current()
      if (++checks > 1 && replace) who.accessToken = 'replacement'
      return who
    },
    authorizeEntitlement: async () => {},
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'r140-route',
  }
  const methods = {
    home: vi.fn(async () => ({ schema: 'safe-home' })),
    state: vi.fn(async () => ({ schema: 'safe-state' })),
    submit: vi.fn(async () => ({ schema: 'safe-finish', status: 'completed' })),
    read: vi.fn(async () => ({ schema: 'safe-read' })),
    cancel: vi.fn(async () => ({ schema: 'safe-cancel' })),
  }
  const routes = createTrainingExecutionCompletionRoutes(
    { enabled: () => enabled, service: () => methods },
    runtime,
  )
  const headers = {
    'Content-Type': 'application/json',
    'X-Training-Owner': owner,
    'X-Training-Epoch': golden.command.expected_epoch,
    'X-Training-Completion-Hash': golden.begin.completion.input_hash,
    'Idempotency-Key': `tfinish1:${golden.command.operation_id}`,
  }
  const request = (
    path = '/completions',
    body: unknown = golden.command,
    extra: Record<string, string> = {},
  ) =>
    new Request(`https://unit.invalid/api/mobile/v1/training/execution-v2${path}`, {
      method: body === null ? 'GET' : 'POST',
      headers: { ...headers, ...extra },
      ...(body === null ? {} : { body: JSON.stringify(body) }),
    })
  const params = {
    params: Promise.resolve({
      sessionId: golden.command.session_id,
      completionId: golden.command.operation_id,
    }),
  }
  return { routes, methods, request, params, headers }
}
describe('closed completion route family preserves old progress endpoints', () => {
  it('disabled completion cannot dispatch a new state read or write', async () => {
    const h = setup(false)
    expect((await h.routes.POST(h.request())).status).toBe(503)
    expect(h.methods.submit).not.toHaveBeenCalled()
  })
  it.each([
    [{ ...golden.command, calories: 900 }, {}, 422],
    [golden.command, { 'X-Training-Owner': golden.begin.scope.auth_user_id }, 409],
    [golden.command, { 'X-Training-Epoch': golden.begin.scope.auth_user_id }, 409],
    [golden.command, { 'Idempotency-Key': 'other' }, 422],
  ])('refuses request authority/owner/epoch/key changes before dispatch', async (body, extra, status) => {
    const h = setup()
    expect((await h.routes.POST(h.request('/completions', body, extra))).status).toBe(status)
    expect(h.methods.submit).not.toHaveBeenCalled()
  })
  it('dispatches exactly the original accepted report once with explicit private protocol', async () => {
    const h = setup(),
      r = await h.routes.POST(h.request())
    expect(r.status).toBe(200)
    expect(r.headers.get('X-Training-Execution')).toBe('2')
    expect(r.headers.get('X-Training-Completion')).toBe('1')
    expect(r.headers.get('Cache-Control')).toBe('no-store')
    expect(h.methods.submit).toHaveBeenCalledTimes(1)
    expect(h.methods.submit).toHaveBeenCalledWith(
      `tfinish1:${golden.command.operation_id}`,
      golden.command,
    )
  })
  it('does not adopt a replacement Auth token between initial authentication and dispatch', async () => {
    const h = setup(true, true)
    expect((await h.routes.POST(h.request())).status).toBe(409)
    expect(h.methods.submit).not.toHaveBeenCalled()
  })
  it('uses only an opaque expected hash for a cold read; source text is not a URL argument', async () => {
    const h = setup(),
      r = await h.routes.READ(
        h.request(`/${golden.command.session_id}/completions/${golden.command.operation_id}`, null),
        h.params,
      )
    expect(r.status).toBe(200)
    expect(h.methods.read).toHaveBeenCalledWith({
      session_id: golden.command.session_id,
      completion_id: golden.command.operation_id,
      epoch: golden.command.expected_epoch,
      input_hash: golden.begin.completion.input_hash,
    })
    expect(h.methods.submit).not.toHaveBeenCalled()
  })
  it('binds safe cancellation to the same path, epoch, hash and operation key', async () => {
    const h = setup(),
      body = {
        schema: 'training.execution.finish-cancel.v1',
        session_id: golden.command.session_id,
        completion_id: golden.command.operation_id,
        expected_epoch: golden.command.expected_epoch,
        input_hash: golden.begin.completion.input_hash,
      }
    const r = await h.routes.CANCEL(
      h.request(`/${body.session_id}/completions/${body.completion_id}/cancel`, body, {
        'Idempotency-Key': `tcancel1:${body.completion_id}`,
      }),
      h.params,
    )
    expect(r.status).toBe(200)
    expect(h.methods.cancel).toHaveBeenCalledTimes(1)
    expect(h.methods.submit).not.toHaveBeenCalled()
  })
  it('rejects extra history queries rather than leaking private context through ad-hoc lookup', async () => {
    const h = setup(),
      r = await h.routes.STATE(
        h.request(`/${golden.command.session_id}?source=private`, null),
        h.params,
      )
    expect(r.status).toBe(422)
    expect(h.methods.state).not.toHaveBeenCalled()
  })
})
