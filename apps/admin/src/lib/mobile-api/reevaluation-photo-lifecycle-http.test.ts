import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import type { ReevaluationPhotoLifecycleOperations } from './reevaluation-photo-lifecycle'
import { createReevaluationPhotoLifecycleRoutes } from './reevaluation-photo-lifecycle-http'
import type { MobileRouteRuntime } from './route'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

const cycle = uid(5601),
  asset = uid(5602),
  key = uid(5604)
const context = (cycleId = cycle, assetId = asset) => ({
  params: Promise.resolve({ cycleId, assetId }),
})
const request = (body: unknown = {}, id = key, query = '') =>
  new Request(`https://bodyflow.test/api/mobile/v1/reevaluation/${cycle}/photos${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': id },
    body: JSON.stringify(body),
  })
function setup(enabled = true) {
  const ops = {
    snapshot: vi.fn(),
    allocate: vi.fn(),
    upload: vi.fn(),
    complete: vi.fn(),
    process: vi.fn().mockResolvedValue({ status: 'processed' }),
    discard: vi.fn(),
    drain: vi.fn(),
  } satisfies ReevaluationPhotoLifecycleOperations
  const client = { rpc: vi.fn() } as unknown as ServiceClient
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => consentAuth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => client,
    createRequestId: () => 'recurring-lifecycle-http-qa',
  }
  const factory = vi.fn(() => ops)
  return {
    ops,
    client,
    runtime,
    factory,
    routes: createReevaluationPhotoLifecycleRoutes({ enabled, createOperations: factory }, runtime),
  }
}
describe('recurring lifecycle HTTP authority boundary', () => {
  it('reuses the exact processing intent on replay and authenticates each call without caching a patient response', async () => {
    const x = setup()
    for (let i = 0; i < 2; i++)
      expect((await x.routes.PROCESS(request(), context())).status).toBe(200)
    expect(x.ops.process.mock.calls).toEqual([
      [{ userId: consentAuth.userId, cycleId: cycle, assetId: asset, requestId: key }],
      [{ userId: consentAuth.userId, cycleId: cycle, assetId: asset, requestId: key }],
    ])
    expect(x.runtime.authenticate).toHaveBeenCalledTimes(2)
    expect(x.runtime.authorizeEntitlement).toHaveBeenCalledTimes(2)
    expect(x.factory).toHaveBeenCalledWith(x.client)
  })
  it('rejects client authority, malformed scopes, queries and missing intentions before constructing operations', async () => {
    const x = setup()
    for (const body of [
      { userId: uid(5690) },
      { requestId: uid(5690) },
      { now: '2026-10-27' },
      { mean: 22 },
    ])
      expect((await x.routes.PROCESS(request(body), context())).status).toBe(422)
    expect((await x.routes.PROCESS(request({}, 'bad'), context())).status).toBe(400)
    expect((await x.routes.PROCESS(request({}, key, '?user=other'), context())).status).toBe(422)
    expect((await x.routes.PROCESS(request(), context('bad'))).status).toBe(422)
    expect((await x.routes.PROCESS(request(), context(cycle, 'bad'))).status).toBe(422)
    expect((await x.routes.ALLOCATE(request({ value: 'x'.repeat(9000) }), context())).status).toBe(
      413,
    )
    expect(
      (
        await x.routes.DISCARD(
          request({ acceptanceId: uid(5603), expectedRevision: '1', removeAll: true }),
          context(),
        )
      ).status,
    ).toBe(422)
    expect(x.factory).not.toHaveBeenCalled()
  })
  it('requires empty bounded bodies and stable intention headers for upload and completion too', async () => {
    const x = setup()
    for (const action of [x.routes.UPLOAD, x.routes.COMPLETE]) {
      expect((await action(request({ assetId: uid(5690) }), context())).status).toBe(422)
      expect((await action(request({}, 'bad'), context())).status).toBe(400)
    }
    expect(x.factory).not.toHaveBeenCalled()
  })
  it('keeps the dormant, authentication and entitlement gates ahead of the photo authority', async () => {
    const off = setup(false)
    expect((await off.routes.PROCESS(request(), context())).status).toBe(404)
    expect(off.factory).not.toHaveBeenCalled()
    for (const gate of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[gate]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await x.routes.PROCESS(request(), context())).status).toBe(403)
      expect(x.factory).not.toHaveBeenCalled()
    }
  })
})
