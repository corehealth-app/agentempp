import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import type { MobileRouteRuntime } from './route'
import { createWorkoutStrengthClarificationRoutes } from './workout-strength-clarification-route-handlers'

const owner = 'a1000000-0000-4000-8000-000000000001'
const authID = 'a1000000-0000-4000-8000-000000000002'
const workout = 'b2000000-0000-4000-8000-000000000001'
const lifecycle = 'c3000000-0000-4000-8000-000000000001'
const question = 'd4000000-0000-4000-8000-000000000001'
const key = 'e5000000-0000-4000-8000-000000000001'
const other = 'f6000000-0000-4000-8000-000000000001'
const acceptedAt = '2026-10-21T01:02:03.123456Z'
const auth = { userId: owner, authUserId: authID } as MobileAuthContext
const params = { params: Promise.resolve({ id: workout }) }
const body = {
  expected_lifecycle_key: lifecycle,
  expected_fact_revision: 0,
  question_key: question,
  answer: 'yes',
}
function receipt() {
  return {
    ownerID: owner,
    workoutLogID: workout,
    questionKey: question,
    answer: 'yes',
    operationKey: 'wsa1:winning-a',
    acceptedAt,
  }
}
function available(status = 'unanswered') {
  return {
    status: 'available',
    workoutLogID: workout,
    lifecycleKey: lifecycle,
    factRevision: status === 'answered' ? 1 : 0,
    clarification:
      status === 'answered'
        ? { status, receipt: receipt() }
        : status === 'unanswered'
          ? { status, questionKey: question }
          : { status },
  }
}
function request(method: 'GET' | 'POST', input: unknown = body, idempotency: string | null = key) {
  return new Request(
    `https://app.invalid/api/mobile/v1/workouts/${workout}/strength-clarification`,
    {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(idempotency === null ? {} : { 'Idempotency-Key': idempotency }),
      },
      ...(method === 'POST' ? { body: JSON.stringify(input) } : {}),
    },
  )
}
function setup(
  data: unknown = available(),
  options: { enabled?: boolean; authStatus?: number; entitlementStatus?: number } = {},
) {
  const events: string[] = []
  const rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => ({
    data,
    error: null as unknown,
  }))
  const client = {
    get rpc() {
      events.push('question-port')
      return rpc
    },
  } as unknown as ServiceClient
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => {
      events.push('auth-client')
      return client
    },
    createRequestId: () => 'synthetic-clarification-request',
    authenticate: async () => {
      events.push('auth')
      if (options.authStatus) throw new MobileApiError(options.authStatus, 'auth_denied', 'Denied')
      return auth
    },
    authorizeEntitlement: async () => {
      events.push('entitlement')
      if (options.entitlementStatus)
        throw new MobileApiError(options.entitlementStatus, 'subscription_required', 'Denied')
    },
  }
  return {
    rpc,
    events,
    routes: createWorkoutStrengthClarificationRoutes(runtime, () => {
      events.push('flag')
      return options.enabled ?? true
    }),
  }
}
afterEach(() => vi.restoreAllMocks())

describe('current workout strength clarification HTTP', () => {
  it('GET uses patient identity, returns only public fields and preserves literal UTC6', async () => {
    const { routes, rpc } = setup(available('answered'))
    const response = await routes.GET(request('GET'), params)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      data: {
        status: 'answered',
        workout_id: workout,
        lifecycle_key: lifecycle,
        fact_revision: 1,
        question_key: question,
        receipt: { answer: 'yes', accepted_at: acceptedAt },
      },
      meta: { api_version: 'v1', request_id: 'synthetic-clarification-request' },
    })
    expect(rpc.mock.calls).toEqual([
      [
        'get_mobile_workout_strength_clarification',
        { p_user_id: owner, p_workout_log_id: workout },
      ],
    ])
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('Vary')).toBe('Authorization')
  })
  it.each([
    'unanswered',
    'not_applicable',
  ])('GET projects %s without private keys', async (status) => {
    const { routes } = setup(available(status))
    const response = await routes.GET(request('GET'), params)
    expect((await response.json()).data).toEqual({
      status,
      workout_id: workout,
      lifecycle_key: lifecycle,
      fact_revision: 0,
      ...(status === 'unanswered' ? { question_key: question } : {}),
    })
  })
  it('keeps provenance gap unavailable without a fabricated tuple', async () => {
    const data = { status: 'unavailable', reason: 'provenance_gap' }
    const { routes } = setup(data)
    expect((await (await routes.GET(request('GET'), params)).json()).data).toEqual(data)
  })
  it.each([
    'stale_lifecycle',
    'stale_workout',
  ])('GET keeps %s neutral with no identity or question', async (reason) => {
    const { routes, rpc } = setup({ status: 'forbidden', reason })
    const response = await routes.GET(request('GET'), params)
    expect(response.status).toBe(409)
    const output = await response.json()
    expect(output.error.code).toBe('workout_strength_unavailable')
    expect(output.error.details).toBeUndefined()
    expect(output.data).toBeUndefined()
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    { ...available(), workoutLogID: other },
    { ...available(), factRevision: 1 },
    { ...available(), raw_fact: {} },
  ])('GET malformed/foreign state stays an error, never unavailable: %j', async (data) => {
    const { routes, rpc } = setup(data)
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const response = await routes.GET(request('GET'), params)
    expect(response.status).toBe(500)
    expect((await response.json()).error.code).toBe('internal_error')
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'GET',
    'POST',
  ] as const)('OFF prevents %s question port access after auth and entitlement', async (method) => {
    const { routes, events, rpc } = setup(null, { enabled: false })
    const response = await routes[method](request(method), params)
    expect(response.status).toBe(503)
    expect((await response.json()).error.code).toBe('workout_strength_clarification_unavailable')
    expect(events).toEqual(['auth-client', 'auth', 'entitlement', 'flag'])
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([401, 403, 402])('guard %s precedes handler and all question I/O', async (status) => {
    for (const method of ['GET', 'POST'] as const) {
      const { routes, events, rpc } = setup(
        null,
        status === 402 ? { entitlementStatus: status } : { authStatus: status },
      )
      expect((await routes[method](request(method), params)).status).toBe(status)
      expect(events).not.toContain('flag')
      expect(rpc).not.toHaveBeenCalled()
    }
  })
  it('POST calls only live S9 wrapper; revision0 retries keep original tuple and return official revision1', async () => {
    const { routes, rpc } = setup({ status: 'reuse_existing', receipt: receipt() })
    for (const header of [key, key.toUpperCase()]) {
      const response = await routes.POST(
        request(
          'POST',
          {
            ...body,
            expected_lifecycle_key: lifecycle.toUpperCase(),
            question_key: question.toUpperCase(),
          },
          header,
        ),
        { params: Promise.resolve({ id: workout.toUpperCase() }) },
      )
      expect(response.status).toBe(200)
      expect((await response.json()).data).toEqual({
        status: 'answered',
        workout_id: workout,
        lifecycle_key: lifecycle,
        fact_revision: 1,
        question_key: question,
        receipt: { answer: 'yes', accepted_at: acceptedAt },
      })
    }
    const args = {
      p_user_id: owner,
      p_expected_lifecycle_key: lifecycle,
      p_workout_log_id: workout,
      p_expected_fact_revision: 0,
      p_question_key: question,
      p_answer: 'yes',
      p_operation_key: `wsa1:${key}`,
    }
    expect(rpc.mock.calls).toEqual([
      ['answer_mobile_workout_strength_clarification', args],
      ['answer_mobile_workout_strength_clarification', args],
    ])
  })
  it('never serves an HTTP success cache after reset or SQL failure', async () => {
    const { routes, rpc } = setup({ status: 'accepted', receipt: receipt() })
    expect((await routes.POST(request('POST'), params)).status).toBe(200)
    rpc.mockResolvedValueOnce({
      data: { status: 'forbidden', reason: 'stale_lifecycle' },
      error: null,
    })
    expect((await routes.POST(request('POST'), params)).status).toBe(409)
    rpc.mockResolvedValueOnce({
      data: null,
      error: { code: 'P0002', message: 'private patient detail' },
    })
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const response = await routes.POST(request('POST'), params)
    expect(response.status).toBe(500)
    expect(JSON.stringify(await response.json())).not.toContain('private patient detail')
    expect(rpc).toHaveBeenCalledTimes(3)
  })
  it('a failed GET following POST success never issues another write', async () => {
    const { routes, rpc } = setup({ status: 'accepted', receipt: receipt() })
    expect((await routes.POST(request('POST'), params)).status).toBe(200)
    rpc.mockResolvedValueOnce({ data: null, error: new Error('read failed') })
    vi.spyOn(console, 'error').mockImplementation(() => {})
    expect((await routes.GET(request('GET'), params)).status).toBe(500)
    rpc.mockResolvedValueOnce({ data: available('answered'), error: null })
    expect((await routes.GET(request('GET'), params)).status).toBe(200)
    expect(rpc.mock.calls.map((call) => call[0])).toEqual([
      'answer_mobile_workout_strength_clarification',
      'get_mobile_workout_strength_clarification',
      'get_mobile_workout_strength_clarification',
    ])
  })
  it.each([
    ['forbidden', 'mixed_owner', 'workout_strength_unavailable'],
    ['forbidden', 'stale_workout', 'workout_strength_unavailable'],
    ['forbidden', 'stale_lifecycle', 'workout_strength_unavailable'],
    ['conflict', 'stale_fact', 'workout_strength_answer_conflict'],
    ['conflict', 'answer_already_differs', 'workout_strength_answer_conflict'],
    ['conflict', 'operation_content_conflict', 'workout_strength_answer_conflict'],
    ['not_available', 'not_unrecognized', 'workout_strength_answer_conflict'],
  ])('maps %s/%s to neutral conflict without leaking tuple', async (status, reason, code) => {
    const { routes, rpc } = setup({ status, reason })
    const response = await routes.POST(request('POST'), params)
    expect(response.status).toBe(409)
    const output = await response.json()
    expect(output.error.code).toBe(code)
    expect(output.error.details).toBeUndefined()
    expect(JSON.stringify(output)).not.toContain(owner)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    'not-a-uuid',
    'wsa1:anything',
    `${key},${key}`,
  ])('rejects invalid/missing header %s before RPC', async (header) => {
    const { routes, rpc } = setup()
    const response = await routes.POST(request('POST', body, header), params)
    expect(response.status).toBe(400)
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    { ...body, owner_id: owner },
    { ...body, operation_key: key },
    { ...body, workout_id: workout },
    { ...body, expected_fact_revision: '0' },
    { ...body, expected_fact_revision: -1 },
    { ...body, expected_fact_revision: 0.5 },
    { ...body, expected_fact_revision: 2147483648 },
    { ...body, question_key: null },
    { ...body, expected_lifecycle_key: 'bad' },
    { ...body, answer: true },
    { ...body, answer: 'YES' },
    {},
    null,
  ])('rejects invalid or extra body before RPC: %j', async (input) => {
    const { routes, rpc } = setup()
    expect((await routes.POST(request('POST', input), params)).status).toBe(422)
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    `{"answer":"no",${JSON.stringify(body).slice(1)}`,
    `{"ans\\u0077er":"no",${JSON.stringify(body).slice(1)}`,
  ])('rejects literal and escaped duplicate keys before RPC', async (text) => {
    const { routes, rpc } = setup()
    const req = new Request('https://app.invalid', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
      body: text,
    })
    expect((await routes.POST(req, params)).status).toBe(400)
    expect(rpc).not.toHaveBeenCalled()
  })
  it('enforces bounded body and JSON content type before RPC', async () => {
    for (const [text, contentType, status] of [
      [JSON.stringify(body) + ' '.repeat(2048), 'application/json', 413],
      [JSON.stringify(body), 'text/plain', 415],
    ] as const) {
      const { routes, rpc } = setup()
      const req = new Request('https://app.invalid', {
        method: 'POST',
        headers: { 'Content-Type': contentType, 'Idempotency-Key': key },
        body: text,
      })
      expect((await routes.POST(req, params)).status).toBe(status)
      expect(rpc).not.toHaveBeenCalled()
    }
  })
  it.each([
    'GET',
    'POST',
  ] as const)('refuses invalid %s resource UUID before RPC', async (method) => {
    const { routes, rpc } = setup()
    expect(
      (
        await routes[method](request(method), {
          params: Promise.resolve({ id: 'pending-not-workout' }),
        })
      ).status,
    ).toBe(422)
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    { status: 'accepted', receipt: { ...receipt(), ownerID: other } },
    { status: 'accepted', receipt: { ...receipt(), questionKey: other } },
    { status: 'accepted', receipt: { ...receipt(), answer: 'no' } },
    { status: 'accepted', receipt: { ...receipt(), acceptedAt: '2026-02-29T01:02:03.123456Z' } },
    { status: 'accepted', receipt: receipt(), raw_fact: {} },
    null,
  ])('invalid SQL success stays 500, without fallback/unavailable: %j', async (data) => {
    const { routes, rpc } = setup(data)
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const response = await routes.POST(request('POST'), params)
    expect(response.status).toBe(500)
    expect((await response.json()).error.code).toBe('internal_error')
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
