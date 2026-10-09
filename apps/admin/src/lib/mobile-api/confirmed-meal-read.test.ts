import { describe, expect, it } from 'vitest'
import { loadConfirmedMealRecord, loadPrivateConfirmedMealState } from './confirmed-meal-read'
import {
  anchorID,
  auth,
  authID,
  fixture,
  now,
  owner,
  sdk,
  siblingID,
} from './testing/confirmed-meal-fixtures'

describe('confirmed meal official read', () => {
  it('reads the owned group using fresh timezone, preserves differing headers and hides private evidence', async () => {
    // Catches treating Auth ID as domain ID, cached Tokyo date, or grouping by category/time.
    const rows = fixture()
    const before = structuredClone(rows)
    const { client, requests } = sdk(rows)
    const result = await loadConfirmedMealRecord(client, auth, anchorID, now)
    expect(result).toMatchObject({
      record_id: anchorID,
      scope: 'group',
      item_ids: [anchorID, siblingID],
      timezone: 'Pacific/Honolulu',
      local_date: '2026-10-09',
      editable: true,
      day_closed: false,
      edit_block_reason: null,
      items: [
        {
          id: anchorID,
          food_name: 'iogurte natural',
          quantity_g: 85,
          kcal: 55,
          protein_g: 3,
          carbs_g: 4.5,
          fat_g: 2.75,
          source: 'product_label',
          meal_type: 'almoco',
          consumed_at: '2026-10-09T10:30:00.000Z',
        },
        {
          id: siblingID,
          food_name: 'frango grelhado',
          quantity_g: 120,
          source: 'canonical_exact',
          meal_type: 'jantar',
          consumed_at: '2026-10-09T19:00:00.000Z',
        },
      ],
    })
    expect(result.expected_version).toMatch(/^v1:[a-f0-9]{64}$/)
    expect(Object.keys(result).sort()).toEqual([
      'day_closed',
      'edit_block_reason',
      'editable',
      'expected_version',
      'item_ids',
      'items',
      'local_date',
      'record_id',
      'scope',
      'timezone',
    ])
    expect(Object.keys(result.items[0]).sort()).toEqual([
      'carbs_g',
      'consumed_at',
      'fat_g',
      'food_name',
      'id',
      'kcal',
      'meal_type',
      'protein_g',
      'quantity_g',
      'source',
    ])
    expect(JSON.stringify(result)).not.toMatch(
      /private-|raw_|image_url|auth_user_id|confidence|wpp/,
    )
    expect(rows).toEqual(before)
    expect(requests.every((request) => request.method === 'GET')).toBe(true)
    for (const request of requests) {
      const key = request.table === 'users' ? 'id' : 'user_id'
      expect(request.query.get(key)).toBe(`eq.${owner}`)
    }
  })

  it('treats a NULL origin as one explicit food, even with matching timestamps/category/name nearby', async () => {
    const rows = fixture()
    rows.meal_logs[0].raw_provider_message_id = null
    rows.meal_logs[1] = { ...rows.meal_logs[0], id: siblingID }
    const { client, requests } = sdk(rows)
    const result = await loadConfirmedMealRecord(client, auth, anchorID, now)
    expect(result.scope).toBe('item')
    expect(result.item_ids).toEqual([anchorID])
    expect(result.items).toHaveLength(1)
    expect(requests.filter((request) => request.table === 'meal_logs')).toHaveLength(1)
  })

  it.each([
    'missing',
    'other_owner',
  ] as const)('returns the same not-found for %s anchor', async (kind) => {
    const rows = fixture()
    if (kind === 'missing') rows.meal_logs.splice(0, 1)
    else rows.meal_logs[0].user_id = authID
    await expect(
      loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now),
    ).rejects.toMatchObject({ status: 404, code: 'MEAL_RECORD_NOT_FOUND' })
  })

  it('never adds another owner/snapshot/origin to the group', async () => {
    const rows = fixture()
    const meal = rows.meal_logs[0]
    rows.meal_logs.push(
      { ...meal, id: 'c1110000-0000-4000-8000-000000000006', user_id: authID },
      { ...meal, id: 'c1110000-0000-4000-8000-000000000007', snapshot_id: authID },
      {
        ...meal,
        id: 'c1110000-0000-4000-8000-000000000008',
        raw_provider_message_id: 'other-group',
      },
    )
    expect((await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)).item_ids).toEqual(
      [anchorID, siblingID],
    )
  })

  it.each([
    'closed',
    'past',
    'future',
    'consumed_mismatch',
  ] as const)('shows the record but blocks %s date', async (kind) => {
    const rows = fixture()
    if (kind === 'closed') rows.daily_snapshots[0].day_closed = true
    if (kind === 'past') rows.daily_snapshots[0].date = '2026-10-08'
    if (kind === 'future') rows.daily_snapshots[0].date = '2026-10-10'
    if (kind === 'consumed_mismatch') rows.meal_logs[1].consumed_at = '2026-10-09T00:30:00.000Z'
    const result = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    expect(result.editable).toBe(false)
    expect(result.edit_block_reason).toBe('MEAL_DAY_NOT_EDITABLE')
    expect(result.items).toHaveLength(2)
  })

  it.each([
    'users',
    'daily_snapshots',
    'meal_logs',
  ] as const)('maps %s read failure without leaking DB detail', async (table) => {
    await expect(
      loadConfirmedMealRecord(sdk(fixture(), table).client, auth, anchorID, now),
    ).rejects.toMatchObject({ status: 503, code: 'MEAL_READ_UNAVAILABLE' })
  })

  it.each([
    'null',
    'invalid',
  ] as const)('does not replace %s official timezone with cached timezone', async (kind) => {
    const rows = fixture()
    rows.users[0].timezone = kind === 'null' ? null : 'invalid/timezone'
    await expect(
      loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now),
    ).rejects.toMatchObject({ status: 409, code: 'MEAL_CONTEXT_CHANGED' })
  })

  it.each([
    'foreign_auth',
    'inactive',
  ] as const)('refuses %s current official identity', async (kind) => {
    const rows = fixture()
    if (kind === 'foreign_auth') rows.users[0].auth_user_id = owner
    else rows.users[0].status = 'blocked'
    await expect(
      loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now),
    ).rejects.toMatchObject({ status: 409, code: 'MEAL_CONTEXT_CHANGED' })
  })

  it('does not silently truncate a group above 30 foods', async () => {
    const rows = fixture()
    const original = rows.meal_logs[0]
    rows.meal_logs = Array.from({ length: 31 }, (_, index) => ({
      ...original,
      id:
        index === 0 ? anchorID : `c1110000-0000-4000-8000-${String(index + 100).padStart(12, '0')}`,
    }))
    const { client, requests } = sdk(rows)
    await expect(loadConfirmedMealRecord(client, auth, anchorID, now)).rejects.toMatchObject({
      status: 409,
      code: 'MEAL_GROUP_LIMIT_EXCEEDED',
    })
    expect(
      requests.find((request) => request.query.has('raw_provider_message_id'))?.query.get('limit'),
    ).toBe('31')
  })

  it('captures complete rows privately while public DTO preserves NULL macros/source without promoting them', async () => {
    const rows = fixture()
    rows.meal_logs[0].source = null
    rows.meal_logs[0].kcal = null
    const state = await loadPrivateConfirmedMealState(sdk(rows).client, auth, anchorID)
    expect(state.items).toEqual(rows.meal_logs)
    expect(state.snapshot).toEqual(rows.daily_snapshots[0])
    expect(state.context).toEqual({
      id: owner,
      auth_user_id: authID,
      country: 'BR',
      country_confirmed: true,
      timezone: 'Pacific/Honolulu',
      status: 'active',
      wpp: null,
      updated_at: now.toISOString(),
    })
    const result = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    expect(result.items[0]).toMatchObject({ source: null, kcal: null })
  })

  it('keeps the opaque version stable when row return order changes', async () => {
    const rows = fixture()
    const first = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    rows.meal_logs.reverse()
    const second = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    expect(second.expected_version).toBe(first.expected_version)
    expect(second.item_ids).toEqual([anchorID, siblingID])
  })

  it.each([
    'snapshot_water',
    'snapshot_target',
    'snapshot_training',
    'snapshot_progress',
    'sibling_macros',
    'sibling_header',
    'sibling_private_origin',
    'source',
    'confidence',
    'country',
    'country_confirmed',
    'timezone',
    'wpp',
    'context_revision',
  ] as const)('invalidates the review version when %s changes', async (field) => {
    const rows = fixture()
    const first = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    switch (field) {
      case 'snapshot_water':
        rows.daily_snapshots[0].water_consumed_ml++
        break
      case 'snapshot_target':
        rows.daily_snapshots[0].calories_target = 2000
        break
      case 'snapshot_training':
        rows.daily_snapshots[0].training_done = false
        break
      case 'snapshot_progress':
        rows.daily_snapshots[0].xp_earned++
        break
      case 'sibling_macros':
        rows.meal_logs[1].protein_g = 21
        break
      case 'sibling_header':
        rows.meal_logs[1].meal_type = 'lanche'
        break
      case 'sibling_private_origin':
        rows.meal_logs[1].raw_message_id = 'different-private-origin'
        break
      case 'source':
        rows.meal_logs[0].source = null
        break
      case 'confidence':
        rows.meal_logs[0].confidence = 0.92
        break
      case 'country':
        rows.users[0].country = 'US'
        break
      case 'country_confirmed':
        rows.users[0].country_confirmed = false
        break
      case 'timezone':
        rows.users[0].timezone = 'Pacific/Tahiti'
        break
      case 'wpp':
        rows.users[0].wpp = 'synthetic-legacy-binding'
        break
      case 'context_revision':
        rows.users[0].updated_at = '2026-10-09T20:00:00.001Z'
        break
    }
    const second = await loadConfirmedMealRecord(sdk(rows).client, auth, anchorID, now)
    expect(second.expected_version).not.toBe(first.expected_version)
  })
})
