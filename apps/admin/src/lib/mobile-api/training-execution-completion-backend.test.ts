import { describe, expect, it, vi } from 'vitest'
import golden from './testing/training-completion-pg-golden.json'
import { createTrainingExecutionCompletionBackend } from './training-execution-completion-backend'
import { bindTrainingExecutionCompletion } from './training-execution-completion-contracts'

function setup() {
  const g = structuredClone(golden)
  const bound = bindTrainingExecutionCompletion(
    g.begin.scope.owner_id,
    `tfinish1:${g.command.operation_id}`,
    g.command,
  )
  let completed = false
  let cancelled = false
  const call = vi.fn(async (name: string, args: Readonly<Record<string, unknown>>) => {
    if (name === 'begin_training_execution_completion_authenticated')
      return { data: completed ? { ...g.completed, action: 'replay' } : g.begin, error: null }
    if (name === 'read_training_execution_completion_authenticated')
      return {
        data: cancelled
          ? { action: 'absent' }
          : completed
            ? g.completed
            : { ...g.begin, action: 'available' },
        error: null,
      }
    if (name === 'cancel_training_execution_completion_authenticated') {
      if (completed)
        return {
          data: { action: 'completed', receipt: g.completed.completion.receipt },
          error: null,
        }
      const at = g.begin.scope.observed_at
      const receipt = {
        schema: 'training.execution-finish-cancelled.v1',
        owner_id: bound.ownerId,
        auth_user_id: g.begin.scope.auth_user_id,
        epoch: bound.command.expected_epoch,
        session_id: bound.command.session_id,
        completion_id: bound.command.operation_id,
        input_hash: bound.inputHash,
        at,
      }
      Object.assign(g.begin.completion, {
        status: 'cancelled',
        cancelled_at: at,
        cancel_receipt: receipt,
      })
      return { data: { action: 'cancelled', receipt }, error: null }
    }
    if (name === 'read_conversation_workout_preparation')
      return {
        data: { action: 'available', source: g.source, preparation: g.preparation },
        error: null,
      }
    if (name === 'read_conversation_workout_effect')
      return { data: completed ? g.effect : { action: 'absent' }, error: null }
    if (name === 'commit_training_execution_completion_authenticated') {
      expect(args).toEqual({
        p_user_id: bound.ownerId,
        p_auth_user_id: g.begin.scope.auth_user_id,
        p_auth_session_id: '139d0000-0000-4000-8000-000000000005',
        p_completion_id: bound.command.operation_id,
        p_input_hash: bound.inputHash,
        p_source_hash: g.source.source_hash,
        p_prepared_hash: g.preparation.prepared_hash,
        p_prepared: g.preparation.prepared,
      })
      completed = true
      return { data: { action: 'committed', receipt: g.effect.receipt }, error: null }
    }
    throw Error(`Unexpected RPC ${name}`)
  })
  const checkCurrentScope = vi.fn(async () => true)
  const backend = createTrainingExecutionCompletionBackend(
    { rpc: call },
    {
      owner_id: bound.ownerId,
      auth_user_id: g.begin.scope.auth_user_id,
      auth_session_id: '139d0000-0000-4000-8000-000000000005',
      checkCurrentScope,
    },
  )
  return {
    g,
    bound,
    call,
    checkCurrentScope,
    backend,
    cancel: () => {
      cancelled = true
    },
    complete: () => {
      completed = true
    },
  }
}

function originalImplementation(call: ReturnType<typeof setup>['call']) {
  const original = call.getMockImplementation()
  if (!original) throw Error('Missing controlled transport')
  return original
}

describe('original-login training completion over the existing workout backend', () => {
  it('observes a reserved completion without reserving, preparing or writing anything', async () => {
    const h = setup()
    expect(await h.backend.read(h.bound)).toMatchObject({ completion: { status: 'reserved' } })
    expect(h.call.mock.calls.map(([n]) => n)).toEqual([
      'read_training_execution_completion_authenticated',
    ])
  })
  it('cancels only the same reserved command and independently proves cancellation without registering a workout', async () => {
    const h = setup()
    expect(await h.backend.cancel(h.bound)).toMatchObject({ completion: { status: 'cancelled' } })
    expect(h.call.mock.calls.map(([n]) => n)).toEqual([
      'read_training_execution_completion_authenticated',
      'cancel_training_execution_completion_authenticated',
      'read_training_execution_completion_authenticated',
    ])
    expect(await h.backend.submit(h.bound)).toEqual({ status: 'cancelled' })
    expect(h.call.mock.calls.some(([n]) => n.startsWith('commit_'))).toBe(false)
  })
  it('an already committed finish cannot be unfreezed by cancellation', async () => {
    const h = setup()
    h.complete()
    const value = await h.backend.cancel(h.bound)
    expect(value.completion.status).toBe('completed')
    expect(value.completion.receipt).toEqual(h.g.completed.completion.receipt)
    expect(h.call.mock.calls.some(([n]) => n.startsWith('commit_'))).toBe(false)
  })
  it('maps only the protected commit and proves the actual same-identity effect plus linked completed execution', async () => {
    const h = setup()
    const result = await h.backend.submit(h.bound)
    expect(result).toMatchObject({
      status: 'saved',
      effect: h.g.effect,
      completion: { completion: { status: 'completed' }, workout_is_live: true },
    })
    expect(
      h.call.mock.calls.filter(([n]) => n === 'commit_training_execution_completion_authenticated'),
    ).toHaveLength(1)
    expect(h.call.mock.calls.some(([n]) => n === 'commit_conversation_workout')).toBe(false)
    expect(h.call.mock.calls.some(([n]) => n === 'register_workout_atomic')).toBe(false)
  })
  it('replays a completed operation without a second physical commit', async () => {
    const h = setup()
    h.complete()
    expect(await h.backend.submit(h.bound)).toMatchObject({ status: 'saved', effect: h.g.effect })
    expect(h.call.mock.calls.some(([n]) => n.startsWith('commit_'))).toBe(false)
  })
  it('reconciles one committed lost reply by reading the same official operation', async () => {
    const h = setup(),
      original = originalImplementation(h.call)
    h.call.mockImplementation(async (n, a) => {
      const value = await original(n, a)
      if (n === 'commit_training_execution_completion_authenticated')
        throw Error('Lost AFTER commit')
      return value
    })
    expect(await h.backend.submit(h.bound)).toMatchObject({ status: 'saved', effect: h.g.effect })
    expect(h.call.mock.calls.filter(([n]) => n.startsWith('commit_'))).toHaveLength(1)
  })
  it('retains pending on an unknown pre-commit transport failure, never regenerating the operation', async () => {
    const h = setup(),
      original = originalImplementation(h.call)
    h.call.mockImplementation(async (n, a) => {
      if (n === 'commit_training_execution_completion_authenticated')
        throw Error('Unknown network result')
      return original(n, a)
    })
    expect(await h.backend.submit(h.bound)).toMatchObject({ status: 'pending' })
    expect(h.call.mock.calls.filter(([n]) => n.startsWith('commit_'))).toHaveLength(1)
  })
  it('refuses changed current Auth before even reserving a finish', async () => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValue(false)
    await expect(h.backend.submit(h.bound)).rejects.toThrow()
    expect(h.call).not.toHaveBeenCalled()
  })
  it('does not continue a cancelled or reset reservation through a late generic workout job', async () => {
    const h = setup(),
      original = originalImplementation(h.call)
    h.call.mockImplementation(async (n, a) => {
      const value = await original(n, a)
      if (n === 'read_conversation_workout_preparation') h.cancel()
      return value
    })
    expect(await h.backend.submit(h.bound)).toMatchObject({ status: 'pending' })
    expect(h.call.mock.calls.some(([n]) => n.startsWith('commit_'))).toBe(false)
  })
  it.each([
    'input_hash',
    'workout_hash',
    'auth_user_id',
    'session_id',
  ])('refuses a changed reserved %s before any domain call', async (field) => {
    const h = setup()
    ;(h.g.begin.completion as Record<string, unknown>)[field] = h.g.command.operation_id
    await expect(h.backend.submit(h.bound)).rejects.toThrow()
    expect(
      h.call.mock.calls.some(
        ([n]) => n.startsWith('read_conversation_') || n.startsWith('commit_'),
      ),
    ).toBe(false)
  })
  it('does not accept an official workout without its atomically linked completed execution', async () => {
    const h = setup()
    h.complete()
    h.g.completed.completion.receipt.workout.workout_id = h.g.command.session_id
    await expect(h.backend.submit(h.bound)).rejects.toThrow()
  })
})
