import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { TrainingWindowQuery, TrainingWindowReadPort } from './training-window-repository'
import { createTrainingWindowReadService } from './training-window-runtime'

const OWNER = 'a1111111-1111-4111-8111-111111111111'
const AUTH = 'a2222222-2222-4222-8222-222222222222'
const EPOCH = 'a3333333-3333-4333-8333-333333333333'
const at = '2026-11-04T15:00:00.000000Z'
function state(epoch: string | null = EPOCH, owner = OWNER) {
  return {
    version: 1,
    user_id: owner,
    mode: 'profile',
    profile_present: true,
    epoch,
    signup_generation: null,
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    first_completion: true,
    observed_at: at,
    date: '2026-11-04',
    timezone: 'America/Sao_Paulo',
    body: {
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      sex: 'masculino',
      birth_date: '1990-01-01',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: 24,
      training_frequency: 4,
    },
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
      date: '2026-11-04',
      timezone: 'America/Sao_Paulo',
      observed_at: at,
    },
    phase_origin: { kind: 'not_completed' },
    calculation_config: [],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
const auth: MobileAuthContext = {
  accessToken: 'synthetic',
  authUserId: AUTH,
  userId: OWNER,
  identity: { id: AUTH, email: null, emailConfirmedAt: at },
  patient: {
    id: OWNER,
    authUserId: AUTH,
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
function harness(epoch: string | null = EPOCH) {
  const forbidden = vi.fn(() => {
    throw new Error('No writer/bootstrap/closer')
  })
  const rpcCalls: Array<{ name: string; args: unknown }> = [],
    tables: string[] = []
  const port: TrainingWindowReadPort = {
    from(table) {
      tables.push(table)
      let q: TrainingWindowQuery
      q = Object.assign(Promise.resolve({ data: [], error: null, count: 0 }), {
        select: () => q,
        eq: () => q,
        gte: () => q,
        lt: () => q,
        order: () => q,
        limit: () => q,
        insert: forbidden,
        update: forbidden,
        delete: forbidden,
      })
      return q
    },
  }
  const client = {
    ...port,
    rpc: async (name: string, args: unknown) => {
      rpcCalls.push({ name, args })
      if (name === 'get_mobile_current_clinical_state') return { data: state(epoch), error: null }
      return forbidden()
    },
  } as unknown as ServiceClient
  return { client, rpcCalls, tables, forbidden }
}
describe('Actual training read composition', () => {
  it('is inert at construction and reads only official workouts and current clinical profile', async () => {
    const f = harness(),
      service = createTrainingWindowReadService(f.client)
    expect(f.rpcCalls).toEqual([])
    expect(f.tables).toEqual([])
    const value = await service.read(auth)
    expect(value.owner_id).toBe(OWNER)
    expect(value.days.every((d) => d.workouts.length === 0)).toBe(true)
    expect(f.tables).toEqual(['workout_logs', 'workout_logs'])
    expect(f.rpcCalls).toHaveLength(2)
    for (const r of f.rpcCalls)
      expect(r).toEqual({
        name: 'get_mobile_current_clinical_state',
        args: { p_user_id: OWNER, p_mode: 'profile', p_body: null, p_expected: null },
      })
    expect(f.forbidden).not.toHaveBeenCalled()
  })
  it('missing epoch never bootstraps a replacement or reads a fictitious empty week', async () => {
    const f = harness(null)
    await expect(createTrainingWindowReadService(f.client).read(auth)).rejects.toMatchObject({
      status: 503,
      code: 'training_window_unavailable',
    })
    expect(f.rpcCalls).toHaveLength(1)
    expect(f.tables).toEqual([])
    expect(f.forbidden).not.toHaveBeenCalled()
  })
})
