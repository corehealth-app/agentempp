/**
 * Rule M2 (everyday names) through the app's API — the mobile end of the
 * golden packages/agent/src/__golden__/audit-10-04-app-leite-whey.test.ts.
 *
 * THE REPORT: iPhone, staging, QA account, build 21b5ec7, 2026-10-04. Text
 * "1 copo de leite com whey no jantar", grams typed 200 and 30, meal type
 * jantar. The proposal showed "leite" as coconut milk (332.3 kcal, 36.7 g of
 * fat) and "whey" as not calculated (by the code, such a proposal cannot be
 * confirmed; the refusal itself was not captured in the report).
 *
 * Nothing of `@mpp/agent` is replaced: `proposeRegistration`,
 * `editRegistration` and `confirmRegistration` run with the real
 * `calcMealMacros` and the real `registra_refeicao`.
 *
 * READ FROM STAGING on 2026-10-04 (read-only, public catalog data): the
 * windows of search_food_trgm for "leite" and "whey" (six rows each) and the
 * two verified rows 4492 (FDC:171265) and 6407 (FDC:173180). See the golden
 * for which macros of the other rows come from the import migrations.
 *
 * ASSUMED — declared: the body of the propose request was not captured; it is
 * rebuilt from the report (two items, the grams as typed, quantity_basis
 * stated, channel text). User id, request keys, the clock (19:30 BRT) and the
 * day (no other record, targets 2980 kcal / 144 g as read for the QA account
 * on the same day) are synthetic. `replace_pending_registration_atomic` and
 * `register_meal_atomic` are emulated in TypeScript from the migrations
 * 20260712205000 and 20260713145901 (read, not executed). Every other table
 * is empty.
 *
 * REVIEW FINDING (adversarial review of 2026-10-04): "leite" 200 g and "leite
 * integral" 200 g in one proposal were shown as two identical lines (244
 * kcal) and the confirm recorded one (122 kcal). They are now one line of
 * 400 g and the day receives 244 kcal — run here through propose and confirm.
 *
 * Declared pendencies of this end (the full list is in the golden; the
 * section "Padrões do dia a dia" of docs/CALCULO-MPP.md has to carry the same
 * lines):
 *
 * > RC M2 — cenário frase "1 copo de leite com whey no jantar" passando pelo extrator de texto do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O teste entra no propose (POST da proposta) com os itens "leite" e "whey";
 *   o POST /meal-drafts não roda aqui e os nomes gravados no pending real não
 *   foram lidos.
 * > RC M2 — cenário tela do iPhone mostrando o nome assumido NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O contrato não muda (o app imprime `name` como recebe), mas nada foi
 *   executado no aparelho depois desta mudança; nem a proposta com UMA linha
 *   somada no lugar das duas digitadas.
 * > RC M2 — cenário proposta do app com outro item depois dos dois itens somados (quantity_basis e candidate_id lidos por posição em registration-service.ts) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A proposta tem uma linha a menos que o pedido e buildMealPendingProposal
 *   lê `input.items[index]`: o item seguinte recebe o quantity_basis e o
 *   candidate_id do item que foi somado. Kcal, gramas e nomes ficam certos. O
 *   cálculo já devolve `input_indexes`; o serviço ainda não lê (arquivo de
 *   outra raia). Caracterizado no último teste.
 */
import type { Json } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { confirmRegistration, editRegistration, proposeRegistration } from './registration-service'

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000a1'
const SNAPSHOT_ID = '0b9f6f0e-0000-4000-8000-0000000000d7'
const TIMEZONE = 'America/Sao_Paulo'
const LOCAL_DATE = '2026-10-04'
const PROPOSE_AT = '2026-10-04T22:30:00.000Z'
const CONFIRM_AT = '2026-10-04T22:30:20.000Z'
const KEY_PROPOSE = '0b9f6f0e-58a1-4a10-9d55-2230000000a1'
const KEY_EDIT = '0b9f6f0e-58a1-4a10-9d55-2230100000b2'

const MILK_NAME = 'Milk, whole, 3.25% milkfat, with added vitamin D'
const WHEY_NAME = 'Beverages, Protein powder whey based'
const MILK_ROW_ID = 4492
const WHEY_ROW_ID = 6407

type Row = Record<string, unknown>

type FoodRow = {
  id: number
  name_pt: string
  category: string
  country_code: string
  similarity: number
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number | null
}

const food = (
  id: number,
  name_pt: string,
  category: string,
  similarity: number,
  kcal_per_100g: number,
  protein_g: number,
  carbs_g: number,
  fat_g: number,
  fiber_g: number | null,
  country_code = 'BR',
): FoodRow => ({
  id,
  name_pt,
  category,
  country_code,
  similarity,
  kcal_per_100g,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
})

const LEITE = 'Leite e derivados'
const DAIRY = 'Dairy and Egg Products'

// search_food_trgm on staging, 2026-10-04 ~15:00 BRT.
const WINDOWS: Record<string, FoodRow[]> = {
  leite: [
    food(666, 'Leite, de coco', 'Outros alimentos industrializados', 0.428571, 166.16, 1.01, 2.19, 18.36, 0.68),
    food(596, 'Creme de Leite', LEITE, 0.4, 221.48, 1.51, 4.51, 22.48, null),
    food(602, 'Leite, de cabra', LEITE, 0.4, 66.42, 3.07, 5.25, 3.75, null),
    food(601, 'Leite, condensado', LEITE, 0.352941, 312.57, 7.67, 57, 6.74, null),
    food(606, 'Leite, fermentado', LEITE, 0.352941, 69.62, 1.89, 15.67, 0.1, null),
    food(640, 'Chocolate, ao leite', 'Produtos açucarados', 0.333333, 539.59, 7.22, 59.58, 30.27, 2.17),
  ],
  whey: [
    food(4112, 'Whey, acid, fluid', DAIRY, 0.333333, 24, 0.76, 5.12, 0.09, 0, 'US'),
    food(4508, 'Whey, acid, dried', DAIRY, 0.3125, 339, 11.73, 73.45, 0.54, 0, 'US'),
    food(4509, 'Whey, sweet, fluid', DAIRY, 0.294118, 27, 0.85, 5.14, 0.36, 0, 'US'),
    food(4510, 'Whey, sweet, dried', DAIRY, 0.294118, 353, 12.93, 74.46, 1.07, 0, 'US'),
    food(2948, 'Wheat, durum', 'Cereal Grains and Pasta', 0.214286, 339, 13.68, 71.13, 2.47, null, 'US'),
    food(5913, 'Bread, wheat', 'Baked Products', 0.214286, 274, 10.67, 47.54, 4.53, 4, 'US'),
  ],
  [MILK_NAME.toLowerCase()]: [food(MILK_ROW_ID, MILK_NAME, DAIRY, 1, 61, 3.15, 4.8, 3.25, 0, 'US')],
  [WHEY_NAME.toLowerCase()]: [food(WHEY_ROW_ID, WHEY_NAME, 'Beverages', 1, 352, 78.13, 6.25, 1.56, 3.1, 'US')],
}

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
  consumed_at: string
  created_at: string
  raw_provider_message_id: string | null
}

type PendingRow = {
  id: string
  user_id: string
  proposal: Json
  status: string
  created_at: string
  expires_at: string
  resolved_at: string | null
}

type AtomicItem = {
  food_name: string
  food_db_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source: string | null
}

type AtomicParams = {
  p_user_id: string
  p_date: string
  p_meal_type: string | null
  p_items: AtomicItem[]
  p_replace: boolean
  p_consumed_at: string
  p_provider_message_id: string | null
}

type Filter = { op: 'eq' | 'gte' | 'gt' | 'in' | 'not_null' | 'ilike'; column: string; value: unknown }

const TIMESTAMP_COLUMNS = new Set(['created_at', 'consumed_at', 'resolved_at'])

function passes(row: Row, filter: Filter): boolean {
  const value = row[filter.column]
  if (filter.op === 'eq') return value === filter.value
  if (filter.op === 'in') return Array.isArray(filter.value) && filter.value.includes(value)
  if (filter.op === 'not_null') return value != null
  if (filter.op === 'ilike') {
    return String(value ?? '').toLowerCase() === String(filter.value).toLowerCase()
  }
  if (value == null) return false
  const [left, right] = TIMESTAMP_COLUMNS.has(filter.column)
    ? [Date.parse(String(value)), Date.parse(String(filter.value))]
    : [Number(value), Number(filter.value)]
  return filter.op === 'gt' ? left > right : left >= right
}

/** A table that holds rows: filters and updates are really applied, and a
 * filter this fixture does not know fails the test instead of passing. */
class Query {
  private readonly filters: Filter[] = []
  private max: number | null = null
  private patch: Row | null = null

  constructor(private readonly source: () => Row[]) {}

  select(): this {
    return this
  }

  update(values: Row): this {
    this.patch = values
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

  gt(column: string, value: unknown): this {
    this.filters.push({ op: 'gt', column, value })
    return this
  }

  in(column: string, value: unknown[]): this {
    this.filters.push({ op: 'in', column, value })
    return this
  }

  ilike(column: string, value: string): this {
    this.filters.push({ op: 'ilike', column, value })
    return this
  }

  not(column: string, operator: string, value: unknown): this {
    if (operator !== 'is' || value !== null) {
      throw new Error(`in-memory db: unsupported filter not(${column}, ${operator})`)
    }
    this.filters.push({ op: 'not_null', column, value: null })
    return this
  }

  order(): this {
    return this
  }

  limit(count: number): this {
    this.max = count
    return this
  }

  private run(): Row[] {
    const rows = this.source().filter((row) => this.filters.every((filter) => passes(row, filter)))
    if (this.patch) for (const row of rows) Object.assign(row, this.patch)
    return this.max == null ? rows : rows.slice(0, this.max)
  }

  maybeSingle(): Promise<{ data: Row | null; error: null }> {
    return Promise.resolve({ data: this.run()[0] ?? null, error: null })
  }

  // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
  then<Fulfilled = { data: Row[]; error: null }, Rejected = never>(
    onFulfilled?: ((value: { data: Row[]; error: null }) => Fulfilled | PromiseLike<Fulfilled>) | null,
    onRejected?: ((reason: unknown) => Rejected | PromiseLike<Rejected>) | null,
  ): Promise<Fulfilled | Rejected> {
    return Promise.resolve({ data: this.run(), error: null as null }).then(onFulfilled, onRejected)
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

function stagingDay(options: { withoutRows?: number[] } = {}) {
  const meals: MealRow[] = []
  const pendings: PendingRow[] = []
  const searches: Array<{ term: string; min_similarity: number }> = []
  const snapshot = {
    id: SNAPSHOT_ID,
    user_id: USER_ID,
    date: LOCAL_DATE,
    calories_consumed: 0,
    protein_g: 0,
    carbs_g: 0,
    fat_g: 0,
    exercise_calories: 0,
    calories_target: 2980,
    protein_target: 144,
    daily_balance: -2980,
    day_status: 'open',
    gap_reminder_sent_at: null,
  }
  let sequence = 0

  const searchFood = (params: Row) => {
    const term = String(params.search_term)
    const minSimilarity = Number(params.min_similarity)
    searches.push({ term, min_similarity: minSimilarity })
    const window = WINDOWS[term]
    if (!window) throw new Error(`in-memory db: no catalog window for "${term}"`)
    return {
      data: window
        .filter((row) => !(options.withoutRows ?? []).includes(row.id))
        .filter((row) => row.similarity >= minSimilarity)
        .slice(0, Number(params.max_results)),
      error: null,
    }
  }

  // public.register_meal_atomic (20260713145901), for the day of the fixture.
  const registerMealAtomic = (params: AtomicParams) => {
    if (params.p_user_id !== USER_ID || params.p_date !== LOCAL_DATE) {
      return { data: null, error: { message: 'fixture holds only the day of the report' } }
    }
    const inserted: string[] = []
    for (const item of params.p_items) {
      const canonical = item.source === 'canonical_exact' || item.source === 'canonical_fuzzy'
      if (canonical && item.food_db_id == null) {
        return {
          data: null,
          error: { message: 'invalid meal item provenance: canonical source requires food_db_id' },
        }
      }
      const foodName = item.food_name.trim()
      const pmid = params.p_provider_message_id
      // uniq_meal_logs_provider_msg + ON CONFLICT DO NOTHING.
      if (
        pmid != null &&
        meals.some((row) => row.raw_provider_message_id === pmid && row.food_name === foodName)
      ) {
        continue
      }
      sequence += 1
      meals.push({
        id: `meal-log-${sequence}`,
        user_id: params.p_user_id,
        snapshot_id: SNAPSHOT_ID,
        meal_type: params.p_meal_type,
        food_name: foodName,
        food_db_id: item.food_db_id,
        quantity_g: toCents(item.quantity_g) / 100,
        kcal: toCents(item.kcal) / 100,
        protein_g: toCents(item.protein_g) / 100,
        carbs_g: toCents(item.carbs_g) / 100,
        fat_g: toCents(item.fat_g) / 100,
        source: item.source,
        consumed_at: params.p_consumed_at,
        created_at: new Date().toISOString(),
        raw_provider_message_id: pmid,
      })
      inserted.push(foodName)
    }
    const sum = (pick: (row: MealRow) => number) =>
      meals.reduce((total, row) => total + toCents(pick(row)), 0)
    snapshot.calories_consumed = Math.round(sum((row) => row.kcal) / 100)
    snapshot.protein_g = sum((row) => row.protein_g) / 100
    snapshot.carbs_g = sum((row) => row.carbs_g) / 100
    snapshot.fat_g = sum((row) => row.fat_g) / 100
    snapshot.daily_balance =
      snapshot.calories_consumed - snapshot.calories_target - snapshot.exercise_calories
    return {
      data: {
        snapshot_id: SNAPSHOT_ID,
        inserted_count: inserted.length,
        inserted_food_names: [...inserted].sort(),
        replaced_count: 0,
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

  // public.replace_pending_registration_atomic (20260712205000).
  const replacePending = (params: Row) => {
    const proposal = JSON.parse(JSON.stringify(params.p_proposal)) as { [key: string]: Json }
    const key = typeof params.p_request_key === 'string' ? params.p_request_key.trim() : ''
    if (key) proposal.source_provider_message_id = key
    const now = new Date().toISOString()
    const open = pendings.filter((row) => row.status === 'pending')
    for (const row of open) Object.assign(row, { status: 'cancelled', resolved_at: now })
    const id = `0b9f6f0e-0000-4000-8000-0000000c${String(pendings.length + 1).padStart(4, '0')}`
    pendings.push({
      id,
      user_id: String(params.p_user_id),
      proposal,
      status: 'pending',
      created_at: now,
      expires_at: String(params.p_expires_at),
      resolved_at: null,
    })
    return {
      data: { pending_id: id, created: true, status: 'pending', cancelled_count: open.length },
      error: null,
    }
  }

  const client = {
    from(table: string): unknown {
      if (table === 'pending_registrations') return new Query(() => pendings)
      if (table === 'meal_logs') return new Query(() => meals)
      if (table === 'daily_snapshots') return new Query(() => [snapshot])
      if (table === 'product_events') {
        return { insert: () => Promise.resolve({ data: null, error: null }) }
      }
      return emptyTable()
    },
    rpc(fn: string, params: Row) {
      if (fn === 'search_food_trgm') return Promise.resolve(searchFood(params))
      if (fn === 'register_meal_atomic') {
        return Promise.resolve(registerMealAtomic(params as AtomicParams))
      }
      if (fn === 'replace_pending_registration_atomic') {
        return Promise.resolve(replacePending(params))
      }
      throw new Error(`in-memory db: unexpected rpc ${fn}`)
    },
  }

  return { client, meals, pendings, snapshot, searches }
}

const AUTH = {
  userId: USER_ID,
  patient: { country: 'BR', countryConfirmed: true, timezone: TIMEZONE },
}

type MealInput = Extract<Parameters<typeof proposeRegistration>[2], { kind: 'meal' }>

/** What the app sent for the report (see ASSUMED). */
const REPORTED_MEAL: MealInput = {
  kind: 'meal',
  meal_type: 'jantar',
  items: [
    { food_name: 'leite', quantity_g: 200, quantity_basis: 'stated' },
    { food_name: 'whey', quantity_g: 30, quantity_basis: 'stated' },
  ],
  source: { channel: 'text' },
}

describe('rule M2 (iPhone 2026-10-04) — "leite" and "whey" through the app API', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(PROPOSE_AT))
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('the proposal shows the assumed items, resolved, and the confirm records them', async () => {
    const db = stagingDay()
    const proposed = await proposeRegistration(db.client as never, AUTH as never, REPORTED_MEAL, KEY_PROPOSE)

    expect(proposed.status).toBe('pending')
    expect(proposed.proposal).toEqual({
      kind: 'meal',
      meal_type: 'jantar',
      items: [
        {
          name: 'leite integral',
          quantity_g: 200,
          kcal: 122,
          protein_g: 6.3,
          carbs_g: 9.6,
          fat_g: 6.5,
          user_kcal: null,
          nutrition_source: 'canonical_fuzzy',
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: 'stated',
        },
        {
          name: 'whey protein em pó',
          quantity_g: 30,
          kcal: 105.6,
          protein_g: 23.44,
          carbs_g: 1.88,
          fat_g: 0.47,
          user_kcal: null,
          nutrition_source: 'canonical_fuzzy',
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: 'stated',
        },
      ],
      totals: { kcal: 227.6, protein_g: 29.7, carbs_g: 11.5, fat_g: 7 },
      source: { channel: 'text', media_asset_id: null },
      warnings: [],
    })
    // Stored with the catalog rows the values came from and the display unit.
    expect((db.pendings[0]?.proposal as { items: Row[] }).items).toMatchObject([
      { name: 'leite integral', food_db_id: MILK_ROW_ID, display_qty: 200, display_unit: 'ml' },
      { name: 'whey protein em pó', food_db_id: WHEY_ROW_ID, display_qty: 30, display_unit: 'g' },
    ])

    const searchesAtPropose = db.searches.length
    vi.setSystemTime(new Date(CONFIRM_AT))
    const confirmed = await confirmRegistration(db.client as never, AUTH as never, proposed.id)

    expect(confirmed).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: false })
    expect(db.meals).toMatchObject([
      {
        meal_type: 'jantar',
        food_name: 'leite integral',
        food_db_id: MILK_ROW_ID,
        quantity_g: 200,
        kcal: 122,
        protein_g: 6.3,
        carbs_g: 9.6,
        fat_g: 6.5,
        source: 'canonical_fuzzy',
        raw_provider_message_id: KEY_PROPOSE,
      },
      {
        meal_type: 'jantar',
        food_name: 'whey protein em pó',
        food_db_id: WHEY_ROW_ID,
        quantity_g: 30,
        kcal: 105.6,
        protein_g: 23.44,
        carbs_g: 1.88,
        fat_g: 0.47,
        source: 'canonical_fuzzy',
        raw_provider_message_id: KEY_PROPOSE,
      },
    ])
    // 227.6 kcal in the day, not the 332.3 of coconut milk with the whey left out.
    expect(db.snapshot).toMatchObject({ calories_consumed: 228, protein_g: 29.74, fat_g: 6.97 })
    // The confirm persists what was shown; the catalog is not read again.
    expect(db.searches).toHaveLength(searchesAtPropose)
  })

  it('reads only the two catalog rows of the list, by their exact names', async () => {
    const db = stagingDay()
    await proposeRegistration(db.client as never, AUTH as never, REPORTED_MEAL, KEY_PROPOSE)
    expect(db.searches).toEqual([
      { term: MILK_NAME.toLowerCase(), min_similarity: 0.9 },
      { term: WHEY_NAME.toLowerCase(), min_similarity: 0.9 },
    ])
  })

  // The edit screen sends back item.name of every item of the proposal.
  it('an edit that re-sends the shown names keeps the same items', async () => {
    const db = stagingDay()
    const proposed = await proposeRegistration(db.client as never, AUTH as never, REPORTED_MEAL, KEY_PROPOSE)
    const shown = 'items' in proposed.proposal ? (proposed.proposal.items ?? []) : []
    const shownName = (index: number) => String(shown[index]?.name ?? '')

    expect([shownName(0), shownName(1)]).toEqual(['leite integral', 'whey protein em pó'])
    vi.setSystemTime(new Date('2026-10-04T22:30:10.000Z'))
    const edited = await editRegistration(
      db.client as never,
      AUTH as never,
      proposed.id,
      {
        kind: 'meal',
        meal_type: 'jantar',
        items: [
          { food_name: shownName(0), quantity_g: 250, quantity_basis: 'stated' },
          { food_name: shownName(1), quantity_g: 30, quantity_basis: 'stated' },
        ],
        source: { channel: 'text' },
      },
      KEY_EDIT,
    )

    expect(edited.proposal).toMatchObject({
      items: [
        { name: 'leite integral', quantity_g: 250, kcal: 152.5, resolution: 'resolved' },
        { name: 'whey protein em pó', quantity_g: 30, kcal: 105.6, resolution: 'resolved' },
      ],
      totals: { kcal: 258.1 },
      warnings: [],
    })
  })

  // The report itself: what the same request gives when the catalog does not
  // hold the two rows (and what an empty list gives on any catalog).
  it('without the two catalog rows the proposal is the reported one and the confirm is refused', async () => {
    const db = stagingDay({ withoutRows: [MILK_ROW_ID, WHEY_ROW_ID] })
    const proposed = await proposeRegistration(db.client as never, AUTH as never, REPORTED_MEAL, KEY_PROPOSE)

    expect(proposed.proposal).toMatchObject({
      items: [
        {
          name: 'leite',
          quantity_g: 200,
          kcal: 332.3,
          fat_g: 36.72,
          nutrition_source: 'canonical_fuzzy',
          resolution: 'resolved',
        },
        {
          name: 'whey',
          quantity_g: 30,
          kcal: 0,
          nutrition_source: 'protein_mismatch',
          resolution: 'needs_clarification',
        },
      ],
      totals: { kcal: 332.3, fat_g: 36.7 },
    })
    expect((db.pendings[0]?.proposal as { items: Row[] }).items[0]).toMatchObject({ food_db_id: 666 })

    await expect(
      confirmRegistration(db.client as never, AUTH as never, proposed.id),
    ).rejects.toMatchObject({ status: 422, code: 'registration_unresolved_items' })
    expect(db.meals).toEqual([])
  })
  // Review finding: the proposal showed 244 kcal and the day received 122.
  it('"leite" 200 g and "leite integral" 200 g: one line of 400 g on the proposal and 244 kcal in the day', async () => {
    const db = stagingDay()
    const proposed = await proposeRegistration(
      db.client as never,
      AUTH as never,
      {
        kind: 'meal',
        meal_type: 'jantar',
        items: [
          { food_name: 'leite', quantity_g: 200, quantity_basis: 'stated' },
          { food_name: 'leite integral', quantity_g: 200, quantity_basis: 'stated' },
        ],
        source: { channel: 'text' },
      },
      KEY_PROPOSE,
    )

    expect(proposed.proposal).toEqual({
      kind: 'meal',
      meal_type: 'jantar',
      items: [
        {
          name: 'leite integral',
          quantity_g: 400,
          kcal: 244,
          protein_g: 12.6,
          carbs_g: 19.2,
          fat_g: 13,
          user_kcal: null,
          nutrition_source: 'canonical_fuzzy',
          resolution: 'resolved',
          preparation_options: null,
          quantity_basis: 'stated',
        },
      ],
      totals: { kcal: 244, protein_g: 12.6, carbs_g: 19.2, fat_g: 13 },
      source: { channel: 'text', media_asset_id: null },
      warnings: [],
    })
    expect((db.pendings[0]?.proposal as { items: Row[] }).items).toMatchObject([
      { name: 'leite integral', food_db_id: MILK_ROW_ID, display_qty: 400, display_unit: 'ml' },
    ])

    vi.setSystemTime(new Date(CONFIRM_AT))
    const confirmed = await confirmRegistration(db.client as never, AUTH as never, proposed.id)

    expect(confirmed).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: false })
    expect(db.meals).toMatchObject([
      {
        meal_type: 'jantar',
        food_name: 'leite integral',
        food_db_id: MILK_ROW_ID,
        quantity_g: 400,
        kcal: 244,
        protein_g: 12.6,
        carbs_g: 19.2,
        fat_g: 13,
        source: 'canonical_fuzzy',
      },
    ])
    expect(db.meals).toHaveLength(1)
    // What the proposal showed is what the day received.
    expect(db.snapshot).toMatchObject({ calories_consumed: 244, protein_g: 12.6, fat_g: 13 })
  })

  // Declared pendency (RC M2, header): the proposal has one line fewer than
  // the request and the service pairs lines with the request by position.
  // Names, grams and kcal are right; the line after the added pair carries
  // the quantity_basis and the candidate_id of the item that was added.
  it('declared: the item after the two added ones takes the basis and the candidate of the added item', async () => {
    const db = stagingDay()
    const proposed = await proposeRegistration(
      db.client as never,
      AUTH as never,
      {
        kind: 'meal',
        meal_type: 'jantar',
        items: [
          { food_name: 'leite', quantity_g: 200, quantity_basis: 'stated', candidate_id: 'c1-0a1b2c3d' },
          {
            food_name: 'leite integral',
            quantity_g: 200,
            quantity_basis: 'visual_estimate',
            candidate_id: 'c2-1b2c3d4e',
          },
          { food_name: 'whey', quantity_g: 30, quantity_basis: 'stated', candidate_id: 'c3-2c3d4e5f' },
        ],
        source: { channel: 'text' },
      },
      KEY_PROPOSE,
    )

    expect(proposed.proposal).toMatchObject({
      items: [
        { name: 'leite integral', quantity_g: 400, kcal: 244, quantity_basis: 'stated' },
        // Sent as "stated" (third item of the request).
        { name: 'whey protein em pó', quantity_g: 30, kcal: 105.6, quantity_basis: 'visual_estimate' },
      ],
      totals: { kcal: 349.6 },
    })
    expect((db.pendings[0]?.proposal as { items: Row[] }).items).toMatchObject([
      { name: 'leite integral', candidate_id: 'c1-0a1b2c3d' },
      // Sent as c3-2c3d4e5f.
      { name: 'whey protein em pó', candidate_id: 'c2-1b2c3d4e' },
    ])

    vi.setSystemTime(new Date(CONFIRM_AT))
    await confirmRegistration(db.client as never, AUTH as never, proposed.id)
    // The day is right: 244 + 105.6.
    expect(db.meals).toMatchObject([
      { food_name: 'leite integral', quantity_g: 400, kcal: 244 },
      { food_name: 'whey protein em pó', quantity_g: 30, kcal: 105.6 },
    ])
    expect(db.snapshot).toMatchObject({ calories_consumed: 350 })
  })
})
