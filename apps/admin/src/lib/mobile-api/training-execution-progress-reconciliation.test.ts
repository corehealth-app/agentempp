import { describe, expect, it } from 'vitest'
import { hashMobileRequest } from './idempotency'
import golden from './testing/training-completion-pg-golden.json'
import { projectTrainingExecutionProgressReconciliation } from './training-execution-progress-reconciliation'

function fixture(completed = true) {
  const g = structuredClone(golden),
    s = g.begin.session
  const command = {
    schema: 'training.execution.start.v1',
    session_id: s.id,
    operation_id: s.id,
    expected_epoch: s.epoch,
    expected_local_date: s.local_date,
    plan_id: s.definition.plan_id,
    plan_hash: s.definition.plan_hash,
    day_index: s.definition.day_index,
  }
  const receipt = {
    schema: 'training.execution.receipt.v1',
    owner_id: s.owner_id,
    epoch: s.epoch,
    session_id: s.id,
    operation_id: s.id,
    input_hash: hashMobileRequest(command),
    before_revision: null,
    after_revision: 0,
    kind: 'start',
    at: s.started_at,
  }
  const scope = completed ? g.completed.scope : g.begin.scope
  const state = completed
    ? { action: 'completion', context: g.completed }
    : { action: 'progress', scope, session: s }
  const observation = { action: 'available', scope, command, receipt, state }
  const read = (raw: unknown = observation) =>
    projectTrainingExecutionProgressReconciliation(raw, command, {
      owner: s.owner_id,
      auth: s.auth_user_id,
    })
  return { g, s, command, receipt, observation, read }
}
describe('original progress receipt remains distinct from current protected completion', () => {
  it('acknowledges the original start without replacing a later completed current state with old progress', () => {
    const h = fixture(),
      v = h.read()
    expect(v.action).toBe('available')
    if (v.action !== 'available') throw Error('missing original receipt')
    expect(v.receipt).toEqual(h.receipt)
    expect(v.current).toMatchObject({
      schema: 'training.execution-state.v2',
      session: { schema: 'training.execution.v2', phase: 'completed', revision: 1 },
      completion: { status: 'completed' },
    })
    expect(v.current.session.exercises.every((e) => e.sets.length === 0)).toBe(true)
    expect(JSON.stringify(v)).not.toMatch(
      /"(frozen_state|source_input|prepared|workout_hash|auth_session_id)":/,
    )
  })
  it('returns real current progress for an owned receipt without inventing a completion', () => {
    const h = fixture(false),
      v = h.read()
    expect(v.action).toBe('available')
    if (v.action !== 'available') throw Error()
    expect(v.current).toMatchObject({ session: { phase: 'in_progress' }, completion: null })
    expect(v.receipt.after_revision).toBe(0)
  })
  it.each([
    'input',
    'hash',
    'operation',
    'revision',
    'owner',
    'scope',
    'completion',
    'unexpected',
  ] as const)('rejects an unrelated or unproved %s instead of issuing a generic ACK', (kind) => {
    const h = fixture(),
      v = structuredClone(h.observation)
    switch (kind) {
      case 'input':
        v.command = { ...v.command, day_index: 1 }
        break
      case 'hash':
        v.receipt.input_hash = 'a'.repeat(64)
        break
      case 'operation':
        v.receipt.operation_id = '14100000-0000-4000-8000-000000000099'
        break
      case 'revision':
        v.receipt.after_revision = 1
        break
      case 'owner':
        v.receipt.owner_id = '14100000-0000-4000-8000-000000000099'
        break
      case 'scope':
        v.scope = { ...v.scope, epoch: '14100000-0000-4000-8000-000000000099' }
        break
      case 'completion':
        if (v.state.context) Reflect.set(v.state.context.completion, 'receipt', null)
        break
      default:
        Object.assign(v, { private_override: true })
    }
    expect(() => h.read(v)).toThrow()
  })
  it('a missing original operation remains absent, even when a session may already be completed', () => {
    const h = fixture()
    const v = h.read({ action: 'absent', scope: h.g.completed.scope, state: h.observation.state })
    expect(v.action).toBe('absent')
    expect(v.current?.session.phase).toBe('completed')
    expect('receipt' in v).toBe(false)
  })
})
