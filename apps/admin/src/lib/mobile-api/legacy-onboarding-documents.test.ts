import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import type { LegacyDocumentCommand } from './legacy-onboarding-documents'
import { createLegacyOnboardingDocumentsRoutes } from './legacy-onboarding-documents-http'
import type { MobileRouteRuntime } from './route'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

const key = uid(7401)
const input = () => ({
  version: 1,
  locale: 'pt-BR',
  document_actions: [
    {
      document_key: 'terms',
      version: '1',
      locale: 'pt-BR',
      content_hash: 'a'.repeat(64),
      action: 'acceptance',
    },
  ],
})
function setup(enabled = true) {
  const rpc = vi.fn(
    async (_name: string, args: { p_user_id: string; p_command: LegacyDocumentCommand }) => ({
      data: {
        version: 1,
        user_id: args.p_user_id,
        operation_key: args.p_command.operation_key,
        receipt: {
          id: uid(7402),
          locale: args.p_command.locale,
          accepted_at: '2026-10-28T00:00:00.000003Z',
          document_actions: args.p_command.document_actions.map((a) => ({
            ...a,
            purpose: 'synthetic_notice',
            acted_at: '2026-10-27T00:00:00.000001Z',
          })),
        },
      },
      error: null,
    }),
  )
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => structuredClone(consentAuth)),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: vi.fn(() => ({ rpc }) as unknown as ServiceClient),
    createRequestId: () => 'synthetic-reconsent',
  }
  return { rpc, runtime, routes: createLegacyOnboardingDocumentsRoutes({ enabled }, runtime) }
}
function request(value: unknown = input(), query = '', operation = key) {
  return new Request(`https://owned.test/api/mobile/v1/onboarding/reconsent${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': operation },
    body: JSON.stringify(value),
  })
}
describe('legacy documents-only public command', () => {
  it('construction is inert; one RPC owns replay before any current-source read', async () => {
    const x = setup()
    expect(x.rpc).not.toHaveBeenCalled()
    const response = await x.routes.POST(request())
    expect(response.status).toBe(200)
    expect(x.rpc).toHaveBeenCalledOnce()
    expect(x.rpc).toHaveBeenCalledWith('accept_mobile_clinical_legacy_documents', {
      p_user_id: consentAuth.userId,
      p_command: { ...input(), operation_key: key },
    })
    const data = (await response.json()).data
    expect(data).toMatchObject({ version: 1, operation_key: key, receipt: { id: uid(7402) } })
    for (const field of ['user_id', 'completed_at', 'objective', 'epoch', 'generation', 'draft'])
      expect(data).not.toHaveProperty(field)
  })
  it.each([
    { owner: uid(1) },
    { epoch: uid(1) },
    { generation: uid(1) },
    { operation_key: key },
    { weight_kg: 80 },
    { completed_at: null },
    { risks: [] },
    { version: 2 },
    { locale: 'en-US' },
    { document_actions: [] },
  ])('rejects extra authority, signup fields or invalid identity before RPC (%j)', async (patch) => {
    const x = setup()
    expect((await x.routes.POST(request({ ...input(), ...patch }))).status).toBe(422)
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('rejects queries, bad operation keys and oversized bodies before any RPC', async () => {
    const x = setup()
    expect(
      (await x.routes.POST(request(input(), '?clinical_policy=current_clinical_v1'))).status,
    ).toBe(422)
    expect((await x.routes.POST(request(input(), '', 'invalid'))).status).toBe(400)
    expect((await x.routes.POST(request(input(), '', 'invalid-uuid'))).status).toBe(422)
    expect((await x.routes.POST(request({ ...input(), unused: 'x'.repeat(17000) }))).status).toBe(
      413,
    )
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('keeps auth, entitlement and the opt-in switch before domain writes', async () => {
    const off = setup(false)
    expect((await off.routes.POST(request())).status).toBe(404)
    expect(off.rpc).not.toHaveBeenCalled()
    const denied = setup()
    vi.mocked(denied.runtime.authorizeEntitlement).mockRejectedValueOnce(
      new MobileApiError(403, 'denied', 'Denied'),
    )
    expect((await denied.routes.POST(request())).status).toBe(403)
    expect(denied.rpc).not.toHaveBeenCalled()
    const auth = setup()
    vi.mocked(auth.runtime.authenticate).mockRejectedValueOnce(
      new MobileApiError(401, 'auth', 'Unauthorized'),
    )
    expect((await auth.routes.POST(request())).status).toBe(401)
    expect(auth.rpc).not.toHaveBeenCalled()
  })
  it.each([
    ['40001', 409, 'changed'],
    ['55P03', 409, 'busy'],
    ['23514', 409, 'documents_changed'],
    ['22023', 422, 'input'],
    ['XX001', 503, 'unavailable'],
  ])('sanitizes SQL %s as %s (%s)', async (code, status, kind) => {
    const x = setup()
    x.rpc.mockResolvedValueOnce({
      data: null,
      error: { code, message: 'SECRET must not escape' },
    } as never)
    const response = await x.routes.POST(request())
    expect(response.status).toBe(status)
    const body = await response.text()
    expect(body).toContain(`mobile_legacy_documents_${kind}`)
    expect(body).not.toContain('SECRET')
    expect(x.rpc).toHaveBeenCalledOnce()
  })
  it.each([
    'owner',
    'operation',
    'locale',
    'identity',
    'future_act',
    'extra',
  ] as const)('refuses a corrupt acknowledgement without retry or compensating signup (%s)', async (change) => {
    const x = setup()
    const original = x.rpc.getMockImplementation()
    if (!original) throw Error('Missing RPC fixture')
    x.rpc.mockImplementationOnce(async (name, args) => {
      const value = await original(name, args)
      if (change === 'owner') value.data.user_id = uid(4)
      if (change === 'operation') value.data.operation_key = uid(4)
      if (change === 'locale') value.data.receipt.locale = 'en-US'
      if (change === 'identity') value.data.receipt.document_actions[0].version = 'other'
      if (change === 'future_act')
        value.data.receipt.document_actions[0].acted_at = '2026-10-28T00:00:00.000004Z'
      if (change === 'extra') Object.assign(value.data.receipt, { epoch: uid(4) })
      return value
    })
    expect((await x.routes.POST(request())).status).toBe(503)
    expect(x.rpc).toHaveBeenCalledOnce()
  })
})
