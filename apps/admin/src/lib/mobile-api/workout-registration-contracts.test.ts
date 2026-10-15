import { describe, expect, it } from 'vitest'
import {
  workoutRegistrationCreateSchema,
  workoutRegistrationEditSchema,
  workoutRegistrationSelectionSchema,
} from './workout-registration-contracts'

const input = {
  kind: 'workout',
  workout_type: ' Natação ',
  duration_min: 40,
  workout_protocol: 'ui-v1',
}

describe('explicit workout ui-v1 intent, additive to the legacy API', () => {
  it('retains the current type trim/intensity default and the supplied timestamp', () => {
    const performed_at = '2026-10-15T13:10:11.123456-03:00'
    expect(workoutRegistrationCreateSchema.parse({ ...input, performed_at })).toStrictEqual({
      ...input,
      workout_type: 'Natação',
      intensity: 'moderada',
      performed_at,
    })
  })

  it('requires the revision the patient reviewed on edit and selection', () => {
    expect(workoutRegistrationEditSchema.parse({ ...input, expected_revision: 0 })).toMatchObject({
      expected_revision: 0,
    })
    expect(
      workoutRegistrationSelectionSchema.parse({
        workout_protocol: 'ui-v1',
        expected_revision: 2147483647,
      }),
    ).toStrictEqual({ workout_protocol: 'ui-v1', expected_revision: 2147483647 })
  })

  it.each([
    undefined,
    null,
    -1,
    0.5,
    2147483648,
    '0',
    Number.NaN,
  ])('never invents or coerces expected_revision %#', (expected_revision) => {
    expect(workoutRegistrationEditSchema.safeParse({ ...input, expected_revision }).success).toBe(
      false,
    )
    expect(
      workoutRegistrationSelectionSchema.safeParse({ workout_protocol: 'ui-v1', expected_revision })
        .success,
    ).toBe(false)
  })

  it.each([
    { ...input, workout_protocol: undefined },
    { ...input, workout_protocol: null },
    { ...input, workout_protocol: 'legacy' },
    { ...input, kind: 'meal' },
    { ...input, ownerID: 'another-account' },
    { ...input, content_revision: 0 },
    { ...input, legacy_arguments: {} },
    { ...input, source_provider_message_id: 'spoof' },
    { ...input, expected_revision: 0 },
  ])('rejects unproved or client-owned backend fields on create %#', (value) => {
    expect(workoutRegistrationCreateSchema.safeParse(value).success).toBe(false)
  })

  it.each([
    {},
    { expected_revision: 0 },
    { workout_protocol: 'ui-v1', expected_revision: 0, ownerID: 'another-account' },
    { workout_protocol: 'ui-v1', expected_revision: 0, proposal: {} },
  ])('keeps confirm/cancel selection closed %#', (value) => {
    expect(workoutRegistrationSelectionSchema.safeParse(value).success).toBe(false)
  })
})
