import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { MobileRouteRuntime } from './route'
import { createTrainingExecutionRoutes } from './training-execution-routes'

const owner = '13600000-0000-4000-8000-000000000002',
  auth = '13600000-0000-4000-8000-000000000001',
  epoch = '13600000-0000-4000-8000-000000000010',
  login = '13600000-0000-4000-8000-000000000003'
const token = `e30.${Buffer.from(JSON.stringify({ sub: auth, session_id: login })).toString('base64url')}.synthetic`
const command = {
  schema: 'training.execution.start.v1',
  session_id: login,
  operation_id: login,
  expected_epoch: epoch,
  expected_local_date: '2026-11-14',
  plan_id: owner,
  plan_hash: 'a'.repeat(64),
  day_index: 0,
}
function harness(enabled = true, changed = false) {
  let reads = 0,
    writes = 0,
    checks = 0
  const who = () =>
    ({
      accessToken: token,
      authUserId: auth,
      userId: owner,
      identity: { id: auth, email: 'qa@example.invalid', emailConfirmedAt: '2026-11-14T00:00:00Z' },
      patient: { id: owner, authUserId: auth, status: 'active' },
    }) as MobileAuthContext
  const runtime: MobileRouteRuntime = {
    authenticate: async () => {
      const value = who()
      if (++checks > 1 && changed) value.accessToken = 'replacement'
      return value
    },
    authorizeEntitlement: async () => {},
    createServiceClient: () => ({}) as ReturnType<MobileRouteRuntime['createServiceClient']>,
    createRequestId: () => 'training-api-test',
  }
  const routes = createTrainingExecutionRoutes(
    {
      enabled: () => enabled,
      service: () => ({
        home: async () => {
          reads++
          return { schema: 'owned-home' }
        },
        read: async () => {
          reads++
          return { schema: 'owned-execution' }
        },
        mutate: async () => {
          writes++
          return { schema: 'owned-write' }
        },
      }),
    },
    runtime,
  )
  const request = (body: unknown = command, headers: Record<string, string> = {}) =>
    new Request('https://unit.invalid/api/mobile/v1/training/execution/commands', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Training-Owner': owner,
        'X-Training-Epoch': epoch,
        'Idempotency-Key': `texecution1:${login}`,
        ...headers,
      },
      body: JSON.stringify(body),
    })
  return { routes, request, counts: () => ({ reads, writes, checks }) }
}
describe('training execution original-Auth routes', () => {
  it('holds a disabled feature before any execution read/write', async () => {
    const f = harness(false),
      r = await f.routes.POST(f.request())
    expect(r.status).toBe(503)
    expect(f.counts().writes).toBe(0)
  })
  it('rejects owner/key/epoch overrides and unknown command fields before the writer', async () => {
    for (const [body, headers] of [
      [{ ...command, calories: 12 }, {}],
      [command, { 'X-Training-Owner': auth }],
      [command, { 'X-Training-Epoch': auth }],
      [command, { 'Idempotency-Key': 'different' }],
    ] as const) {
      const f = harness(),
        r = await f.routes.POST(f.request(body, headers))
      expect(r.status).toBeGreaterThanOrEqual(400)
      expect(f.counts().writes).toBe(0)
    }
  })
  it('checks the original identity again before dispatching any write', async () => {
    const f = harness(true, true),
      r = await f.routes.POST(f.request())
    expect(r.status).toBe(409)
    expect(f.counts().writes).toBe(0)
  })
  it('dispatches one closed command and no implicit second confirmation', async () => {
    const f = harness(),
      r = await f.routes.POST(f.request())
    expect(r.status).toBe(200)
    expect(f.counts().writes).toBe(1)
  })
  it('rejects unknown/duplicate discovery query parameters without reading', async () => {
    for (const q of ['owner=other', 'cursor=x&cursor=y']) {
      const f = harness(),
        r = await f.routes.HOME(
          new Request(`https://unit.invalid/api/mobile/v1/training/execution?${q}`, {
            headers: { 'X-Training-Owner': owner },
          }),
        )
      expect(r.status).toBeGreaterThanOrEqual(400)
      expect(f.counts().reads).toBe(0)
    }
  })
})
