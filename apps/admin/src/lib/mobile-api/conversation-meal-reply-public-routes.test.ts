import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationMealReplyPublicRoutes } from './conversation-meal-reply-public-routes'
import type { MobileRouteRuntime } from './route'

function setup() {
  const f = replyFixture(),
    submit = vi
      .fn()
      .mockResolvedValue({ status: 'saved', schema: 'conversation.meal-reply-result.v1' }),
    reconcile = vi.fn().mockResolvedValue({
      status: 'reconciliation_required',
      schema: 'conversation.meal-reply-result.v1',
    }),
    service = vi.fn(() => ({ submit, reconcile })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      authenticate: vi.fn(async () => f.auth),
      authorizeEntitlement: vi.fn(async () => {}),
      createServiceClient: () => ({}) as ServiceClient,
      createRequestId: () => 'synthetic-reply-request',
    }
  return {
    ...f,
    submit,
    reconcile,
    service,
    enabled,
    runtime,
    routes: createConversationMealReplyPublicRoutes({ enabled, service }, runtime),
  }
}
function request(
  f: ReturnType<typeof setup>,
  method = 'POST',
  query = '',
  body: unknown = f.submission,
) {
  return new Request(
    `https://app.invalid/api/mobile/v1/conversation/commands/${f.identity.parentCommandId}/replies${method === 'GET' ? `/${f.identity.replyId}` : ''}${query}`,
    {
      method,
      headers: {
        Authorization: 'Bearer synthetic-token',
        'Content-Type': 'application/json',
        'X-Conversation-Owner': f.identity.ownerId,
        'X-Conversation-Epoch': f.identity.epoch,
        'Idempotency-Key': f.key,
      },
      ...(method === 'GET' ? {} : { body: JSON.stringify(body) }),
    },
  )
}
describe('public linked reply POST and readonly GET', () => {
  it.each([
    'POST',
    'GET',
  ])('negotiates presentation2 on linked %s preserving closed keys and readonly GET', async (method) => {
    const f = setup(),
      q =
        method === 'GET'
          ? `?parent_input_hash=${f.identity.parentInputHash}&reply_input_hash=${f.identity.replyInputHash}`
          : '',
      r = request(f, method, q)
    r.headers.set('X-Conversation-Feedback-Presentation', '2')
    const response =
      method === 'POST'
        ? await f.routes.POST(r, {
            params: Promise.resolve({ commandId: f.identity.parentCommandId }),
          })
        : await f.routes.GET(r, {
            params: Promise.resolve({
              commandId: f.identity.parentCommandId,
              replyId: f.identity.replyId,
            }),
          })
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
    expect(response.headers.get('Vary')).toBe('Authorization, X-Conversation-Feedback-Presentation')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-reply-v1')
    expect((method === 'POST' ? f.submit : f.reconcile).mock.calls[0].at(-1)).toBe('2')
  })
  it('pins both Admin/BFF wrappers to the actual handlers and 120-second server budgets', () => {
    for (const [path, method] of [
      ['commands/[commandId]/replies', 'POST'],
      ['commands/[commandId]/replies/[replyId]', 'GET'],
    ] as const) {
      for (const app of ['admin', 'mobile-bff']) {
        const source = readFileSync(
          new URL(
            `../../../../${app}/src/app/api/mobile/v1/conversation/${path}/route.ts`,
            import.meta.url,
          ),
          'utf8',
        )
        expect(source).toContain("export const runtime = 'nodejs'")
        expect(source).toContain('export const maxDuration = 120')
        expect(source).toContain(method)
        expect(source).not.toMatch(/300|register|calculate|ensureOriginal/)
      }
    }
  })

  it('uses real Auth/entitlement context and forwards closed immutable body once with no-store', async () => {
    const f = setup(),
      res = await f.routes.POST(request(f), {
        params: Promise.resolve({ commandId: f.identity.parentCommandId }),
      })
    expect(res.status).toBe(200)
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(f.submit).toHaveBeenCalledWith(
      f.auth,
      f.identity.parentCommandId,
      f.identity.epoch,
      f.submission,
      f.key,
    )
    expect(res.headers.get('cache-control')).toBe('no-store')
    expect(res.headers.get('vary')).toBe('Authorization')
  })
  it('GET accepts only parent/reply hashes and never calls submit', async () => {
    const f = setup(),
      q = `?parent_input_hash=${f.identity.parentInputHash}&reply_input_hash=${f.identity.replyInputHash}`
    const res = await f.routes.GET(request(f, 'GET', q), {
      params: Promise.resolve({
        commandId: f.identity.parentCommandId,
        replyId: f.identity.replyId,
      }),
    })
    expect(res.status).toBe(202)
    expect(f.reconcile).toHaveBeenCalledWith(
      f.auth,
      f.identity.parentCommandId,
      f.identity.replyId,
      f.identity.epoch,
      {
        parent_input_hash: f.identity.parentInputHash,
        reply_input_hash: f.identity.replyInputHash,
      },
    )
    expect(f.submit).not.toHaveBeenCalled()
  })
  it.each([
    '?unknown=1',
    '?parent_input_hash=a',
    '?parent_input_hash=&reply_input_hash=',
    '?parent_input_hash=aa&parent_input_hash=bb&reply_input_hash=cc',
  ])('refuses damaged GET query %s', async (q) => {
    const f = setup()
    const res = await f.routes.GET(request(f, 'GET', q), {
      params: Promise.resolve({
        commandId: f.identity.parentCommandId,
        replyId: f.identity.replyId,
      }),
    })
    expect(res.status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('requires immutable key and refuses all extra submit/proposal/calorie fields', async () => {
    const f = setup()
    for (const extra of [
      { kcal: 100 },
      { original_text: 'invented' },
      { proposal: {} },
      { epoch: f.identity.epoch },
    ]) {
      const res = await f.routes.POST(request(f, 'POST', '', { ...f.submission, ...extra }), {
        params: Promise.resolve({ commandId: f.identity.parentCommandId }),
      })
      expect(res.status).toBe(422)
    }
    const r = request(f)
    r.headers.set('Idempotency-Key', 'cmreply1:00000000-0000-0000-0000-000000000000')
    expect(
      (
        await f.routes.POST(r, {
          params: Promise.resolve({ commandId: f.identity.parentCommandId }),
        })
      ).status,
    ).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects wrong original patient before constructing any processor', async () => {
    const f = setup(),
      r = request(f)
    r.headers.set('X-Conversation-Owner', f.auth.authUserId)
    expect(
      (
        await f.routes.POST(r, {
          params: Promise.resolve({ commandId: f.identity.parentCommandId }),
        })
      ).status,
    ).toBe(409)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('keeps the existing capability OFF without another writer fallback', async () => {
    const f = setup()
    f.enabled.mockReturnValue(false)
    expect(
      (
        await f.routes.POST(request(f), {
          params: Promise.resolve({ commandId: f.identity.parentCommandId }),
        })
      ).status,
    ).toBe(503)
    expect(f.service).not.toHaveBeenCalled()
  })
})
