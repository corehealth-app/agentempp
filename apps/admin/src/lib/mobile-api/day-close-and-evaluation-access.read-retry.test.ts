/**
 * Characterization (review of 2026-10-05, LOW; declared as RC F in
 * docs/CALCULO-MPP.md §3a and as RC EA in docs/mobile/api-v1.md): how long a
 * FAILING read holds a request once the two switches of the test environment
 * are on.
 *
 * The database client (supabase-js / postgrest-js 2.105.1) repeats every GET
 * up to three times on a network error or on HTTP 503 or 520, waiting 1 s, 2 s
 * and 4 s, before it hands the error back. The on-request day close checks its
 * 4-second budget only between one day and the next, and neither module sets
 * a deadline on its reads. So one failing read keeps `GET /today`, `GET
 * /progress` or the onboarding completion waiting about 7 seconds. Nothing
 * here is a fix: the numbers are locked as they are, with the REAL client and
 * a fake `fetch`, so a change of the client's retry (or a deadline added
 * later) fails this file and the two declared lines get rewritten.
 *
 * The reviewer's inputs, exact: the day-close switch on for the staging ref
 * and HTTP 503 on `users`, on `user_progress` or on `meal_logs` (measured:
 * 7067, 7023 and 7051 ms, four requests each); the evaluation-access switch
 * on and `fetch failed` on the read of `user_profiles` or of
 * `entitlement_events` (about 7 s each). The clock here is fake: 7000 ms is
 * 1000 + 2000 + 4000.
 *
 * No network: every request goes to the fake `fetch` below. The project ref
 * is the real staging one (an identifier, not a credential) and is only
 * parsed.
 */
import { createClient } from '@supabase/supabase-js'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { closeOpenDaysOnRequest } from './day-close-on-request'
import { prepareEvaluationAccess } from './evaluation-access'

const USER = '0b9f6f0e-0000-4000-8000-00000000aaaa'
const ACTOR = '5c1d2e3f-0000-4000-8000-0000000000ac'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const STAGING_URL = `https://${STAGING_REF}.supabase.co`
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')

const DAY_CLOSE_ON = {
  MOBILE_DAY_CLOSE_FROM: '2026-09-22',
  MOBILE_DAY_CLOSE_PROJECT_REF: STAGING_REF,
  NEXT_PUBLIC_SUPABASE_URL: STAGING_URL,
}
const EVALUATION_ACCESS_ON = {
  MOBILE_EVALUATION_ACCESS_DAYS: '30',
  MOBILE_EVALUATION_ACCESS_PROJECT_REF: STAGING_REF,
  MOBILE_EVALUATION_ACCESS_ACTOR_ID: ACTOR,
  NEXT_PUBLIC_SUPABASE_URL: STAGING_URL,
}

type Failure = { status: number } | 'network'

/**
 * A database that answers every read with "nothing there" (and the account
 * and the profile with one plain row), except the one resource under test.
 */
function database(failing: string, failure: Failure) {
  const requests: Array<{ method: string; resource: string }> = []
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
  const fetchFake = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const resource = new URL(String(input)).pathname.split('/rest/v1/')[1] ?? ''
    requests.push({ method: init?.method ?? 'GET', resource })
    if (resource === failing) {
      if (failure === 'network') throw new TypeError('fetch failed')
      return json({ message: 'upstream' }, failure.status)
    }
    const single = (new Headers(init?.headers).get('accept') ?? '').includes('vnd.pgrst.object')
    if (resource === 'users') return json({ wpp: null, timezone: 'America/Sao_Paulo' })
    if (resource === 'user_profiles') {
      return json({ onboarding_completed: false, onboarding_completed_at: null })
    }
    if (resource === 'rpc/resolve_user_entitlement') {
      return json({ has_active_access: false, reason: 'no_entitlement' })
    }
    if (single) {
      return json({ code: 'PGRST116', message: 'no rows', details: '0 rows' }, 406)
    }
    return json([])
  }
  const client = createClient(STAGING_URL, 'service-role-test', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: fetchFake as typeof fetch },
  })
  return {
    client,
    requests,
    to: (resource: string) => requests.filter((r) => r.resource === resource),
  }
}

/** Runs `work` and reports, at each fake instant asked for, whether it has returned. */
async function timeline(work: () => Promise<unknown>, instants: number[]) {
  let returned = false
  const pending = work().then(() => {
    returned = true
  })
  const seen: Array<[number, boolean]> = []
  let at = 0
  for (const instant of instants) {
    await vi.advanceTimersByTimeAsync(instant - at)
    at = instant
    seen.push([instant, returned])
  }
  await pending
  return seen
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  vi.spyOn(console, 'error').mockImplementation(() => undefined)
  vi.spyOn(console, 'info').mockImplementation(() => undefined)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('on-request day close: a failing read holds the request for the client retries (declared, RC F)', () => {
  const context = (client: unknown) =>
    ({ requestId: 'request-read-retry', supabase: client, auth: { userId: USER } }) as never

  it.each([
    ['users'], // the hook's own read of the account
    ['user_progress'], // the first read of the sweep
    ['meal_logs'], // one of the four discovery reads
  ])('HTTP 503 on %s: four requests, and the hook returns only after 1 + 2 + 4 seconds', async (failing) => {
    const db = database(failing, { status: 503 })

    const seen = await timeline(
      () => closeOpenDaysOnRequest(context(db.client), { env: DAY_CLOSE_ON, now: NOW }),
      [0, 999, 1000, 2999, 3000, 6999, 7000],
    )

    expect(seen).toEqual([
      [0, false],
      [999, false],
      [1000, false],
      [2999, false],
      [3000, false],
      [6999, false],
      [7000, true],
    ])
    expect(db.to(failing)).toHaveLength(4)
    // Reads only: the failure ends the sweep, nothing is written.
    expect(db.requests.every((request) => request.method === 'GET')).toBe(true)
    expect(console.error).toHaveBeenCalledTimes(1)
    expect(console.error).toHaveBeenCalledWith('[mobile-api] day_close_failed', {
      request_id: 'request-read-retry',
      scope: 'mobile_api_v1',
      error_name: 'Error',
    })
  })

  it.each([
    ['a network error', 'network' as Failure],
    ['HTTP 520', { status: 520 } as Failure],
  ])('%s on the account read is retried the same way', async (_name, failure) => {
    const db = database('users', failure)
    const seen = await timeline(
      () => closeOpenDaysOnRequest(context(db.client), { env: DAY_CLOSE_ON, now: NOW }),
      [6999, 7000],
    )
    expect(seen).toEqual([
      [6999, false],
      [7000, true],
    ])
    expect(db.to('users')).toHaveLength(4)
  })

  it('HTTP 500 is not retried: one request, and the hook returns at once', async () => {
    const db = database('users', { status: 500 })
    const seen = await timeline(
      () => closeOpenDaysOnRequest(context(db.client), { env: DAY_CLOSE_ON, now: NOW }),
      [0],
    )
    expect(seen).toEqual([[0, true]])
    expect(db.to('users')).toHaveLength(1)
  })

  it('with the switch absent the same failing database is never asked', async () => {
    const db = database('users', { status: 503 })
    const seen = await timeline(
      () =>
        closeOpenDaysOnRequest(context(db.client), {
          env: { NEXT_PUBLIC_SUPABASE_URL: STAGING_URL },
          now: NOW,
        }),
      [0],
    )
    expect(seen).toEqual([[0, true]])
    expect(db.requests).toEqual([])
  })
})

describe('evaluation access: a failing read holds the onboarding completion for the client retries (declared, RC EA)', () => {
  const context = (client: unknown) =>
    ({ requestId: 'request-read-retry', supabase: client, auth: { userId: USER } }) as never

  it('`fetch failed` on user_profiles (asked BEFORE the completion): about 7 s, then no grant and no other query', async () => {
    const db = database('user_profiles', 'network')
    let grant: (() => Promise<void>) | undefined

    const seen = await timeline(async () => {
      grant = await prepareEvaluationAccess(context(db.client), { env: EVALUATION_ACCESS_ON })
    }, [6999, 7000])
    await grant?.()

    expect(seen).toEqual([
      [6999, false],
      [7000, true],
    ])
    expect(db.requests.map((request) => request.resource)).toEqual([
      'user_profiles',
      'user_profiles',
      'user_profiles',
      'user_profiles',
    ])
    expect(console.error).toHaveBeenCalledWith('[mobile-api] evaluation_access_failed', {
      request_id: 'request-read-retry',
      scope: 'mobile_api_v1',
      // The client hands a network error back as a result, not as a throw.
      stage: 'profile_lookup',
      error_name: 'Error',
    })
  })

  it('`fetch failed` on entitlement_events (asked AFTER the completion): about 7 s, then no grant', async () => {
    const db = database('entitlement_events', 'network')
    const grant = await prepareEvaluationAccess(context(db.client), { env: EVALUATION_ACCESS_ON })

    const seen = await timeline(() => grant(), [6999, 7000])

    expect(seen).toEqual([
      [6999, false],
      [7000, true],
    ])
    expect(db.to('entitlement_events')).toHaveLength(4)
    // The resolver (a POST) was asked once, in parallel; the grant never was.
    expect(db.to('rpc/resolve_user_entitlement')).toHaveLength(1)
    expect(db.to('rpc/apply_entitlement_event')).toEqual([])
    expect(console.error).toHaveBeenCalledTimes(1)
  })

  it('a failing POST is not retried: `fetch failed` on the resolver returns at once', async () => {
    const db = database('rpc/resolve_user_entitlement', 'network')
    const grant = await prepareEvaluationAccess(context(db.client), { env: EVALUATION_ACCESS_ON })
    const seen = await timeline(() => grant(), [0])
    expect(seen).toEqual([[0, true]])
    expect(db.to('rpc/resolve_user_entitlement')).toHaveLength(1)
    expect(db.to('rpc/apply_entitlement_event')).toEqual([])
  })

  it('with the switch absent the same failing database is never asked', async () => {
    const db = database('user_profiles', 'network')
    const grant = await prepareEvaluationAccess(context(db.client), {
      env: { NEXT_PUBLIC_SUPABASE_URL: STAGING_URL },
    })
    await grant()
    expect(db.requests).toEqual([])
  })
})
