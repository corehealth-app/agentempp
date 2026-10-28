import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { captureCurrentClinicalState, projectCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

const owner = 'b3b01000-0000-4000-8000-000000002920'
const other = 'b3b01000-0000-4000-8000-000000002921'
const at = '2026-10-26T03:00:00.000001Z'
const body = {
  locale: 'pt-BR' as const,
  timezone: 'America/Sao_Paulo',
  sex: 'masculino' as const,
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 24,
  training_frequency: 4,
}
function state() {
  return {
    version: 1,
    user_id: owner,
    mode: 'signup',
    profile_present: true,
    epoch: null,
    signup_generation: null,
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    first_completion: true,
    observed_at: at,
    date: '2026-10-26',
    timezone: body.timezone,
    body: { ...body },
    assessment: 'complete',
    missing: [],
    health_state: {
      version: 1,
      user_id: owner,
      safety_revision: '0',
      hold_active: false,
      declared_no_plan: false,
      hide_protein: false,
      last_declared_at: null,
      items: [],
    },
    safety: {
      version: 1,
      no_plan: false,
      hold_active: false,
      loss_guard: false,
      hide_protein: false,
      recording_allowed: true,
      date: '2026-10-26',
      timezone: body.timezone,
      observed_at: at,
    },
    phase_origin: { kind: 'not_completed' },
    calculation_config: [],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
function database(response: unknown = { data: state(), error: null }) {
  const rpc = vi.fn(async function (this: unknown, _name: string, _args: unknown) {
    expect(this).toBe(client)
    return response
  })
  const client = { rpc } as unknown as ServiceClient
  return { client, rpc, source: createSupabaseCurrentClinicalStateSource(client) }
}
describe('current clinical trusted transport', () => {
  it('does nothing on construction, keeps RPC receiver and sends only clinical fields', async () => {
    const d = database()
    expect(d.rpc).not.toHaveBeenCalled()
    const result = await d.source.capture({
      userId: owner,
      mode: 'signup',
      body: { ...body, name: 'do not forward', no_plan: true } as typeof body,
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('get_mobile_current_clinical_state', {
      p_user_id: owner,
      p_mode: 'signup',
      p_body: body,
      p_expected: null,
    })
    expect(result).toMatchObject({ user_id: owner, observed_at: at })
    expect(Object.isFrozen(result)).toBe(true)
  })
  it('freezes input before await and detaches mutable output', async () => {
    const raw = state(),
      input = { userId: owner, mode: 'signup' as const, body: { ...body } }
    const rpc = vi.fn(async (_name: string, args: { p_user_id: string; p_body: typeof body }) => {
      input.userId = other
      input.body.weight_kg = 99
      expect(args.p_user_id).toBe(owner)
      expect(args.p_body.weight_kg).toBe(80)
      expect(Object.isFrozen(args.p_body)).toBe(true)
      return { data: raw, error: null }
    })
    const result = await createSupabaseCurrentClinicalStateSource({
      rpc,
    } as unknown as ServiceClient).capture(input)
    raw.body.weight_kg = 99
    expect(result).toMatchObject({ user_id: owner, body: { weight_kg: 80 } })
  })
  it('sends profile mode with null body, never a client clock or another read', async () => {
    const raw = { ...state(), mode: 'profile' }
    const d = database({ data: raw, error: null })
    const value = await captureCurrentClinicalState(d.source, { userId: owner, mode: 'profile' })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('get_mobile_current_clinical_state', {
      p_user_id: owner,
      p_mode: 'profile',
      p_body: null,
      p_expected: null,
    })
    expect(projectCurrentClinicalState(value).targetSource).toBe('unavailable')
  })
  it('retains expected epoch and exact generation, including photo receipt count', async () => {
    const raw = { ...state(), epoch: other }
    const d = database({ data: raw, error: null })
    await d.source.capture({
      userId: owner,
      mode: 'signup',
      body,
      expectedEpoch: other,
      expectedGeneration: raw.generation_token,
    })
    expect(d.rpc.mock.calls[0]?.[1]).toMatchObject({
      p_expected: {
        epoch: other,
        generation_token: raw.generation_token,
      },
    })
  })
  it.each([
    null,
    [],
    {},
    { data: state() },
    { error: null },
    { data: state(), error: [] },
    { data: null, error: 'private sensitive error' },
    { data: { ...state(), user_id: other }, error: null },
    { data: { ...state(), body: { ...body, weight_kg: 99 } }, error: null },
    {
      data: { ...state(), health_state: { ...state().health_state, user_id: other } },
      error: null,
    },
  ])('rejects malformed or mismatched envelopes without returning partial data (%#)', async (raw) => {
    const d = database(raw)
    await expect(d.source.capture({ userId: owner, mode: 'signup', body })).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    '40001',
    '55P03',
  ])('keeps %s as a safe refresh refusal through outer capture', async (code) => {
    const d = database({ data: state(), error: { code, message: 'private health detail' } })
    const pending = captureCurrentClinicalState(d.source, { userId: owner, mode: 'signup', body })
    await expect(pending).rejects.toMatchObject({
      status: 409,
      code: code === '40001' ? 'mobile_current_clinical_changed' : 'mobile_current_clinical_busy',
    })
    await expect(pending).rejects.not.toThrow('private health detail')
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
  it('does not fallback or retry when provider throws', async () => {
    const d = database()
    d.rpc.mockRejectedValueOnce(new Error('secret connection'))
    await expect(d.source.capture({ userId: owner, mode: 'signup', body })).rejects.toMatchObject({
      status: 503,
      code: 'mobile_current_clinical_unavailable',
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
  it('rebuilds a recognized producer refusal without retaining its private message', async () => {
    const pending = captureCurrentClinicalState(
      {
        capture: async () => {
          throw new MobileApiError(409, 'mobile_current_clinical_changed', 'private health detail')
        },
      },
      { userId: owner, mode: 'profile' },
    )
    await expect(pending).rejects.toMatchObject({
      status: 409,
      code: 'mobile_current_clinical_changed',
    })
    await expect(pending).rejects.not.toThrow('private health detail')
  })
  it('rejects invalid local input before calling the provider', async () => {
    const d = database()
    await expect(d.source.capture({ userId: 'not-owner', mode: 'profile' })).rejects.toThrow()
    expect(d.rpc).not.toHaveBeenCalled()
  })
  it.each([
    '42501',
    '22023',
    'XX000',
  ])('does not expose provider code/details for %s', async (code) => {
    const d = database({ data: state(), error: { code, message: 'secret health detail' } })
    await expect(d.source.capture({ userId: owner, mode: 'signup', body })).rejects.toMatchObject({
      status: 503,
      code: 'mobile_current_clinical_unavailable',
    })
  })
})
