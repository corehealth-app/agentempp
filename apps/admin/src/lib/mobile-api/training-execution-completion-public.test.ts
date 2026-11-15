import { describe, expect, it } from 'vitest'
import golden from './testing/training-completion-pg-golden.json'
import { bindTrainingExecutionCompletion } from './training-execution-completion-contracts'
import { projectTrainingExecutionCompletion } from './training-execution-completion-public'
import { readTrainingExecutionSession } from './training-execution-kernel'

function capture() {
  const g = structuredClone(golden)
  const bound = bindTrainingExecutionCompletion(
    g.begin.scope.owner_id,
    `tfinish1:${g.command.operation_id}`,
    g.command,
  )
  return { g, bound, auth: g.begin.scope.auth_user_id }
}
describe('whitelisted public completion from protected original SQL facts', () => {
  it('exposes actual performed values and one linked receipt without clinical capture, frozen state or private source', () => {
    const { g, bound, auth } = capture()
    const value = projectTrainingExecutionCompletion(g.completed, bound, auth)
    expect(value).toMatchObject({
      schema: 'training.execution-completion.v1',
      status: 'completed',
      session_id: '13700000-0000-4000-8000-000000000020',
      completion_id: '139d0000-0000-4000-8000-000000000003',
      receipt: { kind: 'completed', before_revision: 0, after_revision: 1 },
      workout: {
        kind: 'workout',
        workout_type: 'full_body',
        duration_min: 30,
        intensity: 'moderada',
      },
      workout_state: 'present',
      session: { schema: 'training.execution.v2', phase: 'completed', revision: 1 },
      feedback: null,
    })
    expect(value.workout?.workout_id).toBe(g.effect.receipt.workout_id)
    expect(value.session?.exercises.map((e) => e.sets)).toEqual([[], []])
    expect(JSON.stringify(value)).not.toMatch(
      /"(clinical|source_input|prepared|frozen_state|workout_hash|auth_session_id|command|source_hash|strength_capture)":/,
    )
    expect(g.completed.completion.frozen_state.phase).toBe('in_progress')
  })
  it('a reservation is not a workout, a completion receipt or a checked prescription', () => {
    const { g, bound, auth } = capture()
    const value = projectTrainingExecutionCompletion(g.begin, bound, auth)
    expect(value.status).toBe('reserved')
    expect(value.workout).toBeNull()
    expect(value.receipt).toBeNull()
    expect(value.session?.phase).toBe('in_progress')
    expect(value.session?.exercises.every((e) => !e.completed && e.sets.length === 0)).toBe(true)
  })
  it('keeps completed state terminal after the official workout is removed', () => {
    const { g, bound, auth } = capture()
    g.completed.workout_is_live = false
    const value = projectTrainingExecutionCompletion(g.completed, bound, auth)
    expect(value.workout_state).toBe('removed')
    expect(value.session?.phase).toBe('completed')
    expect(value.workout?.workout_id).toBe(g.effect.receipt.workout_id)
  })
  it.each([
    { duration_min: 0 },
    { estimated_kcal: -1 },
    { clinical: { private: 'not public' } },
    { workout_type: '' },
  ])('refuses malformed or extra original receipt data instead of projecting it: %j', (change) => {
    const { g, bound, auth } = capture()
    Object.assign(g.completed.completion.receipt.workout.activity, change)
    expect(() => projectTrainingExecutionCompletion(g.completed, bound, auth)).toThrow()
  })
  it('a historical cancellation never publishes an unrelated later current state without its own proof', () => {
    const { g, bound, auth } = capture(),
      at = g.begin.scope.observed_at
    Object.assign(g.begin.completion, {
      status: 'cancelled',
      cancelled_at: at,
      cancel_receipt: {
        schema: 'training.execution-finish-cancelled.v1',
        owner_id: bound.ownerId,
        auth_user_id: auth,
        epoch: bound.command.expected_epoch,
        session_id: bound.command.session_id,
        completion_id: bound.command.operation_id,
        input_hash: bound.inputHash,
        at,
      },
    })
    Object.assign(g.begin, { session: { ...g.completed.session, unproved: 'must not leak' } })
    const value = projectTrainingExecutionCompletion(g.begin, bound, auth)
    expect(value.status).toBe('cancelled')
    expect(value.session).toBeNull()
    expect(value.workout).toBeNull()
    expect(value.receipt?.kind).toBe('cancelled')
    expect(JSON.stringify(value)).not.toContain('unproved')
  })
  it('does not widen the v1 decoder to accept a completed v2 execution', () => {
    const { g } = capture()
    expect(() => readTrainingExecutionSession(g.completed.session, g.completed.scope)).toThrow()
  })
})
