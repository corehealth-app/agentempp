import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'

export type FlowMessageRole = 'user' | 'assistant'
export type FlowMessageState = 'processing' | 'completed' | 'failed'

/** Executions (first attempts and retries) a patient may start per rolling minute. */
export const FLOW_EXECUTIONS_PER_MINUTE = 10

/**
 * How long an execution attempt owns its turn. It mirrors the in-progress
 * window of `claim_mobile_api_request` (10 minutes) and outlives the route's
 * `maxDuration` (300 s), so a `processing` turn older than this belongs to an
 * invocation that has provably ended — it is never "possibly still running".
 */
export const FLOW_EXECUTION_LEASE_MS = 10 * 60_000

/**
 * The current execution attempt of an inbound turn, kept in its raw_payload.
 * `providerStartedAt` is written right before Flow (and so the paid provider)
 * is called: when an attempt died without it, nothing effective happened.
 */
export interface FlowInboundAttempt {
  startedAt: string
  providerStartedAt: string | null
  /** Start time of every retry execution of this turn (newest last, bounded). */
  retryStartedAt: string[]
}

export interface StoredFlowMessage {
  id: string
  role: FlowMessageRole
  content: string
  state: FlowMessageState
  requestId: string
  createdAt: string
  /** Inbound turns only; null for rows written before attempts were recorded. */
  attempt?: FlowInboundAttempt | null
}

interface NewFlowMessage {
  userId: string
  content: string
  providerMessageId: string
  requestId: string
  state: FlowMessageState
  createdAt: string
  metadata?: Record<string, unknown>
  attempt?: FlowInboundAttempt
}

export interface FlowInboundTransition {
  /** The change only applies while the turn is still in this state… */
  from: FlowMessageState
  to: FlowMessageState
  requestId: string
  attempt: FlowInboundAttempt
  /** …and still in the attempt this request observed (null: a row written
   * before attempts were recorded), so a stale view never wins. */
  expectedAttemptStartedAt: string | null
  /** When set, the attempt must also still belong to this request. */
  expectedRequestId?: string
  errorCode?: string
}

export interface FlowChatStore {
  loadHistory(userId: string, limit: number): Promise<StoredFlowMessage[]>
  /** First attempts created since `since`, plus every retry started since then. */
  countRecentExecutions(userId: string, since: string): Promise<number>
  findInbound(userId: string, providerMessageId: string): Promise<StoredFlowMessage | null>
  findAssistant(userId: string, providerMessageId: string): Promise<StoredFlowMessage | null>
  insertInbound(input: NewFlowMessage): Promise<StoredFlowMessage>
  /** Compare-and-set on the turn's state; false when another request changed it first. */
  transitionInbound(
    userId: string,
    providerMessageId: string,
    change: FlowInboundTransition,
  ): Promise<boolean>
  insertAssistant(input: NewFlowMessage): Promise<StoredFlowMessage>
  completeInbound(userId: string, providerMessageId: string): Promise<void>
  failInbound(userId: string, providerMessageId: string, code?: string): Promise<void>
}

export interface FlowAgent {
  reply(input: {
    userId: string
    providerMessageId: string
    text: string
    timestamp: Date
  }): Promise<{ text: string; metadata: Record<string, unknown> }>
}

/** The plan proposal a turn produced, for the app to open its review. */
export interface FlowTurnDraft {
  id: string
  domain: 'training' | 'nutrition'
}

export interface FlowDraftLookup {
  /** The draft created by this turn of this patient, if any. */
  findForTurn(userId: string, turnProviderMessageId: string): Promise<FlowTurnDraft | null>
}

export interface FlowChatDependencies {
  store: FlowChatStore
  agent: FlowAgent
  /** Absent where plan drafts do not exist; the reply then carries none. */
  drafts?: FlowDraftLookup
}

/**
 * The reply plus the proposal its turn created. The draft comes from the
 * database (bound to the patient and to the turn), never from the model's
 * text, and a failed lookup only leaves the reply without the shortcut.
 */
async function turnResponse(
  dependencies: FlowChatDependencies,
  userId: string,
  turnProviderMessageId: string,
  message: StoredFlowMessage,
) {
  const draft = dependencies.drafts
    ? await dependencies.drafts.findForTurn(userId, turnProviderMessageId).catch(() => null)
    : null
  return { conversation_id: 'flow' as const, message: dto(message), draft }
}

export interface SendFlowMessageInput {
  userId: string
  text: string
  idempotencyKey: string
  requestId: string
  now: Date
}

export interface FlowMessageDTO {
  id: string
  conversation_id: 'flow'
  role: FlowMessageRole
  content: string
  state: FlowMessageState
  request_id: string
  created_at: string
}

function dto(message: StoredFlowMessage): FlowMessageDTO {
  return {
    id: message.id,
    conversation_id: 'flow',
    role: message.role,
    content: message.content,
    state: message.state,
    request_id: message.requestId,
    created_at: message.createdAt,
  }
}

export async function loadFlowHistory(
  dependencies: FlowChatDependencies,
  userId: string,
  limit: number,
) {
  const rows = await dependencies.store.loadHistory(userId, limit)
  return {
    conversation_id: 'flow' as const,
    messages: rows
      // A reply stored empty before tags were flattened is not a message.
      .filter((row) => row.role !== 'assistant' || row.content.trim().length > 0)
      .sort((left, right) => left.createdAt.localeCompare(right.createdAt))
      .map(dto),
  }
}

/**
 * `messages(provider, provider_message_id)` is unique across ALL users, while
 * an Idempotency-Key is only unique per user. The stored id therefore carries
 * the authenticated user (never a payload value). "/" is not allowed in an
 * Idempotency-Key, so a scoped id can never equal a legacy row's bare key.
 */
export function scopedFlowProviderMessageId(userId: string, idempotencyKey: string): string {
  return `mobile_flow/${userId}/${idempotencyKey}`
}

/**
 * Every reply is written as "<scoped inbound>/assistant" ("/" is also outside
 * the key charset), so no key — e.g. "x:assistant", or another user's legacy
 * row — can ever name it. A legacy turn's earlier reply, if any, is still read
 * from its original "<key>:assistant".
 */
function scopedReplyProviderMessageId(userId: string, idempotencyKey: string): string {
  return `${scopedFlowProviderMessageId(userId, idempotencyKey)}/assistant`
}

/** The row being inserted already exists (unique index on the provider id). */
export class FlowMessageAlreadyStoredError extends Error {
  constructor() {
    super('Flow message already stored')
    this.name = 'FlowMessageAlreadyStoredError'
  }
}

const MAX_RECORDED_RETRIES = 20

function inProgress(): MobileApiError {
  return new MobileApiError(
    409,
    'idempotency_request_in_progress',
    'The same request is already being processed',
  )
}

const SAFE_TURN_ERROR_NAMES = new Set([
  'Error',
  'TypeError',
  'RangeError',
  'SyntaxError',
  'ZodError',
  'APIError',
  'APIConnectionError',
  'APIConnectionTimeoutError',
  'APIUserAbortError',
  'BadRequestError',
  'AuthenticationError',
  'PermissionDeniedError',
  'NotFoundError',
  'UnprocessableEntityError',
  'RateLimitError',
  'InternalServerError',
])

// Our own failure messages are short lowercase codes ("diet proposal profile
// lookup failed"); only those are logged. Provider messages, and anything that
// could carry the patient's text, are not (audit 2026-09-28).
const INTERNAL_CODE = /^[a-z][a-z _-]{2,79}$/

function logTurnFailure(error: unknown): void {
  if (error === 'empty_reply') {
    console.error('[mobile-flow] turn_failed', { error_name: 'EmptyReply', provider_status: null, internal_code: null })
    return
  }
  const className = error instanceof Error ? error.constructor.name : ''
  const name =
    error instanceof Error && SAFE_TURN_ERROR_NAMES.has(className)
      ? className
      : error instanceof Error && SAFE_TURN_ERROR_NAMES.has(error.name)
        ? error.name
        : 'UnknownError'
  const rawStatus = (error as { status?: unknown } | null)?.status
  const status = typeof rawStatus === 'number' && Number.isInteger(rawStatus) ? rawStatus : null
  const message = error instanceof Error ? error.message : ''
  console.error('[mobile-flow] turn_failed', {
    error_name: name,
    provider_status: status,
    internal_code: status === null && INTERNAL_CODE.test(message) ? message : null,
  })
}

/** Safe outline of the tools a Flow turn ran: names, outcome, own codes only. */
export function summarizeFlowToolCalls(
  toolCalls: ReadonlyArray<{ name: string; arguments?: unknown; result?: unknown; error?: string }>,
): Array<{ name: string; outcome: 'ok' | 'returned_failure' | 'threw'; code: string | null }> {
  return toolCalls.slice(0, 10).map((call) => {
    const name = /^[a-z_]{1,64}$/.test(call.name) ? call.name : 'invalid_tool_name'
    if (call.error !== undefined) {
      const code = call.error.trimStart().startsWith('[{')
        ? 'validation'
        : INTERNAL_CODE.test(call.error)
          ? call.error
          : null
      return { name, outcome: 'threw', code }
    }
    const failed =
      call.result !== null && typeof call.result === 'object' && (call.result as { success?: unknown }).success === false
    return { name, outcome: failed ? 'returned_failure' : 'ok', code: null }
  })
}

function providerFailed(): MobileApiError {
  return new MobileApiError(502, 'flow_provider_failed', 'Flow is temporarily unavailable')
}

/**
 * Every execution that can reach the provider or a tool — a first attempt, a
 * retry of a failed turn, or the continuation of a turn whose invocation died
 * before the provider — is counted here. A replay of a stored reply is not.
 */
async function assertExecutionBudget(dependencies: FlowChatDependencies, input: SendFlowMessageInput) {
  const since = new Date(input.now.getTime() - 60_000).toISOString()
  const executions = await dependencies.store.countRecentExecutions(input.userId, since)
  if (executions >= FLOW_EXECUTIONS_PER_MINUTE) {
    throw new MobileApiError(429, 'flow_rate_limited', 'Please wait before sending again')
  }
}

function retryAttempt(previous: FlowInboundAttempt | null | undefined, now: string): FlowInboundAttempt {
  return {
    startedAt: now,
    providerStartedAt: null,
    retryStartedAt: [...(previous?.retryStartedAt ?? []), now].slice(-MAX_RECORDED_RETRIES),
  }
}

/**
 * Decides what an existing inbound turn (no stored reply) may do now, and
 * claims it for this request. Returns the attempt this request now owns.
 */
async function resumeTurn(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
  providerMessageId: string,
  inbound: StoredFlowMessage,
): Promise<FlowInboundAttempt> {
  const store = dependencies.store
  const nowIso = input.now.toISOString()

  if (inbound.state === 'processing') {
    const startedAt = inbound.attempt?.startedAt ?? inbound.createdAt
    // The attempt may still be running: never execute it a second time.
    if (input.now.getTime() - new Date(startedAt).getTime() < FLOW_EXECUTION_LEASE_MS) {
      throw inProgress()
    }
    // Its invocation has ended. Close it first, so only one request recovers
    // it — and only the attempt this request saw.
    const closed = await store.transitionInbound(input.userId, providerMessageId, {
      from: 'processing',
      to: 'failed',
      requestId: inbound.requestId,
      attempt: inbound.attempt ?? { startedAt, providerStartedAt: null, retryStartedAt: [] },
      expectedAttemptStartedAt: inbound.attempt?.startedAt ?? null,
      errorCode: 'flow_turn_interrupted',
    })
    if (!closed) throw inProgress()
    // The provider may have been called (and charged) and its effects are
    // unknown — or, for a row without markers, cannot be known. The turn is
    // failed; only a later explicit retry runs it again.
    if (!inbound.attempt || inbound.attempt.providerStartedAt !== null) {
      throw providerFailed()
    }
    // It died before the provider: nothing effective happened; continue below
    // as a new execution of a failed turn.
  }

  // A failed turn (or, defensively, a completed one whose reply is missing)
  // runs again only as a new, counted execution.
  await assertExecutionBudget(dependencies, input)
  const attempt = retryAttempt(inbound.attempt, nowIso)
  let claimed: boolean
  try {
    claimed = await store.transitionInbound(input.userId, providerMessageId, {
      from: inbound.state === 'completed' ? 'completed' : 'failed',
      to: 'processing',
      requestId: input.requestId,
      attempt,
      expectedAttemptStartedAt: inbound.attempt?.startedAt ?? null,
    })
  } catch {
    // The claim may or may not have been written.
    await releaseTurn(dependencies, input, providerMessageId, attempt, 'flow_provider_failed')
    throw providerFailed()
  }
  if (!claimed) throw inProgress()
  return attempt
}

/**
 * Best effort: a turn this request recorded as `processing` goes back to
 * `failed` (only if it is still this request's attempt), so a storage error
 * never leaves it "in progress" for the whole lease. The provider was not
 * called on any path that uses it.
 */
async function releaseTurn(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
  providerMessageId: string,
  attempt: FlowInboundAttempt,
  errorCode: string,
) {
  await dependencies.store
    .transitionInbound(input.userId, providerMessageId, {
      from: 'processing',
      to: 'failed',
      requestId: input.requestId,
      attempt,
      expectedAttemptStartedAt: attempt.startedAt,
      expectedRequestId: input.requestId,
      errorCode,
    })
    .catch(() => false)
}

/**
 * The count-then-record above is not atomic across different keys, so the
 * execution is checked again once recorded: counting itself, a request that
 * finds more than the limit gives its turn back (failed, never deleted) and
 * is refused. Concurrent bursts can refuse more than strictly needed; they
 * can never let more than the limit reach the provider.
 */
async function confirmExecutionBudget(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
  providerMessageId: string,
  attempt: FlowInboundAttempt,
) {
  const since = new Date(input.now.getTime() - 60_000).toISOString()
  let executions: number
  try {
    executions = await dependencies.store.countRecentExecutions(input.userId, since)
  } catch {
    await releaseTurn(dependencies, input, providerMessageId, attempt, 'flow_provider_failed')
    throw providerFailed()
  }
  if (executions <= FLOW_EXECUTIONS_PER_MINUTE) return
  await releaseTurn(dependencies, input, providerMessageId, attempt, 'flow_rate_limited')
  throw new MobileApiError(429, 'flow_rate_limited', 'Please wait before sending again')
}

export async function sendFlowMessage(
  dependencies: FlowChatDependencies,
  input: SendFlowMessageInput,
) {
  // The inbound this key already created: a scoped row, or a legacy
  // (pre-scoping) row that used the bare key. Both lookups are pinned to the
  // authenticated user, so another user's rows are never read.
  let inboundProviderId = scopedFlowProviderMessageId(input.userId, input.idempotencyKey)
  let legacyTurn = false
  let existingInbound = await dependencies.store.findInbound(input.userId, inboundProviderId)
  if (!existingInbound) {
    const legacyInbound = await dependencies.store.findInbound(input.userId, input.idempotencyKey)
    if (legacyInbound) {
      existingInbound = legacyInbound
      inboundProviderId = input.idempotencyKey
      legacyTurn = true
    }
  }
  // Same key, different text: a new request under a used key, never a replay.
  if (existingInbound && existingInbound.content !== input.text) {
    throw new MobileApiError(
      409,
      'idempotency_key_conflict',
      'Idempotency-Key was already used with a different message',
    )
  }

  const assistantProviderId = scopedReplyProviderMessageId(input.userId, input.idempotencyKey)
  const existing =
    (await dependencies.store.findAssistant(input.userId, assistantProviderId)) ??
    (legacyTurn
      ? await dependencies.store.findAssistant(input.userId, `${input.idempotencyKey}:assistant`)
      : null)
  if (existing) {
    // A reply stored empty before tags were flattened is never replayed as a
    // successful turn (and is not re-executed: the patient sends it again).
    if (existing.content.trim().length === 0) throw providerFailed()
    await dependencies.store.completeInbound(input.userId, inboundProviderId)
    return turnResponse(dependencies, input.userId, inboundProviderId, existing)
  }

  let attempt: FlowInboundAttempt
  if (existingInbound) {
    attempt = await resumeTurn(dependencies, input, inboundProviderId, existingInbound)
  } else {
    await assertExecutionBudget(dependencies, input)

    const createdAt = input.now.toISOString()
    attempt = { startedAt: createdAt, providerStartedAt: null, retryStartedAt: [] }
    try {
      await dependencies.store.insertInbound({
        userId: input.userId,
        content: input.text,
        providerMessageId: inboundProviderId,
        requestId: input.requestId,
        state: 'processing',
        createdAt,
        attempt,
      })
    } catch (error) {
      // The same turn was stored by a concurrent request; Flow is not called.
      if (error instanceof FlowMessageAlreadyStoredError) throw inProgress()
      // Any other error may still have written the row.
      await releaseTurn(dependencies, input, inboundProviderId, attempt, 'flow_provider_failed')
      throw providerFailed()
    }
  }

  const failTurn = async () => {
    await dependencies.store
      .failInbound(input.userId, inboundProviderId, 'flow_provider_failed')
      .catch(() => undefined)
    return providerFailed()
  }

  await confirmExecutionBudget(dependencies, input, inboundProviderId, attempt)

  // Recorded before the provider is called: if this invocation dies from here
  // on, the next one knows the provider may have run and does not repeat it.
  const providerAttempt: FlowInboundAttempt = { ...attempt, providerStartedAt: input.now.toISOString() }
  let owned: boolean
  try {
    owned = await dependencies.store.transitionInbound(input.userId, inboundProviderId, {
      from: 'processing',
      to: 'processing',
      requestId: input.requestId,
      attempt: providerAttempt,
      expectedAttemptStartedAt: attempt.startedAt,
      expectedRequestId: input.requestId,
    })
  } catch {
    // The provider was not called: give the turn back as failed so a retry
    // can run it, instead of leaving it "processing" for the whole lease.
    await releaseTurn(dependencies, input, inboundProviderId, attempt, 'flow_provider_failed')
    throw providerFailed()
  }
  if (!owned) throw inProgress()

  let reply: Awaited<ReturnType<FlowAgent['reply']>>
  try {
    reply = await dependencies.agent.reply({
      userId: input.userId,
      // The stored id, so the agent excludes this turn from its own history.
      providerMessageId: inboundProviderId,
      text: input.text,
      timestamp: input.now,
    })
  } catch (error) {
    logTurnFailure(error)
    throw await failTurn()
  }
  // A reply with no visible text is not a completed turn (nothing is shown to
  // the patient); it fails with the typed 502 and no assistant row is stored.
  if (reply.text.trim().length === 0) {
    logTurnFailure('empty_reply')
    throw await failTurn()
  }

  let assistant: StoredFlowMessage
  try {
    assistant = await dependencies.store.insertAssistant({
      userId: input.userId,
      content: reply.text,
      providerMessageId: assistantProviderId,
      requestId: input.requestId,
      state: 'completed',
      createdAt: new Date().toISOString(),
      metadata: reply.metadata,
    })
  } catch (error) {
    // This turn's reply is already stored: replay it. Anything else fails the
    // turn, so the inbound never stays "processing".
    if (error instanceof FlowMessageAlreadyStoredError) {
      const stored = await dependencies.store
        .findAssistant(input.userId, assistantProviderId)
        .catch(() => null)
      if (stored) {
        await dependencies.store.completeInbound(input.userId, inboundProviderId)
        return turnResponse(dependencies, input.userId, inboundProviderId, stored)
      }
    }
    throw await failTurn()
  }

  try {
    await dependencies.store.completeInbound(input.userId, inboundProviderId)
  } catch {
    throw await failTurn()
  }
  return turnResponse(dependencies, input.userId, inboundProviderId, assistant)
}

/** 23505 on the messages unique index: this exact provider id is stored. */
function persistError(error: { code?: string } | null, message: string): Error {
  if (error?.code === '23505') return new FlowMessageAlreadyStoredError()
  return new Error(message)
}

type MessageRow = {
  id: string
  direction: string
  content: string | null
  delivery_status: string | null
  raw_payload: unknown
  created_at: string
}

function rawRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}
}

function isoList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === 'string') : []
}

function attemptFromRaw(raw: Record<string, unknown>): FlowInboundAttempt | null {
  if (typeof raw.attempt_started_at !== 'string') return null
  return {
    startedAt: raw.attempt_started_at,
    providerStartedAt: typeof raw.provider_started_at === 'string' ? raw.provider_started_at : null,
    retryStartedAt: isoList(raw.retry_started_at),
  }
}

function inboundPayload(
  requestId: string,
  attempt: FlowInboundAttempt,
): { [key: string]: string | string[] | null } {
  const lastRetry = attempt.retryStartedAt.at(-1)
  return {
    request_id: requestId,
    conversation_id: 'flow',
    attempt_started_at: attempt.startedAt,
    provider_started_at: attempt.providerStartedAt,
    retry_started_at: attempt.retryStartedAt,
    // Top-level so the per-minute count can filter on it.
    ...(lastRetry ? { last_retry_at: lastRetry } : {}),
  }
}

function mapRow(row: MessageRow): StoredFlowMessage {
  const raw = rawRecord(row.raw_payload)
  const state =
    row.delivery_status === 'processing' || row.delivery_status === 'failed'
      ? row.delivery_status
      : 'completed'
  return {
    id: row.id,
    role: row.direction === 'in' ? 'user' : 'assistant',
    content: row.content ?? '',
    state,
    requestId: typeof raw.request_id === 'string' ? raw.request_id : 'request-unavailable',
    createdAt: row.created_at,
    ...(row.direction === 'in' ? { attempt: attemptFromRaw(raw) } : {}),
  }
}

export function createSupabaseFlowDraftLookup(supabase: ServiceClient): FlowDraftLookup {
  return {
    async findForTurn(userId, turnProviderMessageId) {
      const { data, error } = await (
        supabase.from('plan_drafts' as never) as unknown as {
          select(columns: string): {
            eq(column: string, value: string): {
              in(column: string, values: string[]): {
                in(column: string, values: string[]): {
                  order(column: string, options: { ascending: boolean }): {
                    limit(count: number): PromiseLike<{
                      data: Array<{ id: string; domain: string }> | null
                      error: { message: string } | null
                    }>
                  }
                }
              }
            }
          }
        }
      )
        .select('id, domain')
        .eq('user_id', userId)
        .in('request_key', [
          `${turnProviderMessageId}:propoe_plano_treino`,
          `${turnProviderMessageId}:propoe_plano_dieta`,
        ])
        .in('status', ['needs_completion', 'ready_for_review'])
        .order('created_at', { ascending: false })
        .limit(1)
      if (error) throw new Error('Unable to load the turn draft')
      const row = data?.[0]
      return row && (row.domain === 'training' || row.domain === 'nutrition')
        ? { id: row.id, domain: row.domain }
        : null
    },
  }
}

export function createSupabaseFlowChatStore(supabase: ServiceClient): FlowChatStore {
  const columns = 'id, direction, content, delivery_status, raw_payload, created_at'
  return {
    async loadHistory(userId, limit) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error) throw new Error('Unable to load Flow history')
      return ((data ?? []) as MessageRow[]).map(mapRow)
    },
    async countRecentExecutions(userId, since) {
      const { count, error } = await supabase
        .from('messages')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('direction', 'in')
        .gte('created_at', since)
      if (error) throw new Error('Unable to enforce Flow rate limit')
      // Retries do not create rows: every retry start is recorded on its turn,
      // and turns retried inside the window carry a recent `last_retry_at`.
      const { data: retried, error: retryError } = await supabase
        .from('messages')
        .select('raw_payload')
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('direction', 'in')
        .gte('raw_payload->>last_retry_at', since)
        .limit(50)
      if (retryError) throw new Error('Unable to enforce Flow rate limit')
      const retries = ((retried ?? []) as Array<{ raw_payload: unknown }>).reduce(
        (total, row) =>
          total + isoList(rawRecord(row.raw_payload).retry_started_at).filter((time) => time >= since).length,
        0,
      )
      // A count that did not come back is not zero: fail closed.
      if (count == null) throw new Error('Unable to enforce Flow rate limit')
      return count + retries
    },
    async findAssistant(userId, providerMessageId) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'out')
        .maybeSingle()
      if (error) throw new Error('Unable to verify Flow replay')
      return data ? mapRow(data as MessageRow) : null
    },
    async findInbound(userId, providerMessageId) {
      const { data, error } = await supabase
        .from('messages')
        .select(columns)
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
        .maybeSingle()
      if (error) throw new Error('Unable to verify Flow input replay')
      return data ? mapRow(data as MessageRow) : null
    },
    async insertInbound(input) {
      const { data, error } = await supabase
        .from('messages')
        .insert({
          user_id: input.userId,
          direction: 'in',
          role: 'user',
          content_type: 'text',
          content: input.content,
          provider: 'mobile_flow',
          provider_message_id: input.providerMessageId,
          raw_payload: input.attempt
            ? inboundPayload(input.requestId, input.attempt)
            : { request_id: input.requestId, conversation_id: 'flow' },
          delivery_status: input.state,
          created_at: input.createdAt,
        })
        .select(columns)
        .single()
      if (error || !data) throw persistError(error, 'Unable to persist Flow input')
      return mapRow(data as MessageRow)
    },
    async insertAssistant(input) {
      const metadata = input.metadata ?? {}
      const stringMetadata = (key: string) =>
        typeof metadata[key] === 'string' ? (metadata[key] as string) : null
      const numberMetadata = (key: string) =>
        typeof metadata[key] === 'number' ? (metadata[key] as number) : null
      const { data, error } = await supabase
        .from('messages')
        .insert({
          user_id: input.userId,
          direction: 'out',
          role: 'assistant',
          content_type: 'text',
          content: input.content,
          provider: 'mobile_flow',
          provider_message_id: input.providerMessageId,
          raw_payload: { request_id: input.requestId, conversation_id: 'flow' },
          delivery_status: input.state,
          agent_stage: stringMetadata('stage'),
          model_used: stringMetadata('modelUsed'),
          prompt_tokens: numberMetadata('promptTokens'),
          completion_tokens: numberMetadata('completionTokens'),
          cost_usd: numberMetadata('costUsd'),
          latency_ms: numberMetadata('latencyMs'),
          created_at: input.createdAt,
        })
        .select(columns)
        .single()
      if (error || !data) throw persistError(error, 'Unable to persist Flow output')
      return mapRow(data as MessageRow)
    },
    async transitionInbound(userId, providerMessageId, change) {
      const query = supabase
        .from('messages')
        .update({
          delivery_status: change.to,
          delivery_error: change.errorCode ? { code: change.errorCode } : null,
          raw_payload: inboundPayload(change.requestId, change.attempt),
        })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
        .eq('delivery_status', change.from)
      const sameAttempt =
        change.expectedAttemptStartedAt === null
          ? query.is('raw_payload->>attempt_started_at', null)
          : query.eq('raw_payload->>attempt_started_at', change.expectedAttemptStartedAt)
      const scoped =
        change.expectedRequestId === undefined
          ? sameAttempt
          : sameAttempt.eq('raw_payload->>request_id', change.expectedRequestId)
      const { data, error } = await scoped.select('id')
      if (error) throw new Error('Unable to update Flow input')
      return (data ?? []).length > 0
    },
    async completeInbound(userId, providerMessageId) {
      const { error } = await supabase
        .from('messages')
        .update({ delivery_status: 'completed', delivery_error: null })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
      if (error) throw new Error('Unable to complete Flow input')
    },
    async failInbound(userId, providerMessageId, code = 'flow_provider_failed') {
      const { error } = await supabase
        .from('messages')
        .update({ delivery_status: 'failed', delivery_error: { code } })
        .eq('user_id', userId)
        .eq('provider', 'mobile_flow')
        .eq('provider_message_id', providerMessageId)
        .eq('direction', 'in')
      if (error) throw new Error('Unable to mark Flow input failed')
    },
  }
}
