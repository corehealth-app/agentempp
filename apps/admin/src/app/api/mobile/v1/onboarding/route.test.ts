import { createHash } from 'node:crypto'
import { clearCalcConfigCache } from '@mpp/agent'
import { protocolWelcomeMessage } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { authorizeMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { EVALUATION_ACCESS_DAYS_ENV } from '@/lib/mobile-api/evaluation-access'
import {
  executeIdempotent,
  hashMobileRequest,
  type MobileIdempotencyStore,
} from '@/lib/mobile-api/idempotency'
import type { OnboardingRepository } from '@/lib/mobile-api/onboarding-service'
import {
  createMobileRoute,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { handleOnboardingEligibilityPost } from './eligibility/handler'
import {
  handleOnboardingGet,
  handleOnboardingPost,
  type OnboardingRouteDependencies,
} from './handler'

const USER_ID = '00000000-0000-4000-8000-000000000951'
const AUTH_USER_ID = '00000000-0000-4000-8000-000000000952'
const REQUEST_ID = 'request-onboarding-951'
const ENDPOINT = 'https://bodyflow.test/api/mobile/v1/onboarding'

// ---------------------------------------------------------------------------
// The database behind POST /onboarding, in memory
// ---------------------------------------------------------------------------

type ConfigRow = { key: string; value: unknown }

/**
 * `public.global_config`, the three rows the rule reads, as recorded for
 * staging on 2026-10-04 (audit-10-04-goal-ladder-floors.test.ts). No database
 * was read for this file.
 */
const STAGING_CALC_ROWS: ConfigRow[] = [
  {
    key: 'calc.bf_limits',
    value: { feminino: { gain: 27, recomp: 28 }, masculino: { gain: 19, recomp: 20 } },
  },
  { key: 'calc.imc_limit_recomp', value: 25 },
  { key: 'calc.training_min', value: 3 },
]

/** When the SQL function of this file records a first completion. */
const COMPLETED_AT = '2026-10-07T15:00:00.000Z'
/** The completion time of an account that signed up before this change. */
const EARLIER_COMPLETION = '2026-09-20T12:00:00.000Z'

/** The Idempotency-Key of a completion sent with no other key named. */
const KEY = 'signup-objective-key-1'

const CLAIM = 'rpc:claim_mobile_api_request'
const PROFILE_READ = 'select:user_profiles'
const SNAPSHOT_READ = 'rpc:get_mobile_signup_body_photo_snapshot'
const CONFIG_READ = 'select:global_config'
const SQL_FUNCTION = 'rpc:complete_mobile_onboarding_with_body_photo_confirmation'
const RECORD = 'rpc:complete_mobile_api_request'
const RELEASE = 'rpc:fail_mobile_api_request'

interface DbResult {
  data: unknown
  error: { message: string } | null
}

type Failure = 'error' | 'throw' | { data: unknown }

/** The one read of live sign-up body photos on an empty catalogue. */
interface SignupBodyPhotoMemoryRead {
  columns: string[]
  filters: Array<{ operator: 'eq' | 'neq'; column: string; value: unknown }>
  order: { column: string; ascending: boolean } | null
  limit: number
}

interface SignupBodyPhotoMemoryQuery {
  abortSignal(signal: AbortSignal): SignupBodyPhotoMemoryQuery
  select(columns: string): SignupBodyPhotoMemoryQuery
  eq(column: string, value: unknown): SignupBodyPhotoMemoryQuery
  neq(column: string, value: unknown): SignupBodyPhotoMemoryQuery
  order(column: string, options: { ascending: boolean }): SignupBodyPhotoMemoryQuery
  limit(count: number): SignupBodyPhotoMemoryQuery
  maybeSingle(): Promise<DbResult>
  update(patch: Record<string, unknown>): SignupBodyPhotoMemoryQuery
  insert(row: Record<string, unknown>): SignupBodyPhotoMemoryQuery
  delete(): SignupBodyPhotoMemoryQuery
  then(
    onFulfilled: (value: DbResult) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ): Promise<unknown>
}

interface LegalDocument {
  document_key: string
  version: string
  locale: string
  content_hash: string
  purpose: string
  action_type: string
}

const DOCUMENT_V1: LegalDocument = {
  document_key: 'terms_of_service',
  version: '2026-09-15.1',
  locale: 'pt-BR',
  content_hash: 'a'.repeat(64),
  purpose: 'terms_of_service_acceptance',
  action_type: 'acceptance',
}

const DOCUMENT_V2: LegalDocument = {
  ...DOCUMENT_V1,
  version: '2026-10-07.1',
  content_hash: 'b'.repeat(64),
}

function documentActions(document: LegalDocument) {
  return [
    {
      document_key: document.document_key,
      version: document.version,
      locale: document.locale,
      content_hash: document.content_hash,
      action: document.action_type,
    },
  ]
}

interface StoredProfile {
  onboarding_completed: boolean
  onboarding_completed_at: string | null
  current_protocol: string | null
  /** What the first completion recorded, without `document_actions`. */
  answers: string | null
}

interface IdempotencyRow {
  id: string
  user_id: string
  idempotency_key: string
  request_method: string
  request_route: string
  request_hash: string
  state: 'processing' | 'completed' | 'failed'
  response_status: number | null
  response_body: unknown
  attempt_count: number
}

interface IdempotencyRequest {
  userId: string
  idempotencyKey: string
  method: string
  route: string
  requestHash: string
}

type IdempotencyAnswer =
  | { action: 'claimed'; claim_id: string }
  | { action: 'conflict' }
  | { action: 'in_progress' }
  | { action: 'replay'; response_status: number; response_body: unknown }

/**
 * `public.mobile_api_idempotency` and its three functions, as their migration
 * writes them (20260720130537_mobile_api_idempotency.sql — read, not run):
 *
 * - one row for each (user, key): `UNIQUE (user_id, idempotency_key)`;
 * - claim: with no row, inserts one as 'processing' and answers 'claimed'. With
 *   a row of another method, route or hash it answers 'conflict' WHATEVER the
 *   state of the row (lines 144-148, before the state is looked at). Then:
 *   'completed' → 'replay'; 'processing' → 'in_progress'; 'failed' → the same
 *   row goes back to 'processing' and is claimed again, under the same id;
 * - complete and fail touch only a row that is 'processing', and answer
 *   whether they found it. A failed request is NOT deleted: the row stays as
 *   'failed', with its hash (line 219).
 *
 * Not reproduced: the 24 hours after which a key is claimed as new, and the 10
 * minutes after which a 'processing' row is claimed again. No row gets that
 * old in a test.
 */
class IdempotencyLedger {
  readonly rows: IdempotencyRow[] = []

  claim(request: IdempotencyRequest): IdempotencyAnswer {
    const method = request.method.toUpperCase()
    const hash = request.requestHash.toLowerCase()
    const row = this.rows.find(
      (entry) =>
        entry.user_id === request.userId && entry.idempotency_key === request.idempotencyKey,
    )
    if (!row) {
      const id = `00000000-0000-4000-8000-${String(this.rows.length + 1).padStart(12, '0')}`
      this.rows.push({
        id,
        user_id: request.userId,
        idempotency_key: request.idempotencyKey,
        request_method: method,
        request_route: request.route,
        request_hash: hash,
        state: 'processing',
        response_status: null,
        response_body: null,
        attempt_count: 1,
      })
      return { action: 'claimed', claim_id: id }
    }
    if (
      row.request_method !== method ||
      row.request_route !== request.route ||
      row.request_hash !== hash
    ) {
      return { action: 'conflict' }
    }
    if (row.state === 'completed') {
      return {
        action: 'replay',
        response_status: row.response_status as number,
        response_body: row.response_body,
      }
    }
    if (row.state === 'processing') return { action: 'in_progress' }
    row.state = 'processing'
    row.response_status = null
    row.response_body = null
    row.attempt_count += 1
    return { action: 'claimed', claim_id: row.id }
  }

  complete(claimId: unknown, userId: unknown, status: number, body: unknown): boolean {
    const row = this.processing(claimId, userId)
    if (!row) return false
    row.state = 'completed'
    row.response_status = status
    row.response_body = body
    return true
  }

  fail(claimId: unknown, userId: unknown): boolean {
    const row = this.processing(claimId, userId)
    if (!row) return false
    row.state = 'failed'
    row.response_status = null
    row.response_body = null
    return true
  }

  private processing(claimId: unknown, userId: unknown): IdempotencyRow | undefined {
    return this.rows.find(
      (entry) => entry.id === claimId && entry.user_id === userId && entry.state === 'processing',
    )
  }
}

/** A submission without its document actions, in one fixed key order. */
function answersOf(submission: Record<string, unknown>): string {
  return JSON.stringify(
    Object.entries(submission)
      .filter(([key]) => key !== 'document_actions')
      .sort(([left], [right]) => left.localeCompare(right)),
  )
}

/**
 * It answers what the code asks on this path and nothing else: the two reads
 * of the objective check (`user_profiles.onboarding_completed_at` and the
 * `calc.*` rows), the three idempotency functions over the ledger above, and
 * `complete_mobile_onboarding_atomic` reduced to the part that matters here,
 * copied from its migration (20260915150739_bodyflow_server_owned_onboarding.sql):
 * WITHOUT a completion time the function writes the profile, `current_protocol`
 * included; WITH one it writes nothing of the profile and requires the data
 * sent again to equal the data stored. Any other table or function throws.
 * (How `numeric` rounds the stored values is not reproduced: no case here
 * resends a value of more than two decimal places to a completed account.)
 */
class SignupMemoryDb {
  readonly operations: string[] = []
  /** Every `p_submission` that reached the SQL function, as it arrived. */
  readonly submissions: unknown[] = []
  /** The columns and the filter of every profile read. */
  readonly profileReads: string[] = []
  readonly signupSnapshotReads: Record<string, unknown>[] = []
  signupSnapshotOverride: unknown | undefined
  /** Actual awaited photo reads, including their account/kind/status filters. */
  readonly bodyPhotoReads: SignupBodyPhotoMemoryRead[] = []
  readonly bodyPhotoReadSignals: AbortSignal[] = []
  /** Media/Storage attempts stay observable even when the finalizer catches an error. */
  readonly forbiddenPhotoEffects: string[] = []
  readonly failures = new Map<string, Failure>()
  calcRows: ConfigRow[] = STAGING_CALC_ROWS
  profile: StoredProfile | null = null
  /** While set, the SQL function waits for it before it reads or writes anything. */
  holdSqlFunction: Promise<void> | null = null
  /** How many calls of the SQL function are waiting for `holdSqlFunction`. */
  waitingSqlFunctions = 0
  readonly client: ServiceClient

  private readonly ledger = new IdempotencyLedger()
  private currentDocument = DOCUMENT_V1

  constructor() {
    this.client = {
      from: (table: string) => this.query(table),
      storage: {
        from: (_bucketId: string) => this.refusePhotoEffect('storage:from'),
      },
      rpc: (name: string, params: Record<string, unknown>) => {
        const pending = this.rpc(name, params)
        return Object.assign(pending, {
          abortSignal: (_signal: AbortSignal) => pending,
        })
      },
    } as unknown as ServiceClient
  }

  /** A new account: not completed, no completion time, no protocol. */
  addAccount(): this {
    this.profile = {
      onboarding_completed: false,
      onboarding_completed_at: null,
      current_protocol: null,
      answers: null,
    }
    return this
  }

  /** An account that completed the sign-up with `submission`, at `completedAt`. */
  addCompletedAccount(submission: Record<string, unknown>, completedAt: string): this {
    this.profile = {
      onboarding_completed: true,
      onboarding_completed_at: completedAt,
      current_protocol: String(submission.objective),
      answers: answersOf(submission),
    }
    return this
  }

  /**
   * An account from before `onboarding_completed_at` existed: marked completed
   * and holding a protocol, with no completion time (migration 20260915150739
   * added the column and did not fill the accounts that were already there).
   */
  addAccountCompletedWithoutDate(protocol: string): this {
    this.profile = {
      onboarding_completed: true,
      onboarding_completed_at: null,
      current_protocol: protocol,
      answers: null,
    }
    return this
  }

  /** A new version of the required document is published: completion now needs it. */
  publishNewDocumentVersion(): void {
    this.currentDocument = DOCUMENT_V2
  }

  private answer(operation: string, rows: () => DbResult): DbResult {
    this.operations.push(operation)
    const failure = this.failures.get(operation)
    if (failure === 'throw') throw new TypeError('network down for synthetic@example.invalid')
    if (failure === 'error') {
      return { data: null, error: { message: `permission denied for ${USER_ID}` } }
    }
    if (failure) return { data: failure.data, error: null }
    return rows()
  }

  private refusePhotoEffect(operation: string): never {
    this.forbiddenPhotoEffects.push(operation)
    this.operations.push(operation)
    throw new Error(`unexpected photo effect ${operation}`)
  }

  /** Only the existing catalogue adapter's listOpen query; every other shape is refused. */
  private bodyPhotoQuery(): SignupBodyPhotoMemoryQuery {
    const read: SignupBodyPhotoMemoryRead = {
      columns: [],
      filters: [],
      order: null,
      limit: Number.POSITIVE_INFINITY,
    }
    const run = async (single: boolean): Promise<DbResult> => {
      this.bodyPhotoReads.push(structuredClone(read))
      return this.answer('select:media_assets', () => {
        if (
          single ||
          JSON.stringify(read.columns) !==
            JSON.stringify([
              'id',
              'bucket_id',
              'object_path',
              'status',
              'failure_stage',
              'context_text',
              'created_at',
              'uploaded_at',
              'processing_result',
            ]) ||
          JSON.stringify(read.filters) !==
            JSON.stringify([
              { operator: 'eq', column: 'user_id', value: USER_ID },
              { operator: 'eq', column: 'kind', value: 'body_checkin_photo' },
              { operator: 'eq', column: 'signup_origin', value: true },
              { operator: 'neq', column: 'status', value: 'deleted' },
            ]) ||
          read.order === null ||
          read.order.column !== 'created_at' ||
          read.order.ascending !== false ||
          read.limit !== 1000
        ) {
          throw new Error('unexpected sign-up body-photo query')
        }
        return { data: [], error: null }
      })
    }
    const builder: SignupBodyPhotoMemoryQuery = {
      abortSignal: (signal) => {
        this.bodyPhotoReadSignals.push(signal)
        return builder
      },
      select: (selected: string) => {
        read.columns = selected.split(',').map((column) => column.trim())
        return builder
      },
      eq: (column: string, value: unknown) => {
        read.filters.push({ operator: 'eq', column, value })
        return builder
      },
      neq: (column: string, value: unknown) => {
        read.filters.push({ operator: 'neq', column, value })
        return builder
      },
      order: (column: string, options: { ascending: boolean }) => {
        read.order = { column, ascending: options.ascending }
        return builder
      },
      limit: (count: number) => {
        read.limit = count
        return builder
      },
      maybeSingle: () => run(true),
      update: (_patch: Record<string, unknown>) => this.refusePhotoEffect('update:media_assets'),
      insert: (_row: Record<string, unknown>) => this.refusePhotoEffect('insert:media_assets'),
      delete: () => this.refusePhotoEffect('delete:media_assets'),
      // biome-ignore lint/suspicious/noThenProperty: the query builder of the real client is awaitable too.
      then: (onFulfilled, onRejected) => run(false).then(onFulfilled, onRejected),
    }
    return builder
  }

  private query(table: string) {
    if (table === 'media_assets') return this.bodyPhotoQuery()
    if (table === 'user_profiles') {
      let columns: string[] = []
      const filters: Array<[string, unknown]> = []
      const builder = {
        select: (selected: string) => {
          columns = selected.split(',').map((column) => column.trim())
          return builder
        },
        eq: (column: string, value: unknown) => {
          filters.push([column, value])
          return builder
        },
        maybeSingle: async () =>
          this.answer(PROFILE_READ, () => {
            this.profileReads.push(
              `${columns.join(', ')} where ${filters.map(([column, value]) => `${column} = ${String(value)}`).join(' and ')}`,
            )
            const row: Record<string, unknown> | null = this.profile && {
              user_id: USER_ID,
              ...this.profile,
            }
            const found = row && filters.every(([column, value]) => row[column] === value)
            return {
              data: found
                ? Object.fromEntries(columns.map((column) => [column, row[column]]))
                : null,
              error: null,
            }
          }),
      }
      return builder
    }
    if (table === 'global_config') {
      // The one statement of the calc-config loader.
      return {
        select: (_columns: string) => ({
          like: async (_column: string, _pattern: string) =>
            this.answer(CONFIG_READ, () => ({ data: this.calcRows, error: null })),
        }),
      }
    }
    throw new Error(`unexpected table ${table}`)
  }

  private async rpc(name: string, params: Record<string, unknown>): Promise<DbResult> {
    if (
      (name === 'complete_mobile_onboarding_atomic' ||
        name === 'complete_mobile_onboarding_with_body_photo_confirmation') &&
      this.holdSqlFunction
    ) {
      this.waitingSqlFunctions += 1
      await this.holdSqlFunction
    }
    return this.answer(`rpc:${name}`, () => {
      if (name === 'claim_mobile_api_request') return this.claim(params)
      if (name === 'complete_mobile_api_request') return this.completeClaim(params)
      if (name === 'fail_mobile_api_request') return this.failClaim(params)
      if (name === 'prepare_mobile_signup_body_photo_disposition') {
        if (
          params.p_user_id !== USER_ID ||
          !Array.isArray(params.p_swept_generations) ||
          params.p_swept_generations.length !== 0 ||
          params.p_generation !== this.profile?.onboarding_completed_at
        )
          throw new Error('unexpected empty disposition arguments')
        // This fixture has no signup media. Native SQL separately proves sealing/cleanup.
        return {
          data: {
            version: 1,
            user_id: USER_ID,
            kind: 'empty',
            current_profile_completed:
              this.profile?.onboarding_completed === true ||
              this.profile?.onboarding_completed_at !== null,
          },
          error: null,
        }
      }
      if (name === 'get_mobile_signup_body_photo_snapshot') {
        if (params.p_user_id !== USER_ID || typeof params.p_include_open_photos !== 'boolean')
          throw new Error('unexpected signup snapshot arguments')
        this.signupSnapshotReads.push(structuredClone(params))
        if (this.signupSnapshotOverride !== undefined)
          return { data: structuredClone(this.signupSnapshotOverride), error: null }
        return {
          data: {
            version: 1,
            user_id: USER_ID,
            profile_present: this.profile !== null,
            locale: 'pt-BR',
            timezone: 'America/Sao_Paulo',
            generation_token: {
              onboarding_completed: this.profile?.onboarding_completed ?? false,
              onboarding_completed_at: this.profile?.onboarding_completed_at ?? null,
              receipt_count: 0,
            },
            poses:
              params.p_include_open_photos &&
              this.profile &&
              !this.profile.onboarding_completed &&
              this.profile.onboarding_completed_at === null
                ? ['front', 'side', 'back'].map((pose) => ({ pose, photo: null }))
                : [],
            remaining_uploads: 0,
            consent: null,
            estimate: null,
            candidate: null,
            confirmation: null,
          },
          error: null,
        }
      }
      if (name === 'complete_mobile_onboarding_with_body_photo_confirmation') {
        // This memory fixture only delegates the no-metadata/count0 compatibility path.
        // Atomicity, receipt/CAS and photo acceptance are covered in native PostgreSQL.
        if (params.p_confirmation !== null || params.p_expected_receipt_count !== 0)
          throw new Error('photo confirmation requires a dedicated native fixture')
        return this.completeOnboarding(params)
      }
      if (name === 'complete_mobile_onboarding_atomic') return this.completeOnboarding(params)
      throw new Error(`unexpected rpc ${name}`)
    })
  }

  /** The rows of the idempotency ledger: key, state and stored status. */
  idempotencyRows(): Array<{ key: string; state: string; status: number | null }> {
    return this.ledger.rows.map((row) => ({
      key: row.idempotency_key,
      state: row.state,
      status: row.response_status,
    }))
  }

  private claim(params: Record<string, unknown>): DbResult {
    return {
      data: this.ledger.claim({
        userId: String(params.p_user_id),
        idempotencyKey: String(params.p_idempotency_key),
        method: String(params.p_request_method),
        route: String(params.p_request_route),
        requestHash: String(params.p_request_hash),
      }),
      error: null,
    }
  }

  private completeClaim(params: Record<string, unknown>): DbResult {
    return {
      data: this.ledger.complete(
        params.p_claim_id,
        params.p_user_id,
        Number(params.p_response_status),
        params.p_response_body,
      ),
      error: null,
    }
  }

  private failClaim(params: Record<string, unknown>): DbResult {
    return { data: this.ledger.fail(params.p_claim_id, params.p_user_id), error: null }
  }

  private completeOnboarding(params: Record<string, unknown>): DbResult {
    const submission = params.p_submission as Record<string, unknown>
    this.submissions.push(structuredClone(submission))
    const profile = this.profile
    // IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_user_not_found'
    if (params.p_user_id !== USER_ID || !profile) {
      return { data: null, error: { message: 'onboarding_user_not_found' } }
    }

    const document = this.currentDocument
    const actions = submission.document_actions as Array<Record<string, unknown>>
    const accepted =
      actions.length === 1 &&
      Object.entries(documentActions(document)[0]).every(
        ([field, value]) => actions[0]?.[field] === value,
      )
    if (!accepted) {
      return { data: null, error: { message: 'onboarding_document_version_mismatch' } }
    }

    const answers = answersOf(submission)
    if (profile.onboarding_completed_at !== null) {
      // IF v_existing_completion IS NOT NULL: no column of the profile is
      // written; the data sent again must equal the data stored.
      if (!profile.onboarding_completed || profile.answers !== answers) {
        return { data: null, error: { message: 'onboarding_already_completed' } }
      }
    } else {
      // The only branch that writes `current_protocol`.
      profile.current_protocol = String(submission.objective)
      profile.onboarding_completed = true
      profile.onboarding_completed_at = COMPLETED_AT
      profile.answers = answers
    }

    return {
      data: {
        user_id: USER_ID,
        onboarding_completed: true,
        completed_at: profile.onboarding_completed_at,
        objective: submission.objective,
        persona: submission.persona,
        document_actions: [
          {
            document_key: document.document_key,
            version: document.version,
            locale: document.locale,
            content_hash: document.content_hash,
            purpose: document.purpose,
            action: document.action_type,
            acted_at: COMPLETED_AT,
          },
        ],
      },
      error: null,
    }
  }
}

function context(body?: unknown): MobileRouteContext {
  return {
    request: new Request(ENDPOINT, {
      method: body === undefined ? 'GET' : 'POST',
      // Every POST carries the key. A completion reads it in the handler,
      // ahead of the objective check, and no longer only inside the
      // idempotent execution these tests replace.
      headers:
        body === undefined
          ? undefined
          : { 'content-type': 'application/json', 'idempotency-key': 'onboarding-request-951' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: REQUEST_ID,
    // The objective check of a completion reads the profile and the calc
    // config from here: a new account and the cuts of staging.
    supabase: new SignupMemoryDb().addAccount().client,
    auth: {
      accessToken: 'redacted-test-token',
      authUserId: AUTH_USER_ID,
      userId: USER_ID,
      identity: {
        id: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        emailConfirmedAt: '2026-09-15T14:00:00.000Z',
      },
      patient: {
        id: USER_ID,
        authUserId: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function dependencies(repository: OnboardingRepository): OnboardingRouteDependencies {
  // A variable keeps this fixture assignable before and after the required hook is introduced.
  const values = {
    createOnboardingRepository: vi.fn(() => repository),
    executeIdempotent: vi.fn(
      async (...args: Parameters<OnboardingRouteDependencies['executeIdempotent']>) =>
        args[2]('normalized-key'),
    ),
    saveLegacyOnboarding: vi.fn(async () => ({
      profile: null,
      targets: { calories: null, protein_g: null },
    })),
    finalizeSignupBodyPhotos: vi.fn(async () => {}),
  }
  return values
}

function validBody() {
  return {
    name: 'Synthetic User',
    locale: 'pt-BR',
    country: 'BR',
    timezone: 'America/Sao_Paulo',
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    objective: 'recomposicao',
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms_of_service',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  }
}

function repository(): OnboardingRepository {
  return {
    load: vi.fn(async () => ({
      locale: 'pt-BR' as const,
      completed: false,
      completedAt: null,
      documents: [],
      acceptedActions: [],
      draft: null,
    })),
    complete: vi.fn(async () => ({
      userId: USER_ID,
      completed: true as const,
      completedAt: '2026-09-15T15:00:00.000Z',
      objective: 'recomposicao' as const,
      persona: 'focus' as const,
      documentActions: [],
    })),
  }
}

type Objective = 'recomposicao' | 'ganho_massa' | 'manutencao'

/** A repository that records whatever objective the request carries. */
function recordingRepository(): OnboardingRepository {
  return {
    ...repository(),
    complete: vi.fn(async (_userId, input) => ({
      userId: USER_ID,
      completed: true as const,
      completedAt: '2026-09-15T15:00:00.000Z',
      objective: input.objective,
      persona: 'focus' as const,
      documentActions: [],
    })),
  }
}

/** The idempotency ledger in memory, behind the real `executeIdempotent`. */
function ledger() {
  const rows = new IdempotencyLedger()
  const stored: Array<{ status: number; body: unknown }> = []
  const store: MobileIdempotencyStore = {
    async claim(input) {
      const answer = rows.claim(input)
      if (answer.action === 'claimed') return { action: 'claimed', claimId: answer.claim_id }
      if (answer.action === 'replay') {
        return { action: 'replay', status: answer.response_status, body: answer.response_body }
      }
      return answer
    },
    async complete(claimId, userId, status, body) {
      if (!rows.complete(claimId, userId, status, body)) throw new Error('unknown claim')
      stored.push({ status, body })
    },
    async fail(claimId, userId) {
      rows.fail(claimId, userId)
    },
  }
  const execute: OnboardingRouteDependencies['executeIdempotent'] = (
    requestContext,
    payload,
    operation,
    options,
  ) => executeIdempotent(requestContext, payload, store, operation, options)
  return { execute, stored, rows }
}

function completionContext(body: unknown, idempotencyKey: string): MobileRouteContext {
  const requestContext = context(body)
  requestContext.request = new Request('https://bodyflow.test/api/mobile/v1/onboarding', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'idempotency-key': idempotencyKey },
    body: JSON.stringify(body),
  })
  return requestContext
}

/** Only the authentication is a pass-through; the entitlement gate is the real one. */
function runtime(db: SignupMemoryDb): MobileRouteRuntime {
  return {
    authenticate: async () => context().auth,
    authorizeEntitlement: (auth, request, supabase) =>
      authorizeMobileEntitlement(supabase, auth.userId, new URL(request.url).pathname),
    createServiceClient: () => db.client,
    createRequestId: () => REQUEST_ID,
  }
}

/** The envelope of the route: `data` on success, `error` otherwise. */
interface CompletionJson {
  data: {
    onboarding_completed: boolean
    completed_at: string
    objective: string
    persona: string
    document_actions: unknown[]
    protocol_welcome: { protocol: string; paragraphs: string[] }
  }
  error: { code: string; message: string; request_id: string; details?: unknown }
}

/**
 * POST /onboarding as route.ts builds it: the real wrapper (error mapping
 * included) and the handler with its DEFAULT dependencies — idempotency,
 * objective check, calc-config loader, repository and service are the real
 * code, over the database in memory.
 */
async function complete(db: SignupMemoryDb, body: unknown, idempotencyKey: string | null = KEY) {
  const headers = new Headers({ 'content-type': 'application/json' })
  if (idempotencyKey !== null) headers.set('idempotency-key', idempotencyKey)
  const response = await createMobileRoute(
    handleOnboardingPost,
    runtime(db),
  )(new Request(ENDPOINT, { method: 'POST', headers, body: JSON.stringify(body) }))
  return { response, json: (await response.json()) as CompletionJson }
}

/** What POST /onboarding/eligibility, the real route, answers for these body values. */
async function eligibilityOptions(db: SignupMemoryDb, values: Record<string, unknown>) {
  const response = await createMobileRoute(
    handleOnboardingEligibilityPost,
    runtime(db),
  )(
    new Request(`${ENDPOINT}/eligibility`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': 'signup-eligibility-1' },
      body: JSON.stringify({ locale: 'pt-BR', ...values }),
    }),
  )
  expect(response.status).toBe(200)
  const json = (await response.json()) as {
    data: { options: Array<{ objective: string; status: string }> }
  }
  return json.data.options
}

/** Homem, 180 cm, 80 kg (IMC 24,69), sem gordura informada, musculação 4x: `validBody()`. */
function man(patch: Record<string, unknown> = {}): Record<string, unknown> {
  return { ...validBody(), ...patch }
}

/** Mulher, 165 cm, 62 kg (IMC 22,77), sem gordura informada, musculação 3x. */
function woman(patch: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ...validBody(),
    sex: 'feminino',
    height_cm: 165,
    weight_kg: 62,
    training_frequency: 3,
    ...patch,
  }
}

const NEW_ACCOUNT: StoredProfile = {
  onboarding_completed: false,
  onboarding_completed_at: null,
  current_protocol: null,
  answers: null,
}

/** The whole refusal: a code, a fixed sentence and the request id. */
const REFUSED = {
  error: {
    code: 'onboarding_objective_not_eligible',
    message: 'The objective is not available for the data sent',
    request_id: REQUEST_ID,
  },
}

function logs() {
  return (['log', 'info', 'warn', 'error', 'debug'] as const).map((level) =>
    vi.spyOn(console, level).mockImplementation(() => undefined),
  )
}

beforeEach(() => {
  // The calc-config loader keeps the rows for a minute.
  clearCalcConfigCache()
  // The grant of evaluation access is another module's subject (off by
  // default): it stays off here whatever the shell holds.
  vi.stubEnv(EVALUATION_ACCESS_DAYS_ENV, undefined)
  // B4a's default finalizer is exercised on the authorized synthetic target.
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
  vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', undefined)
})

describe('D2 staging completion integration', () => {
  it('rebuilds a same-key replay from the new official receipt while preserving the ORIGINAL hash', async () => {
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', 'xitugspwfxkcluxvrdeg')
    const db = new SignupMemoryDb().addAccount()
    const sources = {
      front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    }
    const body = 'Synthetic unpublished consent.'
    db.signupSnapshotOverride = {
      version: 1,
      user_id: USER_ID,
      profile_present: true,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      generation_token: {
        onboarding_completed: false,
        onboarding_completed_at: null,
        receipt_count: 0,
      },
      poses: (['front', 'side', 'back'] as const).map((pose) => ({
        pose,
        photo: { id: sources[pose], status: 'read', created_at: COMPLETED_AT },
      })),
      remaining_uploads: 6,
      consent: {
        legal_document_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        document_key: 'body_photo_estimate_consent',
        version: 'synthetic-v1',
        locale: 'pt-BR',
        body,
        body_hash: createHash('sha256').update(body).digest('hex'),
        accepted_at: COMPLETED_AT,
      },
      estimate: {
        is_estimate: true,
        by_sex: {
          masculino: { usable: true, body_fat_percent: 24 },
          feminino: { usable: true, body_fat_percent: 24 },
        },
      },
      candidate: {
        method: 'arithmetic_mean_v1',
        body_fat_percent: 24,
        source_ids: sources,
        fingerprint: 'a'.repeat(64),
      },
      confirmation: null,
    }
    const original = {
      ...validBody(),
      body_photo_confirmation: {
        decision: 'accept',
        source_ids: sources,
        fingerprint: 'a'.repeat(64),
      },
    }
    const state = ledger()
    const deps = dependencies(repository())
    deps.executeIdempotent = async (ctx, payload, operation, options) => {
      // Another request has completed between the first preflight and this claim.
      // The real executor stores this hash and refreshes its replay below.
      await state.execute(
        ctx,
        payload,
        async () =>
          new Response(
            JSON.stringify({
              data: { obsolete_source: 'must never be reused' },
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          ),
      )
      db.signupSnapshotOverride = {
        version: 1,
        user_id: USER_ID,
        profile_present: true,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        generation_token: {
          onboarding_completed: true,
          onboarding_completed_at: COMPLETED_AT,
          receipt_count: 1,
        },
        poses: [],
        remaining_uploads: 0,
        consent: null,
        estimate: null,
        candidate: null,
        confirmation: {
          decision: 'accepted',
          method: 'arithmetic_mean_v1',
          source_ids: sources,
          fingerprint: 'a'.repeat(64),
          confirmed_body_fat_percent: 24,
          decided_at: COMPLETED_AT,
          invalidated_at: null,
          active: true,
        },
      }
      vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', undefined)
      db.failures.set(CONFIG_READ, 'error')
      return state.execute(ctx, payload, operation, options)
    }
    const ctx = context(original)
    ctx.supabase = db.client
    const response = await handleOnboardingPost(ctx, deps)
    const result = await response.json()
    expect(response.status).toBe(200)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(result.data).not.toHaveProperty('obsolete_source')
    expect(result.data.protocol_welcome.protocol).toBe('recomposicao')
    expect(db.signupSnapshotReads).toEqual([
      { p_user_id: USER_ID, p_include_open_photos: true },
      { p_user_id: USER_ID, p_include_open_photos: false },
    ])
    expect(deps.createOnboardingRepository).toHaveBeenCalledWith(db.client, {
      signupPhotoConfirmation: expect.objectContaining({
        mode: 'historic_accept',
        snapshot: expect.objectContaining({
          generation_token: {
            onboarding_completed: true,
            onboarding_completed_at: COMPLETED_AT,
            receipt_count: 1,
          },
        }),
      }),
    })
    expect(state.rows.rows).toHaveLength(1)
    expect(state.rows.rows[0]?.request_hash).toBe(hashMobileRequest(original))
    expect(state.rows.rows[0]?.state).toBe('completed')
    expect(original).not.toHaveProperty('body_fat_percent')
    expect(state.stored).toHaveLength(1)
  })

  it('uses one profile-only snapshot and the checked SQL entry even without metadata and photos OFF', async () => {
    const db = new SignupMemoryDb().addAccount()
    const body = validBody()
    const { response } = await complete(db, body)
    expect(response.status).toBe(200)
    expect(db.operations).toEqual([
      'rpc:get_mobile_signup_body_photo_snapshot',
      CONFIG_READ,
      CLAIM,
      'rpc:complete_mobile_onboarding_with_body_photo_confirmation',
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
    expect(db.signupSnapshotReads).toEqual([{ p_user_id: USER_ID, p_include_open_photos: false }])
    expect(db.profileReads).toEqual([])
    expect(db.submissions).toEqual([body])
  })

  it('uses the confirmed mean for objective eligibility before claiming, preserving the original intent', async () => {
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', 'xitugspwfxkcluxvrdeg')
    const db = new SignupMemoryDb().addAccount()
    const sources = {
      front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    }
    const consentBody = 'Synthetic unpublished consent.'
    db.signupSnapshotOverride = {
      version: 1,
      user_id: USER_ID,
      profile_present: true,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      generation_token: {
        onboarding_completed: false,
        onboarding_completed_at: null,
        receipt_count: 0,
      },
      poses: (['front', 'side', 'back'] as const).map((pose) => ({
        pose,
        photo: { id: sources[pose], status: 'read', created_at: COMPLETED_AT },
      })),
      remaining_uploads: 6,
      consent: {
        legal_document_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        document_key: 'body_photo_estimate_consent',
        version: 'synthetic-v1',
        locale: 'pt-BR',
        body: consentBody,
        body_hash: createHash('sha256').update(consentBody).digest('hex'),
        accepted_at: COMPLETED_AT,
      },
      estimate: {
        is_estimate: true,
        by_sex: {
          masculino: { usable: true, body_fat_percent: 24 },
          feminino: { usable: true, body_fat_percent: 24 },
        },
      },
      candidate: {
        method: 'arithmetic_mean_v1',
        body_fat_percent: 24,
        source_ids: sources,
        fingerprint: 'a'.repeat(64),
      },
      confirmation: null,
    }
    const original = {
      ...validBody(),
      objective: 'ganho_massa',
      body_photo_confirmation: {
        decision: 'accept',
        source_ids: sources,
        fingerprint: 'a'.repeat(64),
      },
    }
    const { response, json } = await complete(db, original)
    expect(response.status).toBe(422)
    expect(json).toEqual(REFUSED)
    expect(db.operations).toEqual(['rpc:get_mobile_signup_body_photo_snapshot', CONFIG_READ])
    expect(db.idempotencyRows()).toEqual([])
    expect(db.submissions).toEqual([])
    expect(original).not.toHaveProperty('body_fat_percent')
    expect(original.body_photo_confirmation.fingerprint).toBe('a'.repeat(64))
  })
})

afterEach(() => {
  clearCalcConfigCache()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('D2 confirmation target guard before the idempotency claim', () => {
  const confirmation = {
    decision: 'accept',
    source_ids: {
      front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    },
    fingerprint: 'a'.repeat(64),
  }

  it.each([
    ['unknown target', undefined, confirmation],
    ['old production target', 'https://xuxehkhdvjivitduarvb.supabase.co', confirmation],
    [
      'decline on old production',
      'https://xuxehkhdvjivitduarvb.supabase.co',
      { decision: 'decline' },
    ],
  ])('refuses %s without a claim, completion or cleanup', async (_case, url, intent) => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', url as string | undefined)
    const repo = repository()
    const deps = dependencies(repo)

    await expect(
      handleOnboardingPost(context({ ...validBody(), body_photo_confirmation: intent }), deps),
    ).rejects.toMatchObject({ status: 404, code: 'body_photos_unavailable' })

    expect(deps.executeIdempotent).not.toHaveBeenCalled()
    expect(repo.complete).not.toHaveBeenCalled()
    expect(deps.finalizeSignupBodyPhotos).not.toHaveBeenCalled()
  })
})

describe('mobile onboarding route', () => {
  it('loads server-owned state for the authenticated user and locale', async () => {
    const repo = repository()
    const response = await handleOnboardingGet(context(), dependencies(repo))

    expect(repo.load).toHaveBeenCalledWith(USER_ID, 'pt-BR')
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
  })

  it('completes inside idempotency using only the authenticated user identity', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const response = await handleOnboardingPost(context(validBody()), deps)

    expect(deps.executeIdempotent).toHaveBeenCalledOnce()
    expect(repo.complete).toHaveBeenCalledWith(USER_ID, validBody())
    expect(response.status).toBe(200)
    const responseBody = await response.json()
    expect(responseBody).toMatchObject({ data: { onboarding_completed: true } })
    expect(responseBody.data).not.toHaveProperty('user_id')
    expect(AUTH_USER_ID).not.toBe(USER_ID)
  })

  it('revalidates current requirements when an exact completion request is replayed', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    deps.executeIdempotent = vi.fn(async (_context, _payload, operation, options) => {
      await operation('normalized-key')
      if (!options.refreshReplay) throw new Error('Expected completion replay revalidation')
      return options.refreshReplay({ action: 'replay', body: {}, status: 200 })
    })

    const response = await handleOnboardingPost(context(validBody()), deps)

    expect(response.status).toBe(200)
    expect(repo.complete).toHaveBeenCalledTimes(2)
  })

  // The words of each entry message are pinned, in both languages, in
  // packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts.
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('returns the entry message of the recorded objective: %s', async (objective: Objective) => {
    const repo = recordingRepository()
    const body = { ...validBody(), objective }

    const response = await handleOnboardingPost(context(body), dependencies(repo))

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      onboarding_completed: true,
      completed_at: '2026-09-15T15:00:00.000Z',
      objective,
      persona: 'focus',
      document_actions: [],
      protocol_welcome: {
        protocol: objective,
        paragraphs: protocolWelcomeMessage(objective, 'Synthetic User', 'pt-BR'),
      },
    })
  })

  it('writes the entry message in the language of the request and with the name it carries', async () => {
    const repo = recordingRepository()
    const body = { ...validBody(), name: '  Ana Clara  ', locale: 'en-US', objective: 'manutencao' }

    const response = await handleOnboardingPost(context(body), dependencies(repo))

    const { data } = await response.json()
    expect(data.protocol_welcome).toEqual({
      protocol: 'manutencao',
      paragraphs: protocolWelcomeMessage('manutencao', 'Ana Clara', 'en-US'),
    })
    expect(data.protocol_welcome.paragraphs[0]).toMatch(
      /^Ana Clara, you are now entering the maintenance phase /,
    )
    // The account's own name and locale are not consulted: the request's are.
    expect(data.protocol_welcome.paragraphs[0]).not.toContain('Synthetic')
  })

  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('keeps the entry message out of the idempotency record and returns it again on every replay: %s', async (objective: Objective) => {
    const repo = recordingRepository()
    const deps = dependencies(repo)
    const { execute, stored } = ledger()
    deps.executeIdempotent = execute
    const body = { ...validBody(), objective }
    const key = `onboarding-welcome-${objective}`

    const first = await handleOnboardingPost(completionContext(body, key), deps)
    const firstBody = await first.json()

    expect(first.status).toBe(200)
    expect(first.headers.get('idempotency-replayed')).toBeNull()
    expect(firstBody.data.protocol_welcome).toEqual({
      protocol: objective,
      paragraphs: protocolWelcomeMessage(objective, 'Synthetic User', 'pt-BR'),
    })
    // What the ledger keeps is the response as it was before this field
    // existed: no entry message, and so no name of the person.
    expect(stored).toEqual([
      {
        status: 200,
        body: {
          data: {
            onboarding_completed: true,
            completed_at: '2026-09-15T15:00:00.000Z',
            objective,
            persona: 'focus',
            document_actions: [],
          },
          meta: { api_version: 'v1', request_id: 'request-onboarding-951' },
        },
      },
    ])
    expect(JSON.stringify(stored)).not.toContain('Synthetic User')
    expect(JSON.stringify(stored)).not.toContain('protocol_welcome')

    for (const attempt of [2, 3]) {
      const replay = await handleOnboardingPost(completionContext(body, key), deps)

      expect(replay.status).toBe(200)
      expect(replay.headers.get('idempotency-replayed')).toBe('true')
      expect(await replay.json()).toEqual(firstBody)
      expect(repo.complete).toHaveBeenCalledTimes(attempt)
    }
    expect(stored).toHaveLength(1)
  })

  it('a replay with another payload under the same key is still a conflict', async () => {
    const repo = recordingRepository()
    const deps = dependencies(repo)
    deps.executeIdempotent = ledger().execute
    const key = 'onboarding-welcome-conflict'

    await handleOnboardingPost(completionContext(validBody(), key), deps)

    await expect(
      handleOnboardingPost(
        completionContext({ ...validBody(), objective: 'manutencao' }, key),
        deps,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
    expect(repo.complete).toHaveBeenCalledTimes(1)
  })

  it('the legacy partial update carries no entry message and its record is stored whole', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const { execute, stored } = ledger()
    deps.executeIdempotent = execute

    const response = await handleOnboardingPost(
      completionContext({ height_cm: 180 }, 'onboarding-legacy-partial'),
      deps,
    )
    const body = await response.json()

    expect(body.data).toEqual({ profile: null, targets: { calories: null, protein_g: null } })
    expect(stored).toEqual([{ status: 200, body }])
  })

  it('rejects caller-owned state before idempotency or persistence', async () => {
    const repo = repository()
    const deps = dependencies(repo)

    await expect(
      handleOnboardingPost(
        context({ ...validBody(), user_id: '00000000-0000-4000-8000-000000000999' }),
        deps,
      ),
    ).rejects.toThrow()
    expect(deps.executeIdempotent).not.toHaveBeenCalled()
    expect(repo.complete).not.toHaveBeenCalled()
  })

  it('preserves the legacy partial update response while forbidding client completion', async () => {
    const repo = repository()
    const deps = dependencies(repo)
    const response = await handleOnboardingPost(
      context({ height_cm: 180, onboarding_completed: false }),
      deps,
    )

    expect(deps.saveLegacyOnboarding).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: USER_ID, authUserId: AUTH_USER_ID }),
      { height_cm: 180 },
      'normalized-key',
    )
    expect(repo.complete).not.toHaveBeenCalled()
    await expect(response.json()).resolves.toMatchObject({
      data: {
        profile: null,
        targets: { calories: null, protein_g: null },
      },
    })

    await expect(
      handleOnboardingPost(context({ onboarding_completed: true }), deps),
    ).rejects.toThrow()
  })

  it('fails closed for an unsupported authenticated locale', async () => {
    const repo = repository()
    const requestContext = context()
    requestContext.auth.patient.locale = 'fr-FR'

    await expect(handleOnboardingGet(requestContext, dependencies(repo))).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_locale_unsupported',
    })
    expect(repo.load).not.toHaveBeenCalled()
  })
})

// ---------------------------------------------------------------------------
// The objective check of the completion (docs/CALCULO-MPP.md §10o;
// docs/mobile/api-v1.md "Objetivo fora da regra na conclusão").
//
// Everything between the request and the database is the real code: the route
// wrapper, the handler with its default dependencies, the idempotency, the
// check (onboarding-eligibility-guard.ts), the calc-config loader, the rule
// (`decideSignupEligibility`) and the repository. The database is the one in
// memory at the top of this file. No network.
//
// NUMBERS — the client's cuts and their neighbours (19 / 20 / 27 / 28 %, BMI
// 25.0, 2 and 3 sessions), the same as the golden of the rule
// (packages/agent/src/__golden__/audit-10-07-signup-eligibility.test.ts). No
// patient: weights and heights are chosen to land on the BMI named in each
// case.
// ---------------------------------------------------------------------------

describe('POST /onboarding — a first completion records only an objective the rule allows', () => {
  const ACCEPTED: Array<[string, Record<string, unknown>]> = [
    [
      'man with 20.0% of body fat asking recomposição',
      man({ body_fat_percent: 20, objective: 'recomposicao' }),
    ],
    [
      'woman with 27.0% and 3 sessions asking ganho de massa',
      woman({ body_fat_percent: 27, training_frequency: 3, objective: 'ganho_massa' }),
    ],
    [
      'woman with 27.0% and 2 sessions asking manutenção',
      woman({ body_fat_percent: 27, training_frequency: 2, objective: 'manutencao' }),
    ],
    [
      'no body fat, 79.38 kg / 180 cm (BMI 24.5) and 3 sessions asking ganho de massa (the cut is "less than 25")',
      man({ weight_kg: 79.38, training_frequency: 3, objective: 'ganho_massa' }),
    ],
    [
      'man with 15%, 3 sessions, in bed at 02:00, up at 07:00, eating not organised, asking ganho de massa (sleep and eating are not read)',
      man({
        body_fat_percent: 15,
        training_frequency: 3,
        bedtime: '02:00',
        wake_time: '07:00',
        food_organization: 'nao',
        objective: 'ganho_massa',
      }),
    ],
  ]

  it.each(ACCEPTED)('%s → completes', async (_case, body) => {
    const db = new SignupMemoryDb().addAccount()

    const { response, json } = await complete(db, body)

    expect(response.status).toBe(200)
    expect(json.data).toMatchObject({
      onboarding_completed: true,
      completed_at: COMPLETED_AT,
      objective: body.objective,
      protocol_welcome: { protocol: body.objective },
    })
    // The check first, and only then the key is claimed.
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CONFIG_READ,
      CLAIM,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
    expect(db.idempotencyRows()).toEqual([{ key: KEY, state: 'completed', status: 200 }])
    // The submission reaches the SQL function whole and unchanged.
    expect(db.submissions).toEqual([body])
    expect(db.profile).toMatchObject({
      current_protocol: body.objective,
      onboarding_completed_at: COMPLETED_AT,
    })
  })

  const REFUSED_CASES: Array<[string, Record<string, unknown>]> = [
    [
      'man with 20.0% of body fat asking ganho de massa',
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
    ],
    [
      'man with 20.0% of body fat asking manutenção',
      man({ body_fat_percent: 20, objective: 'manutencao' }),
    ],
    [
      'woman with 27.0% and 2 sessions asking ganho de massa',
      woman({ body_fat_percent: 27, training_frequency: 2, objective: 'ganho_massa' }),
    ],
    [
      'no body fat, 64 kg / 160 cm (BMI 25.0) asking manutenção',
      woman({ height_cm: 160, weight_kg: 64, objective: 'manutencao' }),
    ],
    [
      'no body fat, 81 kg / 180 cm (BMI 25.0) and 3 sessions asking ganho de massa',
      man({ weight_kg: 81, training_frequency: 3, objective: 'ganho_massa' }),
    ],
    [
      'man with 19.995% of body fat (stored as 20.00%) asking manutenção',
      man({ body_fat_percent: 19.995, objective: 'manutencao' }),
    ],
  ]

  it.each(REFUSED_CASES)('%s → 422, and the SQL function is not called', async (_case, body) => {
    const spies = logs()
    const db = new SignupMemoryDb().addAccount()

    const { response, json } = await complete(db, body)

    expect(response.status).toBe(422)
    expect(json).toEqual(REFUSED)
    // Refused before the key is claimed: the two reads, and no row in the ledger.
    expect(db.operations).toEqual([SNAPSHOT_READ, CONFIG_READ])
    expect(db.idempotencyRows()).toEqual([])
    expect(db.submissions).toEqual([])
    expect(db.profile).toEqual(NEW_ACCOUNT)
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  it('decides on the value as the profile stores it, and still hands the SQL function the value as it was sent', async () => {
    // 19.994% is stored as 19.99%: below the cut of 20, so he chooses.
    const db = new SignupMemoryDb().addAccount()
    const body = man({ body_fat_percent: 19.994, objective: 'manutencao' })

    const { response } = await complete(db, body)

    expect(response.status).toBe(200)
    expect(db.submissions).toEqual([body])
    expect((db.submissions[0] as { body_fat_percent: number }).body_fat_percent).toBe(19.994)

    // 80.999 kg is stored as 81.00 kg: BMI 25.0 at 180 cm.
    const other = new SignupMemoryDb().addAccount()
    const refused = await complete(
      other,
      man({ weight_kg: 80.999, training_frequency: 3, objective: 'ganho_massa' }),
    )

    expect(refused.response.status).toBe(422)
    expect(refused.json).toEqual(REFUSED)
    expect(other.submissions).toEqual([])
  })

  it('the cuts are the rows of the calc config, as in the eligibility check: with calc.training_min = 4, 3 sessions no longer do', async () => {
    const rows = STAGING_CALC_ROWS.map((row) =>
      row.key === 'calc.training_min' ? { key: row.key, value: 4 } : row,
    )
    const three = new SignupMemoryDb().addAccount()
    three.calcRows = rows
    const four = new SignupMemoryDb().addAccount()
    four.calcRows = rows

    const refused = await complete(
      three,
      woman({ body_fat_percent: 27, training_frequency: 3, objective: 'ganho_massa' }),
    )
    const accepted = await complete(
      four,
      woman({ body_fat_percent: 27, training_frequency: 4, objective: 'ganho_massa' }),
    )

    expect(refused.response.status).toBe(422)
    expect(three.submissions).toEqual([])
    expect(accepted.response.status).toBe(200)
    expect(four.profile?.current_protocol).toBe('ganho_massa')
  })

  it('accepts exactly what the eligibility check marks available: every objective, around every cut', async () => {
    const bodies: Array<Record<string, unknown>> = [
      ...[18.99, 19, 19.004, 19.005, 19.5, 19.994, 19.995, 20, 25].flatMap((bodyFat) =>
        [2, 3].map((sessions) => ({
          sex: 'masculino',
          height_cm: 180,
          weight_kg: 80,
          body_fat_percent: bodyFat,
          training_frequency: sessions,
        })),
      ),
      ...[26.99, 27, 27.004, 27.005, 27.5, 27.994, 27.995, 28].flatMap((bodyFat) =>
        [2, 3].map((sessions) => ({
          sex: 'feminino',
          height_cm: 165,
          weight_kg: 62,
          body_fat_percent: bodyFat,
          training_frequency: sessions,
        })),
      ),
      // No body fat: the BMI decides (79.38, 80.99 and 81 kg at 180 cm; 64 kg at 160 cm).
      ...[79.38, 80.994, 80.999, 81].flatMap((weight) =>
        [2, 3].map((sessions) => ({
          sex: 'masculino',
          height_cm: 180,
          weight_kg: weight,
          training_frequency: sessions,
        })),
      ),
      { sex: 'feminino', height_cm: 160, weight_kg: 64, training_frequency: 3 },
      { sex: 'feminino', height_cm: 160, weight_kg: 63.99, training_frequency: 3 },
    ]
    const seen = new Set<string>()

    for (const values of bodies) {
      const options = await eligibilityOptions(new SignupMemoryDb(), values)
      expect(options.map((option) => option.objective)).toEqual([
        'recomposicao',
        'ganho_massa',
        'manutencao',
      ])

      for (const { objective, status } of options) {
        seen.add(status)
        const db = new SignupMemoryDb().addAccount()

        const { response } = await complete(db, { ...validBody(), ...values, objective })

        const label = `${JSON.stringify(values)} asking ${objective} (${status})`
        expect(response.status, label).toBe(status === 'available' ? 200 : 422)
        expect(db.submissions, label).toHaveLength(status === 'available' ? 1 : 0)
        expect(db.profile?.current_protocol ?? null, label).toBe(
          status === 'available' ? objective : null,
        )
      }
    }
    // The grid went through the three answers of the check.
    expect([...seen].sort()).toEqual(['available', 'blocked', 'not_offered'])
  })

  it('the refusal carries no value of the request, no reason and no detail, and nothing is logged', async () => {
    const spies = logs()
    const db = new SignupMemoryDb().addAccount()

    const { response, json } = await complete(
      db,
      man({
        name: 'Marina Synthetic',
        height_cm: 181.37,
        weight_kg: 77.31,
        body_fat_percent: 23.37,
        training_frequency: 1,
        objective: 'ganho_massa',
      }),
    )

    expect(response.status).toBe(422)
    expect(json).toEqual(REFUSED)
    expect(Object.keys(json.error).sort()).toEqual(['code', 'message', 'request_id'])
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    const serialized = JSON.stringify(json)
    for (const value of [
      '181.37',
      '77.31',
      '23.37',
      'Marina',
      'ganho',
      'gain',
      'composition',
      'training',
      'recomp',
    ]) {
      expect(serialized).not.toContain(value)
    }
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  // THE SCENARIO OF THE PUBLISHED APP (adversarial review of 2026-10-07). The
  // app keeps the Idempotency-Key of a completion until the server answers a
  // success, a change of requirements or "already completed"
  // (OnboardingFlowModel.swift, `pendingCompletionKey`). After this 422 the
  // person goes back, touches another objective and concludes UNDER THE SAME
  // KEY. The ledger here is the one of the migration: had the refusal claimed
  // the key, its row would stay as 'failed' with the hash of the refused
  // request, and the corrected request would be answered
  // 409 idempotency_key_conflict — on every try, for 24 hours.
  it.each<[string, Objective]>([
    ['man with 20.0% of body fat asking manutenção', 'manutencao'],
    ['man with 20.0% of body fat asking ganho de massa', 'ganho_massa'],
  ])('%s, then the same request again, then recomposição, all under ONE Idempotency-Key → 422, 422, completes', async (_case, objective) => {
    const db = new SignupMemoryDb().addAccount()
    const key = 'signup-objective-retry-1'
    const refusedBody = man({ body_fat_percent: 20, objective })
    const correctedBody = man({ body_fat_percent: 20, objective: 'recomposicao' })

    const refused = await complete(db, refusedBody, key)
    const again = await complete(db, refusedBody, key)

    expect(refused.response.status).toBe(422)
    expect(refused.json).toEqual(REFUSED)
    // Decided again, not read back from a stored answer.
    expect(again.response.status).toBe(422)
    expect(again.json).toEqual(REFUSED)
    expect(again.response.headers.get('idempotency-replayed')).toBeNull()
    // Neither refusal reached the ledger: the key is still free.
    expect(db.operations).not.toContain(CLAIM)
    expect(db.operations).not.toContain(RELEASE)
    expect(db.idempotencyRows()).toEqual([])

    const corrected = await complete(db, correctedBody, key)

    expect(corrected.response.status).toBe(200)
    expect(corrected.response.headers.get('idempotency-replayed')).toBeNull()
    expect(corrected.json.data).toMatchObject({
      onboarding_completed: true,
      completed_at: COMPLETED_AT,
      objective: 'recomposicao',
    })
    expect(db.idempotencyRows()).toEqual([{ key, state: 'completed', status: 200 }])
    expect(db.submissions).toEqual([correctedBody])
    expect(db.profile?.current_protocol).toBe('recomposicao')
  })

  // Why the order matters, on the ledger as the migration writes it. A
  // completion that fails AFTER the claim leaves its key tied to its body: the
  // row stays, 'failed', with its hash. That was so before this change and is
  // not the check's doing; the check answers ahead of it and adds no such row.
  it('a key tied to another body by a completion that failed after the claim: the refusal still comes first (422), and the key answers 409 to any other body, as before', async () => {
    const db = new SignupMemoryDb().addAccount()
    const key = 'signup-objective-failed-1'
    const body = man({ body_fat_percent: 20, objective: 'recomposicao' })
    db.failures.set(SQL_FUNCTION, 'error')

    const failed = await complete(db, body, key)
    db.failures.clear()

    expect(failed.response.status).toBe(500)
    expect(failed.json.error.code).toBe('onboarding_persistence_failed')
    expect(db.idempotencyRows()).toEqual([{ key, state: 'failed', status: null }])

    // The objective changed to one outside the rule: the check answers.
    const refused = await complete(db, man({ body_fat_percent: 20, objective: 'manutencao' }), key)

    expect(refused.response.status).toBe(422)
    expect(refused.json).toEqual(REFUSED)
    expect(db.idempotencyRows()).toEqual([{ key, state: 'failed', status: null }])

    // Another body the rule allows: the ledger's own conflict, whatever the state.
    const other = await complete(
      db,
      man({ body_fat_percent: 20, training_frequency: 5, objective: 'recomposicao' }),
      key,
    )

    expect(other.response.status).toBe(409)
    expect(other.json.error.code).toBe('idempotency_key_conflict')

    // The body the key belongs to is claimed again, and completes.
    const retried = await complete(db, body, key)

    expect(retried.response.status).toBe(200)
    expect(retried.response.headers.get('idempotency-replayed')).toBeNull()
    expect(db.idempotencyRows()).toEqual([{ key, state: 'completed', status: 200 }])
    expect(db.submissions).toEqual([body])
    expect(db.profile?.current_protocol).toBe('recomposicao')
  })

  it('the same request sent twice at once: both pass the check, one is recorded and its twin is answered 409 in progress, as before', async () => {
    const db = new SignupMemoryDb().addAccount()
    const key = 'signup-objective-twin-1'
    const body = man({ body_fat_percent: 20, objective: 'recomposicao' })
    let release = () => {}
    db.holdSqlFunction = new Promise<void>((resolve) => {
      release = resolve
    })

    const first = complete(db, body, key)
    await vi.waitFor(() => expect(db.waitingSqlFunctions).toBe(1))
    // The first has claimed the key and recorded nothing yet.
    const twin = await complete(db, body, key)
    release()
    const recorded = await first

    expect(twin.response.status).toBe(409)
    expect(twin.json.error.code).toBe('idempotency_request_in_progress')
    expect(recorded.response.status).toBe(200)
    expect(db.operations.filter((operation) => operation === SNAPSHOT_READ)).toHaveLength(2)
    expect(db.submissions).toEqual([body])
    expect(db.idempotencyRows()).toEqual([{ key, state: 'completed', status: 200 }])
  })

  it('reads one server snapshot of the authenticated account, with no second profile lookup', async () => {
    const db = new SignupMemoryDb().addAccount()

    await complete(db, man())

    expect(db.profileReads).toEqual([])
    expect(db.signupSnapshotReads).toEqual([{ p_user_id: USER_ID, p_include_open_photos: false }])
  })

  it.each<[string, string | null, string]>([
    ['without it', null, 'missing_idempotency_key'],
    ['with one that is not valid', 'short', 'invalid_idempotency_key'],
  ])('the Idempotency-Key is still asked for first: %s nothing is read and nothing is decided', async (_case, key, code) => {
    const db = new SignupMemoryDb().addAccount()

    const { response, json } = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
      key,
    )

    expect(response.status).toBe(400)
    expect(json.error.code).toBe(code)
    expect(db.operations).toEqual([])
  })

  // The check answers before every refusal of the SQL function, not only the
  // one of an account with no profile row (last test of this file). Nothing is
  // recorded either way.
  it('a first completion outside the rule AND with a document version that is no longer the current one is answered by the check (422); inside the rule, by the SQL function as before (409)', async () => {
    const db = new SignupMemoryDb().addAccount()
    db.publishNewDocumentVersion()

    const outside = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
      'signup-objective-old-document-1',
    )
    const inside = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'recomposicao' }),
      'signup-objective-old-document-2',
    )

    expect(outside.response.status).toBe(422)
    expect(outside.json).toEqual(REFUSED)
    expect(inside.response.status).toBe(409)
    expect(inside.json.error.code).toBe('onboarding_requirements_changed')
    expect(db.submissions).toHaveLength(1)
    expect(db.profile).toEqual(NEW_ACCOUNT)
  })

  // "Nothing is decided on a default" is about a read that FAILS (last block
  // of this file). A read that succeeds and brings no `calc.*` row, or a row
  // that holds no number, gives the cut of the code — the loader and the rule
  // do that for the eligibility check too, so the two still agree.
  it('a calc config read that succeeds with no row decides on the cuts of the code, as the eligibility check does', async () => {
    const refusing = new SignupMemoryDb().addAccount()
    refusing.calcRows = []
    const accepting = new SignupMemoryDb().addAccount()
    accepting.calcRows = []

    const options = await eligibilityOptions(refusing, {
      sex: 'masculino',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: 20,
      training_frequency: 4,
    })
    const refused = await complete(refusing, man({ body_fat_percent: 20, objective: 'manutencao' }))
    const accepted = await complete(
      accepting,
      man({ body_fat_percent: 19.99, objective: 'manutencao' }),
    )

    expect(options.find((option) => option.objective === 'manutencao')?.status).toBe('not_offered')
    expect(refused.response.status).toBe(422)
    expect(refused.json).toEqual(REFUSED)
    expect(refusing.operations).toEqual([CONFIG_READ, SNAPSHOT_READ])
    expect(accepted.response.status).toBe(200)
    expect(accepting.profile?.current_protocol).toBe('manutencao')
  })

  it('a calc row that holds a text instead of a number gives the cut of the code for that cut: with calc.training_min = "4", 3 sessions still do', async () => {
    const db = new SignupMemoryDb().addAccount()
    db.calcRows = STAGING_CALC_ROWS.map((row) =>
      row.key === 'calc.training_min' ? { key: row.key, value: '4' } : row,
    )

    const { response } = await complete(
      db,
      woman({ body_fat_percent: 27, training_frequency: 3, objective: 'ganho_massa' }),
    )

    expect(response.status).toBe(200)
    expect(db.profile?.current_protocol).toBe('ganho_massa')
  })

  it('the legacy partial update is not a completion: nothing is read for the check', async () => {
    const db = new SignupMemoryDb().addAccount()
    const requestContext = context({ height_cm: 180 })
    requestContext.supabase = db.client

    const response = await handleOnboardingPost(requestContext, dependencies(repository()))

    expect(response.status).toBe(200)
    expect(db.operations).toEqual([])
  })
})

describe('POST /onboarding — an account that already has a completion time is not checked', () => {
  it('new terms re-accepted by an account already in ganho de massa outside the criteria (man, 25% of body fat) → completes, with no check', async () => {
    const stored = man({ body_fat_percent: 25, objective: 'ganho_massa' })
    const db = new SignupMemoryDb().addCompletedAccount(stored, EARLIER_COMPLETION)
    db.publishNewDocumentVersion()
    const body = { ...stored, document_actions: documentActions(DOCUMENT_V2) }

    const { response, json } = await complete(db, body)

    expect(response.status).toBe(200)
    expect(json.data).toMatchObject({
      onboarding_completed: true,
      completed_at: EARLIER_COMPLETION,
      objective: 'ganho_massa',
      protocol_welcome: { protocol: 'ganho_massa' },
    })
    expect(json.data.document_actions).toMatchObject([{ version: DOCUMENT_V2.version }])
    // One read of the profile; the calc config is not even loaded.
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CLAIM,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
    expect(db.submissions).toEqual([body])
    expect(db.profile).toMatchObject({
      current_protocol: 'ganho_massa',
      onboarding_completed_at: EARLIER_COMPLETION,
    })
  })

  it.each<[string, Record<string, unknown>]>([
    [
      'a man with 25% of body fat in ganho de massa',
      man({ body_fat_percent: 25, objective: 'ganho_massa' }),
    ],
    [
      'a woman with 30% of body fat in manutenção',
      woman({ body_fat_percent: 30, objective: 'manutencao' }),
    ],
    [
      'a man with no body fat, 81 kg / 180 cm (BMI 25.0) and no strength training in ganho de massa',
      man({ weight_kg: 81, training_frequency: 0, objective: 'ganho_massa' }),
    ],
  ])('%s re-accepts while the calc config cannot be read → completes all the same', async (_case, stored) => {
    const db = new SignupMemoryDb().addCompletedAccount(stored, EARLIER_COMPLETION)
    db.publishNewDocumentVersion()
    db.failures.set(CONFIG_READ, 'error')

    const { response, json } = await complete(db, {
      ...stored,
      document_actions: documentActions(DOCUMENT_V2),
    })

    expect(response.status).toBe(200)
    expect(json.data.objective).toBe(stored.objective)
    expect(json.data.completed_at).toBe(EARLIER_COMPLETION)
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CLAIM,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
    expect(db.profile?.current_protocol).toBe(stored.objective)
  })

  it('replay of a completed request → the same response, with no check — even after the cuts changed against it', async () => {
    const db = new SignupMemoryDb().addAccount()
    const body = woman({ body_fat_percent: 27, training_frequency: 3, objective: 'ganho_massa' })
    const key = 'signup-objective-replay-1'

    const first = await complete(db, body, key)

    expect(first.response.status).toBe(200)
    expect(first.response.headers.get('idempotency-replayed')).toBeNull()
    expect(first.json.data.protocol_welcome).toEqual({
      protocol: 'ganho_massa',
      paragraphs: protocolWelcomeMessage('ganho_massa', 'Synthetic User', 'pt-BR'),
    })

    // From here on the rule would refuse her: 3 sessions under a minimum of 4.
    db.calcRows = STAGING_CALC_ROWS.map((row) =>
      row.key === 'calc.training_min' ? { key: row.key, value: 4 } : row,
    )
    clearCalcConfigCache()
    db.operations.length = 0

    for (const _attempt of [2, 3]) {
      const replay = await complete(db, body, key)

      expect(replay.response.status).toBe(200)
      expect(replay.response.headers.get('idempotency-replayed')).toBe('true')
      expect(replay.json).toEqual(first.json)
    }
    // As before this change, the SQL function validates each replay again. The
    // profile now has its completion time: one read of it, and no check.
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CLAIM,
      SNAPSHOT_READ,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      SNAPSHOT_READ,
      CLAIM,
      SNAPSHOT_READ,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
    ])
    expect(db.idempotencyRows()).toEqual([{ key, state: 'completed', status: 200 }])
    expect(db.submissions).toEqual([body, body, body])
    expect(db.profile?.current_protocol).toBe('ganho_massa')
  })

  // The completion time as the database client hands it over: a text with an
  // offset, with or without a fraction of a second.
  it.each([
    '2026-09-20T12:00:00+00:00',
    '2026-09-20T12:00:00.123456+00:00',
    '2026-09-20T09:00:00.5-03:00',
  ])('a completion time written as %s is a completion time: the account is not checked', async (completedAt) => {
    const stored = man({ body_fat_percent: 25, objective: 'ganho_massa' })
    const db = new SignupMemoryDb().addCompletedAccount(stored, completedAt)

    const { response, json } = await complete(db, stored)

    expect(response.status).toBe(200)
    expect(json.data.completed_at).toBe(completedAt)
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CLAIM,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
  })

  it('the same answers under a new Idempotency-Key, after the cuts changed against them → completes, with no check', async () => {
    const db = new SignupMemoryDb().addAccount()
    const body = man({ body_fat_percent: 19, training_frequency: 3, objective: 'ganho_massa' })
    const first = await complete(db, body, 'signup-objective-first-1')
    db.calcRows = STAGING_CALC_ROWS.map((row) =>
      row.key === 'calc.training_min' ? { key: row.key, value: 4 } : row,
    )
    clearCalcConfigCache()
    db.operations.length = 0

    const second = await complete(db, body, 'signup-objective-second-1')

    expect(first.response.status).toBe(200)
    expect(second.response.status).toBe(200)
    expect(second.json.data).toEqual(first.json.data)
    expect(db.operations).toEqual([
      SNAPSHOT_READ,
      CLAIM,
      SQL_FUNCTION,
      'rpc:prepare_mobile_signup_body_photo_disposition',
      RECORD,
    ])
  })

  it('a completed account sending another objective is answered by the SQL function, as before: 409, never the 422 of the check', async () => {
    const stored = man({ body_fat_percent: 25, objective: 'recomposicao' })
    const db = new SignupMemoryDb().addCompletedAccount(stored, EARLIER_COMPLETION)

    const { response, json } = await complete(db, { ...stored, objective: 'ganho_massa' })

    expect(response.status).toBe(409)
    expect(json.error.code).toBe('onboarding_already_completed')
    expect(db.operations).toEqual([SNAPSHOT_READ, CLAIM, SQL_FUNCTION, RELEASE])
    expect(db.profile).toMatchObject({
      current_protocol: 'recomposicao',
      onboarding_completed_at: EARLIER_COMPLETION,
    })
  })

  // `reset_user_conversation_atomic` empties the profile and marks it not
  // completed, and leaves the completion time where it was (migration
  // 20260928150000). The SQL function then takes its branch "with a completion
  // time" and records nothing; the check follows it and does not run.
  it('an account that was reset keeps its completion time: the SQL function answers as before (409), and the check does not run', async () => {
    const db = new SignupMemoryDb()
    db.profile = {
      onboarding_completed: false,
      onboarding_completed_at: EARLIER_COMPLETION,
      current_protocol: null,
      answers: null,
    }

    const { response, json } = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
    )

    expect(response.status).toBe(409)
    expect(json.error.code).toBe('onboarding_already_completed')
    expect(db.operations).toEqual([SNAPSHOT_READ, CLAIM, SQL_FUNCTION, RELEASE])
    expect(db.profile.current_protocol).toBeNull()
  })
})

describe('POST /onboarding — an older account marked completed with no completion time (declared as RC E)', () => {
  // The SQL function tells a first completion by the completion time alone:
  // it records this account as one and rewrites its protocol, as it did before
  // this change. The check follows the SQL function.
  it('is checked as a first completion: ganho de massa outside the criteria (man, 25% of body fat) → 422, and the protocol it holds stays', async () => {
    const db = new SignupMemoryDb().addAccountCompletedWithoutDate('ganho_massa')

    const { response, json } = await complete(
      db,
      man({ body_fat_percent: 25, objective: 'ganho_massa' }),
    )

    expect(response.status).toBe(422)
    expect(json).toEqual(REFUSED)
    expect(db.operations).toEqual([SNAPSHOT_READ, CONFIG_READ])
    expect(db.idempotencyRows()).toEqual([])
    expect(db.submissions).toEqual([])
    expect(db.profile).toMatchObject({
      onboarding_completed: true,
      onboarding_completed_at: null,
      current_protocol: 'ganho_massa',
    })
  })

  it('with an objective the rule allows it completes, and the SQL function records it as a first completion, as it already did', async () => {
    const db = new SignupMemoryDb().addAccountCompletedWithoutDate('ganho_massa')

    const { response } = await complete(
      db,
      man({ body_fat_percent: 25, objective: 'recomposicao' }),
    )

    expect(response.status).toBe(200)
    expect(db.profile).toMatchObject({
      onboarding_completed_at: COMPLETED_AT,
      current_protocol: 'recomposicao',
    })
  })
})

/** A valid no-photo snapshot except for the completion time deliberately under test. */
function snapshotWithCompletionTime(completedAt: unknown) {
  return {
    version: 1,
    user_id: USER_ID,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: completedAt,
      receipt_count: 0,
    },
    poses: [],
    remaining_uploads: 0,
    consent: null,
    estimate: null,
    candidate: null,
    confirmation: null,
  }
}

describe('POST /onboarding — the objective check fails closed', () => {
  it.each<[string, Failure]>([
    ['answers an error', 'error'],
    ['throws', 'throw'],
    ['answers a snapshot without the generation column', { data: {} }],
    ['answers a completion time that is not a text', { data: snapshotWithCompletionTime(0) }],
    ['answers an empty completion time', { data: snapshotWithCompletionTime('') }],
    // A text that is not a date is not a completion time either: it does not
    // exempt the request from the check, and nothing is assumed in its place.
    ['answers a blank completion time', { data: snapshotWithCompletionTime(' ') }],
    ['answers the text "null" as completion time', { data: snapshotWithCompletionTime('null') }],
    [
      'answers a completion time that is not a date',
      { data: snapshotWithCompletionTime('not-a-date') },
    ],
    // Texts `Date.parse` would take for a date, and that are not a time with
    // an offset as the database client writes it.
    ['answers the text "1" as completion time', { data: snapshotWithCompletionTime('1') }],
    ['answers a bare year as completion time', { data: snapshotWithCompletionTime('2026') }],
    [
      'answers a completion time with no offset',
      { data: snapshotWithCompletionTime('2026-09-20T12:00:00') },
    ],
    ['answers a list of rows', { data: [{ onboarding_completed_at: null }] }],
  ])('the snapshot read %s → 500 data_access_failed, and the SQL function is not called', async (_case, failure) => {
    const spies = logs()
    const db = new SignupMemoryDb().addAccount()
    db.failures.set(SNAPSHOT_READ, failure)

    // Recomposição is available to everyone, and still nothing is assumed.
    const { response, json } = await complete(db, man({ objective: 'recomposicao' }))

    expect(response.status).toBe(500)
    expect(json).toEqual({
      error: {
        code: 'data_access_failed',
        message: 'Onboarding completion lookup failed',
        request_id: REQUEST_ID,
      },
    })
    // Before the key is claimed: one read, and no row in the ledger.
    expect(db.operations).toEqual([SNAPSHOT_READ])
    expect(db.idempotencyRows()).toEqual([])
    expect(db.submissions).toEqual([])
    expect(db.profile).toEqual(NEW_ACCOUNT)
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  it('a text that is not a date in the place of the completion time never lets a first completion outside the rule be recorded', async () => {
    const db = new SignupMemoryDb().addAccount()
    db.failures.set(SNAPSHOT_READ, { data: snapshotWithCompletionTime('not-a-date') })

    const { response, json } = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
    )

    expect(response.status).toBe(500)
    expect(json.error.code).toBe('data_access_failed')
    expect(db.submissions).toEqual([])
    expect(db.profile).toEqual(NEW_ACCOUNT)
  })

  it('a completed account whose profile cannot be read is not let through either', async () => {
    const stored = man({ body_fat_percent: 25, objective: 'ganho_massa' })
    const db = new SignupMemoryDb().addCompletedAccount(stored, EARLIER_COMPLETION)
    db.failures.set(SNAPSHOT_READ, 'error')

    const { response, json } = await complete(db, stored)

    expect(response.status).toBe(500)
    expect(json.error.code).toBe('data_access_failed')
    expect(db.submissions).toEqual([])
  })

  it.each<[string, Failure]>([
    ['answers an error', 'error'],
    ['throws', 'throw'],
  ])('the calc config read %s → 500 data_access_failed: nothing is decided on the code defaults', async (_case, failure) => {
    const spies = logs()
    const db = new SignupMemoryDb().addAccount()
    db.failures.set(CONFIG_READ, failure)

    const { response, json } = await complete(db, man({ objective: 'recomposicao' }))

    expect(response.status).toBe(500)
    expect(json).toEqual({
      error: {
        code: 'data_access_failed',
        message: 'Calculation config lookup failed',
        request_id: REQUEST_ID,
      },
    })
    expect(db.operations).toEqual([SNAPSHOT_READ, CONFIG_READ])
    expect(db.idempotencyRows()).toEqual([])
    expect(db.submissions).toEqual([])
    expect(db.profile).toEqual(NEW_ACCOUNT)
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  it('once the read answers again, the same request under the same key completes', async () => {
    const db = new SignupMemoryDb().addAccount()
    const body = man({ objective: 'recomposicao' })
    const key = 'signup-objective-after-failure-1'
    db.failures.set(SNAPSHOT_READ, 'error')
    const failed = await complete(db, body, key)
    db.failures.clear()

    const completed = await complete(db, body, key)

    expect(failed.response.status).toBe(500)
    expect(completed.response.status).toBe(200)
    expect(completed.response.headers.get('idempotency-replayed')).toBeNull()
    expect(db.submissions).toEqual([body])
  })

  it.each<[string, string]>([
    ['the profile', SNAPSHOT_READ],
    ['the calc config', CONFIG_READ],
  ])('a failed read of %s leaves no record either: once it answers again the same key completes even with another objective', async (_case, read) => {
    const db = new SignupMemoryDb().addAccount()
    const key = 'signup-objective-after-failure-2'
    db.failures.set(read, 'error')
    const failed = await complete(db, man({ objective: 'recomposicao' }), key)
    db.failures.clear()
    const body = man({ objective: 'manutencao' })

    const completed = await complete(db, body, key)

    expect(failed.response.status).toBe(500)
    expect(failed.json.error.code).toBe('data_access_failed')
    expect(completed.response.status).toBe(200)
    expect(completed.response.headers.get('idempotency-replayed')).toBeNull()
    expect(db.idempotencyRows()).toEqual([{ key, state: 'completed', status: 200 }])
    expect(db.submissions).toEqual([body])
  })

  it('an account with no profile row: the check runs all the same, and an allowed objective gets the answer the SQL function already gave', async () => {
    const db = new SignupMemoryDb()

    const refused = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'ganho_massa' }),
      'signup-objective-no-profile-1',
    )
    const allowed = await complete(
      db,
      man({ body_fat_percent: 20, objective: 'recomposicao' }),
      'signup-objective-no-profile-2',
    )

    expect(refused.response.status).toBe(422)
    expect(refused.json).toEqual(REFUSED)
    expect(allowed.response.status).toBe(404)
    expect(allowed.json.error.code).toBe('patient_not_found')
    // Only the allowed one reached the SQL function, which recorded nothing.
    expect(db.submissions).toHaveLength(1)
    expect(db.profile).toBeNull()
  })
})
