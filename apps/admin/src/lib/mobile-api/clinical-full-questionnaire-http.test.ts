import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { clinicalFullPublicCandidateId } from './clinical-full-public-command'
import { createClinicalFullQuestionnaire } from './clinical-full-questionnaire'
import { createClinicalFullQuestionnaireRoutes } from './clinical-full-questionnaire-http'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import wire from './testing/clinical-full-wire.json'

const owner = wire.context.user_id,
  subject = 'b3b01000-0000-4000-8000-000000004399'
const auth = {
  userId: owner,
  authUserId: subject,
  identity: { id: subject },
  patient: { id: owner, authUserId: subject, status: 'active', locale: 'pt-BR' },
} as MobileAuthContext
const scope = { kind: 'REGULAR', cycleId: wire.context.cycle_id }
const body = () => ({ ...scope, activityPurpose: 'normal' })
const draft = () => ({
  activityPurpose: 'normal',
  answers: structuredClone(wire.receipt.form.answers),
  preference: null,
  measureConfirmed: false,
  bodyFat: {
    confirmed: true,
    candidateId: clinicalFullPublicCandidateId(
      { ...scope, kind: 'REGULAR', userId: owner },
      wire.receipt.intent.bodyFat,
    ),
  },
})
function setup(enabled = true) {
  const capture = vi.fn().mockResolvedValue(structuredClone(wire.context))
  const service = createClinicalFullQuestionnaire({ enabled: true, repository: { capture } })
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'full-questionnaire-qa',
  }
  const createService = vi.fn(() => service)
  return {
    capture,
    service,
    runtime,
    createService,
    routes: createClinicalFullQuestionnaireRoutes({ enabled, createService }, runtime),
  }
}
function post(value: unknown, query = '') {
  return new Request(`https://bodyflow.test/api/mobile/v1/reevaluation/form${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(value),
  })
}
describe('public FULL questionnaire HTTP without clinical writes', () => {
  it('uses actual auth/entitlement and one real service capture without returning source identity', async () => {
    const x = setup(),
      response = await x.routes.DESCRIBE(post(body()))
    expect(response.status).toBe(200)
    const payload = await response.json()
    expect(payload.data.body_fat.percent).toBe(24)
    expect(payload.data.photo_requirement.required).toBe(true)
    expect(JSON.stringify(payload)).not.toContain('source_hash')
    expect(x.runtime.authorizeEntitlement).toHaveBeenCalledOnce()
    expect(x.capture).toHaveBeenCalledOnce()
  })
  it('runs the authoritative assessment without needing an idempotency key or preparing a command', async () => {
    const x = setup(),
      response = await x.routes.ASSESS(post({ ...scope, input: draft() }))
    expect(response.status).toBe(200)
    expect(
      (await response.json()).data.actions.find(
        (a: { choice: { kind: string } }) => a.choice.kind === 'keep',
      ).targets,
    ).toEqual({ calories_kcal: 1599, protein_g: 126 })
    expect(x.capture).toHaveBeenCalledOnce()
  })
  it('rejects scope/authority injection and query strings before capture', async () => {
    for (const [value, query] of [
      [{ ...body(), userId: subject }, ''],
      [body(), '?phase=ganho_massa'],
      [{ ...scope, input: { ...draft(), targets: {} } }, ''],
    ] as const) {
      const x = setup(),
        response =
          value && 'input' in value
            ? await x.routes.ASSESS(post(value, query))
            : await x.routes.DESCRIBE(post(value, query))
      expect(response.status).toBe(422)
      expect(x.capture).not.toHaveBeenCalled()
    }
  })
  it('stops at auth or entitlement failure without invoking the clinical service', async () => {
    for (const boundary of ['authenticate', 'authorizeEntitlement'] as const) {
      const x = setup()
      vi.mocked(x.runtime[boundary]).mockRejectedValueOnce(
        new MobileApiError(401, 'unauthorized', 'Unauthorized'),
      )
      expect((await x.routes.DESCRIBE(post(body()))).status).toBe(401)
      expect(x.createService).not.toHaveBeenCalled()
      expect(x.capture).not.toHaveBeenCalled()
    }
  })
  it('disabled routes do not create the service, capture, or fall back to the old path', async () => {
    const x = setup(false)
    expect((await x.routes.DESCRIBE(post(body()))).status).toBe(404)
    expect(x.createService).not.toHaveBeenCalled()
  })
  it('rejects oversized bodies before capture and invalid private output before publication', async () => {
    const x = setup()
    expect((await x.routes.DESCRIBE(post({ ...body(), padding: 'x'.repeat(20000) }))).status).toBe(
      413,
    )
    expect(x.capture).not.toHaveBeenCalled()
    const value = await x.service.describe(auth, body())
    x.createService.mockReturnValueOnce({
      ...x.service,
      describe: async () => ({ ...value, source_hash: 'must-never-be-public' }) as typeof value,
    })
    const response = await x.routes.DESCRIBE(post(body()))
    expect(response.status).toBe(503)
    expect(await response.text()).not.toContain('must-never-be-public')
  })
})
