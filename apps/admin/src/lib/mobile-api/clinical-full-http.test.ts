import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalFullRoutes, projectClinicalFullPreview } from './clinical-full-http'
import { clinicalFullPublicCandidateId } from './clinical-full-public-command'
import { createClinicalFullService } from './clinical-full-service'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import { createSupabaseClinicalFullRepository } from './supabase-clinical-full'
import { createSupabaseHealthHoldRepository } from './supabase-health-hold'
import wire from './testing/clinical-full-wire.json'
import health from './testing/health-hold-fixture.json'

const owner = wire.context.user_id,
  subject = 'b3b01000-0000-4000-8000-000000004399'
const scope = { kind: 'REGULAR' as const, cycleId: wire.context.cycle_id }
const auth = {
  userId: owner,
  authUserId: subject,
  identity: { id: subject },
  patient: { id: owner, authUserId: subject, status: 'active', locale: 'pt-BR' },
} as MobileAuthContext
const policy = {
  version: 1 as const,
  hide: { objective: false, calories: false, protein: true },
  professionalAssessmentRecommended: true,
  pauseWeightLossGuidance: true,
}
function prepared(presentation: typeof policy | undefined = policy) {
  return {
    ...structuredClone(wire.prepared),
    command_version: 1 as const,
    command_hash: 'd'.repeat(64),
    normalization_context: { sex: 'masculino' as const, heightCm: 180 },
    command: {
      form: structuredClone(wire.receipt.form),
      choice: { kind: 'keep' as const },
      measureConfirmed: false,
      bodyFat: structuredClone(wire.receipt.intent.bodyFat),
    },
    package: {
      form: structuredClone(wire.receipt.form),
      intent: structuredClone(wire.receipt.intent),
      proposal: structuredClone(wire.receipt.proposal),
    },
    ...(presentation ? { presentation } : {}),
  }
}
const input = () => ({
  activityPurpose: 'normal',
  answers: structuredClone(wire.receipt.form.answers),
  preference: null,
  measureConfirmed: false,
  choice: { kind: 'keep' },
  bodyFat: {
    confirmed: true,
    candidateId: clinicalFullPublicCandidateId(
      { ...scope, userId: owner },
      wire.receipt.intent.bodyFat,
    ),
  },
})
function post(value: unknown, key: string | null = wire.prepared.operation_key, query = '') {
  return new Request(`https://bodyflow.test/api/mobile/v1/reevaluation/preview${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) },
    body: JSON.stringify(value),
  })
}
function setup(enabled = true) {
  const rpc = vi.fn(),
    client = { rpc } as unknown as ServiceClient
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => client,
    createRequestId: () => 'full-command-http-qa',
  }
  const routes = createClinicalFullRoutes(
    {
      enabled,
      createService: (c) =>
        createClinicalFullService({
          enabled: true,
          repository: createSupabaseClinicalFullRepository(c),
        }),
      createHealthDependencies: (c) => ({
        enabled: true,
        repository: createSupabaseHealthHoldRepository(c),
      }),
    },
    runtime,
  )
  const reply = (data: unknown) => rpc.mockResolvedValueOnce({ data, error: null })
  return { rpc, runtime, routes, reply }
}
describe('public FULL preview and historical confirmation projection', () => {
  it('uses only the original after-mask and never returns before-targets or private clinical authority', () => {
    const value = projectClinicalFullPreview(prepared())
    expect(value).toMatchObject({
      status: 'ready',
      phase: 'recomposicao',
      targets: { calories_kcal: 1599, protein_g: null },
      professional_assessment_recommended: true,
    })
    for (const name of [
      'beforeKcal',
      'beforeProtein',
      'sourceHash',
      'meanHundredths',
      'context_hash',
      'normalization_context',
      'user_id',
      'clearHold',
    ])
      expect(JSON.stringify(value)).not.toContain(name)
    const hidden = projectClinicalFullPreview(
      prepared({ ...policy, hide: { objective: true, calories: true, protein: true } }),
    )
    expect(hidden).toMatchObject({ phase: null, targets: { calories_kcal: null, protein_g: null } })
  })
  it('legacy preview without display proof returns historical-unavailable with no inferred numbers or phase', () => {
    const packet = prepared()
    delete packet.presentation
    const value = projectClinicalFullPreview(packet)
    expect(value).toEqual({
      version: 1,
      preview_id: wire.prepared.preview.preview_id,
      kind: 'REGULAR',
      cycle_id: scope.cycleId,
      expires_at: wire.prepared.preview.valid_until,
      status: 'historical_display_unavailable',
    })
  })
  it('an actual public preparation sends the server-derived policy, preserving entitlement and header key', async () => {
    const x = setup(),
      packet = prepared({
        ...policy,
        hide: { objective: false, calories: false, protein: false },
        professionalAssessmentRecommended: false,
        pauseWeightLossGuidance: false,
      })
    x.reply(null)
    x.reply(wire.context)
    x.reply(packet)
    const response = await x.routes.PREVIEW(post({ ...scope, input: input() }))
    expect(response.status).toBe(200)
    expect((await response.json()).data.targets).toEqual({ calories_kcal: 1599, protein_g: 126 })
    expect(x.rpc.mock.calls[2]).toEqual([
      'prepare_mobile_clinical_full_presented_command',
      expect.objectContaining({
        p_operation_key: wire.prepared.operation_key,
        p_presentation: packet.presentation,
      }),
    ])
    expect(x.runtime.authorizeEntitlement).toHaveBeenCalledOnce()
  })
  it('confirmed old receipt is acknowledged before current capture without displaying historical targets or policy', async () => {
    const x = setup(),
      old = prepared()
    delete old.presentation
    x.reply({ ...structuredClone(wire.receipt), prepared: old })
    const response = await x.routes.CONFIRM(
      post(
        { ...scope, previewId: wire.prepared.preview.preview_id, input: input() },
        wire.confirmed.operation_key,
      ),
    )
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      version: 1,
      review_id: wire.confirmed.result.review_id,
      kind: 'REGULAR',
      cycle_id: scope.cycleId,
      completed_at: wire.confirmed.result.completed_at,
      next_due_date: wire.confirmed.result.next_due_date,
    })
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual(['get_mobile_clinical_full_command_receipt'])
  })
  it('explicit health admission returns only a historical receipt, not the current risk snapshot', async () => {
    const x = setup(),
      value = structuredClone(health.initial)
    value.user_id = owner
    value.state.user_id = owner
    x.reply(value)
    const response = await x.routes.DECLARE_HEALTH(
      post({ items: value.receipt.items }, value.receipt.operation_key),
    )
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      version: 1,
      receipt_id: value.receipt.id,
      declared_at: value.receipt.declared_at,
    })
    expect(x.rpc.mock.calls[0]).toEqual([
      'declare_mobile_health_risk',
      {
        p_user_id: owner,
        p_operation_key: value.receipt.operation_key,
        p_items: value.receipt.items,
      },
    ])
  })
  it('rejects client policies/operation keys and invalid query/header/body bounds before any RPC', async () => {
    for (const value of [
      { ...scope, input: input(), presentation: policy },
      { ...scope, input: input(), operationKey: wire.confirmed.operation_key },
    ]) {
      const x = setup()
      expect((await x.routes.PREVIEW(post(value))).status).toBe(422)
      expect(x.rpc).not.toHaveBeenCalled()
    }
    const x = setup()
    expect((await x.routes.PREVIEW(post({ ...scope, input: input() }, null))).status).toBe(400)
    expect(
      (
        await x.routes.PREVIEW(
          post({ ...scope, input: input() }, wire.prepared.operation_key, '?owner=other'),
        )
      ).status,
    ).toBe(422)
    expect((await x.routes.PREVIEW(post({ padding: 'x'.repeat(17000) }))).status).toBe(413)
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('disabled/auth/entitlement failures never invoke a clinical RPC', async () => {
    const disabled = setup(false)
    expect((await disabled.routes.PREVIEW(post({ ...scope, input: input() }))).status).toBe(404)
    expect(disabled.rpc).not.toHaveBeenCalled()
    for (const method of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[method]).mockRejectedValueOnce(
        new MobileApiError(403, 'forbidden', 'Forbidden'),
      )
      expect((await x.routes.PREVIEW(post({ ...scope, input: input() }))).status).toBe(403)
      expect(x.rpc).not.toHaveBeenCalled()
    }
  })
})
