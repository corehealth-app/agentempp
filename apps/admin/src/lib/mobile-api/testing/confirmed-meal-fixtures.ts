import type { Database, Tables } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import type { MobileAuthContext } from '../auth'

// Synthetic full persisted rows. Domain user ID is deliberately NOT the Auth ID.
export const owner = 'c1110000-0000-4000-8000-000000000001'
export const authID = 'c1110000-0000-4000-8000-000000000002'
export const anchorID = 'c1110000-0000-4000-8000-000000000003'
export const siblingID = 'c1110000-0000-4000-8000-000000000004'
export const snapshotID = 'c1110000-0000-4000-8000-000000000005'
export const now = new Date('2026-10-09T20:00:00.000Z')
export const auth: MobileAuthContext = {
  accessToken: 'synthetic-never-sent',
  authUserId: authID,
  userId: owner,
  identity: { id: authID, email: 'qa@example.invalid', emailConfirmedAt: now.toISOString() },
  patient: {
    id: owner,
    authUserId: authID,
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'Asia/Tokyo',
    country: 'US',
    countryConfirmed: false,
    status: 'active',
  },
}

export function fixture() {
  const user: Tables<'users'> = {
    id: owner,
    auth_user_id: authID,
    status: 'active',
    timezone: 'Pacific/Honolulu',
    country: 'BR',
    country_confirmed: true,
    wpp: null,
    updated_at: now.toISOString(),
    created_at: now.toISOString(),
    email: null,
    flow_phrase_cursor_revision: 0,
    flow_shared_phrase_cursor: null,
    flow_shared_phrase_legacy_revision: 0,
    flow_shared_phrase_revision: 0,
    name: null,
    locale: 'pt-BR',
    admin_notes: null,
    country_detected_from_wpp: null,
    last_active_at: null,
    metadata: {},
    summary: null,
    summary_updated_at: null,
    tags: [],
  }
  const snapshot: Tables<'daily_snapshots'> = {
    id: snapshotID,
    user_id: owner,
    date: '2026-10-09',
    day_closed: false,
    day_status: 'open',
    calories_consumed: 155,
    calories_target: 1900,
    protein_g: 23,
    carbs_g: 4.5,
    fat_g: 4.75,
    daily_balance: -1845,
    exercise_calories: 100,
    protein_target: 120,
    closed_at: null,
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
    current_protocol: 'recomposicao',
    deficit_accumulated: 321,
    gap_reminder_sent_at: null,
    sleep_hours: 7,
    steps: 1234,
    training_done: true,
    water_consumed_ml: 1100,
    xp_earned: 40,
  }
  const meal: Tables<'meal_logs'> = {
    id: anchorID,
    user_id: owner,
    snapshot_id: snapshotID,
    food_name: 'iogurte natural',
    quantity_g: 85,
    kcal: 55,
    protein_g: 3,
    carbs_g: 4.5,
    fat_g: 2.75,
    source: 'product_label',
    confidence: 0.93,
    food_db_id: null,
    meal_type: 'almoco',
    consumed_at: '2026-10-09T10:30:00.000Z',
    created_at: now.toISOString(),
    image_url: 'private-image-origin',
    raw_message_id: 'private-message',
    raw_provider_message_id: 'private-group',
  }
  const sibling: Tables<'meal_logs'> = {
    ...meal,
    id: siblingID,
    food_name: 'frango grelhado',
    quantity_g: 120,
    kcal: 100,
    protein_g: 20,
    carbs_g: 0,
    fat_g: 2,
    source: 'canonical_exact',
    food_db_id: 42,
    meal_type: 'jantar',
    consumed_at: '2026-10-09T19:00:00.000Z',
    image_url: null,
    raw_message_id: null,
  }
  return {
    users: [user],
    daily_snapshots: [snapshot],
    meal_logs: [meal, sibling],
    mobile_api_idempotency: [] as Tables<'mobile_api_idempotency'>[],
  }
}

type Fixture = ReturnType<typeof fixture>

// The real Supabase query builder talks only to this bounded synthetic Data API.
// No auth/bootstrap, network or nutritional operation is replaced by a service mock.
export function sdk(
  rows: Fixture,
  failTable?: keyof Fixture,
  rpcResponse?: (body: Record<string, unknown>) => Response | Promise<Response>,
  onRead?: (table: string) => void,
) {
  const requests: { table: string; query: URLSearchParams; method: string; body?: unknown }[] = []
  const client = createClient<Database>('https://c11-read.invalid', 'synthetic-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const url = new URL(String(input))
        const table = url.pathname.split('/').at(-1) ?? ''
        const method = init?.method ?? 'GET'
        requests.push({ table, query: url.searchParams, method })
        onRead?.(table)
        if (
          url.origin === 'https://c11-read.invalid' &&
          url.pathname === '/rest/v1/rpc/mutate_mobile_confirmed_meal' &&
          method === 'POST' &&
          rpcResponse
        ) {
          const body = JSON.parse(String(init?.body)) as Record<string, unknown>
          requests[requests.length - 1].body = body
          return rpcResponse(body)
        }
        if (url.origin !== 'https://c11-read.invalid' || method !== 'GET')
          throw new Error('Read may not send a mutation or real network request')
        if (table === failTable)
          return Response.json({ code: 'P0001', message: 'private-detail' }, { status: 500 })
        const source = rows[table as keyof Fixture]
        if (!source) throw new Error(`Unexpected table ${table}`)
        let selected: Record<string, unknown>[] = source.map((row) => ({ ...row }))
        for (const [key, value] of url.searchParams) {
          if (value.startsWith('eq.'))
            selected = selected.filter((row) => String(row[key]) === value.slice(3))
        }
        const order = url.searchParams.get('order')
        if (order === 'id.asc') selected.sort((a, b) => String(a.id).localeCompare(String(b.id)))
        const limit = url.searchParams.get('limit')
        if (limit) selected = selected.slice(0, Number(limit))
        const projection = url.searchParams.get('select')
        if (projection && projection !== '*')
          selected = selected.map((row) =>
            Object.fromEntries(projection.split(',').map((key) => [key, row[key]])),
          )
        return Response.json(selected)
      },
    },
  })
  return { client, requests }
}
