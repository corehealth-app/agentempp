import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const boundary = vi.hoisted(() => ({
  handlers: [] as Array<(context: MobileRouteContext) => Promise<Response>>,
  providerConstructors: vi.fn(),
}))
// Inject authenticated context at the route wrapper only; JWT is not under test.
vi.mock('@/lib/mobile-api/route', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
  createMobileRoute: (handler: (context: MobileRouteContext) => Promise<Response>) => {
    boundary.handlers.push(handler)
    return handler
  },
}))
// Cost/network tripwire only. This constructor must NEVER be reached by C7.
vi.mock('@mpp/providers', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@mpp/providers')>()),
  OpenRouterLLM: class {
    constructor() {
      boundary.providerConstructors()
      throw new Error('C7 deterministic status must not construct a provider')
    }
  },
}))
// Actual composition: handler, idempotency, factory, agent, Today reader, service,
// phrase selector and Supabase adapters are all real. Only their DB is synthetic.
import '@/app/api/mobile/v1/flow/chat/route'

const OWNER = '00000000-0000-0000-0000-00000000c501'
const KEY = 'c5-event-0001'
const NOW = new Date('2026-10-08T18:00:00.000Z')
const QUESTION = 'Como está meu dia?'
const PHRASE = 'Consistência vale mais do que perfeição.'
type Row = Record<string, unknown>
type Result = { data: unknown; error: null; count?: number }

function field(row: Row, name: string): unknown {
  const [column, jsonKey] = name.split('->>')
  return jsonKey ? (row[column] as Row | null)?.[jsonKey] : row[column]
}

/** Supabase boundary model, not SQL/durability/locking proof. Conditions apply. */
class Query {
  columns = '*'
  head = false
  predicates: Array<(row: Row) => boolean> = []
  max = Number.POSITIVE_INFINITY
  mode: 'select' | 'insert' | 'update' = 'select'
  values: Row | null = null
  constructor(
    readonly db: SyntheticDB,
    readonly table: string,
  ) {}
  select(columns: string, options?: { head?: boolean }) {
    this.columns = columns
    this.head = options?.head ?? false
    return this
  }
  eq(column: string, value: unknown) {
    this.predicates.push((r) => field(r, column) === value)
    return this
  }
  is(column: string, value: unknown) {
    this.predicates.push((r) => (field(r, column) ?? null) === value)
    return this
  }
  gte(column: string, value: string) {
    this.predicates.push((r) => String(field(r, column)) >= value)
    return this
  }
  lte(column: string, value: string) {
    this.predicates.push((r) => String(field(r, column)) <= value)
    return this
  }
  gt(column: string, value: string) {
    this.predicates.push((r) => String(field(r, column)) > value)
    return this
  }
  lt(column: string, value: string) {
    this.predicates.push((r) => String(field(r, column)) < value)
    return this
  }
  in(column: string, values: unknown[]) {
    this.predicates.push((r) => values.includes(field(r, column)))
    return this
  }
  like(column: string, value: string) {
    if (!value.endsWith('%')) throw new Error('Only prefix LIKE is supported by this fixture')
    this.predicates.push((r) => String(field(r, column)).startsWith(value.slice(0, -1)))
    return this
  }
  filter(column: string, operator: string, value: unknown) {
    if (operator !== 'eq') throw new Error('Unexpected fixture filter')
    return this.eq(column, value)
  }
  order() {
    return this
  }
  limit(max: number) {
    this.max = max
    return this
  }
  insert(values: Row) {
    this.mode = 'insert'
    this.values = values
    return this
  }
  update(values: Row) {
    this.mode = 'update'
    this.values = values
    return this
  }
  project(row: Row): Row {
    if (this.columns === '*' || this.columns.includes('(')) return structuredClone(row)
    return Object.fromEntries(this.columns.split(',').map((key) => [key.trim(), row[key.trim()]]))
  }
  async result(single = false): Promise<Result> {
    this.db.queries.push({ table: this.table, columns: this.columns, mode: this.mode })
    if (this.mode !== 'select' && this.table !== 'messages')
      throw new Error('Unexpected fixture table write')
    const source = this.db.rows[this.table]
    if (!source) throw new Error(`Unexpected fixture table ${this.table}`)
    let selected: Row[]
    if (this.mode === 'insert') {
      const row: Row = { id: this.db.nextID(), ...structuredClone(this.values) }
      if (source.some((r) => r.provider_message_id === row.provider_message_id))
        throw new Error('Duplicate synthetic provider id')
      source.push(row)
      selected = [row]
    } else {
      selected = source.filter((r) => this.predicates.every((p) => p(r)))
      if (this.mode === 'update')
        for (const row of selected) Object.assign(row, structuredClone(this.values))
    }
    const projected = selected.slice(0, this.max).map((row) => this.project(row))
    return {
      data: this.head ? null : single ? (projected[0] ?? null) : projected,
      error: null,
      count: selected.length,
    }
  }
  maybeSingle() {
    return this.result(true)
  }
  single() {
    return this.result(true)
  }
  // biome-ignore lint/suspicious/noThenProperty: represents the external Supabase query boundary.
  then<TResult1 = Result, TResult2 = never>(
    resolve?: ((value: Result) => TResult1 | PromiseLike<TResult1>) | null,
    reject?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ) {
    return this.result().then(resolve, reject)
  }
}

class SyntheticDB {
  sequence = 0
  queries: Array<{ table: string; columns: string; mode: string }> = []
  rpcs: string[] = []
  cursor: Row | null = null
  cache: { status: number; body: unknown } | null = null
  readonly rows: Record<string, Row[]> = {
    users: [
      {
        id: OWNER,
        name: 'Pessoa sintética',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        metadata: null,
        country: 'BR',
        country_confirmed: true,
        summary: null,
        last_active_at: null,
      },
    ],
    user_profiles: [
      {
        user_id: OWNER,
        sex: 'masculino',
        birth_date: '1990-01-01',
        height_cm: 180,
        weight_kg: 80,
        body_fat_percent: 20,
        activity_level: 'sedentario',
        training_frequency: 3,
        water_intake: 'moderado',
        hunger_level: 'moderada',
        current_protocol: 'manutencao',
        goal_type: null,
        goal_value: null,
        deficit_level: 500,
      },
    ],
    // Explicit official empty day; targets are persisted values, never recomputed here.
    daily_snapshots: [
      {
        id: '00000000-0000-0000-0000-00000000d701',
        user_id: OWNER,
        date: '2026-10-08',
        calories_consumed: 0,
        calories_target: 2400,
        protein_g: 0,
        protein_target: 150,
        carbs_g: 0,
        fat_g: 0,
        exercise_calories: 0,
        water_consumed_ml: 0,
        current_protocol: 'manutencao',
        day_closed: false,
        day_status: null,
        updated_at: '2026-10-08T17:00:00Z',
        meal_logs: [],
        workout_logs: [],
      },
    ],
    user_progress: [],
    pending_registrations: [],
    notification_preferences: [],
    product_events: [],
    global_config: [],
    messages: [],
    plan_drafts: [],
    subscriptions: [],
  }
  nextID() {
    return `00000000-0000-0000-0000-${(++this.sequence).toString(16).padStart(12, '0')}`
  }
  from(table: string) {
    return new Query(this, table)
  }
  statusReads() {
    return this.queries.filter(
      (q) =>
        !['messages', 'plan_drafts'].includes(q.table) &&
        !(q.table === 'user_profiles' && q.columns === 'current_protocol'),
    ).length
  }
  projectionReads() {
    return this.queries.filter(
      (q) => q.table === 'user_profiles' && q.columns === 'current_protocol',
    ).length
  }
  async rpc(name: string, p: Row): Promise<{ data: unknown; error: null }> {
    this.rpcs.push(name)
    if (p.p_user_id !== OWNER) throw new Error('Unexpected synthetic RPC owner')
    if (name === 'claim_mobile_api_request') {
      expect(p).toMatchObject({
        p_idempotency_key: KEY,
        p_request_method: 'POST',
        p_request_route: '/api/mobile/v1/flow/chat',
      })
      return {
        data: this.cache
          ? {
              action: 'replay',
              response_status: this.cache.status,
              response_body: structuredClone(this.cache.body),
            }
          : { action: 'claimed', claim_id: '00000000-0000-0000-0000-00000000c701' },
        error: null,
      }
    }
    if (name === 'complete_mobile_api_request') {
      expect(p.p_claim_id).toBe('00000000-0000-0000-0000-00000000c701')
      this.cache = {
        status: p.p_response_status as number,
        body: structuredClone(p.p_response_body),
      }
      return { data: true, error: null }
    }
    if (name === 'list_mobile_routine_items') {
      expect(p.p_now).toBe(NOW.toISOString())
      return { data: { local_date: '2026-10-08', items: [] }, error: null }
    }
    if (name === 'read_flow_phrase_cursor') {
      return {
        data: { anchor_assistant_id: null, cursor_revision: '0', cursor: null },
        error: null,
      }
    }
    if (name === 'commit_flow_phrase_reply') {
      const inbound = this.rows.messages.find((r) => r.id === p.p_expected_inbound_id)
      expect(inbound).toMatchObject({
        user_id: OWNER,
        content: QUESTION,
        delivery_status: 'processing',
      })
      expect(inbound?.raw_payload).toMatchObject({
        request_id: p.p_expected_request_id,
        attempt_started_at: p.p_expected_attempt_started_at,
      })
      expect(p).toMatchObject({
        p_event_key: `mobile_flow/${OWNER}/${KEY}`,
        p_expected_cursor_revision: '0',
        p_expected_anchor_assistant_id: null,
        p_expected_cursor: null,
      })
      expect(this.cursor).toBeNull()
      const raw_payload = {
        request_id: p.p_expected_request_id,
        conversation_id: 'flow',
        flow_phrase_v1: {
          schema: 'flow.phrase-store.v1',
          cursor_revision: '1',
          previous_anchor_assistant_id: null,
          cursor: p.p_next_cursor,
          receipt: p.p_receipt,
        },
      }
      const row = {
        id: this.nextID(),
        user_id: OWNER,
        provider: 'mobile_flow',
        provider_message_id: p.p_assistant_provider_message_id,
        direction: 'out',
        role: 'assistant',
        content_type: 'text',
        content: p.p_content,
        delivery_status: 'completed',
        raw_payload,
        created_at: p.p_created_at,
      }
      this.rows.messages.push(row)
      if (!inbound) throw new Error('Synthetic inbound absent')
      inbound.delivery_status = 'completed'
      this.cursor = structuredClone(p.p_next_cursor as Row)
      return {
        data: {
          action: 'committed',
          message: Object.fromEntries(
            ['id', 'direction', 'content', 'delivery_status', 'raw_payload', 'created_at'].map(
              (key) => [key, row[key as keyof typeof row]],
            ),
          ),
        },
        error: null,
      }
    }
    throw new Error(`Unexpected fixture RPC ${name}`)
  }
  client() {
    return this as unknown as ServiceClient
  }
}

function context(db: SyntheticDB, requestId: string): MobileRouteContext {
  return {
    request: new Request('https://performe.test/api/mobile/v1/flow/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'Idempotency-Key': KEY },
      body: JSON.stringify({ text: QUESTION }),
    }),
    requestId,
    supabase: db.client(),
    auth: {
      accessToken: 'synthetic-not-a-token',
      authUserId: OWNER,
      userId: OWNER,
      identity: { id: OWNER, email: 'c7@example.invalid', emailConfirmedAt: NOW.toISOString() },
      patient: {
        id: OWNER,
        authUserId: OWNER,
        email: 'c7@example.invalid',
        name: 'Pessoa sintética',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('SUBSCRIPTION_GATE', 'off')
  vi.stubEnv('OPENROUTER_API_KEY', 'synthetic-tripwire-not-a-key')
  vi.stubGlobal(
    'fetch',
    vi.fn(() => {
      throw new Error('No network is permitted in C7 fixture')
    }),
  )
  vi.spyOn(console, 'info').mockImplementation(() => {})
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('C7 exact authenticated route status and stable incentive', () => {
  it('answers Como está meu dia? on an empty day and replays the same official phrase without re-reading status or rotating', async () => {
    const db = new SyntheticDB()
    const post = boundary.handlers[1]
    expect(boundary.handlers).toHaveLength(2)
    const first = await post(context(db, 'c7-original-request'))
    expect(first.status).toBe(201)
    const original = (await first.json()).data.message
    expect(original.content).toContain(
      'Status do dia: 2026-10-08\nAinda não há refeição ou treino confirmado neste dia.',
    )
    expect(original.content).toContain('Consumido: 0 / 2.400 kcal (0%).')
    expect(original.content).toContain('Restam: 2.400 kcal para comida.')
    expect(original.content).toContain('Proteína: 0 / 150 g (0%). Faltam 150 g.')
    expect(original.content).toContain('Balanço do dia (parcial): Déficit de 2.400 kcal.')
    expect(original.content.endsWith(`\n\n${PHRASE}`)).toBe(true)
    expect(original.content.split(PHRASE)).toHaveLength(2)
    expect(db.cursor).toMatchObject({ userId: OWNER, ordinal: 1 })
    expect(db.rpcs.filter((n) => n === 'read_flow_phrase_cursor')).toHaveLength(1)
    expect(db.rpcs.filter((n) => n === 'commit_flow_phrase_reply')).toHaveLength(1)
    expect(db.rows.messages).toHaveLength(2)
    const officialReads = db.statusReads()
    expect(officialReads).toBeGreaterThan(0)
    expect(db.projectionReads()).toBe(1)
    const cursor = structuredClone(db.cursor)
    const routineReads = db.rpcs.filter((n) => n === 'list_mobile_routine_items').length
    // Two item types, then the same two reads in the official consistency fence.
    expect(routineReads).toBe(4)

    const cachedReplay = await post(context(db, 'c7-http-replay-request'))
    expect(cachedReplay.status).toBe(201)
    expect(cachedReplay.headers.get('Idempotency-Replayed')).toBe('true')
    expect((await cachedReplay.json()).data.message).toEqual(original)
    expect(db.statusReads()).toBe(officialReads)
    expect(db.projectionReads()).toBe(2)

    // Remove only the synthetic HTTP-cache entry. Real service replay must now
    // find the persisted event, not render/select/commit a second status.
    db.cache = null
    const durableReplay = await post(context(db, 'c7-durable-replay-request'))
    expect(durableReplay.status).toBe(201)
    expect((await durableReplay.json()).data.message).toEqual(original)
    expect(db.statusReads()).toBe(officialReads)
    // Real handler intentionally reads current_protocol once per response,
    // after idempotency. This is presentation authority, not a status refresh.
    expect(db.projectionReads()).toBe(3)
    expect(db.rpcs.filter((n) => n === 'list_mobile_routine_items')).toHaveLength(routineReads)
    expect(db.rpcs.filter((n) => n === 'read_flow_phrase_cursor')).toHaveLength(1)
    expect(db.rpcs.filter((n) => n === 'commit_flow_phrase_reply')).toHaveLength(1)
    expect(db.cursor).toEqual(cursor)
    expect(db.rows.messages).toHaveLength(2)
    expect(boundary.providerConstructors).not.toHaveBeenCalled()
    expect(fetch).not.toHaveBeenCalled()
  })
})
