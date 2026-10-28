import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalFullEntryRoutes } from './clinical-full-entry'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'

const owner = 'b3b01000-0000-4000-8000-000000004800',
  subject = 'b3b01000-0000-4000-8000-000000004899',
  key = 'b3b01000-0000-4000-8000-000000004888'
const auth = {
  userId: owner,
  authUserId: subject,
  identity: { id: subject },
  patient: { id: owner, authUserId: subject, status: 'active' },
} as MobileAuthContext
function state() {
  return {
    version: 1,
    availability: 'available',
    unavailable_reason: null,
    clock: { base_date: '2026-10-20', due_date: '2026-11-03', timezone: 'America/Sao_Paulo' },
    cycle: {
      id: owner,
      signup_generation: subject,
      revision: '9007199254740993',
      kind: 'EARLY_FULL',
      status: 'open',
      base_date: '2026-10-20',
      due_date: '2026-11-03',
      timezone_at_open: 'America/Sao_Paulo',
      opened_at: '2026-10-26T12:00:00.000000Z',
    },
  }
}
function setup(
  enabled = true,
  admitLegacy?: (client: ServiceClient, owner: string) => Promise<void>,
) {
  const rpc = vi
    .fn<
      (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
    >()
    .mockResolvedValue({ data: state(), error: null })
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
    createRequestId: () => 'full-entry-http-qa',
  }
  return { rpc, runtime, routes: createClinicalFullEntryRoutes({ enabled, admitLegacy }, runtime) }
}
const get = () => new Request('https://bodyflow.test/api/mobile/v1/reevaluation')
const post = (body: unknown, id = key) =>
  new Request('https://bodyflow.test/api/mobile/v1/reevaluation/start', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': id },
    body: JSON.stringify(body),
  })
describe('actual server-owned FULL entry public boundary', () => {
  it('admits only after valid Auth, entitlement, query and START body, before reading the calendar', async () => {
    const admit = vi.fn(async (_client: ServiceClient, actual: string) => {
      expect(actual).toBe(owner)
      expect(x.rpc).not.toHaveBeenCalled()
    })
    const x = setup(true, admit)
    expect(admit).not.toHaveBeenCalled()
    expect((await x.routes.START(post({ reason: null, kind: 'TRANSITION_FULL' }))).status).toBe(422)
    expect(
      (await x.routes.GET(new Request(`${get().url}?clinical_policy=current_clinical_v1`))).status,
    ).toBe(422)
    expect(admit).not.toHaveBeenCalled()
    expect((await x.routes.START(post({ reason: null }))).status).toBe(200)
    expect(admit).toHaveBeenCalledOnce()
    expect(x.rpc).toHaveBeenCalledOnce()
    for (const method of ['authenticate', 'authorizeEntitlement'] as const) {
      const noAdmission = vi.fn(),
        y = setup(true, noAdmission)
      vi.mocked(y.runtime[method]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await y.routes.GET(get())).status).toBe(403)
      expect(noAdmission).not.toHaveBeenCalled()
      expect(y.rpc).not.toHaveBeenCalled()
    }
  })
  it('projects only safe cycle scope/calendar and keeps bigint revisions as strings', async () => {
    const x = setup(),
      response = await x.routes.GET(get())
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      version: 1,
      availability: 'available',
      unavailable_reason: null,
      clock: state().clock,
      cycle: { id: owner, kind: 'EARLY_FULL', status: 'open', revision: '9007199254740993' },
    })
    expect(x.rpc).toHaveBeenCalledWith('get_mobile_reevaluation_cycle', { p_user_id: owner })
    expect(x.runtime.authorizeEntitlement).toHaveBeenCalledOnce()
  })
  it('resume sends no client kind/date and consumes the actual returned kind', async () => {
    const x = setup(),
      response = await x.routes.START(post({ reason: null }))
    expect(response.status).toBe(200)
    expect((await response.json()).data.cycle.kind).toBe('EARLY_FULL')
    expect(x.rpc).toHaveBeenCalledOnce()
    expect(x.rpc).toHaveBeenCalledWith('start_mobile_clinical_full', {
      p_user_id: owner,
      p_operation_key: key,
      p_reason: null,
    })
  })
  it('explicit early reason remains a declaration, never a client calendar or target', async () => {
    const x = setup()
    expect((await x.routes.START(post({ reason: 'not_well_with_plan' }))).status).toBe(200)
    expect(x.rpc).toHaveBeenCalledWith('start_mobile_clinical_full', {
      p_user_id: owner,
      p_operation_key: key,
      p_reason: 'not_well_with_plan',
    })
  })
  it('invalid input/header/query fails before any RPC and SQL conflicts are safe', async () => {
    const x = setup()
    for (const body of [
      { reason: null, kind: 'EARLY_FULL' },
      { reason: null, date: '2026-01-01' },
      { reason: 'pretend_due' },
    ])
      expect((await x.routes.START(post(body))).status).toBe(422)
    expect((await x.routes.GET(new Request(`${get().url}?owner=other`))).status).toBe(422)
    expect(x.rpc).not.toHaveBeenCalled()
    x.rpc.mockResolvedValueOnce({ data: null, error: { code: '40001', message: 'private' } })
    const response = await x.routes.START(post({ reason: null }))
    expect(response.status).toBe(409)
    expect(await response.text()).not.toContain('private')
  })
  it('disabled/auth/entitlement boundaries prevent clinical effects', async () => {
    const off = setup(false)
    expect((await off.routes.GET(get())).status).toBe(404)
    expect(off.rpc).not.toHaveBeenCalled()
    for (const method of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[method]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await x.routes.START(post({ reason: null }))).status).toBe(403)
      expect(x.rpc).not.toHaveBeenCalled()
    }
  })
})
