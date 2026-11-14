import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  bindTrainingExecutionCompletion,
  parseTrainingExecutionCompletionCommand,
} from './training-execution-completion-contracts'

const owner = '139d0000-0000-4000-8000-000000000001'
const session = '139d0000-0000-4000-8000-000000000002'
const operation = '139d0000-0000-4000-8000-000000000003'
const epoch = '139d0000-0000-4000-8000-000000000004'
const report = 'Fiz musculação por 30 min com intensidade moderada.'
const command = () => ({
  schema: 'training.execution.finish.v1',
  session_id: session,
  operation_id: operation,
  expected_epoch: epoch,
  expected_revision: 3,
  source: { channel: 'text', text: report },
})
const key = `tfinish1:${operation}`

describe('An explicit finish report remains the original activity claim', () => {
  it('binds the exact accepted report and one stable workout command without inventing performed facts', () => {
    const raw = command(),
      result = bindTrainingExecutionCompletion(owner, key, raw)
    expect(result.command).toEqual(raw)
    expect(result.workout).toMatchObject({
      ownerId: owner,
      commandId: operation,
      command: {
        command_protocol: 'conversation.command.v1',
        command_id: operation,
        kind: 'workout.report',
        source: { channel: 'text', text: report },
      },
    })
    const literal = `{"command_id":"${operation}","command_protocol":"conversation.command.v1","kind":"workout.report","source":{"channel":"text","text":"${report}"}}`
    expect(result.workout.inputHash).toBe(createHash('sha256').update(literal).digest('hex'))
    expect(result.inputHash).toMatch(/^[0-9a-f]{64}$/)
    expect(JSON.stringify(result)).not.toMatch(
      /"(estimated_kcal|calories|performed_at|recommended_sets|xp)":/,
    )
    raw.source.text = 'Mudou depois'
    expect(result.workout.command.source).toEqual({ channel: 'text', text: report })
    expect(Object.isFrozen(result.command.source)).toBe(true)
  })
  it('preserves spelling, accents and whitespace rather than silently changing the accepted source', () => {
    const source = { channel: 'text', text: '  Fiz caminhada por 15 min.  ' }
    expect(
      bindTrainingExecutionCompletion(owner, key, { ...command(), source }).workout.command.source,
    ).toEqual(source)
  })
  it('changes the finish digest for revision, session or actual report changes, preserving the original command', () => {
    const original = bindTrainingExecutionCompletion(owner, key, command())
    for (const change of [
      { expected_revision: 4 },
      { session_id: owner },
      { source: { channel: 'text', text: 'Fiz caminhada por 10 min' } },
    ]) {
      const next = bindTrainingExecutionCompletion(owner, key, { ...command(), ...change })
      expect(next.inputHash).not.toBe(original.inputHash)
      expect(original.command).toEqual(command())
    }
  })
  it.each([
    '',
    `cmsg1:${operation}`,
    `tfinish1:${session}`,
    `${key}:retry`,
    ` ${key}`,
  ])('refuses a different or malformed protected key %s', (invalid) => {
    expect(() => bindTrainingExecutionCompletion(owner, invalid, command())).toThrow()
  })
  it.each([
    { owner_id: owner },
    { auth_user_id: owner },
    { estimated_kcal: 200 },
    { xp: 100 },
    { receipt: { workout_id: owner } },
    { performed_at: '2026-11-14T20:00:00Z' },
    { actual_sets: [] },
    { expected_revision: -1 },
    { expected_revision: 2147483647 },
    { expected_revision: 2147483648 },
    { source: { channel: 'text', text: report, performed: true } },
    { source: { channel: 'text', text: '' } },
    { source: { channel: 'text', text: ' '.repeat(20) } },
    { source: { channel: 'text', text: 'x'.repeat(2001) } },
    { source: { channel: 'media', media_asset_id: owner } },
  ])('does not accept client-supplied authority or an absent report: %j', (change) => {
    expect(() => parseTrainingExecutionCompletionCommand({ ...command(), ...change })).toThrow()
  })
  it('does not promote a future plan or a question into a performed activity at this transport boundary', () => {
    for (const text of ['Vou fazer musculação amanhã', 'Posso fazer musculação por 30 min?']) {
      const bound = bindTrainingExecutionCompletion(owner, key, {
        ...command(),
        source: { channel: 'text', text },
      })
      expect(bound.workout.command.source).toEqual({ channel: 'text', text })
      expect(bound).not.toHaveProperty('receipt')
      expect(bound).not.toHaveProperty('activity')
    }
  })
})
