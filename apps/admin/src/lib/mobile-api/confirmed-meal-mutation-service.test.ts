import { describe, expect, it } from 'vitest'
import {
  type ConfirmedMealCommand,
  confirmedMealCommandIdentity,
} from './confirmed-meal-mutation-preparation'
import { mutateConfirmedMeal } from './confirmed-meal-mutation-service'
import {
  loadConfirmedMealRecord,
  loadPrivateConfirmedMealState,
  privateConfirmedMealVersion,
} from './confirmed-meal-read'
import {
  anchorID,
  auth,
  fixture,
  now,
  owner,
  sdk,
  siblingID,
  snapshotID,
} from './testing/confirmed-meal-fixtures'

const replacementID = 'c1110000-0000-4000-8000-000000000010'
function body() {
  return {
    data: {
      record_id: anchorID,
      operation: 'updated',
      removed_item_ids: [anchorID],
      new_item_ids: [replacementID],
      next_record_id: replacementID,
      snapshot: {
        id: snapshotID,
        date: '2026-10-09',
        calories_consumed: 210,
        protein_g: 26,
        carbs_g: 9,
        fat_g: 7.5,
        daily_balance: -1790,
      },
    },
    meta: { api_version: 'v1', request_id: 'old-request-id' },
  }
}

async function setup() {
  const rows = fixture()
  const state = await loadPrivateConfirmedMealState(sdk(rows).client, auth, anchorID)
  const command: ConfirmedMealCommand = {
    method: 'PATCH',
    body: {
      expected_version: privateConfirmedMealVersion(state),
      item_ids: [anchorID],
      items: [{ food_name: 'iogurte natural', quantity_g: 170 }],
    },
  }
  const context = (client: ReturnType<typeof sdk>['client']) => ({
    supabase: client,
    auth,
    requestId: 'current-request-id',
    request: new Request(`https://app.invalid/api/mobile/v1/meal-records/${anchorID}`, {
      method: 'PATCH',
      headers: { 'Idempotency-Key': 'synthetic-command-key' },
    }),
  })
  return { rows, state, command, context }
}

describe('confirmed meal mutation orchestration', () => {
  it.each([
    'PATCH',
    'DELETE',
  ] as const)('refuses %s of the current anchor when its Honolulu group contains a previous-day sibling', async (method) => {
    const { rows, context } = await setup()
    // Exact review scenario: at20Z anchor10:30Z is09October in Honolulu; sibling00:30Z is08October.
    rows.meal_logs[1].consumed_at = '2026-10-09T00:30:00.000Z'
    const before = structuredClone(rows)
    const official =
      method === 'PATCH'
        ? body()
        : {
            ...body(),
            data: {
              ...body().data,
              operation: 'deleted',
              new_item_ids: [],
              next_record_id: siblingID,
            },
          }
    const boundary = sdk(rows, undefined, () =>
      Response.json({ action: 'completed', response_status: 200, response_body: official }),
    )
    const read = await loadConfirmedMealRecord(boundary.client, auth, anchorID, now)
    expect(read).toMatchObject({ editable: false, edit_block_reason: 'MEAL_DAY_NOT_EDITABLE' })
    const state = await loadPrivateConfirmedMealState(boundary.client, auth, anchorID)
    const selection = { expected_version: privateConfirmedMealVersion(state), item_ids: [anchorID] }
    const command: ConfirmedMealCommand =
      method === 'PATCH'
        ? {
            method,
            body: { ...selection, items: [{ food_name: 'iogurte natural', quantity_g: 170 }] },
          }
        : { method, body: selection }
    await expect(
      mutateConfirmedMeal(context(boundary.client), anchorID, command, now),
    ).rejects.toMatchObject({ status: 409, code: 'MEAL_DAY_NOT_EDITABLE' })
    expect(boundary.requests.every((request) => request.method === 'GET')).toBe(true)
    expect(rows).toEqual(before)
  })

  it.each([
    'id',
    'date',
  ] as const)('refuses a fresh completed receipt with a foreign snapshot %s', async (field) => {
    const { rows, command, context } = await setup()
    const foreign = body()
    if (field === 'id') foreign.data.snapshot.id = replacementID
    else foreign.data.snapshot.date = '2026-10-08'
    const boundary = sdk(rows, undefined, () =>
      Response.json({ action: 'completed', response_status: 200, response_body: foreign }),
    )
    await expect(
      mutateConfirmedMeal(context(boundary.client), anchorID, command, now),
    ).rejects.toMatchObject({ status: 503, code: 'MEAL_RECEIPT_INVALID' })
    expect(boundary.requests.filter((request) => request.method === 'POST')).toHaveLength(1)
  })

  it.each([
    replacementID,
    null,
  ])('refuses a fresh DELETE receipt that loses the known surviving sibling: next=%s', async (next) => {
    const { rows, state, context } = await setup()
    const command: ConfirmedMealCommand = {
      method: 'DELETE',
      body: { expected_version: privateConfirmedMealVersion(state), item_ids: [anchorID] },
    }
    const deleted = {
      ...body(),
      data: { ...body().data, operation: 'deleted', new_item_ids: [], next_record_id: next },
    }
    const boundary = sdk(rows, undefined, () =>
      Response.json({ action: 'completed', response_status: 200, response_body: deleted }),
    )
    await expect(
      mutateConfirmedMeal(context(boundary.client), anchorID, command, now),
    ).rejects.toMatchObject({ status: 503, code: 'MEAL_RECEIPT_INVALID' })
    expect(boundary.requests.filter((request) => request.method === 'POST')).toHaveLength(1)
  })

  it('accepts a fresh DELETE receipt bound to the known snapshot and surviving sibling', async () => {
    const { rows, state, context } = await setup()
    const command: ConfirmedMealCommand = {
      method: 'DELETE',
      body: { expected_version: privateConfirmedMealVersion(state), item_ids: [anchorID] },
    }
    const deleted = {
      ...body(),
      data: { ...body().data, operation: 'deleted', new_item_ids: [], next_record_id: siblingID },
    }
    const boundary = sdk(rows, undefined, () =>
      Response.json({ action: 'completed', response_status: 200, response_body: deleted }),
    )
    const response = await mutateConfirmedMeal(context(boundary.client), anchorID, command, now)
    expect(response.status).toBe(200)
    expect((await response.json()).data.next_record_id).toBe(siblingID)
  })

  it('keeps a concurrently replayed receipt independent of the freshly read snapshot date', async () => {
    const { rows, command, context } = await setup()
    const original = body()
    original.data.snapshot.date = '2026-10-08'
    const boundary = sdk(rows, undefined, () =>
      Response.json({ action: 'replay', response_status: 200, response_body: original }),
    )
    const response = await mutateConfirmedMeal(context(boundary.client), anchorID, command, now)
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect((await response.json()).data).toEqual(original.data)
  })

  it('uses one transactional RPC, official private context and quantity-only proof; emits official totals', async () => {
    const { rows, state, command, context } = await setup()
    const { client, requests } = sdk(rows, undefined, () =>
      Response.json({ action: 'completed', response_status: 200, response_body: body() }),
    )
    const response = await mutateConfirmedMeal(context(client), anchorID, command, now)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      ...body(),
      meta: { api_version: 'v1', request_id: 'current-request-id' },
    })
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
    const mutation = requests.filter((request) => request.method === 'POST')
    expect(mutation).toHaveLength(1)
    expect(mutation[0].body).toMatchObject({
      p_user_id: owner,
      p_record_id: anchorID,
      p_item_ids: [anchorID],
      p_expected_state: state,
      p_expected_version: command.body.expected_version,
      p_nutrition_mode: 'quantity_only',
      p_quantity_change: { quantity_g: 170 },
      p_calculated_items: [
        {
          food_name: 'iogurte natural',
          quantity_g: 170,
          kcal: 110,
          protein_g: 6,
          carbs_g: 9,
          fat_g: 5.5,
          source: 'product_label',
          confidence: 0.93,
          food_db_id: null,
        },
      ],
    })
    expect(JSON.stringify(mutation[0].body)).not.toContain('synthetic-never-sent')
  })

  it('replays completed expired receipt before reading a missing target or changed context', async () => {
    const { rows, command, context } = await setup()
    const identity = confirmedMealCommandIdentity(anchorID, command)
    rows.mobile_api_idempotency.push({
      id: replacementID,
      user_id: owner,
      idempotency_key: 'synthetic-command-key',
      request_method: identity.method,
      request_route: identity.route,
      request_hash: identity.requestHash,
      state: 'completed',
      response_status: 200,
      response_body: body(),
      attempt_count: 1,
      created_at: '2026-10-01T00:00:00Z',
      updated_at: '2026-10-01T00:00:00Z',
      expires_at: '2026-10-02T00:00:00Z',
    })
    rows.meal_logs = []
    rows.users[0].country_confirmed = false
    const { client, requests } = sdk(rows)
    const response = await mutateConfirmedMeal(context(client), anchorID, command, now)
    expect(await response.json()).toEqual({
      ...body(),
      meta: { api_version: 'v1', request_id: 'current-request-id' },
    })
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect(requests.map((request) => request.table)).toEqual(['mobile_api_idempotency'])
  })

  it('preserves the operation error and never mutates when official version changed', async () => {
    const { rows, command, context } = await setup()
    rows.daily_snapshots[0].water_consumed_ml++
    const { client, requests } = sdk(rows)
    await expect(
      mutateConfirmedMeal(context(client), anchorID, command, now),
    ).rejects.toMatchObject({ status: 409, code: 'MEAL_VERSION_CONFLICT' })
    expect(requests.every((request) => request.method === 'GET')).toBe(true)
    expect(requests.filter((request) => request.table === 'mobile_api_idempotency')).toHaveLength(2)
  })

  it('picks up a concurrently completed owned receipt once after preparation refusal', async () => {
    const { rows, command, context } = await setup()
    rows.daily_snapshots[0].water_consumed_ml++
    const identity = confirmedMealCommandIdentity(anchorID, command)
    // Publish at the external read boundary between preparation and the bounded recheck.
    let reads = 0
    const base = sdk(rows, undefined, undefined, (table) => {
      if (table === 'mobile_api_idempotency' && ++reads === 2) {
        rows.mobile_api_idempotency.push({
          id: replacementID,
          user_id: owner,
          idempotency_key: 'synthetic-command-key',
          request_method: identity.method,
          request_route: identity.route,
          request_hash: identity.requestHash,
          state: 'completed',
          response_status: 200,
          response_body: body(),
          attempt_count: 1,
          created_at: now.toISOString(),
          updated_at: now.toISOString(),
          expires_at: now.toISOString(),
        })
      }
    })
    const response = await mutateConfirmedMeal(context(base.client), anchorID, command, now)
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect((await response.json()).data.new_item_ids).toEqual([replacementID])
    expect(reads).toBe(2)
  })

  it.each([
    'conflict',
    'in_progress',
  ] as const)('maps transactional %s without resending', async (action) => {
    const { rows, command, context } = await setup()
    const { client, requests } = sdk(rows, undefined, () => Response.json({ action }))
    await expect(
      mutateConfirmedMeal(context(client), anchorID, command, now),
    ).rejects.toMatchObject({
      status: 409,
      code: action === 'conflict' ? 'IDEMPOTENCY_KEY_CONFLICT' : 'IDEMPOTENCY_REQUEST_IN_PROGRESS',
    })
    expect(requests.filter((request) => request.method === 'POST')).toHaveLength(1)
  })

  it.each([
    '40001',
    '55P03',
    '23514',
    'P0001',
  ] as const)('maps SQL %s safely without claim release or a second POST', async (code) => {
    const { rows, command, context } = await setup()
    const { client, requests } = sdk(rows, undefined, () =>
      Response.json({ code, message: 'private SQL detail' }, { status: 400 }),
    )
    await expect(
      mutateConfirmedMeal(context(client), anchorID, command, now),
    ).rejects.toMatchObject({
      code:
        code === '40001'
          ? 'MEAL_VERSION_CONFLICT'
          : code === '55P03'
            ? 'IDEMPOTENCY_REQUEST_IN_PROGRESS'
            : 'MEAL_MUTATION_UNAVAILABLE',
    })
    expect(requests.filter((request) => request.method === 'POST')).toHaveLength(1)
  })
})
