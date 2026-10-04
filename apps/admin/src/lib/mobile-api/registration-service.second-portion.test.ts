/**
 * Defect B, "second portion in the app" (iPhone, staging, QA account,
 * 2026-10-04) — the mobile BFF end of the fix.
 *
 * Block 1 runs `confirmRegistration` against the REAL `registra_refeicao`: it
 * is the only test that catches a field name that differs between the BFF and
 * the tool, or a marker dropped by the proposal schema. Block 2 pins what the
 * BFF passes to the tool. Blocks 3 and 4 run `editRegistration` and
 * `confirmRegistration` with the real tool too (adversarial review of
 * 2026-10-04): an edit after a failed pending transition, and the origin an
 * edit keeps. Blocks 5 and 6 come from the second review: the two pendings of
 * the report created THROUGH `proposeRegistration` (the seam that stamps the
 * origin), and the edit guard limited to proposals the app created. Block 7
 * comes from the third review: `cancelRegistration` (DELETE) on a pending
 * whose record is already saved, with the real tool, for the reviewer's
 * sequences PB-1, PB-2 and PB-3. The one thing replaced in `@mpp/agent` is
 * `calcMealMacros`, the catalog lookup of propose and edit; every other export
 * is the production one.
 *
 * READ FROM STAGING: the two pendings (created 14:58:03.558Z and
 * 14:59:03.518Z, source_timestamp 14:58:02.503Z and 14:59:02.488Z,
 * source_local_date 2026-10-04, America/Sao_Paulo, mealType almoco, replace
 * false, one item of 150 g, 238.8 kcal, P 48.05, C 0, F 3.72, food_db_id 7,
 * quantity_basis stated, display 150 g, totals 238.8 / 48 / 0 / 3.7; item
 * name "frango grelhado no almoço" + canonical_fuzzy in the first,
 * "frango grelhado no almoco" + history in the second), the breakfast rows
 * (301.9 kcal) and the snapshot observed after the second confirmation
 * (541 kcal, P 59.03, exercise 322, target 2980, protein target 144,
 * balance -2761). Correct result: two almoco rows, 780 kcal, P 107.08.
 *
 * ASSUMED — declared: user id, registration ids, snapshot id and the three
 * provider message ids are synthetic (the two proposals had different keys on
 * staging); the text channel of the proposals; patient country BR; the clock
 * of each confirmation (the first pending's resolved_at 14:58:29.651Z and
 * the surviving row's created_at 14:59:28.055Z); expires_at = created + 24 h;
 * the snapshot before the lunch is derived from the breakfast rows; every
 * other table is empty. The two RPCs are emulated in TypeScript from the
 * migrations 20260713145901 and 20260716160452 (read, not executed), with
 * exact decimal sums as numeric in Postgres.
 *
 * ASSUMED in blocks 3 and 4 — nothing there was observed on a device: the
 * failed UPDATE of the pending is injected in the in-memory database; the
 * edit to 200 g and its macros (318.4 kcal, P 64.07, F 4.96) scale the staging
 * chicken; the WhatsApp lunch (arroz, feijão, salame, calabresa) and its
 * macros are invented, as are the wamid values and the workout rows.
 *
 * ASSUMED in block 5: the bodies of the two propose requests were not
 * captured. They are rebuilt from the stored pendings (the item name as
 * stored, 150 g, quantity_basis stated, channel text, no consumed_at: on
 * staging source_timestamp is about one second before created_at, the time
 * the catalog took, and the test moves the clock the same way).
 * `replace_pending_registration_atomic` is emulated in TypeScript from the
 * migration 20260712205000 (read, not executed).
 *
 * ASSUMED in block 6: the WhatsApp message that produced an express record
 * and a pending (rice at lunch, banana as a snack), its wamid and its macros
 * are invented; they are the scenario of the reviewer, not a print.
 *
 * ASSUMED in block 7 — nothing there was observed on a device: the sequences
 * are the ones the third review ran (PB-1, PB-2, PB-3), the clocks of the
 * Cancel and of the later requests are invented, KEY_3 is synthetic, and the
 * propose body is the one of block 5. The WhatsApp message and the workout
 * rows are the invented ones of blocks 6 and 3.
 *
 * READ FROM THE iPHONE CODE, not run on a device (blocks 3 and 7): the current
 * build maps `409 registration_not_pending` to "create a new proposal" and any
 * conflict code it does not know to a generic failure that keeps the proposal
 * on screen (MobileAPITransportError+Capability.swift:15-16 and 27-28;
 * MealRegistrationModel.swift:344-352 and 431-435;
 * WorkoutRegistrationModel.swift:186-202 and 251-253;
 * RegistrationOperationSummary.swift:46-57). After a Cancel refused with
 * `409 registration_already_confirmed` the meal sheet is in
 * `.failed(.cancel, .serviceUnavailable)` with `currentProposal` kept: it
 * shows "Não foi possível concluir. Tente novamente.", the proposal with
 * Confirmar / Editar / Cancelar, and "Tentar novamente" (the same DELETE, same
 * key). "Criar nova proposta" is not offered (only for
 * `registration_not_pending` and 410), the capture screen is not shown while
 * `currentProposal` exists (RegistrationSheet.swift:838-866), and
 * `propose(reviewed:)` / `createNewProposalFromDraft` both require
 * `currentProposal == nil` (MealRegistrationModel.swift:59-61, 107-108,
 * 176-177). Editar and Cancelar get the same code again; Confirmar gets
 * `already_confirmed: true`. The workout sheet behaves the same way
 * (RegistrationSheet.swift:683-685 and 717-737). So no path of that sheet
 * leads to a second proposal, with two exceptions that are declared below:
 * the 410 of an expired pending, and the patient closing the sheet (X) and
 * registering the same meal again by hand, since the app never said the meal
 * was saved.
 *
 * Declared pendencies of the BFF end (CLAUDE.md criterion 2). The lines of
 * the agent end are in the golden; every line is in docs/CALCULO-MPP.md §5.
 *
 * > RC B — cenário mensagem "já registrado" no iPhone para o código registration_already_confirmed vista no aparelho NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Coberto no código do app em commit separado do mesmo dia (9624cd5): um
 *   409 registration_already_confirmed ao editar ou cancelar fecha a proposta
 *   como confirmada, com a mensagem "Este registro já estava salvo. A
 *   alteração não foi aplicada.", sem oferecer nova proposta. Ainda não
 *   verificado no aparelho, e nenhum teste de interface do app dirige o 409
 *   (só testes de unidade). Continua aberto: um build anterior a esse commit
 *   não conhece o código — mostra "Não foi possível concluir. Tente
 *   novamente.", mantém a proposta na tela, "Tentar novamente" reenvia o
 *   mesmo PATCH ou o mesmo DELETE (mesma resposta) e Confirmar responde
 *   "Registro confirmado." sem gravar de novo; e, em qualquer build, o
 *   servidor só recusa o pedido, não impede uma proposta nova: quem registrar
 *   a mesma refeição de novo depois do aviso a grava duas vezes (2 linhas,
 *   780), porque esta API não apaga registro confirmado (teste "declared:
 *   the refusal is all the server does" do bloco 7).
 * > RC B — cenário pending de refeição sem o marcador cuja escrita já aconteceu, editado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A guarda da edição vale só para proposta com `registration_origin`
 *   `mobile_app`. Sem o marcador (WhatsApp, ou app antes desta PR) a edição é
 *   aceita como antes desta PR: chave nova, e o confirm segue o caminho antigo
 *   (substitui em 30 min; depois disso duplica). Caracterizado no bloco 6.
 * > RC B — cenário pending de treino do WhatsApp com treino do MESMO tipo já gravado pela mesma mensagem, editado ou cancelado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A proposta de treino não carrega marcador, então a guarda de treino vale
 *   para qualquer origem, por chave + tipo (a idempotência de
 *   `registra_treino`): o PATCH fecha esse pending sem gravar o segundo treino,
 *   e o DELETE também o fecha como "confirmed" (409
 *   registration_already_confirmed) em vez de cancelar. O confirm direto do
 *   mesmo pending já terminava igual (deduplicado).
 * > RC B — cenário pending expirado cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado: PATCH e confirm respondem `410 registration_expired`, que o
 *   iPhone trata com "Criar nova proposta" (a refeição seria gravada de novo).
 *   Exige a tela aberta 24 h depois de um confirm que falhou na transição. O
 *   DELETE não olha a validade: enquanto o status ainda é "pending", ele
 *   responde 409 registration_already_confirmed e fecha como "confirmed"
 *   (bloco 7). Depois de um confirm fora da validade o pending já está
 *   "expired", e o DELETE responde 409 registration_not_pending.
 * > RC B — cenário pending sem o marcador (criado no WhatsApp ou antes desta PR) confirmado pela API do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Segue o caminho antigo, com perda; fixado abaixo e só medido por
 *   `mobile.registration.implicit_replace`. Editar esse pending não o torna
 *   aditivo (bloco 4).
 * > RC B — cenário pending de correção do WhatsApp editado pela API do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Inalterado em relação a antes desta PR: a edição reconstrói a proposta sem
 *   `replace`/`writeItems`/`corrections`, e o item que a correção trocaria
 *   continua gravado (4 linhas em vez de 3; bloco 4). A tela do iPhone só
 *   edita proposta criada por ela.
 * > RC B — cenário treino confirmado duas vezes no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   `registra_treino` descarta treino idêntico em 6 h e o app mostra
 *   "confirmado".
 * > RC B — cenário pending de treino editado para refeição pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A proposta de treino não carrega o marcador, então a refeição resultante
 *   segue o caminho antigo. A tela do iPhone não troca o tipo ao editar.
 * > RC B — cenário cancelar (DELETE) um pending de refeição SEM o marcador cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Com o marcador (proposta do app) e para treino o cancelamento agora é
 *   recusado com 409 registration_already_confirmed (bloco 7). Sem o marcador
 *   (WhatsApp, ou app antes desta PR) segue como antes desta PR: o pending
 *   vira "cancelled" e a refeição fica gravada. Caracterizado no bloco 7.
 * > RC B — cenário PATCH ou DELETE simultâneo a um confirm em andamento NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A guarda lê `meal_logs` antes do UPDATE, sem trava: um confirm que grava
 *   entre a leitura e o UPDATE ainda deixa a proposta com chave nova (PATCH)
 *   ou o pending "cancelled" com a refeição gravada (DELETE).
 */
import { calcMealMacros, type MealCalcResult, registraRefeicao } from '@mpp/agent'
import type { Json } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  buildMealPendingProposal,
  cancelRegistration,
  confirmRegistration,
  editRegistration,
  proposeRegistration,
} from './registration-service'

// Only the catalog lookup of propose and edit is replaced; the tools stay real.
vi.mock('@mpp/agent', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@mpp/agent')>()),
  calcMealMacros: vi.fn(),
}))

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000a1'
const SNAPSHOT_ID = '0b9f6f0e-0000-4000-8000-0000000000d4'
const TIMEZONE = 'America/Sao_Paulo'
const LOCAL_DATE = '2026-10-04'
const BREAKFAST_KEY = '0b9f6f0e-58a1-4a10-9d55-120439000001'
const KEY_1 = '0b9f6f0e-58a1-4a10-9d55-1458020000a1'
const KEY_2 = '0b9f6f0e-58a1-4a10-9d55-1459020000b2'
const REGISTRATION_1 = '0b9f6f0e-0000-4000-8000-000000145803'
const REGISTRATION_2 = '0b9f6f0e-0000-4000-8000-000000145903'

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

type PendingRow = {
  id: string
  user_id: string
  proposal: Json
  status: string
  created_at: string
  expires_at: string
  resolved_at: string | null
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
}

type AtomicParams = {
  p_user_id: string
  p_date: string
  p_meal_type: string | null
  p_items: AtomicItem[]
  p_replace: boolean
  p_consumed_at: string
  p_provider_message_id: string | null
  p_replace_log_ids?: string[]
}

type ReplacePendingParams = {
  p_user_id: string
  p_proposal: Json
  p_expires_at: string
  p_request_key: string | null
}

type Filter = { op: 'eq' | 'gte' | 'in' | 'not_null'; column: string; value: unknown }

type DbError = { message: string }

/** What a test makes fail; mutable, so one step of a scenario can fail alone. */
type Failures = {
  /** How many of the next pending→confirmed UPDATEs fail. */
  confirmTransitions: number
  /** The read of meal_logs by provider message id (the edit guard). */
  writtenLookup: boolean
}

type QueryHooks = {
  read?: (filters: Filter[]) => DbError | null
  write?: (patch: Row) => DbError | null
}

const TIMESTAMP_COLUMNS = new Set(['created_at', 'consumed_at', 'resolved_at'])

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

/** A table that holds rows: filters and updates are really applied, and a
 * filter this fixture does not know fails the test instead of passing. */
class Query {
  private readonly filters: Filter[] = []
  private max: number | null = null
  private patch: Row | null = null

  constructor(
    private readonly source: () => Row[],
    private readonly hooks: QueryHooks = {},
  ) {}

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

  /** As supabase-js: a failed statement resolves with `error` and changes nothing. */
  private failure(): DbError | null {
    return this.patch
      ? (this.hooks.write?.(this.patch) ?? null)
      : (this.hooks.read?.(this.filters) ?? null)
  }

  maybeSingle(): Promise<{ data: Row | null; error: DbError | null }> {
    const error = this.failure()
    return Promise.resolve(
      error ? { data: null, error } : { data: this.run()[0] ?? null, error: null },
    )
  }

  // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
  then<Fulfilled = { data: Row[] | null; error: DbError | null }, Rejected = never>(
    onFulfilled?:
      | ((value: {
          data: Row[] | null
          error: DbError | null
        }) => Fulfilled | PromiseLike<Fulfilled>)
      | null,
    onRejected?: ((reason: unknown) => Rejected | PromiseLike<Rejected>) | null,
  ): Promise<Fulfilled | Rejected> {
    const error = this.failure()
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

function stagingDay() {
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
    consumed_at: '2026-10-04T12:04:39.442Z',
    created_at: '2026-10-04T12:04:39.442Z',
    raw_provider_message_id: BREAKFAST_KEY,
  })
  const meals: MealRow[] = [
    breakfast('breakfast-1', 'café sem açúcar', 200, 2, 0, 0, 0, 'llm_estimate', null),
    breakfast('breakfast-2', 'ovo mexido', 100, 150, 7, 18, 5, 'llm_estimate', null),
    breakfast('breakfast-3', 'pão francês', 50, 149.9, 3.98, 29.32, 1.55, 'canonical_fuzzy', 210),
  ]
  const snapshot: SnapshotRow = {
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
  }
  const pendings: PendingRow[] = []
  const workouts: Row[] = []
  const events: ProductEvent[] = []
  const rpcCalls: Array<{ fn: string; params: Record<string, unknown> }> = []
  const failures: Failures = { confirmTransitions: 0, writtenLookup: false }
  let sequence = 0
  let pendingSequence = 0

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
      const conflict =
        pmid != null &&
        meals.some((row) => row.raw_provider_message_id === pmid && row.food_name === foodName)
      if (conflict) continue
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
    // Exact decimal sums: 301.9 + 238.8 + 238.8 is 779.50 and rounds to 780.
    const sum = (pick: (row: MealRow) => number) =>
      meals.reduce((total, row) => total + toCents(pick(row)), 0)
    snapshot.calories_consumed = Math.round(sum((row) => row.kcal) / 100)
    snapshot.protein_g = sum((row) => row.protein_g) / 100
    snapshot.carbs_g = sum((row) => row.carbs_g) / 100
    snapshot.fat_g = sum((row) => row.fat_g) / 100
    snapshot.daily_balance =
      snapshot.calories_consumed - (snapshot.calories_target ?? 0) - snapshot.exercise_calories
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

  // public.register_meal_atomic_scoped (20260716160452): DELETE by id, then insert.
  const registerMealAtomicScoped = (params: AtomicParams) => {
    const ids = params.p_replace_log_ids ?? []
    const targets = meals.filter((row) => ids.includes(row.id))
    if (ids.length === 0 || !params.p_replace || targets.length !== ids.length) {
      return { data: null, error: { message: 'replacement target is missing' } }
    }
    for (const target of targets) meals.splice(meals.indexOf(target), 1)
    const result = registerMealAtomic({ ...params, p_replace: false })
    if (result.error) return result
    return { data: { ...result.data, replaced_count: targets.length }, error: null }
  }

  // public.replace_pending_registration_atomic (20260712205000): the request
  // key is written into the proposal, a retry of the same key answers the
  // pending it created, open pendings are cancelled, and the proposal is
  // stored whole (no key is filtered).
  const replacePendingRegistrationAtomic = (params: ReplacePendingParams) => {
    const proposal = JSON.parse(JSON.stringify(params.p_proposal)) as Json
    if (typeof proposal !== 'object' || proposal === null || Array.isArray(proposal)) {
      return { data: null, error: { message: 'proposal must be a JSON object' } }
    }
    const key = params.p_request_key?.trim() || null
    if (key) {
      proposal.source_provider_message_id = key
      const existing = pendings
        .filter(
          (row) =>
            row.user_id === params.p_user_id &&
            (row.proposal as Row | null)?.source_provider_message_id === key,
        )
        .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0]
      if (existing) {
        return {
          data: {
            pending_id: existing.id,
            created: false,
            status: existing.status,
            cancelled_count: 0,
          },
          error: null,
        }
      }
    }
    const now = new Date().toISOString()
    const open = pendings.filter(
      (row) => row.user_id === params.p_user_id && row.status === 'pending',
    )
    for (const row of open) Object.assign(row, { status: 'cancelled', resolved_at: now })
    pendingSequence += 1
    const id = `0b9f6f0e-0000-4000-8000-0000000b${String(pendingSequence).padStart(4, '0')}`
    pendings.push({
      id,
      user_id: params.p_user_id,
      proposal,
      status: 'pending',
      created_at: now,
      expires_at: params.p_expires_at,
      resolved_at: null,
    })
    return {
      data: { pending_id: id, created: true, status: 'pending', cancelled_count: open.length },
      error: null,
    }
  }

  const client = {
    from(table: string): unknown {
      if (table === 'pending_registrations') {
        return new Query(() => pendings, {
          write: (patch) => {
            if (patch.status !== 'confirmed' || failures.confirmTransitions <= 0) return null
            failures.confirmTransitions -= 1
            return { message: 'could not serialize access due to concurrent update' }
          },
        })
      }
      if (table === 'meal_logs') {
        return new Query(() => meals, {
          read: (filters) =>
            failures.writtenLookup &&
            filters.some((filter) => filter.column === 'raw_provider_message_id')
              ? { message: 'statement timeout' }
              : null,
        })
      }
      if (table === 'workout_logs') return new Query(() => workouts)
      if (table === 'daily_snapshots') return new Query(() => [snapshot])
      if (table === 'product_events') {
        return {
          insert(event: ProductEvent) {
            events.push(event)
            return Promise.resolve({ data: null, error: null })
          },
        }
      }
      return emptyTable()
    },
    rpc(fn: string, params: Record<string, unknown>) {
      rpcCalls.push({ fn, params })
      if (fn === 'register_meal_atomic') {
        return Promise.resolve(registerMealAtomic(params as AtomicParams))
      }
      if (fn === 'register_meal_atomic_scoped') {
        return Promise.resolve(registerMealAtomicScoped(params as AtomicParams))
      }
      if (fn === 'replace_pending_registration_atomic') {
        return Promise.resolve(replacePendingRegistrationAtomic(params as ReplacePendingParams))
      }
      // The estimate of an edited workout; its value is not under test.
      if (fn === 'calc_workout_kcal') return Promise.resolve({ data: 300, error: null })
      throw new Error(`in-memory db: unexpected rpc ${fn}`)
    },
  }

  return {
    client,
    meals,
    snapshot,
    pendings,
    workouts,
    events,
    rpcCalls,
    failures,
    pending: (id: string) => {
      const row = pendings.find((candidate) => candidate.id === id)
      if (!row) throw new Error(`pending ${id} is missing`)
      return row
    },
    storedProposal: (id: string) => {
      const row = pendings.find((candidate) => candidate.id === id)
      return (row?.proposal ?? {}) as Row
    },
    mealWrites: () => rpcCalls.filter((call) => call.fn.startsWith('register_meal_atomic')),
    lunchRows: () => meals.filter((row) => row.meal_type === 'almoco'),
    eventNames: () => events.map((event) => event.event),
    /** Stores a pending as jsonb does: only what survives a JSON round trip. */
    addPending(id: string, createdAt: string, proposal: unknown) {
      pendings.push({
        id,
        user_id: USER_ID,
        proposal: JSON.parse(JSON.stringify(proposal)) as Json,
        status: 'pending',
        created_at: createdAt,
        expires_at: new Date(Date.parse(createdAt) + 24 * 60 * 60 * 1000).toISOString(),
        resolved_at: null,
      })
    },
  }
}

type StagingDay = ReturnType<typeof stagingDay>

const AUTH = {
  userId: USER_ID,
  patient: { country: 'BR', countryConfirmed: true, timezone: TIMEZONE },
}

type StagingSource = 'canonical_fuzzy' | 'history'

/** What the catalog answered on staging for the 150 g of chicken. */
function stagingCalculation(name: string, source: StagingSource): MealCalcResult {
  return {
    items: [
      {
        food_name: name,
        // The catalog name of food_db 7 was not read; the proposal does not store it.
        matched_taco_name: '[food_db 7]',
        matched_taco_id: 7,
        quantity_g: 150,
        kcal: 238.8,
        protein_g: 48.05,
        carbs_g: 0,
        fat_g: 3.72,
        fiber_g: 0,
        similarity: 1,
        source,
        display_qty: 150,
        display_unit: 'g',
      },
    ],
    totals: { kcal: 238.8, protein_g: 48, carbs_g: 0, fat_g: 3.7, fiber_g: 0 },
    warnings: [],
    user_warnings: [],
    audit_warnings: [],
  }
}

type MealInput = Extract<Parameters<typeof proposeRegistration>[2], { kind: 'meal' }>

/** What the app sends for "150 g de frango grelhado no almoco" (see ASSUMED). */
function reportedMeal(name: string): MealInput {
  return {
    kind: 'meal',
    meal_type: 'almoco',
    items: [{ food_name: name, quantity_g: 150, quantity_basis: 'stated' }],
    source: { channel: 'text' },
  }
}

/** The proposal as the app's propose route builds it, from the staging values. */
function appProposal(name: string, source: StagingSource, key: string, at: string) {
  return buildMealPendingProposal(reportedMeal(name), stagingCalculation(name, source), {
    requestKey: key,
    timestamp: at,
    timezone: TIMEZONE,
    localDate: LOCAL_DATE,
  })
}

function seedTheTwoProposals(db: StagingDay, transform: (proposal: Row) => Row = (p) => p) {
  db.addPending(
    REGISTRATION_1,
    '2026-10-04T14:58:03.558Z',
    transform(appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1)),
  )
  db.addPending(
    REGISTRATION_2,
    '2026-10-04T14:59:03.518Z',
    transform(appProposal('frango grelhado no almoco', 'history', KEY_2, SOURCE_2)),
  )
}

async function confirmAt(db: StagingDay, registrationId: string, clock: string) {
  vi.setSystemTime(new Date(clock))
  return confirmRegistration(db.client as never, AUTH as never, registrationId)
}

describe('Defect B (iPhone 2026-10-04) — confirmRegistration with the real registra_refeicao', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('builds the two proposals of the report, marked as created by the app', () => {
    const proposal = appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1)
    expect(proposal).toMatchObject({
      kind: 'meal',
      mealType: 'almoco',
      replace: false,
      registration_origin: 'mobile_app',
      source_provider_message_id: KEY_1,
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
      items: [
        {
          name: 'frango grelhado no almoço',
          quantity_g: 150,
          kcal: 238.8,
          protein_g: 48.05,
          carbs_g: 0,
          fat_g: 3.72,
          food_db_id: 7,
          nutrition_source: 'canonical_fuzzy',
          quantity_basis: 'stated',
          display_qty: 150,
          display_unit: 'g',
          user_kcal: null,
        },
      ],
      totals: { kcal: 238.8, protein_g: 48, carbs_g: 0, fat_g: 3.7 },
    })
  })

  it('exact report: the two proposals confirmed one minute apart are TWO lunch rows and 780 kcal', async () => {
    const db = stagingDay()
    seedTheTwoProposals(db)

    const first = await confirmAt(db, REGISTRATION_1, CONFIRM_1)
    const second = await confirmAt(db, REGISTRATION_2, CONFIRM_2)

    expect(first).toMatchObject({
      id: REGISTRATION_1,
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    })
    expect(second).toMatchObject({
      id: REGISTRATION_2,
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    })
    // The marker stays in the backend: the DTO is a closed list.
    expect(second.proposal).not.toHaveProperty('registration_origin')

    expect(db.lunchRows()).toMatchObject([
      {
        food_name: 'frango grelhado no almoço',
        quantity_g: 150,
        kcal: 238.8,
        source: 'canonical_fuzzy',
        raw_provider_message_id: KEY_1,
        consumed_at: SOURCE_1,
      },
      {
        food_name: 'frango grelhado no almoco',
        quantity_g: 150,
        kcal: 238.8,
        source: 'history',
        raw_provider_message_id: KEY_2,
        consumed_at: SOURCE_2,
        created_at: CONFIRM_2,
      },
    ])
    expect(db.snapshot).toMatchObject({
      calories_consumed: 780,
      protein_g: 107.08,
      exercise_calories: 322,
      calories_target: 2980,
      protein_target: 144,
    })
    expect(db.rpcCalls.map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic',
    ])
    expect(db.eventNames()).toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.eventNames()).not.toContain('tool.replace_implicit_detected')
    expect(db.eventNames()).not.toContain('mobile.registration.implicit_replace')

    // The same registration again (double tap, retry after a lost response).
    const writes = db.rpcCalls.length
    const replay = await confirmAt(db, REGISTRATION_2, '2026-10-04T14:59:40.000Z')
    expect(replay).toMatchObject({ id: REGISTRATION_2, already_confirmed: true })
    expect(db.rpcCalls).toHaveLength(writes)
    expect(db.lunchRows()).toHaveLength(2)
    expect(db.snapshot.calories_consumed).toBe(780)
  })

  it('a pending WITHOUT the marker keeps the previous path, as observed on staging (one row, 541), and is measured', async () => {
    const db = stagingDay()
    seedTheTwoProposals(db, (proposal) => {
      const { registration_origin: _marker, ...legacy } = proposal
      return legacy
    })

    await confirmAt(db, REGISTRATION_1, CONFIRM_1)
    const second = await confirmAt(db, REGISTRATION_2, CONFIRM_2)

    // Not fixed for such a pending (declared in the header): the app is still
    // told "confirmed" while the first row is gone.
    expect(second).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: false })
    expect(db.lunchRows()).toMatchObject([
      { food_name: 'frango grelhado no almoco', created_at: CONFIRM_2, consumed_at: SOURCE_2 },
    ])
    expect(db.snapshot).toMatchObject({
      calories_consumed: 541,
      protein_g: 59.03,
      carbs_g: 47.32,
      fat_g: 10.27,
      daily_balance: -2761,
    })
    expect(db.events.filter((event) => event.event.startsWith('mobile.'))).toEqual([
      {
        user_id: USER_ID,
        event: 'mobile.registration.implicit_replace',
        properties: {
          registration_id: REGISTRATION_2,
          replaced_count: 1,
          kcal_removed: 239,
          cross_from: null,
          additive_confirmation: false,
        },
      },
    ])
  })
})

describe('Defect B (iPhone 2026-10-04) — what confirmRegistration passes to the tool', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('A · a proposal built by the app is confirmed as an additive, text-free, replace=false registration', async () => {
    const execute = vi.spyOn(registraRefeicao, 'execute').mockResolvedValue({ success: true })
    const db = stagingDay()
    seedTheTwoProposals(db)

    await confirmAt(db, REGISTRATION_2, CONFIRM_2)

    expect(execute).toHaveBeenCalledTimes(1)
    const [args, ctx] = execute.mock.calls[0] ?? []
    expect(args).toMatchObject({
      meal_type: 'almoco',
      replace: false,
      consumed_date: LOCAL_DATE,
      items: [{ food_name: 'frango grelhado no almoco', quantity_g: 150, kcal: 238.8 }],
    })
    expect(args).not.toHaveProperty('corrections')
    expect(ctx).toMatchObject({
      userId: USER_ID,
      userWpp: '',
      userTimezone: TIMEZONE,
      additiveConfirmation: true,
      trustMealType: true,
      providerMessageId: KEY_2,
      referenceTimestamp: new Date(SOURCE_2),
    })
    expect(ctx).not.toHaveProperty('currentUserText')
    expect(ctx).not.toHaveProperty('recentUserMessages')
  })

  it('B · a pending created on WhatsApp (no marker, replace + replace_evidence) is NOT confirmed as additive', async () => {
    const execute = vi.spyOn(registraRefeicao, 'execute').mockResolvedValue({ success: true })
    const db = stagingDay()
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', {
      kind: 'meal',
      mealType: 'almoco',
      items: [
        {
          name: 'frango grelhado',
          food_db_id: 7,
          nutrition_source: 'canonical_fuzzy',
          quantity_g: 150,
          kcal: 238.8,
          protein_g: 48.05,
          carbs_g: 0,
          fat_g: 3.72,
        },
      ],
      totals: { kcal: 238.8, protein_g: 48, carbs_g: 0, fat_g: 3.7 },
      sourceContentType: 'text',
      source_provider_message_id: 'wamid.HBgNNTUxMTkwMDAwMDAwMA',
      source_text: 'corrige, eram 150 g de frango grelhado',
      express_eligible: false,
      replace: true,
      replace_evidence: { llm_requested_replace: true, pending_context_is_authorization: false },
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
    })

    await confirmAt(db, REGISTRATION_1, CONFIRM_1)

    expect(execute).toHaveBeenCalledTimes(1)
    const [, ctx] = execute.mock.calls[0] ?? []
    expect(ctx).toMatchObject({
      trustMealType: true,
      providerMessageId: 'wamid.HBgNNTUxMTkwMDAwMDAwMA',
    })
    expect(ctx).not.toHaveProperty('additiveConfirmation')
  })
})

describe('Defect B review — the event of the BFF carries no free text', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
  })
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it.each([
    ['lanche', 'lanche'],
    ['frango grelhado que a paciente digitou', null],
  ])('cross_from %j is recorded as %j, next to ids and counts only', async (fromTool, recorded) => {
    vi.spyOn(registraRefeicao, 'execute').mockResolvedValue({
      success: true,
      replaced: { count: 1, kcal_removed: 239, cross_from: fromTool },
    })
    const db = stagingDay()
    seedTheTwoProposals(db)

    await confirmAt(db, REGISTRATION_2, CONFIRM_2)

    expect(db.events).toEqual([
      {
        user_id: USER_ID,
        event: 'mobile.registration.implicit_replace',
        properties: {
          registration_id: REGISTRATION_2,
          replaced_count: 1,
          kcal_removed: 239,
          cross_from: recorded,
          additive_confirmation: true,
        },
      },
    ])
  })
})

const KEY_EDIT = '0b9f6f0e-58a1-4a10-9d55-1500100000e3'
const EDIT_CLOCK = '2026-10-04T15:00:10.000Z'

type MealEditInput = Extract<Parameters<typeof editRegistration>[3], { kind: 'meal' }>

/** What the patient sends when fixing the grams in the app: one name, 200 g. */
const EDIT_TO_200_G: MealEditInput = {
  kind: 'meal',
  meal_type: 'almoco',
  items: [{ food_name: 'frango grelhado no almoço', quantity_g: 200, quantity_basis: 'stated' }],
  source: { channel: 'text' },
}

function calculated(
  name: string,
  quantity_g: number,
  kcal: number,
  protein_g: number,
  carbs_g: number,
  fat_g: number,
  food_db_id: number | null,
): MealCalcResult['items'][number] {
  return {
    food_name: name,
    matched_taco_name: name,
    matched_taco_id: food_db_id,
    quantity_g,
    kcal,
    protein_g,
    carbs_g,
    fat_g,
    fiber_g: 0,
    similarity: 1,
    source: food_db_id == null ? 'llm_estimate' : 'canonical_fuzzy',
    display_qty: quantity_g,
    display_unit: 'g',
  }
}

/** Stands in for the catalog: the edit recalculates to exactly these items. */
function catalogAnswers(items: MealCalcResult['items']) {
  const sum = (pick: (item: MealCalcResult['items'][number]) => number) =>
    Math.round(items.reduce((total, item) => total + pick(item), 0) * 10) / 10
  vi.mocked(calcMealMacros).mockResolvedValue({
    items,
    totals: {
      kcal: sum((item) => item.kcal),
      protein_g: sum((item) => item.protein_g),
      carbs_g: sum((item) => item.carbs_g),
      fat_g: sum((item) => item.fat_g),
      fiber_g: 0,
    },
    warnings: [],
    user_warnings: [],
    audit_warnings: [],
  })
}

const CHICKEN_200_G = calculated('frango grelhado no almoço', 200, 318.4, 64.07, 0, 4.96, 7)

async function editAt(
  db: StagingDay,
  registrationId: string,
  input: Parameters<typeof editRegistration>[3],
  clock = EDIT_CLOCK,
  key = KEY_EDIT,
) {
  vi.setSystemTime(new Date(clock))
  return editRegistration(db.client as never, AUTH as never, registrationId, input, key)
}

describe('Defect B review — the tool wrote and the pending→confirmed UPDATE failed', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.mocked(calcMealMacros).mockReset()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  /** The meal is written under KEY_1 and the pending still says "pending". */
  async function writtenButStillPending() {
    const db = stagingDay()
    db.addPending(
      REGISTRATION_1,
      '2026-10-04T14:58:03.558Z',
      appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1),
    )
    db.failures.confirmTransitions = 1
    await expect(confirmAt(db, REGISTRATION_1, CONFIRM_1)).rejects.toMatchObject({
      status: 500,
      code: 'registration_confirmation_failed',
    })
    expect(db.pending(REGISTRATION_1).status).toBe('pending')
    expect(db.lunchRows()).toMatchObject([{ quantity_g: 150, raw_provider_message_id: KEY_1 }])
    expect(db.snapshot.calories_consumed).toBe(541)
    return db
  }

  it('the edit is refused with 409 registration_already_confirmed, the pending is closed, and the day holds ONE meal', async () => {
    const db = await writtenButStillPending()
    catalogAnswers([CHICKEN_200_G])

    // Not `registration_not_pending`: that is the code the iPhone answers by
    // proposing the draft again, which would write the meal a second time.
    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
      message: 'Este registro já foi salvo e não pode mais ser editado.',
    })

    // Refused before anything is recalculated: no new key, no new proposal.
    expect(calcMealMacros).not.toHaveBeenCalled()
    expect(db.pending(REGISTRATION_1)).toMatchObject({
      status: 'confirmed',
      resolved_at: EDIT_CLOCK,
    })
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({
      source_provider_message_id: KEY_1,
      items: [{ quantity_g: 150 }],
    })

    const later = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(later).toMatchObject({
      id: REGISTRATION_1,
      status: 'confirmed',
      already_confirmed: true,
    })
    // One write in the whole scenario. Before the guard: 150 g + 200 g, 859 kcal.
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.lunchRows()).toMatchObject([
      { food_name: 'frango grelhado no almoço', quantity_g: 150, raw_provider_message_id: KEY_1 },
    ])
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it('iPhone sequence with the real tool: confirm fails at the transition → PATCH refused → "Tentar novamente" → Confirmar: ONE row, 541 kcal', async () => {
    // 1. Confirmar: the tool writes, the pending→confirmed UPDATE fails (500).
    const db = await writtenButStillPending()
    catalogAnswers([CHICKEN_200_G])
    const refusals: Array<{ status: number; code: string }> = []
    const refused = async (step: Promise<unknown>) => {
      const error = await step.then(
        () => null,
        (reason: { status: number; code: string }) => reason,
      )
      if (!error) throw new Error('the PATCH was accepted')
      refusals.push({ status: error.status, code: error.code })
    }

    // 2. The patient fixes the grams instead of retrying: PATCH, 200 g.
    await refused(editAt(db, REGISTRATION_1, EDIT_TO_200_G))
    expect(db.pending(REGISTRATION_1)).toMatchObject({
      status: 'confirmed',
      resolved_at: EDIT_CLOCK,
    })

    // 3. "Tentar novamente" resends the SAME PATCH with the same key (a
    //    refused request releases its idempotency claim, so it runs again).
    //    The pending now reads "confirmed": the answer must stay the same.
    await refused(editAt(db, REGISTRATION_1, EDIT_TO_200_G, '2026-10-04T15:00:20.000Z'))

    // Neither step answers what the iPhone turns into "Criar nova proposta"
    // (409 registration_not_pending, or 410).
    expect(refusals).toEqual([
      { status: 409, code: 'registration_already_confirmed' },
      { status: 409, code: 'registration_already_confirmed' },
    ])
    expect(calcMealMacros).not.toHaveBeenCalled()

    // 4. The proposal is still on screen; Confirmar closes the sheet.
    const confirmed = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(confirmed).toMatchObject({
      id: REGISTRATION_1,
      status: 'confirmed',
      already_confirmed: true,
    })

    // One pending, one write, one row: 301.9 + 238.8 = 540.7 → 541.
    expect(db.pendings).toHaveLength(1)
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.lunchRows()).toMatchObject([
      { food_name: 'frango grelhado no almoço', quantity_g: 150, raw_provider_message_id: KEY_1 },
    ])
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it('the confirm answer was lost and the pending IS confirmed: the PATCH gets the same code, Confirmar gets already_confirmed', async () => {
    const db = stagingDay()
    db.addPending(
      REGISTRATION_1,
      '2026-10-04T14:58:03.558Z',
      appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1),
    )
    // The app never saw this answer (timeout): it still shows the proposal.
    await confirmAt(db, REGISTRATION_1, CONFIRM_1)
    expect(db.pending(REGISTRATION_1).status).toBe('confirmed')
    catalogAnswers([CHICKEN_200_G])

    // Before: 409 registration_not_pending → new proposal → second row, 780.
    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
    })
    expect(calcMealMacros).not.toHaveBeenCalled()
    expect(db.pending(REGISTRATION_1)).toMatchObject({
      status: 'confirmed',
      resolved_at: CONFIRM_1,
    })

    const again = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(again).toMatchObject({ id: REGISTRATION_1, already_confirmed: true })
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.lunchRows()).toHaveLength(1)
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it.each([
    'cancelled',
    'expired',
  ])('a %s pending keeps 409 registration_not_pending: there a new proposal is the right way out', async (status) => {
    const db = stagingDay()
    db.addPending(
      REGISTRATION_1,
      '2026-10-04T14:58:03.558Z',
      appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1),
    )
    db.pending(REGISTRATION_1).status = status
    catalogAnswers([CHICKEN_200_G])

    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 409,
      code: 'registration_not_pending',
    })
    expect(db.pending(REGISTRATION_1).status).toBe(status)
    expect(db.lunchRows()).toHaveLength(0)
  })

  it('declared, not fixed: past expires_at the PATCH still answers 410 before the guard runs, even when the meal is written', async () => {
    const db = await writtenButStillPending()
    catalogAnswers([CHICKEN_200_G])

    await expect(
      editAt(db, REGISTRATION_1, EDIT_TO_200_G, '2026-10-05T14:58:03.558Z'),
    ).rejects.toMatchObject({ status: 410, code: 'registration_expired' })
    expect(db.pending(REGISTRATION_1).status).toBe('pending')
    expect(db.lunchRows()).toHaveLength(1)
  })

  it('the UPDATE fails again during the edit: still refused, the key is kept, and the next confirm is deduped', async () => {
    const db = await writtenButStillPending()
    catalogAnswers([CHICKEN_200_G])
    db.failures.confirmTransitions = 1

    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 500,
      code: 'registration_confirmation_failed',
    })
    expect(calcMealMacros).not.toHaveBeenCalled()
    expect(db.pending(REGISTRATION_1).status).toBe('pending')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({ source_provider_message_id: KEY_1 })

    const later = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(later).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: true })
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.lunchRows()).toHaveLength(1)
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it('the guard cannot read meal_logs: the edit is refused (500) instead of accepted blind', async () => {
    const db = await writtenButStillPending()
    catalogAnswers([CHICKEN_200_G])
    db.failures.writtenLookup = true

    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 500,
      code: 'registration_lookup_failed',
    })
    expect(calcMealMacros).not.toHaveBeenCalled()
    expect(db.pending(REGISTRATION_1).status).toBe('pending')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({ source_provider_message_id: KEY_1 })
    expect(db.lunchRows()).toHaveLength(1)
  })

  it('a workout already written under the pending key and type is closed the same way, with no origin marker; another type under the same key is not', async () => {
    const db = stagingDay()
    // As buildWorkoutPendingProposal stores it: a workout carries no
    // `registration_origin`, so the workout guard does not depend on one.
    const workoutProposal = {
      kind: 'workout',
      workoutType: 'musculacao',
      durationMin: 50,
      kcalEst: 322,
      intensity: 'moderada',
      sourceContentType: 'mobile',
      source_provider_message_id: KEY_1,
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
      express_eligible: false,
    }
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', workoutProposal)
    db.addPending(REGISTRATION_2, '2026-10-04T14:59:03.518Z', {
      ...workoutProposal,
      workoutType: 'corrida',
    })
    db.workouts.push({
      id: 'workout-1',
      user_id: USER_ID,
      workout_type: 'musculacao',
      raw_provider_message_id: KEY_1,
    })
    const edit = {
      kind: 'workout',
      workout_type: 'musculacao',
      duration_min: 60,
      intensity: 'moderada',
    } as const

    await expect(editAt(db, REGISTRATION_1, edit)).rejects.toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
    })
    expect(db.pending(REGISTRATION_1).status).toBe('confirmed')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({ durationMin: 50 })

    // `registra_treino` is idempotent by key + type, so a row of another type
    // does not mean this pending was written: the edit goes through.
    const edited = await editAt(db, REGISTRATION_2, { ...edit, workout_type: 'corrida' })
    expect(edited).toMatchObject({ id: REGISTRATION_2, status: 'pending' })
    expect(db.storedProposal(REGISTRATION_2)).toMatchObject({
      durationMin: 60,
      source_provider_message_id: KEY_EDIT,
    })
  })
})

describe('Defect B review — an edit keeps the origin of the pending it edits', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.mocked(calcMealMacros).mockReset()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('a pending the app created keeps the marker after the edit and is confirmed as a NEW meal (150 g + 200 g, 859 kcal)', async () => {
    const db = stagingDay()
    seedTheTwoProposals(db)
    await confirmAt(db, REGISTRATION_1, CONFIRM_1)
    catalogAnswers([CHICKEN_200_G])

    const edited = await editAt(db, REGISTRATION_2, EDIT_TO_200_G, '2026-10-04T14:59:20.000Z')

    expect(edited).toMatchObject({ id: REGISTRATION_2, status: 'pending' })
    expect(edited.proposal).not.toHaveProperty('registration_origin')
    expect(db.storedProposal(REGISTRATION_2)).toMatchObject({
      registration_origin: 'mobile_app',
      replace: false,
      source_provider_message_id: KEY_EDIT,
      items: [{ name: 'frango grelhado no almoço', quantity_g: 200, kcal: 318.4 }],
    })

    const second = await confirmAt(db, REGISTRATION_2, CONFIRM_2)
    expect(second).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: false })
    expect(db.lunchRows()).toMatchObject([
      { quantity_g: 150, raw_provider_message_id: KEY_1 },
      { quantity_g: 200, raw_provider_message_id: KEY_EDIT },
    ])
    // round(301.9 + 238.8 + 318.4) = 859.
    expect(db.snapshot.calories_consumed).toBe(859)
    expect(db.eventNames()).toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.eventNames()).not.toContain('mobile.registration.implicit_replace')
  })

  it('a correction pending created on WhatsApp stays WITHOUT the marker after an edit through the app API: rice and beans are not doubled (the salame still stays — declared)', async () => {
    const db = stagingDay()
    // The lunch the patient registered on WhatsApp five minutes before.
    const WAMID_LUNCH = 'wamid.ORIGINAL'
    const whatsappLunch = [
      calculated('arroz branco', 100, 128, 2.5, 28.1, 0.2, null),
      calculated('feijão carioca', 80, 61, 3.8, 10.9, 0.4, null),
      calculated('salame', 30, 119, 7.7, 0.9, 9.3, null),
    ]
    for (const [index, item] of whatsappLunch.entries()) {
      db.meals.push({
        id: `whatsapp-lunch-${index + 1}`,
        user_id: USER_ID,
        snapshot_id: SNAPSHOT_ID,
        meal_type: 'almoco',
        food_name: item.food_name,
        food_db_id: null,
        quantity_g: item.quantity_g,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        source: 'llm_estimate',
        consumed_at: '2026-10-04T14:54:00.000Z',
        created_at: '2026-10-04T14:54:20.000Z',
        raw_provider_message_id: WAMID_LUNCH,
      })
    }
    // round(301.9 + 128 + 61 + 119) = 610.
    db.snapshot.calories_consumed = 610
    // "troca salame por calabresa": the pending the WhatsApp pipeline created.
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', {
      kind: 'meal',
      mealType: 'almoco',
      items: [
        {
          name: 'calabresa',
          food_db_id: null,
          nutrition_source: 'llm_estimate',
          quantity_g: 30,
          kcal: 90,
          protein_g: 5.4,
          carbs_g: 0.6,
          fat_g: 7.2,
        },
      ],
      writeItems: [{ food_name: 'calabresa', quantity_g: 30 }],
      corrections: [{ de: 'salame', para: 'calabresa' }],
      totals: { kcal: 90, protein_g: 5.4, carbs_g: 0.6, fat_g: 7.2 },
      sourceContentType: 'text',
      source_provider_message_id: 'wamid.CORRECTION',
      source_text: 'troca salame por calabresa',
      express_eligible: false,
      replace: true,
      replace_evidence: { llm_requested_replace: true, pending_context_is_authorization: false },
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
    })
    const editedLunch = [
      calculated('arroz branco', 100, 128, 2.5, 28.1, 0.2, null),
      calculated('feijão carioca', 80, 61, 3.8, 10.9, 0.4, null),
      calculated('calabresa', 30, 90, 5.4, 0.6, 7.2, null),
    ]
    catalogAnswers(editedLunch)

    await editAt(
      db,
      REGISTRATION_1,
      {
        kind: 'meal',
        meal_type: 'almoco',
        items: editedLunch.map((item) => ({
          food_name: item.food_name,
          quantity_g: item.quantity_g,
        })),
      },
      '2026-10-04T14:58:40.000Z',
    )

    expect(db.storedProposal(REGISTRATION_1)).not.toHaveProperty('registration_origin')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({
      source_provider_message_id: KEY_EDIT,
      items: [{ name: 'arroz branco' }, { name: 'feijão carioca' }, { name: 'calabresa' }],
    })

    const execute = vi.spyOn(registraRefeicao, 'execute')
    const confirmed = await confirmAt(db, REGISTRATION_1, '2026-10-04T14:59:00.000Z')
    const [, ctx] = execute.mock.calls[0] ?? []
    execute.mockRestore()

    expect(confirmed).toMatchObject({ status: 'confirmed', already_confirmed: false })
    expect(ctx).not.toHaveProperty('additiveConfirmation')
    // With the marker stamped by the edit this ended as SIX lunch rows (rice
    // and beans twice). Without it the previous path runs: the rows that
    // overlap (rice, beans) are replaced, as before this PR.
    expect(db.mealWrites().map((call) => [call.fn, call.params.p_replace_log_ids])).toEqual([
      ['register_meal_atomic_scoped', ['whatsapp-lunch-1', 'whatsapp-lunch-2']],
    ])
    // NOT the corrected meal (rice, beans, calabresa): the edit rebuilt the
    // proposal without `corrections`, so the salame is still there. Declared
    // in the header; unchanged by this PR.
    expect(
      db
        .lunchRows()
        .map((row) => `${row.food_name}:${row.quantity_g}`)
        .sort(),
    ).toEqual(['arroz branco:100', 'calabresa:30', 'feijão carioca:80', 'salame:30'])
    // round(301.9 + 128 + 61 + 90 + 119) = 700.
    expect(db.snapshot.calories_consumed).toBe(700)
    expect(db.eventNames()).not.toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.events.filter((event) => event.event.startsWith('mobile.'))).toEqual([
      {
        user_id: USER_ID,
        event: 'mobile.registration.implicit_replace',
        properties: {
          registration_id: REGISTRATION_1,
          replaced_count: 2,
          kcal_removed: 189,
          cross_from: null,
          additive_confirmation: false,
        },
      },
    ])
  })
})

describe('Defect B closure — the two pendings of the report created THROUGH proposeRegistration', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.mocked(calcMealMacros).mockReset()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  /** POST /registrations/propose as the route calls it, on the staging clock. */
  async function proposeAt(
    db: StagingDay,
    name: string,
    source: StagingSource,
    key: string,
    requestedAt: string,
    storedAt: string,
  ) {
    vi.setSystemTime(new Date(requestedAt))
    vi.mocked(calcMealMacros).mockImplementationOnce(async (_client, items) => {
      // The catalog took about a second on staging: the row is stamped after it.
      vi.setSystemTime(new Date(storedAt))
      return stagingCalculation(items[0]?.food_name ?? '', source)
    })
    return proposeRegistration(db.client as never, AUTH as never, reportedMeal(name), key)
  }

  it('"150 g de frango grelhado no almoco" proposed and confirmed twice, one minute apart: both pendings carry the app origin, TWO rows, 780 kcal', async () => {
    const db = stagingDay()

    const first = await proposeAt(
      db,
      'frango grelhado no almoço',
      'canonical_fuzzy',
      KEY_1,
      SOURCE_1,
      '2026-10-04T14:58:03.558Z',
    )

    // The catalog was asked for what the patient sent, for this patient.
    expect(vi.mocked(calcMealMacros).mock.calls[0]?.slice(1)).toEqual([
      [{ food_name: 'frango grelhado no almoço', quantity_g: 150 }],
      'BR',
      USER_ID,
    ])
    // The seam: what proposeRegistration hands to the RPC, and what is stored.
    const firstCall = db.rpcCalls.find((call) => call.fn === 'replace_pending_registration_atomic')
    expect(firstCall?.params).toMatchObject({
      p_user_id: USER_ID,
      p_request_key: KEY_1,
      p_expires_at: '2026-10-05T14:58:03.558Z',
      p_proposal: { kind: 'meal', registration_origin: 'mobile_app' },
    })
    expect(db.pending(first.id)).toMatchObject({
      status: 'pending',
      created_at: '2026-10-04T14:58:03.558Z',
      expires_at: '2026-10-05T14:58:03.558Z',
    })
    expect(db.storedProposal(first.id)).toMatchObject({
      kind: 'meal',
      mealType: 'almoco',
      replace: false,
      registration_origin: 'mobile_app',
      sourceContentType: 'text',
      source_provider_message_id: KEY_1,
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
      items: [
        {
          name: 'frango grelhado no almoço',
          quantity_g: 150,
          kcal: 238.8,
          protein_g: 48.05,
          carbs_g: 0,
          fat_g: 3.72,
          food_db_id: 7,
          nutrition_source: 'canonical_fuzzy',
          quantity_basis: 'stated',
          display_qty: 150,
          display_unit: 'g',
          user_kcal: null,
        },
      ],
      totals: { kcal: 238.8, protein_g: 48, carbs_g: 0, fat_g: 3.7 },
    })
    // The marker stays in the backend: the DTO is a closed list.
    expect(first).toMatchObject({ status: 'pending', proposal: { kind: 'meal' } })
    expect(first.proposal).not.toHaveProperty('registration_origin')

    const firstConfirm = await confirmAt(db, first.id, CONFIRM_1)

    const second = await proposeAt(
      db,
      'frango grelhado no almoco',
      'history',
      KEY_2,
      SOURCE_2,
      '2026-10-04T14:59:03.518Z',
    )
    expect(second.id).not.toBe(first.id)
    expect(db.pending(first.id).status).toBe('confirmed')
    expect(db.pending(second.id)).toMatchObject({
      status: 'pending',
      created_at: '2026-10-04T14:59:03.518Z',
    })
    expect(db.storedProposal(second.id)).toMatchObject({
      registration_origin: 'mobile_app',
      replace: false,
      source_provider_message_id: KEY_2,
      source_timestamp: SOURCE_2,
      source_local_date: LOCAL_DATE,
      items: [
        {
          name: 'frango grelhado no almoco',
          quantity_g: 150,
          kcal: 238.8,
          food_db_id: 7,
          nutrition_source: 'history',
        },
      ],
    })

    const secondConfirm = await confirmAt(db, second.id, CONFIRM_2)

    expect(firstConfirm).toMatchObject({
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    })
    expect(secondConfirm).toMatchObject({
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    })
    expect(db.lunchRows()).toMatchObject([
      {
        food_name: 'frango grelhado no almoço',
        quantity_g: 150,
        kcal: 238.8,
        source: 'canonical_fuzzy',
        raw_provider_message_id: KEY_1,
        consumed_at: SOURCE_1,
        created_at: CONFIRM_1,
      },
      {
        food_name: 'frango grelhado no almoco',
        quantity_g: 150,
        kcal: 238.8,
        source: 'history',
        raw_provider_message_id: KEY_2,
        consumed_at: SOURCE_2,
        created_at: CONFIRM_2,
      },
    ])
    expect(db.lunchRows()).toHaveLength(2)
    // round(301.9 + 238.8 + 238.8) = 780; on staging this was ONE row and 541.
    expect(db.snapshot).toMatchObject({
      calories_consumed: 780,
      protein_g: 107.08,
      exercise_calories: 322,
      calories_target: 2980,
      protein_target: 144,
    })
    expect(db.mealWrites().map((call) => call.fn)).toEqual([
      'register_meal_atomic',
      'register_meal_atomic',
    ])
    expect(db.eventNames()).toContain('tool.replace_implicit_skipped_additive_confirmation')
    expect(db.eventNames()).not.toContain('mobile.registration.implicit_replace')
  })

  it('the propose request sent again with the same key answers the same pending: one proposal, the marker kept', async () => {
    const db = stagingDay()
    const first = await proposeAt(
      db,
      'frango grelhado no almoço',
      'canonical_fuzzy',
      KEY_1,
      SOURCE_1,
      '2026-10-04T14:58:03.558Z',
    )
    const again = await proposeAt(
      db,
      'frango grelhado no almoço',
      'canonical_fuzzy',
      KEY_1,
      '2026-10-04T14:58:05.000Z',
      '2026-10-04T14:58:06.000Z',
    )

    expect(again.id).toBe(first.id)
    expect(db.pendings).toHaveLength(1)
    expect(db.storedProposal(first.id)).toMatchObject({
      registration_origin: 'mobile_app',
      source_timestamp: SOURCE_1,
    })
  })
})

describe('Defect B review — the edit guard applies only to a meal proposal the app created', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.mocked(calcMealMacros).mockReset()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('WhatsApp message key shared by an express record and a pending of another meal: the PATCH is accepted and the pending stays pending', async () => {
    const db = stagingDay()
    const WAMID = 'wamid.SAME_MESSAGE'
    // "almocei arroz e vou lanchar uma banana": the rice was registered at
    // once (express), the snack became a pending. Both carry the message id.
    db.meals.push({
      id: 'whatsapp-express-1',
      user_id: USER_ID,
      snapshot_id: SNAPSHOT_ID,
      meal_type: 'almoco',
      food_name: 'arroz branco',
      food_db_id: null,
      quantity_g: 100,
      kcal: 128,
      protein_g: 2.5,
      carbs_g: 28.1,
      fat_g: 0.2,
      source: 'llm_estimate',
      consumed_at: '2026-10-04T14:54:00.000Z',
      created_at: '2026-10-04T14:54:20.000Z',
      raw_provider_message_id: WAMID,
    })
    // round(301.9 + 128) = 430.
    db.snapshot.calories_consumed = 430
    db.addPending(REGISTRATION_1, '2026-10-04T14:54:20.000Z', {
      kind: 'meal',
      mealType: 'lanche',
      items: [
        {
          name: 'banana',
          food_db_id: null,
          nutrition_source: 'llm_estimate',
          quantity_g: 100,
          kcal: 92,
          protein_g: 1.3,
          carbs_g: 23.8,
          fat_g: 0.1,
        },
      ],
      totals: { kcal: 92, protein_g: 1.3, carbs_g: 23.8, fat_g: 0.1 },
      sourceContentType: 'text',
      source_provider_message_id: WAMID,
      source_text: 'almocei arroz e vou lanchar uma banana',
      express_eligible: false,
      replace: false,
      source_timestamp: '2026-10-04T14:54:00.000Z',
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
    })
    const banana120 = calculated('banana', 120, 110.4, 1.56, 28.56, 0.12, null)
    catalogAnswers([banana120])
    // The guard does not even read meal_logs for this pending: a read by key
    // would fail here, and the edit goes through.
    db.failures.writtenLookup = true

    const edited = await editAt(db, REGISTRATION_1, {
      kind: 'meal',
      meal_type: 'lanche',
      items: [{ food_name: 'banana', quantity_g: 120 }],
    })

    // With the guard deciding by the key alone this was 409, the pending was
    // closed as "confirmed" and the snack was never written.
    expect(edited).toMatchObject({ id: REGISTRATION_1, status: 'pending' })
    expect(db.pending(REGISTRATION_1)).toMatchObject({ status: 'pending', resolved_at: null })
    expect(db.storedProposal(REGISTRATION_1)).not.toHaveProperty('registration_origin')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({
      mealType: 'lanche',
      source_provider_message_id: KEY_EDIT,
      items: [{ name: 'banana', quantity_g: 120, kcal: 110.4 }],
    })

    // The way out this pending had before this PR still works: the confirm
    // writes the snack, and the rice of the same message is untouched.
    db.failures.writtenLookup = false
    const confirmed = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(confirmed).toMatchObject({
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
    })
    expect(
      db.meals
        .filter((row) => row.meal_type !== 'cafe')
        .map(
          (row) =>
            `${row.meal_type}:${row.food_name}:${row.quantity_g}:${row.raw_provider_message_id}`,
        ),
    ).toEqual([`almoco:arroz branco:100:${WAMID}`, `lanche:banana:120:${KEY_EDIT}`])
    // round(301.9 + 128 + 110.4) = 540.
    expect(db.snapshot.calories_consumed).toBe(540)
  })

  it('declared: a meal pending WITHOUT the marker that was already written keeps the behaviour from before this PR — the edit is accepted', async () => {
    const db = stagingDay()
    const { registration_origin: _marker, ...legacy } = appProposal(
      'frango grelhado no almoço',
      'canonical_fuzzy',
      KEY_1,
      SOURCE_1,
    )
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', legacy)
    db.failures.confirmTransitions = 1
    await expect(confirmAt(db, REGISTRATION_1, CONFIRM_1)).rejects.toMatchObject({
      status: 500,
      code: 'registration_confirmation_failed',
    })
    expect(db.lunchRows()).toMatchObject([{ quantity_g: 150, raw_provider_message_id: KEY_1 }])
    catalogAnswers([CHICKEN_200_G])

    const edited = await editAt(db, REGISTRATION_1, EDIT_TO_200_G)

    expect(edited).toMatchObject({ id: REGISTRATION_1, status: 'pending' })
    expect(db.storedProposal(REGISTRATION_1)).not.toHaveProperty('registration_origin')
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({
      source_provider_message_id: KEY_EDIT,
      items: [{ quantity_g: 200 }],
    })

    // The confirm takes the previous path: inside 30 min the same name is a
    // correction, so the 150 g row is replaced by the 200 g one (not doubled).
    const confirmed = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:30.000Z')
    expect(confirmed).toMatchObject({ status: 'confirmed', already_confirmed: false })
    expect(db.lunchRows()).toMatchObject([{ quantity_g: 200, raw_provider_message_id: KEY_EDIT }])
    expect(db.lunchRows()).toHaveLength(1)
    // round(301.9 + 318.4) = 620.
    expect(db.snapshot.calories_consumed).toBe(620)
  })

  it('the same already-written proposal WITH the marker is refused (the app key belongs to one attempt)', async () => {
    const db = stagingDay()
    db.addPending(
      REGISTRATION_1,
      '2026-10-04T14:58:03.558Z',
      appProposal('frango grelhado no almoço', 'canonical_fuzzy', KEY_1, SOURCE_1),
    )
    db.failures.confirmTransitions = 1
    await expect(confirmAt(db, REGISTRATION_1, CONFIRM_1)).rejects.toMatchObject({ status: 500 })
    catalogAnswers([CHICKEN_200_G])

    await expect(editAt(db, REGISTRATION_1, EDIT_TO_200_G)).rejects.toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
    })
    expect(db.storedProposal(REGISTRATION_1)).toMatchObject({
      registration_origin: 'mobile_app',
      source_provider_message_id: KEY_1,
    })
    expect(db.lunchRows()).toHaveLength(1)
  })
})

const KEY_3 = '0b9f6f0e-58a1-4a10-9d55-1501000000c3'
const CANCEL_CLOCK = '2026-10-04T15:00:20.000Z'
const ALREADY_SAVED_ON_CANCEL = {
  status: 409,
  code: 'registration_already_confirmed',
  message: 'Este registro já foi salvo e não pode mais ser cancelado.',
}

async function cancelAt(db: StagingDay, registrationId: string, clock = CANCEL_CLOCK) {
  vi.setSystemTime(new Date(clock))
  return cancelRegistration(db.client as never, USER_ID, registrationId)
}

/** What a refused request answered; an accepted one fails the test. */
function refusal(step: Promise<unknown>) {
  return step.then(
    () => {
      throw new Error('the request was accepted')
    },
    (reason: { status: number; code: string; message: string }) => ({
      status: reason.status,
      code: reason.code,
      message: reason.message,
    }),
  )
}

describe('Defect B review 3 — Cancelar (DELETE) on a pending whose record is already saved', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.mocked(calcMealMacros).mockReset()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  /** POST /registrations/propose as the route calls it: the app origin is stamped by the seam. */
  async function proposeAt(db: StagingDay, key: string, requestedAt: string) {
    vi.setSystemTime(new Date(requestedAt))
    vi.mocked(calcMealMacros).mockImplementationOnce(async (_client, items) =>
      stagingCalculation(items[0]?.food_name ?? '', 'canonical_fuzzy'),
    )
    return proposeRegistration(
      db.client as never,
      AUTH as never,
      reportedMeal('frango grelhado no almoço'),
      key,
    )
  }

  /** The confirm wrote the lunch and failed at the pending→confirmed UPDATE (500). */
  async function proposedWrittenStillPending() {
    const db = stagingDay()
    const first = await proposeAt(db, KEY_1, SOURCE_1)
    db.failures.confirmTransitions = 1
    await expect(confirmAt(db, first.id, CONFIRM_1)).rejects.toMatchObject({
      status: 500,
      code: 'registration_confirmation_failed',
    })
    expect(db.pending(first.id).status).toBe('pending')
    expect(db.lunchRows()).toHaveLength(1)
    return { db, first }
  }

  function expectOneLunchOf541(db: StagingDay) {
    expect(db.pendings).toHaveLength(1)
    expect(db.mealWrites()).toHaveLength(1)
    expect(db.lunchRows()).toMatchObject([
      { food_name: 'frango grelhado no almoço', quantity_g: 150, raw_provider_message_id: KEY_1 },
    ])
    // 301.9 + 238.8 = 540.7 → 541.
    expect(db.snapshot.calories_consumed).toBe(541)
  }

  it('PB-1 · the confirm answer was lost: PATCH refused → Cancelar refused with the SAME code → "Tentar novamente" → Confirmar: ONE row, 541', async () => {
    const db = stagingDay()
    const first = await proposeAt(db, KEY_1, SOURCE_1)
    expect(db.storedProposal(first.id)).toMatchObject({ registration_origin: 'mobile_app' })
    // The confirm reaches the server and writes; the app times out and still
    // shows the proposal with Editar / Confirmar / Cancelar.
    await confirmAt(db, first.id, CONFIRM_1)
    expect(db.snapshot.calories_consumed).toBe(541)
    catalogAnswers([CHICKEN_200_G])

    expect(await refusal(editAt(db, first.id, EDIT_TO_200_G))).toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
    })

    // Before: 409 registration_not_pending, which the iPhone turns into
    // "Criar nova proposta" → the draft proposed again → second row, 780.
    expect(await refusal(cancelAt(db, first.id))).toEqual(ALREADY_SAVED_ON_CANCEL)
    // "Tentar novamente" resends the same DELETE (a refused request releases
    // its idempotency claim, so it runs again): the answer does not change.
    expect(await refusal(cancelAt(db, first.id, '2026-10-04T15:00:25.000Z'))).toEqual(
      ALREADY_SAVED_ON_CANCEL,
    )
    expect(db.pending(first.id)).toMatchObject({ status: 'confirmed', resolved_at: CONFIRM_1 })

    // The proposal is still on screen; Confirmar closes it without writing.
    const confirmed = await confirmAt(db, first.id, '2026-10-04T15:00:40.000Z')
    expect(confirmed).toMatchObject({ id: first.id, status: 'confirmed', already_confirmed: true })
    expect(calcMealMacros).toHaveBeenCalledTimes(1)
    expectOneLunchOf541(db)
  })

  it('PB-2 · the confirm failed at the transition: PATCH refused (the guard closes the pending) → Cancelar refused → Confirmar: ONE row, 541', async () => {
    const { db, first } = await proposedWrittenStillPending()
    catalogAnswers([CHICKEN_200_G])

    expect(await refusal(editAt(db, first.id, EDIT_TO_200_G))).toMatchObject({
      status: 409,
      code: 'registration_already_confirmed',
    })
    expect(db.pending(first.id)).toMatchObject({ status: 'confirmed', resolved_at: EDIT_CLOCK })

    expect(await refusal(cancelAt(db, first.id))).toEqual(ALREADY_SAVED_ON_CANCEL)
    expect(db.pending(first.id)).toMatchObject({ status: 'confirmed', resolved_at: EDIT_CLOCK })

    const confirmed = await confirmAt(db, first.id, '2026-10-04T15:00:40.000Z')
    expect(confirmed).toMatchObject({ id: first.id, status: 'confirmed', already_confirmed: true })
    expectOneLunchOf541(db)
  })

  it('PB-3 · the confirm failed at the transition and the patient taps Cancelar at once: the pending is closed as CONFIRMED, not cancelled', async () => {
    const { db, first } = await proposedWrittenStillPending()

    // Before: 200, the pending read "cancelled" with the lunch saved, and the
    // next proposal of the same meal wrote it again (780).
    expect(await refusal(cancelAt(db, first.id))).toEqual(ALREADY_SAVED_ON_CANCEL)
    expect(db.pending(first.id)).toMatchObject({ status: 'confirmed', resolved_at: CANCEL_CLOCK })
    expect(db.storedProposal(first.id)).toMatchObject({ source_provider_message_id: KEY_1 })

    const confirmed = await confirmAt(db, first.id, '2026-10-04T15:00:40.000Z')
    expect(confirmed).toMatchObject({ id: first.id, status: 'confirmed', already_confirmed: true })
    expectOneLunchOf541(db)
  })

  it('a pending that was never written is still cancelled (200), writes nothing, and a new proposal is the way out', async () => {
    const db = stagingDay()
    const first = await proposeAt(db, KEY_1, SOURCE_1)

    const cancelled = await cancelAt(db, first.id)
    expect(cancelled).toMatchObject({
      id: first.id,
      status: 'cancelled',
      resolved_at: CANCEL_CLOCK,
    })
    expect(db.pending(first.id)).toMatchObject({ status: 'cancelled', resolved_at: CANCEL_CLOCK })
    expect(db.mealWrites()).toHaveLength(0)
    expect(db.lunchRows()).toHaveLength(0)
    expect(db.snapshot.calories_consumed).toBe(302)

    // The DELETE sent again answers the same pending; nothing else moves.
    const again = await cancelAt(db, first.id, '2026-10-04T15:00:25.000Z')
    expect(again).toMatchObject({ id: first.id, status: 'cancelled', resolved_at: CANCEL_CLOCK })
    // Here `registration_not_pending` is right: there is nothing saved.
    expect(await refusal(confirmAt(db, first.id, '2026-10-04T15:00:27.000Z'))).toMatchObject({
      status: 409,
      code: 'registration_not_pending',
    })
    expect(db.mealWrites()).toHaveLength(0)

    const second = await proposeAt(db, KEY_3, '2026-10-04T15:00:30.000Z')
    expect(second.id).not.toBe(first.id)
    await confirmAt(db, second.id, '2026-10-04T15:00:40.000Z')
    expect(db.lunchRows()).toMatchObject([{ quantity_g: 150, raw_provider_message_id: KEY_3 }])
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it('an expired pending keeps 409 registration_not_pending on Cancelar; a cancelled one keeps answering 200', async () => {
    const db = stagingDay()
    const first = await proposeAt(db, KEY_1, SOURCE_1)
    db.pending(first.id).status = 'expired'

    expect(await refusal(cancelAt(db, first.id))).toMatchObject({
      status: 409,
      code: 'registration_not_pending',
    })
    expect(db.pending(first.id).status).toBe('expired')

    db.pending(first.id).status = 'cancelled'
    expect(await cancelAt(db, first.id)).toMatchObject({ id: first.id, status: 'cancelled' })
    expect(db.lunchRows()).toHaveLength(0)
  })

  it('the guard cannot read meal_logs: Cancelar is refused (500) instead of cancelling blind; the retry closes the pending as confirmed', async () => {
    const { db, first } = await proposedWrittenStillPending()
    db.failures.writtenLookup = true

    expect(await refusal(cancelAt(db, first.id))).toMatchObject({
      status: 500,
      code: 'registration_lookup_failed',
    })
    expect(db.pending(first.id)).toMatchObject({ status: 'pending', resolved_at: null })

    db.failures.writtenLookup = false
    expect(await refusal(cancelAt(db, first.id, '2026-10-04T15:00:25.000Z'))).toEqual(
      ALREADY_SAVED_ON_CANCEL,
    )
    expect(db.pending(first.id).status).toBe('confirmed')
    expectOneLunchOf541(db)
  })

  it('the pending→confirmed UPDATE fails again during Cancelar: refused (500), never cancelled, and the next confirm is deduped', async () => {
    const { db, first } = await proposedWrittenStillPending()
    db.failures.confirmTransitions = 1

    expect(await refusal(cancelAt(db, first.id))).toMatchObject({
      status: 500,
      code: 'registration_confirmation_failed',
    })
    expect(db.pending(first.id)).toMatchObject({ status: 'pending', resolved_at: null })

    const later = await confirmAt(db, first.id, '2026-10-04T15:00:40.000Z')
    expect(later).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: true })
    expectOneLunchOf541(db)
  })

  it('a written pending past expires_at is closed as confirmed by Cancelar too (the DELETE never checked the expiry)', async () => {
    const { db, first } = await proposedWrittenStillPending()

    expect(await refusal(cancelAt(db, first.id, '2026-10-05T14:58:03.558Z'))).toEqual(
      ALREADY_SAVED_ON_CANCEL,
    )
    expect(db.pending(first.id).status).toBe('confirmed')
    expect(db.lunchRows()).toHaveLength(1)
  })

  it('WhatsApp message key shared by an express record and a pending of another meal: Cancelar cancels as before and the guard does not read meal_logs', async () => {
    const db = stagingDay()
    const WAMID = 'wamid.SAME_MESSAGE'
    // The scenario of block 6: the rice was registered at once (express), the
    // snack became a pending, and both carry the message id.
    db.meals.push({
      id: 'whatsapp-express-1',
      user_id: USER_ID,
      snapshot_id: SNAPSHOT_ID,
      meal_type: 'almoco',
      food_name: 'arroz branco',
      food_db_id: null,
      quantity_g: 100,
      kcal: 128,
      protein_g: 2.5,
      carbs_g: 28.1,
      fat_g: 0.2,
      source: 'llm_estimate',
      consumed_at: '2026-10-04T14:54:00.000Z',
      created_at: '2026-10-04T14:54:20.000Z',
      raw_provider_message_id: WAMID,
    })
    db.addPending(REGISTRATION_1, '2026-10-04T14:54:20.000Z', {
      kind: 'meal',
      mealType: 'lanche',
      items: [
        {
          name: 'banana',
          food_db_id: null,
          nutrition_source: 'llm_estimate',
          quantity_g: 100,
          kcal: 92,
          protein_g: 1.3,
          carbs_g: 23.8,
          fat_g: 0.1,
        },
      ],
      totals: { kcal: 92, protein_g: 1.3, carbs_g: 23.8, fat_g: 0.1 },
      sourceContentType: 'text',
      source_provider_message_id: WAMID,
      express_eligible: false,
      replace: false,
      source_timestamp: '2026-10-04T14:54:00.000Z',
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
    })
    // A read by key would fail here: the guard skips a pending without the marker.
    db.failures.writtenLookup = true

    // With the guard deciding by the key alone the snack nobody ate would be
    // closed as "confirmed" and the patient could not cancel it.
    const cancelled = await cancelAt(db, REGISTRATION_1)
    expect(cancelled).toMatchObject({ id: REGISTRATION_1, status: 'cancelled' })
    expect(db.pending(REGISTRATION_1)).toMatchObject({
      status: 'cancelled',
      resolved_at: CANCEL_CLOCK,
    })
    expect(db.meals.filter((row) => row.raw_provider_message_id === WAMID)).toHaveLength(1)
  })

  it('declared: a meal pending WITHOUT the marker that was already written is cancelled as before this PR — "cancelled" with the meal saved', async () => {
    const db = stagingDay()
    const { registration_origin: _marker, ...legacy } = appProposal(
      'frango grelhado no almoço',
      'canonical_fuzzy',
      KEY_1,
      SOURCE_1,
    )
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', legacy)
    db.failures.confirmTransitions = 1
    await expect(confirmAt(db, REGISTRATION_1, CONFIRM_1)).rejects.toMatchObject({ status: 500 })
    expect(db.lunchRows()).toHaveLength(1)

    const cancelled = await cancelAt(db, REGISTRATION_1)
    expect(cancelled).toMatchObject({ id: REGISTRATION_1, status: 'cancelled' })
    expect(db.lunchRows()).toHaveLength(1)
    expect(db.snapshot.calories_consumed).toBe(541)
  })

  it('declared: the refusal is all the server does — the same meal proposed again after it (a client that ignores the code, or the patient typing it again) is a second row, 780', async () => {
    const db = stagingDay()
    const first = await proposeAt(db, KEY_1, SOURCE_1)
    await confirmAt(db, first.id, CONFIRM_1)
    expect(await refusal(cancelAt(db, first.id))).toEqual(ALREADY_SAVED_ON_CANCEL)

    const second = await proposeAt(db, KEY_3, '2026-10-04T15:00:30.000Z')
    const confirmed = await confirmAt(db, second.id, '2026-10-04T15:00:40.000Z')

    expect(confirmed).toMatchObject({ already_confirmed: false, deduped: false })
    expect(db.lunchRows().map((row) => row.raw_provider_message_id)).toEqual([KEY_1, KEY_3])
    // 301.9 + 238.8 + 238.8 = 779.5 → 780.
    expect(db.snapshot.calories_consumed).toBe(780)
  })

  it('workouts follow the same rule: confirmed, or written under the pending key and type → refused and closed as confirmed; another type under the key → cancelled', async () => {
    const db = stagingDay()
    // As buildWorkoutPendingProposal stores it: no `registration_origin`, so
    // the workout guard holds for every origin (key + type).
    const workoutProposal = {
      kind: 'workout',
      workoutType: 'musculacao',
      durationMin: 50,
      kcalEst: 322,
      intensity: 'moderada',
      sourceContentType: 'mobile',
      source_provider_message_id: KEY_1,
      source_timestamp: SOURCE_1,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
      express_eligible: false,
    }
    const REGISTRATION_3 = '0b9f6f0e-0000-4000-8000-000000150003'
    db.addPending(REGISTRATION_1, '2026-10-04T14:58:03.558Z', workoutProposal)
    db.addPending(REGISTRATION_2, '2026-10-04T14:59:03.518Z', {
      ...workoutProposal,
      workoutType: 'corrida',
    })
    db.addPending(REGISTRATION_3, '2026-10-04T15:00:03.000Z', {
      ...workoutProposal,
      source_provider_message_id: KEY_2,
    })
    db.pending(REGISTRATION_3).status = 'confirmed'
    db.workouts.push({
      id: 'workout-1',
      user_id: USER_ID,
      workout_type: 'musculacao',
      raw_provider_message_id: KEY_1,
    })

    // Written, the pending still "pending": closed as confirmed.
    expect(await refusal(cancelAt(db, REGISTRATION_1))).toEqual(ALREADY_SAVED_ON_CANCEL)
    expect(db.pending(REGISTRATION_1)).toMatchObject({
      status: 'confirmed',
      resolved_at: CANCEL_CLOCK,
    })
    // Already confirmed: same code, nothing changes.
    expect(await refusal(cancelAt(db, REGISTRATION_3))).toEqual(ALREADY_SAVED_ON_CANCEL)
    expect(db.pending(REGISTRATION_3).status).toBe('confirmed')
    // A row of another type under the same key is not this pending's workout.
    expect(await cancelAt(db, REGISTRATION_2)).toMatchObject({
      id: REGISTRATION_2,
      status: 'cancelled',
    })

    const confirmed = await confirmAt(db, REGISTRATION_1, '2026-10-04T15:00:40.000Z')
    expect(confirmed).toMatchObject({ id: REGISTRATION_1, already_confirmed: true })
    expect(db.workouts).toHaveLength(1)
  })
})
