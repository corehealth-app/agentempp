import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import protectedWorkout from './__fixtures__/feedback-v2-protected-qa.json'
import {
  context,
  fixtureFirst,
  legacyFeedback,
  other,
  owner,
  registrationId,
} from './__fixtures__/feedback-v2-source'
import { projectRegistrationFeedbackV2Facts } from './registration-feedback-v2-facts'
import {
  createSupabaseRegistrationFeedbackV2Store,
  parseFeedbackV2Capture,
} from './registration-feedback-v2-store'

const identity = { userId: owner, registrationId, kind: 'meal' as const }
function prepared() {
  const c = context()
  const facts = projectRegistrationFeedbackV2Facts({
    userId: owner,
    registrationId,
    confirmed: c.confirmed,
    logs: c.logs,
  })
  if (!facts) throw new Error('Fixture facts')
  return prepareRegistrationFeedbackV2({
    registrationId,
    localDate: facts.localDate,
    locale: 'pt-BR',
    registration: facts.registration,
    policy: null,
    officialDay: null,
  })
}
function store(data: unknown, error: unknown = null) {
  const rpc = vi.fn(async () => ({ data, error }))
  return {
    rpc,
    value: createSupabaseRegistrationFeedbackV2Store({ rpc } as unknown as ServiceClient),
  }
}
describe('feedback v2 trusted RPC transport', () => {
  it('constructs without reading, then reads one typed service RPC and validates the public receipt', async () => {
    const f = prepared(),
      s = store({ action: 'available', feedback: f })
    expect(s.rpc).not.toHaveBeenCalled()
    expect(await s.value.readReceipt(identity)).toEqual({ action: 'available', feedback: f })
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('read_mobile_registration_feedback_v2', {
      p_user_id: owner,
      p_registration_id: registrationId,
    })
  })
  it('preserves a historical v1 result without upgrading it', async () => {
    const f = legacyFeedback(),
      s = store({ action: 'legacy', feedback: f })
    expect(await s.value.readReceipt(identity)).toEqual({ action: 'legacy', feedback: f })
    expect(s.rpc).toHaveBeenCalledTimes(1)
  })
  it('captures owned facts and a detached private observation without returning it as public feedback', async () => {
    const c = context(),
      s = store({ action: 'available', context: c })
    const value = await s.value.capture(identity)
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Fixture')
    fixtureFirst(c.logs).kcal = 999
    expect(value.observation.facts.registration).toMatchObject({
      kind: 'meal',
      items: [{ kcal: 126.12, quantity: { value: 200, unit: 'mL' } }],
      totals: { kcal: 126.1 },
    })
    expect(Object.isFrozen(value.observation.context)).toBe(true)
    expect(Object.isFrozen(value.observation.context.logs)).toBe(true)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('capture_mobile_registration_feedback_v2', {
      p_user_id: owner,
      p_registration_id: registrationId,
    })
  })
  it.each([
    'owner',
    'nonmobile',
    'event',
    'snapshot-owner',
    'snapshot-link',
    'progress-owner',
    'clinical-owner',
    'log-edit',
    'proof-on-meal',
    'private-root',
  ] as const)('rejects a private capture with %s mismatch', (kind) => {
    const c = context()
    if (kind === 'owner') c.user_id = other
    if (kind === 'nonmobile') c.confirmed.proposal.registration_origin = 'legacy'
    if (kind === 'event') c.registration_id = other
    if (kind === 'snapshot-owner') c.snapshot.user_id = other
    if (kind === 'snapshot-link') fixtureFirst(c.logs).snapshot_id = other
    if (kind === 'progress-owner') c.progress.user_id = other
    if (kind === 'clinical-owner') c.clinical.user_id = other
    if (kind === 'log-edit') fixtureFirst(c.logs).kcal = 999
    const raw =
      kind === 'proof-on-meal'
        ? { ...c, workout_proof: { kind: 'direct-key' } }
        : kind === 'private-root'
          ? { ...c, private_extra: 'x' }
          : c
    expect(() => parseFeedbackV2Capture(raw, identity)).toThrow()
  })
  it('requires the protected marker and maps ui-v1 to the full existing witness', () => {
    const p = structuredClone(protectedWorkout)
    const c = context()
    const snapshot = {
      ...c.snapshot,
      id: fixtureFirst(p.logs).snapshot_id,
      user_id: p.userId,
      date: p.confirmed.proposal.source_local_date,
    }
    const raw = {
      ...c,
      user_id: p.userId,
      registration_id: p.registrationId,
      confirmed: p.confirmed,
      logs: p.logs,
      workout_proof: p.workoutProof,
      snapshot,
      progress: null,
      clinical: {
        ...c.clinical,
        user_id: p.userId,
        date: p.confirmed.proposal.source_local_date,
        health_state: { ...c.clinical.health_state, user_id: p.userId },
      },
    }
    const who = { userId: p.userId, registrationId: p.registrationId, kind: 'workout' as const }
    expect(parseFeedbackV2Capture(raw, who).facts.registration).toMatchObject({
      kind: 'workout',
      estimated_kcal: 123,
    })
    expect(() => parseFeedbackV2Capture({ ...raw, workout_proof: null }, who)).toThrow()
    expect(() =>
      parseFeedbackV2Capture(
        { ...raw, confirmed: { ...p.confirmed, workout_protocol: undefined } },
        who,
      ),
    ).toThrow()
  })
  it('validates direct-key separately rather than passing it as a protected witness', () => {
    const c = context(),
      provider = 'synthetic-direct-key'
    const raw = {
      ...c,
      confirmed: {
        id: registrationId,
        user_id: owner,
        status: 'confirmed',
        proposal: {
          kind: 'workout',
          workoutType: 'caminhada',
          kcalEst: 999,
          source_provider_message_id: provider,
          source_timestamp: '2026-11-03T11:00:00Z',
          source_timezone: 'UTC',
          source_local_date: '2026-11-03',
        },
      },
      logs: [
        {
          id: fixtureFirst(c.logs).id,
          user_id: owner,
          snapshot_id: c.snapshot.id,
          raw_provider_message_id: provider,
          performed_at: '2026-11-03T11:00:00Z',
          workout_type: 'caminhada',
          duration_min: 30,
          intensity: 'moderada',
          estimated_kcal: 123,
        },
      ],
      workout_proof: {
        kind: 'direct-key',
        operation_key: provider,
        workout_id: fixtureFirst(c.logs).id,
      },
    }
    const who = { ...identity, kind: 'workout' as const }
    expect(parseFeedbackV2Capture(raw, who).facts.registration).toMatchObject({
      kind: 'workout',
      estimated_kcal: 123,
    })
    expect(() =>
      parseFeedbackV2Capture(
        { ...raw, workout_proof: { ...raw.workout_proof, operation_key: 'different' } },
        who,
      ),
    ).toThrow()
  })
  it('commits the untouched observation and accepts only the exact committed public DTO', async () => {
    const f = prepared(),
      c = parseFeedbackV2Capture(context(), identity),
      s = store({ action: 'committed', feedback: f })
    expect(await s.value.commit({ ...identity, observation: c, feedback: f })).toEqual({
      action: 'committed',
      feedback: f,
    })
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('commit_mobile_registration_feedback_v2', {
      p_user_id: owner,
      p_registration_id: registrationId,
      p_expected_context: c.context,
      p_feedback: f,
    })
    const different = store({
      action: 'committed',
      feedback: { ...f, locale: 'en', education: { status: 'unavailable' } },
    })
    await expect(
      different.value.commit({ ...identity, observation: c, feedback: f }),
    ).rejects.toThrow()
  })
  it.each([
    null,
    {},
    { action: 'available', feedback: null },
    { action: 'available', feedback: prepared(), context: 'private' },
    { action: 'absent', extra: true },
  ])('rejects malformed receipt envelopes (%#)', async (raw) => {
    await expect(store(raw).value.readReceipt(identity)).rejects.toThrow()
  })
  it('never exposes provider details and rejects invalid identity before I/O', async () => {
    const s = store(null, { message: 'private provider credential' })
    await expect(s.value.readReceipt(identity)).rejects.not.toThrow(/private|credential/)
    s.rpc.mockClear()
    await expect(s.value.readReceipt({ ...identity, userId: 'bad' })).rejects.toThrow()
    expect(s.rpc).not.toHaveBeenCalled()
  })
})
