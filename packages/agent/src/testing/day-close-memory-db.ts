/**
 * In-memory database for the day-close tests (packages/agent, the worker
 * parity test and the mobile API hook test). TEST SUPPORT ONLY: nothing in
 * the product imports this file.
 *
 * It answers the query builder calls that the production closer, the shared
 * close function and their read helpers make, evaluating the filters for
 * real, so a test fails when a query asks for the wrong rows.
 *
 * EMULATED, read from the repository and from the staging schema on
 * 2026-10-04 (read-only), not executed:
 *  - `daily_snapshots.daily_balance`, the generated column:
 *    `(calories_consumed - COALESCE(calories_target, 0)) - COALESCE(exercise_calories, 0)`;
 *  - the column defaults of `daily_snapshots` (`day_status` 'complete',
 *    `day_closed` false, `xp_earned` 0) and the UNIQUE (user_id, date);
 *  - no trigger on `daily_snapshots`: `updated_at` changes only when a writer
 *    sets it;
 *  - `finalize_daily_close_atomic` (migration 20260712000000);
 *  - `advance_reevaluation_schedule` (migration 20260712194305);
 *  - the effect of `register_meal_atomic` (20260711200000) and
 *    `register_workout_atomic` (20260711202000) on the day row: the row is
 *    created with the target handed in, an existing target is kept
 *    (COALESCE), the totals are re-derived from the logs and `updated_at` is
 *    set.
 * The advisory locks of those functions are not emulated; each emulated RPC
 * runs to completion without yielding, which is what the locks guarantee.
 */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { addIsoDateDays, getLocalDateString, getLocalDayUtcBounds } from '../timezone-utils.js'

export type MemoryRow = Record<string, unknown>

export interface MemoryOperation {
  kind: 'select' | 'insert' | 'update' | 'upsert' | 'rpc'
  /** Table name, or the RPC name. */
  target: string
  /** Columns written, for writes. */
  values?: MemoryRow | MemoryRow[]
  filters?: Array<{ op: string; column: string; value: unknown }>
  params?: MemoryRow
  /** Row limit of a read, when it has one. */
  limit?: number
  /** Whether a read asked for an ordering. */
  ordered?: boolean
}

type Filter = { op: string; column: string; value: unknown }
type OperationGate = (operation: MemoryOperation) => void | Promise<void>
type QueryResult = { data: unknown; error: { message: string } | null }

const TABLES = [
  'users',
  'user_profiles',
  'user_progress',
  'daily_snapshots',
  'meal_logs',
  'workout_logs',
  'messages',
  'product_events',
  'global_config',
] as const
type TableName = (typeof TABLES)[number]

function isTimestamp(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value)
}

function compare(left: unknown, right: unknown): number {
  if (typeof left === 'number' && typeof right === 'number') return left - right
  if (isTimestamp(left) && isTimestamp(right)) {
    const difference = Date.parse(left) - Date.parse(right)
    // Inside one millisecond the text still orders the in-memory tail.
    if (difference !== 0) return difference
  }
  return String(left) < String(right) ? -1 : String(left) > String(right) ? 1 : 0
}

function readColumn(row: MemoryRow, column: string): unknown {
  // `properties->>local_date`: the one JSON path the read helpers filter on.
  const jsonPath = column.match(/^(\w+)->>(\w+)$/)
  if (!jsonPath) return row[column]
  const container = row[jsonPath[1] as string]
  if (container === null || typeof container !== 'object') return null
  const value = (container as MemoryRow)[jsonPath[2] as string]
  return value === undefined || value === null ? null : String(value)
}

function matches(row: MemoryRow, filter: Filter): boolean {
  const value = readColumn(row, filter.column)
  switch (filter.op) {
    case 'eq':
      // Exact text for timestamps: `updated_at` is used as a row version and
      // carries microseconds a Date would drop.
      return value === filter.value
    case 'gt':
      return value != null && compare(value, filter.value) > 0
    case 'gte':
      return value != null && compare(value, filter.value) >= 0
    case 'lt':
      return value != null && compare(value, filter.value) < 0
    case 'lte':
      return value != null && compare(value, filter.value) <= 0
    case 'in':
      return (filter.value as unknown[]).includes(value)
    case 'like': {
      const pattern = String(filter.value)
      return pattern.endsWith('%')
        ? String(value).startsWith(pattern.slice(0, -1))
        : String(value) === pattern
    }
    case 'is.null':
      return value === null || value === undefined
    case 'not.is.null':
      return value !== null && value !== undefined
    default:
      throw new Error(`memory db: unsupported filter ${filter.op}`)
  }
}

export class DayCloseMemoryDb {
  readonly tables: Record<TableName, MemoryRow[]> = {
    users: [],
    user_profiles: [],
    user_progress: [],
    daily_snapshots: [],
    meal_logs: [],
    workout_logs: [],
    messages: [],
    product_events: [],
    global_config: [],
  }

  /** Every operation that reached the database, in order. */
  readonly operations: MemoryOperation[] = []

  /** Runs before each operation; a test uses it to interleave another writer. */
  before: ((operation: MemoryOperation) => void | Promise<void>) | null = null

  /** Returns a message to make that operation fail, as a database error. */
  failWith: ((operation: MemoryOperation) => string | null) | null = null

  private sequence = 0

  /** The client handed to the code under test. */
  get client(): ServiceClient {
    return this as unknown as ServiceClient
  }

  /**
   * A second client on the SAME data, as another request of the same account
   * has. `gate` runs before each operation of that client only (and before
   * `before`), so a test can hold one request at an exact point while the
   * other goes on.
   */
  session(gate: (operation: MemoryOperation) => void | Promise<void>): ServiceClient {
    const client = {
      from: (table: string) => this.from(table, gate),
      rpc: (name: string, params: MemoryRow) => this.rpc(name, params, gate),
    }
    return client as unknown as ServiceClient
  }

  /** Operations that changed (or tried to change) data. */
  get writes(): MemoryOperation[] {
    return this.operations.filter((operation) => operation.kind !== 'select')
  }

  /**
   * `now()` with a strictly increasing tail after the milliseconds, so two
   * writes inside one frozen test instant still produce different
   * `updated_at` values, as two transactions do in Postgres.
   */
  timestamp(): string {
    this.sequence += 1
    const base = new Date(Date.now()).toISOString().slice(0, -1)
    return `${base}${String(this.sequence).padStart(6, '0')}+00:00`
  }

  uuid(): string {
    this.sequence += 1
    return `00000000-0000-4000-8000-${String(this.sequence).padStart(12, '0')}`
  }

  from(table: string, gate: OperationGate | null = null): MemoryQuery {
    if (!(TABLES as readonly string[]).includes(table)) {
      throw new Error(`memory db: unexpected table ${table}`)
    }
    return new MemoryQuery(this, table as TableName, gate)
  }

  async rpc(
    name: string,
    params: MemoryRow,
    gate: OperationGate | null = null,
  ): Promise<QueryResult> {
    const operation: MemoryOperation = { kind: 'rpc', target: name, params: { ...params } }
    const failure = await this.enter(operation, gate)
    if (failure) return { data: null, error: { message: failure } }
    try {
      if (name === 'finalize_daily_close_atomic') {
        return { data: this.finalizeDailyClose(params), error: null }
      }
      if (name === 'finalize_mobile_daily_close_atomic') {
        return { data: this.finalizeMobileDailyClose(params), error: null }
      }
      if (name === 'reset_mobile_inactive_streak_atomic') {
        return { data: this.resetMobileInactiveStreak(params), error: null }
      }
      if (name === 'advance_reevaluation_schedule') {
        return { data: this.advanceReevaluationSchedule(params), error: null }
      }
    } catch (error) {
      return { data: null, error: { message: error instanceof Error ? error.message : 'error' } }
    }
    throw new Error(`memory db: unexpected rpc ${name}`)
  }

  async enter(
    operation: MemoryOperation,
    gate: OperationGate | null = null,
  ): Promise<string | null> {
    if (gate) await gate(operation)
    if (this.before) await this.before(operation)
    this.operations.push(operation)
    return this.failWith ? this.failWith(operation) : null
  }

  /** A row as a SELECT returns it: a copy, with the generated column. */
  present(table: TableName, row: MemoryRow): MemoryRow {
    const copy = structuredClone(row)
    if (table === 'daily_snapshots') {
      copy.daily_balance =
        Number(row.calories_consumed) -
        Number(row.calories_target ?? 0) -
        Number(row.exercise_calories ?? 0)
    }
    return copy
  }

  withDefaults(table: TableName, values: MemoryRow): MemoryRow {
    const now = this.timestamp()
    switch (table) {
      case 'daily_snapshots':
        return {
          id: this.uuid(),
          calories_consumed: 0,
          calories_target: null,
          protein_g: 0,
          protein_target: null,
          carbs_g: 0,
          fat_g: 0,
          exercise_calories: 0,
          training_done: false,
          xp_earned: 0,
          current_protocol: null,
          day_status: 'complete',
          day_closed: false,
          closed_at: null,
          gap_reminder_sent_at: null,
          deficit_accumulated: 0,
          water_consumed_ml: 0,
          created_at: now,
          updated_at: now,
          ...values,
        }
      case 'user_progress':
        return {
          xp_total: 0,
          level: 1,
          current_streak: 0,
          longest_streak: 0,
          blocks_completed: 0,
          deficit_block: 0,
          badges_earned: [],
          last_active_date: null,
          next_reevaluation: null,
          current_weight: null,
          current_bf_percent: null,
          updated_at: now,
          ...values,
        }
      case 'product_events':
        return { id: this.uuid(), occurred_at: now, properties: null, ...values }
      case 'meal_logs':
      case 'workout_logs':
      case 'messages':
        return { id: this.uuid(), created_at: now, ...values }
      default:
        return { ...values }
    }
  }

  // ---------------------------------------------------------------- seeding

  /** One app account: no WhatsApp number, a time zone, a zeroed progress row. */
  addAccount(input: {
    userId: string
    timezone?: string | null
    wpp?: string | null
    status?: string
    profile: MemoryRow
    progress?: MemoryRow
  }): void {
    this.tables.users.push({
      id: input.userId,
      created_at: this.timestamp(),
      wpp: input.wpp ?? null,
      timezone: input.timezone === undefined ? 'America/Sao_Paulo' : input.timezone,
      status: input.status ?? 'active',
    })
    this.tables.user_profiles.push({ user_id: input.userId, ...input.profile })
    this.tables.user_progress.push(
      this.withDefaults('user_progress', { user_id: input.userId, ...input.progress }),
    )
  }

  snapshot(userId: string, date: string): MemoryRow | null {
    const row = this.tables.daily_snapshots.find(
      (candidate) => candidate.user_id === userId && candidate.date === date,
    )
    return row ? this.present('daily_snapshots', row) : null
  }

  progress(userId: string): MemoryRow | null {
    const row = this.tables.user_progress.find((candidate) => candidate.user_id === userId)
    return row ? structuredClone(row) : null
  }

  events(userId: string, event?: string): MemoryRow[] {
    return this.tables.product_events
      .filter((row) => row.user_id === userId && (event === undefined || row.event === event))
      .map((row) => structuredClone(row))
  }

  private ensureDayRow(
    userId: string,
    date: string,
    targets: { calories: number | null; protein: number | null },
  ): MemoryRow {
    const existing = this.tables.daily_snapshots.find(
      (row) => row.user_id === userId && row.date === date,
    )
    if (existing) {
      existing.calories_target = existing.calories_target ?? targets.calories
      existing.protein_target = existing.protein_target ?? targets.protein
      existing.updated_at = this.timestamp()
      return existing
    }
    const created = this.withDefaults('daily_snapshots', {
      user_id: userId,
      date,
      calories_target: targets.calories,
      protein_target: targets.protein,
    })
    this.tables.daily_snapshots.push(created)
    return created
  }

  /** The effect of `register_meal_atomic` on the day row and on `meal_logs`. */
  registerMeal(input: {
    userId: string
    date: string
    consumedAt: string
    kcal: number
    proteinG?: number
    carbsG?: number
    fatG?: number
    mealType?: string | null
    caloriesTarget?: number | null
    proteinTarget?: number | null
  }): void {
    const day = this.ensureDayRow(input.userId, input.date, {
      calories: input.caloriesTarget ?? null,
      protein: input.proteinTarget ?? null,
    })
    this.tables.meal_logs.push(
      this.withDefaults('meal_logs', {
        user_id: input.userId,
        snapshot_id: day.id,
        consumed_at: input.consumedAt,
        meal_type: input.mealType ?? null,
        food_name: 'item',
        kcal: input.kcal,
        protein_g: input.proteinG ?? 0,
        carbs_g: input.carbsG ?? 0,
        fat_g: input.fatG ?? 0,
      }),
    )
    const logs = this.tables.meal_logs.filter((log) => log.snapshot_id === day.id)
    const sum = (column: string) => logs.reduce((total, log) => total + Number(log[column]), 0)
    day.calories_consumed = Math.round(sum('kcal'))
    day.protein_g = Math.round(sum('protein_g') * 100) / 100
    day.carbs_g = Math.round(sum('carbs_g') * 100) / 100
    day.fat_g = Math.round(sum('fat_g') * 100) / 100
    day.updated_at = this.timestamp()
  }

  /** The effect of `register_workout_atomic` on the day row and on `workout_logs`. */
  registerWorkout(input: {
    userId: string
    date: string
    performedAt: string
    kcal: number
    caloriesTarget?: number | null
    proteinTarget?: number | null
  }): void {
    const day = this.ensureDayRow(input.userId, input.date, {
      calories: input.caloriesTarget ?? null,
      protein: input.proteinTarget ?? null,
    })
    this.tables.workout_logs.push(
      this.withDefaults('workout_logs', {
        user_id: input.userId,
        snapshot_id: day.id,
        performed_at: input.performedAt,
        workout_type: 'treino',
        duration_min: 40,
        estimated_kcal: input.kcal,
      }),
    )
    const logs = this.tables.workout_logs.filter((log) => log.snapshot_id === day.id)
    day.exercise_calories = Math.round(
      logs.reduce((total, log) => total + Number(log.estimated_kcal), 0),
    )
    day.training_done = logs.length > 0
    day.updated_at = this.timestamp()
  }

  /** An inbound Flow message: a row in `messages`, and no day row. */
  addInboundMessage(userId: string, createdAt: string): void {
    this.tables.messages.push(
      this.withDefaults('messages', {
        user_id: userId,
        direction: 'in',
        provider: 'mobile_flow',
        content: 'mensagem',
        created_at: createdAt,
      }),
    )
  }

  // ------------------------------------------------------------------- RPCs

  private resetMobileInactiveStreak(params: MemoryRow): MemoryRow {
    const refusal = (reason: string) => ({ applied: false, user_id: params.p_user_id, reason })
    const user = this.tables.users.find((row) => row.id === params.p_user_id)
    if (
      !user ||
      user.status !== 'active' ||
      user.wpp !== null ||
      user.timezone !== params.p_expected_timezone ||
      typeof user.timezone !== 'string'
    ) {
      return refusal('context_changed')
    }
    const progress = this.tables.user_progress.find((row) => row.user_id === params.p_user_id)
    if (
      !progress ||
      !isDeepStrictEqual(
        {
          current_streak: progress.current_streak,
          last_active_date: progress.last_active_date,
          updated_at: progress.updated_at,
        },
        params.p_expected_progress,
      )
    )
      return refusal('progress_changed')
    const now = new Date()
    const today = getLocalDateString(user.timezone, now)
    const start = Date.parse(getLocalDayUtcBounds(user.timezone, today).startIso)
    const latest = addIsoDateDays(today, now.getTime() - start >= 30 * 60 * 1000 ? -1 : -2)
    if (latest !== params.p_expected_latest_date) return refusal('context_changed')
    const gap = (Date.parse(latest) - Date.parse(String(progress.last_active_date))) / 86_400_000
    if (Number(progress.current_streak) <= 0 || !progress.last_active_date || gap < 2) {
      return refusal('not_inactive')
    }
    const previous = progress.current_streak
    progress.current_streak = 0
    progress.updated_at = now.toISOString()
    return {
      applied: true,
      user_id: user.id,
      previous_streak: previous,
      last_active_date: progress.last_active_date,
      gap_days: gap,
      latest_closable_date: latest,
    }
  }

  /** New mobile guards only. Locks/SQL rollback still require physical PG tests. */
  private finalizeMobileDailyClose(params: MemoryRow): MemoryRow {
    const refusal = (reason: string) => ({
      applied: false,
      already_closed: false,
      snapshot_id: params.p_snapshot_id,
      reason,
    })
    const user = this.tables.users.find((row) => row.id === params.p_user_id)
    if (
      !user ||
      user.wpp !== null ||
      user.status !== 'active' ||
      user.timezone !== params.p_expected_timezone ||
      typeof user.timezone !== 'string'
    ) {
      return refusal('context_changed')
    }
    const profile = this.tables.user_profiles.find((row) => row.user_id === params.p_user_id)
    if (!profile || !isDeepStrictEqual(profile, params.p_expected_profile)) {
      return refusal('profile_changed')
    }
    const snapshot = this.tables.daily_snapshots.find(
      (row) => row.id === params.p_snapshot_id && row.user_id === params.p_user_id,
    )
    if (!snapshot || snapshot.date !== params.p_last_active_date) return refusal('snapshot_changed')
    if (snapshot.day_closed)
      return {
        applied: false,
        already_closed: true,
        snapshot_id: snapshot.id,
        reason: 'already_closed',
      }
    if (!isDeepStrictEqual(this.present('daily_snapshots', snapshot), params.p_expected_snapshot)) {
      return refusal('snapshot_changed')
    }
    const progress = this.tables.user_progress.find((row) => row.user_id === params.p_user_id)
    const progressFields = progress
      ? Object.fromEntries(
          [
            'xp_total',
            'level',
            'current_streak',
            'longest_streak',
            'blocks_completed',
            'deficit_block',
            'badges_earned',
            'last_active_date',
            'updated_at',
          ].map((key) => [key, progress[key]]),
        )
      : null
    if (!isDeepStrictEqual(progressFields, params.p_expected_progress)) {
      return refusal('progress_changed')
    }
    const now = new Date()
    const today = getLocalDateString(user.timezone, now)
    const start = Date.parse(getLocalDayUtcBounds(user.timezone, today).startIso)
    const latest = addIsoDateDays(today, now.getTime() - start >= 30 * 60 * 1000 ? -1 : -2)
    if (String(params.p_last_active_date) > latest) return refusal('not_closable')
    return this.finalizeDailyClose(params)
  }

  private finalizeDailyClose(params: MemoryRow): MemoryRow {
    const status = params.p_day_status
    const integers = [
      params.p_xp_total,
      params.p_current_streak,
      params.p_longest_streak,
      params.p_blocks_completed,
      params.p_deficit_block,
    ]
    if (
      !params.p_user_id ||
      !params.p_snapshot_id ||
      !params.p_last_active_date ||
      !['complete', 'user_skipped', 'incomplete_no_response'].includes(String(status)) ||
      integers.some((value) => typeof value !== 'number' || value < 0) ||
      typeof params.p_level !== 'number' ||
      params.p_level < 1
    ) {
      throw new Error('invalid daily close payload')
    }
    const snapshot = this.tables.daily_snapshots.find(
      (row) => row.id === params.p_snapshot_id && row.user_id === params.p_user_id,
    )
    if (!snapshot) throw new Error('daily snapshot not found')
    if (snapshot.day_closed) {
      return { applied: false, already_closed: true, snapshot_id: params.p_snapshot_id }
    }

    const written = {
      xp_total: params.p_xp_total,
      level: params.p_level,
      current_streak: params.p_current_streak,
      longest_streak: params.p_longest_streak,
      blocks_completed: params.p_blocks_completed,
      deficit_block: params.p_deficit_block,
      badges_earned: [...((params.p_badges_earned as string[] | null) ?? [])],
      last_active_date: params.p_last_active_date,
      updated_at: this.timestamp(),
    }
    const progress = this.tables.user_progress.find((row) => row.user_id === params.p_user_id)
    if (progress) Object.assign(progress, written)
    else {
      this.tables.user_progress.push(
        this.withDefaults('user_progress', { user_id: params.p_user_id, ...written }),
      )
    }

    snapshot.day_status = status
    snapshot.day_closed = true
    snapshot.closed_at = params.p_closed_at ?? this.timestamp()
    snapshot.updated_at = this.timestamp()
    return {
      applied: true,
      already_closed: false,
      snapshot_id: params.p_snapshot_id,
      day_status: status,
    }
  }

  private advanceReevaluationSchedule(params: MemoryRow): MemoryRow {
    const userId = params.p_user_id
    const closingDate = String(params.p_closing_date)
    const progress = this.tables.user_progress.find((row) => row.user_id === userId)
    if (!progress) throw new Error('user progress not found')
    const plusDays = (date: string, days: number) => {
      const parsed = new Date(`${date}T00:00:00.000Z`)
      parsed.setUTCDate(parsed.getUTCDate() + days)
      return parsed.toISOString().slice(0, 10)
    }

    let next = (progress.next_reevaluation as string | null) ?? null
    let bootstrapped = false
    if (next === null) {
      const first = this.tables.daily_snapshots
        .filter((row) => row.user_id === userId)
        .map((row) => String(row.date))
        .sort()[0]
      if (!first) return { status: 'no_snapshot', next_reevaluation: null }
      next = plusDays(first, 14)
      bootstrapped = true
      if (closingDate < next) {
        progress.next_reevaluation = next
        progress.updated_at = this.timestamp()
        return { status: 'bootstrapped', next_reevaluation: next }
      }
    }
    if (closingDate < next) return { status: 'not_due', next_reevaluation: next }

    const due = next
    do {
      next = plusDays(next, 14)
    } while (next <= closingDate)
    this.tables.product_events.push(
      this.withDefaults('product_events', {
        user_id: userId,
        event: 'reevaluation.due',
        properties: {
          due_date: due,
          closing_date: closingDate,
          next_reevaluation: next,
          bootstrapped,
        },
      }),
    )
    progress.next_reevaluation = next
    progress.updated_at = this.timestamp()
    return { status: 'due', due_date: due, next_reevaluation: next }
  }
}

class MemoryQuery implements PromiseLike<QueryResult> {
  private kind: 'select' | 'insert' | 'update' | 'upsert' = 'select'
  private columns: string | null = '*'
  private readonly filters: Filter[] = []
  private values: MemoryRow | MemoryRow[] | null = null
  private upsertOptions: { onConflict?: string; ignoreDuplicates?: boolean } = {}
  private readonly ordering: Array<{ column: string; ascending: boolean }> = []
  private rowLimit: number | null = null
  private returning = false
  private expect: 'many' | 'single' | 'maybeSingle' = 'many'

  constructor(
    private readonly db: DayCloseMemoryDb,
    private readonly table: TableName,
    private readonly gate: OperationGate | null = null,
  ) {}

  select(columns = '*'): this {
    this.columns = columns
    if (this.kind !== 'select') this.returning = true
    return this
  }

  insert(values: MemoryRow | MemoryRow[]): this {
    this.kind = 'insert'
    this.values = values
    return this
  }

  update(values: MemoryRow): this {
    this.kind = 'update'
    this.values = values
    return this
  }

  upsert(
    values: MemoryRow | MemoryRow[],
    options: { onConflict?: string; ignoreDuplicates?: boolean } = {},
  ): this {
    this.kind = 'upsert'
    this.values = values
    this.upsertOptions = options
    return this
  }

  eq(column: string, value: unknown): this {
    return this.where('eq', column, value)
  }

  gt(column: string, value: unknown): this {
    return this.where('gt', column, value)
  }

  gte(column: string, value: unknown): this {
    return this.where('gte', column, value)
  }

  lt(column: string, value: unknown): this {
    return this.where('lt', column, value)
  }

  lte(column: string, value: unknown): this {
    return this.where('lte', column, value)
  }

  in(column: string, value: unknown[]): this {
    return this.where('in', column, value)
  }

  like(column: string, value: string): this {
    return this.where('like', column, value)
  }

  is(column: string, value: unknown): this {
    if (value !== null) throw new Error('memory db: only is(null)')
    return this.where('is.null', column, value)
  }

  filter(column: string, op: string, value: unknown): this {
    return this.where(op, column, value)
  }

  not(column: string, op: string, value: unknown): this {
    if (op !== 'is' || value !== null) throw new Error('memory db: only not(is, null)')
    return this.where('not.is.null', column, value)
  }

  order(column: string, options: { ascending?: boolean } = {}): this {
    this.ordering.push({ column, ascending: options.ascending !== false })
    return this
  }

  limit(count: number): this {
    this.rowLimit = count
    return this
  }

  single(): Promise<QueryResult> {
    this.expect = 'single'
    return this.run()
  }

  maybeSingle(): Promise<QueryResult> {
    this.expect = 'maybeSingle'
    return this.run()
  }

  // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
  then<TResult1 = QueryResult, TResult2 = never>(
    onfulfilled?: ((value: QueryResult) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return this.run().then(onfulfilled, onrejected)
  }

  private where(op: string, column: string, value: unknown): this {
    this.filters.push({ op, column, value })
    return this
  }

  private project(row: MemoryRow): MemoryRow {
    const presented = this.db.present(this.table, row)
    if (this.columns === null || this.columns.trim() === '*') return presented
    const picked: MemoryRow = {}
    for (const column of this.columns.split(',').map((name) => name.trim())) {
      picked[column] = presented[column] === undefined ? null : presented[column]
    }
    return picked
  }

  private shape(rows: MemoryRow[]): QueryResult {
    if (this.expect === 'many') return { data: rows, error: null }
    if (rows.length > 1) return { data: null, error: { message: 'multiple rows returned' } }
    if (rows.length === 0 && this.expect === 'single') {
      return { data: null, error: { message: 'no rows returned' } }
    }
    return { data: rows[0] ?? null, error: null }
  }

  private async run(): Promise<QueryResult> {
    const operation: MemoryOperation = {
      kind: this.kind,
      target: this.table,
      filters: this.filters.map((filter) => ({ ...filter })),
      ...(this.values ? { values: structuredClone(this.values) } : {}),
      ...(this.rowLimit !== null ? { limit: this.rowLimit } : {}),
      ...(this.ordering.length > 0 ? { ordered: true } : {}),
    }
    const failure = await this.db.enter(operation, this.gate)
    if (failure) return { data: null, error: { message: failure } }

    const rows = this.db.tables[this.table]
    const selected = () => rows.filter((row) => this.filters.every((f) => matches(row, f)))

    if (this.kind === 'select') {
      let result = selected()
      if (this.ordering.length > 0) {
        result = [...result].sort((left, right) => {
          for (const { column, ascending } of this.ordering) {
            const order = compare(left[column], right[column]) * (ascending ? 1 : -1)
            if (order !== 0) return order
          }
          return 0
        })
      }
      if (this.rowLimit !== null) result = result.slice(0, this.rowLimit)
      return this.shape(result.map((row) => this.project(row)))
    }

    const touched: MemoryRow[] = []
    if (this.kind === 'update') {
      for (const row of selected()) {
        Object.assign(row, structuredClone(this.values as MemoryRow))
        touched.push(row)
      }
    } else {
      const list = Array.isArray(this.values) ? this.values : [this.values as MemoryRow]
      const keys = (this.upsertOptions.onConflict ?? '').split(',').filter(Boolean)
      for (const values of list) {
        const conflict =
          this.kind === 'upsert' && keys.length > 0
            ? rows.find((row) => keys.every((key) => row[key] === values[key]))
            : undefined
        if (conflict) {
          if (this.upsertOptions.ignoreDuplicates) continue
          Object.assign(conflict, structuredClone(values))
          touched.push(conflict)
          continue
        }
        if (
          this.table === 'daily_snapshots' &&
          rows.some((row) => row.user_id === values.user_id && row.date === values.date)
        ) {
          return { data: null, error: { message: 'duplicate key value (user_id, date)' } }
        }
        const created = this.db.withDefaults(this.table, structuredClone(values))
        rows.push(created)
        touched.push(created)
      }
    }
    if (!this.returning) return { data: null, error: null }
    return this.shape(touched.map((row) => this.project(row)))
  }
}
