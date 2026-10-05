/**
 * Automatic evaluation access for accounts created on the test environment.
 *
 * WHY. The app has no purchase screen, and an account without an entitlement
 * gets 402 on every route outside account, profile, onboarding, entitlements,
 * persona, devices and notification preferences. Until now each evaluator had
 * to wait for an operator to grant a trial by SQL. With the switch on, the
 * account's FIRST onboarding completion grants a manual trial of N days
 * through the domain's own RPC, with the same fields the operator's grants on
 * the test environment carry.
 *
 * OFF BY DEFAULT, and four locks must all hold:
 *  a. `MOBILE_EVALUATION_ACCESS_DAYS` is an integer from 1 to 90. Absent,
 *     empty or anything else = off, with not a single query;
 *  b. the project ref of the configured database URL is listed in
 *     `MOBILE_EVALUATION_ACCESS_PROJECT_REF`, and is never the production
 *     ref, which is refused here in code whatever the variables say;
 *  c. `MOBILE_EVALUATION_ACCESS_ACTOR_ID` is a uuid: the audit actor the
 *     domain requires on a manual entitlement;
 *  d. the account has no entitlement event and no entitlement of any kind
 *     yet. A lapsed or blocked access is never renewed from here, and an
 *     account that already has access is left alone.
 *
 * ONCE. Only a first completion is eligible: the profile is read BEFORE the
 * completion is recorded and must have no completion time yet, so a retry, a
 * replay or a later re-acceptance of new documents grants nothing, and
 * neither does an account that completed before the switch was on. The event
 * id is derived from the user id, so two first completions arriving together
 * end as one grant (the second is answered `duplicate` by the database).
 *
 * It only calls the database it was handed, and sends nothing. A failure is
 * logged without personal data and the onboarding response goes on unchanged:
 * the account exists and an operator can still grant by hand.
 */
import type { MobileRouteContext } from './route'
import { safeUnexpectedErrorName } from './route'

export const EVALUATION_ACCESS_DAYS_ENV = 'MOBILE_EVALUATION_ACCESS_DAYS'
export const EVALUATION_ACCESS_PROJECT_REF_ENV = 'MOBILE_EVALUATION_ACCESS_PROJECT_REF'
export const EVALUATION_ACCESS_ACTOR_ID_ENV = 'MOBILE_EVALUATION_ACCESS_ACTOR_ID'

/** The production database. Never granted from a request, whatever is configured. */
const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'

const MAX_DAYS = 90
const DAY_MS = 86_400_000

/**
 * What is written. Entitlement key, source, status, plan and environment are
 * those of the operator's active manual trials on the test environment (read
 * there on 2026-10-05: columns and enums only), and the event type is the one
 * three of those four carry (the fourth says `grant`). The reason code is
 * what tells this automatic grant apart from them.
 */
const GRANT = {
  entitlementKey: 'bodyflow_full',
  source: 'manual',
  eventType: 'manual.qa.grant',
  status: 'active',
  plan: 'trial',
  environment: 'sandbox',
  reasonCode: 'closed_evaluation_auto',
} as const

/** One per account for ever: the database keeps (source, source_reference, key) unique. */
function sourceReference(userId: string): string {
  return `closed-evaluation-auto:${userId}`
}

/** One per account for ever: the database keeps (source, provider_event_id) unique. */
function eventId(userId: string): string {
  return `${sourceReference(userId)}:grant`
}

type Environment = Record<string, string | undefined>

export interface EvaluationAccessConfig {
  days: number
  actorId: string
}

/** Runs after the completion was recorded. Never throws. */
export type EvaluationAccessGrant = () => Promise<void>

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const NIL_UUID = '00000000-0000-0000-0000-000000000000'

/**
 * The project ref of a hosted database URL (`https://<ref>.supabase.co`), or
 * null. The same rule as the on-request day close; it is repeated here, not
 * imported, so this module reaches nothing but the route wrapper (a test
 * keeps the two in agreement).
 */
export function projectRefFromUrl(url: string | undefined): string | null {
  if (!url) return null
  try {
    const { protocol, hostname } = new URL(url)
    if (protocol !== 'https:') return null
    const match = hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)
    return match?.[1] ?? null
  } catch {
    return null
  }
}

/** Locks a, b and c, from the environment alone. Null = off. */
export function resolveEvaluationAccess(env: Environment): EvaluationAccessConfig | null {
  // Plain decimal digits only: "30.0", "+30", "1e1" and "030" are a typo, not a number of days.
  const rawDays = (env[EVALUATION_ACCESS_DAYS_ENV] ?? '').trim()
  if (!/^[1-9]\d?$/.test(rawDays)) return null
  const days = Number(rawDays)
  if (days > MAX_DAYS) return null

  const allowedRefs = (env[EVALUATION_ACCESS_PROJECT_REF_ENV] ?? '')
    .split(/[\s,]+/)
    .map((ref) => ref.trim())
    .filter(Boolean)
  const ref = projectRefFromUrl(env.NEXT_PUBLIC_SUPABASE_URL)
  if (ref === null || ref === PRODUCTION_PROJECT_REF) return null
  // Listing the production ref is a configuration mistake: nothing is trusted.
  if (allowedRefs.includes(PRODUCTION_PROJECT_REF)) return null
  if (!allowedRefs.includes(ref)) return null

  const actorId = (env[EVALUATION_ACCESS_ACTOR_ID_ENV] ?? '').trim().toLowerCase()
  // The all-zero uuid names nobody, and the audit column exists to name someone.
  if (!UUID_PATTERN.test(actorId) || actorId === NIL_UUID) return null

  return { days, actorId }
}

function runtimeEnvironment(): Environment {
  return {
    [EVALUATION_ACCESS_DAYS_ENV]: process.env.MOBILE_EVALUATION_ACCESS_DAYS,
    [EVALUATION_ACCESS_PROJECT_REF_ENV]: process.env.MOBILE_EVALUATION_ACCESS_PROJECT_REF,
    [EVALUATION_ACCESS_ACTOR_ID_ENV]: process.env.MOBILE_EVALUATION_ACCESS_ACTOR_ID,
    // The same static expression the service client factory reads
    // (../supabase/server), so the lock looks at the URL the client was built
    // with even where the bundler inlines it.
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  }
}

interface QueryResult {
  data: unknown
  error: unknown
}

interface UntypedQuery extends PromiseLike<QueryResult> {
  select(columns: string): UntypedQuery
  eq(column: string, value: unknown): UntypedQuery
  limit(count: number): UntypedQuery
  maybeSingle(): PromiseLike<QueryResult>
}

// The generated RPC types do not keep nullable function arguments (the grace
// expiry is null here), so the three calls go through this narrow shape.
interface UntypedClient {
  from(table: string): UntypedQuery
  rpc(functionName: string, params: Record<string, unknown>): PromiseLike<QueryResult>
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

/** The reason is one of this module's own words: no database text reaches the log. */
class EvaluationAccessError extends Error {
  constructor(readonly stage: string) {
    super(stage)
  }
}

const NO_GRANT: EvaluationAccessGrant = async () => undefined

type GrantContext = Pick<MobileRouteContext, 'auth' | 'requestId' | 'supabase'>

function logFailure(context: GrantContext, error: unknown): void {
  console.error('[mobile-api] evaluation_access_failed', {
    request_id: context.requestId,
    scope: 'mobile_api_v1',
    stage: error instanceof EvaluationAccessError ? error.stage : 'unexpected',
    error_name: safeUnexpectedErrorName(error),
  })
}

/**
 * Lock d and the grant itself. `now` is taken after the completion was
 * recorded: access starts then and lasts `days` × 24 hours.
 */
async function grantOnce(
  client: UntypedClient,
  context: GrantContext,
  config: EvaluationAccessConfig,
  now: Date,
): Promise<void> {
  const userId = context.auth.userId
  const nowIso = now.toISOString()

  const [events, decision] = await Promise.all([
    client.from('entitlement_events').select('id').eq('user_id', userId).limit(1),
    client.rpc('resolve_user_entitlement', {
      p_user_id: userId,
      p_entitlement_key: GRANT.entitlementKey,
      p_now: nowIso,
    }),
  ])
  if (events.error || !Array.isArray(events.data)) {
    throw new EvaluationAccessError('event_lookup')
  }
  if (decision.error || !isRecord(decision.data)) {
    throw new EvaluationAccessError('entitlement_lookup')
  }
  // Lock d. The resolver's `no_entitlement` also rules out what the event
  // ledger does not show: a subscription from the older billing path.
  const untouched =
    events.data.length === 0 &&
    decision.data.has_active_access === false &&
    decision.data.reason === 'no_entitlement'
  if (!untouched) {
    console.info('[mobile-api] evaluation_access', {
      request_id: context.requestId,
      scope: 'mobile_api_v1',
      result: 'left_alone',
    })
    return
  }

  const applied = await client.rpc('apply_entitlement_event', {
    p_provider_event_id: eventId(userId),
    p_event_type: GRANT.eventType,
    p_user_id: userId,
    p_entitlement_key: GRANT.entitlementKey,
    p_source: GRANT.source,
    p_source_reference: sourceReference(userId),
    p_status: GRANT.status,
    p_plan: GRANT.plan,
    p_environment: GRANT.environment,
    p_occurred_at: nowIso,
    p_starts_at: nowIso,
    p_access_expires_at: new Date(now.getTime() + config.days * DAY_MS).toISOString(),
    p_grace_expires_at: null,
    p_cancel_at_period_end: false,
    p_reason_code: GRANT.reasonCode,
    p_actor_id: config.actorId,
  })
  const result = isRecord(applied.data) ? applied.data.result : undefined
  // `duplicate`: another request of the same account granted a moment ago.
  if (applied.error || (result !== 'applied' && result !== 'duplicate')) {
    throw new EvaluationAccessError('grant')
  }
  console.info('[mobile-api] evaluation_access', {
    request_id: context.requestId,
    scope: 'mobile_api_v1',
    result,
    days: config.days,
  })
}

/**
 * Call BEFORE the onboarding completion is recorded, and run what it returns
 * right after the completion succeeded. With the switch off it reads nothing
 * and returns a function that does nothing.
 */
export async function prepareEvaluationAccess(
  context: GrantContext,
  options: { env?: Environment; now?: () => Date } = {},
): Promise<EvaluationAccessGrant> {
  const config = resolveEvaluationAccess(options.env ?? runtimeEnvironment())
  if (config === null) return NO_GRANT

  const client = context.supabase as unknown as UntypedClient
  const userId = context.auth.userId
  try {
    // The id goes into the event id and the source reference, which the
    // domain restricts to a small alphabet.
    if (!UUID_PATTERN.test(userId)) throw new EvaluationAccessError('account')

    const profile = await client
      .from('user_profiles')
      .select('onboarding_completed_at')
      .eq('user_id', userId)
      .maybeSingle()
    if (profile.error) throw new EvaluationAccessError('profile_lookup')
    // Only a first completion is eligible; `null` is the same test the
    // completion RPC uses to tell a first completion from a re-acceptance.
    if (!isRecord(profile.data) || profile.data.onboarding_completed_at !== null) return NO_GRANT
  } catch (error) {
    logFailure(context, error)
    return NO_GRANT
  }

  return async () => {
    try {
      await grantOnce(client, context, config, (options.now ?? (() => new Date()))())
    } catch (error) {
      logFailure(context, error)
    }
  }
}
