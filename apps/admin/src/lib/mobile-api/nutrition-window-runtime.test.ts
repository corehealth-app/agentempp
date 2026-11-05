import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { NutritionWindowQuery, NutritionWindowReadPort } from './nutrition-window-repository'
import { createNutritionWindowReadService } from './nutrition-window-runtime'

const OWNER = 'a1111111-1111-4111-8111-111111111111'
const AUTH = 'a2222222-2222-4222-8222-222222222222'
const EPOCH = 'a3333333-3333-4333-8333-333333333333'
const at = '2026-11-04T15:00:00.000000Z'
function state(epoch: string | null = EPOCH) {
  return {
    version: 1,
    user_id: OWNER,
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
      user_id: OWNER,
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
  const rpcCalls: Array<{ name: string; args: unknown }> = [],
    tables: string[] = []
  const port: NutritionWindowReadPort = {
    from(table) {
      tables.push(table)
      const response = Promise.resolve({ data: [], error: null, count: 0 })
      const q: NutritionWindowQuery = {
        select: () => q,
        eq: () => q,
        gte: () => q,
        lt: () => q,
        lte: () => q,
        in: () => q,
        or: () => q,
        order: () => q,
        limit: () => q,
        // biome-ignore lint/suspicious/noThenProperty: actual PostgREST read queries are PromiseLike
        then: response.then.bind(response),
      }
      return q
    },
  }
  const client = {
    ...port,
    rpc: async (name: string, args: unknown) => {
      rpcCalls.push({ name, args })
      return { data: state(epoch), error: null }
    },
  } as unknown as ServiceClient
  return { client, rpcCalls, tables }
}
describe('Actual nutrition read service composition never bootstraps or applies a day', () => {
  it('is inert at construction and uses only profile observations plus two complete bounded captures', async () => {
    const f = harness(),
      service = createNutritionWindowReadService(f.client)
    expect(f.rpcCalls).toHaveLength(0)
    expect(f.tables).toHaveLength(0)
    const value = await service.read(auth)
    expect(value.owner_id).toBe(OWNER)
    expect(value.days).toHaveLength(7)
    expect(value.days.every((d) => d.totals.kcal === 0 && d.planned.status === 'protected')).toBe(
      true,
    )
    expect(f.rpcCalls).toHaveLength(2)
    for (const call of f.rpcCalls) {
      expect(call.name).toBe('get_mobile_current_clinical_state')
      expect(call.args).toEqual({
        p_user_id: OWNER,
        p_mode: 'profile',
        p_body: null,
        p_expected: null,
      })
    }
    expect(f.tables).toEqual([
      'daily_snapshots',
      'meal_logs',
      'prescriptions',
      'daily_snapshots',
      'meal_logs',
      'prescriptions',
    ])
  })
  it('refuses an absent signup epoch without creating it or reading a fake empty week', async () => {
    const f = harness(null)
    await expect(createNutritionWindowReadService(f.client).read(auth)).rejects.toMatchObject({
      status: 503,
      code: 'nutrition_window_unavailable',
    })
    expect(f.rpcCalls).toHaveLength(1)
    expect(f.tables).toHaveLength(0)
  })
})
