import { describe, expect, it } from 'vitest'
import { legacyFeedback } from './__fixtures__/feedback-v2-source'
import {
  frozenMealV3Capture,
  linkedMealV3Capture,
  pendingV3Capture,
  workoutV3Capture,
} from './__fixtures__/feedback-v3-source'
import {
  parseCanonicalRegistrationFeedback,
  parseFeedbackV3Capture,
} from './registration-feedback-v3-contracts'

describe('feedback v3 authoritative source boundary', () => {
  it('accepts an actual pending source without turning it into conversational workout provenance', () => {
    const f = pendingV3Capture()
    expect(() => parseFeedbackV3Capture(f.context, f.who)).not.toThrow()
    const value = parseFeedbackV3Capture(f.context, f.who)
    expect(value.registration).toEqual(f.context.record)
    expect(value.energyComplete).toBe(true)
    expect(value.localDate).toBe(f.context.local_date)
    expect(Object.isFrozen(value.context.snapshot)).toBe(true)
  })
  it.each([
    'known',
    'unknown',
  ] as const)('reuses the actual PostgreSQL %s own-workout receipt/source/strength decoder', (kind) => {
    const f = workoutV3Capture(kind),
      value = parseFeedbackV3Capture(f.context, f.who)
    expect(value.registration).toEqual(f.context.record)
    expect(value.energyComplete).toBe(kind === 'known')
    expect(f.context.source.effect.receipt.provenance).toBe('conversation.workout.v1')
  })
  it('detaches source aliases before awaits', () => {
    const f = pendingV3Capture(),
      value = parseFeedbackV3Capture(f.context, f.who)
    f.context.snapshot.exercise_energy_complete = false
    if (f.context.record.kind !== 'meal') throw new Error('Expected meal fixture')
    f.context.record.totals.kcal = 9
    expect(value.energyComplete).toBe(true)
    expect(value.registration).not.toEqual(f.context.record)
  })
  it.each([
    (c: Record<string, unknown>) => {
      c.user_id = '99999999-0000-4000-8000-000000000001'
    },
    (c: Record<string, unknown>) => {
      c.registration_id = '99999999-0000-4000-8000-000000000001'
    },
    (c: Record<string, unknown>) => {
      c.origin = 'pending_registration'
    },
    (c: Record<string, unknown>) => {
      ;(c.snapshot as Record<string, unknown>).user_id = '99999999-0000-4000-8000-000000000001'
    },
    (c: Record<string, unknown>) => {
      ;(c.snapshot as Record<string, unknown>).date = '2026-10-01'
    },
    (c: Record<string, unknown>) => {
      delete (c.snapshot as Record<string, unknown>).exercise_energy_complete
    },
    (c: Record<string, unknown>) => {
      ;(c.source as Record<string, unknown>).kind = 'ui-v1'
    },
    (c: Record<string, unknown>) => {
      ;(c.record as Record<string, unknown>).estimated_kcal = 400
    },
  ])('refuses foreign identity, missing coverage and invented workout protocol/energy', (mutate) => {
    const f = workoutV3Capture('unknown')
    mutate(f.context as unknown as Record<string, unknown>)
    expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
  })
  it('treats a saved false witness as unavailable even when the observed owned set is known', () => {
    const f = pendingV3Capture()
    f.context.snapshot.exercise_energy_complete = false
    expect(parseFeedbackV3Capture(f.context, f.who).energyComplete).toBe(false)
  })
  it('refuses a foreign or duplicated day workout row instead of calling it coverage proof', () => {
    const f = workoutV3Capture('known')
    const row = f.context.logs[0]
    ;(f.context as Record<string, unknown>).day_workouts = [row, row]
    expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
  })
  it('dispatches a historical v1 receipt exactly only for its actual pending origin', () => {
    const f = pendingV3Capture(),
      old = legacyFeedback()
    expect(parseCanonicalRegistrationFeedback(old, f.who)).toEqual(old)
    expect(() =>
      parseCanonicalRegistrationFeedback(old, { ...f.who, origin: 'conversation_workout' }),
    ).toThrow()
    expect(old.schema).toBe('registration.feedback.v1')
  })
})

describe('frozen conversational meal source stays historical', () => {
  it('retains unproved historical coverage instead of inheriting the current SQL default', () => {
    const f = frozenMealV3Capture()
    delete (f.context.snapshot as Record<string, unknown>).exercise_energy_complete
    expect(parseFeedbackV3Capture(f.context, f.who)).toMatchObject({
      energyComplete: null,
      energyUnavailableReason: 'source_unavailable',
    })
  })
  it.each([
    true,
    false,
  ])('retains the original post-core coverage %s without a current workout recapture', (marker) => {
    const f = frozenMealV3Capture()
    f.context.snapshot.exercise_energy_complete = marker
    expect(parseFeedbackV3Capture(f.context, f.who)).toMatchObject({
      energyComplete: marker,
      energyUnavailableReason: marker ? null : 'unknown_workout_energy',
    })
  })
  it('requires command metadata for every frozen snapshot exception and every conversational proposal', () => {
    const f = frozenMealV3Capture()
    f.context.source.command = null as never
    expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
    const live = pendingV3Capture()
    delete (live.context.snapshot as Record<string, unknown>).exercise_energy_complete
    expect(() => parseFeedbackV3Capture(live.context, live.who)).toThrow()
  })
  it('refuses a foreign/original-identity mismatch and an invented frozen energy marker', () => {
    const f = frozenMealV3Capture()
    f.context.source.command.receipt.registration_id = '99999999-0000-4000-8000-000000000001'
    expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
    const g = frozenMealV3Capture()
    g.context.snapshot.exercise_energy_complete = null as never
    expect(() => parseFeedbackV3Capture(g.context, g.who)).toThrow()
  })
})

it('keeps own-workout original snapshot after later source changes instead of a new current capture', () => {
  const f = workoutV3Capture('unknown')
  expect(parseFeedbackV3Capture(f.context, f.who).energyComplete).toBe(false)
  f.context.snapshot.exercise_energy_complete = true
  expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
})

it('decodes the complete real rollback PostgreSQL workout and historical meal captures with v3 wire', async () => {
  const golden = await import('./testing/registration-feedback-v3-pg-golden.json')
  for (const row of golden.feedback_v3_actual_golden) {
    const c = row.context
    const who = {
      userId: c.user_id,
      registrationId: c.registration_id,
      kind: c.record.kind === 'meal' ? ('meal' as const) : ('workout' as const),
      origin:
        c.origin === 'pending_registration'
          ? ('pending_registration' as const)
          : ('conversation_workout' as const),
    }
    const observation = parseFeedbackV3Capture(c, who)
    expect(observation.registration).toEqual(row.feedback.registration)
    expect(observation.energyComplete).toBe(
      row.kind === 'unknown_workout' ? false : row.kind === 'precoverage_meal' ? null : true,
    )
    expect(parseCanonicalRegistrationFeedback(row.feedback, who)).toEqual(row.feedback)
  }
})

it('reuses the real linked receipt/parent binding contract and preserves its own protocol namespace', () => {
  const f = linkedMealV3Capture()
  expect(parseFeedbackV3Capture(f.context, f.who)).toMatchObject({
    registration: f.context.record,
    energyComplete: true,
  })
  const foreign = linkedMealV3Capture()
  foreign.context.source.command.continuation.parentBinding.command_id =
    foreign.context.source.command.command_id
  expect(() => parseFeedbackV3Capture(foreign.context, foreign.who)).toThrow()
  const invented = linkedMealV3Capture()
  invented.context.source.command.continuation.receipt.provider_key = `conversation.meal/${f.who.userId}/${f.context.source.command.command_id}`
  expect(() => parseFeedbackV3Capture(invented.context, invented.who)).toThrow()
})

it('requires the post-core coverage witness for own-workout provenance even if both supplied aliases omit it', () => {
  const f = workoutV3Capture('unknown')
  delete (f.context.snapshot as Record<string, unknown>).exercise_energy_complete
  delete (f.context.source.feedback_context.snapshot as Record<string, unknown>)
    .exercise_energy_complete
  expect(() => parseFeedbackV3Capture(f.context, f.who)).toThrow()
})
