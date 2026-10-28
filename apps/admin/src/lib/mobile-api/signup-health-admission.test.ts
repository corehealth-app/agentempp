import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createSignupHealthAdmissionService } from './signup-health-admission'
import fixture from './testing/health-hold-fixture.json'

const owner = fixture.initial.user_id
const authId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const key = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const intent = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
const requestKey = `osc1:${intent}`
const doc = {
  document_key: 'evaluation_4_sensitive_data_consent',
  version: '04.10.2026',
  locale: 'pt-BR',
  content_hash: 'a'.repeat(64),
  action: 'consent',
}
const command = () => ({
  version: 1,
  operation_key: key,
  intent_id: intent,
  request_key: requestKey,
  locale: 'pt-BR',
  document_actions: [{ ...doc }],
  risks: [...fixture.initial.receipt.items],
})
function auth(): MobileAuthContext {
  return {
    userId: owner,
    authUserId: authId,
    accessToken: 'synthetic-local',
    identity: { id: authId, email: 'qa@example.invalid', emailConfirmedAt: '2026-10-01T00:00:00Z' },
    patient: {
      id: owner,
      authUserId: authId,
      email: 'qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
function wire() {
  return {
    version: 1,
    user_id: owner,
    operation_key: key,
    receipt: {
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      intent_id: intent,
      request_key: requestKey,
      epoch: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      locale: 'pt-BR',
      requirement_set_id: '11111111-1111-4111-8111-111111111111',
      document_actions: [{ ...doc }],
      risks: [...fixture.initial.receipt.items],
      health_operation_key: fixture.initial.receipt.operation_key,
      admitted_at: fixture.initial.receipt.declared_at,
    },
    declaration: structuredClone(fixture.initial),
  }
}
function setup(raw: unknown = wire()) {
  const admit = vi.fn().mockResolvedValue(raw)
  const repository = { admit }
  const dependencies = { enabled: true, repository }
  return {
    admit,
    repository,
    dependencies,
    service: createSignupHealthAdmissionService(dependencies),
  }
}

describe('signup consent and marked risks, dormant trusted admission', () => {
  it('disabled never reads a repository and does not fabricate a health state', async () => {
    const service = createSignupHealthAdmissionService({
      enabled: false,
      get repository(): never {
        throw new Error('must not read')
      },
    })
    expect(await service.admit(auth(), command())).toEqual({
      availability: 'unavailable',
      reason: 'disabled',
    })
  })

  it('binds acknowledgement to the operation and strips internal epoch and health keys', async () => {
    const { service, admit } = setup()
    const result = await service.admit(auth(), command())
    if (result.availability !== 'available') throw new Error('expected admission')
    expect(admit.mock.calls).toEqual([[owner, command()]])
    expect(result).toMatchObject({
      availability: 'available',
      receipt: { intent_id: intent },
      state: fixture.initial.state,
    })
    expect(result).not.toHaveProperty('declaration')
    expect(result.receipt).not.toHaveProperty('epoch')
    expect(result.receipt).not.toHaveProperty('health_operation_key')
  })

  it('a replay with a later risk state is not preceded by a stale intent verification', async () => {
    const raw = wire()
    raw.declaration = structuredClone(fixture.replay)
    const { service, admit } = setup(raw)
    const result = await service.admit(auth(), command())
    expect(result).toMatchObject({ state: fixture.replay.state, receipt: { intent_id: intent } })
    expect(admit).toHaveBeenCalledTimes(1)
  })

  it('presents a cleared current state alongside the old immutable acknowledgement', async () => {
    const raw = wire()
    raw.declaration.state = {
      ...raw.declaration.state,
      safety_revision: '3',
      hold_active: false,
      hide_protein: false,
      declared_no_plan: false,
      items: [],
      last_declared_at: fixture.later.receipt.declared_at,
    }
    const { service, admit } = setup(raw)
    expect(await service.admit(auth(), command())).toMatchObject({
      state: { hold_active: false },
      receipt: { intent_id: intent },
    })
    expect(admit).toHaveBeenCalledTimes(1)
  })

  it('captures owner, command, receiver and dependency before awaiting', async () => {
    const context = auth()
    const input = command()
    let release: (value: unknown) => void = () => {
      throw new Error('not pending')
    }
    const pending = new Promise((resolve) => {
      release = resolve
    })
    const { service, admit, dependencies, repository } = setup()
    admit.mockImplementation(function (this: unknown) {
      expect(this).toBe(repository)
      return pending
    })
    const run = service.admit(context, input)
    context.userId = authId
    context.patient.id = authId
    input.document_actions[0].content_hash = 'b'.repeat(64)
    input.risks.reverse()
    dependencies.repository = { admit: vi.fn().mockRejectedValue(new Error('changed')) }
    release(wire())
    expect(await run).toMatchObject({ availability: 'available' })
    expect(admit.mock.calls[0]).toEqual([owner, command()])
  })

  it.each([
    { userId: authId },
    { authUserId: owner },
    { patient: { ...auth().patient, status: 'deleted' } },
  ])('rejects an unbound person before the repository %#', async (patch) => {
    const { service, admit } = setup()
    await expect(
      service.admit({ ...auth(), ...patch } as MobileAuthContext, command()),
    ).rejects.toMatchObject({ status: 403 })
    expect(admit).not.toHaveBeenCalled()
  })

  it.each([
    { risks: [] },
    { risks: ['none'] },
    { risks: ['professional_diet', 'professional_diet'] },
    { document_actions: [] },
    { document_actions: [doc, { ...doc, version: 'other' }] },
    { document_actions: [{ ...doc, locale: 'en-US' }] },
    { document_actions: [{ ...doc, consent: true }] },
    { request_key: 'osc1:not-a-uuid' },
    { epoch: intent },
    { weight_kg: 80 },
    { owner },
    { no_plan: true },
    { accepted: true },
    { version: 2 },
  ])('rejects invalid, ordinary or client-authority inputs %#', async (patch) => {
    const { service, admit } = setup()
    await expect(service.admit(auth(), { ...command(), ...patch })).rejects.toMatchObject({
      status: 422,
    })
    expect(admit).not.toHaveBeenCalled()
  })

  it('canonizes unordered documents and risks without changing their identities', async () => {
    const other = { ...doc, document_key: 'evaluation_1_terms_notice', action: 'acceptance' }
    const raw = wire()
    raw.receipt.document_actions = [other, doc]
    const { service, admit } = setup(raw)
    await service.admit(auth(), {
      ...command(),
      document_actions: [doc, other],
      risks: [...command().risks].reverse(),
    })
    expect(admit.mock.calls[0][1]).toEqual({ ...command(), document_actions: [other, doc] })
  })

  it('canonizes multiple marked risks in the shared catalog order', async () => {
    const raw = wire()
    raw.receipt.risks = ['reduced_intake', 'professional_diet']
    raw.declaration.receipt.items = ['reduced_intake', 'professional_diet']
    raw.declaration.state.items.unshift({
      code: 'reduced_intake',
      declared_at: raw.receipt.admitted_at,
    })
    const { service, admit } = setup(raw)
    await service.admit(auth(), { ...command(), risks: ['professional_diet', 'reduced_intake'] })
    expect(admit.mock.calls[0][1].risks).toEqual(['reduced_intake', 'professional_diet'])
  })

  it.each([
    'owner',
    'operation',
    'intent',
    'request',
    'documents',
    'risks',
    'health-key',
    'time',
    'extra',
  ])('rejects a mismatched acknowledgement: %s', async (kind) => {
    const raw = wire()
    if (kind === 'owner') raw.user_id = authId
    if (kind === 'operation') raw.operation_key = intent
    if (kind === 'intent') raw.receipt.intent_id = key
    if (kind === 'request') raw.receipt.request_key = `osc1:${key}`
    if (kind === 'documents') raw.receipt.document_actions[0].content_hash = 'b'.repeat(64)
    if (kind === 'risks') raw.receipt.risks = ['reduced_intake']
    if (kind === 'health-key') raw.receipt.health_operation_key = key
    if (kind === 'time') raw.receipt.admitted_at = '1990-01-01T00:00:00.000000Z'
    const { service } = setup(kind === 'extra' ? { ...raw, profile: { weight_kg: 80 } } : raw)
    await expect(service.admit(auth(), command())).rejects.toMatchObject({
      status: 503,
      code: 'mobile_signup_health_unavailable',
    })
  })

  it('sanitizes provider errors and never retries an uncertain admission', async () => {
    const { service, admit } = setup()
    admit.mockRejectedValue(new Error('private professional_diet secret'))
    const error = await service.admit(auth(), command()).catch((value: unknown) => value)
    expect(error).toMatchObject({
      status: 503,
      code: 'mobile_signup_health_unavailable',
      details: undefined,
    })
    expect(String(error)).not.toContain('professional_diet')
    expect(admit).toHaveBeenCalledTimes(1)
  })
})
