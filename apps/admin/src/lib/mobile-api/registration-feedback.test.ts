import { prepareRegistrationFeedback } from '@mpp/agent/registration-feedback'
import type { Database, ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { FlowPhraseCursorSnapshot } from './flow-phrase-reply-store'
import {
  ensureRegistrationFeedback,
  type RegistrationFeedbackDaySnapshot,
  readRegistrationFeedback,
} from './registration-feedback-service'
import {
  createSupabaseRegistrationFeedbackStore,
  parseRegistrationFeedback,
  type RegistrationFeedbackCommit,
  type RegistrationFeedbackStore,
} from './registration-feedback-store'

const owner = '00000000-0000-0000-0000-00000000c501'
const id = '00000000-0000-0000-0000-00000000c531'
const logId = '00000000-0000-0000-0000-00000000c541'
const identity = { userId: owner, registrationId: id, kind: 'meal' as const }
const proposal = {
  kind: 'meal',
  mealType: 'cafe',
  items: [{ name: 'iogurte natural', kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 }],
  totals: { kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 },
  source_provider_message_id: 'mobile/qa/meal',
  source_timestamp: '2026-10-25T01:30:00Z',
  source_timezone: 'America/Sao_Paulo',
  source_local_date: '2026-10-24',
  private_sentinel: 'not-public',
}
const registration = { id, user_id: owner, status: 'confirmed', proposal }
const auth: MobileAuthContext = {
  userId: owner,
  authUserId: '00000000-0000-0000-0000-00000000a501',
  accessToken: 'synthetic',
  identity: { id: '00000000-0000-0000-0000-00000000a501', email: null, emailConfirmedAt: null },
  patient: {
    id: owner,
    authUserId: '00000000-0000-0000-0000-00000000a501',
    email: null,
    name: 'QA',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
const stored = {
  schema: 'registration.feedback.v1' as const,
  registration_id: id,
  kind: 'meal' as const,
  locale: 'pt-BR' as const,
  meal_totals: { kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 },
  day: null,
  lines: [
    { key: 'meal_totals' as const, text: '435 kcal' },
    { key: 'day_unavailable' as const, text: 'Os dados deste dia estão indisponíveis.' },
  ],
  food_comment: null,
  incentive: 'Consistência vale mais do que perfeição.',
}
const day: RegistrationFeedbackDaySnapshot = {
  local_date: '2026-10-24',
  current_protocol: 'recomposicao',
  consumed: {
    calories_kcal: 1785,
    protein_g: 126,
    carbs_g: 200,
    fat_g: 50,
    source: 'daily_snapshot',
  },
  targets: { calories_kcal: 2400, protein_g: 150 },
  remaining_food_kcal: 615,
  food_excess_kcal: 0,
  exercise_kcal: 504,
  meals: [{ id: logId }],
  workouts: [],
}
const zeroCursor = { anchorAssistantId: null, cursorRevision: '0', cursor: null }

function client(respond: (path: string, body: unknown) => { data: unknown; status?: number }) {
  const requests: { path: string; body: unknown }[] = []
  const urls: string[] = []
  const supabase = createClient<Database>('https://synthetic.invalid', 'synthetic-test-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (url, init) => {
        urls.push(String(url))
        const path = new URL(String(url)).pathname
        const body = typeof init?.body === 'string' ? JSON.parse(init.body) : null
        requests.push({ path, body })
        const result = respond(path, body)
        return new Response(JSON.stringify(result.data), {
          status: result.status ?? 200,
          headers: { 'Content-Type': 'application/json' },
        })
      },
    },
  })
  return { supabase, requests, urls }
}

function harness(
  options: {
    receipts?: Awaited<ReturnType<RegistrationFeedbackStore['readReceipt']>>[]
    commits?: (Awaited<ReturnType<RegistrationFeedbackStore['commit']>> | Error)[]
    day?: RegistrationFeedbackDaySnapshot | Error
    logIds?: string[]
    kind?: 'meal' | 'workout'
  } = {},
) {
  const calls: string[] = []
  const inputs: RegistrationFeedbackCommit[] = []
  const receipts = [...(options.receipts ?? [{ action: 'absent' as const }])]
  const commits = [...(options.commits ?? [])]
  let cursor: FlowPhraseCursorSnapshot = zeroCursor
  const store: RegistrationFeedbackStore = {
    async readReceipt(got) {
      expect(got).toStrictEqual({ ...identity, kind: options.kind ?? 'meal' })
      calls.push('receipt')
      return receipts.shift() ?? { action: 'absent' }
    },
    async loadCursor(got) {
      expect(got).toBe(owner)
      calls.push('cursor')
      return cursor
    },
    async commit(input) {
      calls.push('commit')
      inputs.push(input)
      const result = commits.shift()
      if (result instanceof Error) throw result
      if (result) return result
      cursor = {
        ...zeroCursor,
        cursorRevision: '1',
        cursor: input.steps.at(-1)?.nextCursor ?? null,
      }
      return { action: 'committed', feedback: input.feedback }
    },
  }
  const supabase = client(() => {
    throw new Error('Unexpected network in injected test')
  }).supabase
  const deps = {
    store,
    async loadDay(_db: ServiceClient, userId: string, timezone: string, instant: Date) {
      calls.push('day')
      expect(userId).toBe(owner)
      expect(timezone).toBe('America/Sao_Paulo')
      expect(instant.toISOString()).toBe('2026-10-25T01:30:00.000Z')
      if (options.day instanceof Error) throw options.day
      return options.day ?? structuredClone(day)
    },
    async loadLogIds() {
      calls.push('logs')
      return options.logIds ?? [logId]
    },
  }
  return { calls, inputs, deps, supabase }
}

describe('C13 trusted receipt adapter', () => {
  it('reads the owned receipt through the backend RPC without exposing private columns', async () => {
    const { supabase, requests } = client(() => ({
      data: { action: 'available', feedback: stored },
    }))
    const result = await createSupabaseRegistrationFeedbackStore(supabase).readReceipt(identity)
    expect(result).toStrictEqual({ action: 'available', feedback: stored })
    expect(requests).toStrictEqual([
      {
        path: '/rest/v1/rpc/read_mobile_registration_feedback',
        body: { p_user_id: owner, p_registration_id: id },
      },
    ])
  })
  it.each([
    'absent',
    'event_conflict',
  ] as const)('keeps %s distinct from a receipt', async (action) => {
    const { supabase } = client(() => ({ data: { action } }))
    expect(
      await createSupabaseRegistrationFeedbackStore(supabase).readReceipt(identity),
    ).toStrictEqual({ action })
  })
  it('uses the shared cursor with a lossless revision above the JS safe integer range', async () => {
    const prepared = prepareRegistrationFeedback(
      {
        ...identity,
        registrationId: id,
        locale: 'en',
        registration: { status: 'confirmed', kind: 'workout' },
        day: null,
      },
      null,
    )
    const { supabase, requests } = client(() => ({
      data: {
        schema: 'flow.shared-phrase-snapshot.v1',
        mode: 'shared',
        legacy_cursor_revision: '0',
        anchor_assistant_id: null,
        cursor_revision: '9007199254740993',
        cursor: prepared.nextCursor,
      },
    }))
    const result = await createSupabaseRegistrationFeedbackStore(supabase).loadCursor(owner)
    expect(result.cursorRevision).toBe('9007199254740993')
    expect(requests[0]?.path).toBe('/rest/v1/rpc/read_flow_shared_phrase_cursor')
  })
  it('commits the exact proposal/two steps, and returns the stored winner rather than its candidate', async () => {
    const prepared = prepareRegistrationFeedback(
      {
        userId: owner,
        registrationId: id,
        locale: 'en',
        registration: {
          status: 'confirmed',
          kind: 'meal',
          mealKind: 'cafe',
          totals: proposal.totals,
          items: proposal.items.map(({ name, ...item }) => ({ ...item, food_name: name })),
        },
        day: null,
      },
      null,
    )
    const { supabase, requests } = client(() => ({ data: { action: 'replay', feedback: stored } }))
    const result = await createSupabaseRegistrationFeedbackStore(supabase).commit({
      ...identity,
      expectedProposal: proposal,
      expectedCursorRevision: '9007199254740993',
      expectedCursor: null,
      steps: prepared.steps,
      feedback: prepared.feedback,
    })
    expect(result).toStrictEqual({ action: 'replay', feedback: stored })
    expect(requests).toStrictEqual([
      {
        path: '/rest/v1/rpc/commit_mobile_registration_feedback',
        body: {
          p_user_id: owner,
          p_registration_id: id,
          p_expected_proposal: proposal,
          p_expected_revision: '9007199254740993',
          p_expected_cursor: null,
          p_steps: prepared.steps,
          p_feedback: prepared.feedback,
        },
      },
    ])
    expect(JSON.stringify(result)).not.toContain('private_sentinel')
  })
  it.each([
    { ...stored, private_sentinel: 'secret' },
    { ...stored, registration_id: logId },
    { ...stored, kind: 'workout' },
    { ...stored, meal_totals: { ...stored.meal_totals, kcal: Number.NaN } },
    { ...stored, meal_totals: { ...stored.meal_totals, kcal: undefined } },
    { ...stored, locale: 'en' },
    { ...stored, lines: [stored.lines[0], stored.lines[0]] },
    { ...stored, day: { ...day, local_date: '2026-02-30' } },
  ])('rejects malformed/private/mismatched feedback without lossy JSON normalization %#', (value) => {
    expect(() => parseRegistrationFeedback(value, identity)).toThrow()
  })
  it('does not convert transport failures into retryable CAS conflicts', async () => {
    const { supabase } = client(() => ({ data: { message: 'synthetic SQL failure' }, status: 500 }))
    await expect(
      createSupabaseRegistrationFeedbackStore(supabase).readReceipt(identity),
    ).rejects.toThrow()
  })
})

describe('C13 optional confirmed feedback service', () => {
  it.each([
    'meal',
    'workout',
  ] as const)('links %s through real SDK filters and the exact receipt RPC contract', async (kind) => {
    const { supabase, urls } = client((path, body) => {
      if (path.endsWith('/read_mobile_registration_feedback')) return { data: { action: 'absent' } }
      if (path.endsWith('/commit_mobile_registration_feedback')) {
        const args = body as Record<string, unknown>
        if (
          Object.keys(args).sort().join(',') !==
          'p_expected_cursor,p_expected_proposal,p_expected_revision,p_feedback,p_registration_id,p_steps,p_user_id'
        )
          return { status: 404, data: { code: 'PGRST202', message: 'No matching RPC signature' } }
        return { data: { action: 'committed', feedback: args.p_feedback } }
      }
      if (path.endsWith('/read_flow_shared_phrase_cursor'))
        return {
          data: {
            schema: 'flow.shared-phrase-snapshot.v1',
            mode: 'legacy',
            legacy_cursor_revision: '0',
            anchor_assistant_id: null,
            cursor_revision: '0',
            cursor: null,
          },
        }
      if (path === `/rest/v1/${kind === 'meal' ? 'meal_logs' : 'workout_logs'}`)
        return { data: [{ id: logId }] }
      throw new Error(`Unexpected SDK request: ${path}`)
    })
    const result = await ensureRegistrationFeedback(
      supabase,
      auth,
      {
        ...registration,
        proposal: kind === 'meal' ? proposal : { ...proposal, kind, workoutType: 'forca' },
      },
      { loadDay: async () => ({ ...day, workouts: [{ id: logId }] }) },
    )
    expect(result?.kind).toBe(kind)
    expect(result?.day?.consumed.calories_kcal).toBe(1785)
    const lookup = urls
      .map((url) => new URL(url))
      .find((url) => url.pathname.endsWith(`/${kind === 'meal' ? 'meal_logs' : 'workout_logs'}`))
    expect(lookup?.searchParams.get('select')).toBe('id')
    expect(lookup?.searchParams.get('user_id')).toBe(`eq.${owner}`)
    expect(lookup?.searchParams.get('raw_provider_message_id')).toBe('eq.mobile/qa/meal')
    expect(lookup?.searchParams.get('workout_type')).toBe(kind === 'workout' ? 'eq.forca' : null)
    expect(lookup?.searchParams.get('limit')).toBe('31')
  })
  it.each([
    true,
    false,
  ])('uses the confirmed workout identity to prove daily inclusion: %s', async (present) => {
    const h = harness({
      kind: 'workout',
      day: { ...day, workouts: present ? [{ id: logId }] : [] },
    })
    const result = await ensureRegistrationFeedback(
      h.supabase,
      auth,
      {
        ...registration,
        proposal: { ...proposal, kind: 'workout', workoutType: 'forca' },
        confirmedWorkoutId: logId,
      },
      h.deps,
    )
    expect(result?.kind).toBe('workout')
    expect(result?.meal_totals).toBeNull()
    expect(result?.food_comment).toBeNull()
    expect(result?.incentive).toBeTruthy()
    expect(result?.day?.local_date ?? null).toBe(present ? '2026-10-24' : null)
    expect(h.calls).not.toContain('logs')
    expect(h.inputs[0]?.steps).toHaveLength(1)
  })
  it('keeps English numeric feedback without translating the approved Portuguese phrase bank', async () => {
    const h = harness({ kind: 'workout' })
    const result = await ensureRegistrationFeedback(
      h.supabase,
      { ...auth, patient: { ...auth.patient, locale: 'en' } },
      { ...registration, proposal: { kind: 'workout' } },
      h.deps,
    )
    expect(result?.locale).toBe('en')
    expect(result?.food_comment).toBeNull()
    expect(result?.incentive).toBeNull()
    expect(result?.lines).toStrictEqual([
      { key: 'day_unavailable', text: 'The data for this day is unavailable.' },
    ])
    expect(h.inputs[0]?.steps[0]?.nextCursor.ordinal).toBe(0)
  })
  it('returns an existing receipt before reading timing, official day, or phrase cursor', async () => {
    const h = harness({ receipts: [{ action: 'available', feedback: stored }] })
    const result = await ensureRegistrationFeedback(
      h.supabase,
      { ...auth, patient: { ...auth.patient, locale: 'en' } },
      { ...registration, proposal: { kind: 'meal' } },
      h.deps,
    )
    expect(result).toStrictEqual(stored)
    expect(h.calls).toStrictEqual(['receipt'])
  })
  it('uses canonical totals and the linked official day, with UTC rollover and no private fields', async () => {
    const h = harness()
    const result = await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)
    expect(result?.meal_totals).toStrictEqual({ kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 })
    expect(result?.day).toStrictEqual({
      local_date: '2026-10-24',
      current_protocol: 'recomposicao',
      consumed: { calories_kcal: 1785, protein_g: 126, carbs_g: 200, fat_g: 50 },
      targets: { calories_kcal: 2400, protein_g: 150 },
      remaining_food_kcal: 615,
      food_excess_kcal: 0,
      exercise_kcal: 504,
      calorie_percentage: 74.4,
      protein_percentage: 84,
    })
    expect(result?.lines.some((line) => line.text === 'Restam 615 kcal para comida.')).toBe(true)
    expect(JSON.stringify(result)).not.toMatch(/sentinel|source|meals|workouts|cursor|receipt/u)
    expect(h.inputs[0]?.expectedProposal).toStrictEqual(proposal)
    expect(h.inputs[0]?.steps).toHaveLength(2)
  })
  it('does not resum binary item floats over the official decimal total', async () => {
    const h = harness()
    const nutrients = (kcal: number) => ({ kcal, protein_g: kcal, carbs_g: kcal, fat_g: kcal })
    const result = await ensureRegistrationFeedback(
      h.supabase,
      auth,
      {
        ...registration,
        proposal: {
          ...proposal,
          totals: nutrients(0.3),
          items: [0.1, 0.2].map((value) => ({ name: 'synthetic', ...nutrients(value) })),
        },
      },
      h.deps,
    )
    expect(result?.meal_totals?.kcal).toBe(0.3)
  })
  it('omits new feedback for a historical meal without canonical totals, without selecting', async () => {
    const h = harness()
    expect(
      await ensureRegistrationFeedback(
        h.supabase,
        auth,
        { ...registration, proposal: { ...proposal, totals: null } },
        h.deps,
      ),
    ).toBeNull()
    expect(h.calls).toStrictEqual(['receipt'])
  })
  it.each([
    { day: { ...day, consumed: { ...day.consumed, source: 'empty_day' } } },
    { day: { ...day, local_date: '2026-10-25' } },
    { day: new Error('daily source unavailable') },
    { logIds: [] },
    { logIds: [id] },
  ])('keeps meal feedback but omits unproven daily facts %#', async (options) => {
    const h = harness(options)
    const result = await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)
    expect(result?.day).toBeNull()
    expect(result?.meal_totals?.kcal).toBe(435)
    expect(result?.incentive).toBeTruthy()
  })
  it('does not replace invalid source timing with now or UTC', async () => {
    const h = harness()
    const result = await ensureRegistrationFeedback(
      h.supabase,
      auth,
      { ...registration, proposal: { ...proposal, source_timezone: 'invalid/timezone' } },
      h.deps,
    )
    expect(result?.day).toBeNull()
    expect(h.calls).toStrictEqual(['receipt', 'cursor', 'commit'])
  })
  it('preserves nullable official targets and the current protocol without substituting old profile values', async () => {
    const h = harness({
      day: {
        ...day,
        current_protocol: 'ganho_massa',
        targets: { calories_kcal: null, protein_g: null },
        remaining_food_kcal: null,
        food_excess_kcal: null,
      },
    })
    const result = await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)
    expect(result?.day?.current_protocol).toBe('ganho_massa')
    expect(result?.day?.calorie_percentage).toBeNull()
    expect(result?.day?.protein_percentage).toBeNull()
  })
  it('retries only explicit cursor conflicts, with the same confirmed facts', async () => {
    const h = harness({ commits: [{ action: 'cursor_conflict' }] })
    expect(
      (await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps))?.registration_id,
    ).toBe(id)
    expect(h.calls).toStrictEqual([
      'receipt',
      'day',
      'logs',
      'cursor',
      'commit',
      'cursor',
      'commit',
    ])
    expect(h.inputs[1]?.expectedProposal).toStrictEqual(h.inputs[0]?.expectedProposal)
  })
  it('bounds cursor contention and never publishes an uncommitted candidate', async () => {
    const h = harness({
      commits: Array.from({ length: 3 }, () => ({ action: 'cursor_conflict' as const })),
    })
    expect(await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)).toBeNull()
    expect(h.inputs).toHaveLength(3)
  })
  it('does not retry an event conflict', async () => {
    const h = harness({ commits: [{ action: 'event_conflict' }] })
    expect(await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)).toBeNull()
    expect(h.inputs).toHaveLength(1)
  })
  it('resolves an uncertain commit with one receipt read and no blind retry', async () => {
    const h = harness({
      receipts: [{ action: 'absent' }, { action: 'available', feedback: stored }],
      commits: [new Error('connection lost after commit')],
    })
    expect(await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)).toStrictEqual(
      stored,
    )
    expect(h.calls).toStrictEqual(['receipt', 'day', 'logs', 'cursor', 'commit', 'receipt'])
    expect(h.inputs).toHaveLength(1)
  })
  it('keeps optional feedback unavailable when an uncertain commit cannot be resolved', async () => {
    const h = harness({ commits: [new Error('connection lost')] })
    expect(await ensureRegistrationFeedback(h.supabase, auth, registration, h.deps)).toBeNull()
    expect(h.inputs).toHaveLength(1)
    expect(h.calls.at(-1)).toBe('receipt')
  })
  it.each([
    'pending',
    'cancelled',
  ])('does not enrich %s or touch a receipt/cursor', async (status) => {
    const h = harness()
    expect(
      await ensureRegistrationFeedback(h.supabase, auth, { ...registration, status }, h.deps),
    ).toBeNull()
    expect(h.calls).toStrictEqual([])
  })
  it('refuses a different row owner before any operation', async () => {
    const h = harness()
    expect(
      await ensureRegistrationFeedback(
        h.supabase,
        auth,
        { ...registration, user_id: logId },
        h.deps,
      ),
    ).toBeNull()
    expect(h.calls).toStrictEqual([])
  })
  it('reopening only reads the receipt; absence never generates a new response', async () => {
    const h = harness()
    expect(
      await readRegistrationFeedback(h.supabase, auth.userId, registration, h.deps.store),
    ).toBeNull()
    expect(h.calls).toStrictEqual(['receipt'])
  })
})
