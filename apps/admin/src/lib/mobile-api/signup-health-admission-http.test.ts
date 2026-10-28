import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import { createSignupHealthAdmissionRoutes } from './signup-health-admission-http'
import {
  signupHealthAuth,
  signupHealthIDs,
  signupHealthInput,
  signupHealthWire,
} from './testing/signup-health-admission-fixture'

const post = (input: unknown = signupHealthInput(), key = signupHealthIDs.operation, query = '') =>
  new Request(`https://owned.test/api/mobile/v1/onboarding/health${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': key },
    body: JSON.stringify(input),
  })
function setup(enabled = true) {
  const rpc = vi.fn().mockResolvedValue({ data: signupHealthWire(), error: null })
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => signupHealthAuth()),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
    createRequestId: () => 'signup-health-http-qa',
  }
  return { rpc, runtime, routes: createSignupHealthAdmissionRoutes({ enabled }, runtime) }
}
describe('signup health public HTTP authority', () => {
  it('takes the operation from the header and returns only the bound legal/risk acknowledgement and current state', async () => {
    const x = setup(),
      response = await x.routes.POST(post())
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data).toMatchObject({
      availability: 'available',
      operation_key: signupHealthIDs.operation,
      receipt: { intent_id: signupHealthIDs.intent },
    })
    for (const key of ['epoch', 'health_operation_key', 'policy_evidence', 'command_hash'])
      expect(JSON.stringify(data)).not.toContain(`"${key}"`)
    expect(x.rpc).toHaveBeenCalledWith('admit_mobile_signup_health', {
      p_user_id: signupHealthIDs.owner,
      p_command: { ...signupHealthInput(), operation_key: signupHealthIDs.operation },
    })
  })
  it('every replay reaches the atomic authority; an old receipt is not pre-verified or restored', async () => {
    const x = setup()
    expect((await x.routes.POST(post())).status).toBe(200)
    x.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '40001', message: 'private epoch data' },
    })
    const response = await x.routes.POST(post())
    expect(response.status).toBe(409)
    expect(await response.text()).not.toContain('private epoch data')
    expect(x.rpc.mock.calls.map(([name]) => name)).toEqual([
      'admit_mobile_signup_health',
      'admit_mobile_signup_health',
    ])
  })
  it('rejects ordinary answers, client authority, invalid declarations and oversized inputs before any RPC', async () => {
    const x = setup()
    for (const body of [
      { ...signupHealthInput(), operation_key: signupHealthIDs.operation },
      { ...signupHealthInput(), epoch: signupHealthIDs.epoch },
      { ...signupHealthInput(), weight_kg: 80 },
      { ...signupHealthInput(), user_id: signupHealthIDs.owner },
      { ...signupHealthInput(), risks: [] },
      { ...signupHealthInput(), risks: ['none'] },
    ])
      expect((await x.routes.POST(post(body))).status).toBe(422)
    expect((await x.routes.POST(post({}, 'bad'))).status).toBe(400)
    expect(
      (await x.routes.POST(post(signupHealthInput(), signupHealthIDs.operation, '?owner=other')))
        .status,
    ).toBe(422)
    expect((await x.routes.POST(post({ value: 'x'.repeat(9000) }))).status).toBe(413)
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('preserves disabled/auth/entitlement gates and never invents an admission', async () => {
    const off = setup(false)
    expect((await off.routes.POST(post())).status).toBe(404)
    expect(off.rpc).not.toHaveBeenCalled()
    for (const gate of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[gate]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await x.routes.POST(post())).status).toBe(403)
      expect(x.rpc).not.toHaveBeenCalled()
    }
  })
  it.each([
    ['40001', 409],
    ['55P03', 409],
    ['23514', 409],
    ['22023', 422],
    ['42501', 503],
    ['XX001', 503],
  ])('maps SQL %s without exposing its message', async (code, status) => {
    const x = setup()
    x.rpc.mockResolvedValueOnce({ data: null, error: { code, message: 'private health marker' } })
    const response = await x.routes.POST(post())
    expect(response.status).toBe(status)
    expect(await response.text()).not.toContain('private health marker')
    expect(x.rpc).toHaveBeenCalledOnce()
  })
})
