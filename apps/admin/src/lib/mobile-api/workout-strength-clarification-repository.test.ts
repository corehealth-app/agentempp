import { describe, expect, it } from 'vitest'
import {
  createWorkoutStrengthClarificationRepository,
  type WorkoutStrengthClarificationPort,
} from './workout-strength-clarification-repository'

const ownerID = 'a1000000-0000-4000-8000-000000000001'
const workoutLogID = 'b2000000-0000-4000-8000-000000000001'
const expectedLifecycleKey = 'c3000000-0000-4000-8000-000000000001'
const questionKey = 'd4000000-0000-4000-8000-000000000001'
const otherOwner = 'a1000000-0000-4000-8000-000000000002'
const acceptedAt = '2026-10-21T01:02:03.123456Z'
function attempt() {
  return {
    ownerID,
    workoutLogID,
    expectedLifecycleKey,
    questionKey,
    expectedFactRevision: 0,
    answer: 'yes' as const,
    operationKey: 'wsa1:original-b',
  }
}
function reply(id = ownerID) {
  return {
    data: {
      status: 'accepted',
      receipt: {
        ownerID: id,
        workoutLogID,
        questionKey,
        answer: 'yes',
        operationKey: 'wsa1:winner-a',
        acceptedAt,
      },
    },
    error: null,
  }
}

describe('clarification narrow SQL port', () => {
  it('freezes the original attempt before await and does not bind receipt to the losing key', async () => {
    let finish!: (value: ReturnType<typeof reply>) => void
    const calls: unknown[] = []
    const port: WorkoutStrengthClarificationPort = {
      rpc(name, args) {
        calls.push({ name, args })
        return new Promise((resolve) => {
          finish = resolve
        })
      },
    }
    const input = attempt()
    const pending = createWorkoutStrengthClarificationRepository(port).answer(input)
    input.ownerID = otherOwner
    input.operationKey = 'changed-after-submit'
    input.expectedFactRevision = 1
    finish(reply())
    await expect(pending).resolves.toEqual(reply().data)
    expect(calls).toEqual([
      {
        name: 'answer_mobile_workout_strength_clarification',
        args: {
          p_user_id: ownerID,
          p_workout_log_id: workoutLogID,
          p_expected_lifecycle_key: expectedLifecycleKey,
          p_expected_fact_revision: 0,
          p_question_key: questionKey,
          p_answer: 'yes',
          p_operation_key: 'wsa1:original-b',
        },
      },
    ])
  })
  it('isolates concurrent owner replies even in reverse completion order', async () => {
    const finishes = new Map<string, (value: ReturnType<typeof reply>) => void>()
    const port: WorkoutStrengthClarificationPort = {
      rpc(_name, args) {
        return new Promise((resolve) => {
          finishes.set(args.p_user_id, resolve)
        })
      },
    }
    const repository = createWorkoutStrengthClarificationRepository(port)
    const a = repository.answer(attempt())
    const b = repository.answer({ ...attempt(), ownerID: otherOwner })
    const finishB = finishes.get(otherOwner)
    if (!finishB) throw new Error('Missing owner B request')
    finishB(reply(otherOwner))
    await expect(b).resolves.toEqual(reply(otherOwner).data)
    const finishA = finishes.get(ownerID)
    if (!finishA) throw new Error('Missing owner A request')
    finishA(reply())
    await expect(a).resolves.toEqual(reply().data)
  })
  it.each([
    null,
    {},
    { data: null },
    { error: null },
    { data: null, error: undefined },
  ])('refuses incomplete SDK envelopes %j', async (value) => {
    const port = { rpc: async () => value } as unknown as WorkoutStrengthClarificationPort
    await expect(
      createWorkoutStrengthClarificationRepository(port).read({ ownerID, workoutLogID }),
    ).rejects.toBeDefined()
  })
  it('propagates operational errors verbatim to the existing safe HTTP boundary', async () => {
    const error = { code: 'P0002', message: 'workout_strength_patient_not_found' }
    const port: WorkoutStrengthClarificationPort = { rpc: async () => ({ data: null, error }) }
    await expect(createWorkoutStrengthClarificationRepository(port).answer(attempt())).rejects.toBe(
      error,
    )
  })
})
