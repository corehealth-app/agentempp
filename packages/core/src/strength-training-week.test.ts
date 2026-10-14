/**
 * C59a.1 Q15 contract specified before the separate implementation.
 * These tests exercise pure functions with synthetic trusted local-date
 * facts; they do not prove persistence, authentication, timezone/DST or UI.
 * Q15 final is authoritative; all three original goldens remain explicit.
 */
import { describe, expect, it } from 'vitest'
import {
  type EffectiveStrengthWeekSources,
  type ResolveStrengthWeekTargetInput,
  resolveStrengthWeekTarget,
  type StrengthTrainingWeekSummary,
  type StrengthWeekIssue,
  type StrengthWeekTargetRecord,
  type StrengthWeekWorkout,
  type SummarizeStrengthTrainingWeekInput,
  summarizeStrengthTrainingWeek,
} from './strength-training-week.js'

const OWNER = 'synthetic-owner-a'
const OTHER_OWNER = 'synthetic-owner-b'
const MONDAY = '2026-10-12'
const SUNDAY = '2026-10-18'
const NEXT_MONDAY = '2026-10-19'

function record(patch: Partial<StrengthWeekTargetRecord> = {}): StrengthWeekTargetRecord {
  return {
    ownerKey: OWNER,
    weekStartDate: MONDAY,
    plannedDays: 3,
    source: 'accepted_plan',
    sourceKey: 'accepted-plan-3-effective-2026-10-12',
    ...patch,
  }
}

function effective(
  patch: Partial<EffectiveStrengthWeekSources> = {},
): EffectiveStrengthWeekSources {
  return {
    ownerKey: OWNER,
    weekStartDate: MONDAY,
    plan: {
      ownerKey: OWNER,
      sourceKey: 'accepted-plan-3-effective-2026-10-12',
      state: 'accepted',
      daysPerWeek: 3,
    },
    informedFrequency: {
      ownerKey: OWNER,
      sourceKey: 'frequency-4-effective-2026-10-12',
      daysPerWeek: 4,
    },
    ...patch,
  }
}

function targetInput(
  patch: Partial<ResolveStrengthWeekTargetInput> = {},
): ResolveStrengthWeekTargetInput {
  return {
    scope: { ownerKey: OWNER, weekStartDate: MONDAY },
    existingRecord: null,
    effectiveSources: effective(),
    ...patch,
  }
}

function workout(
  workoutKey: string,
  localDate: string,
  patch: Partial<StrengthWeekWorkout> = {},
): StrengthWeekWorkout {
  return {
    ownerKey: OWNER,
    workoutKey,
    localDate,
    state: 'confirmed',
    catalogueCategory: 'musculacao',
    storedStrengthAnswer: null,
    ...patch,
  }
}

function summaryInput(
  patch: Partial<SummarizeStrengthTrainingWeekInput> = {},
): SummarizeStrengthTrainingWeekInput {
  return {
    scope: { ownerKey: OWNER, weekStartDate: MONDAY, asOfLocalDate: SUNDAY },
    persistedTarget: record(),
    workouts: [],
    ...patch,
  }
}

function expectedSummary(
  patch: Partial<StrengthTrainingWeekSummary> = {},
): StrengthTrainingWeekSummary {
  return {
    status: 'counted',
    completedStrengthDays: 0,
    plannedDays: 3,
    targetSource: 'accepted_plan',
    targetAvailability: 'available',
    percentage: 0,
    countedLocalDates: [],
    otherWorkoutKeys: [],
    unclassifiedWorkoutKeys: [],
    issues: [],
    ...patch,
  }
}

function expectInvalidSummary(input: SummarizeStrengthTrainingWeekInput, issue: StrengthWeekIssue) {
  const result = summarizeStrengthTrainingWeek(input)
  expect(result).toEqual({
    status: 'invalid_input',
    completedStrengthDays: null,
    plannedDays: null,
    targetSource: null,
    targetAvailability: 'unavailable',
    percentage: null,
    countedLocalDates: [],
    otherWorkoutKeys: [],
    unclassifiedWorkoutKeys: [],
    issues: expect.arrayContaining([issue]),
  })
}

describe('C59a.1 Q15 original goldens — explicit week-effective facts, no energy calculation', () => {
  it('G1: plan 3 days; Musculação Monday and Wednesday -> 2 de 3, 67%', () => {
    expect(resolveStrengthWeekTarget(targetInput())).toEqual({
      status: 'propose_new',
      record: record(),
      issues: [],
    })
    // A separate synthetic persisted record represents the later durable
    // winner. We deliberately do not pass the proposal as durability proof.
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({ workouts: [workout('monday', MONDAY), workout('wednesday', '2026-10-14')] }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 2,
        percentage: 67,
        countedLocalDates: [MONDAY, '2026-10-14'],
      }),
    )
  })

  it('G2: two strength records on one day -> 1; four days with Y3 -> 4 de 3, 100% without capping X', () => {
    const monday = [workout('monday-a', MONDAY), workout('monday-b', MONDAY)]
    expect(summarizeStrengthTrainingWeek(summaryInput({ workouts: monday }))).toEqual(
      expectedSummary({ completedStrengthDays: 1, percentage: 33, countedLocalDates: [MONDAY] }),
    )
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          workouts: [
            ...monday,
            workout('tuesday', '2026-10-13'),
            workout('wednesday', '2026-10-14'),
            workout('thursday', '2026-10-15'),
          ],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 4,
        percentage: 100,
        countedLocalDates: [MONDAY, '2026-10-13', '2026-10-14', '2026-10-15'],
      }),
    )
  })

  it('G3: frequency 4 changed to 3 Thursday -> current week X of 4, next week X of 3', () => {
    const currentPersisted = record({
      plannedDays: 4,
      source: 'informed_frequency',
      sourceKey: 'frequency-4-effective-2026-10-12',
    })
    const effectiveNextWeek = effective({
      weekStartDate: NEXT_MONDAY,
      plan: null,
      informedFrequency: {
        ownerKey: OWNER,
        sourceKey: 'thursday-change-3-effective-2026-10-19',
        daysPerWeek: 3,
      },
    })
    expect(
      resolveStrengthWeekTarget(
        targetInput({ existingRecord: currentPersisted, effectiveSources: effectiveNextWeek }),
      ),
    ).toEqual({ status: 'reuse_existing', record: currentPersisted, issues: [] })
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          scope: { ownerKey: OWNER, weekStartDate: MONDAY, asOfLocalDate: '2026-10-15' },
          persistedTarget: currentPersisted,
          workouts: [workout('monday', MONDAY), workout('wednesday', '2026-10-14')],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 2,
        plannedDays: 4,
        targetSource: 'informed_frequency',
        percentage: 50,
        countedLocalDates: [MONDAY, '2026-10-14'],
      }),
    )
    const nextPersisted = record({
      weekStartDate: NEXT_MONDAY,
      source: 'informed_frequency',
      sourceKey: 'thursday-change-3-effective-2026-10-19',
    })
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          scope: { ownerKey: OWNER, weekStartDate: NEXT_MONDAY },
          effectiveSources: effectiveNextWeek,
        }),
      ),
    ).toEqual({ status: 'propose_new', record: nextPersisted, issues: [] })
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          scope: { ownerKey: OWNER, weekStartDate: NEXT_MONDAY, asOfLocalDate: '2026-10-25' },
          persistedTarget: nextPersisted,
          workouts: [workout('next-monday', NEXT_MONDAY), workout('next-wednesday', '2026-10-21')],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 2,
        targetSource: 'informed_frequency',
        percentage: 67,
        countedLocalDates: [NEXT_MONDAY, '2026-10-21'],
      }),
    )
  })
})

describe('C59a.1 target authority — proposal only, never historical inference', () => {
  it.each([
    'draft',
    'cancelled',
  ] as const)('plan %s does not override effective informed frequency', (state) => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: { ownerKey: OWNER, sourceKey: 'not-accepted', state, daysPerWeek: 6 },
          }),
        }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({
        plannedDays: 4,
        source: 'informed_frequency',
        sourceKey: 'frequency-4-effective-2026-10-12',
      }),
      issues: [],
    })
  })

  it('accepted plan beats frequency even when planned days are zero; never invents a positive target', () => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'accepted-zero',
              state: 'accepted',
              daysPerWeek: 0,
            },
          }),
        }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({ plannedDays: 0, sourceKey: 'accepted-zero' }),
      issues: [],
    })
  })

  it('accepted plan with null days falls back to the same-owner frequency effective for this week', () => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'accepted-incomplete',
              state: 'accepted',
              daysPerWeek: null,
            },
          }),
        }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({
        plannedDays: 4,
        source: 'informed_frequency',
        sourceKey: 'frequency-4-effective-2026-10-12',
      }),
      issues: [],
    })
  })

  it('accepted plan with null days and explicit no frequency proposes absence, not unavailable or zero', () => {
    const plan = {
      ownerKey: OWNER,
      sourceKey: 'accepted-incomplete',
      state: 'accepted' as const,
      daysPerWeek: null,
    }
    for (const informedFrequency of [
      null,
      { ownerKey: OWNER, sourceKey: 'frequency-with-no-value', daysPerWeek: null },
    ]) {
      expect(
        resolveStrengthWeekTarget(
          targetInput({ effectiveSources: effective({ plan, informedFrequency }) }),
        ),
      ).toEqual({
        status: 'propose_new',
        record: record({ plannedDays: null, source: 'absent', sourceKey: null }),
        issues: [],
      })
    }
  })

  it('accepted plan with null days retains informed zero and a separately persisted zero has no percentage', () => {
    const frequency = {
      ownerKey: OWNER,
      sourceKey: 'frequency-zero-effective-2026-10-12',
      daysPerWeek: 0,
    }
    const persistedZero = record({
      plannedDays: 0,
      source: 'informed_frequency',
      sourceKey: frequency.sourceKey,
    })
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'accepted-incomplete',
              state: 'accepted',
              daysPerWeek: null,
            },
            informedFrequency: frequency,
          }),
        }),
      ),
    ).toEqual({ status: 'propose_new', record: persistedZero, issues: [] })
    // A separate synthetic persisted winner supplies publication authority;
    // this assertion does not establish persistence of the proposal above.
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({ persistedTarget: persistedZero, workouts: [workout('strength', MONDAY)] }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        plannedDays: 0,
        targetSource: 'informed_frequency',
        targetAvailability: 'zero',
        percentage: null,
        countedLocalDates: [MONDAY],
      }),
    )
  })

  it('accepted plan with null days cannot fall back to another owners frequency', () => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'accepted-incomplete',
              state: 'accepted',
              daysPerWeek: null,
            },
            informedFrequency: {
              ownerKey: OTHER_OWNER,
              sourceKey: 'foreign-frequency',
              daysPerWeek: 4,
            },
          }),
        }),
      ),
    ).toEqual({ status: 'invalid_input', record: null, issues: ['mixed_owner'] })
  })

  it('a valid frozen owner/week target wins without consuming later incomplete plan facts', () => {
    const persisted = record()
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          existingRecord: persisted,
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'later-incomplete-plan',
              state: 'accepted',
              daysPerWeek: null,
            },
          }),
        }),
      ),
    ).toEqual({ status: 'reuse_existing', record: persisted, issues: [] })
  })

  it.each([
    ['string', '4'],
    ['negative', -1],
    ['fraction', 2.5],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
    ['unsafe integer', Number.MAX_SAFE_INTEGER + 1],
  ] as const)('null accepted-plan target does not coerce invalid fallback frequency %s', (_label, value) => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: {
              ownerKey: OWNER,
              sourceKey: 'accepted-incomplete',
              state: 'accepted',
              daysPerWeek: null,
            },
            informedFrequency: {
              ownerKey: OWNER,
              sourceKey: 'invalid-frequency',
              daysPerWeek: value as unknown as number,
            },
          }),
        }),
      ),
    ).toEqual({ status: 'invalid_input', record: null, issues: ['invalid_target_value'] })
  })

  it('explicit effective absence freezes no denominator; unknown bootstrap sources do not manufacture absence', () => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({ effectiveSources: effective({ plan: null, informedFrequency: null }) }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({ plannedDays: null, source: 'absent', sourceKey: null }),
      issues: [],
    })
    expect(resolveStrengthWeekTarget(targetInput({ effectiveSources: null }))).toEqual({
      status: 'unavailable',
      record: null,
      issues: ['effective_sources_missing'],
    })
  })

  it('profile frequency null is explicit absence; frequency zero retains zero and its actual source', () => {
    const frequency = { ownerKey: OWNER, sourceKey: 'frequency-event', daysPerWeek: null }
    expect(
      resolveStrengthWeekTarget(
        targetInput({ effectiveSources: effective({ plan: null, informedFrequency: frequency }) }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({ plannedDays: null, source: 'absent', sourceKey: null }),
      issues: [],
    })
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            plan: null,
            informedFrequency: { ...frequency, daysPerWeek: 0 },
          }),
        }),
      ),
    ).toEqual({
      status: 'propose_new',
      record: record({
        plannedDays: 0,
        source: 'informed_frequency',
        sourceKey: 'frequency-event',
      }),
      issues: [],
    })
  })

  it('facts effective next Monday cannot bootstrap this week without an existing weekly record', () => {
    expect(
      resolveStrengthWeekTarget(
        targetInput({ effectiveSources: effective({ weekStartDate: NEXT_MONDAY }) }),
      ),
    ).toEqual({
      status: 'unavailable',
      record: null,
      issues: ['effective_week_mismatch'],
    })
  })

  it('existing weekly absence is immutable even when a plan is available later', () => {
    const frozenAbsent = record({ plannedDays: null, source: 'absent', sourceKey: null })
    expect(resolveStrengthWeekTarget(targetInput({ existingRecord: frozenAbsent }))).toEqual({
      status: 'reuse_existing',
      record: frozenAbsent,
      issues: [],
    })
  })

  it('repeated resolution reuses an identical persisted winner without creating another target', () => {
    const persisted = record()
    const input = targetInput({ existingRecord: persisted, effectiveSources: null })
    expect(resolveStrengthWeekTarget(input)).toEqual({
      status: 'reuse_existing',
      record: persisted,
      issues: [],
    })
    expect(resolveStrengthWeekTarget(input)).toEqual(resolveStrengthWeekTarget(input))
  })

  it.each([
    ['string', '3'],
    ['negative', -1],
    ['fraction', 2.5],
    ['NaN', Number.NaN],
    ['Infinity', Number.POSITIVE_INFINITY],
    ['unsafe integer', Number.MAX_SAFE_INTEGER + 1],
  ] as const)('invalid accepted-plan target %s is not coerced, rounded or replaced by frequency', (_label, value) => {
    const sources = effective({
      plan: {
        ownerKey: OWNER,
        sourceKey: 'invalid-plan',
        state: 'accepted',
        daysPerWeek: value as unknown as number,
      },
    })
    expect(resolveStrengthWeekTarget(targetInput({ effectiveSources: sources }))).toEqual({
      status: 'invalid_input',
      record: null,
      issues: ['invalid_target_value'],
    })
  })

  it('rejects mixed source owners and missing source references instead of authorising another account', () => {
    const source = effective({
      plan: { ownerKey: OTHER_OWNER, sourceKey: 'foreign-plan', state: 'accepted', daysPerWeek: 3 },
    })
    expect(resolveStrengthWeekTarget(targetInput({ effectiveSources: source }))).toEqual({
      status: 'invalid_input',
      record: null,
      issues: ['mixed_owner'],
    })
    expect(
      resolveStrengthWeekTarget(
        targetInput({
          effectiveSources: effective({
            informedFrequency: null,
            plan: { ownerKey: OWNER, sourceKey: '', state: 'accepted', daysPerWeek: 3 },
          }),
        }),
      ),
    ).toEqual({ status: 'invalid_input', record: null, issues: ['invalid_source_reference'] })
  })

  it('does not reuse a weekly record belonging to another owner or another week', () => {
    expect(
      resolveStrengthWeekTarget(targetInput({ existingRecord: record({ ownerKey: OTHER_OWNER }) })),
    ).toEqual({ status: 'invalid_input', record: null, issues: ['mixed_owner'] })
    expect(
      resolveStrengthWeekTarget(
        targetInput({ existingRecord: record({ weekStartDate: NEXT_MONDAY }) }),
      ),
    ).toEqual({ status: 'invalid_input', record: null, issues: ['record_week_mismatch'] })
  })
})

describe('C59a.1 confirmed-day projection — classification is an event fact', () => {
  it('known catalogue strength counts without requiring any current catalogue-active flag', () => {
    const event = workout('historical-confirmed-category', MONDAY)
    expect(event).not.toHaveProperty('isActive')
    expect(summarizeStrengthTrainingWeek(summaryInput({ workouts: [event] }))).toEqual(
      expectedSummary({ completedStrengthDays: 1, percentage: 33, countedLocalDates: [MONDAY] }),
    )
  })

  it('known category wins yes/no: musculacao + no counts; cardio + yes remains other activity', () => {
    const strength = workout('known-strength', MONDAY, {
      storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'known-strength', answer: 'no' },
    })
    const cardio = workout('known-cardio', '2026-10-13', {
      catalogueCategory: 'cardio',
      storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'known-cardio', answer: 'yes' },
    })
    expect(summarizeStrengthTrainingWeek(summaryInput({ workouts: [cardio, strength] }))).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        percentage: 33,
        countedLocalDates: [MONDAY],
        otherWorkoutKeys: ['known-cardio'],
      }),
    )
  })

  it('unknown type counts only persisted yes; persisted no is other, absent answer stays unclassified', () => {
    const unknownYes = workout('unknown-yes', MONDAY, {
      catalogueCategory: null,
      storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'unknown-yes', answer: 'yes' },
    })
    const unknownNo = workout('unknown-no', '2026-10-13', {
      catalogueCategory: null,
      storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'unknown-no', answer: 'no' },
    })
    const unanswered = workout('unknown-unanswered', '2026-10-14', { catalogueCategory: null })
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({ workouts: [unanswered, unknownYes, unknownNo] }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        percentage: 33,
        countedLocalDates: [MONDAY],
        otherWorkoutKeys: ['unknown-no'],
        unclassifiedWorkoutKeys: ['unknown-unanswered'],
      }),
    )
  })

  it('known non-strength categories stay separate and never increase X', () => {
    const events = (['cardio', 'esporte', 'mobilidade'] as const).map((category) =>
      workout(category, MONDAY, { catalogueCategory: category }),
    )
    expect(summarizeStrengthTrainingWeek(summaryInput({ workouts: events }))).toEqual(
      expectedSummary({ otherWorkoutKeys: ['cardio', 'esporte', 'mobilidade'] }),
    )
  })

  it('draft/pending and cancelled records do not count and do not create a yes/no question', () => {
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          workouts: [
            workout('pending', MONDAY, { state: 'pending', catalogueCategory: null }),
            workout('cancelled', '2026-10-13', { state: 'cancelled' }),
          ],
        }),
      ),
    ).toEqual(expectedSummary())
  })

  it('exact Monday and Sunday count; previous Sunday and next Monday are excluded', () => {
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          workouts: [
            workout('previous-sunday', '2026-10-11'),
            workout('monday', MONDAY),
            workout('sunday', SUNDAY),
            workout('next-monday', NEXT_MONDAY),
          ],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 2,
        percentage: 67,
        countedLocalDates: [MONDAY, SUNDAY],
      }),
    )
  })

  it('future dates within the same week do not count before the observed local date', () => {
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          scope: { ownerKey: OWNER, weekStartDate: MONDAY, asOfLocalDate: '2026-10-14' },
          workouts: [workout('monday', MONDAY), workout('future-thursday', '2026-10-15')],
        }),
      ),
    ).toEqual(
      expectedSummary({ completedStrengthDays: 1, percentage: 33, countedLocalDates: [MONDAY] }),
    )
  })

  it('a civil week crossing a year boundary keeps seven local dates; this is not a timezone/DST test', () => {
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          scope: { ownerKey: OWNER, weekStartDate: '2026-12-28', asOfLocalDate: '2027-01-03' },
          persistedTarget: record({ weekStartDate: '2026-12-28' }),
          workouts: [
            workout('december', '2026-12-28'),
            workout('january', '2027-01-03'),
            workout('next-week', '2027-01-04'),
          ],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 2,
        percentage: 67,
        countedLocalDates: ['2026-12-28', '2027-01-03'],
      }),
    )
  })

  it('identical IDs are idempotent and input order does not change the projection', () => {
    const first = workout('a', MONDAY)
    const second = workout('b', '2026-10-14')
    const input = summaryInput({ workouts: [second, first, { ...first }] })
    const before = JSON.stringify(input)
    const expected = expectedSummary({
      completedStrengthDays: 2,
      percentage: 67,
      countedLocalDates: [MONDAY, '2026-10-14'],
    })
    expect(summarizeStrengthTrainingWeek(input)).toEqual(expected)
    expect(
      summarizeStrengthTrainingWeek({ ...input, workouts: [...input.workouts].reverse() }),
    ).toEqual(expected)
    expect(JSON.stringify(input)).toBe(before)
  })

  it('conflicting duplicate IDs with different dates fail without publishing a partial count', () => {
    expectInvalidSummary(
      summaryInput({ workouts: [workout('same', MONDAY), workout('same', '2026-10-13')] }),
      'conflicting_workout_duplicate',
    )
  })

  it.each([
    ['category', workout('same', MONDAY), workout('same', MONDAY, { catalogueCategory: 'cardio' })],
    ['state', workout('same', MONDAY), workout('same', MONDAY, { state: 'cancelled' })],
    [
      'persisted answer',
      workout('same', MONDAY, {
        catalogueCategory: null,
        storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'same', answer: 'yes' },
      }),
      workout('same', MONDAY, {
        catalogueCategory: null,
        storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'same', answer: 'no' },
      }),
    ],
  ] as const)('same owner/ID/date with conflicting %s withholds every counter in both input orders', (_label, first, second) => {
    const events = [workout('otherwise-countable', '2026-10-14'), first, second]
    expectInvalidSummary(summaryInput({ workouts: events }), 'conflicting_workout_duplicate')
    expectInvalidSummary(
      summaryInput({ workouts: [...events].reverse() }),
      'conflicting_workout_duplicate',
    )
  })

  it('same-day strength and cardio preserve one strength day plus the separate other activity', () => {
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          workouts: [
            workout('strength', MONDAY),
            workout('cardio', MONDAY, { catalogueCategory: 'cardio' }),
          ],
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        percentage: 33,
        countedLocalDates: [MONDAY],
        otherWorkoutKeys: ['cardio'],
      }),
    )
  })

  it('no weekly record, frozen absence and frozen zero never manufacture a denominator or percentage', () => {
    const workouts = [workout('strength', MONDAY)]
    expect(
      summarizeStrengthTrainingWeek(summaryInput({ persistedTarget: null, workouts })),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        plannedDays: null,
        targetSource: null,
        targetAvailability: 'not_frozen',
        percentage: null,
        countedLocalDates: [MONDAY],
      }),
    )
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({
          persistedTarget: record({ source: 'absent', plannedDays: null, sourceKey: null }),
          workouts,
        }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        plannedDays: null,
        targetSource: 'absent',
        targetAvailability: 'absent',
        percentage: null,
        countedLocalDates: [MONDAY],
      }),
    )
    expect(
      summarizeStrengthTrainingWeek(
        summaryInput({ persistedTarget: record({ plannedDays: 0 }), workouts }),
      ),
    ).toEqual(
      expectedSummary({
        completedStrengthDays: 1,
        plannedDays: 0,
        targetAvailability: 'zero',
        percentage: null,
        countedLocalDates: [MONDAY],
      }),
    )
  })

  it('a known positive target with no workouts is a confirmed empty count, not missing target data', () => {
    expect(summarizeStrengthTrainingWeek(summaryInput())).toEqual(expectedSummary())
  })

  it('mixed workout or target owner fails without leaking a partial counter', () => {
    expectInvalidSummary(
      summaryInput({
        workouts: [
          workout('own', MONDAY),
          workout('foreign', '2026-10-13', { ownerKey: OTHER_OWNER }),
        ],
      }),
      'mixed_owner',
    )
    expectInvalidSummary(
      summaryInput({ persistedTarget: record({ ownerKey: OTHER_OWNER }) }),
      'mixed_owner',
    )
  })

  it('unknown answer from another owner or another workout cannot authorise strength classification', () => {
    expectInvalidSummary(
      summaryInput({
        workouts: [
          workout('unknown', MONDAY, {
            catalogueCategory: null,
            storedStrengthAnswer: { ownerKey: OTHER_OWNER, workoutKey: 'unknown', answer: 'yes' },
          }),
        ],
      }),
      'mixed_owner',
    )
    expectInvalidSummary(
      summaryInput({
        workouts: [
          workout('unknown', MONDAY, {
            catalogueCategory: null,
            storedStrengthAnswer: { ownerKey: OWNER, workoutKey: 'different', answer: 'yes' },
          }),
        ],
      }),
      'stored_answer_workout_mismatch',
    )
  })

  it('unknown answer outside persisted yes/no is invalid, not a truthy yes', () => {
    const event = workout('unknown', MONDAY, {
      catalogueCategory: null,
      storedStrengthAnswer: {
        ownerKey: OWNER,
        workoutKey: 'unknown',
        answer: true as unknown as 'yes',
      },
    })
    expectInvalidSummary(summaryInput({ workouts: [event] }), 'invalid_stored_answer')
  })

  it('unknown category text is not inferred from a name and is not silently treated as musculacao', () => {
    expectInvalidSummary(
      summaryInput({
        workouts: [
          workout('invalid', MONDAY, { catalogueCategory: 'forca' as unknown as 'musculacao' }),
        ],
      }),
      'invalid_catalogue_category',
    )
  })

  it.each([
    '2026-02-30',
    '2026-2-03',
    '2026-10-12T00:00:00Z',
  ])('rejects invalid civil workout date %s without timezone conversion', (localDate) => {
    expectInvalidSummary(
      summaryInput({ workouts: [workout('invalid-date', localDate)] }),
      'invalid_workout_date',
    )
  })

  it('rejects a non-Monday week, observation outside the week and mismatched target week', () => {
    expectInvalidSummary(
      summaryInput({
        scope: { ownerKey: OWNER, weekStartDate: '2026-10-13', asOfLocalDate: '2026-10-14' },
      }),
      'invalid_week',
    )
    expectInvalidSummary(
      summaryInput({
        scope: { ownerKey: OWNER, weekStartDate: MONDAY, asOfLocalDate: NEXT_MONDAY },
      }),
      'invalid_observation_date',
    )
    expectInvalidSummary(
      summaryInput({ persistedTarget: record({ weekStartDate: NEXT_MONDAY }) }),
      'record_week_mismatch',
    )
  })

  it('rejects invalid frozen target structure instead of normalising it into a fabricated value', () => {
    expectInvalidSummary(
      summaryInput({
        persistedTarget: record({ source: 'absent', plannedDays: 3, sourceKey: null }),
      }),
      'invalid_target_record',
    )
    expectInvalidSummary(
      summaryInput({ persistedTarget: record({ plannedDays: Number.NaN }) }),
      'invalid_target_value',
    )
  })

  it('missing owner, workout key and invalid workout state do not produce a count', () => {
    expectInvalidSummary(
      summaryInput({ scope: { ownerKey: ' ', weekStartDate: MONDAY, asOfLocalDate: SUNDAY } }),
      'invalid_owner',
    )
    expectInvalidSummary(summaryInput({ workouts: [workout('', MONDAY)] }), 'invalid_workout_key')
    expectInvalidSummary(
      summaryInput({
        workouts: [workout('invalid', MONDAY, { state: 'accepted' as unknown as 'confirmed' })],
      }),
      'invalid_workout_state',
    )
  })

  it('A to B to A is local to its inputs; the other account never changes A', () => {
    const a = summaryInput({ workouts: [workout('a', MONDAY)] })
    const b = summaryInput({
      scope: { ownerKey: OTHER_OWNER, weekStartDate: MONDAY, asOfLocalDate: SUNDAY },
      persistedTarget: record({ ownerKey: OTHER_OWNER, plannedDays: 4 }),
      workouts: [],
    })
    const before = JSON.stringify(a)
    const first = summarizeStrengthTrainingWeek(a)
    expect(summarizeStrengthTrainingWeek(b)).toEqual(expectedSummary({ plannedDays: 4 }))
    expect(summarizeStrengthTrainingWeek(a)).toEqual(first)
    expect(first).toEqual(
      expectedSummary({ completedStrengthDays: 1, percentage: 33, countedLocalDates: [MONDAY] }),
    )
    expect(JSON.stringify(a)).toBe(before)
  })
})
