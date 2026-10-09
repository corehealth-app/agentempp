/**
 * On-request day close for app accounts on the test environment.
 *
 * WHY. There the worker serves media processing only, so no day is ever
 * closed and block, streak, XP, level and medals never move for an app
 * account. With the switch on, GET /today, GET /progress and the authenticated
 * whole-message Flow day-status adapter first close the account's past open
 * days with the shared close function, then read. The Flow adapter runs only
 * after the subscription gate; ordinary chat and completed replay do not call
 * it. Production needs none
 * of this: its closer already covers app accounts.
 *
 * OFF BY DEFAULT, and three locks must all hold before anything is read:
 *  1. `MOBILE_DAY_CLOSE_FROM` is set to a date (the first local date that may
 *     be closed). Absent, empty or malformed = off, with not a single query;
 *  2. the project ref of the configured database URL is listed in
 *     `MOBILE_DAY_CLOSE_PROJECT_REF`, and is never the production ref, which
 *     is refused here in code whatever the variables say;
 *  3. the account has no WhatsApp number and has a time zone.
 *
 * It only writes to the database it was handed. It sends nothing. A failure
 * is logged without personal data and the request goes on: these numbers
 * being one request late is better than the screen not loading. (The request
 * goes on LATE when the failure is a read the client retries: see
 * `REQUEST_LIMITS`.)
 */
import { closePastOpenDays } from '@mpp/agent'
import type { MobileRouteContext } from './route'
import { safeUnexpectedErrorName } from './route'

export const DAY_CLOSE_FROM_ENV = 'MOBILE_DAY_CLOSE_FROM'
export const DAY_CLOSE_PROJECT_REF_ENV = 'MOBILE_DAY_CLOSE_PROJECT_REF'

/** The production database. Never closed from a request, whatever is configured. */
const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'

/**
 * Budget of one request: a first visit after several days away closes the
 * oldest three and leaves the rest to the next request, in order.
 *
 * NOT A DEADLINE. The sweep checks it between one day and the next only: a
 * day being closed finishes, and no read is cut short. The database client
 * repeats a GET three times (after 1, 2 and 4 seconds) on a network error or
 * HTTP 503/520, so one failing read keeps the request waiting about 7 seconds
 * before the failure is logged below and the request goes on. Declared in
 * docs/CALCULO-MPP.md §3a (RC F) and locked, as it is, in
 * day-close-and-evaluation-access.read-retry.test.ts.
 */
const REQUEST_LIMITS = { maxDays: 3, maxMs: 4000 } as const

type Environment = Record<string, string | undefined>

/** The project ref of a hosted database URL (`https://<ref>.supabase.co`), or null. */
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

/** A real calendar date written as YYYY-MM-DD ("2026-02-31" is not one). */
function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const parsed = new Date(`${value}T00:00:00.000Z`)
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value
}

/**
 * Locks 1 and 2, from the environment alone. Returns the first local date
 * that may be closed, or null when the on-request close is off.
 */
export function resolveDayCloseStart(env: Environment): string | null {
  const from = (env[DAY_CLOSE_FROM_ENV] ?? '').trim()
  if (!isCalendarDate(from)) return null

  const allowedRefs = (env[DAY_CLOSE_PROJECT_REF_ENV] ?? '')
    .split(/[\s,]+/)
    .map((ref) => ref.trim())
    .filter(Boolean)
  const ref = projectRefFromUrl(env.NEXT_PUBLIC_SUPABASE_URL)
  if (ref === null || ref === PRODUCTION_PROJECT_REF) return null
  // Listing the production ref is a configuration mistake: nothing is trusted.
  if (allowedRefs.includes(PRODUCTION_PROJECT_REF)) return null
  if (!allowedRefs.includes(ref)) return null
  return from
}

function runtimeEnvironment(): Environment {
  return {
    [DAY_CLOSE_FROM_ENV]: process.env.MOBILE_DAY_CLOSE_FROM,
    [DAY_CLOSE_PROJECT_REF_ENV]: process.env.MOBILE_DAY_CLOSE_PROJECT_REF,
    // The same static expression the service client factory reads
    // (../supabase/server), so the lock looks at the URL the client was built
    // with even where the bundler inlines it.
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  }
}

export async function closeOpenDaysOnRequest(
  context: Pick<MobileRouteContext, 'auth' | 'requestId' | 'supabase'>,
  options: { env?: Environment; now?: Date } = {},
): Promise<void> {
  const from = resolveDayCloseStart(options.env ?? runtimeEnvironment())
  if (from === null) return

  try {
    const userId = context.auth.userId
    const { data: account, error } = await context.supabase
      .from('users')
      .select('wpp, timezone')
      .eq('id', userId)
      .maybeSingle()
    if (error) throw new Error('account lookup failed')
    // Lock 3. A WhatsApp account is closed by the production closer, and an
    // account without a time zone has no "local date" to close.
    if (!account || account.wpp !== null || !account.timezone) return

    const result = await closePastOpenDays(context.supabase, {
      userId,
      timezone: account.timezone,
      now: options.now ?? new Date(),
      from,
      limits: REQUEST_LIMITS,
      block7700Policy: 'flow-recomposition-v1',
      finalizationFence: 'mobile-current-v1',
    })
    const closed = result.days.filter((day) => day.closed).length
    if (closed > 0 || result.pendingDates.length > 0 || result.streakReset?.applied) {
      console.info('[mobile-api] day_close', {
        request_id: context.requestId,
        scope: 'mobile_api_v1',
        closed,
        pending: result.pendingDates.length,
        left_open_behind_frontier: result.staleOpenDates.length,
        streak_reset: result.streakReset?.applied === true,
      })
    }
  } catch (error) {
    console.error('[mobile-api] day_close_failed', {
      request_id: context.requestId,
      scope: 'mobile_api_v1',
      error_name: safeUnexpectedErrorName(error),
    })
  }
}
