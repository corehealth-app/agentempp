import type { Protocol } from '@mpp/core'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { loadOfficialDailyState } from '../daily-state-service.js'
import { type FlowDayStatusContext, loadFlowDayStatusContext } from '../flow-day-status-context.js'
import {
  type AuthenticatedPipelineDeps,
  type PipelineDeps,
  processAuthenticatedMessage,
} from '../pipeline.js'
import { getLocalDateString } from '../timezone-utils.js'

type Row = Record<string, unknown>
type StatusTable =
  | 'users'
  | 'user_profiles'
  | 'daily_snapshots'
  | 'user_progress'
  | 'pending_registrations'
  | 'notification_preferences'
  | 'product_events'
  | 'global_config'
  | 'messages'
  | 'subscriptions'
type Read = { table: string; columns: string; filters: Array<[string, unknown]> }
type Result = { data: unknown; error: { message: string } | null }

/** External DB boundary only: every equality/date condition is actually applied. */
class Query {
  columns = ''
  filters: Array<[string, unknown]> = []
  predicates: Array<(row: Row) => boolean> = []
  maxRows: number | undefined
  constructor(
    readonly table: string,
    readonly db: StatusDb,
  ) {}
  select(columns: string) {
    this.columns = columns
    return this
  }
  eq(column: string, value: unknown) {
    this.filters.push([column, value])
    this.predicates.push((row) => row[column] === value)
    return this
  }
  gte(column: string, value: string) {
    this.predicates.push((row) => String(row[column]) >= value)
    return this
  }
  lte(column: string, value: string) {
    this.predicates.push((row) => String(row[column]) <= value)
    return this
  }
  lt(column: string, value: string) {
    this.predicates.push((row) => String(row[column]) < value)
    return this
  }
  gt(column: string, value: string) {
    this.predicates.push((row) => String(row[column]) > value)
    return this
  }
  like(column: string, value: string) {
    if (!value.endsWith('%')) throw new Error('Only prefix fixtures are supported')
    this.predicates.push((row) => String(row[column]).startsWith(value.slice(0, -1)))
    return this
  }
  in(column: string, values: unknown[]) {
    this.filters.push([column, values])
    this.predicates.push((row) => values.includes(row[column]))
    return this
  }
  not(column: string, operator: string, value: unknown) {
    if (operator !== 'is' || value !== null) throw new Error('Only not-null fixtures are supported')
    this.predicates.push((row) => row[column] != null)
    return this
  }
  filter(column: string, _operator: string, value: string) {
    if (column === 'properties->>local_date')
      this.predicates.push((row) => (row.properties as Row)?.local_date === value)
    else throw new Error(`Unexpected filter: ${column}`)
    return this
  }
  order() {
    return this
  }
  limit(size: number) {
    this.maxRows = size
    return this
  }
  insert() {
    throw new Error('Status must not write a table')
  }
  update() {
    throw new Error('Status must not update a table')
  }
  async result(single: boolean): Promise<Result> {
    this.db.reads.push({ table: this.table, columns: this.columns, filters: this.filters })
    await this.db.beforeRead?.(this)
    const error = this.db.errors[this.table] ?? null
    const rows = (this.db.rows[this.table] ?? []).filter((row) =>
      this.predicates.every((p) => p(row)),
    )
    const limited = this.maxRows === undefined ? rows : rows.slice(0, this.maxRows)
    return { data: single ? (limited[0] ?? null) : limited, error }
  }
  single() {
    return this.result(true)
  }
  maybeSingle() {
    return this.result(true)
  }
  // biome-ignore lint/suspicious/noThenProperty: models the external Supabase query boundary.
  then<TResult1 = Result, TResult2 = never>(
    resolve?: ((value: Result) => TResult1 | PromiseLike<TResult1>) | null,
    reject?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ) {
    return this.result(false).then(resolve, reject)
  }
}

class StatusDb {
  reads: Read[] = []
  rpcReads: Array<{ name: string; params: Row }> = []
  errors: Record<string, { message: string }> = {}
  beforeRead?: (query: Query) => Promise<void>
  rows: Record<StatusTable, Row[]> & Partial<Record<string, Row[]>> = {
    users: [],
    user_profiles: [],
    daily_snapshots: [],
    user_progress: [],
    pending_registrations: [],
    notification_preferences: [],
    product_events: [],
    global_config: [],
    messages: [],
    subscriptions: [],
  }
  from(table: string) {
    return new Query(table, this)
  }
  async rpc(name: string, params: Row) {
    this.rpcReads.push({ name, params })
    if (name !== 'list_mobile_routine_items') throw new Error(`Unexpected status RPC: ${name}`)
    const owner = this.rows.users.find((row) => row.id === params.p_user_id)
    if (!owner) throw new Error('Routine owner missing')
    return {
      data: {
        local_date: getLocalDateString(
          String(owner.timezone ?? 'UTC'),
          new Date(String(params.p_now)),
        ),
        items: [],
      },
      error: null,
    }
  }
  client() {
    return this as unknown as PipelineDeps['supabase']
  }
}

const NOW = new Date('2026-10-08T18:00:00.000Z')
const A = 'status-owner-a'
const B = 'status-owner-b'

function addAccount(
  db: StatusDb,
  id: string,
  protocol: Protocol | null,
  locale = 'pt-BR',
  timezone: string | null = 'America/Sao_Paulo',
) {
  db.rows.users.push({
    id,
    name: `Synthetic ${id}`,
    locale,
    timezone,
    metadata: null,
    country: 'BR',
    country_confirmed: true,
    summary: null,
    last_active_at: null,
  })
  db.rows.user_profiles.push({
    user_id: id,
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    body_fat_percent: 20,
    activity_level: 'sedentario',
    training_frequency: 3,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    current_protocol: protocol,
    goal_type: null,
    goal_value: null,
    deficit_level: 500,
  })
}

function snapshot(id: string, calories = 1785, protocol: Protocol = 'manutencao') {
  return {
    id: `day-${id}`,
    user_id: id,
    date: '2026-10-08',
    calories_consumed: calories,
    calories_target: 2400,
    protein_g: 126,
    protein_target: 150,
    carbs_g: 180,
    fat_g: 45,
    exercise_calories: 0,
    water_consumed_ml: 1000,
    current_protocol: protocol,
    day_closed: false,
    day_status: null,
    updated_at: '2026-10-08T17:00:00Z',
    meal_logs: [],
    workout_logs: [],
  }
}

function turn(
  db: StatusDb,
  owner = A,
  text = 'Como está meu dia?',
  timestamp = NOW,
  options: {
    eventKey?: string
    afterContextLoaded?: (context: FlowDayStatusContext) => Promise<void>
  } = {},
) {
  const complete = vi.fn(async () => {
    throw new Error('Status must not call the model')
  })
  const deps: AuthenticatedPipelineDeps = {
    supabase: db.client(),
    llm: { complete } as unknown as PipelineDeps['llm'],
  }
  if (options.afterContextLoaded) {
    deps.loadFlowDayStatus = async (userId, message, time) => {
      const context = await loadFlowDayStatusContext(db.client(), userId, message, time)
      await options.afterContextLoaded?.(context)
      return context
    }
  }
  return {
    complete,
    promise: processAuthenticatedMessage(deps, {
      userId: owner,
      providerMessageId: `mobile_flow/${owner}/${options.eventKey ?? 'synthetic-event'}`,
      text,
      timestamp,
    }),
  }
}

beforeEach(() => clearCalcConfigCache())
afterEach(() => {
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
})

describe('C7 real authenticated entry and official Today loader', () => {
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('answers the exact question in an empty %s day without progress or model', async (protocol) => {
    const db = new StatusDb()
    addAccount(db, A, protocol)
    const request = turn(db)
    const output = await request.promise
    expect(output.text).toContain('Ainda não há refeição ou treino confirmado neste dia.')
    expect(output.text).toMatch(/Consumido: 0 \/ [\d.]+ kcal \(0%\)/u)
    expect(output.text).toContain('Status do dia: 2026-10-08')
    expect(output).toMatchObject({
      stage: protocol,
      modelUsed: 'none',
      toolCalls: [],
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
      singleMessage: true,
      preferAudio: false,
    })
    expect(request.complete).not.toHaveBeenCalled()
    expect(
      db.reads.some((read) => ['v_active_prompts', 'agent_rules', 'messages'].includes(read.table)),
    ).toBe(false)
    expect(db.rpcReads.every((read) => read.name === 'list_mobile_routine_items')).toBe(true)
  })

  it.each([
    'Como está meu dia até agora?',
    'How is my day so far?',
  ])('answers the existing app suggestion exactly: %s', async (text) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    const request = turn(db, A, text)
    const output = await request.promise
    expect(output.modelUsed).toBe('none')
    expect(output.text).toContain(
      text.startsWith('How') ? 'Day status: 2026-10-08' : 'Status do dia: 2026-10-08',
    )
    expect(request.complete).not.toHaveBeenCalled()
  })

  it.each([
    { text: 'Status do dia', saved: 'en', expected: 'Day status:' },
    { text: 'Resumo do dia', saved: 'en', expected: 'Day status:' },
    { text: 'Day status', saved: 'pt-BR', expected: 'Status do dia:' },
    { text: 'Daily summary', saved: 'pt-BR', expected: 'Status do dia:' },
    { text: 'Como está meu dia?', saved: 'en', expected: 'Status do dia:' },
    { text: 'How’s my day?', saved: 'pt-BR', expected: 'Day status:' },
  ])('preserves the existing response locale policy for $text with account $saved', async ({
    text,
    saved,
    expected,
  }) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao', saved)
    expect((await turn(db, A, text).promise).text).toContain(expected)
  })

  it('reads only the authenticated owner and official local date, even across midnight in UTC fallback', async () => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao', 'pt-BR', null)
    addAccount(db, B, 'ganho_massa')
    db.rows.daily_snapshots.push(snapshot(A), snapshot(B, 8888))
    const time = new Date('2026-10-09T00:01:00Z')
    const ctx = await loadFlowDayStatusContext(db.client(), A, 'Como está meu dia?', time)
    expect(ctx.today.local_date).toBe('2026-10-09')
    expect(ctx.today.consumed.calories_kcal).toBe(0)
    expect(ctx.today.current_protocol).toBe('manutencao')
    const ownerReads = db.reads.filter(
      (read) => !['global_config', 'meal_logs'].includes(read.table),
    )
    expect(ownerReads.length).toBeGreaterThan(0)
    for (const read of ownerReads)
      expect(read.filters).toContainEqual([read.table === 'users' ? 'id' : 'user_id', A])
    for (const read of db.reads.filter((read) => read.table === 'meal_logs'))
      expect(read.filters).toContainEqual(['snapshot_id', [`day-${A}`]])
    for (const read of db.reads.filter(
      (read) => read.table === 'daily_snapshots' && read.columns.includes('calories_consumed'),
    ))
      expect(read.filters).toContainEqual(['date', '2026-10-09'])
    expect(
      db.rpcReads.every(
        (read) => read.params.p_user_id === A && read.params.p_now === '2026-10-09T00:01:00.000Z',
      ),
    ).toBe(true)
  })

  it('keeps every official Today energy/protein value and current goal after a historical recomposition snapshot', async () => {
    const db = new StatusDb()
    addAccount(db, A, 'ganho_massa')
    db.rows.daily_snapshots.push(snapshot(A, 1785, 'recomposicao'))
    db.rows.user_progress.push({
      user_id: A,
      deficit_block: 3120,
      blocks_completed: 2,
      current_streak: 3,
      level: 4,
      xp_total: 500,
      updated_at: null,
    })
    const today = await loadOfficialDailyState(db.client(), A, 'America/Sao_Paulo', NOW)
    expect(today).toMatchObject({
      current_protocol: 'ganho_massa',
      consumed: { calories_kcal: 1785 },
      remaining_food_kcal: 615,
      protein_status: { percentage: 84, remaining_g: 24 },
      daily_balance_kcal: -615,
    })
    const output = await turn(db).promise
    expect(output.text).toContain('Consumido: 1.785 / 2.400 kcal (74%).')
    expect(output.text).toContain('Restam: 615 kcal para comida.')
    expect(output.text).toContain('Proteína: 126 / 150 g (84%). Faltam 24 g.')
    expect(output.text).toContain('Balanço do dia (parcial): Déficit de 615 kcal.')
    expect(output.text).toContain('O Bloco 7.700 é exibido apenas na recomposição corporal.')
    expect(output.text).not.toContain('3.120')
    expect(output.text).toContain('Sequência: 3 dias · Nível: 4 · XP: 500.')
  })

  it.each([
    'users',
    'user_profiles',
    'daily_snapshots',
    'user_progress',
    'pending_registrations',
    'notification_preferences',
    'product_events',
  ])('keeps a failed %s read as an error, never a zero day or provider fallback', async (table) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    db.errors[table] = { message: 'synthetic read failure' }
    const request = turn(db)
    await expect(request.promise).rejects.toThrow()
    expect(request.complete).not.toHaveBeenCalled()
  })

  it('keeps missing account an error, with no model call', async () => {
    const request = turn(new StatusDb())
    await expect(request.promise).rejects.toThrow()
    expect(request.complete).not.toHaveBeenCalled()
  })

  it('isolates completed B and fresh A2 when an older A1 result arrives last', async () => {
    const db = new StatusDb()
    addAccount(db, A, 'recomposicao')
    addAccount(db, B, 'manutencao', 'en')
    db.rows.daily_snapshots.push(snapshot(A), snapshot(B, 531))
    let releaseA = () => {}
    let enteredA = () => {}
    const paused = new Promise<void>((resolve) => {
      enteredA = resolve
    })
    const released = new Promise<void>((resolve) => {
      releaseA = resolve
    })
    const firstA = turn(db, A, 'Como está meu dia?', NOW, {
      eventKey: 'A1',
      afterContextLoaded: async () => {
        enteredA()
        await released
      },
    })
    await paused
    const b = turn(db, B, 'Day status', NOW, { eventKey: 'B1' })
    const bOutput = await b.promise
    expect(bOutput.stage).toBe('manutencao')
    expect(bOutput.text).toContain('Consumed: 531 / 2,400 kcal (22%).')
    expect(bOutput.text).not.toContain('1.785')
    // Simulate a later confirmed registration, then issue a new query.
    db.rows.daily_snapshots[0] = { ...snapshot(A, 2300), protein_g: 149 }
    const freshA = turn(db, A, 'Como está meu dia?', NOW, { eventKey: 'A2' })
    const freshOutput = await freshA.promise
    expect(freshOutput.text).toContain('Consumido: 2.300 / 2.400 kcal (96%).')
    expect(freshOutput.text).toContain('Restam: 100 kcal para comida.')
    expect(freshOutput.text).toContain('Proteína: 149 / 150 g (99%). Faltam 1 g.')
    releaseA()
    const aOutput = await firstA.promise
    expect(aOutput.stage).toBe('recomposicao')
    expect(aOutput.text).toContain('Consumido: 1.785 / 2.400 kcal (74%).')
    expect(aOutput.text).not.toContain('531')
    expect(freshOutput.text).toContain('Consumido: 2.300 / 2.400 kcal (96%).')
    expect(firstA.complete).not.toHaveBeenCalled()
    expect(b.complete).not.toHaveBeenCalled()
    expect(freshA.complete).not.toHaveBeenCalled()
  })

  it.each([
    1, 2,
  ])('keeps the official two-attempt fence when the day changes %s times', async (changes) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    db.rows.daily_snapshots.push(snapshot(A))
    let fences = 0
    db.beforeRead = async (query) => {
      if (
        query.table === 'daily_snapshots' &&
        query.columns.includes('calories_consumed') &&
        !query.columns.includes('meal_logs(')
      ) {
        fences++
        if (fences <= changes) db.rows.daily_snapshots[0] = snapshot(A, 1785 + fences * 100)
      }
    }
    const request = turn(db)
    if (changes === 1) {
      const output = await request.promise
      expect(output.text).toContain('Consumido: 1.885 / 2.400 kcal (79%).')
      expect(output.text).toContain('Restam: 515 kcal para comida.')
    } else
      await expect(request.promise).rejects.toMatchObject({
        name: 'DailyStateLoadError',
        operation: 'daily state consistency',
      })
    expect(fences).toBe(2)
    expect(request.complete).not.toHaveBeenCalled()
  })

  it.each([
    { current_streak: -1, level: 1, xp_total: 0 },
    { current_streak: 0, level: 0, xp_total: 0 },
    { current_streak: 0, level: 1, xp_total: 1.5 },
    { current_streak: null, level: 1, xp_total: 0 },
  ])('rejects malformed optional progress instead of displaying invented values: %j', async (progress) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    db.rows.user_progress.push({
      user_id: A,
      deficit_block: 0,
      blocks_completed: 0,
      updated_at: null,
      ...progress,
    })
    const request = turn(db)
    await expect(request.promise).rejects.toMatchObject({
      name: 'DailyStateLoadError',
      operation: 'Flow status progress data',
    })
    expect(request.complete).not.toHaveBeenCalled()
  })

  it('preserves the production subscription gate before any status read', async () => {
    vi.stubEnv('NODE_ENV', 'production')
    vi.stubEnv('SUBSCRIPTION_GATE', 'on')
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    db.rows.subscriptions = [
      { user_id: A, status: 'expired', current_period_end: null, trial_ends_at: null },
    ]
    const request = turn(db)
    expect((await request.promise).text).toContain('assinatura precisa ser renovada')
    expect(db.reads.map((read) => read.table)).toEqual(['subscriptions'])
    expect(request.complete).not.toHaveBeenCalled()
  })

  it.each([
    {
      text: 'Como está meu dia?',
      expected: 'Há registros pendentes de revisão; eles ainda não entram nos totais.',
    },
    {
      text: 'How is my day?',
      expected: 'There are records awaiting review; they are not included in the totals yet.',
    },
  ])('does not present the 20-item pending page as a total when 21 exist: $text', async ({
    text,
    expected,
  }) => {
    const db = new StatusDb()
    addAccount(db, A, 'manutencao')
    db.rows.pending_registrations = Array.from({ length: 21 }, (_, i) => ({
      id: `pending-${i}`,
      user_id: A,
      status: 'pending',
      proposal: { kind: 'meal', mealType: 'almoco' },
      created_at: NOW.toISOString(),
      expires_at: '2026-10-09T18:00:00Z',
    }))
    const context = await loadFlowDayStatusContext(db.client(), A, text, NOW)
    expect(context.today.pending_actions.registrations).toHaveLength(20)
    const request = turn(db, A, text)
    const output = await request.promise
    expect(output.text).toContain(expected)
    expect(output.text).not.toMatch(/(?:Há 20 registros|There are 20 records)/u)
    expect(db.rows.pending_registrations).toHaveLength(21)
    expect(request.complete).not.toHaveBeenCalled()
  })
})
