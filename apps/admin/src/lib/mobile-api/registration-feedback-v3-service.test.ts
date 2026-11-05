import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { auth, legacyFeedback } from './__fixtures__/feedback-v2-source'
import { pendingV3Capture } from './__fixtures__/feedback-v3-source'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { parseFeedbackV3Capture } from './registration-feedback-v3-contracts'
import {
  ensureRegistrationFeedbackV3,
  readRegistrationFeedbackV3,
} from './registration-feedback-v3-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

function harness(
  options: { old?: unknown; lost?: boolean; conflict?: boolean; revokeAfterCommit?: boolean } = {},
) {
  const f = pendingV3Capture()
  let stored: unknown = options.old ?? null
  let committed = false
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    if (name === 'read_mobile_registration_feedback_v3')
      return {
        data: stored ? { action: 'available', feedback: stored } : { action: 'absent' },
        error: null,
      }
    if (name === 'capture_mobile_registration_feedback_v3')
      return { data: { action: 'available', context: f.context }, error: null }
    if (name === 'commit_mobile_registration_feedback_v3') {
      if (options.conflict) return { data: { action: 'source_conflict' }, error: null }
      stored = structuredClone(args.p_feedback)
      committed = true
      if (options.lost) throw new Error('PRIVATE lost response')
      return { data: { action: 'committed', feedback: stored }, error: null }
    }
    throw new Error('Domain/unrelated RPC is forbidden')
  })
  const scope = { checkCurrentScope: vi.fn(async () => !(options.revokeAfterCommit && committed)) }
  const loadClinical = vi.fn(
    async (
      _db: ServiceClient,
      _auth: unknown,
      observation: ReturnType<typeof parseFeedbackV3Capture>,
    ) => ({ policy: projectCurrentClinicalPublicPolicy(observation.clinical), officialDay: null }),
  )
  const db = { rpc } as unknown as ServiceClient
  return { ...f, rpc, db, scope, loadClinical }
}
describe('canonical feedback v3 optional post-registration service', () => {
  it('reads the immutable old winner before source, preparation or current clinical reads', async () => {
    const h = harness({ old: legacyFeedback() })
    await expect(ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).resolves.toEqual(
      legacyFeedback(),
    )
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.loadClinical).not.toHaveBeenCalled()
  })
  it('preserves a stored v2 original rather than generating v3 or rewriting education', async () => {
    const f = pendingV3Capture(),
      o = parseFeedbackV3Capture(f.context, f.who)
    const old = prepareRegistrationFeedbackV2({
      registrationId: f.who.registrationId,
      localDate: o.localDate,
      locale: 'en',
      registration: o.registration,
      policy: projectCurrentClinicalPublicPolicy(o.clinical),
      officialDay: null,
    })
    const h = harness({ old })
    expect(await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).toEqual(old)
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.loadClinical).not.toHaveBeenCalled()
  })
  it('requires a separate canonical read after commit, without any domain writer', async () => {
    const h = harness()
    const result = await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)
    expect(result).toMatchObject({
      schema: 'registration.feedback.v3',
      registration_id: h.who.registrationId,
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
      'commit_mobile_registration_feedback_v3',
      'read_mobile_registration_feedback_v3',
    ])
    expect(h.loadClinical).toHaveBeenCalledTimes(1)
    expect(h.scope.checkCurrentScope).toHaveBeenCalledTimes(10)
  })
  it('reconciles one lost-success response by read, never repeats the commit or preparation', async () => {
    const h = harness({ lost: true })
    expect(await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).toMatchObject({
      schema: 'registration.feedback.v3',
    })
    expect(
      h.rpc.mock.calls.filter(([name]) => name === 'commit_mobile_registration_feedback_v3'),
    ).toHaveLength(1)
    expect(
      h.rpc.mock.calls.filter(([name]) => name === 'read_mobile_registration_feedback_v3'),
    ).toHaveLength(2)
    expect(h.loadClinical).toHaveBeenCalledTimes(1)
  })
  it('does not issue the reconciliation read or return success after post-commit scope revocation', async () => {
    const h = harness({ lost: true, revokeAfterCommit: true })
    expect(await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).toBeNull()
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
      'commit_mobile_registration_feedback_v3',
    ])
  })
  it('returns no enrichment on authoritative source conflict and does not try a numeric fallback', async () => {
    const h = harness({ conflict: true })
    expect(await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).toBeNull()
    expect(h.rpc).toHaveBeenCalledTimes(3)
    expect(h.loadClinical).toHaveBeenCalledTimes(1)
  })
  it('historical read is receipt-only and invalid current Auth mapping performs no RPC', async () => {
    const h = harness({ old: legacyFeedback() })
    expect(await readRegistrationFeedbackV3(h.db, auth, h.who, h.scope)).toEqual(legacyFeedback())
    const changed = structuredClone(auth)
    changed.patient.authUserId = auth.userId
    expect(await ensureRegistrationFeedbackV3(h.db, changed, h.who, h.scope, h)).toBeNull()
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
})

it('latches revocation inside an optional clinical RPC even when that reader swallows the first failure', async () => {
  const h = harness(),
    original = h.rpc.getMockImplementation()
  if (!original) throw new Error('Missing SDK harness')
  let revoked = false
  h.scope.checkCurrentScope.mockImplementation(async () => !revoked)
  h.rpc.mockImplementation(async (name, args) => {
    if (name === 'get_mobile_current_clinical_state') revoked = true
    return original(
      name === 'get_mobile_current_clinical_state' ? 'read_mobile_registration_feedback_v3' : name,
      args,
    )
  })
  h.loadClinical.mockImplementation(async (client, _auth, observation) => {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await createSupabaseCurrentClinicalStateSource(client).capture({
          userId: h.who.userId,
          mode: 'profile',
        })
      } catch {
        /* Simulate a safe optional-reader fallback. */
      }
    }
    return { policy: projectCurrentClinicalPublicPolicy(observation.clinical), officialDay: null }
  })
  expect(await ensureRegistrationFeedbackV3(h.db, auth, h.who, h.scope, h)).toBeNull()
  expect(
    h.rpc.mock.calls.filter(([name]) => name === 'get_mobile_current_clinical_state'),
  ).toHaveLength(1)
  expect(h.rpc.mock.calls.some(([name]) => name === 'commit_mobile_registration_feedback_v3')).toBe(
    false,
  )
})

it('guards each physical optional clinical query dispatch after a swallowed query failure', async () => {
  const h = harness()
  let revoked = false,
    dispatches = 0
  h.scope.checkCurrentScope.mockImplementation(async () => !revoked)
  const query = {
    select: () => query,
    eq: () => query,
    maybeSingle: () => query,
    // biome-ignore lint/suspicious/noThenProperty: Model the actual lazy PostgREST query dispatch boundary.
    then(resolve: (v: unknown) => unknown, reject: (v: unknown) => unknown) {
      dispatches++
      revoked = true
      return Promise.resolve({ data: null, error: null }).then(resolve, reject)
    },
  }
  const db = { ...h.db, from: vi.fn(() => query) } as unknown as ServiceClient
  h.loadClinical.mockImplementation(async (client, _auth, observation) => {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await client.from('daily_snapshots').select('id').eq('user_id', h.who.userId).maybeSingle()
      } catch {
        /* Optional reader may catch its own data failure. */
      }
    }
    return { policy: projectCurrentClinicalPublicPolicy(observation.clinical), officialDay: null }
  })
  expect(await ensureRegistrationFeedbackV3(db, auth, h.who, h.scope, h)).toBeNull()
  expect(dispatches).toBe(1)
  expect(h.rpc).toHaveBeenCalledTimes(2)
})

it('never gives optional clinical enrichment a table-write capability', async () => {
  const h = harness(),
    update = vi.fn(async () => ({ data: null, error: null }))
  const db = { ...h.db, from: vi.fn(() => ({ update })) } as unknown as ServiceClient
  h.loadClinical.mockImplementation(async (client, _auth, observation) => {
    try {
      await client.from('daily_snapshots').update({ exercise_calories: 999 })
    } catch {
      /* Metadata remains optional. */
    }
    return { policy: projectCurrentClinicalPublicPolicy(observation.clinical), officialDay: null }
  })
  expect(await ensureRegistrationFeedbackV3(db, auth, h.who, h.scope, h)).toMatchObject({
    schema: 'registration.feedback.v3',
  })
  expect(update).not.toHaveBeenCalled()
})
