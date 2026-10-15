/**
 * The workout type typed in the app (review of 2026-10-04) — golden of the
 * mobile API end. In the iPhone app the type is a free-text field; the API
 * handed it as typed to `calc_workout_kcal`, which only lowercases its
 * argument, so "Natação" missed the slug `natacao` and was charged the
 * generic 'outro' rate with no notice.
 *
 * THE REPORTED CASE, exact: "Natação", 40 min, moderada, 70 kg.
 *   before: 'natação' is not a slug → 'outro' 6.00 × 40 × 1.0 × 70/70 = 240
 *   now:    lookup slug `natacao`     → 10.00 × 40 × 1.0 × 70/70      = 400
 *
 * Every block runs `proposeRegistration`, `editRegistration` and
 * `confirmRegistration` as exported, with the REAL `registra_treino` of
 * `@mpp/agent` (nothing in that package is replaced) against an in-memory
 * database. The confirm is under test on purpose: the tool calculates again
 * when it writes, with the type it is given, so a fix at the proposal alone
 * would show 400 and store 240. The confirm hands the tool the catalogue slug
 * in an optional typed field of its context (`workoutKcalLookupSlug`), read
 * only by the kcal lookup; the database client it hands over is the one it
 * received, unwrapped. The WhatsApp side of that field is locked in
 * packages/agent/src/tools-workout-kcal-lookup.test.ts.
 *
 * READ FROM STAGING (2026-10-04, read-only): the 58 rows of
 * `public.workout_types` (slug, display_name, kcal_per_min; all active), equal
 * to the migrations 20260504165600 and 20260504172500 (the last block of this
 * file compares the fixture with the two files), and the definition of
 * `public.calc_workout_kcal(text, integer, text, numeric)`, equal to the one
 * in 20260504165600.
 *
 * ASSUMED — declared: the reviewer gave the typed type, the duration, the
 * intensity, the weight and the two kcal values; nothing else. User id,
 * request keys, timezone, the clock, a profile that holds only the weight
 * (so the day has no calorie target) and every other table being empty are
 * synthetic. The three RPCs are emulated in TypeScript from the migrations
 * 20260504165600 (`calc_workout_kcal`), 20260711202000
 * (`register_workout_atomic`) and 20260712205000
 * (`replace_pending_registration_atomic`), read and not executed. The
 * inactive slug, the two slugs under one display name and the failed
 * catalogue read are injected in the in-memory database: none exists on
 * staging.
 *
 * Declared pendencies (CLAUDE.md criterion 2); every line is in
 * docs/CALCULO-MPP.md §2d, identical.
 *
 * > RC W — cenário esporte que o catálogo não tem ("Capoeira", "Surfe") NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: taxa genérica 'outro' (6,0 kcal/min; 40 min, moderada, 70 kg = 240 kcal), sem aviso na resposta nem na tela, e o treino entra em `exercise_calories`. Travado no teste.
 * > RC W — cenário outra palavra para uma atividade que o catálogo tem ("Bike" para `bicicleta`, "Academia", "Futsal", "Natação no mar", duas atividades no mesmo campo, travessão ou outro separador como "Jiu–jitsu" e "jiu.jitsu") NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem sinônimo e sem busca aproximada: taxa genérica, em silêncio. No WhatsApp o modelo escolhe o slug; no app ninguém escolhe. "Bike" e "Natação no mar" travados no teste.
 * > RC W — cenário WhatsApp (o modelo manda para `registra_treino` um tipo com acento, espaço ou fora do catálogo) NÃO coberto nesta PR (pendência da audit 2026-10-04). O pipeline não foi tocado e nunca define o campo `workoutKcalLookupSlug` do contexto: sem ele a ferramenta passa o tipo como veio e a função cai em 'outro'.
 * > RC W — cenário treinos e propostas gravados antes desta mudança NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill: a "Natação" de 240 kcal segue em `workout_logs`, em `exercise_calories` do dia e no bloco já creditado.
 * > RC W — cenário fechamento do dia (crédito do bloco 7.700) com o treino recalculado NÃO coberto nesta PR (pendência da audit 2026-10-04). O teste vai até `workout_logs.estimated_kcal` e `daily_snapshots.exercise_calories` (400); o closer não é executado e nenhum número de bloco é afirmado.
 * > RC W — cenário catálogo `workout_types` de PRODUÇÃO NÃO coberto nesta PR (pendência da audit 2026-10-04). Não foi lido. Taxas e nomes são os do staging em 2026-10-04 (58 linhas ativas, iguais às migrations 20260504165600 e 20260504172500).
 * > RC W — cenário tipo gravado como texto livre ("Natação" e "natacao" são tipos diferentes para a idempotência e para o descarte de treino idêntico em 6 h; histórico e tela mostram o que foi digitado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado de propósito: o valor gravado não muda nesta PR.
 * > RC W — cenário peso do perfil ou catálogo alterados entre a proposta e a confirmação NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: a confirmação recalcula, e o kcal gravado pode diferir do kcal mostrado na proposta.
 * > RC W — cenário uma leitura a mais de `workout_types` em toda proposta, edição e confirmação de treino do app (inclusive slug exato e tipo desconhecido; sem cache) NÃO coberto nesta PR (pendência da audit 2026-10-04). Com a leitura funcionando, slug exato e tipo desconhecido saem como no HEAD; o custo é uma ida ao banco a mais por pedido. Travado no teste.
 * > RC W — cenário leitura do catálogo falha NÃO coberto nesta PR (pendência da audit 2026-10-04). Texto cujo minúsculo já é a própria normalização (sem acento, espaço nem hífen: "musculacao", "MUSCULACAO", "natacao", "Capoeira", "Bike") segue como digitado, como antes da mudança: a função SQL faz `lower()` sozinha e responde pela taxa do catálogo quando o slug existe ("MUSCULACAO", 40 min, moderada, 70 kg = 240; "NATACAO" = 400) e pela genérica quando não existe. Qualquer outro texto ("Natação", "jiu-jitsu", "corrida leve") responde `500 workout_calculation_failed`, onde antes respondia pela taxa genérica (240 no mesmo treino). E um texto do primeiro grupo que o catálogo só casa pelo nome de exibição sai pela taxa genérica enquanto a leitura falhar; no catálogo de staging são cinco, em qualquer combinação de maiúsculas: "polichinelos" ou "Polichinelos" (`jumping_jacks`) e, só se digitados com "_" no lugar dos espaços, "biceps_e_triceps", "costas_e_biceps", "ombro_e_trapezio" e "peito_e_triceps". Para "polichinelos": 240 em vez de 320 e, se a falha for só na confirmação, grava 240 sob uma proposta que mostrou 320. Travado no teste.
 * > RC W — cenário tela do iPhone (tipo digitado e kcal da proposta vistos no aparelho) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho nem no simulador.
 */
import { readFileSync } from 'node:fs'
import { registraTreino } from '@mpp/agent'
import type { Json } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { registrationProposalInputSchema } from './contracts'
import {
  buildWorkoutRegistrationCandidate,
  confirmRegistration,
  editRegistration,
  prepareWorkoutRegistrationConfirmation,
  proposeRegistration,
} from './registration-service'

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000c7'
const SNAPSHOT_ID = '0b9f6f0e-0000-4000-8000-0000000000d7'
const TIMEZONE = 'America/Sao_Paulo'
const LOCAL_DATE = '2026-10-04'
const NOW = '2026-10-04T15:00:00.000Z'
const KEY_1 = '0b9f6f0e-58a1-4a10-9d55-1500000000a1'
const KEY_2 = '0b9f6f0e-58a1-4a10-9d55-1500000000b2'

type Row = Record<string, unknown>
type DbError = { message: string }
type Filter = { op: 'eq' | 'gte'; column: string; value: unknown }

type CatalogueRow = {
  slug: string
  display_name: string
  kcal_per_min: number
  is_active: boolean
}

/** `public.workout_types` as read from staging on 2026-10-04: slug, display_name, kcal_per_min. */
const STAGING_CATALOGUE: ReadonlyArray<readonly [string, string, number]> = [
  ['abdomen', 'Abdômen', 4.5],
  ['abdominal', 'Abdominal (alias)', 4.5],
  ['aerobico', 'Aeróbico (alias)', 8],
  ['alongamento', 'Alongamento', 2.5],
  ['basquete', 'Basquete', 8.5],
  ['beach_tennis', 'Beach tennis', 7],
  ['biceps_triceps', 'Bíceps e tríceps', 5],
  ['bicicleta', 'Bicicleta', 8],
  ['bjj', 'BJJ (alias)', 10.5],
  ['boxe', 'Boxe (alias)', 10.5],
  ['calistenia', 'Calistenia', 6.5],
  ['caminhada', 'Caminhada', 4.5],
  ['caminhada_rapida', 'Caminhada rápida', 6],
  ['cardio', 'Cardio (genérico)', 8],
  ['corrida', 'Corrida', 11],
  ['corrida_intensa', 'Corrida intensa', 13],
  ['corrida_leve', 'Corrida leve', 8],
  ['costas', 'Costas (alias)', 5.5],
  ['costas_biceps', 'Costas e bíceps', 5.5],
  ['crossfit', 'CrossFit / Funcional', 9],
  ['crossfit_wod', 'CrossFit WOD (alias)', 9],
  ['danca', 'Dança', 6.5],
  ['eliptico', 'Elíptico', 8.5],
  ['escada', 'Escada / Stair', 10],
  ['escalada', 'Escalada', 9.5],
  ['esteira', 'Esteira', 8],
  ['flex', 'Flexibilidade (alias)', 2.5],
  ['full_body', 'Full body', 6.5],
  ['funcional', 'Treino funcional (alias)', 9],
  ['futebol', 'Futebol', 8],
  ['gluteos', 'Glúteos', 6.5],
  ['handstand', 'Handstand / parada de mão', 6],
  ['hiit', 'HIIT', 12],
  ['jiu_jitsu', 'Jiu-jitsu (alias)', 10.5],
  ['jumping_jacks', 'Polichinelos', 8],
  ['luta', 'Luta / Jiu-jitsu / Boxe', 10.5],
  ['mobility', 'Mobility / mobilidade', 3],
  ['muay_thai', 'Muay Thai', 11],
  ['musculacao', 'Musculação (genérico)', 6],
  ['natacao', 'Natação', 10],
  ['ombro_trapezio', 'Ombro e trapézio', 5],
  ['ombros', 'Ombros (alias)', 5],
  ['outro', 'Outro', 6],
  ['peito', 'Peito (alias)', 5.5],
  ['peito_triceps', 'Peito e tríceps', 5.5],
  ['perna_completa', 'Perna completa', 7],
  ['pernas', 'Pernas (alias)', 7],
  ['pilates', 'Pilates', 4],
  ['pilates_solo', 'Pilates solo (alias)', 4],
  ['remo', 'Remo / Remoergômetro', 9],
  ['spinning', 'Spinning', 9],
  ['tenis', 'Tênis', 7.5],
  ['treino_a', 'Treino A', 6],
  ['treino_b', 'Treino B', 6],
  ['treino_c', 'Treino C', 6],
  ['volei', 'Vôlei', 6.5],
  ['yoga', 'Yoga', 3],
  ['zumba', 'Zumba', 7.5],
]

type PendingRow = {
  id: string
  user_id: string
  proposal: Json
  status: string
  created_at: string
  expires_at: string
  resolved_at: string | null
}

type WorkoutRow = {
  id: string
  user_id: string
  snapshot_id: string
  workout_type: string
  duration_min: number
  estimated_kcal: number
  intensity: string | null
  notes: string | null
  performed_at: string
  created_at: string
  raw_provider_message_id: string | null
}

type KcalParams = {
  p_slug: string
  p_duration_min: number
  p_intensity?: string | null
  p_weight_kg?: number
}

type RegisterWorkoutParams = {
  p_user_id: string
  p_date: string
  p_workout_type: string
  p_duration_min: number
  p_estimated_kcal: number
  p_intensity: string | null
  p_notes: string | null
  p_performed_at: string
  p_provider_message_id: string | null
  p_calories_target: number | null
  p_protein_target: number | null
  p_replace_recent: boolean
  p_replace_since: string | null
}

type ReplacePendingParams = {
  p_user_id: string
  p_proposal: Json
  p_expires_at: string
  p_request_key: string | null
}

function passes(row: Row, filter: Filter): boolean {
  const value = row[filter.column]
  if (filter.op === 'eq') return value === filter.value
  return value != null && Date.parse(String(value)) >= Date.parse(String(filter.value))
}

/** A table that holds rows: filters and updates are really applied, and a
 * filter this fixture does not know fails the test instead of passing. */
class Query {
  private readonly filters: Filter[] = []
  private max: number | null = null
  private patch: Row | null = null

  constructor(
    private readonly source: () => Row[],
    private readonly readFailure: () => DbError | null = () => null,
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
    if (column !== 'created_at') throw new Error(`in-memory db: unsupported filter gte(${column})`)
    this.filters.push({ op: 'gte', column, value })
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

  maybeSingle(): Promise<{ data: Row | null; error: DbError | null }> {
    const error = this.patch ? null : this.readFailure()
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
    const error = this.patch ? null : this.readFailure()
    return Promise.resolve(error ? { data: null, error } : { data: this.run(), error: null }).then(
      onFulfilled,
      onRejected,
    )
  }
}

/** `global_config` has no `calc.%` row: the tool uses the defaults of the core. */
function noCalcOverrides() {
  const table = {
    select: () => table,
    like: () => Promise.resolve({ data: [], error: null }),
  }
  return table
}

function database(options: { weightKg?: number | null; catalogue?: CatalogueRow[] } = {}) {
  const catalogue: CatalogueRow[] =
    options.catalogue ??
    STAGING_CATALOGUE.map(([slug, display_name, kcal_per_min]) => ({
      slug,
      display_name,
      kcal_per_min,
      is_active: true,
    }))
  // Only the weight is known (see ASSUMED); the other columns the tool reads are absent.
  const profile = {
    user_id: USER_ID,
    weight_kg: options.weightKg === undefined ? 70 : options.weightKg,
  }
  const pendings: PendingRow[] = []
  const workouts: WorkoutRow[] = []
  const snapshots: Array<{
    id: string
    user_id: string
    date: string
    exercise_calories: number
    training_done: boolean
    calories_target: number | null
    protein_target: number | null
  }> = []
  const events: Row[] = []
  const rpcCalls: Array<{ fn: string; params: Record<string, unknown> }> = []
  const failures = { catalogueRead: false }
  /** Every `from(table)` of the code under test, in order. */
  const tableReads: string[] = []
  let pendingSequence = 0
  let workoutSequence = 0

  // public.calc_workout_kcal (20260504165600): `lower()` of the argument, active
  // rows only; else the 'outro' row (no is_active filter there); else 6.0.
  const calcWorkoutKcal = (params: KcalParams): number => {
    const slug = params.p_slug.toLowerCase()
    const base =
      catalogue.find((row) => row.slug === slug && row.is_active)?.kcal_per_min ??
      catalogue.find((row) => row.slug === 'outro')?.kcal_per_min ??
      6
    const intensity = (params.p_intensity ?? 'moderada').toLowerCase()
    const factor = intensity === 'leve' ? 0.75 : intensity === 'alta' ? 1.25 : 1
    return Math.round(base * params.p_duration_min * factor * ((params.p_weight_kg ?? 70) / 70))
  }

  // public.register_workout_atomic (20260711202000), without the replacement
  // branch: no test here sends p_replace_recent.
  const registerWorkoutAtomic = (params: RegisterWorkoutParams) => {
    const type = params.p_workout_type.trim()
    if (
      !type ||
      params.p_workout_type.length > 200 ||
      params.p_duration_min < 1 ||
      params.p_duration_min > 1440 ||
      !Number.isInteger(params.p_estimated_kcal) ||
      params.p_estimated_kcal < 0 ||
      params.p_estimated_kcal > 10000
    ) {
      return { data: null, error: { message: 'invalid workout payload' } }
    }
    if (params.p_replace_recent) {
      return { data: null, error: { message: 'in-memory db: replacement is not emulated' } }
    }
    let snapshot = snapshots.find(
      (row) => row.user_id === params.p_user_id && row.date === params.p_date,
    )
    if (!snapshot) {
      snapshot = {
        id: SNAPSHOT_ID,
        user_id: params.p_user_id,
        date: params.p_date,
        exercise_calories: 0,
        training_done: false,
        calories_target: params.p_calories_target,
        protein_target: params.p_protein_target,
      }
      snapshots.push(snapshot)
    }
    const snapshotId = snapshot.id
    const pmid = params.p_provider_message_id
    // ON CONFLICT (user_id, raw_provider_message_id, workout_type) DO NOTHING.
    const existing = workouts.find(
      (row) =>
        pmid != null &&
        row.user_id === params.p_user_id &&
        row.raw_provider_message_id === pmid &&
        row.workout_type === type,
    )
    let workoutLogId = existing?.id ?? null
    if (!existing) {
      workoutSequence += 1
      workoutLogId = `workout-log-${workoutSequence}`
      workouts.push({
        id: workoutLogId,
        user_id: params.p_user_id,
        snapshot_id: snapshotId,
        workout_type: type,
        duration_min: params.p_duration_min,
        estimated_kcal: params.p_estimated_kcal,
        intensity: params.p_intensity,
        notes: params.p_notes,
        performed_at: params.p_performed_at,
        created_at: new Date().toISOString(),
        raw_provider_message_id: pmid,
      })
    }
    const ofSnapshot = workouts.filter((row) => row.snapshot_id === snapshotId)
    snapshot.exercise_calories = ofSnapshot.reduce((sum, row) => sum + row.estimated_kcal, 0)
    snapshot.training_done = ofSnapshot.length > 0
    return {
      data: {
        snapshot_id: snapshotId,
        workout_log_id: workoutLogId,
        inserted: !existing,
        replaced_count: 0,
        exercise_calories: snapshot.exercise_calories,
        training_done: snapshot.training_done,
        calories_target: snapshot.calories_target,
        protein_target: snapshot.protein_target,
      },
      error: null,
    }
  }

  // public.replace_pending_registration_atomic (20260712205000): the request
  // key is written into the proposal, a retry of the same key answers the
  // pending it created, and open pendings are cancelled.
  const replacePendingRegistrationAtomic = (params: ReplacePendingParams) => {
    const proposal = JSON.parse(JSON.stringify(params.p_proposal)) as Json
    if (typeof proposal !== 'object' || proposal === null || Array.isArray(proposal)) {
      return { data: null, error: { message: 'proposal must be a JSON object' } }
    }
    const key = params.p_request_key?.trim() || null
    if (key) {
      proposal.source_provider_message_id = key
      const existing = pendings.find(
        (row) =>
          row.user_id === params.p_user_id &&
          (row.proposal as Row | null)?.source_provider_message_id === key,
      )
      if (existing) {
        return {
          data: { pending_id: existing.id, created: false, status: existing.status },
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
    const id = `0b9f6f0e-0000-4000-8000-0000000c${String(pendingSequence).padStart(4, '0')}`
    pendings.push({
      id,
      user_id: params.p_user_id,
      proposal,
      status: 'pending',
      created_at: now,
      expires_at: params.p_expires_at,
      resolved_at: null,
    })
    return { data: { pending_id: id, created: true, status: 'pending' }, error: null }
  }

  const client = {
    from(table: string): unknown {
      tableReads.push(table)
      if (table === 'user_profiles') return new Query(() => [profile])
      if (table === 'workout_types') {
        return new Query(
          () => catalogue,
          () => (failures.catalogueRead ? { message: 'statement timeout' } : null),
        )
      }
      if (table === 'pending_registrations') return new Query(() => pendings)
      if (table === 'workout_logs') return new Query(() => workouts)
      if (table === 'global_config') return noCalcOverrides()
      if (table === 'product_events') {
        return {
          insert(event: Row) {
            events.push(event)
            return Promise.resolve({ data: null, error: null })
          },
        }
      }
      throw new Error(`in-memory db: unexpected table ${table}`)
    },
    rpc(fn: string, params: Record<string, unknown>) {
      rpcCalls.push({ fn, params })
      if (fn === 'calc_workout_kcal') {
        return Promise.resolve({ data: calcWorkoutKcal(params as KcalParams), error: null })
      }
      if (fn === 'register_workout_atomic') {
        return Promise.resolve(registerWorkoutAtomic(params as RegisterWorkoutParams))
      }
      if (fn === 'replace_pending_registration_atomic') {
        return Promise.resolve(replacePendingRegistrationAtomic(params as ReplacePendingParams))
      }
      throw new Error(`in-memory db: unexpected rpc ${fn}`)
    },
  }

  return {
    client,
    pendings,
    workouts,
    snapshots,
    events,
    failures,
    tableReads,
    calcWorkoutKcal,
    /** What each kcal lookup received, in order: the proposal's, then the tool's. */
    lookups: () =>
      rpcCalls.filter((call) => call.fn === 'calc_workout_kcal').map((call) => call.params),
    writes: () =>
      rpcCalls.filter((call) => call.fn === 'register_workout_atomic').map((call) => call.params),
    storedProposal: (id: string) => (pendings.find((row) => row.id === id)?.proposal ?? {}) as Row,
  }
}

type Database = ReturnType<typeof database>

/**
 * The in-memory database behind a client shaped like supabase-js: a class
 * whose methods and getter need their own `this` (a private field). A wrapper
 * that calls them on anything but the client itself throws a TypeError here.
 */
class ClassClient {
  readonly #inner: Database['client']

  constructor(inner: Database['client']) {
    this.#inner = inner
  }

  get rest() {
    return this.#inner
  }

  from(table: string) {
    return this.rest.from(table)
  }

  rpc(fn: string, params: Record<string, unknown>) {
    return this.rest.rpc(fn, params)
  }
}

const AUTH = {
  userId: USER_ID,
  patient: { country: 'BR', countryConfirmed: true, timezone: TIMEZONE },
}

type Body = { workout_type: string; duration_min?: number; intensity?: string }

/** The body as the route receives it, through the real contract of the route. */
function contract(body: Body) {
  return registrationProposalInputSchema.safeParse({
    kind: 'workout',
    duration_min: 40,
    intensity: 'moderada',
    ...body,
  })
}

async function propose(db: Database, body: Body, key = KEY_1) {
  const parsed = contract(body)
  if (!parsed.success) throw new Error('the contract refused the body of the test')
  return proposeRegistration(db.client as never, AUTH as never, parsed.data, key)
}

function confirm(db: Database, registrationId: string) {
  return confirmRegistration(db.client as never, AUTH as never, registrationId)
}

/** Propose and confirm one workout; what was shown, looked up and stored. */
async function register(db: Database, body: Body) {
  const proposed = await propose(db, body)
  const confirmed = await confirm(db, proposed.id)
  return {
    proposed,
    confirmed,
    lookupSlugs: db.lookups().map((params) => params.p_slug),
    stored: db.workouts.map((row) => ({
      workout_type: row.workout_type,
      estimated_kcal: row.estimated_kcal,
    })),
  }
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(NOW))
})
afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('workout type typed in the app — the reported case: "Natação", 40 min, moderada, 70 kg', () => {
  it('the fixture reproduces what the reviewer measured: the function given the typed text answers the generic 240', () => {
    const db = database()
    // 'natação' is not a slug → 'outro' 6.00 × 40 × 1.0 × 70/70 = 240.
    expect(
      db.calcWorkoutKcal({
        p_slug: 'Natação',
        p_duration_min: 40,
        p_intensity: 'moderada',
        p_weight_kg: 70,
      }),
    ).toBe(240)
  })

  it('proposes 400 kcal (natacao 10.00 × 40 × 1.0 × 70/70), looked up by slug, with the type as typed', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })

    expect(db.lookups()).toEqual([
      { p_slug: 'natacao', p_duration_min: 40, p_intensity: 'moderada', p_weight_kg: 70 },
    ])
    // The response shape and the type shown are the ones of HEAD.
    expect(proposed).toMatchObject({
      status: 'pending',
      proposal: {
        kind: 'workout',
        workout_type: 'Natação',
        duration_min: 40,
        estimated_kcal: 400,
        intensity: 'moderada',
      },
    })
    expect(Object.keys(proposed.proposal).sort()).toEqual([
      'duration_min',
      'estimated_kcal',
      'intensity',
      'kind',
      'workout_type',
    ])
    // What the pending stores: the typed text, never the slug.
    expect(db.storedProposal(proposed.id)).toEqual({
      kind: 'workout',
      workoutType: 'Natação',
      durationMin: 40,
      kcalEst: 400,
      intensity: 'moderada',
      sourceContentType: 'mobile',
      source_provider_message_id: KEY_1,
      source_timestamp: NOW,
      source_timezone: TIMEZONE,
      source_local_date: LOCAL_DATE,
      raw_args: { workout_type: 'Natação', duration_min: 40, intensity: 'moderada' },
      express_eligible: false,
    })
  })

  it('confirms what it proposed: the real tool writes 400 kcal under the typed type, and the day has 400 of exercise', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    const confirmed = await confirm(db, proposed.id)

    expect(confirmed).toMatchObject({
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
      proposal: { workout_type: 'Natação', estimated_kcal: 400 },
    })
    // The proposal's lookup, then the tool's: both by the catalogue slug.
    expect(db.lookups().map((params) => params.p_slug)).toEqual(['natacao', 'natacao'])
    expect(db.writes()).toHaveLength(1)
    expect(db.writes()[0]).toMatchObject({
      p_user_id: USER_ID,
      p_date: LOCAL_DATE,
      p_workout_type: 'Natação',
      p_duration_min: 40,
      p_estimated_kcal: 400,
      p_intensity: 'moderada',
      p_performed_at: NOW,
      p_provider_message_id: KEY_1,
    })
    expect(db.workouts).toEqual([
      {
        id: 'workout-log-1',
        user_id: USER_ID,
        snapshot_id: SNAPSHOT_ID,
        workout_type: 'Natação',
        duration_min: 40,
        estimated_kcal: 400,
        intensity: 'moderada',
        notes: '[kcal_source=formula, formula=400, image=n/a]',
        performed_at: NOW,
        created_at: NOW,
        raw_provider_message_id: KEY_1,
      },
    ])
    expect(db.snapshots).toEqual([
      {
        id: SNAPSHOT_ID,
        user_id: USER_ID,
        date: LOCAL_DATE,
        exercise_calories: 400,
        training_done: true,
        calories_target: null,
        protein_target: null,
      },
    ])
    expect(db.events).toEqual([])
  })

  it('the same through a client that is a class with private state, as supabase-js is', async () => {
    const db = database()
    const client = new ClassClient(db.client)
    const parsed = contract({ workout_type: 'Natação' })
    if (!parsed.success) throw new Error('the contract refused the body of the test')
    const proposed = await proposeRegistration(client as never, AUTH as never, parsed.data, KEY_1)
    const confirmed = await confirmRegistration(client as never, AUTH as never, proposed.id)

    expect(confirmed).toMatchObject({ status: 'confirmed', deduped: false })
    expect(db.lookups().map((params) => params.p_slug)).toEqual(['natacao', 'natacao'])
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['Natação', 400],
    ])
  })

  it('a second confirm answers already_confirmed and writes nothing', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    await confirm(db, proposed.id)
    const again = await confirm(db, proposed.id)

    expect(again).toMatchObject({ status: 'confirmed', already_confirmed: true })
    expect(db.workouts).toHaveLength(1)
    expect(db.snapshots[0]?.exercise_calories).toBe(400)
  })

  it('intensity and weight still enter the same way: alta, 82 kg → round(10 × 40 × 1.25 × 82/70 = 585.71) = 586', async () => {
    const db = database({ weightKg: 82 })
    const result = await register(db, { workout_type: 'Natação', intensity: 'alta' })

    expect(result.proposed.proposal).toMatchObject({ estimated_kcal: 586, intensity: 'alta' })
    expect(result.stored).toEqual([{ workout_type: 'Natação', estimated_kcal: 586 }])
    expect(db.lookups()).toEqual([
      { p_slug: 'natacao', p_duration_min: 40, p_intensity: 'alta', p_weight_kg: 82 },
      { p_slug: 'natacao', p_duration_min: 40, p_intensity: 'alta', p_weight_kg: 82 },
    ])
  })

  it('a profile with no weight keeps the 70 kg fallback', async () => {
    const db = database({ weightKg: null })
    const result = await register(db, { workout_type: 'Natação' })

    expect(result.proposed.proposal).toMatchObject({ estimated_kcal: 400 })
    expect(result.stored).toEqual([{ workout_type: 'Natação', estimated_kcal: 400 }])
    expect(db.lookups().map((params) => params.p_weight_kg)).toEqual([70, 70])
  })
})

describe('versioned workout bridge reuses the real calculation without the legacy writer', () => {
  it.each([
    { weightKg: 70, intensity: 'moderada' as const, kcal: 400 },
    { weightKg: 82, intensity: 'alta' as const, kcal: 586 },
    { weightKg: null, intensity: 'moderada' as const, kcal: 400 },
  ])('keeps Natação40 with $weightKg kg/$intensity at $kcal kcal in the official first13', async ({
    weightKg,
    intensity,
    kcal,
  }) => {
    const db = database({ weightKg })
    const key = `wui1:${KEY_1}`
    const candidate = await buildWorkoutRegistrationCandidate(
      db.client as never,
      AUTH as never,
      {
        kind: 'workout',
        workout_type: 'Natação',
        duration_min: 40,
        intensity,
      },
      key,
    )
    const prepared = await prepareWorkoutRegistrationConfirmation(
      db.client as never,
      AUTH as never,
      candidate,
    )
    expect(candidate).toMatchObject({
      workoutType: 'Natação',
      durationMin: 40,
      kcalEst: kcal,
      source_provider_message_id: key,
    })
    expect(prepared).toStrictEqual({
      p_user_id: USER_ID,
      p_date: LOCAL_DATE,
      p_workout_type: 'Natação',
      p_duration_min: 40,
      p_estimated_kcal: kcal,
      p_intensity: intensity,
      p_notes: `[kcal_source=formula, formula=${kcal}, image=n/a]`,
      p_performed_at: NOW,
      p_provider_message_id: key,
      p_calories_target: null,
      p_protein_target: null,
      p_replace_recent: false,
      p_replace_since: null,
    })
    expect(db.lookups()).toStrictEqual([
      {
        p_slug: 'natacao',
        p_duration_min: 40,
        p_intensity: intensity,
        p_weight_kg: weightKg ?? 70,
      },
      {
        p_slug: 'natacao',
        p_duration_min: 40,
        p_intensity: intensity,
        p_weight_kg: weightKg ?? 70,
      },
    ])
    expect(db.writes()).toStrictEqual([])
    expect([db.pendings, db.workouts, db.snapshots, db.events]).toStrictEqual([[], [], [], []])
  })
})

describe('workout type typed in the app — every wording resolves to its slug and rate (40 min, moderada, 70 kg)', () => {
  it.each([
    // typed, slug, kcal_per_min, kcal = rate × 40 × 1.0 × 70/70
    ['Natação', 'natacao', 10, 400],
    ['Tênis', 'tenis', 7.5, 300],
    ['Muay thai', 'muay_thai', 11, 440],
    ['Jiu-jitsu', 'jiu_jitsu', 10.5, 420],
    ['Elíptico', 'eliptico', 8.5, 340],
    ['Corrida leve', 'corrida_leve', 8, 320],
  ])('"%s" → %s (%d kcal/min) → %d kcal, proposed and stored', async (typed, slug, rate, kcal) => {
    const db = database()
    expect(rate * 40).toBe(kcal)
    const result = await register(db, { workout_type: typed })

    expect(result.lookupSlugs).toEqual([slug, slug])
    expect(result.proposed.proposal).toMatchObject({ workout_type: typed, estimated_kcal: kcal })
    expect(result.confirmed.proposal).toMatchObject({ workout_type: typed, estimated_kcal: kcal })
    expect(result.stored).toEqual([{ workout_type: typed, estimated_kcal: kcal }])
    expect(db.snapshots[0]?.exercise_calories).toBe(kcal)
  })

  it.each([
    // typed, what the contract hands over (trimmed), slug, kcal
    ['  NATAÇÃO  ', 'NATAÇÃO', 'natacao', 400],
    ['natação', 'natação', 'natacao', 400],
    ['Natação', 'Natação', 'natacao', 400],
    ['Muay  Thai', 'Muay  Thai', 'muay_thai', 440],
    ['muay-thai', 'muay-thai', 'muay_thai', 440],
    ['Jiu jitsu', 'Jiu jitsu', 'jiu_jitsu', 420],
    ['JIU - JITSU', 'JIU - JITSU', 'jiu_jitsu', 420],
    ['Jiu_Jitsu', 'Jiu_Jitsu', 'jiu_jitsu', 420],
    ['corrida-leve', 'corrida-leve', 'corrida_leve', 320],
    ['Corrida__Leve', 'Corrida__Leve', 'corrida_leve', 320],
  ])('spelling "%s" is stored as "%s" and looked up as %s → %d kcal', async (typed, stored, slug, kcal) => {
    const db = database()
    const result = await register(db, { workout_type: typed })

    expect(result.lookupSlugs).toEqual([slug, slug])
    expect(result.proposed.proposal).toMatchObject({ workout_type: stored, estimated_kcal: kcal })
    expect(result.stored).toEqual([{ workout_type: stored, estimated_kcal: kcal }])
  })

  it.each([
    // The catalogue's own display name of a slug with another spelling.
    ['Polichinelos', 'jumping_jacks', 320], // 8.00 × 40
    ['Peito e tríceps', 'peito_triceps', 220], // 5.50 × 40
    ['OMBRO E TRAPEZIO', 'ombro_trapezio', 200], // 5.00 × 40
    ['Luta / Jiu-jitsu / Boxe', 'luta', 420], // 10.50 × 40
  ])('display name "%s" → %s → %d kcal', async (typed, slug, kcal) => {
    const db = database()
    const result = await register(db, { workout_type: typed })

    expect(result.lookupSlugs).toEqual([slug, slug])
    expect(result.proposed.proposal).toMatchObject({ workout_type: typed, estimated_kcal: kcal })
    expect(result.stored).toEqual([{ workout_type: typed, estimated_kcal: kcal }])
  })

  it('an edit resolves the new type the same way and keeps it as typed', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    const parsed = contract({ workout_type: 'Tênis' })
    if (!parsed.success) throw new Error('the contract refused the body of the test')
    const edited = await editRegistration(
      db.client as never,
      AUTH as never,
      proposed.id,
      parsed.data,
      KEY_2,
    )

    expect(edited.proposal).toMatchObject({ workout_type: 'Tênis', estimated_kcal: 300 })
    await confirm(db, proposed.id)
    expect(db.lookups().map((params) => params.p_slug)).toEqual(['natacao', 'tenis', 'tenis'])
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['Tênis', 300],
    ])
  })
})

describe('workout type typed in the app — what did not change', () => {
  it.each([
    ['natacao', 400],
    ['corrida_leve', 320],
    ['outro', 240],
  ])('the exact slug "%s" still works and reaches the function as typed → %d kcal', async (slug, kcal) => {
    const db = database()
    const result = await register(db, { workout_type: slug })

    expect(result.lookupSlugs).toEqual([slug, slug])
    expect(result.proposed.proposal).toMatchObject({ workout_type: slug, estimated_kcal: kcal })
    expect(result.stored).toEqual([{ workout_type: slug, estimated_kcal: kcal }])
  })

  it.each([
    // A sport the catalogue does not have (RC W, first line).
    ['Capoeira'],
    ['Surfe'],
    // Another word for an activity the catalogue has: no synonym, no fuzzy
    // match (RC W, second line).
    ['Bike'],
    ['Natação no mar'],
    ['Jiu jitsu brasileiro'],
    ['Corridas'],
    ['jiu.jitsu'],
    ['Jiu–jitsu'],
  ])('"%s" still falls back to the generic rate, handed over as typed: 6.00 × 40 = 240 kcal, with no notice', async (typed) => {
    const db = database()
    const result = await register(db, { workout_type: typed })

    // Byte for byte what HEAD sent; the function lowercases and misses.
    expect(result.lookupSlugs).toEqual([typed, typed])
    expect(result.proposed.proposal).toEqual({
      kind: 'workout',
      workout_type: typed,
      duration_min: 40,
      estimated_kcal: 240,
      intensity: 'moderada',
    })
    expect(result.stored).toEqual([{ workout_type: typed, estimated_kcal: 240 }])
    expect(db.snapshots[0]?.exercise_calories).toBe(240)
  })

  it('an inactive slug is not resolved: the typed text is handed over and the function answers the generic rate', async () => {
    const catalogue = STAGING_CATALOGUE.map(([slug, display_name, kcal_per_min]) => ({
      slug,
      display_name,
      kcal_per_min,
      is_active: slug !== 'natacao',
    }))
    const db = database({ catalogue })
    const result = await register(db, { workout_type: 'Natação' })

    expect(result.lookupSlugs).toEqual(['Natação', 'Natação'])
    expect(result.stored).toEqual([{ workout_type: 'Natação', estimated_kcal: 240 }])
  })

  it('two active slugs under one display name: none is chosen, generic rate', async () => {
    const db = database({
      catalogue: [
        { slug: 'outro', display_name: 'Outro', kcal_per_min: 6, is_active: true },
        { slug: 'karate', display_name: 'Artes marciais', kcal_per_min: 9, is_active: true },
        { slug: 'judo', display_name: 'Artes Marciais', kcal_per_min: 10, is_active: true },
      ],
    })
    const result = await register(db, { workout_type: 'Artes marciais' })

    expect(result.lookupSlugs).toEqual(['Artes marciais', 'Artes marciais'])
    expect(result.stored).toEqual([{ workout_type: 'Artes marciais', estimated_kcal: 240 }])
  })

  it('a slug wins over another slug that carries the same word as its display name', async () => {
    const db = database({
      catalogue: [
        { slug: 'outro', display_name: 'Outro', kcal_per_min: 6, is_active: true },
        { slug: 'remo', display_name: 'Remo / Remoergômetro', kcal_per_min: 9, is_active: true },
        { slug: 'canoagem', display_name: 'Remo', kcal_per_min: 7, is_active: true },
      ],
    })
    const result = await register(db, { workout_type: 'Remo' })

    expect(result.lookupSlugs).toEqual(['remo', 'remo'])
    expect(result.stored).toEqual([{ workout_type: 'Remo', estimated_kcal: 360 }]) // 9.00 × 40
  })

  it('a catalogue read that fails refuses the proposal (500 workout_calculation_failed) and creates no pending', async () => {
    const db = database()
    db.failures.catalogueRead = true

    await expect(propose(db, { workout_type: 'Natação' })).rejects.toMatchObject({
      status: 500,
      code: 'workout_calculation_failed',
    })
    expect(db.pendings).toEqual([])
    expect(db.lookups()).toEqual([])
  })

  it('a catalogue read that fails refuses the edit the same way and leaves the proposal as it was', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    const parsed = contract({ workout_type: 'Tênis' })
    if (!parsed.success) throw new Error('the contract refused the body of the test')
    db.failures.catalogueRead = true

    await expect(
      editRegistration(db.client as never, AUTH as never, proposed.id, parsed.data, KEY_2),
    ).rejects.toMatchObject({ status: 500, code: 'workout_calculation_failed' })
    expect(db.storedProposal(proposed.id)).toMatchObject({ workoutType: 'Natação', kcalEst: 400 })
    expect(db.pendings[0]?.status).toBe('pending')
  })

  it('a catalogue read that fails at the confirm writes nothing and leaves the pending open for a retry', async () => {
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    db.failures.catalogueRead = true

    await expect(confirm(db, proposed.id)).rejects.toMatchObject({
      status: 500,
      code: 'workout_calculation_failed',
    })
    expect(db.workouts).toEqual([])
    expect(db.pendings[0]?.status).toBe('pending')

    db.failures.catalogueRead = false
    const confirmed = await confirm(db, proposed.id)
    expect(confirmed).toMatchObject({ status: 'confirmed', already_confirmed: false })
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['Natação', 400],
    ])
  })
})

describe('workout type typed in the app — a failed catalogue read (review of 2026-10-05, MEDIUM)', () => {
  // The lookup reads `workout_types` on every proposal, edit and confirm. At
  // HEAD nothing read it, so a failed read could not fail a workout. Now: a
  // text whose lower-cased form already is its canonical spelling goes on as
  // typed (what HEAD sent, and the SQL function lowercases by itself); only a
  // text that needs the catalogue (an accent, a space, a hyphen) is refused.
  // "HEAD" in this block is the code before the lookup existed.

  it("the reviewer's case: 'musculacao', 40 min, moderada, 70 kg with the catalogue read failing → proposed 240 and confirmed, one row, as HEAD", async () => {
    const db = database()
    db.failures.catalogueRead = true

    const result = await register(db, { workout_type: 'musculacao' })

    // musculacao 6.00 × 40 × 1.0 × 70/70 = 240. Both lookups as typed.
    expect(result.lookupSlugs).toEqual(['musculacao', 'musculacao'])
    expect(result.proposed).toMatchObject({
      status: 'pending',
      proposal: { workout_type: 'musculacao', estimated_kcal: 240 },
    })
    expect(result.confirmed).toMatchObject({ status: 'confirmed', deduped: false })
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['musculacao', 240],
    ])
    expect(db.pendings[0]?.status).toBe('confirmed')
  })

  // Review of 2026-10-05 (LOW), the exact input: 'MUSCULACAO', 40 min,
  // moderada, 70 kg, the read of `workout_types` failing. The first version of
  // this fallback compared the typed text with its canonical form, so one
  // capital letter answered 500 where HEAD answered the catalogue's rate.
  it("the reviewer's case: 'MUSCULACAO' with the catalogue read failing → proposed 240 with p_slug 'MUSCULACAO', as HEAD, and confirmed", async () => {
    const db = database()
    db.failures.catalogueRead = true

    const result = await register(db, { workout_type: 'MUSCULACAO' })

    // The function's own lower(): musculacao 6.00 × 40 × 1.0 × 70/70 = 240.
    expect(result.lookupSlugs).toEqual(['MUSCULACAO', 'MUSCULACAO'])
    expect(result.proposed).toMatchObject({
      status: 'pending',
      proposal: { workout_type: 'MUSCULACAO', estimated_kcal: 240 },
    })
    expect(result.confirmed).toMatchObject({ status: 'confirmed', deduped: false })
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['MUSCULACAO', 240],
    ])
    expect(db.pendings[0]?.status).toBe('confirmed')
  })

  it.each([
    // typed (its lower-cased form equals its canonical form), kcal of 40 min at 70 kg
    ['natacao', 400], // 10.00 × 40: the function finds the slug by itself
    ['NATACAO', 400], // the catalogue's rate, not the generic one: lower() in SQL
    ['Musculacao', 240],
    ['Corrida', 440], // corrida 11.00 × 40
    ['corrida_leve', 320],
    ['outro', 240],
    ['capoeira', 240], // not in the catalogue: generic rate, as HEAD
    ['Capoeira', 240],
    ['Bike', 240],
  ])('"%s" needs nothing but lower(): handed over as typed with the read failing → %d kcal, proposed, edited and stored', async (typed, kcal) => {
    const db = database()
    db.failures.catalogueRead = true

    const proposed = await propose(db, { workout_type: 'yoga' })
    const parsed = contract({ workout_type: typed })
    if (!parsed.success) throw new Error('the contract refused the body of the test')
    const edited = await editRegistration(
      db.client as never,
      AUTH as never,
      proposed.id,
      parsed.data,
      KEY_2,
    )
    await confirm(db, proposed.id)

    expect(edited.proposal).toMatchObject({ workout_type: typed, estimated_kcal: kcal })
    expect(db.lookups().map((params) => params.p_slug)).toEqual(['yoga', typed, typed])
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      [typed, kcal],
    ])
  })

  it.each([
    // Declared (RC W): HEAD answered each of these with the generic 240.
    ['Natação'], // an accent
    ['jiu-jitsu'], // a hyphen where the slug has "_" (the reviewer's second input)
    ['corrida leve'], // a space
    ['NATAÇÃO'],
    ['Muay thai'],
  ])('"%s" needs the catalogue: the proposal is refused with 500 workout_calculation_failed and nothing is created', async (typed) => {
    const db = database()
    db.failures.catalogueRead = true

    await expect(propose(db, { workout_type: typed })).rejects.toMatchObject({
      status: 500,
      code: 'workout_calculation_failed',
    })
    expect(db.pendings).toEqual([])
    expect(db.lookups()).toEqual([])
    expect(db.workouts).toEqual([])
  })

  it('declared pendency, locked as it is: "polichinelos" matches only by display name, so with the read failing it gets the generic rate', async () => {
    // With the catalogue: jumping_jacks 8.00 × 40 = 320.
    const healthy = database()
    expect((await register(healthy, { workout_type: 'polichinelos' })).stored).toEqual([
      { workout_type: 'polichinelos', estimated_kcal: 320 },
    ])

    // Read failing at the confirm only: the proposal showed 320, the row has 240.
    const db = database()
    const proposed = await propose(db, { workout_type: 'polichinelos' })
    expect(proposed.proposal).toMatchObject({ estimated_kcal: 320 })
    db.failures.catalogueRead = true
    await confirm(db, proposed.id)
    expect(db.lookups().map((params) => params.p_slug)).toEqual(['jumping_jacks', 'polichinelos'])
    expect(db.workouts.map((row) => [row.workout_type, row.estimated_kcal])).toEqual([
      ['polichinelos', 240],
    ])
  })

  it('declared pendency, locked as it is: the display name itself, "Polichinelos", is in the same situation since letter case stopped mattering', async () => {
    const db = database()
    db.failures.catalogueRead = true

    const result = await register(db, { workout_type: 'Polichinelos' })

    // Handed over as typed; 'polichinelos' is not a slug → 'outro' 6.00 × 40.
    expect(result.lookupSlugs).toEqual(['Polichinelos', 'Polichinelos'])
    expect(result.stored).toEqual([{ workout_type: 'Polichinelos', estimated_kcal: 240 }])
  })

  it('every text the fallback refuses got the generic rate at HEAD: no slug of the catalogue differs from its own canonical form', () => {
    const canonical = (value: string) =>
      value
        .normalize('NFD')
        .replace(/\p{Diacritic}/gu, '')
        .toLowerCase()
        .trim()
        .replace(/[\s_-]+/g, '_')
    // HEAD matched lower(typed) against the slugs. A refused text has
    // lower(typed) ≠ canonical(typed); it could only have matched a slug that
    // is not canonical itself.
    expect(STAGING_CATALOGUE.filter(([slug]) => canonical(slug) !== slug)).toEqual([])
  })

  it('in the catalogue of staging five slug-shaped texts are in that situation, one of them a plain word', () => {
    const canonical = (value: string) =>
      value
        .normalize('NFD')
        .replace(/\p{Diacritic}/gu, '')
        .toLowerCase()
        .trim()
        .replace(/[\s_-]+/g, '_')
    const slugs = new Set(STAGING_CATALOGUE.map(([slug]) => slug))
    // A text the fallback hands over as typed (it equals its canonical form)
    // that the catalogue would have resolved to ANOTHER slug by display name.
    const exposed = STAGING_CATALOGUE.map(([slug, displayName]) => [
      slug,
      canonical(displayName),
    ]).filter(
      ([slug, name]) =>
        name !== slug && !slugs.has(name as string) && /^[a-z0-9_]+$/.test(name as string),
    )
    expect(exposed).toEqual([
      ['biceps_triceps', 'biceps_e_triceps'],
      ['costas_biceps', 'costas_e_biceps'],
      ['jumping_jacks', 'polichinelos'],
      ['ombro_trapezio', 'ombro_e_trapezio'],
      ['peito_triceps', 'peito_e_triceps'],
    ])
  })
})

describe('workout type typed in the app — what the lookup costs and what the tool receives', () => {
  it.each([
    ['an exact slug', 'musculacao'],
    ['a type the catalogue does not have', 'Capoeira'],
    ['a type resolved by the catalogue', 'Natação'],
  ])('%s ("%s"): exactly one read of workout_types per proposal, per edit and per confirm', async (_label, typed) => {
    const db = database()
    const catalogueReads = () => db.tableReads.filter((table) => table === 'workout_types').length

    const proposed = await propose(db, { workout_type: typed })
    expect(catalogueReads()).toBe(1)
    // HEAD read the profile and wrote the pending; the catalogue read is new.
    expect(db.tableReads.slice(0, 2)).toEqual(['user_profiles', 'workout_types'])

    const parsed = contract({ workout_type: typed, duration_min: 50 })
    if (!parsed.success) throw new Error('the contract refused the body of the test')
    await editRegistration(db.client as never, AUTH as never, proposed.id, parsed.data, KEY_2)
    expect(catalogueReads()).toBe(2)

    await confirm(db, proposed.id)
    expect(catalogueReads()).toBe(3)
  })

  it('"Natação": the tool receives the SAME client object and the slug in `workoutKcalLookupSlug`; its arguments carry the typed text', async () => {
    const execute = vi.spyOn(registraTreino, 'execute')
    const db = database()
    const proposed = await propose(db, { workout_type: 'Natação' })
    await confirm(db, proposed.id)

    expect(execute).toHaveBeenCalledTimes(1)
    const [args, ctx] = execute.mock.calls[0] ?? []
    expect(args).toEqual({ workout_type: 'Natação', duration_min: 40, intensity: 'moderada' })
    expect(ctx?.supabase).toBe(db.client)
    expect(ctx).toEqual({
      supabase: db.client,
      userId: USER_ID,
      userWpp: '',
      userCountry: 'BR',
      userTimezone: TIMEZONE,
      trustMealType: true,
      workoutKcalLookupSlug: 'natacao',
      providerMessageId: KEY_1,
      referenceTimestamp: new Date(NOW),
    })
  })

  it.each([
    ['an exact slug', 'natacao'],
    ['a type the catalogue does not have', 'Capoeira'],
    ['another word for a catalogue activity', 'Bike'],
  ])('%s ("%s"): the field is ABSENT and the context is the one HEAD built', async (_label, typed) => {
    const execute = vi.spyOn(registraTreino, 'execute')
    const db = database()
    const proposed = await propose(db, { workout_type: typed })
    await confirm(db, proposed.id)

    const [, ctx] = execute.mock.calls[0] ?? []
    expect(ctx).not.toHaveProperty('workoutKcalLookupSlug')
    expect(ctx).toEqual({
      supabase: db.client,
      userId: USER_ID,
      userWpp: '',
      userCountry: 'BR',
      userTimezone: TIMEZONE,
      trustMealType: true,
      providerMessageId: KEY_1,
      referenceTimestamp: new Date(NOW),
    })
  })

  it('no wrapper is left around the database client in the service', () => {
    const source = readFileSync(new URL('./registration-service.ts', import.meta.url), 'utf8')
    expect(source).not.toMatch(/new Proxy\(/)
    expect(source).not.toContain('withWorkoutKcalLookup')
  })
})

describe('workout type typed in the app — declared pendencies', () => {
  it('every "RC W" line of this header is in docs/CALCULO-MPP.md §2d, identical', () => {
    const header = readFileSync(new URL(import.meta.url), 'utf8')
    const doc = readFileSync(new URL('../../../../../docs/CALCULO-MPP.md', import.meta.url), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC W — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC W — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(11)
    expect(fromDoc).toEqual(fromHeader)
  })
})

describe('workout type typed in the app — the contract of the route refuses what it refused', () => {
  it.each([
    ['empty', { workout_type: '' }],
    ['spaces only', { workout_type: '   ' }],
    ['81 characters', { workout_type: 'a'.repeat(81) }],
    ['duration 0', { workout_type: 'Natação', duration_min: 0 }],
    ['duration 1441', { workout_type: 'Natação', duration_min: 1441 }],
  ])('%s is rejected', (_label, body) => {
    expect(contract(body).success).toBe(false)
  })

  it.each([
    ['80 characters', { workout_type: 'a'.repeat(80) }],
    ['duration 1', { workout_type: 'Natação', duration_min: 1 }],
    ['duration 1440', { workout_type: 'Natação', duration_min: 1440 }],
  ])('%s is accepted', (_label, body) => {
    expect(contract(body).success).toBe(true)
  })

  it('hands the service the typed text, trimmed and otherwise untouched', () => {
    const parsed = contract({ workout_type: '  Natação  ' })
    expect(parsed.success && parsed.data.kind === 'workout' && parsed.data.workout_type).toBe(
      'Natação',
    )
  })
})

describe('workout type typed in the app — the fixture is the catalogue of the migrations', () => {
  it('holds the 58 rows of 20260504165600 and 20260504172500, slug, display name and rate', () => {
    const migration = (file: string) =>
      readFileSync(new URL(`../../../../../supabase/migrations/${file}`, import.meta.url), 'utf8')
    const rows = [
      ...`${migration('20260504165600_critical_bugs_fix.sql')}\n${migration('20260504172500_workout_aliases.sql')}`.matchAll(
        /\('([a-z_]+)',\s*'([^']+)',\s*'(?:musculacao|cardio|esporte|mobilidade)',\s*([\d.]+),/g,
      ),
    ].map((match) => [match[1], match[2], Number(match[3])])

    expect(rows).toHaveLength(58)
    expect(new Set(rows.map(([slug]) => slug)).size).toBe(58)
    expect([...rows].sort((a, b) => String(a[0]).localeCompare(String(b[0]), 'en'))).toEqual(
      [...STAGING_CATALOGUE].sort((a, b) => a[0].localeCompare(b[0], 'en')),
    )
  })
})
