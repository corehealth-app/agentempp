/**
 * Golden regression — Defect B, "second portion in the app" (iPhone, staging,
 * QA account, 2026-10-04; patient timezone America/Sao_Paulo, local date
 * 2026-10-04).
 *
 * Report: Registrar → Refeição → Escrever → "150 g de frango grelhado no
 * almoço" → Confirmar, and the same meal again one minute later. The app
 * said "Refeição confirmada" twice; the database kept ONE lunch row. The app
 * context carries no patient text, so `registra_refeicao` read the name
 * overlap inside 30 min as a correction and deleted the first row.
 *
 * READ FROM STAGING (not invented):
 *  - Breakfast of the day, meal_logs created 2026-10-04T12:04:39.442Z,
 *    meal_type cafe, one provider message id:
 *      café sem açúcar 200 g   2.00 kcal · P 0    · C 0     · F 0    (llm_estimate)
 *      ovo mexido      100 g 150.00 kcal · P 7    · C 18    · F 5    (llm_estimate)
 *      pão francês      50 g 149.90 kcal · P 3.98 · C 29.32 · F 1.55 (canonical_fuzzy, food_db 210)
 *    Sum 301.9 kcal; the snapshot stores round(sum of rows).
 *  - Proposal 1: pending created 14:58:03.558Z, source_timestamp
 *    14:58:02.503Z, source_local_date 2026-10-04, mealType almoco, replace
 *    false, one item "frango grelhado no almoço" (WITH cedilla) 150 g,
 *    238.8 kcal, P 48.05, C 0, F 3.72, food_db_id 7, canonical_fuzzy,
 *    display 150 g, user_kcal null; confirmed (resolved_at) 14:58:29.651Z.
 *  - Proposal 2: pending created 14:59:03.518Z, source_timestamp
 *    14:59:02.488Z, same shape, item "frango grelhado no almoco" (WITHOUT
 *    cedilla, as typed), nutrition_source history; confirmed 14:59:28.287Z.
 *  - Observed after the second confirmation: ONE almoco row ("frango
 *    grelhado no almoco", 150 g, 238.80 kcal, created 14:59:28.055Z,
 *    consumed_at 14:59:02.488Z); daily_snapshots: calories_consumed 541,
 *    protein_g 59.03, carbs_g 47.32, fat_g 10.27, exercise_calories 322,
 *    calories_target 2980, protein_target 144, daily_balance -2761.
 *  - Correct result: two almoco rows; calories_consumed
 *    round(301.9 + 238.8 + 238.8) = 780; protein_g 107.08.
 *
 * ASSUMED (not in the report, or not readable from the rows) — declared:
 *  - The user id, the snapshot id, the meal row ids and the three provider
 *    message ids are synthetic. The two proposals had DIFFERENT
 *    source_provider_message_id values on staging; their literal values were
 *    not copied here.
 *  - consumed_at of the breakfast rows is taken as their created_at.
 *  - The first lunch row was deleted on staging, so its created_at does not
 *    exist anymore: the clock of the first confirmation is the pending's
 *    resolved_at (14:58:29.651Z). The clock of the second is the surviving
 *    row's created_at (14:59:28.055Z).
 *  - The snapshot BEFORE the lunch (302 kcal, P 10.98, C 47.32, F 6.55) is
 *    derived from the breakfast rows; exercise 322 and the targets 2980/144
 *    are the values read after the second confirmation, taken as unchanged
 *    during that minute. day_status/gap_reminder_sent_at: no gap reminder.
 *  - Every other table the tool reads is empty: global_config (no calc.*
 *    override) and user_profiles (the targets then come from the snapshot,
 *    which the SQL keeps with COALESCE).
 *  - Proposal 2 keeps food_db_id 7 ("same shape").
 *  - The two RPCs are emulated in TypeScript from the migrations
 *    20260713145901 (register_meal_atomic) and 20260716160452
 *    (register_meal_atomic_scoped): unique index (user_id,
 *    raw_provider_message_id, food_name) with ON CONFLICT DO NOTHING, the
 *    scoped DELETE by id, numeric(…,2) columns and the snapshot recomputed as
 *    round(sum of rows). The real SQL was read, not executed. The emulation
 *    reproduces the observed staging state to the unit (case 7).
 *  - Cases 3 to 6 are DERIVED variants of the same cause (more than 30 min,
 *    across meals, partial drop, different grams). They were not observed on
 *    the iPhone; their foods and macros other than the chicken are invented.
 *  - Cases 8 to 10, 16 and 17 use the WhatsApp tap context
 *    (interactive-handler) with the same proposals. No WhatsApp print exists
 *    for them: they only pin that the channel behaves exactly as before.
 *  - Cases 12 to 15 (telemetry of the app confirm, failed reads, a lost event)
 *    come from the adversarial review of 2026-10-04, not from the device. The
 *    failures are injected in the in-memory database ("statement timeout").
 *  - Cases 18 to 21 are CHARACTERISATIONS of declared pendencies (a patient
 *    who uses both channels for the same meal; the same name twice inside one
 *    proposal, with an invented egg). They pin what the code does today; they
 *    do not say it is right.
 *
 * Declared pendencies (CLAUDE.md criterion 2; the same lines are in
 * docs/CALCULO-MPP.md §5):
 *
 * > RC B — cenário WhatsApp primeiro e app depois, em até 30 min NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Agora SOMA (2 linhas, 780 kcal); antes desta PR substituía (1 linha, 541).
 *   Muda o total de quem usa os dois canais. Só caracterizado no caso 18.
 * > RC B — cenário app primeiro e WhatsApp depois NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: em até 30 min o tap do WhatsApp SUBSTITUI a linha confirmada no
 *   app (1 linha, 541; caso 19); depois disso o item idêntico do WhatsApp é
 *   descartado como já registrado.
 * > RC B — cenário dois itens com o mesmo nome dentro de UMA proposta do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado, anterior a esta PR: mesmas gramas viram uma linha só (perda
 *   silenciosa, o card mostra o dobro; caso 20); nutrição diferente entre as
 *   cópias lança "conflito nutricional" e o confirm devolve 500 em toda
 *   tentativa (caso 21).
 * > RC B — cenário treino confirmado duas vezes no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: `registra_treino` descarta treino idêntico (tipo + duração) em
 *   6 h e o app mostra "confirmado".
 * > RC B — cenário reclamação C8-35 do WhatsApp (2ª porção sem frase de adição) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado por desenho: substitui em 30 min, descarta depois (casos 8 e 10).
 * > RC B — cenário SQL real das RPCs NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   `register_meal_atomic` e `register_meal_atomic_scoped` são emuladas em
 *   TypeScript a partir das migrações; nenhum teste executa o SQL.
 * > RC B — cenário editar ou apagar refeição já confirmada no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não existe no app: toda confirmação soma e um engano não pode ser desfeito
 *   por lá. Os dois eventos de telemetria só medem; não corrigem.
 * > RC B — cenário foto e áudio no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Usam o mesmo confirm, mas não foram reproduzidos no aparelho.
 * > RC B — cenário pending sem o marcador (criado no WhatsApp ou antes desta PR) confirmado pela API do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Segue o caminho antigo, com perda; só medido por
 *   `mobile.registration.implicit_replace`.
 * > RC B — cenário mensagem "já registrado" no iPhone para o código registration_already_confirmed NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O PATCH de um pending cujo registro já foi gravado responde esse código
 *   (não `registration_not_pending`, que o iPhone trata com "Criar nova
 *   proposta" e que, com a confirmação aditiva, gravaria a refeição de novo).
 *   O build atual não conhece o código: mostra "Não foi possível concluir.
 *   Tente novamente.", mantém a proposta na tela e Confirmar responde
 *   "Registro confirmado." sem gravar de novo. Falta a mudança no iOS. Lido no
 *   código do app, não executado no aparelho; a parte do servidor está em
 *   apps/admin/src/lib/mobile-api/registration-service.second-portion.test.ts,
 *   com as demais pendências da guarda da edição (pending sem marcador, treino
 *   do WhatsApp, pending expirado), todas em docs/CALCULO-MPP.md §5.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { buildConfirmedMealArgs, type ConfirmedMealProposal } from '../confirmed-meal.js'
import { registraRefeicao, type ToolContext } from '../tools.js'

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000a1'
const SNAPSHOT_ID = '0b9f6f0e-0000-4000-8000-0000000000d4'
const TIMEZONE = 'America/Sao_Paulo'
const LOCAL_DATE = '2026-10-04'
const BREAKFAST_KEY = '0b9f6f0e-58a1-4a10-9d55-120439000001'
const KEY_1 = '0b9f6f0e-58a1-4a10-9d55-1458020000a1'
const KEY_2 = '0b9f6f0e-58a1-4a10-9d55-1459020000b2'

const SOURCE_1 = '2026-10-04T14:58:02.503Z'
const SOURCE_2 = '2026-10-04T14:59:02.488Z'
const CONFIRM_1 = '2026-10-04T14:58:29.651Z'
const CONFIRM_2 = '2026-10-04T14:59:28.055Z'

type Row = Record<string, unknown>

type MealRow = {
  id: string
  user_id: string
  snapshot_id: string
  meal_type: string | null
  food_name: string
  food_db_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source: string | null
  confidence: number | null
  consumed_at: string
  created_at: string
  raw_provider_message_id: string | null
}

type SnapshotRow = {
  id: string
  user_id: string
  date: string
  calories_consumed: number
  protein_g: number
  carbs_g: number
  fat_g: number
  exercise_calories: number
  calories_target: number | null
  protein_target: number | null
  daily_balance: number
  day_status: string
  gap_reminder_sent_at: string | null
}

type ProductEvent = { user_id: string; event: string; properties: Record<string, unknown> }

type AtomicItem = {
  food_name: string
  food_db_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source: string | null
  confidence: number | null
}

type AtomicParams = {
  p_user_id: string
  p_date: string
  p_meal_type: string | null
  p_items: AtomicItem[]
  p_replace: boolean
  p_replace_meal_types: string[] | null
  p_consumed_at: string
  p_provider_message_id: string | null
  p_calories_target: number | null
  p_protein_target: number | null
  p_replace_log_ids?: string[]
}

type AtomicResult = {
  snapshot_id: string
  inserted_count: number
  inserted_food_names: string[]
  replaced_count: number
  calories_consumed: number
  protein_g: number
  carbs_g: number
  fat_g: number
  calories_target: number | null
  protein_target: number | null
  daily_balance: number
}

type RpcOutcome = { data: AtomicResult; error: null } | { data: null; error: { message: string } }

type Filter = { op: 'eq' | 'gte' | 'in' | 'not_null'; column: string; value: unknown }

type ReadError = { message: string }

/** What a test makes fail. The names say which statement of the tool is hit. */
type Failures = {
  /** meal_logs of the last 30 min (the overlap evidence). */
  recentLookup?: boolean
  /** meal_logs of the same meal type in the day's snapshot (the day dedup). */
  sameDayLookup?: boolean
  /** product_events whose insert rejects, by event name. */
  eventInserts?: string[]
}

const TIMEOUT: ReadError = { message: 'statement timeout' }

const TIMESTAMP_COLUMNS = new Set(['created_at', 'consumed_at'])

function passes(row: Row, filter: Filter): boolean {
  const value = row[filter.column]
  if (filter.op === 'eq') return value === filter.value
  if (filter.op === 'in') return Array.isArray(filter.value) && filter.value.includes(value)
  if (filter.op === 'not_null') return value != null
  if (value == null) return false
  return TIMESTAMP_COLUMNS.has(filter.column)
    ? Date.parse(String(value)) >= Date.parse(String(filter.value))
    : Number(value) >= Number(filter.value)
}

/** A table that holds rows: every filter the tool sends is really applied,
 * and a filter this fixture does not know fails the test instead of passing. */
class Query {
  private readonly filters: Filter[] = []
  private sort: { column: string; ascending: boolean } | null = null
  private max: number | null = null

  constructor(
    private readonly source: () => Row[],
    private readonly failure: (filters: Filter[]) => ReadError | null = () => null,
  ) {}

  select(): this {
    return this
  }

  eq(column: string, value: unknown): this {
    this.filters.push({ op: 'eq', column, value })
    return this
  }

  gte(column: string, value: unknown): this {
    this.filters.push({ op: 'gte', column, value })
    return this
  }

  in(column: string, value: unknown[]): this {
    this.filters.push({ op: 'in', column, value })
    return this
  }

  not(column: string, operator: string, value: unknown): this {
    if (operator !== 'is' || value !== null) {
      throw new Error(`in-memory db: unsupported filter not(${column}, ${operator})`)
    }
    this.filters.push({ op: 'not_null', column, value: null })
    return this
  }

  order(column: string, options?: { ascending?: boolean }): this {
    this.sort = { column, ascending: options?.ascending !== false }
    return this
  }

  limit(count: number): this {
    this.max = count
    return this
  }

  private run(): Row[] {
    let rows = this.source().filter((row) => this.filters.every((filter) => passes(row, filter)))
    const sort = this.sort
    if (sort) {
      rows = [...rows].sort((left, right) => {
        const order = String(left[sort.column]).localeCompare(String(right[sort.column]))
        return sort.ascending ? order : -order
      })
    }
    return this.max == null ? rows : rows.slice(0, this.max)
  }

  maybeSingle(): Promise<{ data: Row | null; error: ReadError | null }> {
    const error = this.failure(this.filters)
    return Promise.resolve(
      error ? { data: null, error } : { data: this.run()[0] ?? null, error: null },
    )
  }

  // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
  then<Fulfilled = { data: Row[] | null; error: ReadError | null }, Rejected = never>(
    onFulfilled?:
      | ((value: {
          data: Row[] | null
          error: ReadError | null
        }) => Fulfilled | PromiseLike<Fulfilled>)
      | null,
    onRejected?: ((reason: unknown) => Rejected | PromiseLike<Rejected>) | null,
  ): Promise<Fulfilled | Rejected> {
    // As supabase-js: a failed statement resolves with `error`, it does not reject.
    const error = this.failure(this.filters)
    return Promise.resolve(error ? { data: null, error } : { data: this.run(), error: null }).then(
      onFulfilled,
      onRejected,
    )
  }
}

/** A table declared empty in the header: any read answers "no rows". */
function emptyTable(): unknown {
  const table: Record<string, unknown> = {}
  const chain = () => table
  for (const method of [
    'select',
    'eq',
    'neq',
    'gt',
    'gte',
    'lt',
    'lte',
    'in',
    'not',
    'is',
    'or',
    'like',
    'ilike',
    'order',
    'limit',
  ]) {
    table[method] = chain
  }
  table.maybeSingle = () => Promise.resolve({ data: null, error: null })
  // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
  table.then = (onFulfilled: (value: { data: Row[]; error: null }) => unknown) =>
    Promise.resolve(onFulfilled({ data: [], error: null }))
  return table
}

const toCents = (value: number) => Math.round(value * 100)
const unaccent = (value: string) =>
  value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()

function stagingDay(failures: Failures = {}) {
  const has = (filters: Filter[], op: Filter['op'], column: string) =>
    filters.some((filter) => filter.op === op && filter.column === column)
  const mealLogsFailure = (filters: Filter[]): ReadError | null => {
    if (failures.recentLookup && has(filters, 'gte', 'created_at')) return TIMEOUT
    if (
      failures.sameDayLookup &&
      has(filters, 'eq', 'snapshot_id') &&
      has(filters, 'eq', 'meal_type')
    ) {
      return TIMEOUT
    }
    return null
  }
  const breakfast = (
    id: string,
    food_name: string,
    quantity_g: number,
    kcal: number,
    protein_g: number,
    carbs_g: number,
    fat_g: number,
    source: string,
    food_db_id: number | null,
  ): MealRow => ({
    id,
    user_id: USER_ID,
    snapshot_id: SNAPSHOT_ID,
    meal_type: 'cafe',
    food_name,
    food_db_id,
    quantity_g,
    kcal,
    protein_g,
    carbs_g,
    fat_g,
    source,
    confidence: null,
    consumed_at: '2026-10-04T12:04:39.442Z',
    created_at: '2026-10-04T12:04:39.442Z',
    raw_provider_message_id: BREAKFAST_KEY,
  })
  const meals: MealRow[] = [
    breakfast('breakfast-1', 'café sem açúcar', 200, 2, 0, 0, 0, 'llm_estimate', null),
    breakfast('breakfast-2', 'ovo mexido', 100, 150, 7, 18, 5, 'llm_estimate', null),
    breakfast('breakfast-3', 'pão francês', 50, 149.9, 3.98, 29.32, 1.55, 'canonical_fuzzy', 210),
  ]
  const snapshots: SnapshotRow[] = [
    {
      id: SNAPSHOT_ID,
      user_id: USER_ID,
      date: LOCAL_DATE,
      calories_consumed: 302,
      protein_g: 10.98,
      carbs_g: 47.32,
      fat_g: 6.55,
      exercise_calories: 322,
      calories_target: 2980,
      protein_target: 144,
      daily_balance: 302 - 2980 - 322,
      day_status: 'open',
      gap_reminder_sent_at: null,
    },
  ]
  const events: ProductEvent[] = []
  const rpcCalls: Array<{ fn: string; params: Record<string, unknown> }> = []
  let sequence = 0

  const raise = (message: string): RpcOutcome => ({ data: null, error: { message } })

  // public.register_meal_atomic (20260713145901).
  const registerMealAtomic = (params: AtomicParams): RpcOutcome => {
    const items = params.p_items
    if (!Array.isArray(items) || items.length === 0 || items.length > 30) {
      return raise('items must be a non-empty array with at most 30 entries')
    }
    for (const item of items) {
      if (!item.food_name.trim() || !(item.quantity_g > 0))
        return raise('invalid meal item payload')
      if (item.kcal > item.quantity_g * 9.5 + 5) {
        return raise('invalid meal item nutrition: kcal exceeds physical density')
      }
      if (item.protein_g + item.carbs_g + item.fat_g > item.quantity_g * 1.1 + 5) {
        return raise('invalid meal item nutrition: macro mass exceeds quantity')
      }
      if (
        (item.source === 'canonical_exact' || item.source === 'canonical_fuzzy') &&
        item.food_db_id == null
      ) {
        return raise('invalid meal item provenance: canonical source requires food_db_id')
      }
    }
    let snapshot = snapshots.find(
      (row) => row.user_id === params.p_user_id && row.date === params.p_date,
    )
    if (!snapshot) {
      snapshot = {
        id: `snapshot-${params.p_date}`,
        user_id: params.p_user_id,
        date: params.p_date,
        calories_consumed: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        exercise_calories: 0,
        calories_target: params.p_calories_target,
        protein_target: params.p_protein_target,
        daily_balance: 0,
        day_status: 'open',
        gap_reminder_sent_at: null,
      }
      snapshots.push(snapshot)
    } else {
      snapshot.calories_target = snapshot.calories_target ?? params.p_calories_target
      snapshot.protein_target = snapshot.protein_target ?? params.p_protein_target
    }
    const snapshotId = snapshot.id
    let replacedCount = 0
    if (params.p_replace) {
      const types = params.p_replace_meal_types ?? (params.p_meal_type ? [params.p_meal_type] : [])
      if (types.length === 0) return raise('replace requires at least one meal type')
      for (let index = meals.length - 1; index >= 0; index -= 1) {
        const row = meals[index]
        if (
          row &&
          row.user_id === params.p_user_id &&
          row.snapshot_id === snapshotId &&
          types.includes(row.meal_type ?? '')
        ) {
          meals.splice(index, 1)
          replacedCount += 1
        }
      }
    }
    const inserted: string[] = []
    for (const item of items) {
      const foodName = item.food_name.trim()
      const pmid = params.p_provider_message_id
      // uniq_meal_logs_provider_msg + ON CONFLICT DO NOTHING.
      const conflict =
        pmid != null &&
        meals.some(
          (row) =>
            row.user_id === params.p_user_id &&
            row.raw_provider_message_id === pmid &&
            row.food_name === foodName,
        )
      if (conflict) continue
      sequence += 1
      meals.push({
        id: `meal-log-${sequence}`,
        user_id: params.p_user_id,
        snapshot_id: snapshotId,
        meal_type: params.p_meal_type,
        food_name: foodName,
        food_db_id: item.food_db_id,
        quantity_g: toCents(item.quantity_g) / 100,
        kcal: toCents(item.kcal) / 100,
        protein_g: toCents(item.protein_g) / 100,
        carbs_g: toCents(item.carbs_g) / 100,
        fat_g: toCents(item.fat_g) / 100,
        source: item.source,
        confidence: item.confidence,
        consumed_at: params.p_consumed_at,
        created_at: new Date().toISOString(),
        raw_provider_message_id: pmid,
      })
      inserted.push(foodName)
    }
    // Exact decimal sums, as numeric in Postgres: 301.9 + 238.8 + 238.8 is
    // 779.50 and rounds to 780, never to 779 through a binary float.
    const dayRows = meals.filter((row) => row.snapshot_id === snapshotId)
    const sum = (pick: (row: MealRow) => number) =>
      dayRows.reduce((total, row) => total + toCents(pick(row)), 0)
    snapshot.calories_consumed = Math.round(sum((row) => row.kcal) / 100)
    snapshot.protein_g = sum((row) => row.protein_g) / 100
    snapshot.carbs_g = sum((row) => row.carbs_g) / 100
    snapshot.fat_g = sum((row) => row.fat_g) / 100
    // Generated column: consumed − target − exercise (the block balance).
    snapshot.daily_balance =
      snapshot.calories_consumed - (snapshot.calories_target ?? 0) - snapshot.exercise_calories
    return {
      data: {
        snapshot_id: snapshotId,
        inserted_count: inserted.length,
        inserted_food_names: [...inserted].sort(),
        replaced_count: replacedCount,
        calories_consumed: snapshot.calories_consumed,
        protein_g: snapshot.protein_g,
        carbs_g: snapshot.carbs_g,
        fat_g: snapshot.fat_g,
        calories_target: snapshot.calories_target,
        protein_target: snapshot.protein_target,
        daily_balance: snapshot.daily_balance,
      },
      error: null,
    }
  }

  // public.register_meal_atomic_scoped (20260716160452).
  const registerMealAtomicScoped = (params: AtomicParams): RpcOutcome => {
    const ids = params.p_replace_log_ids ?? []
    if (ids.length === 0) return registerMealAtomic(params)
    if (!params.p_replace) return raise('replace_log_ids requires replace=true')
    if (params.p_replace_meal_types != null) {
      return raise('replace_log_ids and replace_meal_types are mutually exclusive')
    }
    if (new Set(ids).size !== ids.length) return raise('replace_log_ids must be unique')
    const snapshot = snapshots.find(
      (row) => row.user_id === params.p_user_id && row.date === params.p_date,
    )
    if (!snapshot) return raise('replacement snapshot not found')
    const ofDay = (row: MealRow) =>
      row.user_id === params.p_user_id && row.snapshot_id === snapshot.id
    const targets = meals.filter((row) => ofDay(row) && ids.includes(row.id))
    if (targets.length !== ids.length) {
      return raise('replacement target is missing or belongs to another user/day')
    }
    const remaining = meals.filter((row) => ofDay(row) && !ids.includes(row.id))
    const duplicatesUntouched =
      params.p_items.length > ids.length &&
      params.p_items.some((item) =>
        remaining.some(
          (row) =>
            Math.abs(row.quantity_g - item.quantity_g) <= 0.01 &&
            unaccent(row.food_name) === unaccent(item.food_name) &&
            targets.some((target) =>
              target.raw_provider_message_id != null
                ? row.raw_provider_message_id === target.raw_provider_message_id
                : row.raw_provider_message_id == null && row.consumed_at === target.consumed_at,
            ),
        ),
      )
    if (duplicatesUntouched) {
      return raise('scoped replacement payload duplicates an untouched meal item')
    }
    const before = [...meals]
    for (const target of targets) meals.splice(meals.indexOf(target), 1)
    const result = registerMealAtomic({ ...params, p_replace: false, p_replace_meal_types: null })
    if (result.error) {
      // One transaction in SQL: a failed insert rolls the delete back.
      meals.splice(0, meals.length, ...before)
      return result
    }
    return { data: { ...result.data, replaced_count: targets.length }, error: null }
  }

  const client = {
    from(table: string): unknown {
      if (table === 'meal_logs') return new Query(() => meals, mealLogsFailure)
      if (table === 'daily_snapshots') return new Query(() => snapshots)
      if (table === 'product_events') {
        return {
          insert(event: ProductEvent) {
            if (failures.eventInserts?.includes(event.event)) {
              return Promise.reject(new Error(`insert of ${event.event} failed`))
            }
            events.push(event)
            return Promise.resolve({ data: null, error: null })
          },
        }
      }
      return emptyTable()
    },
    rpc(fn: string, params: Record<string, unknown>): Promise<RpcOutcome> {
      rpcCalls.push({ fn, params })
      if (fn === 'register_meal_atomic')
        return Promise.resolve(registerMealAtomic(params as AtomicParams))
      if (fn === 'register_meal_atomic_scoped') {
        return Promise.resolve(registerMealAtomicScoped(params as AtomicParams))
      }
      throw new Error(`in-memory db: unexpected rpc ${fn}`)
    },
  }

  const day = () => {
    const snapshot = snapshots.find((row) => row.user_id === USER_ID && row.date === LOCAL_DATE)
    if (!snapshot) throw new Error('snapshot of the day is missing')
    return snapshot
  }

  return {
    supabase: client as unknown as ServiceClient,
    meals,
    events,
    rpcCalls,
    day,
    lunchRows: () => meals.filter((row) => row.meal_type === 'almoco'),
    /** `meal_type:food_name:grams` of everything but the breakfast. */
    afterBreakfast: () =>
      meals
        .filter((row) => row.meal_type !== 'cafe')
        .map((row) => `${row.meal_type}:${row.food_name}:${row.quantity_g}`)
        .sort(),
    eventNames: () => events.map((event) => event.event),
    eventsNamed: (name: string) => events.filter((event) => event.event === name),
    mealWrites: () => rpcCalls.filter((call) => call.fn.startsWith('register_meal_atomic')),
  }
}

type StagingDay = ReturnType<typeof stagingDay>

const chicken = {
  quantity_g: 150,
  kcal: 238.8,
  protein_g: 48.05,
  carbs_g: 0,
  fat_g: 3.72,
  food_db_id: 7,
  display_qty: 150,
  display_unit: 'g',
  user_kcal: null,
}

/** The items as `confirmRegistration` reads them from the two real pendings. */
const PROPOSAL_1: ConfirmedMealProposal = {
  mealType: 'almoco',
  items: [{ name: 'frango grelhado no almoço', nutrition_source: 'canonical_fuzzy', ...chicken }],
}
const PROPOSAL_2: ConfirmedMealProposal = {
  mealType: 'almoco',
  items: [{ name: 'frango grelhado no almoco', nutrition_source: 'history', ...chicken }],
}

/** The context exactly as `confirmRegistration` builds it in the mobile BFF:
 * no patient text, trusted meal type, the proposal's key and instant. */
function appContext(
  db: StagingDay,
  key: string,
  sourceTimestamp: string,
  additive = true,
): ToolContext {
  return {
    supabase: db.supabase,
    userId: USER_ID,
    userWpp: '',
    userCountry: 'BR',
    userTimezone: TIMEZONE,
    trustMealType: true,
    ...(additive ? { additiveConfirmation: true } : {}),
    providerMessageId: key,
    referenceTimestamp: new Date(sourceTimestamp),
  }
}

/** The context of the WhatsApp button tap (interactive-handler `toolCtx`):
 * patient text from `proposal.source_text`, and never the additive field. */
function whatsappTapContext(
  db: StagingDay,
  wamid: string,
  sourceTimestamp: string,
  sourceText: string,
): ToolContext {
  return {
    supabase: db.supabase,
    userId: USER_ID,
    userWpp: '5511900000000',
    userCountry: 'BR',
    userTimezone: TIMEZONE,
    providerMessageId: wamid,
    referenceTimestamp: new Date(sourceTimestamp),
    currentUserText: sourceText,
    recentUserMessages: sourceText.trim() ? [sourceText] : [],
    trustMealType: true,
  }
}

/** Calls the production tool the way both confirm paths do, at a fixed clock. */
async function confirm(proposal: ConfirmedMealProposal, ctx: ToolContext, clock: string) {
  vi.setSystemTime(new Date(clock))
  return registraRefeicao.execute(buildConfirmedMealArgs(proposal, false, LOCAL_DATE) as never, ctx)
}

const SKIPPED_REPLACE = 'tool.replace_implicit_skipped_additive_confirmation'
const KEPT_DUPLICATE = 'tool.same_day_duplicate_kept_additive_confirmation'

async function confirmBothInTheApp(additive: boolean, failures: Failures = {}) {
  const db = stagingDay(failures)
  const first = await confirm(PROPOSAL_1, appContext(db, KEY_1, SOURCE_1, additive), CONFIRM_1)
  const second = await confirm(PROPOSAL_2, appContext(db, KEY_2, SOURCE_2, additive), CONFIRM_2)
  return { db, first, second }
}

type Food = {
  name: string
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}
const rice: Food = {
  name: 'arroz branco',
  quantity_g: 100,
  kcal: 128,
  protein_g: 2.5,
  carbs_g: 28.1,
  fat_g: 0.2,
}
const salad: Food = {
  name: 'salada de alface',
  quantity_g: 50,
  kcal: 8,
  protein_g: 0.6,
  carbs_g: 1.4,
  fat_g: 0.1,
}
const grilledChicken = (quantity_g: number): Food => ({
  name: 'frango grelhado',
  quantity_g,
  kcal: Math.round(238.8 * (quantity_g / 150) * 10) / 10,
  protein_g: Math.round(48.05 * (quantity_g / 150) * 100) / 100,
  carbs_g: 0,
  fat_g: Math.round(3.72 * (quantity_g / 150) * 100) / 100,
})
const derivedProposal = (mealType: string, foods: Food[]): ConfirmedMealProposal => ({
  mealType,
  items: foods.map((food) => ({
    ...food,
    food_db_id: food.name === 'frango grelhado' ? 7 : null,
    nutrition_source: food.name === 'frango grelhado' ? 'canonical_fuzzy' : 'llm_estimate',
    display_qty: food.quantity_g,
    display_unit: 'g',
    user_kcal: null,
  })),
})

describe('audit 2026-10-04 — Defect B: a meal confirmed twice in the app is two meals', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('1 · exact report: the second identical lunch, one minute later, is ADDED (two rows, 780 kcal)', async () => {
    const { db, first, second } = await confirmBothInTheApp(true)

    expect(first.success).toBe(true)
    expect(second.success).toBe(true)
    expect(second.replaced ?? null).toBeNull()
    expect(second.already_logged).toBeUndefined()
    expect(second.deduped).toBeUndefined()

    expect(db.lunchRows()).toMatchObject([
      {
        food_name: 'frango grelhado no almoço',
        quantity_g: 150,
        kcal: 238.8,
        protein_g: 48.05,
        carbs_g: 0,
        fat_g: 3.72,
        food_db_id: 7,
        source: 'canonical_fuzzy',
        raw_provider_message_id: KEY_1,
        consumed_at: SOURCE_1,
        created_at: CONFIRM_1,
      },
      {
        food_name: 'frango grelhado no almoco',
        quantity_g: 150,
        kcal: 238.8,
        protein_g: 48.05,
        carbs_g: 0,
        fat_g: 3.72,
        food_db_id: 7,
        source: 'history',
        raw_provider_message_id: KEY_2,
        consumed_at: SOURCE_2,
        created_at: CONFIRM_2,
      },
    ])
    expect(db.meals.filter((row) => row.meal_type === 'cafe')).toHaveLength(3)

    // round(301.9 + 238.8 + 238.8) = 780; protein 10.98 + 48.05 + 48.05.
    expect(db.day()).toMatchObject({
      calories_consumed: 780,
      protein_g: 107.08,
      carbs_g: 47.32,
      fat_g: 13.99,
      exercise_calories: 322,
      calories_target: 2980,
      protein_target: 144,
    })
    // No formula changes. Food ("Restam") = consumed − target, WITHOUT
    // exercise; block = consumed − target − exercise.
    expect(db.day().calories_consumed - 2980).toBe(-2200)
    expect(db.day().daily_balance).toBe(780 - 2980 - 322)

    const writes = db.mealWrites()
    expect(writes.map((call) => call.fn)).toEqual(['register_meal_atomic', 'register_meal_atomic'])
    expect(writes.map((call) => call.params.p_replace)).toEqual([false, false])
    expect(writes.map((call) => call.params.p_provider_message_id)).toEqual([KEY_1, KEY_2])
    expect(writes.map((call) => call.params.p_replace_log_ids)).toEqual([undefined, undefined])

    // Nothing is replaced or dropped anymore; the two things the tool used to
    // act on are only measured, with counts (an item name is patient text).
    expect(db.eventsNamed(SKIPPED_REPLACE)).toEqual([
      {
        user_id: USER_ID,
        event: SKIPPED_REPLACE,
        properties: {
          meal_type: 'almoco',
          overlap_ratio: 1,
          recent_count: 1,
          new_count: 1,
          provider_message_id: KEY_2,
        },
      },
    ])
    // "almoço" and "almoco" are the same item for the day dedup key.
    expect(db.eventsNamed(KEPT_DUPLICATE)).toEqual([
      {
        user_id: USER_ID,
        event: KEPT_DUPLICATE,
        properties: { meal_type: 'almoco', existing_count: 1, provider_message_id: KEY_2 },
      },
    ])
    expect(db.eventNames()).not.toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).not.toContain('tool.replace_item_scoped')
    expect(db.eventNames()).not.toContain('tool.meal_item_redup_skipped')
  })

  it('2 · retry: the same proposal confirmed again writes nothing', async () => {
    const { db } = await confirmBothInTheApp(true)
    const writesBefore = db.rpcCalls.length

    const replay = await confirm(
      PROPOSAL_2,
      appContext(db, KEY_2, SOURCE_2),
      '2026-10-04T14:59:40.000Z',
    )

    expect(replay).toMatchObject({ success: true, deduped: true })
    expect(db.rpcCalls).toHaveLength(writesBefore)
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.day().calories_consumed).toBe(780)
  })

  it('3 · derived, more than 30 min: a third identical portion 45 min later is also added', async () => {
    const { db } = await confirmBothInTheApp(true)

    const KEY_3 = '0b9f6f0e-58a1-4a10-9d55-1544030000c3'
    const third = await confirm(
      PROPOSAL_2,
      appContext(db, KEY_3, '2026-10-04T15:44:03.000Z'),
      '2026-10-04T15:44:28.000Z',
    )

    expect(third.success).toBe(true)
    expect(third.already_logged).toBeUndefined()
    expect(db.lunchRows()).toHaveLength(3)
    // round(301.9 + 3 × 238.8) = 1018.
    expect(db.day().calories_consumed).toBe(1018)
    expect(db.eventNames()).not.toContain('tool.meal_item_redup_skipped')
    // Past 30 min the overlap event is silent (only the second confirmation
    // fired it). The duplicate of the day is what still leaves a trace.
    expect(
      db.eventsNamed(SKIPPED_REPLACE).map((event) => event.properties.provider_message_id),
    ).toEqual([KEY_2])
    expect(db.eventsNamed(KEPT_DUPLICATE).map((event) => event.properties)).toEqual([
      { meal_type: 'almoco', existing_count: 1, provider_message_id: KEY_2 },
      { meal_type: 'almoco', existing_count: 1, provider_message_id: KEY_3 },
    ])
  })

  it('4 · derived, across meals: lunch [rice, chicken] then snack [chicken] 5 min later keeps the lunch chicken', async () => {
    const db = stagingDay()
    await confirm(
      derivedProposal('almoco', [rice, grilledChicken(150)]),
      appContext(db, 'key-4-lunch-0001', '2026-10-04T15:00:00.000Z'),
      '2026-10-04T15:00:00.000Z',
    )
    const snack = await confirm(
      derivedProposal('lanche', [grilledChicken(100)]),
      appContext(db, 'key-4-snack-0002', '2026-10-04T15:05:00.000Z'),
      '2026-10-04T15:05:00.000Z',
    )

    expect(snack.success).toBe(true)
    expect(snack.replaced ?? null).toBeNull()
    expect(db.afterBreakfast()).toEqual([
      'almoco:arroz branco:100',
      'almoco:frango grelhado:150',
      'lanche:frango grelhado:100',
    ])
    // round(301.9 + 128 + 238.8 + 159.2) = 828.
    expect(db.day().calories_consumed).toBe(828)
    expect(db.eventNames()).not.toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).not.toContain('tool.replace_item_scoped')
    // Another meal type and other grams: not a duplicate of the day.
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
  })

  it('5 · derived, partial drop: lunch [rice, chicken] then lunch [rice, salad] 45 min later keeps the second rice', async () => {
    const db = stagingDay()
    await confirm(
      derivedProposal('almoco', [rice, grilledChicken(150)]),
      appContext(db, 'key-5-lunch-0001', '2026-10-04T15:00:00.000Z'),
      '2026-10-04T15:00:00.000Z',
    )
    const second = await confirm(
      derivedProposal('almoco', [rice, salad]),
      appContext(db, 'key-5-lunch-0002', '2026-10-04T15:45:00.000Z'),
      '2026-10-04T15:45:00.000Z',
    )

    expect(second.success).toBe(true)
    expect(second.already_logged).toBeUndefined()
    expect(db.afterBreakfast()).toEqual([
      'almoco:arroz branco:100',
      'almoco:arroz branco:100',
      'almoco:frango grelhado:150',
      'almoco:salada de alface:50',
    ])
    // What the app showed as the confirmed meal is what was written.
    expect(second.meal).toMatchObject({ totals: { kcal: 136 } })
    // round(301.9 + 128 + 238.8 + 128 + 8) = 805.
    expect(db.day().calories_consumed).toBe(805)
    expect(db.eventNames()).not.toContain('tool.meal_item_redup_skipped')
    // One of the two items (the rice) was already in the lunch: counted, kept.
    expect(db.eventsNamed(KEPT_DUPLICATE).map((event) => event.properties)).toEqual([
      { meal_type: 'almoco', existing_count: 1, provider_message_id: 'key-5-lunch-0002' },
    ])
    expect(db.eventNames()).not.toContain(SKIPPED_REPLACE)
  })

  it('6 · derived, different grams: chicken 150 g then chicken 200 g one minute later are two rows', async () => {
    const db = stagingDay()
    await confirm(
      derivedProposal('almoco', [grilledChicken(150)]),
      appContext(db, 'key-6-lunch-0001', '2026-10-04T15:00:00.000Z'),
      '2026-10-04T15:00:00.000Z',
    )
    const second = await confirm(
      derivedProposal('almoco', [grilledChicken(200)]),
      appContext(db, 'key-6-lunch-0002', '2026-10-04T15:01:00.000Z'),
      '2026-10-04T15:01:00.000Z',
    )

    expect(second.replaced ?? null).toBeNull()
    expect(db.afterBreakfast()).toEqual([
      'almoco:frango grelhado:150',
      'almoco:frango grelhado:200',
    ])
    // round(301.9 + 238.8 + 318.4) = 859.
    expect(db.day().calories_consumed).toBe(859)
    // Same name inside 30 min: the overlap is measured. Other grams: not the
    // same item of the day.
    expect(db.eventsNamed(SKIPPED_REPLACE)).toHaveLength(1)
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
  })

  it('7 · the report as observed: WITHOUT the field the same sequence reproduces staging (one row, 541)', async () => {
    const { db, second } = await confirmBothInTheApp(false)

    expect(second.success).toBe(true)
    expect(second.replaced).toEqual({ count: 1, kcal_removed: 239 })
    expect(db.eventNames()).toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).toContain('tool.replace_item_scoped')
    expect(db.eventNames()).not.toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic_scoped',
    ])

    // The surviving row and the snapshot, value by value, as read on staging.
    const lunch = db.lunchRows()
    expect(lunch).toHaveLength(1)
    expect(lunch[0]).toMatchObject({
      food_name: 'frango grelhado no almoco',
      quantity_g: 150,
      kcal: 238.8,
      created_at: '2026-10-04T14:59:28.055Z',
      consumed_at: '2026-10-04T14:59:02.488Z',
      raw_provider_message_id: KEY_2,
    })
    expect(db.day()).toMatchObject({
      calories_consumed: 541,
      protein_g: 59.03,
      carbs_g: 47.32,
      fat_g: 10.27,
      exercise_calories: 322,
      calories_target: 2980,
      protein_target: 144,
      daily_balance: -2761,
    })
  })
})

describe('audit 2026-10-04 — Defect B: what the app confirm measures can never fail it', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('12 · the events of the app confirm carry counts and ids, never an item name', async () => {
    const { db } = await confirmBothInTheApp(true)

    const measured = [...db.eventsNamed(SKIPPED_REPLACE), ...db.eventsNamed(KEPT_DUPLICATE)]
    expect(measured).toHaveLength(2)
    for (const event of measured) {
      for (const [key, value] of Object.entries(event.properties)) {
        // Free text would be a string other than the enum and the key.
        if (typeof value === 'string') expect(['meal_type', 'provider_message_id']).toContain(key)
        else expect(typeof value).toBe('number')
      }
      expect(JSON.stringify(event.properties)).not.toMatch(/frango|grelhado/i)
    }
  })

  it('13 · the 30-min read fails ("statement timeout"): no evidence, the second lunch is still written', async () => {
    const { db, second } = await confirmBothInTheApp(true, { recentLookup: true })

    expect(second.success).toBe(true)
    expect(second.replaced ?? null).toBeNull()
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.day().calories_consumed).toBe(780)
    // The overlap could not be read, so it is not reported; the duplicate of
    // the day comes from another read and still is.
    expect(db.eventNames()).not.toContain(SKIPPED_REPLACE)
    expect(db.eventNames()).not.toContain('tool.replace_implicit_detected')
    expect(db.eventsNamed(KEPT_DUPLICATE)).toHaveLength(1)
  })

  it('14 · the read of the day fails: nothing is counted, nothing is dropped, the second lunch is written', async () => {
    const { db, second } = await confirmBothInTheApp(true, { sameDayLookup: true })

    expect(second.success).toBe(true)
    expect(second.already_logged).toBeUndefined()
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.day().calories_consumed).toBe(780)
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
    expect(db.eventsNamed(SKIPPED_REPLACE)).toHaveLength(1)
  })

  it('15 · both event inserts reject: the meal is written all the same', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const { db, first, second } = await confirmBothInTheApp(true, {
      eventInserts: [SKIPPED_REPLACE, KEPT_DUPLICATE],
    })

    expect(first.success).toBe(true)
    expect(second.success).toBe(true)
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.day().calories_consumed).toBe(780)
    expect(db.eventNames()).not.toContain(SKIPPED_REPLACE)
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
    expect(warn).toHaveBeenCalledTimes(2)
  })
})

describe('audit 2026-10-04 — Defect B: the WhatsApp tap behaves exactly as before', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  const TEXT = '150 g de frango grelhado no almoco'

  it('8 · tap, same text twice inside 30 min: the second proposal still REPLACES the first', async () => {
    const db = stagingDay()
    await confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, TEXT), CONFIRM_1)
    const second = await confirm(
      PROPOSAL_2,
      whatsappTapContext(db, 'wamid.B', SOURCE_2, TEXT),
      CONFIRM_2,
    )

    expect(second.replaced).toEqual({ count: 1, kcal_removed: 239 })
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic_scoped',
    ])
    expect(db.eventNames()).toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).not.toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.lunchRows()).toHaveLength(1)
    expect(db.day().calories_consumed).toBe(541)
  })

  it('9 · tap, "mais uma porção": the addition phrase still adds (two rows, 780)', async () => {
    const db = stagingDay()
    await confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, TEXT), CONFIRM_1)
    const second = await confirm(
      PROPOSAL_2,
      whatsappTapContext(db, 'wamid.B', SOURCE_2, `mais uma porção de ${TEXT}`),
      CONFIRM_2,
    )

    expect(second.success).toBe(true)
    expect(second.replaced ?? null).toBeNull()
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.day().calories_consumed).toBe(780)
    expect(db.eventNames()).toContain('tool.replace_blocked_addition_intent')
    expect(db.eventNames()).not.toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic',
    ])
  })

  it('10 · tap without text, 41 min later: the identical item is still dropped as already logged', async () => {
    const db = stagingDay()
    await confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, ''), CONFIRM_1)
    const second = await confirm(
      PROPOSAL_2,
      whatsappTapContext(db, 'wamid.C', '2026-10-04T15:39:03.000Z', ''),
      '2026-10-04T15:39:28.000Z',
    )

    expect(second).toMatchObject({ success: true, already_logged: true })
    expect(db.lunchRows()).toHaveLength(1)
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.eventNames()).toContain('tool.meal_item_redup_skipped')
    expect(db.eventNames()).not.toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.day().calories_consumed).toBe(541)
  })

  it('16 · tap, the 30-min read fails: the confirmation still THROWS and writes nothing', async () => {
    const db = stagingDay({ recentLookup: true })

    // On WhatsApp these rows decide what is replaced: a failed read must not
    // be taken for "nothing to replace". Same message as before the change.
    await expect(
      confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, TEXT), CONFIRM_1),
    ).rejects.toThrow('statement timeout')
    expect(db.mealWrites()).toHaveLength(0)
    expect(db.lunchRows()).toHaveLength(0)
    expect(db.day().calories_consumed).toBe(302)
  })

  it('17 · tap without text, the read of the day fails: the confirmation still THROWS', async () => {
    const db = stagingDay({ sameDayLookup: true })

    await expect(
      confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, ''), CONFIRM_1),
    ).rejects.toThrow('statement timeout')
    expect(db.mealWrites()).toHaveLength(0)
    expect(db.lunchRows()).toHaveLength(0)
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
  })

  it('11 · source guard: only the mobile confirm sets the additive field', () => {
    const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url))
    const sources = (directory: string): string[] =>
      readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const path = join(directory, entry.name)
        if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : sources(path)
        return entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts') ? [path] : []
      })
    const mentioning = [
      'packages/agent/src',
      'packages/inngest-functions/src',
      'apps/admin/src',
      'apps/mobile-bff/src',
      'apps/cli/src',
    ]
      .flatMap((directory) => sources(join(repoRoot, directory)))
      .filter((path) => readFileSync(path, 'utf8').includes('additiveConfirmation'))
      .map((path) => relative(repoRoot, path).split(sep).join('/'))
      .sort()

    // The mobile confirm, the two conditions and the declaration. The
    // WhatsApp pipeline (pipeline.ts) and its button tap
    // (interactive-handler.ts) are not in the list: they never set it.
    expect(mentioning).toEqual([
      'apps/admin/src/lib/mobile-api/registration-service.ts',
      'packages/agent/src/tools.ts',
      'packages/agent/src/tools/types.ts',
    ])
  })
})

describe('audit 2026-10-04 — Defect B: characterisation of declared pendencies (pinned, not fixed)', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  const TEXT = '150 g de frango grelhado no almoco'

  it('18 · characterisation (pendency "WhatsApp primeiro e app depois"): the app confirm ADDS to the WhatsApp row — two rows, 780', async () => {
    const db = stagingDay()
    await confirm(PROPOSAL_1, whatsappTapContext(db, 'wamid.A', SOURCE_1, TEXT), CONFIRM_1)
    const second = await confirm(PROPOSAL_2, appContext(db, KEY_2, SOURCE_2), CONFIRM_2)

    // Before this change the same sequence ended as ONE row and 541 kcal
    // (case 7 is that path). Declared, not decided: a patient who sends the
    // meal on WhatsApp and confirms it again in the app now has it twice.
    expect(second.success).toBe(true)
    expect(second.replaced ?? null).toBeNull()
    expect(db.lunchRows().map((row) => row.raw_provider_message_id)).toEqual(['wamid.A', KEY_2])
    expect(db.day().calories_consumed).toBe(780)
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic',
    ])
    expect(db.eventsNamed(SKIPPED_REPLACE)).toHaveLength(1)
    expect(db.eventsNamed(KEPT_DUPLICATE)).toHaveLength(1)
    expect(db.eventNames()).not.toContain('tool.replace_implicit_detected')
  })

  it('19 · characterisation (pendency "app primeiro e WhatsApp depois"): the WhatsApp tap one minute later REPLACES the app row — one row, 541', async () => {
    const db = stagingDay()
    await confirm(PROPOSAL_1, appContext(db, KEY_1, SOURCE_1), CONFIRM_1)
    const second = await confirm(
      PROPOSAL_2,
      whatsappTapContext(db, 'wamid.B', SOURCE_2, TEXT),
      CONFIRM_2,
    )

    // Unchanged by this PR: the WhatsApp path does not know the row came from
    // the app, and the row the app showed as confirmed is deleted.
    expect(second.replaced).toEqual({ count: 1, kcal_removed: 239 })
    expect(db.lunchRows().map((row) => row.raw_provider_message_id)).toEqual(['wamid.B'])
    expect(db.day().calories_consumed).toBe(541)
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic_scoped',
    ])
    expect(db.eventNames()).toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).not.toContain(SKIPPED_REPLACE)
    expect(db.eventNames()).not.toContain(KEPT_DUPLICATE)
  })

  const egg: Food = {
    name: 'ovo cozido',
    quantity_g: 50,
    kcal: 73,
    protein_g: 6.3,
    carbs_g: 0.3,
    fat_g: 5,
  }

  it('20 · characterisation (pendency "dois itens com o mesmo nome"): two identical eggs in ONE proposal are written as one', async () => {
    const db = stagingDay()
    const result = await confirm(
      derivedProposal('lanche', [egg, egg]),
      appContext(db, 'key-20-snack-0001', '2026-10-04T18:00:00.000Z'),
      '2026-10-04T18:00:00.000Z',
    )

    // The card of the proposal showed 146 kcal; 73 are written. Unchanged by
    // this PR and declared: the additive confirm does not reach this.
    expect(result.success).toBe(true)
    expect(db.afterBreakfast()).toEqual(['lanche:ovo cozido:50'])
    // round(301.9 + 73) = 375.
    expect(db.day().calories_consumed).toBe(375)
  })

  it('21 · characterisation (same pendency): copies with different nutrition make the confirmation throw, and nothing is written', async () => {
    const db = stagingDay()

    await expect(
      confirm(
        derivedProposal('lanche', [egg, { ...egg, kcal: 80 }]),
        appContext(db, 'key-21-snack-0001', '2026-10-04T18:00:00.000Z'),
        '2026-10-04T18:00:00.000Z',
      ),
    ).rejects.toThrow(/conflito nutricional/)
    expect(db.mealWrites()).toHaveLength(0)
    expect(db.afterBreakfast()).toEqual([])
  })
})
