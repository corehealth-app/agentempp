/**
 * Automatic evaluation access for accounts created on the test environment
 * (docs/mobile/api-v1.md, "Acesso de avaliação automático").
 *
 * What is locked here: the four locks (and that a closed lock costs not a
 * single query and leaves the response byte-identical), the hard refusal of
 * the production project, the exact event and entitlement a first completion
 * writes, that nothing is ever granted a second time, and that a failure of
 * the grant never reaches the onboarding response.
 *
 * Everything between the request and the database is the real code: the
 * onboarding handler with its default dependencies (idempotency, service,
 * repository), the grant module, and the entitlement gate the other routes
 * use. The database is in memory and reproduces the functions the code calls
 * (`complete_mobile_onboarding_atomic`, `resolve_user_entitlement`,
 * `apply_entitlement_event` and the three idempotency functions) from their
 * migrations. No network. The project refs are the two real ones (they are
 * identifiers of projects, not credentials); every URL here is only parsed,
 * never called.
 *
 * > RC EA — cenário conta que concluiu o onboarding ANTES de o interruptor ser ligado NÃO coberto nesta PR (pendência da audit 2026-10-04). Não recebe nada, nem reenviando a conclusão nem aceitando documentos novos depois: segue dependendo da concessão manual do operador. Travado em evaluation-access.test.ts.
 * > RC EA — cenário acesso vencido (N dias depois) ou bloqueado NÃO coberto nesta PR (pendência da audit 2026-10-04). Não é renovado por este caminho: a conta volta a receber 402 e a renovação é manual. Travado em evaluation-access.test.ts.
 * > RC EA — cenário compra ou assinatura pelo app NÃO coberto nesta PR (pendência da audit 2026-10-04). Não existe tela nem caminho de compra; `mobile_billing.available` segue `false`.
 * > RC EA — cenário nova tentativa depois de uma concessão que falhou, ou de uma função encerrada entre a conclusão e a concessão NÃO coberto nesta PR (pendência da audit 2026-10-04). A conta fica criada e sem acesso; reenviar a conclusão não concede (a conta já tem data de conclusão). A falha fica no log `[mobile-api] evaluation_access_failed` e a concessão é manual.
 * > RC EA — cenário funções `apply_entitlement_event` e `resolve_user_entitlement` REAIS do Postgres NÃO coberto nesta PR (pendência da audit 2026-10-04). Os testes usam um banco em memória que reproduz as duas; nada foi gravado em staging, e a primeira concessão real só acontece depois de ligar o interruptor.
 * > RC EA — cenário ator de auditoria que não existe NÃO coberto nesta PR (pendência da audit 2026-10-04). `actor_id` não tem chave estrangeira: o código só confere que a variável é um uuid diferente de zero, não que ele seja de um operador cadastrado.
 * > RC EA — cenário tela do iPhone (primeira tela depois do onboarding vista no aparelho com o interruptor ligado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho nem no simulador.
 * > RC EA — cenário relógio de outra instância da API atrasado em relação à que concedeu NÃO coberto nesta PR (pendência da audit 2026-10-04). O início do acesso é a hora da instância que concedeu; outra instância com o relógio atrás responde 402 até alcançá-la.
 * > RC EA — cenário a mesma pessoa criando outra conta (outro e-mail) NÃO coberto nesta PR (pendência da audit 2026-10-04). Cada conta nova que conclui o onboarding recebe os N dias; não há limite por pessoa nem por aparelho.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  handleOnboardingPost,
  type OnboardingRouteDependencies,
} from '@/app/api/mobile/v1/onboarding/handler'
import { onboardingCompletionInputSchema } from './contracts'
import { projectRefFromUrl as dayCloseProjectRefFromUrl } from './day-close-on-request'
import { authorizeMobileEntitlement, loadMobileEntitlement } from './entitlement-service'
import {
  EVALUATION_ACCESS_ACTOR_ID_ENV,
  EVALUATION_ACCESS_DAYS_ENV,
  EVALUATION_ACCESS_PROJECT_REF_ENV,
  prepareEvaluationAccess,
  projectRefFromUrl,
  resolveEvaluationAccess,
} from './evaluation-access'
import { mobileSuccess } from './http'
import { executeSupabaseIdempotent } from './idempotency'
import { completeOnboarding } from './onboarding-service'
import type { MobileRouteContext } from './route'
import { createSupabaseOnboardingRepository } from './supabase-onboarding'

const USER = '0b9f6f0e-0000-4000-8000-00000000ea01'
const AUTH_USER = '0b9f6f0e-0000-4000-8000-00000000ea02'
const ACTOR = '5c1d2e3f-0000-4000-8000-0000000000ac'
const EMAIL = 'synthetic-evaluator@example.invalid'
const NAME = 'Synthetic Evaluator'
const REQUEST_ID = 'request-evaluation-access'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const PRODUCTION_REF = 'xuxehkhdvjivitduarvb'
const STAGING_URL = `https://${STAGING_REF}.supabase.co`
const PRODUCTION_URL = `https://${PRODUCTION_REF}.supabase.co`
const NOW = new Date('2026-10-05T15:00:00.000Z')
const DAY_MS = 86_400_000
const GATED_PATH = '/api/mobile/v1/today'

const ON = {
  [EVALUATION_ACCESS_DAYS_ENV]: '30',
  [EVALUATION_ACCESS_PROJECT_REF_ENV]: STAGING_REF,
  [EVALUATION_ACCESS_ACTOR_ID_ENV]: ACTOR,
  NEXT_PUBLIC_SUPABASE_URL: STAGING_URL,
}

/** What the handler asked the database before this change, for one completion. */
const BASELINE_OPERATIONS = [
  'rpc:claim_mobile_api_request',
  'rpc:complete_mobile_onboarding_atomic',
  'rpc:complete_mobile_api_request',
]

const FIRST_GRANT_OPERATIONS = [
  'rpc:claim_mobile_api_request',
  'select:user_profiles',
  'rpc:complete_mobile_onboarding_atomic',
  'select:entitlement_events',
  'rpc:resolve_user_entitlement',
  'rpc:apply_entitlement_event',
  'rpc:complete_mobile_api_request',
]

const LEFT_ALONE_OPERATIONS = FIRST_GRANT_OPERATIONS.filter(
  (operation) => operation !== 'rpc:apply_entitlement_event',
)

// ---------------------------------------------------------------------------
// In-memory database
// ---------------------------------------------------------------------------

interface DbError {
  message: string
  code?: string
}

interface DbResult {
  data: unknown
  error: DbError | null
}

type Failure = 'error' | 'throw' | { data: unknown }

interface MemoryQuery {
  select(columns: string): MemoryQuery
  eq(column: string, value: unknown): MemoryQuery
  limit(count: number): MemoryQuery
  maybeSingle(): Promise<DbResult>
  then(
    onFulfilled: (value: DbResult) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ): Promise<unknown>
}

interface LegalDocument {
  id: string
  document_key: string
  version: string
  locale: string
  content_hash: string
  purpose: string
  action_type: string
}

interface EntitlementRow {
  id: string
  user_id: string
  entitlement_key: string
  source: string
  source_reference: string
  status: string
  plan: string | null
  environment: string
  starts_at: string | null
  access_expires_at: string | null
  grace_expires_at: string | null
  cancel_at_period_end: boolean
  last_provider_event_id: string
  last_provider_event_at: string
  reason_code: string | null
  actor_id: string | null
  updated_at: string
}

interface EntitlementEventRow {
  id: string
  entitlement_id: string | null
  user_id: string
  entitlement_key: string
  source: string
  source_reference: string
  provider_event_id: string
  event_type: string
  environment: string
  occurred_at: string
  processing_result: string
}

const IDENTIFIER = /^[A-Za-z0-9._:/-]{1,200}$/
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const SOURCES = ['stripe', 'apple_storekit', 'revenuecat', 'manual', 'legacy']
const PROVIDER_SOURCES = ['stripe', 'apple_storekit', 'revenuecat']
const STATUSES = [
  'active',
  'trialing',
  'grace_period',
  'expired',
  'canceled',
  'grandfathered',
  'manual_comp',
  'blocked',
]
const STATUS_PRIORITY: Record<string, number> = {
  active: 700,
  trialing: 600,
  grace_period: 500,
  grandfathered: 400,
  manual_comp: 300,
  canceled: 200,
}

const DOCUMENT_V1: LegalDocument = {
  id: '00000000-0000-4000-8000-0000000000d1',
  document_key: 'terms_of_service',
  version: '2026-10-01.1',
  locale: 'pt-BR',
  content_hash: 'a'.repeat(64),
  purpose: 'terms_of_service_acceptance',
  action_type: 'acceptance',
}

const DOCUMENT_V2: LegalDocument = {
  ...DOCUMENT_V1,
  id: '00000000-0000-4000-8000-0000000000d2',
  version: '2026-10-15.1',
  content_hash: 'b'.repeat(64),
}

function invalid(message: string): DbResult {
  return { data: null, error: { message, code: '22023' } }
}

function time(value: unknown): number | null {
  return typeof value === 'string' ? Date.parse(value) : null
}

class EvaluationMemoryDb {
  readonly operations: string[] = []
  readonly calls: Array<{ name: string; params: Record<string, unknown> }> = []
  readonly entitlements: EntitlementRow[] = []
  readonly events: EntitlementEventRow[] = []
  readonly failures = new Map<string, Failure>()
  readonly client: ServiceClient

  private readonly profiles = new Map<
    string,
    { onboarding_completed_at: string | null; answers: string | null }
  >()
  private readonly claims = new Map<
    string,
    { id: string; hash: unknown; done: boolean; status: unknown; body: unknown }
  >()
  private readonly legalActions: Array<{ user_id: string; document: LegalDocument; at: string }> =
    []
  private currentDocument = DOCUMENT_V1
  private sequence = 0

  constructor() {
    this.client = {
      from: (table: string) => this.query(table),
      // Like the real client, a call is sent when it is awaited, not when it is built.
      rpc: (name: string, params: Record<string, unknown>) => {
        let sent: Promise<DbResult> | undefined
        return {
          // biome-ignore lint/suspicious/noThenProperty: the RPC builder of the real client is awaitable too.
          then: (
            onFulfilled: (value: DbResult) => unknown,
            onRejected?: (reason: unknown) => unknown,
          ) => {
            sent ??= this.rpc(name, params)
            return sent.then(onFulfilled, onRejected)
          },
        }
      },
    } as unknown as ServiceClient
  }

  addAccount(userId = USER): this {
    this.profiles.set(userId, { onboarding_completed_at: null, answers: null })
    return this
  }

  completedAt(userId = USER): string | null {
    return this.profiles.get(userId)?.onboarding_completed_at ?? null
  }

  /** A new version of the required document is published: completion now needs it. */
  publishNewDocumentVersion(): void {
    this.currentDocument = DOCUMENT_V2
  }

  /** What an operator's SQL grant leaves behind, without counting as a request query. */
  seedEntitlement(overrides: Partial<Record<string, unknown>> = {}): void {
    const result = this.applyEntitlementEvent({
      p_provider_event_id: 'qa:seed-1:grant',
      p_event_type: 'manual.qa.grant',
      p_user_id: USER,
      p_entitlement_key: 'bodyflow_full',
      p_source: 'manual',
      p_source_reference: 'seed-1',
      p_status: 'active',
      p_plan: 'trial',
      p_environment: 'sandbox',
      p_occurred_at: '2026-09-01T12:00:00.000Z',
      p_starts_at: '2026-09-01T12:00:00.000Z',
      p_access_expires_at: '2026-10-31T12:00:00.000Z',
      p_grace_expires_at: null,
      p_cancel_at_period_end: false,
      p_reason_code: 'qa_seed',
      p_actor_id: '5c1d2e3f-0000-4000-8000-0000000000bb',
      ...overrides,
    })
    if (result.error) throw new Error(`seed refused: ${result.error.message}`)
  }

  private nextId(): string {
    this.sequence += 1
    return `00000000-0000-4000-8000-${String(this.sequence).padStart(12, '0')}`
  }

  private injected(operation: string): DbResult | null {
    const failure = this.failures.get(operation)
    if (failure === undefined) return null
    if (failure === 'throw') throw new TypeError(`network down for ${EMAIL}`)
    if (failure === 'error') {
      return { data: null, error: { message: `permission denied for ${EMAIL} (${USER})` } }
    }
    return { data: failure.data, error: null }
  }

  private rows(table: string): Array<Record<string, unknown>> {
    if (table === 'user_profiles') {
      return [...this.profiles].map(([userId, profile]) => ({
        user_id: userId,
        onboarding_completed_at: profile.onboarding_completed_at,
      }))
    }
    if (table === 'entitlement_events') return this.events.map((event) => ({ ...event }))
    throw new Error(`unexpected table ${table}`)
  }

  private query(table: string): MemoryQuery {
    const filters: Array<[string, unknown]> = []
    let columns: string[] = []
    let limit = Number.POSITIVE_INFINITY
    const run = async (single: boolean): Promise<DbResult> => {
      const operation = `select:${table}`
      this.operations.push(operation)
      const injected = this.injected(operation)
      if (injected) return injected
      const found = this.rows(table)
        .filter((row) => filters.every(([column, value]) => row[column] === value))
        .slice(0, limit)
        .map((row) => Object.fromEntries(columns.map((column) => [column, row[column]])))
      return { data: single ? (found[0] ?? null) : found, error: null }
    }
    const builder: MemoryQuery = {
      select: (selected: string) => {
        columns = selected.split(',').map((column) => column.trim())
        return builder
      },
      eq: (column: string, value: unknown) => {
        filters.push([column, value])
        return builder
      },
      limit: (count: number) => {
        limit = count
        return builder
      },
      maybeSingle: () => run(true),
      // biome-ignore lint/suspicious/noThenProperty: the query builder of the real client is awaitable too.
      then: (onFulfilled, onRejected) => run(false).then(onFulfilled, onRejected),
    }
    return builder
  }

  private async rpc(name: string, params: Record<string, unknown>): Promise<DbResult> {
    const operation = `rpc:${name}`
    this.operations.push(operation)
    this.calls.push({ name, params })
    const injected = this.injected(operation)
    if (injected) return injected
    if (name === 'claim_mobile_api_request') return this.claim(params)
    if (name === 'complete_mobile_api_request') return this.completeClaim(params)
    if (name === 'fail_mobile_api_request') return this.failClaim(params)
    if (name === 'complete_mobile_onboarding_atomic') return this.completeOnboarding(params)
    if (name === 'resolve_user_entitlement') return this.resolveEntitlement(params)
    if (name === 'apply_entitlement_event') return this.applyEntitlementEvent(params)
    throw new Error(`unexpected rpc ${name}`)
  }

  private claimKey(params: Record<string, unknown>): string {
    return [
      params.p_user_id,
      params.p_request_method,
      params.p_request_route,
      params.p_idempotency_key,
    ].join('|')
  }

  private claim(params: Record<string, unknown>): DbResult {
    const key = this.claimKey(params)
    const existing = this.claims.get(key)
    if (!existing) {
      const id = this.nextId()
      this.claims.set(key, {
        id,
        hash: params.p_request_hash,
        done: false,
        status: null,
        body: null,
      })
      return { data: { action: 'claimed', claim_id: id }, error: null }
    }
    if (existing.hash !== params.p_request_hash)
      return { data: { action: 'conflict' }, error: null }
    if (!existing.done) return { data: { action: 'in_progress' }, error: null }
    return {
      data: { action: 'replay', response_status: existing.status, response_body: existing.body },
      error: null,
    }
  }

  private completeClaim(params: Record<string, unknown>): DbResult {
    const claim = [...this.claims.values()].find((entry) => entry.id === params.p_claim_id)
    if (!claim) return { data: false, error: null }
    claim.done = true
    claim.status = params.p_response_status
    claim.body = params.p_response_body
    return { data: true, error: null }
  }

  private failClaim(params: Record<string, unknown>): DbResult {
    for (const [key, claim] of this.claims) {
      if (claim.id === params.p_claim_id) this.claims.delete(key)
    }
    return { data: null, error: null }
  }

  /** supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql */
  private completeOnboarding(params: Record<string, unknown>): DbResult {
    const userId = params.p_user_id as string
    const submission = params.p_submission as Record<string, unknown>
    const profile = this.profiles.get(userId)
    if (!profile) return { data: null, error: { message: 'onboarding_user_not_found' } }

    const actions = submission.document_actions as Array<Record<string, unknown>>
    const document = this.currentDocument
    const accepted = actions.some(
      (action) =>
        action.document_key === document.document_key &&
        action.version === document.version &&
        action.locale === document.locale &&
        action.content_hash === document.content_hash &&
        action.action === document.action_type,
    )
    if (actions.length !== 1 || !accepted) {
      return { data: null, error: { message: 'onboarding_document_version_mismatch' } }
    }

    const answers = JSON.stringify(
      Object.entries(submission).filter(([key]) => key !== 'document_actions'),
    )
    const now = new Date().toISOString()
    if (profile.onboarding_completed_at !== null) {
      if (profile.answers !== answers) {
        return { data: null, error: { message: 'onboarding_already_completed' } }
      }
    } else {
      // COALESCE(profile.onboarding_completed_at, v_now): written once.
      profile.onboarding_completed_at = now
      profile.answers = answers
    }
    if (!this.legalActions.some((row) => row.user_id === userId && row.document === document)) {
      this.legalActions.push({ user_id: userId, document, at: now })
    }

    return {
      data: {
        user_id: userId,
        onboarding_completed: true,
        completed_at: profile.onboarding_completed_at,
        objective: submission.objective,
        persona: submission.persona,
        document_actions: this.legalActions
          .filter((row) => row.user_id === userId && row.document === document)
          .map((row) => ({
            document_key: row.document.document_key,
            version: row.document.version,
            locale: row.document.locale,
            content_hash: row.document.content_hash,
            purpose: row.document.purpose,
            action: row.document.action_type,
            acted_at: row.at,
          })),
      },
      error: null,
    }
  }

  /** resolve_user_entitlement, without the older Stripe read-through (no such rows here). */
  private resolveEntitlement(params: Record<string, unknown>): DbResult {
    const userId = params.p_user_id as string
    const key = params.p_entitlement_key as string
    const now = time(params.p_now)
    if (!this.profiles.has(userId)) return invalid('invalid entitlement user')
    if (now === null || Number.isNaN(now)) return invalid('entitlement decision time is required')

    const decision = (row: EntitlementRow | null, fields: Record<string, unknown>): DbResult => ({
      data: {
        entitlement: key,
        source: row?.source ?? null,
        plan: row?.plan ?? null,
        access_expires_at: row?.access_expires_at ?? null,
        grace_expires_at: row?.grace_expires_at ?? null,
        cancel_at_period_end: row?.cancel_at_period_end ?? false,
        decision_at: params.p_now,
        ...fields,
      },
      error: null,
    })
    const mine = this.entitlements.filter(
      (row) => row.user_id === userId && row.entitlement_key === key,
    )
    const started = (row: EntitlementRow) =>
      row.starts_at === null || Date.parse(row.starts_at) <= now
    const after = (value: string | null) => value !== null && Date.parse(value) > now
    const openEnded = (value: string | null) => value === null || Date.parse(value) > now
    const blocking = (row: EntitlementRow) =>
      row.status === 'blocked' && started(row) && openEnded(row.access_expires_at)
    const newest = (left: EntitlementRow, right: EntitlementRow) =>
      Date.parse(right.updated_at) - Date.parse(left.updated_at)

    const blocked = mine.filter(blocking).sort(newest)[0]
    if (blocked) {
      return decision(blocked, { has_active_access: false, status: 'blocked', reason: 'blocked' })
    }

    const valid = mine
      .filter((row) => {
        if (row.status === 'blocked' || !started(row)) return false
        if (['active', 'trialing', 'canceled'].includes(row.status))
          return after(row.access_expires_at)
        if (row.status === 'grace_period') return after(row.grace_expires_at)
        if (['grandfathered', 'manual_comp'].includes(row.status)) {
          return openEnded(row.access_expires_at)
        }
        return false
      })
      .sort(
        (left, right) =>
          (STATUS_PRIORITY[right.status] ?? 0) - (STATUS_PRIORITY[left.status] ?? 0) ||
          newest(left, right),
      )[0]
    if (valid) {
      const reasons: Record<string, string> = {
        canceled: 'canceled_until_expiry',
        grace_period: 'grace_period',
        grandfathered: 'grandfathered',
        manual_comp: 'manual_comp',
      }
      return decision(valid, {
        has_active_access: true,
        status: valid.status,
        reason: reasons[valid.status] ?? 'valid_entitlement',
      })
    }

    const denied = mine
      .filter((row) => !blocking(row))
      .sort(
        (left, right) =>
          Date.parse(right.last_provider_event_at) - Date.parse(left.last_provider_event_at),
      )[0]
    if (denied) {
      return decision(denied, {
        has_active_access: false,
        status: ['expired', 'canceled'].includes(denied.status) ? denied.status : 'expired',
        reason: denied.status === 'canceled' ? 'canceled' : 'expired_entitlement',
      })
    }
    return decision(null, { has_active_access: false, status: 'expired', reason: 'no_entitlement' })
  }

  /** apply_entitlement_event, with the refusals of the function and of the table checks. */
  private applyEntitlementEvent(params: Record<string, unknown>): DbResult {
    const expected = [
      'p_access_expires_at',
      'p_actor_id',
      'p_cancel_at_period_end',
      'p_entitlement_key',
      'p_environment',
      'p_event_type',
      'p_grace_expires_at',
      'p_occurred_at',
      'p_plan',
      'p_provider_event_id',
      'p_reason_code',
      'p_source',
      'p_source_reference',
      'p_starts_at',
      'p_status',
      'p_user_id',
    ]
    // The API layer resolves a function by its argument names.
    if (JSON.stringify(Object.keys(params).sort()) !== JSON.stringify(expected)) {
      return { data: null, error: { message: 'function not found', code: 'PGRST202' } }
    }
    const text = (name: string) =>
      typeof params[name] === 'string' ? (params[name] as string) : ''
    const eventId = text('p_provider_event_id')
    const eventType = text('p_event_type')
    const userId = text('p_user_id')
    const key = text('p_entitlement_key')
    const source = text('p_source')
    const sourceReference = text('p_source_reference')
    const status = text('p_status')
    const environment = text('p_environment')
    const reasonCode = params.p_reason_code === null ? null : text('p_reason_code')
    const actorId = params.p_actor_id === null ? null : text('p_actor_id')
    const plan = params.p_plan === null ? null : text('p_plan')
    const occurredAt = time(params.p_occurred_at)
    const startsAt = time(params.p_starts_at)
    const expiresAt = time(params.p_access_expires_at)
    const graceAt = time(params.p_grace_expires_at)

    if (!this.profiles.has(userId)) return invalid('invalid entitlement user')
    if (!IDENTIFIER.test(eventId)) return invalid('invalid provider event id')
    if (!IDENTIFIER.test(eventType)) return invalid('invalid entitlement event type')
    if (!IDENTIFIER.test(key)) return invalid('invalid entitlement key')
    if (!SOURCES.includes(source)) return invalid('invalid entitlement source')
    if (!IDENTIFIER.test(sourceReference)) return invalid('invalid entitlement source reference')
    if (!STATUSES.includes(status)) return invalid('invalid entitlement status')
    if (!['sandbox', 'production', 'internal'].includes(environment)) {
      return invalid('invalid entitlement environment')
    }
    if (plan !== null && !['trial', 'mensal', 'anual'].includes(plan)) {
      return invalid('invalid input value for enum plan_enum')
    }
    if (actorId !== null && !UUID.test(actorId))
      return invalid('invalid input syntax for type uuid')
    if (occurredAt === null || Number.isNaN(occurredAt)) {
      return invalid('entitlement event time is required')
    }
    if (startsAt !== null && expiresAt !== null && startsAt > expiresAt) {
      return invalid('entitlement expiry precedes start')
    }
    if (expiresAt !== null && graceAt !== null && expiresAt > graceAt) {
      return invalid('entitlement grace precedes expiry')
    }
    if (
      PROVIDER_SOURCES.includes(source) &&
      ['active', 'trialing'].includes(status) &&
      expiresAt === null
    ) {
      return invalid('provider access requires expiry')
    }
    if (status === 'grace_period' && graceAt === null)
      return invalid('grace period requires expiry')
    if (reasonCode !== null && !/^[a-z][a-z0-9_]{0,63}$/.test(reasonCode)) {
      return invalid('invalid entitlement reason')
    }
    if (source === 'manual' && (reasonCode === null || actorId === null)) {
      return invalid('manual entitlement requires audit context')
    }

    const occurredIso = params.p_occurred_at as string
    const duplicate = this.events.find(
      (event) => event.source === source && event.provider_event_id === eventId,
    )
    if (duplicate) {
      if (
        duplicate.user_id !== userId ||
        duplicate.entitlement_key !== key ||
        duplicate.source_reference !== sourceReference
      ) {
        return {
          data: null,
          error: { message: 'provider event identity conflict', code: '23505' },
        }
      }
      return {
        data: {
          result: 'duplicate',
          event_id: duplicate.id,
          entitlement_id: duplicate.entitlement_id,
        },
        error: null,
      }
    }

    let entitlement = this.entitlements.find(
      (row) =>
        row.source === source &&
        row.source_reference === sourceReference &&
        row.entitlement_key === key,
    )
    if (entitlement && entitlement.user_id !== userId) {
      return {
        data: null,
        error: { message: 'entitlement source reference identity conflict', code: '23505' },
      }
    }
    const event: EntitlementEventRow = {
      id: this.nextId(),
      entitlement_id: null,
      user_id: userId,
      entitlement_key: key,
      source,
      source_reference: sourceReference,
      provider_event_id: eventId,
      event_type: eventType,
      environment,
      occurred_at: occurredIso,
      processing_result: 'received',
    }
    this.events.push(event)

    if (entitlement) {
      const last = Date.parse(entitlement.last_provider_event_at)
      if (
        occurredAt < last ||
        (occurredAt === last && eventId <= entitlement.last_provider_event_id)
      ) {
        event.entitlement_id = entitlement.id
        event.processing_result = 'stale'
        return {
          data: { result: 'stale', event_id: event.id, entitlement_id: entitlement.id },
          error: null,
        }
      }
    }
    const fields = {
      status,
      plan,
      environment,
      starts_at: (params.p_starts_at as string | null) ?? null,
      access_expires_at: (params.p_access_expires_at as string | null) ?? null,
      grace_expires_at: (params.p_grace_expires_at as string | null) ?? null,
      cancel_at_period_end: params.p_cancel_at_period_end === true,
      last_provider_event_id: eventId,
      last_provider_event_at: occurredIso,
      reason_code: reasonCode,
      actor_id: actorId,
      updated_at: new Date().toISOString(),
    }
    if (entitlement) {
      Object.assign(entitlement, fields)
    } else {
      entitlement = {
        id: this.nextId(),
        user_id: userId,
        entitlement_key: key,
        source,
        source_reference: sourceReference,
        ...fields,
      }
      this.entitlements.push(entitlement)
    }
    event.entitlement_id = entitlement.id
    event.processing_result = 'applied'
    return {
      data: { result: 'applied', event_id: event.id, entitlement_id: entitlement.id },
      error: null,
    }
  }
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

function completionBody(document: LegalDocument = DOCUMENT_V1) {
  return {
    name: NAME,
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
        document_key: document.document_key,
        version: document.version,
        locale: document.locale,
        content_hash: document.content_hash,
        action: document.action_type,
      },
    ],
  }
}

function context(
  db: EvaluationMemoryDb,
  body: unknown = completionBody(),
  idempotencyKey = 'evaluation-access-key-1',
): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/onboarding', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': idempotencyKey },
      body: JSON.stringify(body),
    }),
    requestId: REQUEST_ID,
    supabase: db.client,
    auth: {
      accessToken: 'redacted-test-token',
      authUserId: AUTH_USER,
      userId: USER,
      identity: { id: AUTH_USER, email: EMAIL, emailConfirmedAt: '2026-10-05T14:00:00.000Z' },
      patient: {
        id: USER,
        authUserId: AUTH_USER,
        email: EMAIL,
        name: NAME,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

/** The real handler with its default dependencies. */
function post(db: EvaluationMemoryDb, body?: unknown, idempotencyKey?: string): Promise<Response> {
  return handleOnboardingPost(context(db, body, idempotencyKey))
}

async function wire(response: Response) {
  return {
    status: response.status,
    headers: [...response.headers.entries()].sort(([left], [right]) => left.localeCompare(right)),
    body: await response.text(),
  }
}

/** The response as the handler built it before this change, on a database of its own. */
async function baselineResponse() {
  const db = new EvaluationMemoryDb().addAccount()
  const repository = createSupabaseOnboardingRepository(db.client)
  const input = onboardingCompletionInputSchema.parse(completionBody())
  return wire(mobileSuccess(await completeOnboarding(repository, USER, input), REQUEST_ID))
}

function switchOn(overrides: Record<string, string | undefined> = {}): void {
  for (const [name, value] of Object.entries({ ...ON, ...overrides })) vi.stubEnv(name, value)
}

function logs() {
  return {
    info: vi.spyOn(console, 'info').mockImplementation(() => undefined),
    error: vi.spyOn(console, 'error').mockImplementation(() => undefined),
  }
}

const GRANTED_EVENT = {
  entitlement_key: 'bodyflow_full',
  source: 'manual',
  source_reference: `closed-evaluation-auto:${USER}`,
  provider_event_id: `closed-evaluation-auto:${USER}:grant`,
  event_type: 'manual.qa.grant',
  environment: 'sandbox',
  occurred_at: NOW.toISOString(),
  processing_result: 'applied',
  user_id: USER,
}

function grantedEntitlement(days: number) {
  return {
    user_id: USER,
    entitlement_key: 'bodyflow_full',
    source: 'manual',
    source_reference: `closed-evaluation-auto:${USER}`,
    status: 'active',
    plan: 'trial',
    environment: 'sandbox',
    starts_at: NOW.toISOString(),
    access_expires_at: new Date(NOW.getTime() + days * DAY_MS).toISOString(),
    grace_expires_at: null,
    cancel_at_period_end: false,
    last_provider_event_id: `closed-evaluation-auto:${USER}:grant`,
    last_provider_event_at: NOW.toISOString(),
    reason_code: 'closed_evaluation_auto',
    actor_id: ACTOR,
    updated_at: NOW.toISOString(),
  }
}

beforeEach(() => {
  // Only the clock: the request body is read through a stream.
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  vi.stubEnv(EVALUATION_ACCESS_DAYS_ENV, undefined)
  vi.stubEnv(EVALUATION_ACCESS_PROJECT_REF_ENV, undefined)
  vi.stubEnv(EVALUATION_ACCESS_ACTOR_ID_ENV, undefined)
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', STAGING_URL)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

// ---------------------------------------------------------------------------

describe('locks a, b and c — the environment', () => {
  it.each([
    ['1', 1],
    ['30', 30],
    ['90', 90],
    [' 30 ', 30],
  ])('MOBILE_EVALUATION_ACCESS_DAYS=%j is %i days', (raw, days) => {
    expect(resolveEvaluationAccess({ ...ON, [EVALUATION_ACCESS_DAYS_ENV]: raw })).toEqual({
      days,
      actorId: ACTOR,
    })
  })

  it.each([
    [undefined],
    [''],
    ['   '],
    ['0'],
    ['91'],
    ['100'],
    ['365'],
    ['-1'],
    ['+30'],
    ['30.0'],
    ['30,0'],
    ['1e1'],
    ['030'],
    ['0x1e'],
    ['3 0'],
    ['30d'],
    ['thirty'],
    ['true'],
    ['NaN'],
    ['Infinity'],
  ])('lock a: MOBILE_EVALUATION_ACCESS_DAYS=%j is off', (raw) => {
    expect(resolveEvaluationAccess({ ...ON, [EVALUATION_ACCESS_DAYS_ENV]: raw })).toBeNull()
  })

  it.each([
    ['the list is absent', { [EVALUATION_ACCESS_PROJECT_REF_ENV]: undefined }],
    ['the list is empty', { [EVALUATION_ACCESS_PROJECT_REF_ENV]: '' }],
    [
      'the list names another project',
      { [EVALUATION_ACCESS_PROJECT_REF_ENV]: 'abcdefghijklmnopqrst' },
    ],
    [
      'the list holds a prefix of the ref',
      { [EVALUATION_ACCESS_PROJECT_REF_ENV]: 'xitugspwfxkcluxvrde' },
    ],
    [
      'the list holds the URL instead of the ref',
      { [EVALUATION_ACCESS_PROJECT_REF_ENV]: STAGING_URL },
    ],
    ['the database URL is absent', { NEXT_PUBLIC_SUPABASE_URL: undefined }],
    ['the database URL is http', { NEXT_PUBLIC_SUPABASE_URL: `http://${STAGING_REF}.supabase.co` }],
    [
      'the database URL is a custom domain',
      { NEXT_PUBLIC_SUPABASE_URL: 'https://db.performe.example' },
    ],
    [
      'the database URL only contains the ref',
      { NEXT_PUBLIC_SUPABASE_URL: `https://example.com/${STAGING_REF}.supabase.co` },
    ],
    ['the database URL is local', { NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321' }],
  ])('lock b: off when %s', (_name, overrides) => {
    expect(resolveEvaluationAccess({ ...ON, ...overrides })).toBeNull()
  })

  it('lock b: several refs may be listed, separated by commas or spaces', () => {
    expect(
      resolveEvaluationAccess({
        ...ON,
        [EVALUATION_ACCESS_PROJECT_REF_ENV]: `abcdefghijklmnopqrst, ${STAGING_REF}`,
      }),
    ).toEqual({ days: 30, actorId: ACTOR })
  })

  it.each([
    ['the production URL with the production ref listed', PRODUCTION_URL, PRODUCTION_REF],
    ['the production URL with the staging ref listed', PRODUCTION_URL, STAGING_REF],
    [
      'the production URL with both refs listed',
      PRODUCTION_URL,
      `${STAGING_REF},${PRODUCTION_REF}`,
    ],
    ['the staging URL with both refs listed', STAGING_URL, `${STAGING_REF},${PRODUCTION_REF}`],
  ])('lock b: production is refused in code — %s', (_name, url, refs) => {
    expect(
      resolveEvaluationAccess({
        ...ON,
        NEXT_PUBLIC_SUPABASE_URL: url,
        [EVALUATION_ACCESS_PROJECT_REF_ENV]: refs,
      }),
    ).toBeNull()
  })

  it.each([
    [undefined],
    [''],
    ['operator'],
    ['5c1d2e3f-0000-4000-8000-0000000000a'],
    ['5c1d2e3f-0000-4000-8000-0000000000acd'],
    ['5c1d2e3f00004000800000000000 00ac'],
    ['5c1d2e3f0000400080000000000000ac'],
    ['{5c1d2e3f-0000-4000-8000-0000000000ac}'],
    ['5c1d2e3f-0000-4000-8000-0000000000ag'],
    ['00000000-0000-0000-0000-000000000000'],
    [`${ACTOR},${ACTOR}`],
    [EMAIL],
  ])('lock c: MOBILE_EVALUATION_ACCESS_ACTOR_ID=%j is off', (raw) => {
    expect(resolveEvaluationAccess({ ...ON, [EVALUATION_ACCESS_ACTOR_ID_ENV]: raw })).toBeNull()
  })

  it('lock c: the actor is written in lower case, as the database prints a uuid', () => {
    expect(
      resolveEvaluationAccess({
        ...ON,
        [EVALUATION_ACCESS_ACTOR_ID_ENV]: ` ${ACTOR.toUpperCase()} `,
      }),
    ).toEqual({ days: 30, actorId: ACTOR })
  })

  it('reads the project ref exactly as the on-request day close does', () => {
    for (const url of [
      undefined,
      '',
      STAGING_URL,
      PRODUCTION_URL,
      `${STAGING_URL}/`,
      `${STAGING_URL}/rest/v1`,
      `http://${STAGING_REF}.supabase.co`,
      `https://${STAGING_REF}.supabase.co.example.com`,
      `https://${STAGING_REF}.supabase.com`,
      `https://${STAGING_REF.toUpperCase()}.supabase.co`,
      `https://x.${STAGING_REF}.supabase.co`,
      'https://short.supabase.co',
      'https://db.performe.example',
      'not a url',
    ]) {
      expect(projectRefFromUrl(url), String(url)).toBe(dayCloseProjectRefFromUrl(url))
    }
    expect(projectRefFromUrl(STAGING_URL)).toBe(STAGING_REF)
    expect(projectRefFromUrl(PRODUCTION_URL)).toBe(PRODUCTION_REF)
  })

  it('a closed lock does not touch the request context at all', async () => {
    const untouchable = new Proxy(
      {},
      {
        get() {
          throw new Error('the context was read')
        },
      },
    ) as MobileRouteContext

    for (const env of [
      {},
      { ...ON, [EVALUATION_ACCESS_DAYS_ENV]: '0' },
      { ...ON, [EVALUATION_ACCESS_PROJECT_REF_ENV]: '' },
      { ...ON, [EVALUATION_ACCESS_ACTOR_ID_ENV]: '' },
      {
        ...ON,
        NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL,
        [EVALUATION_ACCESS_PROJECT_REF_ENV]: PRODUCTION_REF,
      },
    ]) {
      const grant = await prepareEvaluationAccess(untouchable, { env })
      await expect(grant()).resolves.toBeUndefined()
    }
  })
})

describe('switch off, or one lock closed: the same queries and the same bytes', () => {
  it('nothing configured (the default)', async () => {
    const log = logs()
    const db = new EvaluationMemoryDb().addAccount()

    const response = await wire(await post(db))

    expect(db.operations).toEqual(BASELINE_OPERATIONS)
    expect(response).toEqual(await baselineResponse())
    expect(response.status).toBe(200)
    expect(db.events).toEqual([])
    expect(db.entitlements).toEqual([])
    expect(log.info).not.toHaveBeenCalled()
    expect(log.error).not.toHaveBeenCalled()
  })

  it.each([
    ['lock a: no number of days', { [EVALUATION_ACCESS_DAYS_ENV]: undefined }],
    ['lock a: zero days', { [EVALUATION_ACCESS_DAYS_ENV]: '0' }],
    ['lock a: 91 days', { [EVALUATION_ACCESS_DAYS_ENV]: '91' }],
    ['lock a: a decimal', { [EVALUATION_ACCESS_DAYS_ENV]: '30.5' }],
    ['lock b: no project listed', { [EVALUATION_ACCESS_PROJECT_REF_ENV]: undefined }],
    [
      'lock b: another project listed',
      { [EVALUATION_ACCESS_PROJECT_REF_ENV]: 'abcdefghijklmnopqrst' },
    ],
    [
      'lock b: a database URL that is not a hosted project',
      { NEXT_PUBLIC_SUPABASE_URL: 'https://db.performe.example' },
    ],
    ['lock c: no actor', { [EVALUATION_ACCESS_ACTOR_ID_ENV]: undefined }],
    ['lock c: an actor that is not a uuid', { [EVALUATION_ACCESS_ACTOR_ID_ENV]: 'operator' }],
    [
      'lock c: the all-zero uuid',
      { [EVALUATION_ACCESS_ACTOR_ID_ENV]: '00000000-0000-0000-0000-000000000000' },
    ],
    [
      'production: every variable present, the URL and the listed ref are production',
      {
        NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL,
        [EVALUATION_ACCESS_PROJECT_REF_ENV]: PRODUCTION_REF,
      },
    ],
    [
      'production: every variable present, the staging ref listed, the URL is production',
      { NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL },
    ],
    [
      'production listed next to staging',
      { [EVALUATION_ACCESS_PROJECT_REF_ENV]: `${STAGING_REF},${PRODUCTION_REF}` },
    ],
  ])('%s', async (_name, overrides) => {
    const log = logs()
    switchOn(overrides)
    const db = new EvaluationMemoryDb().addAccount()

    const response = await wire(await post(db))

    expect(db.operations).toEqual(BASELINE_OPERATIONS)
    expect(response).toEqual(await baselineResponse())
    expect(db.events).toEqual([])
    expect(db.entitlements).toEqual([])
    expect(log.info).not.toHaveBeenCalled()
    expect(log.error).not.toHaveBeenCalled()
    await expect(authorizeMobileEntitlement(db.client, USER, GATED_PATH)).rejects.toMatchObject({
      status: 402,
      code: 'subscription_required',
    })
  })
})

describe('first completion with the four locks open', () => {
  it('grants exactly one event and one entitlement, and the response is the same bytes', async () => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()

    const response = await wire(await post(db))

    expect(db.operations).toEqual(FIRST_GRANT_OPERATIONS)
    expect(response).toEqual(await baselineResponse())
    expect(JSON.parse(response.body)).toEqual({
      data: {
        onboarding_completed: true,
        completed_at: NOW.toISOString(),
        objective: 'recomposicao',
        persona: 'focus',
        document_actions: [
          {
            document_key: 'terms_of_service',
            version: '2026-10-01.1',
            locale: 'pt-BR',
            content_hash: 'a'.repeat(64),
            purpose: 'terms_of_service_acceptance',
            action: 'acceptance',
            acted_at: NOW.toISOString(),
          },
        ],
      },
      meta: { api_version: 'v1', request_id: REQUEST_ID },
    })

    expect(db.calls.filter((call) => call.name === 'apply_entitlement_event')).toEqual([
      {
        name: 'apply_entitlement_event',
        params: {
          p_provider_event_id: `closed-evaluation-auto:${USER}:grant`,
          p_event_type: 'manual.qa.grant',
          p_user_id: USER,
          p_entitlement_key: 'bodyflow_full',
          p_source: 'manual',
          p_source_reference: `closed-evaluation-auto:${USER}`,
          p_status: 'active',
          p_plan: 'trial',
          p_environment: 'sandbox',
          p_occurred_at: '2026-10-05T15:00:00.000Z',
          p_starts_at: '2026-10-05T15:00:00.000Z',
          p_access_expires_at: '2026-11-04T15:00:00.000Z',
          p_grace_expires_at: null,
          p_cancel_at_period_end: false,
          p_reason_code: 'closed_evaluation_auto',
          p_actor_id: ACTOR,
        },
      },
    ])
    expect(db.events).toEqual([
      { ...GRANTED_EVENT, id: expect.any(String), entitlement_id: db.entitlements[0]?.id },
    ])
    expect(db.entitlements).toEqual([{ ...grantedEntitlement(30), id: expect.any(String) }])

    expect(log.error).not.toHaveBeenCalled()
    expect(log.info.mock.calls).toEqual([
      [
        '[mobile-api] evaluation_access',
        { request_id: REQUEST_ID, scope: 'mobile_api_v1', result: 'applied', days: 30 },
      ],
    ])
  })

  it('opens the routes that answered 402, until the expiry instant and not after', async () => {
    logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    await expect(
      authorizeMobileEntitlement(db.client, USER, GATED_PATH, NOW),
    ).rejects.toMatchObject({ status: 402, code: 'subscription_required' })

    await post(db)

    const expiry = NOW.getTime() + 30 * DAY_MS
    await expect(
      authorizeMobileEntitlement(db.client, USER, GATED_PATH, NOW),
    ).resolves.toBeUndefined()
    await expect(
      authorizeMobileEntitlement(db.client, USER, GATED_PATH, new Date(expiry - 1)),
    ).resolves.toBeUndefined()
    await expect(
      authorizeMobileEntitlement(db.client, USER, GATED_PATH, new Date(expiry)),
    ).rejects.toMatchObject({ status: 402, code: 'subscription_required' })

    // What GET /entitlements answers for this account.
    await expect(loadMobileEntitlement(db.client, USER, NOW)).resolves.toEqual({
      entitlement: 'bodyflow_full',
      has_active_access: true,
      status: 'active',
      source: 'manual',
      plan: 'trial',
      access_expires_at: '2026-11-04T15:00:00.000Z',
      grace_expires_at: null,
      cancel_at_period_end: false,
      reason: 'valid_entitlement',
      decision_at: NOW.toISOString(),
      mobile_billing: {
        provider: 'revenuecat',
        available: false,
        reason: 'provider_not_configured',
      },
    })
  })

  it.each([
    ['1', '2026-10-06T15:00:00.000Z'],
    ['7', '2026-10-12T15:00:00.000Z'],
    ['90', '2027-01-03T15:00:00.000Z'],
  ])('MOBILE_EVALUATION_ACCESS_DAYS=%s expires at %s', async (days, expiresAt) => {
    logs()
    switchOn({ [EVALUATION_ACCESS_DAYS_ENV]: days })
    const db = new EvaluationMemoryDb().addAccount()

    await post(db)

    expect(db.entitlements.map((row) => [row.starts_at, row.access_expires_at])).toEqual([
      ['2026-10-05T15:00:00.000Z', expiresAt],
    ])
    expect(db.events).toHaveLength(1)
  })
})

describe('never twice', () => {
  async function grantedAccount() {
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    await post(db)
    expect(db.events).toHaveLength(1)
    const before = structuredClone({ events: db.events, entitlements: db.entitlements })
    db.operations.length = 0
    return { db, before }
  }

  it('the same request replayed: the completion is validated again, nothing is granted', async () => {
    logs()
    const { db, before } = await grantedAccount()

    const replay = await post(db)

    expect(replay.status).toBe(200)
    expect(replay.headers.get('idempotency-replayed')).toBe('true')
    // One read (the profile already has its completion time) and no entitlement query.
    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'select:user_profiles',
      'rpc:complete_mobile_onboarding_atomic',
    ])
    expect({ events: db.events, entitlements: db.entitlements }).toEqual(before)
  })

  it('the same answers under a new Idempotency-Key, a day later', async () => {
    logs()
    const { db, before } = await grantedAccount()
    vi.setSystemTime(new Date(NOW.getTime() + DAY_MS))

    const response = await post(db, completionBody(), 'evaluation-access-key-2')

    expect(response.status).toBe(200)
    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'select:user_profiles',
      'rpc:complete_mobile_onboarding_atomic',
      'rpc:complete_mobile_api_request',
    ])
    expect({ events: db.events, entitlements: db.entitlements }).toEqual(before)
  })

  it('a new document version re-accepted ten days later: the expiry does not move', async () => {
    logs()
    const { db, before } = await grantedAccount()
    db.publishNewDocumentVersion()
    vi.setSystemTime(new Date(NOW.getTime() + 10 * DAY_MS))

    const response = await post(db, completionBody(DOCUMENT_V2), 'evaluation-access-key-3')
    const body = (await response.json()) as { data: { completed_at: string } }

    expect(response.status).toBe(200)
    expect(body.data.completed_at).toBe(NOW.toISOString())
    expect(db.operations).not.toContain('rpc:apply_entitlement_event')
    expect(db.operations).not.toContain('rpc:resolve_user_entitlement')
    expect({ events: db.events, entitlements: db.entitlements }).toEqual(before)
    expect(db.entitlements[0]?.access_expires_at).toBe('2026-11-04T15:00:00.000Z')
  })

  it('after the access expired, a re-acceptance does not renew it (declared as RC EA)', async () => {
    logs()
    const { db, before } = await grantedAccount()
    db.publishNewDocumentVersion()
    const later = new Date(NOW.getTime() + 31 * DAY_MS)
    vi.setSystemTime(later)

    const response = await post(db, completionBody(DOCUMENT_V2), 'evaluation-access-key-4')

    expect(response.status).toBe(200)
    expect({ events: db.events, entitlements: db.entitlements }).toEqual(before)
    await expect(
      authorizeMobileEntitlement(db.client, USER, GATED_PATH, later),
    ).rejects.toMatchObject({ status: 402, code: 'subscription_required' })
  })

  it('two first completions arriving together end as one grant', async () => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()

    const responses = await Promise.all([
      post(db, completionBody(), 'evaluation-access-key-a'),
      post(db, completionBody(), 'evaluation-access-key-b'),
    ])

    expect(responses.map((response) => response.status)).toEqual([200, 200])
    // Both saw an account without any event; the database kept one.
    expect(db.calls.filter((call) => call.name === 'apply_entitlement_event')).toHaveLength(2)
    expect(db.events).toEqual([
      { ...GRANTED_EVENT, id: expect.any(String), entitlement_id: db.entitlements[0]?.id },
    ])
    expect(db.entitlements).toEqual([{ ...grantedEntitlement(30), id: expect.any(String) }])
    expect(
      log.info.mock.calls.map(([, payload]) => (payload as { result: string }).result),
    ).toEqual(['applied', 'duplicate'])
    expect(log.error).not.toHaveBeenCalled()
  })
})

describe('lock d — an account that already has an entitlement event is left alone', () => {
  it.each([
    ['an active manual trial', {}, true],
    ['a trial that lapsed last month', { p_access_expires_at: '2026-09-15T12:00:00.000Z' }, false],
    [
      'a blocked access',
      {
        p_status: 'blocked',
        p_plan: null,
        p_access_expires_at: null,
        p_event_type: 'manual.qa.block',
      },
      false,
    ],
    [
      'an expired status',
      { p_status: 'expired', p_access_expires_at: '2026-09-15T12:00:00.000Z' },
      false,
    ],
    [
      'an access that only starts next month',
      { p_starts_at: '2026-11-01T12:00:00.000Z', p_access_expires_at: '2026-12-01T12:00:00.000Z' },
      false,
    ],
    ['an event for another entitlement key', { p_entitlement_key: 'another_product' }, false],
  ])('%s', async (_name, seed, hasAccess) => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.seedEntitlement(seed)
    const before = structuredClone({ events: db.events, entitlements: db.entitlements })

    const response = await wire(await post(db))

    expect(response).toEqual(await baselineResponse())
    expect(db.operations).toEqual(LEFT_ALONE_OPERATIONS)
    expect({ events: db.events, entitlements: db.entitlements }).toEqual(before)
    expect(log.info.mock.calls).toEqual([
      [
        '[mobile-api] evaluation_access',
        { request_id: REQUEST_ID, scope: 'mobile_api_v1', result: 'left_alone' },
      ],
    ])
    expect(log.error).not.toHaveBeenCalled()
    const gate = authorizeMobileEntitlement(db.client, USER, GATED_PATH, NOW)
    if (hasAccess) await expect(gate).resolves.toBeUndefined()
    else await expect(gate).rejects.toMatchObject({ status: 402 })
  })

  it('an entitlement row whose event is gone is left alone too', async () => {
    logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.seedEntitlement({ p_access_expires_at: '2026-09-15T12:00:00.000Z' })
    db.events.length = 0
    const before = structuredClone(db.entitlements)

    await post(db)

    expect(db.operations).toEqual(LEFT_ALONE_OPERATIONS)
    expect(db.events).toEqual([])
    expect(db.entitlements).toEqual(before)
  })

  it('an event row whose entitlement is gone is left alone too', async () => {
    logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.seedEntitlement()
    db.entitlements.length = 0
    const before = structuredClone(db.events)

    await post(db)

    expect(db.operations).toEqual(LEFT_ALONE_OPERATIONS)
    expect(db.events).toEqual(before)
    expect(db.entitlements).toEqual([])
  })
})

describe('an account that completed onboarding before the switch was on (declared as RC EA)', () => {
  async function oldAccount() {
    const db = new EvaluationMemoryDb().addAccount()
    await post(db)
    expect(db.completedAt()).toBe(NOW.toISOString())
    switchOn()
    vi.setSystemTime(new Date(NOW.getTime() + 3 * DAY_MS))
    db.operations.length = 0
    return db
  }

  it.each([
    ['replays its completion', 'evaluation-access-key-1', false],
    ['sends the same answers under a new key', 'evaluation-access-key-9', false],
    ['re-accepts a new document version', 'evaluation-access-key-9', true],
  ])('gets nothing when it %s', async (_name, key, newVersion) => {
    const log = logs()
    const db = await oldAccount()
    if (newVersion) db.publishNewDocumentVersion()

    const response = await post(db, completionBody(newVersion ? DOCUMENT_V2 : DOCUMENT_V1), key)

    expect(response.status).toBe(200)
    expect(db.operations.filter((operation) => !operation.endsWith('_mobile_api_request'))).toEqual(
      ['select:user_profiles', 'rpc:complete_mobile_onboarding_atomic'],
    )
    expect(db.events).toEqual([])
    expect(db.entitlements).toEqual([])
    expect(log.info).not.toHaveBeenCalled()
    expect(log.error).not.toHaveBeenCalled()
    await expect(authorizeMobileEntitlement(db.client, USER, GATED_PATH)).rejects.toMatchObject({
      status: 402,
    })
  })
})

describe('a failure of the grant never reaches the onboarding response', () => {
  const FAILURES: Array<[string, string, Failure, string, string]> = [
    [
      'the profile read answers an error',
      'select:user_profiles',
      'error',
      'profile_lookup',
      'Error',
    ],
    ['the profile read throws', 'select:user_profiles', 'throw', 'unexpected', 'TypeError'],
    [
      'the event read answers an error',
      'select:entitlement_events',
      'error',
      'event_lookup',
      'Error',
    ],
    ['the event read throws', 'select:entitlement_events', 'throw', 'unexpected', 'TypeError'],
    [
      'the event read answers no list',
      'select:entitlement_events',
      { data: null },
      'event_lookup',
      'Error',
    ],
    [
      'the resolver answers an error',
      'rpc:resolve_user_entitlement',
      'error',
      'entitlement_lookup',
      'Error',
    ],
    ['the resolver throws', 'rpc:resolve_user_entitlement', 'throw', 'unexpected', 'TypeError'],
    [
      'the resolver answers nothing',
      'rpc:resolve_user_entitlement',
      { data: null },
      'entitlement_lookup',
      'Error',
    ],
    ['the grant answers an error', 'rpc:apply_entitlement_event', 'error', 'grant', 'Error'],
    ['the grant throws', 'rpc:apply_entitlement_event', 'throw', 'unexpected', 'TypeError'],
    ['the grant answers nothing', 'rpc:apply_entitlement_event', { data: null }, 'grant', 'Error'],
    [
      'the grant answers "stale"',
      'rpc:apply_entitlement_event',
      { data: { result: 'stale' } },
      'grant',
      'Error',
    ],
  ]

  it.each(FAILURES)('%s', async (_name, operation, failure, stage, errorName) => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.failures.set(operation, failure)

    const response = await wire(await post(db))

    expect(response).toEqual(await baselineResponse())
    expect(db.completedAt()).toBe(NOW.toISOString())
    expect(db.events).toEqual([])
    expect(db.entitlements).toEqual([])
    expect(db.operations.at(-1)).toBe('rpc:complete_mobile_api_request')
    expect(log.info).not.toHaveBeenCalled()
    expect(log.error.mock.calls).toEqual([
      [
        '[mobile-api] evaluation_access_failed',
        { request_id: REQUEST_ID, scope: 'mobile_api_v1', stage, error_name: errorName },
      ],
    ])
    // No personal data: neither the account nor what the database said.
    const logged = JSON.stringify(log.error.mock.calls)
    for (const secret of [
      USER,
      AUTH_USER,
      EMAIL,
      NAME,
      ACTOR,
      'permission denied',
      'network down',
    ]) {
      expect(logged).not.toContain(secret)
    }
  })

  it('a failed profile read asks nothing else about entitlements', async () => {
    logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.failures.set('select:user_profiles', 'error')

    await post(db)

    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'select:user_profiles',
      'rpc:complete_mobile_onboarding_atomic',
      'rpc:complete_mobile_api_request',
    ])
  })

  it('an account id that is not a uuid is refused before any query', async () => {
    const log = logs()
    const db = new EvaluationMemoryDb().addAccount()
    // The id becomes part of the event id and of the source reference, which
    // the domain restricts to a small alphabet.
    const requestContext = context(db)
    const grant = await prepareEvaluationAccess(
      { ...requestContext, auth: { ...requestContext.auth, userId: 'not a uuid' } },
      { env: ON },
    )
    await grant()

    expect(db.operations).toEqual([])
    expect(log.error.mock.calls).toEqual([
      [
        '[mobile-api] evaluation_access_failed',
        { request_id: REQUEST_ID, scope: 'mobile_api_v1', stage: 'account', error_name: 'Error' },
      ],
    ])
  })

  it('after a failed grant, replaying the completion does not grant (declared as RC EA)', async () => {
    logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.failures.set('rpc:apply_entitlement_event', 'error')
    await post(db)
    db.failures.clear()
    db.operations.length = 0

    const replay = await post(db)

    expect(replay.status).toBe(200)
    expect(db.operations).not.toContain('rpc:apply_entitlement_event')
    expect(db.events).toEqual([])
  })

  it('a completion that the database refuses grants nothing', async () => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    db.publishNewDocumentVersion()

    await expect(post(db, completionBody(DOCUMENT_V1))).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_requirements_changed',
    })

    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'select:user_profiles',
      'rpc:complete_mobile_onboarding_atomic',
      'rpc:fail_mobile_api_request',
    ])
    expect(db.completedAt()).toBeNull()
    expect(db.events).toEqual([])
    expect(log.info).not.toHaveBeenCalled()
    expect(log.error).not.toHaveBeenCalled()
  })

  it('a completion that fails with the switch off fails the same way', async () => {
    const db = new EvaluationMemoryDb().addAccount()
    db.publishNewDocumentVersion()

    await expect(post(db, completionBody(DOCUMENT_V1))).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_requirements_changed',
    })
    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'rpc:complete_mobile_onboarding_atomic',
      'rpc:fail_mobile_api_request',
    ])
  })
})

describe('where the grant is called from', () => {
  const here = dirname(fileURLToPath(import.meta.url))
  const sourceRoot = resolve(here, '../..')

  function sourceFiles(directory: string): string[] {
    return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
      const path = resolve(directory, entry.name)
      if (entry.isDirectory()) return sourceFiles(path)
      return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) ? [path] : []
    })
  }

  it('the legacy partial onboarding POST does not complete onboarding and asks nothing', async () => {
    const log = logs()
    switchOn()
    const db = new EvaluationMemoryDb().addAccount()
    const dependencies: OnboardingRouteDependencies = {
      createOnboardingRepository: createSupabaseOnboardingRepository,
      executeIdempotent: executeSupabaseIdempotent,
      saveLegacyOnboarding: vi.fn(async () => ({
        profile: null,
        targets: { calories: null, protein_g: null },
      })),
    }

    const response = await handleOnboardingPost(context(db, { height_cm: 180 }), dependencies)

    expect(response.status).toBe(200)
    expect(db.operations).toEqual([
      'rpc:claim_mobile_api_request',
      'rpc:complete_mobile_api_request',
    ])
    expect(db.events).toEqual([])
    expect(log.info).not.toHaveBeenCalled()
  })

  it('only the onboarding handler imports the module', () => {
    const importers = sourceFiles(sourceRoot)
      .filter((path) => /evaluation-access['"]/.test(readFileSync(path, 'utf8')))
      .map((path) => relative(sourceRoot, path).split(sep).join('/'))
    expect(importers).toEqual(['app/api/mobile/v1/onboarding/handler.ts'])
  })

  it('the handler asks before the completion and grants right after it, once', () => {
    const handler = readFileSync(
      resolve(sourceRoot, 'app/api/mobile/v1/onboarding/handler.ts'),
      'utf8',
    )
    expect(handler.match(/prepareEvaluationAccess\(/g)).toHaveLength(1)
    expect(handler.match(/grantEvaluationAccess\(\)/g)).toHaveLength(1)
    const prepared = handler.indexOf('await prepareEvaluationAccess(context)')
    const completed = handler.indexOf('await completeOnboarding(')
    const granted = handler.indexOf('await grantEvaluationAccess()')
    expect(prepared).toBeGreaterThan(0)
    expect(completed).toBeGreaterThan(prepared)
    expect(granted).toBeGreaterThan(completed)
  })

  it('the route wrapper shared by the 48 routes and the entitlement gate do not know it', () => {
    for (const file of ['route.ts', 'entitlement-service.ts', 'onboarding-service.ts']) {
      expect(readFileSync(resolve(here, file), 'utf8'), file).not.toMatch(/evaluation/i)
    }
  })
})

describe('declared pendencies', () => {
  it('every "RC EA" line of this header is in docs/mobile/api-v1.md, identical', () => {
    const header = readFileSync(new URL(import.meta.url), 'utf8')
    const doc = readFileSync(
      new URL('../../../../../docs/mobile/api-v1.md', import.meta.url),
      'utf8',
    )
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC EA — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC EA — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(9)
    expect(fromDoc).toEqual(fromHeader)
  })
})
