import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import { createConversationWorkoutBackend } from './conversation-workout-backend'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
  workoutUUID,
} from './conversation-workout-contracts'
import actualGoldenValues from './testing/conversation-workout-pg-golden.json'

function actualGolden() {
  const value = actualGoldenValues.workout_actual_golden[0]
  if (!value) throw new Error('Missing actual PG golden')
  return value
}
function setup(text = 'Fiz caminhada') {
  const clinical = structuredClone(replyFixture().profile)
  const id = '139c0000-0000-4000-8000-000000000100'
  const command = bindConversationWorkoutCommand(clinical.user_id, `cmsg1:${id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: id,
    kind: 'workout.report',
    source: { channel: 'text', text },
  })
  const rawSource = {
    source_hash: 'a'.repeat(64),
    context: {
      schema: 'conversation.workout-source.v1',
      owner_id: clinical.user_id,
      command_id: id,
      input_hash: command.inputHash,
      epoch: clinical.epoch,
      source_input: command.command,
      admitted_at: clinical.observed_at,
      captured_at: clinical.observed_at,
      clinical,
      day_closed: false,
      media: null,
      catalogue: [
        {
          id: '139c0000-0000-4000-8000-000000000101',
          slug: 'caminhada',
          display_name: 'Caminhada',
          is_active: true,
          updated_at: clinical.observed_at,
        },
      ],
    },
  }
  const source = parseConversationWorkoutSource(command, rawSource)
  const decision = resolveConversationWorkoutReport(source)
  const stored = { prepared_hash: workoutDigest(decision), prepared: decision }
  const responses: Record<string, unknown> = {
    read_conversation_workout_preparation: { action: 'absent' },
    admit_conversation_workout_command: {
      action: 'admitted',
      command: {
        owner_id: clinical.user_id,
        command_id: id,
        input_hash: command.inputHash,
        epoch: clinical.epoch,
        admitted_at: clinical.observed_at,
      },
    },
    capture_conversation_workout_source: rawSource,
    prepare_conversation_workout: { action: 'prepared', ...stored },
  }
  const rpc = vi.fn(async (name: string) => ({ data: responses[name], error: null }))
  const checkCurrentScope = vi.fn(async () => true)
  const service = createConversationWorkoutBackend({ rpc }, { checkCurrentScope })
  return {
    service,
    command,
    clinical,
    epoch: workoutUUID.parse(clinical.epoch),
    responses,
    rpc,
    checkCurrentScope,
    stored,
    rawSource,
  }
}
describe('concrete workout backend composition', () => {
  it('detaches an SDK read before the following scope observation can mutate its alias', async () => {
    const h = setup()
    h.responses.read_conversation_workout_preparation = {
      action: 'available',
      source: h.rawSource,
      preparation: h.stored,
    }
    h.checkCurrentScope.mockImplementation(async () => {
      if (h.rpc.mock.calls.length === 1) h.rawSource.context.epoch = h.command.commandId
      return true
    })
    expect(await h.service.report(h.command, h.epoch)).toMatchObject({
      status: 'needs_reply',
      question: { field: 'duration_min' },
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('preserves one server sealed question and its immutable source, no domain RPC', async () => {
    const h = setup()
    const result = await h.service.report(h.command, h.epoch)
    expect(result).toMatchObject({ status: 'needs_reply', question: { field: 'duration_min' } })
    expect(h.rpc.mock.calls.map((c) => c[0])).toEqual([
      'read_conversation_workout_preparation',
      'admit_conversation_workout_command',
      'capture_conversation_workout_source',
      'prepare_conversation_workout',
    ])
    h.responses.read_conversation_workout_preparation = {
      action: 'available',
      source: h.rawSource,
      preparation: h.stored,
    }
    h.rpc.mockClear()
    expect(await h.service.report(h.command, h.epoch)).toEqual(result)
    expect(h.rpc.mock.calls.map((c) => c[0])).toEqual(['read_conversation_workout_preparation'])
  })
  it('revocation after an await is sticky and prevents every later RPC', async () => {
    const h = setup()
    h.checkCurrentScope
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true)
    expect(await h.service.report(h.command, h.epoch)).toMatchObject({
      status: 'unavailable',
      reason: 'scope_changed',
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
  it('rejects changed prepared question identity instead of trusting a SQL-shaped value', async () => {
    const h = setup()
    h.responses.prepare_conversation_workout = {
      action: 'prepared',
      prepared_hash: workoutDigest({}),
      prepared: {},
    }
    expect(await h.service.report(h.command, h.epoch)).toMatchObject({ status: 'unavailable' })
    expect(h.rpc.mock.calls.map((c) => c[0])).not.toContain('commit_conversation_workout')
  })
})

it('recovers actual PG prepared identity and durable receipt without re-estimating current body', async () => {
  const actual = actualGolden()
  const c = actual.source.context
  const command = bindConversationWorkoutCommand(
    c.owner_id,
    `cmsg1:${c.command_id}`,
    c.source_input,
  )
  const calls: Array<{ name: string; args: Readonly<Record<string, unknown>> }> = []
  let reads = 0
  const service = createConversationWorkoutBackend(
    {
      async rpc(name, args) {
        calls.push({ name, args })
        if (name === 'read_conversation_workout_preparation')
          return {
            data: {
              action: 'available',
              source: actual.source,
              preparation: {
                prepared_hash: actual.preparation.prepared_hash,
                prepared: actual.preparation.prepared,
              },
            },
            error: null,
          }
        if (name === 'read_conversation_workout_effect')
          return { data: ++reads === 1 ? { action: 'absent' } : actual.effect, error: null }
        if (name === 'commit_conversation_workout')
          throw new Error('Lost response after actual durable commit')
        throw new Error('Unexpected regeneration or additional RPC')
      },
    },
    { checkCurrentScope: async () => true },
  )
  expect(await service.report(command, c.epoch)).toMatchObject({
    status: 'saved',
    effect: { receipt: actual.effect.receipt },
  })
  expect(calls.map((c) => c.name)).toEqual([
    'read_conversation_workout_preparation',
    'read_conversation_workout_effect',
    'commit_conversation_workout',
    'read_conversation_workout_effect',
  ])
  const firstRead = calls[1],
    commit = calls[2],
    recovery = calls[3]
  if (!firstRead || !commit || !recovery) throw new Error('Missing effect/recovery calls')
  expect(firstRead.args).toEqual(recovery.args)
  expect(commit.args.p_prepared).toEqual(actual.preparation.prepared)
})
it('latches revocation after commit and never dispatches the reconciliation read', async () => {
  const actual = actualGolden()
  const c = actual.source.context
  const command = bindConversationWorkoutCommand(
    c.owner_id,
    `cmsg1:${c.command_id}`,
    c.source_input,
  )
  let revoked = false
  const rpc = vi.fn(async (name: string) => {
    if (name === 'read_conversation_workout_preparation')
      return {
        data: {
          action: 'available',
          source: actual.source,
          preparation: {
            prepared_hash: actual.preparation.prepared_hash,
            prepared: actual.preparation.prepared,
          },
        },
        error: null,
      }
    if (name === 'commit_conversation_workout') revoked = true
    return { data: { action: 'absent' }, error: null }
  })
  const service = createConversationWorkoutBackend(
    { rpc },
    { checkCurrentScope: async () => !revoked },
  )
  expect(await service.report(command, c.epoch)).toMatchObject({
    status: 'unavailable',
    reason: 'scope_changed',
  })
  expect(rpc.mock.calls.map((c) => c[0])).toEqual([
    'read_conversation_workout_preparation',
    'read_conversation_workout_effect',
    'commit_conversation_workout',
  ])
})
