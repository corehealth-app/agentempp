import { describe, expect, it } from 'vitest'
import golden from './testing/training-completion-pg-golden.json'
import { bindTrainingExecutionCompletion } from './training-execution-completion-contracts'
import { projectTrainingExecutionFinishResolution } from './training-execution-finish-resolution'

function fixture() {
  const g = structuredClone(golden),
    command = {
      ...g.begin.completion.command,
      operation_id: '14300000-0000-4000-8000-000000000099',
    }
  const bound = bindTrainingExecutionCompletion(
    g.begin.completion.user_id,
    `tfinish1:${command.operation_id}`,
    command,
  )
  const scope = g.completed.scope,
    state = { action: 'completion', context: g.completed }
  const request = {
    session_id: command.session_id,
    operation_id: command.operation_id,
    epoch: command.expected_epoch,
    before_revision: command.expected_revision,
    input_hash: bound.inputHash,
  }
  const read = (raw: Record<string, unknown> = { action: 'absent', scope, state }) =>
    projectTrainingExecutionFinishResolution(
      { request, ...raw },
      bound,
      g.begin.completion.auth_user_id,
    )
  return { g, bound, scope, state, read }
}
describe('exact queued finish observation cannot borrow another completion receipt', () => {
  it('fences only an absent original command while preserving the other actual completion', () => {
    const h = fixture(),
      v = h.read()
    expect(v).toMatchObject({
      schema: 'training.execution-finish-resolution.v1',
      status: 'fenced',
      reason: 'terminal',
      operation_id: h.bound.command.operation_id,
      input_hash: h.bound.inputHash,
      completion: null,
      withdrawal: null,
      current: {
        session: { phase: 'completed' },
        completion: { completion_id: h.g.completed.completion.completion_id },
      },
    })
    expect(JSON.stringify(v)).not.toMatch(/"(frozen_state|source_input|prepared|auth_session_id)":/)
  })
  it('keeps a cancellable other reservation pending and clinical pause is never a permanent fence', () => {
    const h = fixture(),
      scope = h.g.begin.scope
    const reserved = h.read({
      action: 'absent',
      scope,
      state: { action: 'completion', context: { ...h.g.begin, action: 'available' } },
    })
    expect(reserved).toMatchObject({
      status: 'pending',
      reason: 'other_reservation',
      completion: null,
    })
    const paused = { ...scope, recording_allowed: false }
    expect(
      h.read({
        action: 'absent',
        scope: paused,
        state: { action: 'progress', scope: paused, session: h.g.begin.session },
      }),
    ).toMatchObject({ status: 'pending', reason: 'recording_unavailable' })
  })
  it('ready means no acknowledgement; an advanced revision is a separate permanent fence', () => {
    const h = fixture(),
      scope = h.g.begin.scope
    expect(
      h.read({
        action: 'absent',
        scope,
        state: { action: 'progress', scope, session: h.g.begin.session },
      }),
    ).toMatchObject({ status: 'ready', completion: null, withdrawal: null })
    const session = { ...h.g.begin.session, revision: h.bound.command.expected_revision + 1 }
    expect(
      h.read({ action: 'absent', scope, state: { action: 'progress', scope, session } }),
    ).toMatchObject({ status: 'fenced', reason: 'revision_advanced' })
  })
  it('an epoch change resolves only future use and publishes no old session under a new epoch', () => {
    const h = fixture(),
      scope = { ...h.scope, epoch: '14300000-0000-4000-8000-000000000080' }
    expect(h.read({ action: 'absent', scope, state: { action: 'absent', scope } })).toMatchObject({
      status: 'fenced',
      reason: 'epoch_changed',
      current: null,
      completion: null,
    })
    expect(() => h.read({ action: 'absent', scope, state: h.state })).toThrow()
  })
  it.each([
    'owner',
    'auth',
    'unknown',
    'scope',
    'claim',
    'revision',
  ])('rejects an unproved %s resolution', (attack) => {
    const h = fixture(),
      raw: Record<string, unknown> = { action: 'absent', scope: h.scope, state: h.state }
    if (attack === 'owner')
      raw.scope = { ...h.scope, owner_id: '14300000-0000-4000-8000-000000000080' }
    else if (attack === 'auth')
      raw.scope = { ...h.scope, auth_user_id: '14300000-0000-4000-8000-000000000080' }
    else if (attack === 'unknown') raw.extra = true
    else if (attack === 'scope')
      raw.scope = { ...h.scope, observed_at: '2099-01-01T00:00:00.000000Z' }
    else if (attack === 'claim') raw.action = 'available'
    else
      raw.state = {
        action: 'progress',
        scope: h.scope,
        session: { ...h.g.begin.session, revision: -1 },
      }
    expect(() => h.read(raw)).toThrow()
  })
})

describe('withdrawal markers are future-denial proof only', () => {
  it('rejects a new-epoch current execution attached to an old withdrawal', () => {
    const h = fixture(),
      scope = { ...h.g.begin.scope, epoch: '14300000-0000-4000-8000-000000000080' },
      request = {
        session_id: h.bound.command.session_id,
        operation_id: h.bound.command.operation_id,
        epoch: h.bound.command.expected_epoch,
        before_revision: h.bound.command.expected_revision,
        input_hash: h.bound.inputHash,
      },
      marker = {
        schema: 'training.execution-finish-withdrawal.v1',
        ...request,
        owner_id: scope.owner_id,
        auth_user_id: scope.auth_user_id,
        at: scope.observed_at,
      }
    expect(() =>
      h.read({
        action: 'withdrawn',
        scope,
        withdrawal: marker,
        state: { action: 'progress', scope, session: { ...h.g.begin.session, epoch: scope.epoch } },
      }),
    ).toThrow()
  })
  it('requires an exact marker and keeps independent completed current facts', () => {
    const h = fixture(),
      request = {
        session_id: h.bound.command.session_id,
        operation_id: h.bound.command.operation_id,
        epoch: h.bound.command.expected_epoch,
        before_revision: h.bound.command.expected_revision,
        input_hash: h.bound.inputHash,
      },
      marker = {
        schema: 'training.execution-finish-withdrawal.v1',
        ...request,
        owner_id: h.scope.owner_id,
        auth_user_id: h.scope.auth_user_id,
        at: h.scope.observed_at,
      }
    const value = h.read({
      action: 'withdrawn',
      scope: h.scope,
      state: h.state,
      withdrawal: marker,
    })
    expect(value).toMatchObject({
      status: 'withdrawn',
      completion: null,
      current: { session: { phase: 'completed' } },
    })
    for (const patch of [
      { input_hash: 'a'.repeat(64) },
      { at: '2099-01-01T00:00:00.000000Z' },
      { source: 'private' },
      { operation_id: h.g.command.operation_id },
    ])
      expect(() =>
        h.read({
          action: 'withdrawn',
          scope: h.scope,
          state: h.state,
          withdrawal: { ...marker, ...patch },
        }),
      ).toThrow()
  })
})
