import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import { createReevaluationPhotoConsentRoutes } from './reevaluation-photo-consent-http'
import type { MobileRouteRuntime } from './route'
import {
  consentAuth,
  consentInput,
  consentWire,
  uid,
} from './testing/reevaluation-photo-consent-fixture'

const cycle = uid(5601),
  key = uid(5604)
const routeContext = (id = cycle) => ({ params: Promise.resolve({ cycleId: id }) })
const get = (query = '') =>
  new Request(`https://bodyflow.test/api/mobile/v1/reevaluation/${cycle}/photos/consent${query}`)
const post = (input: unknown, id = key) =>
  new Request(get().url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': id },
    body: JSON.stringify(input),
  })
function setup(enabled = true) {
  const rpc = vi
    .fn<
      (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
    >()
    .mockResolvedValue({ data: consentWire(), error: null })
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => consentAuth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
    createRequestId: () => 'recurring-consent-http-qa',
  }
  return { rpc, runtime, routes: createReevaluationPhotoConsentRoutes({ enabled }, runtime) }
}
describe('recurring photo consent HTTP boundary', () => {
  it('reads exact text for the authenticated cycle and never auto-accepts', async () => {
    const x = setup(),
      response = await x.routes.GET(get(), routeContext())
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data.document.body).toBe(consentWire().document.body)
    expect(data.acceptance).toBeNull()
    expect(data.cycle_id).toBe(cycle)
    expect(x.rpc.mock.calls.map(([name]) => name)).toEqual([
      'get_mobile_reevaluation_photo_consent',
    ])
    expect(x.runtime.authorizeEntitlement).toHaveBeenCalledOnce()
  })
  it('accepts only an explicit shown identity with stable header key, without an outer response cache', async () => {
    const x = setup()
    x.rpc
      .mockResolvedValueOnce({ data: consentWire(true), error: null })
      .mockResolvedValueOnce({ data: null, error: { code: '40001', message: 'private policy' } })
    expect((await x.routes.ACCEPT(post(consentInput()), routeContext())).status).toBe(200)
    const replay = await x.routes.ACCEPT(post(consentInput()), routeContext())
    expect(replay.status).toBe(409)
    expect(await replay.text()).not.toContain('private policy')
    expect(x.rpc).toHaveBeenCalledTimes(2)
  })
  it('rejects private claims, body/key/scope/query errors before the authority', async () => {
    const x = setup()
    for (const body of [
      { ...consentInput(), userId: uid(5690) },
      { ...consentInput(), accepted: true },
      { ...consentInput(), now: '2026-01-01' },
    ])
      expect((await x.routes.ACCEPT(post(body), routeContext())).status).toBe(422)
    expect((await x.routes.GET(get('?user=other'), routeContext())).status).toBe(422)
    expect((await x.routes.GET(get(), routeContext('bad'))).status).toBe(422)
    expect((await x.routes.ACCEPT(post(consentInput(), 'bad'), routeContext())).status).toBe(400)
    expect((await x.routes.ACCEPT(post({ value: 'x'.repeat(9000) }), routeContext())).status).toBe(
      413,
    )
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('preserves disabled/auth/entitlement barriers without creating consent', async () => {
    const off = setup(false)
    expect((await off.routes.GET(get(), routeContext())).status).toBe(404)
    expect(off.rpc).not.toHaveBeenCalled()
    for (const method of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[method]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await x.routes.ACCEPT(post(consentInput()), routeContext())).status).toBe(403)
      expect(x.rpc).not.toHaveBeenCalled()
    }
  })
})
