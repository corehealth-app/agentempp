import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from './current-clinical-admission'
import { currentClinicalError, readCurrentClinicalState } from './current-clinical-state'
import { currentOnboardingIDs, currentOnboardingWire } from './testing/current-onboarding-fixture'

const { owner, generation, epoch } = currentOnboardingIDs
const later = '2026-10-27T12:00:00.000002Z'
const other = 'b3b01000-0000-4000-8000-000000007777'
function fixture(marker: string | null = null) {
  const value = currentOnboardingWire()
  const raw = {
    ...value,
    epoch: null,
    signup_generation: null,
    first_completion: marker === null,
    generation_token: { ...value.generation_token, onboarding_completed_at: marker },
    phase_origin: marker === null ? { kind: 'not_completed' } : value.phase_origin,
  }
  const authority = {
    kind: 'legacy_transition',
    user_id: owner,
    generation,
    epoch,
    admitted_at: value.observed_at,
    admitted_date: value.date,
    timezone_at_admission: value.timezone,
    profile_completed_marker: marker,
  }
  const after = {
    ...raw,
    epoch,
    signup_generation: generation,
    generation_authority: authority,
    first_completion: false,
    observed_at: later,
    safety: { ...raw.safety, observed_at: later },
    phase_origin: { kind: 'assigned', phase: 'recomposicao' },
  }
  return {
    before: readCurrentClinicalState(raw, owner),
    authority,
    after,
    receipt: { version: 1, availability: 'admitted', authority },
  }
}
describe('request-owned explicit clinical admission', () => {
  it.each([
    null,
    '2026-10-01T12:00:00.000001Z',
  ])('binds one real source while preserving the original marker %s and facts', async (marker) => {
    const x = fixture(marker),
      admit = vi.fn(async () => x.receipt),
      capture = vi.fn(async () => x.after)
    const boundary = createCurrentClinicalAdmission({ admit })
    expect(admit).not.toHaveBeenCalled()
    expect(capture).not.toHaveBeenCalled()
    const established = await boundary.establish(x.before, { capture })
    expect(admit).toHaveBeenCalledOnce()
    expect(admit).toHaveBeenCalledWith(owner)
    expect(capture).toHaveBeenCalledOnce()
    expect(capture).toHaveBeenCalledWith({
      userId: owner,
      mode: 'profile',
      expectedEpoch: epoch,
    })
    expect(established.first_completion).toBe(false)
    expect(established.generation_token?.onboarding_completed_at).toBe(marker)
    expect(Object.isFrozen(established.generation_authority)).toBe(true)
    expect(await boundary.establish(established, { capture })).toEqual(established)
    const reset = {
      ...x.after,
      epoch: other,
      signup_generation: null,
      generation_authority: undefined,
      first_completion: true,
      phase_origin: { kind: 'not_completed' },
      generation_token: {
        ...x.after.generation_token,
        onboarding_completed: false,
        onboarding_completed_at: null,
      },
    }
    await expect(
      boundary.establish(readCurrentClinicalState(reset, owner), { capture }),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_changed' })
    expect(admit).toHaveBeenCalledTimes(1)
    expect(capture).toHaveBeenCalledTimes(1)
  })
  it('shares an in-flight original preflight and keeps failures terminal within its own request', async () => {
    const x = fixture(),
      admit = vi.fn(async () => x.receipt),
      capture = vi.fn(async () => x.after)
    const boundary = createCurrentClinicalAdmission({ admit })
    const [a, b] = await Promise.all([
      boundary.establish(x.before, { capture }),
      boundary.establish(x.before, { capture }),
    ])
    expect(a).toEqual(b)
    expect(admit).toHaveBeenCalledOnce()
    expect(capture).toHaveBeenCalledOnce()
    const refused = vi.fn(async () => {
      throw Error('private upstream secret')
    })
    const failed = createCurrentClinicalAdmission({ admit: refused })
    for (let n = 0; n < 2; n++)
      await expect(failed.establish(x.before, { capture })).rejects.toMatchObject({
        code: 'mobile_current_clinical_unavailable',
        message: 'Unable to read current clinical state',
      })
    expect(refused).toHaveBeenCalledOnce()
  })
  it('never admits an incomplete or already proven source and refuses a later identity on the same boundary', async () => {
    const x = fixture(),
      admitted = readCurrentClinicalState(x.after, owner),
      source = vi.fn()
    const boundary = createCurrentClinicalAdmission({ admit: source }),
      capture = vi.fn()
    expect(await boundary.establish(admitted, { capture })).toEqual(admitted)
    const foreign = {
      ...x.after,
      user_id: other,
      health_state: { ...x.after.health_state, user_id: other },
      generation_authority: { ...x.authority, user_id: other },
    }
    await expect(
      boundary.establish(readCurrentClinicalState(foreign, other), { capture }),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_changed' })
    const pending = readCurrentClinicalState(
      {
        ...currentOnboardingWire(),
        signup_generation: null,
        epoch: null,
        first_completion: true,
        generation_token: {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: 0,
        },
        phase_origin: { kind: 'not_completed' },
      },
      owner,
    )
    expect(
      await createCurrentClinicalAdmission({ admit: source }).establish(pending, { capture }),
    ).toEqual(pending)
    expect(source).not.toHaveBeenCalled()
    expect(capture).not.toHaveBeenCalled()
  })
  it.each([
    'profile',
    'health',
    'config',
    'owner_date',
    'source',
  ] as const)('refuses a changed %s between admission and the new observation', async (kind) => {
    const x = fixture(),
      raw = structuredClone(x.after)
    if (kind === 'profile') raw.body.weight_kg = 81
    if (kind === 'health') {
      const held = currentOnboardingWire('hold')
      raw.health_state = held.health_state
      raw.safety = { ...held.safety, observed_at: later }
    }
    if (kind === 'config')
      Object.assign(raw, {
        calculation_config: [{ key: 'calc.training_min', value: 7, updated_at: later }],
      })
    if (kind === 'owner_date') {
      raw.date = '2026-10-28'
      raw.safety.date = raw.date
    }
    if (kind === 'source') raw.generation_authority.generation = other
    const admit = vi.fn(async () => x.receipt)
    await expect(
      createCurrentClinicalAdmission({ admit }).establish(x.before, { capture: async () => raw }),
    ).rejects.toBeDefined()
    expect(admit).toHaveBeenCalledOnce()
  })
  it('retains an observed epoch and cannot reinterpret an incomplete result as a new admission', async () => {
    const x = fixture(),
      capture = vi.fn()
    for (const result of [
      { version: 1, availability: 'unavailable', reason: 'onboarding_incomplete' },
      { ...x.receipt, authority: { ...x.authority, epoch: other } },
    ]) {
      const before = readCurrentClinicalState({ ...x.before, epoch }, owner)
      await expect(
        createCurrentClinicalAdmission({ admit: async () => result }).establish(before, {
          capture,
        }),
      ).rejects.toMatchObject({ code: 'mobile_current_clinical_changed' })
    }
    expect(capture).not.toHaveBeenCalled()
    await expect(
      createCurrentClinicalAdmission({ admit: async () => x.receipt }).establish(x.before, {
        capture: async () => {
          throw currentClinicalError('changed')
        },
      }),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_changed' })
  })
})
describe('service-only legacy admission transport', () => {
  it('is inert, keeps the RPC receiver, sends only owner and detaches the returned source', async () => {
    const x = fixture()
    const rpc = vi.fn(async function (this: unknown, name: string, args: unknown) {
      expect(this).toBe(client)
      expect(name).toBe('admit_mobile_clinical_legacy_generation')
      expect(args).toEqual({ p_user_id: owner })
      return { data: x.receipt, error: null }
    })
    const client = { rpc } as unknown as ServiceClient
    const source = createSupabaseLegacyClinicalAdmissionSource(client)
    expect(rpc).not.toHaveBeenCalled()
    const result = await source.admit(owner)
    x.authority.generation = other
    expect(result).toMatchObject({ authority: { generation } })
  })
  it.each(['40001', '55P03', '42501'])('sanitizes provider error %s', async (code) => {
    const rpc = vi.fn(async () => ({ data: null, error: { code, message: 'private token' } }))
    await expect(
      createSupabaseLegacyClinicalAdmissionSource({ rpc } as unknown as ServiceClient).admit(owner),
    ).rejects.toMatchObject({
      code: `mobile_current_clinical_${code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable'}`,
      message: 'Unable to read current clinical state',
    })
  })
  it.each([
    null,
    {},
    { data: null, error: null },
    { data: { version: 1, availability: 'admitted', authority: {} }, error: null },
  ])('rejects a malformed admission envelope without exposing it', async (packet) => {
    const rpc = vi.fn(async () => packet)
    await expect(
      createSupabaseLegacyClinicalAdmissionSource({ rpc } as unknown as ServiceClient).admit(owner),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_invalid_response' })
  })
})
