import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { OnboardingRouteDependencies } from '@/app/api/mobile/v1/onboarding/handler'
import { readCurrentClinicalState } from './current-clinical-state'
import { createCurrentOnboardingRoutes } from './current-onboarding-http'
import type { OnboardingLoadRecord, OnboardingRepository } from './onboarding-service'
import type { MobileRouteRuntime } from './route'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth } from './testing/reevaluation-photo-consent-fixture'

function setup(kind: 'healthy' | 'hold' | 'no_plan' = 'no_plan', enabled = true) {
  const raw = currentOnboardingWire(kind)
  if (kind === 'no_plan')
    raw.phase_origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: raw.signup_generation,
      signupEpoch: raw.epoch,
      completedAt: raw.generation_token.onboarding_completed_at,
    }
  const record: OnboardingLoadRecord = {
    locale: 'pt-BR',
    completed: false,
    completedAt: raw.generation_token.onboarding_completed_at,
    acceptedActions: [],
    documents: [
      {
        documentKey: 'terms',
        version: '1',
        locale: 'pt-BR',
        body: 'Synthetic local text',
        contentUrl: null,
        contentHash: 'a'.repeat(64),
        purpose: 'synthetic',
        action: 'acceptance',
        required: true,
        effectiveAt: '2026-10-01T00:00:00Z',
      },
    ],
    draft: {
      name: 'Synthetic',
      locale: 'pt-BR',
      country: 'BR',
      timezone: 'America/Sao_Paulo',
      sex: 'masculino',
      birthDate: '1990-01-01',
      heightCm: 180,
      weightKg: 80,
      bodyFatPercent: 24,
      objective: kind === 'no_plan' ? null : 'recomposicao',
      activityLevel: 'moderado',
      trainingFrequency: 4,
      waterIntake: null,
      hungerLevel: 'moderada',
      wakeTime: '07:00',
      bedtime: '23:00',
      foodOrganization: 'sim',
      persona: 'focus',
    },
  }
  const repository: OnboardingRepository = {
    load: vi.fn(async () => structuredClone(record)),
    complete: vi.fn(async () => {
      throw Error('Unexpected write')
    }),
  }
  const capture = vi.fn(async () => structuredClone(raw))
  const signing = {
    enabled: vi.fn(() => true),
    createSources: vi.fn(() => {
      throw Error('Unexpected intent')
    }),
  }
  const deps: OnboardingRouteDependencies & {
    currentClinical: { capture: typeof capture }
    signupCompletion: typeof signing
  } = {
    createOnboardingRepository: vi.fn(() => repository),
    currentClinical: { capture },
    signupCompletion: signing,
    executeIdempotent: vi.fn(async () => {
      throw Error('Unexpected claim')
    }),
    saveLegacyOnboarding: vi.fn(async () => {
      throw Error('Unexpected legacy writer')
    }),
    finalizeSignupBodyPhotos: vi.fn(async () => {}),
  }
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => structuredClone(consentAuth)),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'current-onboarding-qa',
  }
  const createDependencies = vi.fn(() => deps)
  return {
    raw,
    record,
    repository,
    capture,
    signing,
    deps,
    runtime,
    createDependencies,
    routes: createCurrentOnboardingRoutes({ enabled, createDependencies }, runtime),
  }
}
const get = (
  query = '?clinical_policy=current_clinical_v1&onboarding_profile_schema=habitual_water_optional_v1',
) => new Request(`https://owned.test/api/mobile/v1/onboarding${query}`)
describe('current onboarding complete boundary', () => {
  it('uses the post-admission source as GET baseline and rejects bad queries before the port', async () => {
    const x = setup('healthy')
    const establish = vi.fn(async () => {
      const generation = 'b3b01000-0000-4000-8000-000000007701'
      x.raw.signup_generation = generation
      Object.assign(x.raw, {
        generation_authority: {
          kind: 'legacy_transition',
          user_id: x.raw.user_id,
          generation,
          epoch: x.raw.epoch,
          admitted_at: x.raw.observed_at,
          admitted_date: x.raw.date,
          timezone_at_admission: x.raw.timezone,
          profile_completed_marker: x.raw.generation_token.onboarding_completed_at,
        },
      })
      return readCurrentClinicalState(x.raw, x.raw.user_id)
    })
    x.deps.clinicalAdmission = { establish }
    expect((await x.routes.GET(get('?onboarding_profile_schema=bad'))).status).toBe(400)
    expect((await x.routes.GET(get('?body_photo_cleanup_generation=bad'))).status).toBe(400)
    expect(establish).not.toHaveBeenCalled()
    expect(x.capture).not.toHaveBeenCalled()
    expect((await x.routes.GET(get())).status).toBe(200)
    expect(establish).toHaveBeenCalledOnce()
    expect(x.repository.load).toHaveBeenCalledOnce()
    expect(x.deps.createOnboardingRepository).toHaveBeenCalledWith(expect.anything(), {
      legacyClinicalState: expect.objectContaining({
        generation_authority: readCurrentClinicalState(x.raw, x.raw.user_id).generation_authority,
      }),
    })
    const guarded = setup(),
      refused = vi.fn()
    guarded.deps.clinicalAdmission = { establish: refused }
    expect((await guarded.routes.GET(get(''))).status).toBe(409)
    expect(refused).not.toHaveBeenCalled()
  })
  it.each([
    null,
    '2026-10-01T12:00:00.000001Z',
  ])('returns documents-only legacy readiness without exposing the original source (%s)', async (marker) => {
    const x = setup('healthy')
    Object.assign(x.raw.generation_token, { onboarding_completed_at: marker })
    Object.assign(x.raw, {
      generation_authority: {
        kind: 'legacy_transition',
        user_id: x.raw.user_id,
        generation: x.raw.signup_generation,
        epoch: x.raw.epoch,
        admitted_at: x.raw.observed_at,
        admitted_date: x.raw.date,
        timezone_at_admission: x.raw.timezone,
        profile_completed_marker: marker,
      },
    })
    x.record.completedAt = marker
    x.record.draft = null
    x.record.legacyReconsent = { protocol: 'documents_only_v1' }
    const response = await x.routes.GET(get())
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data).toMatchObject({
      completion: { completed: false, completed_at: marker },
      legacy_reconsent: { protocol: 'documents_only_v1' },
      draft: null,
    })
    expect(JSON.stringify(data)).not.toContain('legacy_transition')
    expect(JSON.stringify(data)).not.toContain(x.raw.signup_generation)
    expect(x.signing.createSources).not.toHaveBeenCalled()
    expect(x.repository.complete).not.toHaveBeenCalled()
    expect(x.deps.executeIdempotent).not.toHaveBeenCalled()
    if (marker === null) {
      const refused = await x.routes.POST(
        new Request(get().url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'idempotency-key': 'synthetic-key' },
          body: '{}',
        }),
      )
      expect(refused.status).toBe(409)
      expect(await refused.text()).toContain('onboarding_reconsent_required')
      expect(x.signing.createSources).not.toHaveBeenCalled()
      expect(x.repository.complete).not.toHaveBeenCalled()
      expect(x.deps.executeIdempotent).not.toHaveBeenCalled()
    }
  })
  it('returns a literal nullable reacceptance draft, known capability and fresh private-free policy', async () => {
    const x = setup(),
      response = await x.routes.GET(get())
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data.draft.objective).toBeNull()
    expect(data.clinical_signup).toEqual({ representation: 'current_clinical_v2' })
    expect(data.signup_completion).toEqual({ protocol: 'osc1' })
    expect(data.clinical_policy).toMatchObject({
      version: 1,
      pause_weight_loss_guidance: true,
      hide: { objective: true },
    })
    expect(x.capture).toHaveBeenCalledTimes(2)
    for (const key of [
      'epoch',
      'signup_generation',
      'health_state',
      'profile_hash',
      'context_hash',
      'calculation_config',
    ])
      expect(data).not.toHaveProperty(key)
  })
  it('legacy cannot enter a protected profile, before ordinary profile/docs reads or POST claims', async () => {
    const x = setup()
    expect((await x.routes.GET(get(''))).status).toBe(409)
    const post = new Request(get('').url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': 'legacy-key' },
      body: '{}',
    })
    expect((await x.routes.POST(post)).status).toBe(409)
    expect(x.repository.load).not.toHaveBeenCalled()
    expect(x.deps.executeIdempotent).not.toHaveBeenCalled()
  })
  it('a changed epoch/health/profile/config during GET cannot publish the first observation', async () => {
    const x = setup('healthy')
    x.capture.mockImplementationOnce(async () => structuredClone(x.raw))
    x.capture.mockImplementationOnce(async () => ({
      ...structuredClone(x.raw),
      profile_hash: 'c'.repeat(64),
    }))
    expect((await x.routes.GET(get())).status).toBe(409)
  })
  it('healthy compatible legacy keeps its old shape and does not receive an opt-in capability', async () => {
    const x = setup('healthy')
    if (!x.record.draft) throw Error('Missing fixture draft')
    x.record.draft.waterIntake = 'moderado'
    const response = await x.routes.GET(get('')),
      data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data.clinical_signup).toBeUndefined()
    expect(data.clinical_policy).toBeUndefined()
  })
  it('a current completion requires a positive versioned intent before reaching normal admission', async () => {
    const x = setup('healthy')
    const response = await x.routes.POST(
      new Request(get().url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'idempotency-key': 'legacy-key' },
        body: '{}',
      }),
    )
    expect(response.status).toBe(409)
    expect(x.signing.createSources).not.toHaveBeenCalled()
    expect(x.deps.executeIdempotent).not.toHaveBeenCalled()
  })
  it('binds the request-scoped dependencies before an awaited producer can replace them', async () => {
    const x = setup('healthy')
    x.capture.mockImplementationOnce(async () => {
      x.deps.createOnboardingRepository = () => {
        throw Error('Replaced callback')
      }
      return structuredClone(x.raw)
    })
    expect((await x.routes.GET(get())).status).toBe(200)
    expect(x.repository.load).toHaveBeenCalledOnce()
  })
  it('does not advertise a capability switched off during an ordinary read', async () => {
    const x = setup('healthy')
    vi.mocked(x.repository.load).mockImplementationOnce(async () => {
      x.signing.enabled.mockReturnValue(false)
      return structuredClone(x.record)
    })
    expect((await x.routes.GET(get())).status).toBe(503)
  })
  it('unknown representations, disabled capability and unavailable OSC1 fail before normal reads', async () => {
    const x = setup()
    expect((await x.routes.GET(get('?clinical_policy=unknown'))).status).toBe(400)
    expect(x.capture).not.toHaveBeenCalled()
    const off = setup('healthy', false)
    expect((await off.routes.GET(get())).status).toBe(404)
    expect(off.capture).not.toHaveBeenCalled()
    x.signing.enabled.mockReturnValue(false)
    expect((await x.routes.GET(get())).status).toBe(503)
    expect(x.repository.load).not.toHaveBeenCalled()
  })
})
