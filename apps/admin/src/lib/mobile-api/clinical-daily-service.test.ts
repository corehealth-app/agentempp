import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalDailyService } from './clinical-daily-service'
import { MobileApiError } from './http'

const owner = 'b3b01000-0000-4000-8000-000000001900'
const other = 'b3b01000-0000-4000-8000-000000001901'
const key = 'b3b01000-0000-4000-8000-000000001902'
const stamp = '2026-10-25T12:00:00.123456Z'
function auth(): MobileAuthContext {
  return {
    userId: owner,
    authUserId: other,
    accessToken: 'synthetic-only',
    identity: {
      id: other,
      email: 'clinical-qa@example.invalid',
      emailConfirmedAt: stamp,
    },
    patient: {
      id: owner,
      authUserId: other,
      email: 'clinical-qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
function snapshot() {
  return {
    version: 1,
    user_id: owner,
    review_kind: 'APPLICATION',
    cycle_id: null,
    observed_at: stamp,
    valid_until: '2026-10-26T03:00:00.000000Z',
    context_hash: 'a'.repeat(64),
    facts: {
      owner: { id: owner, status: 'active', locale: 'pt-BR', timezone: 'America/Sao_Paulo' },
      anchor: {
        signup_generation: other,
        signup_epoch: key,
        authority: {
          kind: 'signup_receipt',
          generation: other,
          epoch: key,
          completed_at: '2026-10-01T03:00:00.000000Z',
          timezone_at_signup: 'America/Sao_Paulo',
        },
      },
      calculation_date: '2026-10-25',
      profile: {
        user_id: owner,
        sex: 'masculino',
        birth_date: '1982-11-01',
        height_cm: 180,
        weight_kg: 81,
        body_fat_percent: null,
        body_fat_measured_at: null,
        onboarding_completed: true,
        onboarding_completed_at: '2026-10-01T03:00:00.000000Z',
        current_protocol: 'recomposicao',
        deficit_level: 500,
        activity_level: 'leve',
        training_frequency: 4,
        hunger_level: 'moderada',
      },
      day: null,
      calculation_config: [
        {
          key: 'calc.protein_factors',
          updated_at: stamp,
          value: {
            muita: 1.6,
            moderada: 1.8,
            pouca: 1.8,
            training_low: 1.7,
            optimal_mid_training: 1.9,
            optimal_high_training: 2,
          },
        },
      ],
      safety: { user_id: owner, hold_active: false, items: [] },
      protocol_authority: {
        body_fat_origin: null,
        signup_body_fat_origin: null,
        body_fat_candidate: null,
      },
    },
  }
}
const unavailable = {
  version: 1,
  availability: 'unavailable',
  reason: 'clinical_episode_unavailable',
  date: '2026-10-25',
}
const ack = (result: unknown = unavailable) => ({ user_id: owner, operation_key: key, result })
function setup() {
  const repo = {
    findReceipt: vi.fn().mockResolvedValue(null),
    capture: vi.fn().mockResolvedValue(snapshot()),
    apply: vi.fn().mockResolvedValue(ack()),
  }
  return { repo, service: createClinicalDailyService({ enabled: true, repository: repo }) }
}
describe('dormant daily service with the real core calculator', () => {
  it('replays a genuine first-phase daily receipt and rejects a substituted or fabricated FULL source', async () => {
    const { repo, service } = setup()
    const initial = {
      version: 1,
      availability: 'applied',
      source_kind: 'first_phase',
      application_id: other,
      application_no: '1',
      date: '2026-10-25',
      state: 'none',
      reason: 'episode_formula',
      needs_new_confirmation: false,
      applied_at: stamp,
      source_review_id: null,
      source_first_phase_id: key,
      schedule_review_id: null,
      targets: {
        calories_target: 2000,
        protein_target: 144,
        formula_target: 2000,
        effective_adjustment: 0,
      },
      episode: {
        user_id: owner,
        signup_generation: other,
        signup_epoch: key,
        first_phase_id: key,
        review_id: null,
      },
    }
    repo.findReceipt.mockResolvedValue(ack(initial))
    const { episode: _episode, ...visible } = initial
    expect(await service.apply(auth(), { operationKey: key })).toEqual(visible)
    for (const patch of [
      { source_first_phase_id: null },
      { source_first_phase_id: other },
      { source_review_id: other },
      { source_signup_id: other },
      { source_kind: 'full' },
      { schedule_review_id: other },
      { state: 'running' },
      { reason: 'confirmed_schedule' },
      { episode: { ...initial.episode, review_id: other } },
    ]) {
      repo.findReceipt.mockResolvedValue(ack({ ...initial, ...patch }))
      await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
        status: 503,
      })
    }
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('replays an actual signup-source acknowledgement before recapture, without inventing a review ID', async () => {
    const { repo, service } = setup()
    const initial = {
      version: 1,
      availability: 'applied',
      source_kind: 'signup',
      application_id: other,
      application_no: '1',
      date: '2026-10-25',
      state: 'none',
      reason: 'signup_formula',
      needs_new_confirmation: false,
      applied_at: stamp,
      source_review_id: null,
      source_signup_id: other,
      schedule_review_id: null,
      targets: {
        calories_target: 2000,
        protein_target: 144,
        formula_target: 2000,
        effective_adjustment: 0,
      },
      episode: { user_id: owner, signup_generation: other, signup_epoch: key },
    }
    repo.findReceipt.mockResolvedValue(ack(initial))
    const { episode: _episode, ...visible } = initial
    expect(await service.apply(auth(), { operationKey: key })).toEqual(visible)
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
    for (const patch of [
      { source_review_id: other },
      { source_signup_id: key },
      { source_kind: undefined },
      { reason: 'confirmed_schedule' },
      { state: 'running' },
      { targets: { ...initial.targets, formula_target: null, effective_adjustment: null } },
    ]) {
      repo.findReceipt.mockResolvedValue(ack({ ...initial, ...patch }))
      await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
        status: 503,
      })
    }
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it.each([
    'changed',
    'busy',
  ] as const)('retains a closed %s conflict without leaking repository messages', async (kind) => {
    const { repo, service } = setup()
    repo.findReceipt.mockRejectedValue(
      new MobileApiError(409, `mobile_clinical_daily_${kind}`, 'private SQL detail'),
    )
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 409,
      code: `mobile_clinical_daily_${kind}`,
      message:
        kind === 'changed'
          ? 'Clinical update changed; refresh before trying again'
          : 'Clinical update is busy; try again',
    })
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('does not promote an arbitrary repository error into a public clinical conflict', async () => {
    const { repo, service } = setup()
    repo.findReceipt.mockRejectedValue(
      new MobileApiError(409, 'private_backend_error', 'private SQL detail'),
    )
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
      code: 'mobile_clinical_daily_unavailable',
      message: 'Clinical update unavailable',
    })
  })
  it('validates a durable applied receipt without rounding its bigint or exposing the private episode', async () => {
    const { repo, service } = setup()
    repo.findReceipt.mockResolvedValue(
      ack({
        version: 1,
        availability: 'applied',
        application_id: key,
        application_no: '9007199254740993',
        date: '2026-10-24',
        state: 'running',
        reason: 'confirmed_schedule',
        needs_new_confirmation: false,
        applied_at: stamp,
        source_review_id: other,
        schedule_review_id: other,
        targets: {
          calories_target: 2100,
          protein_target: 144,
          formula_target: 2713,
          effective_adjustment: -613,
        },
        episode: {
          user_id: owner,
          signup_generation: other,
          signup_epoch: other,
          private_extra: 'not public',
        },
      }),
    )
    const result = await service.apply(auth(), { operationKey: key })
    expect(result).toMatchObject({ application_no: '9007199254740993', date: '2026-10-24' })
    expect(result).not.toHaveProperty('episode')
    expect(repo.capture).not.toHaveBeenCalled()
  })
  it('refuses a corrupt stored adjustment instead of returning a plausible success', async () => {
    const { repo, service } = setup()
    repo.findReceipt.mockResolvedValue(
      ack({
        version: 1,
        availability: 'applied',
        application_id: key,
        application_no: '1',
        date: '2026-10-25',
        state: 'running',
        reason: 'confirmed_schedule',
        needs_new_confirmation: false,
        applied_at: stamp,
        source_review_id: other,
        schedule_review_id: other,
        targets: {
          calories_target: 2100,
          protein_target: 144,
          formula_target: 2713,
          effective_adjustment: 0,
        },
        episode: { user_id: owner, signup_generation: other, signup_epoch: key },
      }),
    )
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
    })
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('does not borrow a captured profile from another owner', async () => {
    const { repo, service } = setup()
    const captured = snapshot()
    captured.facts.profile.user_id = other
    repo.capture.mockResolvedValue(captured)
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
    })
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('does not silently migrate a report-based target on a new day without provenance', async () => {
    const { repo, service } = setup()
    const captured = snapshot()
    Object.assign(captured.facts.profile, { body_fat_percent: 24 })
    repo.capture.mockResolvedValue(captured)
    await expect(service.apply(auth(), { operationKey: key })).resolves.toMatchObject({
      availability: 'unavailable',
      reason: 'legacy_formula_origin_unproven',
    })
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('does not even read the repository while disabled', async () => {
    const service = createClinicalDailyService({
      enabled: false,
      get repository(): never {
        throw new Error('Must stay unused')
      },
    })
    await expect(service.apply(auth(), { operationKey: key })).resolves.toEqual({
      version: 1,
      availability: 'unavailable',
      reason: 'disabled',
      date: null,
    })
  })
  it('passes only real core projections and the exact server hash to SQL', async () => {
    const { repo, service } = setup()
    await expect(service.apply(auth(), { operationKey: key })).resolves.toEqual(unavailable)
    expect(repo.findReceipt).toHaveBeenCalledWith(owner, key)
    expect(repo.capture).toHaveBeenCalledWith(owner)
    expect(repo.apply).toHaveBeenCalledWith(owner, key, 'a'.repeat(64), {
      version: 1,
      formulaKcal: 1570,
      maintenanceKcal: 2372,
      sedentaryKcal: 2070,
      proteinTarget: 121.5,
      maintenanceProteinTarget: 145.8,
    })
  })
  it('acknowledges the original before trying a changed or reset context', async () => {
    const { repo, service } = setup()
    repo.findReceipt.mockResolvedValue(ack())
    repo.capture.mockRejectedValue(new Error('Signup reset'))
    await expect(service.apply(auth(), { operationKey: key })).resolves.toEqual(unavailable)
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('captures authenticated identity before the first await', async () => {
    const { repo, service } = setup()
    const context = auth()
    repo.findReceipt.mockImplementation(async () => {
      context.userId = key
      context.patient.id = key
      return null
    })
    await service.apply(context, { operationKey: key })
    expect(repo.capture).toHaveBeenCalledWith(owner)
    expect(repo.apply.mock.calls[0]?.[0]).toBe(owner)
  })
  it.each([
    { operationKey: key, formulaKcal: 900 },
    { operationKey: key, userId: other },
    { operationKey: 'bad' },
  ])('refuses client authority fields %j', async (command) => {
    const { repo, service } = setup()
    await expect(service.apply(auth(), command)).rejects.toMatchObject({ status: 422 })
    expect(repo.findReceipt).not.toHaveBeenCalled()
  })
  it('refuses mismatched identity before receipt lookup', async () => {
    const { repo, service } = setup()
    const context = auth()
    context.patient.authUserId = key
    await expect(service.apply(context, { operationKey: key })).rejects.toMatchObject({
      status: 403,
    })
    expect(repo.findReceipt).not.toHaveBeenCalled()
  })
  it('refuses a receipt from another owner or operation', async () => {
    const { repo, service } = setup()
    repo.findReceipt.mockResolvedValue({ ...ack(), user_id: other })
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
    })
    expect(repo.capture).not.toHaveBeenCalled()
    repo.findReceipt.mockResolvedValue({ ...ack(), operation_key: other })
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
    })
  })
  it('does not write invented protein when its table is unverified', async () => {
    const { repo, service } = setup()
    const captured = snapshot()
    captured.facts.calculation_config = []
    captured.facts.profile.current_protocol = 'manutencao'
    repo.capture.mockResolvedValue(captured)
    await expect(service.apply(auth(), { operationKey: key })).resolves.toMatchObject({
      availability: 'unavailable',
      reason: 'protein_table_unverified',
    })
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('lets SQL suspend an unsafe schedule without offering a new target', async () => {
    const { repo, service } = setup()
    const captured = snapshot()
    Object.assign(captured.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    repo.capture.mockResolvedValue(captured)
    await service.apply(auth(), { operationKey: key })
    expect(repo.apply.mock.calls[0]?.[3]).toEqual({
      version: 1,
      formulaKcal: null,
      maintenanceKcal: null,
      sedentaryKcal: null,
      proteinTarget: null,
      maintenanceProteinTarget: null,
    })
  })
  it('never retries an uncertain write or exposes its raw error', async () => {
    const { repo, service } = setup()
    repo.apply.mockRejectedValue(new Error('sensitive details must not escape'))
    await expect(service.apply(auth(), { operationKey: key })).rejects.toMatchObject({
      status: 503,
      message: 'Clinical update unavailable',
    })
    expect(repo.apply).toHaveBeenCalledTimes(1)
  })
})
