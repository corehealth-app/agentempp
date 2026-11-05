import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { prepareConversationWorkout } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'
import {
  createConversationWorkoutWriter,
  parseConversationWorkoutEffect,
  projectConversationWorkoutFacts,
} from './conversation-workout-writer'

const id = (n: number) => `c3cc0000-0000-4000-8000-${String(n).padStart(12, '0')}`
async function fixture() {
  const clinical = structuredClone(replyFixture().profile),
    owner = clinical.user_id,
    commandID = id(20)
  const command = bindConversationWorkoutCommand(owner, `cmsg1:${commandID}`, {
    command_protocol: 'conversation.command.v1',
    command_id: commandID,
    kind: 'workout.report',
    source: { channel: 'text', text: 'Fiz 30 minutos de caminhada leve' },
  })
  const context = {
    schema: 'conversation.workout-source.v1',
    owner_id: owner,
    command_id: commandID,
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
        id: id(21),
        slug: 'caminhada',
        display_name: 'Caminhada',
        is_active: true,
        updated_at: clinical.observed_at,
      },
    ],
  }
  const source = parseConversationWorkoutSource(command, { source_hash: 'a'.repeat(64), context })
  const prepared = await prepareConversationWorkout(source, { checkCurrentScope: async () => true })
  if (prepared.status !== 'ready') throw new Error('Expected prepared synthetic source')
  const operationKey = `cwork1:${commandID}`,
    time = source.admittedAt
  const receipt = {
    schema: 'conversation.workout-effect.v1',
    provenance: 'conversation.workout.v1',
    owner_id: owner,
    command_id: commandID,
    input_hash: command.inputHash,
    source_hash: source.sourceHash,
    epoch: source.epoch,
    registration_id: commandID,
    workout_id: id(22),
    snapshot_id: id(23),
    lifecycle_key: id(24),
    operation_key: operationKey,
    prepared_hash: workoutDigest(prepared),
    performed_at: time,
    local_date: source.localDate,
    time_zone: source.clinical.timezone,
    committed_at: time,
    effect_version: 1,
    activity: prepared.activity,
  }
  const effect = {
    action: 'available',
    receipt,
    original_facts: {
      workout: {
        id: id(22),
        user_id: owner,
        snapshot_id: id(23),
        raw_provider_message_id: operationKey,
        workout_type: 'caminhada',
        duration_min: 30,
        intensity: 'leve',
        estimated_kcal: null,
        performed_at: time,
      },
      snapshot: { id: id(23), user_id: owner, date: source.localDate },
      strength_capture: {
        status: 'committed',
        binding: {
          ownerID: owner,
          lifecycleKey: id(24),
          operationKey,
          originalOperationType: 'caminhada',
          workoutLogID: id(22),
          resolution: 'sql_insert',
        },
        fact: {
          anchor: {
            ownerID: owner,
            workoutLogID: id(22),
            lifecycleKey: id(24),
            snapshotID: id(23),
            storedWorkoutType: 'caminhada',
            performedAt: time,
            snapshotDate: source.localDate,
          },
          classification: {
            status: 'matched',
            method: 'active_slug',
            observation: {
              observationKey: id(25),
              observedAt: time,
              matcherVersion: 'active_slug_then_unique_canonical_display_v1',
            },
            catalogue: {
              id: id(21),
              slug: 'caminhada',
              displayName: 'Caminhada',
              category: 'cardio',
              isActive: true,
              updatedAtLiteral: time,
            },
          },
          calendar: {
            status: 'proven',
            performedAt: time,
            localDate: source.localDate,
            timeZone: source.clinical.timezone,
            zoneSource: 'official_owner_zone_at_recording',
            zoneObservedAt: time,
            snapshotID: id(23),
            snapshotDate: source.localDate,
          },
          clarification: { status: 'not_applicable' },
          revision: 0,
        },
      },
    },
  }
  return { source, prepared, effect }
}

describe('dormant workout own-provenance effect codec and durable bridge', () => {
  it('projects actual bound facts with unknown kcal, without a ui-v1 confirmation or derived credit', async () => {
    const f = await fixture(),
      effect = parseConversationWorkoutEffect(f.source, f.prepared, f.effect)
    const facts = projectConversationWorkoutFacts(effect)
    expect(facts.registration).toEqual({
      kind: 'workout',
      log_id: id(22),
      workout_type: 'caminhada',
      duration_min: 30,
      intensity: 'leve',
      estimated_kcal: null,
    })
    expect(facts.provenance).toBe('conversation.workout.v1')
    expect(facts).not.toHaveProperty('day')
    expect(facts).not.toHaveProperty('xp')
  })
  it.each([
    'owner',
    'epoch',
    'source',
    'ui',
    'zero',
    'window',
    'snapshot',
    'operation',
    'catalogue',
  ])('refuses unproved %s binding before projecting facts', async (kind) => {
    const f = await fixture(),
      effect = structuredClone(f.effect)
    if (kind === 'owner') effect.receipt.owner_id = id(99)
    if (kind === 'epoch') effect.receipt.epoch = id(99)
    if (kind === 'source') effect.receipt.source_hash = 'b'.repeat(64)
    if (kind === 'ui') effect.receipt.provenance = 'ui-v1'
    if (kind === 'zero') Reflect.set(effect.original_facts.workout, 'estimated_kcal', 0)
    if (kind === 'window')
      effect.original_facts.strength_capture.binding.resolution = 'recent6h_dedup'
    if (kind === 'snapshot') effect.original_facts.strength_capture.fact.anchor.snapshotID = id(99)
    if (kind === 'catalogue')
      effect.original_facts.strength_capture.fact.classification.catalogue.id = id(99)
    if (kind === 'operation')
      effect.original_facts.strength_capture.binding.operationKey = 'ui:pretend:review'
    expect(() => parseConversationWorkoutEffect(f.source, f.prepared, effect)).toThrow()
  })
  it('recovers one uncertain commit with an independent read of the exact immutable identity', async () => {
    const f = await fixture()
    let durable = false
    const rpc = vi.fn(async (name: string, _args: unknown) => {
      if (name === 'read_conversation_workout_effect')
        return { data: durable ? f.effect : { action: 'absent' }, error: null }
      if (name === 'commit_conversation_workout') {
        durable = true
        throw new Error('synthetic lost success')
      }
      throw new Error('No other RPC')
    })
    const writer = createConversationWorkoutWriter({ rpc }, { checkCurrentScope: async () => true })
    expect(rpc).not.toHaveBeenCalled()
    expect(await writer.commit(f.source, f.prepared)).toMatchObject({
      status: 'saved',
      effect: { receipt: f.effect.receipt },
    })
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_workout_effect',
      'commit_conversation_workout',
      'read_conversation_workout_effect',
    ])
    expect(rpc.mock.calls[0]?.[1]).toEqual(rpc.mock.calls[2]?.[1])
    expect(await writer.read(f.source, f.prepared)).toMatchObject({ status: 'saved' })
    expect(rpc.mock.calls.filter(([name]) => name === 'commit_conversation_workout')).toHaveLength(
      1,
    )
  })
  it('permanently closes a transiently revoked command between write and durable read', async () => {
    const f = await fixture()
    let deny = false
    const rpc = vi.fn(async (name: string) => {
      if (name === 'commit_conversation_workout') {
        deny = true
        return { data: { action: 'committed', receipt: f.effect.receipt }, error: null }
      }
      return { data: { action: 'absent' }, error: null }
    })
    const writer = createConversationWorkoutWriter(
      { rpc },
      {
        checkCurrentScope: async () => {
          if (deny) {
            deny = false
            return false
          }
          return true
        },
      },
    )
    expect(await writer.commit(f.source, f.prepared)).toMatchObject({
      status: 'reconciliation_required',
    })
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_workout_effect',
      'commit_conversation_workout',
    ])
  })
  it('never accepts rich successful mutation data without a readable durable effect', async () => {
    const f = await fixture(),
      rpc = vi.fn(async (name: string) => ({
        data:
          name === 'commit_conversation_workout'
            ? { action: 'committed', receipt: f.effect.receipt }
            : { action: 'absent' },
        error: null,
      }))
    const writer = createConversationWorkoutWriter({ rpc }, { checkCurrentScope: async () => true })
    expect(await writer.commit(f.source, f.prepared)).toMatchObject({
      status: 'reconciliation_required',
    })
    expect(rpc.mock.calls.filter(([name]) => name === 'commit_conversation_workout')).toHaveLength(
      1,
    )
  })
})
