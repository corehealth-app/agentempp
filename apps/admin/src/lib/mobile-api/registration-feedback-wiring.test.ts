import type { Database } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { confirmRegistration } from './registration-service'

const writers = vi.hoisted(() => ({ meal: vi.fn(), workout: vi.fn() }))
vi.mock('@mpp/agent', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@mpp/agent')>()),
  registraRefeicao: { execute: writers.meal },
  registraTreino: { execute: writers.workout },
}))

const owner = '00000000-0000-4000-8000-00000000c501'
const id = '00000000-0000-4000-8000-00000000c531'
const rawProposal = {
  kind: 'meal',
  mealType: 'cafe',
  registration_origin: 'mobile_app',
  items: [
    {
      name: 'iogurte natural',
      quantity_g: 100,
      kcal: 435.05,
      protein_g: 42.02,
      carbs_g: 49.04,
      fat_g: 5.01,
    },
  ],
  totals: { kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 },
  source_provider_message_id: 'mobile/c13/meal',
  source_timestamp: '2026-10-24T12:30:00Z',
  source_timezone: 'America/Sao_Paulo',
  source_local_date: '2026-10-24',
  private_sentinel: 'never-in-feedback',
}
const auth: MobileAuthContext = {
  accessToken: 'synthetic',
  userId: owner,
  authUserId: '00000000-0000-4000-8000-00000000a501',
  identity: { id: '00000000-0000-4000-8000-00000000a501', email: null, emailConfirmedAt: null },
  patient: {
    id: owner,
    authUserId: '00000000-0000-4000-8000-00000000a501',
    email: null,
    name: 'QA',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
type Options = { confirmed?: boolean; feedbackOutage?: boolean; protected?: boolean }
function database(options: Options = {}) {
  let status = options.confirmed ? 'confirmed' : 'pending'
  let receipt: unknown = null
  const calls: { method: string; url: URL; body: Record<string, unknown> | null }[] = []
  const db = createClient<Database>('https://synthetic.invalid', 'synthetic-test-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (rawURL, init) => {
        const url = new URL(String(rawURL))
        const method = init?.method ?? 'GET'
        const body = typeof init?.body === 'string' ? JSON.parse(init.body) : null
        calls.push({ method, url, body })
        const ok = (value: unknown) =>
          new Response(JSON.stringify(value), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          })
        if (url.pathname.endsWith('/pending_registrations')) {
          expect(url.searchParams.get('user_id')).toBe(`eq.${owner}`)
          expect(url.searchParams.get('id')).toBe(`eq.${id}`)
          if (method === 'PATCH') {
            expect(writers.meal).toHaveBeenCalledTimes(1)
            expect(body?.status).toBe('confirmed')
            status = 'confirmed'
            return ok({ id })
          }
          return ok([
            {
              id,
              user_id: owner,
              proposal: rawProposal,
              status,
              workout_ui_admission_id: options.protected ? id : null,
              created_at: '2026-10-24T12:30:00Z',
              expires_at: '2099-10-25T12:30:00Z',
              resolved_at: status === 'confirmed' ? '2026-10-24T12:31:00Z' : null,
            },
          ])
        }
        if (url.pathname.endsWith('/read_mobile_registration_feedback')) {
          expect(status).toBe('confirmed')
          expect(body).toStrictEqual({ p_user_id: owner, p_registration_id: id })
          if (!options.feedbackOutage)
            return ok(
              receipt === null ? { action: 'absent' } : { action: 'available', feedback: receipt },
            )
        }
        if (url.pathname.endsWith('/read_flow_shared_phrase_cursor'))
          return ok({
            schema: 'flow.shared-phrase-snapshot.v1',
            mode: 'legacy',
            legacy_cursor_revision: '0',
            anchor_assistant_id: null,
            cursor_revision: '0',
            cursor: null,
          })
        if (url.pathname.endsWith('/commit_mobile_registration_feedback')) {
          expect(status).toBe('confirmed')
          expect(body?.p_user_id).toBe(owner)
          expect(body?.p_expected_proposal).toStrictEqual(rawProposal)
          expect(body?.p_expected_revision).toBe('0')
          receipt = body?.p_feedback
          return ok({ action: 'committed', feedback: receipt })
        }
        // The official daily read is intentionally unavailable in this scenario.
        // A confirmed meal still receives its own totals and approved phrases.
        return new Response(
          JSON.stringify({
            code: 'SYNTHETIC_UNAVAILABLE',
            message: 'synthetic source unavailable',
          }),
          { status: 503, headers: { 'Content-Type': 'application/json', 'Retry-After': '0' } },
        )
      },
    },
  })
  return { db, calls }
}

beforeEach(() => {
  vi.resetAllMocks()
  writers.meal.mockResolvedValue({ success: true, deduped: false })
  writers.workout.mockResolvedValue({ success: true, deduped: false })
})

describe('C13 through the real legacy confirm, consumer and Supabase SDK', () => {
  it('attaches durable feedback only after business success and reuses it without writing twice', async () => {
    const h = database()
    const first = await confirmRegistration(h.db, auth, id)
    expect(first).toMatchObject({
      id,
      status: 'confirmed',
      already_confirmed: false,
      deduped: false,
      feedback: {
        registration_id: id,
        kind: 'meal',
        meal_totals: { kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 },
        day: null,
      },
    })
    expect(JSON.stringify(first.feedback)).not.toMatch(/sentinel|provider|cursor|receipt/u)
    expect(first.feedback?.incentive).toBeTruthy()
    const second = await confirmRegistration(h.db, auth, id)
    expect(second).toMatchObject({
      status: 'confirmed',
      already_confirmed: true,
      feedback: first.feedback,
    })
    expect(writers.meal).toHaveBeenCalledTimes(1)
    expect(
      h.calls.filter((call) => call.url.pathname.endsWith('/commit_mobile_registration_feedback')),
    ).toHaveLength(1)
    expect(
      h.calls.filter((call) => call.url.pathname.endsWith('/read_flow_shared_phrase_cursor')),
    ).toHaveLength(1)
    expect(h.calls.filter((call) => call.method === 'PATCH')).toHaveLength(1)
  })
  it('preserves confirmation on feedback outage and does not retry the meal writer', async () => {
    const h = database({ feedbackOutage: true })
    const first = await confirmRegistration(h.db, auth, id)
    expect(first).toMatchObject({ status: 'confirmed', already_confirmed: false, deduped: false })
    expect(first).not.toHaveProperty('feedback')
    expect(await confirmRegistration(h.db, auth, id)).toMatchObject({
      status: 'confirmed',
      already_confirmed: true,
    })
    expect(writers.meal).toHaveBeenCalledTimes(1)
    expect(
      h.calls.filter((call) => call.url.pathname.endsWith('/commit_mobile_registration_feedback')),
    ).toHaveLength(0)
  })
  it('does not invoke feedback before a rejected business confirmation', async () => {
    const h = database()
    writers.meal.mockResolvedValue({ success: false })
    await expect(confirmRegistration(h.db, auth, id)).rejects.toMatchObject({
      status: 422,
      code: 'registration_rejected',
    })
    expect(h.calls.map((call) => call.url.pathname)).toStrictEqual([
      '/rest/v1/pending_registrations',
    ])
  })
  it.each([
    false,
    true,
  ])('keeps the protected workout compatibility guard before all C13: confirmed=%s', async (confirmed) => {
    const h = database({ protected: true, confirmed })
    await expect(confirmRegistration(h.db, auth, id)).rejects.toMatchObject({
      status: 409,
      code: 'registration_revision_required',
    })
    expect(writers.meal).not.toHaveBeenCalled()
    expect(h.calls.map((call) => call.url.pathname)).toStrictEqual([
      '/rest/v1/pending_registrations',
    ])
  })
})
