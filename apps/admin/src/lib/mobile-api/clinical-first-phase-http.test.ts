import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalFirstPhaseRoutes } from './clinical-first-phase-http'
import type { MobileRouteRuntime } from './route'

const id = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const owner = id(1),
  key = id(2),
  preview = id(3)
const auth = (): MobileAuthContext => ({
  userId: owner,
  authUserId: id(4),
  accessToken: 'synthetic-only',
  identity: { id: id(4), email: null, emailConfirmedAt: null },
  patient: {
    id: owner,
    authUserId: id(4),
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
})
function setup(enabled = true) {
  const service = {
    choices: vi.fn().mockResolvedValue({
      availability: 'available',
      date: '2026-10-26',
      effectiveDate: '2026-10-26',
      missing: [],
      safety: {
        age: 36,
        bmi: 25,
        guards: { pregnantOrBreastfeeding: false },
        professionalAssessmentRecommended: false,
      },
      options: [{ phase: 'recomposicao', status: 'available', reasons: [] }],
    }),
    prepare: vi.fn().mockResolvedValue({
      preview_id: preview,
      user_id: owner,
      signup_generation: id(5),
      signup_epoch: id(6),
      context_hash: 'secret-private-context',
      selection: { phase: 'recomposicao' },
      valid_until: '2026-10-26T12:15:00.000000Z',
      package: {
        effectiveDate: '2026-10-26',
        targets: { afterKcal: 1413, afterProtein: 121.5 },
        formulaBodyFat: { origin: 'report', percent: null },
        episode: { difficultyCount: 0 },
      },
    }),
    confirm: vi.fn().mockResolvedValue({
      result: {
        first_phase_id: preview,
        event_id: id(8),
        episode_id: id(9),
        signup_generation: id(5),
        signup_epoch: id(6),
        applied_snapshot_id: id(10),
        phase: 'recomposicao',
        effective_date: '2026-10-26',
        confirmed_at: '2026-10-26T12:01:00.000000Z',
        targets: { calories_target: 1413, protein_target: 121.5, formula_target: 1413 },
      },
    }),
  }
  const createService = vi.fn(() => service)
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth()),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'first-phase-qa',
  }
  // Service outputs here carry deliberately private extras. The route's job is
  // a public whitelist; real service/SQL integration is covered by its bridge.
  const routes = createClinicalFirstPhaseRoutes({ enabled, createService }, runtime)
  return { routes, service, createService, runtime }
}
function post(path: string, body: unknown, operation: string | null = key) {
  return new Request(`https://bodyflow.test/api/mobile/v1/protocol/first-phase/${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(operation === null ? {} : { 'idempotency-key': operation }),
    },
    body: JSON.stringify(body),
  })
}
describe('first-phase authenticated public HTTP boundary', () => {
  it('returns only public choice fields, excluding health answers, age and BMI', async () => {
    const h = setup(),
      response = await h.routes.GET(
        new Request('https://bodyflow.test/api/mobile/v1/protocol/first-phase'),
      )
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      version: 1,
      availability: 'available',
      date: '2026-10-26',
      effective_date: '2026-10-26',
      professional_assessment_recommended: false,
      missing: [],
      options: [{ phase: 'recomposicao', status: 'available', reasons: [] }],
    })
    expect(h.runtime.authorizeEntitlement).toHaveBeenCalledOnce()
  })
  it('prepares only the selected phase with header UUID and publishes the displayed official targets', async () => {
    const h = setup(),
      response = await h.routes.PREVIEW(post('preview', { phase: 'recomposicao' }))
    expect(response.status).toBe(200)
    expect(h.service.prepare).toHaveBeenCalledWith(auth(), {
      operationKey: key,
      selection: { phase: 'recomposicao' },
    })
    expect((await response.json()).data).toEqual({
      version: 1,
      preview_id: preview,
      phase: 'recomposicao',
      effective_date: '2026-10-26',
      expires_at: '2026-10-26T12:15:00.000000Z',
      targets: { calories_kcal: 1413, protein_g: 121.5 },
    })
  })
  it('confirms by opaque preview, phase and header key, excluding provenance from the historical ACK', async () => {
    const h = setup(),
      response = await h.routes.CONFIRM(
        post('confirm', { preview_id: preview, phase: 'recomposicao' }),
      )
    expect(response.status).toBe(200)
    expect(h.service.confirm).toHaveBeenCalledWith(auth(), {
      operationKey: key,
      previewId: preview,
      selection: { phase: 'recomposicao' },
    })
    expect((await response.json()).data).toEqual({
      version: 1,
      confirmation_id: preview,
      phase: 'recomposicao',
      effective_date: '2026-10-26',
      confirmed_at: '2026-10-26T12:01:00.000000Z',
    })
  })
  it.each([
    { phase: 'recomposicao', calories: 1 },
    { phase: 'recomposicao', user_id: owner },
    { phase: 'recomposicao', context_hash: 'a'.repeat(64) },
    { phase: 'invalid' },
  ])('rejects client authority before the service: %j', async (body) => {
    const h = setup()
    expect((await h.routes.PREVIEW(post('preview', body))).status).toBe(422)
    expect(h.service.prepare).not.toHaveBeenCalled()
  })
  it.each([
    { key: null, status: 400 },
    { key: 'not-a-uuid', status: 422 },
  ])('requires an exact stable operation UUID: %j', async ({ key, status }) => {
    const h = setup()
    expect((await h.routes.PREVIEW(post('preview', { phase: 'recomposicao' }, key))).status).toBe(
      status,
    )
    expect(h.service.prepare).not.toHaveBeenCalled()
  })
  it('rejects GET query overrides before any service call', async () => {
    const h = setup()
    expect(
      (
        await h.routes.GET(
          new Request(`https://bodyflow.test/api/mobile/v1/protocol/first-phase?user_id=${owner}`),
        )
      ).status,
    ).toBe(422)
    expect(h.service.choices).not.toHaveBeenCalled()
  })
  it('disabled composition neither parses a body nor constructs or invokes a clinical service', async () => {
    const h = setup(false)
    expect(
      (
        await h.routes.PREVIEW(
          new Request('https://bodyflow.test/x', { method: 'POST', body: 'invalid' }),
        )
      ).status,
    ).toBe(404)
    expect(h.createService).not.toHaveBeenCalled()
  })
})
