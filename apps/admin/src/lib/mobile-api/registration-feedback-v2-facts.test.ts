import { describe, expect, it } from 'vitest'
import protectedWorkout from './__fixtures__/feedback-v2-protected-qa.json'
import { projectRegistrationFeedbackV2Facts } from './registration-feedback-v2-facts'

const OWNER = '10000000-0000-4000-8000-000000000001'
const OTHER = '10000000-0000-4000-8000-000000000002'
const ID = '20000000-0000-4000-8000-000000000001'
const LOG = '30000000-0000-4000-8000-000000000001'
function meal() {
  return {
    userId: OWNER,
    registrationId: ID,
    confirmed: {
      id: ID,
      user_id: OWNER,
      status: 'confirmed',
      proposal: {
        kind: 'meal',
        mealType: 'cafe',
        source_provider_message_id: 'owned-provider-key',
        source_timestamp: '2026-11-03T11:00:00Z',
        source_timezone: 'America/Sao_Paulo',
        source_local_date: '2026-11-03',
        totals: { kcal: 126.123, protein_g: 6.3, carbs_g: 9.5, fat_g: 6.5 },
        items: [
          {
            name: 'leite integral',
            quantity_g: 206,
            display_qty: 206,
            display_unit: 'g',
            quantity_basis: 'portion_reference',
            nutrition_source: 'canonical_exact',
            kcal: 126.123,
            protein_g: 6.3,
            carbs_g: 9.5,
            fat_g: 6.5,
          },
        ],
      },
    },
    logs: [
      {
        id: LOG,
        user_id: OWNER,
        raw_provider_message_id: 'owned-provider-key',
        consumed_at: '2026-11-03T11:00:00Z',
        meal_type: 'cafe',
        food_name: 'leite integral',
        quantity_g: 206,
        kcal: 126.12,
        protein_g: 6.3,
        carbs_g: 9.5,
        fat_g: 6.5,
        source: 'canonical_exact',
      },
    ],
  }
}
function workout() {
  return {
    userId: OWNER,
    registrationId: ID,
    confirmed: {
      id: ID,
      user_id: OWNER,
      status: 'confirmed',
      confirmedWorkoutId: LOG,
      proposal: {
        kind: 'workout',
        workoutType: 'caminhada',
        durationMin: 30,
        intensity: 'moderada',
        kcalEst: 999,
        source_provider_message_id: 'owned-workout-key',
        source_timestamp: '2026-11-03T11:00:00Z',
        source_timezone: 'America/Sao_Paulo',
        source_local_date: '2026-11-03',
      },
    },
    logs: [
      {
        id: LOG,
        user_id: OWNER,
        raw_provider_message_id: 'owned-workout-key',
        performed_at: '2026-11-03T11:00:00Z',
        workout_type: 'caminhada',
        duration_min: 30,
        intensity: 'moderada',
        estimated_kcal: 123,
      },
    ],
  }
}

describe('feedback v2 persisted facts', () => {
  it('uses the saved item value separately from the original canonical summary', () => {
    const result = projectRegistrationFeedbackV2Facts(meal())
    expect(result?.registration.kind === 'meal' && result.registration.items[0]?.kcal).toBe(126.12)
    expect(result?.registration.kind === 'meal' && result.registration.totals.kcal).toBe(126.123)
  })
  it('accepts the real protected SQL capture without treating its operation key as a legacy key', () => {
    expect(projectRegistrationFeedbackV2Facts(protectedWorkout)?.registration).toMatchObject({
      kind: 'workout',
      workout_type: 'qa-feedback-v2-activity',
      estimated_kcal: 123,
    })
  })
  it('never downgrades a protected workout whose witness was lost', () => {
    expect(
      projectRegistrationFeedbackV2Facts({ ...protectedWorkout, workoutProof: undefined }),
    ).toBeNull()
  })
  it('rejects a protected capture tied to another operation or another owner', () => {
    const wrongOperation = structuredClone(protectedWorkout)
    wrongOperation.workoutProof.operation_key += '-different'
    expect(projectRegistrationFeedbackV2Facts(wrongOperation)).toBeNull()
    const wrongOwner = structuredClone(protectedWorkout)
    wrongOwner.workoutProof.resolver.binding.ownerID = OTHER
    expect(projectRegistrationFeedbackV2Facts(wrongOwner)).toBeNull()
  })
  it('retains saved activity facts for the exact legacy provenance gap without inventing classification', () => {
    const log = protectedWorkout.logs[0]
    if (!log) throw new Error('Fixture')
    const request = {
      ...protectedWorkout,
      workoutProof: {
        ...protectedWorkout.workoutProof,
        resolver: {
          status: 'unavailable',
          reason: 'legacy_provenance_gap',
          confirmedWorkoutLogID: log.id,
        },
      },
    }
    const projected = projectRegistrationFeedbackV2Facts(request)
    expect(projected?.registration).toMatchObject({
      kind: 'workout',
      log_id: log.id,
      estimated_kcal: 123,
    })
    expect(projected?.registration).not.toHaveProperty('classification')
    request.workoutProof.resolver.confirmedWorkoutLogID = OTHER
    expect(projectRegistrationFeedbackV2Facts(request)).toBeNull()
  })
  it('binds a confirmed proposal to its owned rows and preserves its canonical decimal total', () => {
    const result = projectRegistrationFeedbackV2Facts(meal())
    expect(result?.logIds).toEqual([LOG])
    expect(result?.localDate).toBe('2026-11-03')
    expect(result?.registration).toMatchObject({
      kind: 'meal',
      totals: { kcal: 126.123 },
      items: [
        {
          log_id: LOG,
          food_name: 'leite integral',
          quantity_g: 206,
          kcal: 126.12,
          quantity: {
            value: 200,
            unit: 'mL',
            estimated: true,
            reference_id: 'fao-infoods-v2-whole-milk-tb',
          },
        },
      ],
    })
  })
  it('shows a whey measure using the existing editable reference rather than requiring grams again', () => {
    const request = meal()
    const original = request.confirmed.proposal.items[0]
    const log = request.logs[0]
    if (!original || !log) throw new Error('Fixture')
    original.name = log.food_name = 'whey protein'
    original.quantity_g = log.quantity_g = 30
    const result = projectRegistrationFeedbackV2Facts(request)
    expect(
      result?.registration.kind === 'meal' && result.registration.items[0]?.quantity,
    ).toMatchObject({ value: 1, unit: 'scoop', estimated: true })
  })
  it('uses the persisted workout expenditure and identity instead of the proposed estimate', () => {
    expect(projectRegistrationFeedbackV2Facts(workout())?.registration).toEqual({
      kind: 'workout',
      log_id: LOG,
      workout_type: 'caminhada',
      duration_min: 30,
      intensity: 'moderada',
      estimated_kcal: 123,
    })
  })
  it.each([
    'owner',
    'event',
    'pending',
    'provider',
    'date',
    'modified',
    'source',
    'extra-row',
    'missing-row',
  ] as const)('omits meal enrichment when %s proof is unavailable', (reason) => {
    const request = meal()
    const log = request.logs[0]
    if (!log) throw new Error('Fixture')
    if (reason === 'owner') log.user_id = OTHER
    if (reason === 'event') request.confirmed.id = LOG
    if (reason === 'pending') request.confirmed.status = 'pending'
    if (reason === 'provider') log.raw_provider_message_id = 'another-event'
    if (reason === 'date') log.consumed_at = '2026-11-04T11:00:00Z'
    if (reason === 'modified') log.kcal = 190
    if (reason === 'source') log.source = 'no_match'
    if (reason === 'extra-row') request.logs.push({ ...log, id: OTHER })
    if (reason === 'missing-row') request.logs = []
    expect(projectRegistrationFeedbackV2Facts(request)).toBeNull()
  })
  it('requires an explicitly owned confirmed row, never an omitted owner', () => {
    const request = meal()
    expect(
      projectRegistrationFeedbackV2Facts({
        ...request,
        confirmed: { ...request.confirmed, user_id: undefined },
      }),
    ).toBeNull()
  })
  it('does not choose the newest of ambiguous workout logs', () => {
    const request = workout()
    const log = request.logs[0]
    if (!log) throw new Error('Fixture')
    request.logs.push({ ...log, id: OTHER })
    expect(projectRegistrationFeedbackV2Facts(request)).toBeNull()
  })
  it('rejects conflicting source timestamp/local date before using any context', () => {
    const request = meal()
    request.confirmed.proposal.source_local_date = '2026-11-02'
    expect(projectRegistrationFeedbackV2Facts(request)).toBeNull()
  })
})
