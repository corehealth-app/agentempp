import type { Database } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import { createConfirmedMealRoutes } from './confirmed-meal-route-handlers'
import type { MobileRouteRuntime } from './route'
import { anchorID, auth, fixture, now, owner, snapshotID } from './testing/confirmed-meal-fixtures'
import { createWorkoutStrengthClarificationRoutes } from './workout-strength-clarification-route-handlers'

const pendingID = 'c1110000-0000-4000-8000-000000000010'
const admissionID = 'c1110000-0000-4000-8000-000000000011'
const lifecycleID = 'c1110000-0000-4000-8000-000000000012'
const provider = 'mobile/own source:with literal spaces'

function saved(kind: 'meal' | 'workout') {
  return {
    schema: 'registration.feedback.v1',
    registration_id: pendingID,
    kind,
    locale: 'pt-BR',
    meal_totals: kind === 'meal' ? { kcal: 155, protein_g: 23, carbs_g: 4.5, fat_g: 4.75 } : null,
    day: null,
    lines: [
      ...(kind === 'meal'
        ? [{ key: 'meal_totals', text: '155 kcal da confirmação original.' }]
        : []),
      { key: 'day_unavailable', text: 'Os dados deste dia estão indisponíveis.' },
    ],
    food_comment: null,
    incentive: 'Incentivo salvo uma única vez.',
  }
}

function setup(
  kind: 'meal' | 'workout' = 'meal',
  options: {
    include?: boolean
    enabled?: boolean
    ambiguous?: boolean
    sourceMissing?: boolean
    mixedMealTypes?: boolean
    edited?: boolean
    unavailable?: boolean
    forbidden?: boolean
    protectedForbidden?: boolean
    legacy?: boolean
    failPending?: boolean
    failReceipt?: boolean
    invalidReceipt?: boolean
    protectedMismatch?: boolean
    candidateChange?: Record<string, unknown>
  } = {},
) {
  const base = fixture()
  for (const row of base.meal_logs) {
    row.raw_provider_message_id = provider
    row.meal_type = 'almoco'
  }
  if (options.sourceMissing) base.meal_logs[0].raw_provider_message_id = null
  if (options.mixedMealTypes) base.meal_logs[1].meal_type = 'jantar'
  if (options.edited) {
    base.meal_logs[0].food_name = 'nome corrigido depois da confirmação'
    base.meal_logs[0].quantity_g = 170
    base.meal_logs[0].kcal = 900
    base.meal_logs[0].id = 'c1110000-0000-4000-8000-000000000020'
  }
  const recordID = kind === 'meal' ? base.meal_logs[0].id : anchorID
  const proposal =
    kind === 'meal'
      ? {
          kind,
          mealType: 'almoco',
          registration_origin: 'mobile_app',
          source_provider_message_id: provider,
          source_local_date: base.daily_snapshots[0].date,
        }
      : {
          kind,
          workoutType: 'Natação',
          source_provider_message_id: provider,
          // Preview date can differ from the official writer date; never bind by this date.
          source_local_date: '2026-10-08',
        }
  const pending: Record<string, unknown> = {
    id: pendingID,
    user_id: owner,
    status: 'confirmed',
    proposal,
    workout_ui_admission_id: kind === 'workout' && !options.legacy ? admissionID : null,
    ...options.candidateChange,
  }
  const rows: Record<string, Record<string, unknown>[]> = {
    ...base,
    workout_logs: [
      {
        id: anchorID,
        user_id: owner,
        snapshot_id: snapshotID,
        raw_provider_message_id: provider,
        workout_type: 'Natação',
      },
    ],
    pending_registrations: options.ambiguous
      ? [pending, { ...pending, id: admissionID }]
      : [pending],
  }
  const clarification = options.unavailable
    ? { status: 'unavailable', reason: 'provenance_gap' }
    : {
        status: 'not_applicable',
        workout_id: anchorID,
        lifecycle_key: lifecycleID,
        fact_revision: 0,
      }
  const requests: { name: string; method: string; query: URLSearchParams; body: unknown }[] = []
  const client = createClient<Database>('https://history-feedback.invalid', 'synthetic-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const url = new URL(String(input)),
          method = init?.method ?? 'GET'
        const name = url.pathname.split('/').at(-1) ?? ''
        const body = typeof init?.body === 'string' ? JSON.parse(init.body) : null
        requests.push({ name, method, query: url.searchParams, body })
        if (url.origin !== 'https://history-feedback.invalid') throw new Error('Unexpected origin')
        if (url.pathname.includes('/rpc/')) {
          if (name === 'get_mobile_workout_strength_clarification')
            return Response.json(
              options.forbidden
                ? { status: 'forbidden', reason: 'stale_lifecycle' }
                : options.unavailable
                  ? clarification
                  : {
                      status: 'available',
                      workoutLogID: anchorID,
                      lifecycleKey: lifecycleID,
                      factRevision: 0,
                      clarification: { status: 'not_applicable' },
                    },
            )
          if (name === 'get_mobile_workout_registration')
            return Response.json(
              options.protectedForbidden
                ? { status: 'forbidden', reason: 'stale_epoch' }
                : {
                    status: 'available',
                    registration: {
                      id: pendingID,
                      status: 'confirmed',
                      created_at: now.toISOString(),
                      expires_at: now.toISOString(),
                      resolved_at: now.toISOString(),
                      proposal: options.protectedMismatch
                        ? { ...proposal, source_provider_message_id: 'different-protected-source' }
                        : proposal,
                      workout_protocol: 'ui-v1',
                      content_revision: 0,
                    },
                  },
            )
          if (name === 'read_mobile_registration_feedback')
            return Response.json(
              options.failReceipt
                ? { code: 'synthetic_failure' }
                : {
                    action: 'available',
                    feedback: {
                      ...saved(kind),
                      ...(options.invalidReceipt ? { registration_id: admissionID } : {}),
                    },
                  },
              { status: options.failReceipt ? 503 : 200, headers: { 'Retry-After': '0' } },
            )
          throw new Error(`No writer/cursor/other RPC allowed: ${name}`)
        }
        if (method !== 'GET' || !rows[name]) throw new Error(`Unexpected request ${method}/${name}`)
        if (name === 'pending_registrations' && options.failPending)
          return Response.json(
            { code: 'failure' },
            { status: 503, headers: { 'Retry-After': '0' } },
          )
        let selected = rows[name].map((row) => ({ ...row }))
        // Deliberately return an unfiltered candidate when checking response validation.
        if (!(name === 'pending_registrations' && options.candidateChange)) {
          for (const [key, value] of url.searchParams)
            if (value.startsWith('eq.')) {
              const [column, nested] = key.split('->>')
              selected = selected.filter(
                (row) =>
                  String(
                    nested ? (row[column] as Record<string, unknown>)?.[nested] : row[column],
                  ) === value.slice(3),
              )
            }
        }
        const limit = url.searchParams.get('limit')
        if (limit) selected = selected.slice(0, Number(limit))
        const projection = url.searchParams.get('select')
        if (projection && projection !== '*')
          selected = selected.map((row) =>
            Object.fromEntries(projection.split(',').map((key) => [key, row[key]])),
          )
        return Response.json(selected)
      },
    },
  })
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => client,
    createRequestId: () => 'qa-history',
    authenticate: async () => auth,
    authorizeEntitlement: async () => {},
  }
  const route =
    kind === 'meal'
      ? createConfirmedMealRoutes(runtime, () => now).GET
      : createWorkoutStrengthClarificationRoutes(runtime, () => options.enabled ?? true).GET
  const request = new Request(
    `https://app.invalid/api/mobile/v1/${kind === 'meal' ? 'meal-records' : 'workouts'}/${recordID}${kind === 'workout' ? '/strength-clarification' : ''}${options.include === false ? '' : '?include=registration_feedback'}`,
  )
  return {
    recordID,
    clarification,
    requests,
    read: () => route(request, { params: Promise.resolve({ id: recordID }) }),
  }
}

function onlyReads(requests: ReturnType<typeof setup>['requests']) {
  expect(
    requests.every(
      (r) =>
        r.method === 'GET' ||
        [
          'read_mobile_registration_feedback',
          'get_mobile_workout_registration',
          'get_mobile_workout_strength_clarification',
        ].includes(r.name),
    ),
  ).toBe(true)
  const candidate = requests.find((r) => r.name === 'pending_registrations')
  if (candidate) {
    expect(candidate.query.get('user_id')).toBe(`eq.${owner}`)
    expect(candidate.query.get('status')).toBe('eq.confirmed')
    expect(candidate.query.get('limit')).toBe('2')
    expect(candidate.query.get('proposal->>source_provider_message_id')).toBe(`eq.${provider}`)
    expect(['eq.meal', 'eq.workout']).toContain(candidate.query.get('proposal->>kind'))
    if (candidate.query.get('proposal->>kind') === 'eq.meal')
      expect(candidate.query.get('proposal->>registration_origin')).toBe('eq.mobile_app')
  }
  for (const request of requests.filter((r) =>
    ['read_mobile_registration_feedback', 'get_mobile_workout_registration'].includes(r.name),
  ))
    expect(request.body).toEqual({ p_user_id: owner, p_registration_id: pendingID })
}

describe('C13 saved receipt reopening from actual owned History routes', () => {
  it('meal opt-in returns original saved feedback without changing the review version', async () => {
    const ordinary = setup('meal', { include: false }),
      enriched = setup()
    const original = (await (await ordinary.read()).json()).data
    const response = await enriched.read(),
      data = (await response.json()).data
    expect(data).toEqual({ ...original, feedback: saved('meal') })
    expect(data.record_id).not.toBe(data.feedback.registration_id)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(JSON.stringify(data)).not.toMatch(/raw_provider|source_provider|admission|user_id/)
    expect(ordinary.requests.some((r) => r.name === 'pending_registrations')).toBe(false)
    onlyReads(enriched.requests)
  })
  it('C11 new log ID reopens the original receipt, without comparing or recalculating edited foods', async () => {
    const h = setup('meal', { edited: true })
    const data = (await (await h.read()).json()).data
    expect(data.record_id).toBe(h.recordID)
    expect(data.items.find((item: { id: string }) => item.id === h.recordID).kcal).toBe(900)
    expect(data.feedback).toEqual(saved('meal'))
    expect(data.feedback.meal_totals.kcal).toBe(155)
    onlyReads(h.requests)
  })
  it.each([
    'ambiguous',
    'sourceMissing',
    'mixedMealTypes',
    'failPending',
    'failReceipt',
    'invalidReceipt',
  ] as const)('meal preserves its main record when %s prevents optional receipt lookup', async (key) => {
    const h = setup('meal', { [key]: true }),
      response = await h.read()
    expect(response.status).toBe(200)
    expect((await response.json()).data.feedback).toBeUndefined()
    if (['ambiguous', 'sourceMissing', 'mixedMealTypes', 'failPending'].includes(key))
      expect(h.requests.some((r) => r.name === 'read_mobile_registration_feedback')).toBe(false)
    onlyReads(h.requests)
  })
  it.each([
    { user_id: admissionID },
    { status: 'pending' },
    { id: 'not-a-uuid' },
    { workout_ui_admission_id: admissionID },
    { proposal: { kind: 'workout', source_provider_message_id: provider } },
    {
      proposal: {
        kind: 'meal',
        mealType: 'almoco',
        source_provider_message_id: 'foreign',
        registration_origin: 'mobile_app',
        source_local_date: '2026-10-09',
      },
    },
    {
      proposal: {
        kind: 'meal',
        mealType: 'jantar',
        source_provider_message_id: provider,
        registration_origin: 'mobile_app',
        source_local_date: '2026-10-09',
      },
    },
    {
      proposal: {
        kind: 'meal',
        mealType: 'almoco',
        source_provider_message_id: provider,
        source_local_date: '2026-10-09',
      },
    },
  ])('validates the returned meal candidate, not only the requested filters: %j', async (candidateChange) => {
    const h = setup('meal', { candidateChange })
    expect((await (await h.read()).json()).data.feedback).toBeUndefined()
    expect(h.requests.some((r) => r.name === 'read_mobile_registration_feedback')).toBe(false)
    onlyReads(h.requests)
  })
  it.each([
    false,
    true,
  ])('workout opt-in preserves strength authority and reads a %s legacy receipt', async (legacy) => {
    const h = setup('workout', { legacy }),
      response = await h.read()
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      clarification: h.clarification,
      feedback: saved('workout'),
    })
    expect(h.requests[0].name).toBe('get_mobile_workout_strength_clarification')
    expect(h.requests.some((r) => r.name === 'get_mobile_workout_registration')).toBe(!legacy)
    expect(
      h.requests
        .find((r) => r.name === 'pending_registrations')
        ?.query.get('proposal->>workoutType'),
    ).toBe('eq.Natação')
    onlyReads(h.requests)
  })
  it('workout without opt-in keeps the exact old strict shape and no additional reads', async () => {
    const h = setup('workout', { include: false })
    expect((await (await h.read()).json()).data).toEqual(h.clarification)
    expect(h.requests.map((r) => r.name)).toEqual(['get_mobile_workout_strength_clarification'])
  })
  it.each([
    'protectedForbidden',
    'protectedMismatch',
    'ambiguous',
    'invalidReceipt',
    'failReceipt',
    'unavailable',
  ] as const)('workout %s never falls back to another authority or regenerates a receipt', async (key) => {
    const h = setup('workout', { [key]: true }),
      response = await h.read()
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ clarification: h.clarification })
    if (['protectedForbidden', 'protectedMismatch', 'ambiguous', 'unavailable'].includes(key))
      expect(h.requests.some((r) => r.name === 'read_mobile_registration_feedback')).toBe(false)
    if (key === 'protectedMismatch')
      expect(h.requests.some((r) => r.name === 'get_mobile_workout_registration')).toBe(true)
    onlyReads(h.requests)
  })
  it.each([
    'forbidden',
    'enabled',
  ] as const)('main strength %s refusal is never bypassed by optional feedback', async (key) => {
    const h = setup('workout', key === 'enabled' ? { enabled: false } : { forbidden: true })
    expect((await h.read()).status).toBe(key === 'enabled' ? 503 : 409)
    expect(
      h.requests.some((r) =>
        ['pending_registrations', 'workout_logs', 'read_mobile_registration_feedback'].includes(
          r.name,
        ),
      ),
    ).toBe(false)
  })
})
