import { describe, expect, it } from 'vitest'
import * as leaf from './workout-strength-clarification.js'

const ownerID = 'a1000000-0000-4000-8000-000000000001'
const workoutLogID = 'b2000000-0000-4000-8000-000000000001'
const lifecycleKey = 'c3000000-0000-4000-8000-000000000001'
const questionKey = 'd4000000-0000-4000-8000-000000000001'
const other = 'e5000000-0000-4000-8000-000000000001'
const anchor = { ownerID, workoutLogID }
const attempt = {
  ...anchor,
  expectedLifecycleKey: lifecycleKey,
  expectedFactRevision: 0,
  questionKey,
  answer: 'yes' as const,
  operationKey: 'wsa1:attempt-b',
}
function receipt() {
  return {
    ...anchor,
    questionKey,
    answer: 'yes',
    operationKey: 'wsa1:winning-a',
    acceptedAt: '2026-10-21T01:02:03.123456Z',
  }
}
function wire(status: 'unanswered' | 'answered' | 'not_applicable' = 'unanswered') {
  return {
    status: 'available',
    workoutLogID,
    lifecycleKey,
    factRevision: status === 'answered' ? 1 : 0,
    clarification:
      status === 'answered'
        ? { status, receipt: receipt() }
        : status === 'unanswered'
          ? { status, questionKey }
          : { status },
  }
}

describe('pure current-workout clarification wire', () => {
  it('exports only the two pure decoders, with no repository or RPC factory', () => {
    expect(Object.keys(leaf).sort()).toEqual([
      'parseWorkoutStrengthAnswerReply',
      'parseWorkoutStrengthClarification',
    ])
  })
  it.each([
    'unanswered',
    'answered',
    'not_applicable',
  ] as const)('preserves %s literally', (status) => {
    const input = wire(status)
    const original = structuredClone(input)
    expect(leaf.parseWorkoutStrengthClarification(input, anchor)).toEqual(original)
    expect(input).toEqual(original)
  })
  it.each([
    { status: 'unavailable', reason: 'provenance_gap' },
    { status: 'forbidden', reason: 'stale_lifecycle' },
    { status: 'forbidden', reason: 'stale_workout' },
  ])('accepts a closed negative without inventing identity: %j', (input) => {
    expect(leaf.parseWorkoutStrengthClarification(input, anchor)).toEqual(input)
  })
  it.each([
    null,
    [],
    {},
    { ...wire(), workoutLogID: other },
    { ...wire(), lifecycleKey: 'invalid' },
    { ...wire(), lifecycleKey: lifecycleKey.toUpperCase() },
    { ...wire(), ownerID },
    { ...wire(), factRevision: 1 },
    { ...wire('answered'), factRevision: 0 },
    { ...wire('not_applicable'), factRevision: 1 },
    { ...wire(), factRevision: '0' },
    { ...wire(), clarification: { status: 'unanswered', questionKey, answer: 'yes' } },
    { ...wire(), clarification: { status: 'unanswered', questionKey: null } },
    { ...wire(), clarification: { status: 'not_applicable', questionKey } },
    {
      ...wire('answered'),
      clarification: { status: 'answered', receipt: { ...receipt(), ownerID: other } },
    },
    {
      ...wire('answered'),
      clarification: { status: 'answered', receipt: { ...receipt(), workoutLogID: other } },
    },
    { status: 'unavailable', reason: 'legacy_provenance_gap' },
    { status: 'unavailable', reason: 'provenance_gap', workoutLogID },
    { status: 'forbidden', reason: 'mixed_owner' },
  ])('rejects incoherent, foreign, partial or extra-key GET output: %j', (input) => {
    expect(() => leaf.parseWorkoutStrengthClarification(input, anchor)).toThrow(TypeError)
  })
  it.each([
    '2026-10-21T01:02:03.123Z',
    '2026-10-21T01:02:03.123456+00:00',
    '2026-02-29T01:02:03.123456Z',
    '0000-10-21T01:02:03.123456Z',
    '2026-10-21T24:02:03.123456Z',
  ])('rejects noncanonical or impossible acceptedAt %s', (acceptedAt) => {
    const input = {
      ...wire('answered'),
      clarification: { status: 'answered', receipt: { ...receipt(), acceptedAt } },
    }
    expect(() => leaf.parseWorkoutStrengthClarification(input, anchor)).toThrow(TypeError)
  })
  it.each([
    'accepted',
    'reuse_existing',
  ])('accepts %s with winning A receipt for B revision0', (status) => {
    const input = { status, receipt: receipt() }
    expect(leaf.parseWorkoutStrengthAnswerReply(input, attempt)).toEqual(input)
  })
  it.each([
    { ...receipt(), questionKey: other },
    { ...receipt(), answer: 'no' },
    { ...receipt(), ownerID: other },
    { ...receipt(), workoutLogID: other },
    { ...receipt(), operationKey: '' },
    { ...receipt(), extra: true },
  ])('rejects a POST receipt that does not prove the attempt: %j', (value) => {
    expect(() =>
      leaf.parseWorkoutStrengthAnswerReply({ status: 'accepted', receipt: value }, attempt),
    ).toThrow(TypeError)
  })
  it.each([
    ['conflict', 'answer_already_differs'],
    ['conflict', 'operation_content_conflict'],
    ['forbidden', 'mixed_owner'],
    ['forbidden', 'stale_workout'],
    ['forbidden', 'stale_lifecycle'],
    ['conflict', 'stale_fact'],
    ['not_available', 'not_unrecognized'],
  ])('preserves S9 negative %s/%s', (status, reason) => {
    const input = { status, reason }
    expect(leaf.parseWorkoutStrengthAnswerReply(input, attempt)).toEqual(input)
    expect(() =>
      leaf.parseWorkoutStrengthAnswerReply({ ...input, receipt: receipt() }, attempt),
    ).toThrow(TypeError)
  })
})
