// SOURCE ONLY / NOT RUN. Written before R2 preparation/SQL.
// Root registers this factory with R1 then R2 prepare in its real source closure.
// This tests preparation only, not a SQL transaction or real provider transport.

import type { Json, ServiceClient, Tables } from '@mpp/db'
import { describe, expect, test } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { RegistrationProposalInput } from './contracts'

type InputItem = Extract<RegistrationProposalInput, { kind: 'meal' }>['items'][number]
type State = {
  context: Pick<
    Tables<'users'>,
    | 'id'
    | 'auth_user_id'
    | 'country'
    | 'country_confirmed'
    | 'timezone'
    | 'status'
    | 'wpp'
    | 'updated_at'
  >
  snapshot: Tables<'daily_snapshots'>
  items: Tables<'meal_logs'>[]
}
type Command =
  | { method: 'PATCH'; body: { expected_version: string; item_ids: string[]; items: InputItem[] } }
  | { method: 'DELETE'; body: { expected_version: string; item_ids: string[] } }
type Prepare = (
  client: ServiceClient,
  auth: MobileAuthContext,
  id: string,
  command: Command,
  state: State,
  now: Date,
) => Promise<{ expectedState: State; calculatedItems: Json | null }>

const USER = '11111111-1111-4111-8111-111111111111'
const AUTH = '22222222-2222-4222-8222-222222222222'
const SNAPSHOT = '33333333-3333-4333-8333-333333333333'
const RECORD = '44444444-4444-4444-8444-444444444444'
const NOW = new Date('2026-10-09T15:00:00.000Z')

function fixture(): State {
  return {
    context: {
      id: USER,
      auth_user_id: AUTH,
      country: 'BR',
      country_confirmed: true,
      timezone: 'America/Sao_Paulo',
      status: 'active',
      wpp: null,
      updated_at: '2026-10-09T12:00:00Z',
    },
    snapshot: {
      id: SNAPSHOT,
      user_id: USER,
      date: '2026-10-09',
      day_closed: false,
      calories_consumed: 55,
      protein_g: 3,
      carbs_g: 4.5,
      fat_g: 2.75,
      calories_target: 2000,
      protein_target: 100,
      daily_balance: -1945,
      exercise_calories: 0,
      closed_at: null,
      created_at: '2026-10-09T03:00:00Z',
      updated_at: '2026-10-09T12:00:00Z',
      current_protocol: null,
      day_status: 'in_progress',
      deficit_accumulated: 0,
      gap_reminder_sent_at: null,
      sleep_hours: null,
      steps: null,
      training_done: false,
      water_consumed_ml: 0,
      xp_earned: 0,
    },
    items: [
      {
        id: RECORD,
        user_id: USER,
        snapshot_id: SNAPSHOT,
        food_name: 'iogurte natural',
        quantity_g: 85,
        kcal: 55,
        protein_g: 3,
        carbs_g: 4.5,
        fat_g: 2.75,
        source: 'product_label',
        food_db_id: null,
        confidence: 0.92,
        meal_type: 'almoco',
        consumed_at: '2026-10-09T12:00:00Z',
        created_at: '2026-10-09T12:00:01Z',
        raw_provider_message_id: 'mobile-app:synthetic-c11-label',
        raw_message_id: '55555555-5555-4555-8555-555555555555',
        image_url: 'synthetic-private-origin',
      },
    ],
  }
}

function auth(): MobileAuthContext {
  return {
    accessToken: 'synthetic-not-a-valid-token',
    authUserId: AUTH,
    userId: USER,
    identity: {
      id: AUTH,
      email: 'synthetic@example.invalid',
      emailConfirmedAt: '2026-10-09T00:00:00Z',
    },
    patient: {
      id: USER,
      authUserId: AUTH,
      email: 'synthetic@example.invalid',
      name: 'Synthetic',
      locale: 'pt-BR',
      timezone: 'UTC',
      country: 'US',
      countryConfirmed: false,
      status: 'active',
    },
  }
}

function noLookup() {
  const calls: string[] = []
  // Boundary sentinel only: no memory-SQL simulation and no successful fake response.
  const client = {
    from(table: string) {
      calls.push(table)
      throw new Error('LOOKUP_SENTINEL')
    },
  } as unknown as ServiceClient
  return { client, calls }
}

function resultArray(value: Json | null): Record<string, Json | undefined>[] {
  expect(Array.isArray(value)).toBe(true)
  if (!Array.isArray(value)) throw new Error('Actual calculated items are absent')
  return value.map((item) => {
    expect(item !== null && typeof item === 'object' && !Array.isArray(item)).toBe(true)
    if (item === null || typeof item !== 'object' || Array.isArray(item))
      throw new Error('Invalid item')
    return item
  })
}

export function registerQuantityProvenanceRegressions(
  prepare: Prepare,
  version: (state: State) => string,
) {
  async function run(state: State, items: InputItem[], method: 'PATCH' | 'DELETE' = 'PATCH') {
    const sentinel = noLookup()
    const before = structuredClone(state)
    const selection = { expected_version: version(state), item_ids: [RECORD] }
    const command: Command =
      method === 'PATCH' ? { method, body: { ...selection, items } } : { method, body: selection }
    let result: Awaited<ReturnType<Prepare>> | null = null
    let failure: unknown = null
    try {
      result = await prepare(sentinel.client, auth(), RECORD, command, state, NOW)
    } catch (error) {
      failure = error
    }
    // OLD R1 fails this assertion when it calls the actual resolver boundary.
    // Its caught sentinel is never confused with a parser/import RED.
    expect(sentinel.calls).toEqual([])
    expect(state).toEqual(before)
    return { result, failure }
  }

  describe('C11 exact quantity/provenance preparation regressions', () => {
    test('product_label85→170 preserves official macros/source/id/confidence without a lookup', async () => {
      const state = fixture()
      const { result, failure } = await run(state, [
        { food_name: 'iogurte natural', quantity_g: 170 },
      ])
      expect(failure).toBeNull()
      expect(result?.expectedState).toEqual(state)
      expect(resultArray(result?.calculatedItems ?? null)).toEqual([
        {
          food_name: 'iogurte natural',
          quantity_g: 170,
          kcal: 110,
          protein_g: 6,
          carbs_g: 9,
          fat_g: 5.5,
          source: 'product_label',
          food_db_id: null,
          confidence: 0.92,
        },
      ])
    })

    test('quantity-only preserves sourceNULL/confidenceNULL rather than promoting them', async () => {
      const state = fixture()
      const item = state.items[0]
      if (!item) throw new Error('Fixture anchor missing')
      item.source = null
      item.confidence = null
      const { result, failure } = await run(state, [
        { food_name: 'iogurte natural', quantity_g: 170 },
      ])
      expect(failure).toBeNull()
      const [actual] = resultArray(result?.calculatedItems ?? null)
      expect(actual).toEqual({
        food_name: 'iogurte natural',
        quantity_g: 170,
        kcal: 110,
        protein_g: 6,
        carbs_g: 9,
        fat_g: 5.5,
        source: null,
        food_db_id: null,
        confidence: null,
      })
    })

    for (const golden of [
      {
        oldQuantity: 100,
        oldKcal: 11.1,
        oldProtein: 2.01,
        oldCarbs: 2.03,
        oldFat: 2.05,
        quantity: 50,
        kcal: 5.6,
        protein: 1.01,
        carbs: 1.02,
        fat: 1.03,
      },
      {
        oldQuantity: 100,
        oldKcal: 11.1,
        oldProtein: 2.01,
        oldCarbs: 2.03,
        oldFat: 2.05,
        quantity: 33,
        kcal: 3.7,
        protein: 0.66,
        carbs: 0.67,
        fat: 0.68,
      },
      {
        oldQuantity: 50,
        oldKcal: 5.6,
        oldProtein: 1.01,
        oldCarbs: 1.02,
        oldFat: 1.03,
        quantity: 100,
        kcal: 11.2,
        protein: 2.02,
        carbs: 2.04,
        fat: 2.06,
      },
    ]) {
      test(`official rounded quantities ${golden.oldQuantity}→${golden.quantity} use literal calorie/macro goldens`, async () => {
        const state = fixture()
        const item = state.items[0]
        if (!item) throw new Error('Fixture anchor missing')
        Object.assign(item, {
          quantity_g: golden.oldQuantity,
          kcal: golden.oldKcal,
          protein_g: golden.oldProtein,
          carbs_g: golden.oldCarbs,
          fat_g: golden.oldFat,
        })
        const { result, failure } = await run(state, [
          { food_name: 'iogurte natural', quantity_g: golden.quantity },
        ])
        expect(failure).toBeNull()
        expect(resultArray(result?.calculatedItems ?? null)[0]).toMatchObject({
          quantity_g: golden.quantity,
          kcal: golden.kcal,
          protein_g: golden.protein,
          carbs_g: golden.carbs,
          fat_g: golden.fat,
          source: 'product_label',
          confidence: 0.92,
        })
      })
    }

    for (const source of ['user_kcal', 'pending_approved', 'legacy_estimate']) {
      test(`quantity-only keeps ${source} provenance and exact proportional official values`, async () => {
        const state = fixture()
        const item = state.items[0]
        if (!item) throw new Error('Fixture anchor missing')
        item.source = source
        const { result, failure } = await run(state, [
          { food_name: 'iogurte natural', quantity_g: 170 },
        ])
        expect(failure).toBeNull()
        expect(resultArray(result?.calculatedItems ?? null)[0]).toMatchObject({
          source,
          food_db_id: null,
          quantity_g: 170,
          kcal: 110,
          protein_g: 6,
          carbs_g: 9,
          fat_g: 5.5,
        })
      })
    }

    test('exact NFD/case/spaces retain the official food spelling without country fallback', async () => {
      const state = fixture()
      state.context.country = null
      state.context.country_confirmed = false
      const { result, failure } = await run(state, [
        { food_name: '  IOGURTE   NATURAL  ', quantity_g: 170 },
      ])
      expect(failure).toBeNull()
      expect(resultArray(result?.calculatedItems ?? null)[0]).toMatchObject({
        food_name: 'iogurte natural',
        source: 'product_label',
      })
    })

    test('finite DELETE ignores missing nutrition and country and performs no calculation', async () => {
      const state = fixture()
      const item = state.items[0]
      if (!item) throw new Error('Fixture anchor missing')
      state.context.country = null
      state.context.country_confirmed = false
      item.protein_g = null
      const { result, failure } = await run(state, [], 'DELETE')
      expect(failure).toBeNull()
      expect(result).toMatchObject({ expectedState: state, calculatedItems: null })
    })

    for (const field of ['quantity_g', 'kcal', 'protein_g', 'carbs_g', 'fat_g'] as const) {
      test(`raw ${field} NULL is refused rather than converted to0`, async () => {
        const state = fixture()
        const item = state.items[0]
        if (!item) throw new Error('Fixture anchor missing')
        item[field] = null
        const { result, failure } = await run(state, [
          { food_name: 'iogurte natural', quantity_g: 170 },
        ])
        expect(result).toBeNull()
        expect(failure).toMatchObject({ status: 422, code: 'MEAL_NUTRITION_UNRESOLVED' })
      })
    }

    test('a new quantity below physical numeric precision is refused without any lookup', async () => {
      const { result, failure } = await run(fixture(), [
        { food_name: 'iogurte natural', quantity_g: 0.001 },
      ])
      expect(result).toBeNull()
      expect(failure).toMatchObject({ status: 422, code: 'MEAL_QUANTITY_NOT_REPRESENTABLE' })
    })

    test('legitimate zero official nutrients remain zero', async () => {
      const state = fixture()
      const item = state.items[0]
      if (!item) throw new Error('Fixture anchor missing')
      item.kcal = 0
      item.protein_g = 0
      item.carbs_g = 0
      item.fat_g = 0
      const { result, failure } = await run(state, [
        { food_name: 'iogurte natural', quantity_g: 170 },
      ])
      expect(failure).toBeNull()
      expect(resultArray(result?.calculatedItems ?? null)[0]).toMatchObject({
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
      })
    })

    test('old impossible density is refused without silently resolving another food', async () => {
      const state = fixture()
      const item = state.items[0]
      if (!item) throw new Error('Fixture anchor missing')
      item.kcal = 1000
      const { result, failure } = await run(state, [
        { food_name: 'iogurte natural', quantity_g: 170 },
      ])
      expect(result).toBeNull()
      expect(failure).toMatchObject({ status: 422, code: 'MEAL_NUTRITION_UNRESOLVED' })
    })

    for (const input of [
      [{ food_name: 'iogurte natural', quantity_g: 170, user_kcal: 99 }],
      [{ food_name: 'iogurte adoçado', quantity_g: 170 }],
      [{ food_name: 'frango grelhado', quantity_g: 170 }],
    ]) {
      test(`fresh identity or explicit calories require the official confirmed country: ${JSON.stringify(input)}`, async () => {
        const state = fixture()
        state.context.country = null
        state.context.country_confirmed = false
        const { result, failure } = await run(state, input)
        expect(result).toBeNull()
        expect(failure).toMatchObject({ status: 409, code: 'COUNTRY_REQUIRED' })
      })
    }
  })
}

import { prepareConfirmedMealMutation } from './confirmed-meal-mutation-preparation'
import { privateConfirmedMealVersion } from './confirmed-meal-read'

registerQuantityProvenanceRegressions(prepareConfirmedMealMutation, privateConfirmedMealVersion)
