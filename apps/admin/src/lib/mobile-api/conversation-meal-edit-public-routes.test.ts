import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { editBinding, editInput, editOperationId } from './__fixtures__/conversation-meal-edit'
import { createConversationMealEditPublicRoutes } from './conversation-meal-edit-public-routes'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

const b = editBinding(),
  url = `https://app.invalid/api/mobile/v1/conversation/meal-commands/${b.commandId}`
const original = { commandId: b.commandId, inputHash: b.inputHash, epoch: b.epoch }
function setup() {
  const readGroup = vi.fn().mockResolvedValue({ schema: 'conversation.meal-group.v1' }),
    execute = vi
      .fn()
      .mockResolvedValue({ schema: 'conversation.meal-edit-result.v1', status: 'saved' }),
    reconcile = vi
      .fn()
      .mockResolvedValue({ schema: 'conversation.meal-edit-state.v1', status: 'absent' }),
    service = vi.fn(() => ({ readGroup, execute, reconcile })),
    enabled = vi.fn(() => true)
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn().mockResolvedValue(candidateAuth),
    authorizeEntitlement: vi.fn().mockResolvedValue(undefined),
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'public-edit-route-request',
  }
  const ports = { enabled, service }
  return {
    readGroup,
    execute,
    reconcile,
    service,
    enabled,
    runtime,
    ports,
    routes: createConversationMealEditPublicRoutes(ports, runtime),
  }
}
function request(
  method = 'POST',
  input: unknown = editInput(),
  headers: Record<string, string> = {},
  raw?: string,
) {
  return new Request(`${url}/${method === 'GET' ? 'meal' : `edits/${editOperationId}`}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Conversation-Owner': b.ownerId,
      'X-Conversation-Epoch': b.epoch,
      'X-Conversation-Input-Hash': b.inputHash,
      'Idempotency-Key': `cmedit1:${editOperationId}`,
      ...headers,
    },
    ...(method === 'GET' ? {} : { body: raw ?? JSON.stringify(input) }),
  })
}
const params = () => ({
  params: Promise.resolve({ commandId: b.commandId, operationId: editOperationId }),
})
describe('dormant authenticated group/direct edit/read-only reconcile routes', () => {
  it('reads the existing group with original identity and no edit request', async () => {
    const f = setup(),
      response = await f.routes.GROUP(request('GET'), params())
    expect(response.status).toBe(200)
    expect(f.readGroup).toHaveBeenCalledWith(candidateAuth, original)
    expect(f.execute).not.toHaveBeenCalled()
    expect(f.reconcile).not.toHaveBeenCalled()
  })
  it('executes once with exact stable operation identity/body and private request ID', async () => {
    const f = setup(),
      response = await f.routes.EDIT(request(), params())
    expect(response.status).toBe(200)
    expect(f.execute).toHaveBeenCalledTimes(1)
    expect(f.execute).toHaveBeenCalledWith(
      candidateAuth,
      original,
      editOperationId,
      editInput(),
      'public-edit-route-request',
    )
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-command-v1')
    expect((await response.json()).meta).toEqual({
      api_version: 'v1',
      request_id: 'public-edit-route-request',
    })
  })
  it('reconciles through a separate read-only POST carrying original input, never execute', async () => {
    const f = setup(),
      response = await f.routes.RECONCILE(request(), params())
    expect(response.status).toBe(200)
    expect(f.reconcile).toHaveBeenCalledWith(candidateAuth, original, editOperationId, editInput())
    expect(f.execute).not.toHaveBeenCalled()
    expect(f.readGroup).not.toHaveBeenCalled()
    expect((await response.json()).data.status).toBe('absent')
  })
  it('does not idempotency-cache an absent response over a later winner for the same reconciliation key', async () => {
    const f = setup()
    f.reconcile
      .mockResolvedValueOnce({ schema: 'conversation.meal-edit-state.v1', status: 'absent' })
      .mockResolvedValueOnce({ schema: 'conversation.meal-edit-result.v1', status: 'saved' })
    expect((await (await f.routes.RECONCILE(request(), params())).json()).data.status).toBe(
      'absent',
    )
    expect((await (await f.routes.RECONCILE(request(), params())).json()).data.status).toBe('saved')
    expect(f.reconcile).toHaveBeenCalledTimes(2)
    for (const call of f.reconcile.mock.calls)
      expect(call).toEqual([candidateAuth, original, editOperationId, editInput()])
    expect(f.execute).not.toHaveBeenCalled()
  })
  it.each([
    'GROUP',
    'EDIT',
    'RECONCILE',
  ] as const)('remains off without constructing a service for %s', async (method) => {
    const f = setup()
    f.enabled.mockReturnValue(false)
    expect(
      (await f.routes[method](request(method === 'GROUP' ? 'GET' : 'POST'), params())).status,
    ).toBe(503)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    401, 402,
  ])('requires auth/entitlement before parsing or service for %i', async (status) => {
    const f = setup(),
      deny = async () => {
        throw new MobileApiError(status, 'access_denied', 'Access required')
      }
    if (status === 401) f.runtime.authenticate = deny
    else f.runtime.authorizeEntitlement = deny
    const routes = createConversationMealEditPublicRoutes(f.ports, f.runtime)
    for (const route of [routes.GROUP, routes.EDIT, routes.RECONCILE])
      expect((await route(request('POST', {}, {}, 'not JSON'), params())).status).toBe(status)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'X-Conversation-Owner',
    'X-Conversation-Epoch',
    'X-Conversation-Input-Hash',
    'Idempotency-Key',
  ])('rejects missing/invalid %s before effect service construction', async (header) => {
    for (const missing of [true, false]) {
      const f = setup(),
        req = request()
      if (missing) req.headers.delete(header)
      else req.headers.set(header, 'invalid')
      expect((await f.routes.EDIT(req, params())).status).toBe(422)
      expect(f.service).not.toHaveBeenCalled()
    }
  })
  it('refuses a remapped patient before every service method even if the epoch matches', async () => {
    const f = setup()
    for (const method of ['GROUP', 'EDIT', 'RECONCILE'] as const) {
      const response = await f.routes[method](
        request(method === 'GROUP' ? 'GET' : 'POST', editInput(), {
          'X-Conversation-Owner': editOperationId,
        }),
        params(),
      )
      expect(response.status).toBe(409)
      expect((await response.json()).error.code).toBe('conversation_patient_changed')
    }
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects a key for a different operation UUID', async () => {
    const f = setup()
    expect(
      (
        await f.routes.EDIT(
          request('POST', editInput(), { 'Idempotency-Key': `cmedit1:${b.commandId}` }),
          params(),
        )
      ).status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'owner_id',
    'receipt',
    'calories',
    'expectedState',
  ])('rejects client authority %s for edit and read-only reconciliation', async (field) => {
    const f = setup()
    for (const method of [f.routes.EDIT, f.routes.RECONCILE])
      expect(
        (await method(request('POST', { ...editInput(), [field]: true }), params())).status,
      ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects duplicate JSON keys before service and preserves a malformed-JSON 400', async () => {
    const f = setup()
    expect(
      (
        await f.routes.EDIT(
          request('POST', undefined, {}, '{"kind":"save","kind":"save"}'),
          params(),
        )
      ).status,
    ).toBe(400)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects nonfinite JSON numbers as invalid input instead of zero or server failure', async () => {
    const f = setup(),
      raw = JSON.stringify(editInput()).replace('"quantity_g":200', '"quantity_g":1e999')
    expect((await f.routes.EDIT(request('POST', undefined, {}, raw), params())).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('enforces the 16,384-byte edit body bound', async () => {
    const f = setup(),
      raw = JSON.stringify({ ...editInput(), unwanted: 'x'.repeat(16400) })
    expect((await f.routes.EDIT(request('POST', undefined, {}, raw), params())).status).toBe(413)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('validates command/operation route IDs before service construction', async () => {
    const f = setup()
    for (const bad of [
      { commandId: 'invalid', operationId: editOperationId },
      { commandId: b.commandId, operationId: 'invalid' },
    ])
      expect((await f.routes.EDIT(request(), { params: Promise.resolve(bad) })).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
})
