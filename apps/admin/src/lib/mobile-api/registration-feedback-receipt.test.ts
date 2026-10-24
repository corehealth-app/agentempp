import type { Database } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it, vi } from 'vitest'
import { readRegistrationFeedback } from './registration-feedback-receipt'

// The receipt leaf must load without materializing any generation/cursor module.
vi.mock('@mpp/agent/registration-feedback', () => {
  throw new Error('Receipt read imported the generator at runtime')
})
vi.mock('@mpp/agent/flow-curated-phrases', () => {
  throw new Error('Receipt read imported the catalog at runtime')
})
vi.mock('./flow-phrase-reply-store', () => {
  throw new Error('Receipt read imported the cursor store at runtime')
})

const owner = '00000000-0000-4000-8000-000000000001'
const id = '00000000-0000-4000-8000-000000000002'
const row = { id, user_id: owner, status: 'confirmed', proposal: { kind: 'workout' } }
const saved = {
  schema: 'registration.feedback.v1',
  registration_id: id,
  kind: 'workout',
  locale: 'pt-BR',
  meal_totals: null,
  day: null,
  lines: [{ key: 'day_unavailable', text: 'Os dados deste dia estão indisponíveis.' }],
  food_comment: null,
  incentive: 'Texto original salvo.',
}

function sdk(body: unknown) {
  const calls: { path: string; method: string; body: unknown }[] = []
  const db = createClient<Database>('https://receipt.example.invalid', 'synthetic-service', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        calls.push({
          path: new URL(String(input)).pathname,
          method: init?.method ?? '',
          body: JSON.parse(String(init?.body)),
        })
        return new Response(JSON.stringify(body), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        })
      },
    },
  })
  return { db, calls }
}

describe('registration feedback receipt-only leaf', () => {
  it('uses the existing owned receipt RPC once without loading generation dependencies', async () => {
    const h = sdk({ action: 'available', feedback: saved })
    expect(await readRegistrationFeedback(h.db, owner, row)).toEqual(saved)
    expect(h.calls).toEqual([
      {
        path: '/rest/v1/rpc/read_mobile_registration_feedback',
        method: 'POST',
        body: { p_user_id: owner, p_registration_id: id },
      },
    ])
  })

  it.each([
    { ...row, status: 'pending' },
    { ...row, user_id: '00000000-0000-4000-8000-000000000003' },
    { ...row, proposal: { kind: 'unknown' } },
  ])('rejects an unproven registration before any RPC: %j', async (unproven) => {
    const h = sdk({ action: 'available', feedback: saved })
    expect(await readRegistrationFeedback(h.db, owner, unproven)).toBeNull()
    expect(h.calls).toEqual([])
  })

  it.each([
    { action: 'absent' },
    { action: 'event_conflict' },
    { action: 'available', feedback: { ...saved, registration_id: owner } },
  ])('keeps optional absence/conflict/invalid receipt fail-soft: %j', async (reply) => {
    const h = sdk(reply)
    expect(await readRegistrationFeedback(h.db, owner, row)).toBeNull()
    expect(h.calls).toHaveLength(1)
  })
})
