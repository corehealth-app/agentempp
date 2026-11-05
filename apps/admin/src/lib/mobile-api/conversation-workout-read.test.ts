import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { bindConversationWorkoutCommand, workoutDigest } from './conversation-workout-contracts'
import {
  createSupabaseConversationWorkoutReadStore,
  parseConversationWorkoutReconciliation,
} from './conversation-workout-read'
import actual from './testing/conversation-workout-pg-golden.json'

/** Real PG source/preparation/effect bytes; the reconcile envelope/current rows
 * are synthetic constructions of the existing SQL to_jsonb row contract. */
function sample(index = 0) {
  const golden = structuredClone(actual.workout_actual_golden[index])
  if (!golden) throw new Error('Missing actual PG golden')
  const c = golden.source.context,
    r = golden.effect.receipt,
    identity = {
      ownerId: c.owner_id,
      commandId: c.command_id,
      inputHash: c.input_hash,
      epoch: c.epoch,
    },
    wire = {
      action: 'available',
      source: golden.source,
      preparation: {
        prepared_hash: golden.preparation.prepared_hash,
        prepared: golden.preparation.prepared,
      },
      effect: { receipt: golden.effect.receipt, original_facts: golden.effect.original_facts },
      current: {
        status: 'present',
        workout: {
          ...golden.effect.original_facts.workout,
          created_at: r.committed_at,
          notes: 'conversation.workout.v1',
          raw_message_id: null,
        },
        snapshot: {
          ...golden.effect.original_facts.snapshot,
          calories_consumed: 0,
          calories_target: null,
          carbs_g: 0,
          closed_at: null,
          created_at: r.committed_at,
          current_protocol: null,
          daily_balance: null,
          day_closed: false,
          day_status: 'open',
          deficit_accumulated: 0,
          exercise_calories: r.activity.estimated_kcal ?? 0,
          exercise_energy_complete: r.activity.estimated_kcal !== null,
          fat_g: 0,
          gap_reminder_sent_at: null,
          protein_g: 0,
          protein_target: null,
          sleep_hours: null,
          steps: null,
          training_done: false,
          updated_at: r.committed_at,
          water_consumed_ml: 0,
          xp_earned: 0,
        },
      },
    }
  const auth = structuredClone(replyFixture().auth)
  auth.userId = identity.ownerId
  auth.patient.id = identity.ownerId
  return { golden, identity, wire, auth, profile: golden.source.context.clinical }
}

describe('closed existing workout reconciliation decoder', () => {
  it.each([
    0, 1,
  ])('preserves actual original source/preparation/effect and nullable energy (%s)', (index) => {
    const f = sample(index),
      before = JSON.stringify(f.wire),
      result = parseConversationWorkoutReconciliation(f.wire, f.identity)
    expect(JSON.stringify(result)).toBe(before)
    expect(Object.isFrozen(result)).toBe(true)
    if (index === 1)
      expect(result).toMatchObject({
        effect: { receipt: { activity: { estimated_kcal: null } } },
        current: { snapshot: { exercise_energy_complete: false } },
      })
  })

  it('preserves null admission/capture stages without manufacturing pending or preparation', () => {
    const f = sample()
    for (const source of [null, f.wire.source]) {
      const raw = { action: 'available', source, preparation: null, effect: null }
      expect(parseConversationWorkoutReconciliation(raw, f.identity)).toEqual(raw)
    }
  })

  it('reads an immutable question without fulfilling or retyping the command', () => {
    const f = sample(),
      raw = structuredClone(f.wire)
    raw.source.context.source_input.source = { channel: 'text', text: 'Fiz caminhada' }
    const command = bindConversationWorkoutCommand(
      f.identity.ownerId,
      `cmsg1:${f.identity.commandId}`,
      raw.source.context.source_input,
    )
    const identity = { ...f.identity, inputHash: command.inputHash }
    raw.source.context.input_hash = identity.inputHash
    const prepared = {
      owner_id: identity.ownerId,
      command_id: identity.commandId,
      input_hash: identity.inputHash,
      source_hash: raw.source.source_hash,
      epoch: identity.epoch,
      status: 'needs_reply',
      question: {
        key: workoutDigest({ source_hash: raw.source.source_hash, field: 'duration_min' }),
        field: 'duration_min',
        text: 'Quantos minutos durou essa atividade?',
      },
    }
    const wire = {
      action: 'available',
      source: raw.source,
      preparation: { prepared_hash: workoutDigest(prepared), prepared },
      effect: null,
    }
    expect(parseConversationWorkoutReconciliation(wire, identity)).toEqual(wire)
  })

  it('keeps original receipt and facts after removal of the live row', () => {
    const f = sample(),
      raw = { ...f.wire, current: { status: 'removed' } }
    expect(parseConversationWorkoutReconciliation(raw, f.identity)).toEqual(raw)
  })

  it('keeps original acknowledgement separate from changed current amount and coverage', () => {
    const f = sample(),
      original = JSON.stringify(f.wire.effect)
    f.wire.current.workout.duration_min = 45
    f.wire.current.workout.estimated_kcal = null
    f.wire.current.snapshot.exercise_energy_complete = false
    const result = parseConversationWorkoutReconciliation(f.wire, f.identity)
    if (result.action !== 'available') throw new Error('Missing reconciliation')
    expect(JSON.stringify(result.effect)).toBe(original)
    expect(result.current).toMatchObject({
      workout: { duration_min: 45, estimated_kcal: null },
      snapshot: { exercise_energy_complete: false },
    })
  })

  it('refuses complete current energy when its owned workout energy is unknown', () => {
    const f = sample(1)
    f.wire.current.snapshot.exercise_energy_complete = true
    expect(() => parseConversationWorkoutReconciliation(f.wire, f.identity)).toThrow()
  })

  it.each([
    [
      'source owner',
      (f: ReturnType<typeof sample>) => {
        f.wire.source.context.owner_id = f.auth.authUserId
      },
    ],
    [
      'original text',
      (f: ReturnType<typeof sample>) => {
        f.wire.source.context.source_input.source.text += ' '
      },
    ],
    [
      'epoch',
      (f: ReturnType<typeof sample>) => {
        f.identity.epoch = f.auth.authUserId
      },
    ],
    [
      'source hash',
      (f: ReturnType<typeof sample>) => {
        f.wire.source.source_hash = 'a'.repeat(64)
      },
    ],
    [
      'prepared hash',
      (f: ReturnType<typeof sample>) => {
        f.wire.preparation.prepared_hash = 'a'.repeat(64)
      },
    ],
    [
      'prepared body',
      (f: ReturnType<typeof sample>) => {
        f.wire.preparation.prepared.activity.duration_min += 1
      },
    ],
    [
      'original effect',
      (f: ReturnType<typeof sample>) => {
        f.wire.effect.original_facts.workout.id = f.auth.authUserId
      },
    ],
    [
      'current owner',
      (f: ReturnType<typeof sample>) => {
        f.wire.current.workout.user_id = f.auth.authUserId
      },
    ],
    [
      'current snapshot',
      (f: ReturnType<typeof sample>) => {
        f.wire.current.snapshot.id = f.auth.authUserId
      },
    ],
  ])('rejects changed %s instead of repairing it', (_label, mutate) => {
    const f = sample()
    mutate(f)
    expect(() => parseConversationWorkoutReconciliation(f.wire, f.identity)).toThrow()
  })

  it('refuses contradictory stages, extra data and accessor execution', () => {
    const f = sample(),
      hook = vi.fn(() => f.wire.effect)
    for (const raw of [
      { ...f.wire, source: null },
      { ...f.wire, preparation: null },
      { ...f.wire, effect: null },
      { ...f.wire, invented: true },
      { action: 'absent', effect: f.wire.effect },
    ])
      expect(() => parseConversationWorkoutReconciliation(raw, f.identity)).toThrow()
    Object.defineProperty(f.wire, 'effect', { enumerable: true, get: hook })
    expect(() => parseConversationWorkoutReconciliation(f.wire, f.identity)).toThrow()
    expect(hook).not.toHaveBeenCalled()
  })

  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'effect_conflict',
  ])('retains actual SQL refusal %s', (action) => {
    expect(parseConversationWorkoutReconciliation({ action }, sample().identity)).toEqual({
      action,
    })
  })
})

function readerSetup() {
  const f = sample(),
    events: string[] = [],
    auth = {
      verifyAccessToken: vi.fn(async () => {
        events.push('token')
        return f.auth.identity
      }),
      isAdmin: vi.fn(async () => {
        events.push('admin')
        return false
      }),
      loadPatient: vi.fn(async () => {
        events.push('patient')
        return f.auth.patient
      }),
    },
    capture = vi.fn(async () => {
      events.push('profile')
      return f.profile
    }),
    rpc = vi.fn(async () => {
      events.push('rpc')
      return { data: f.wire, error: null }
    }),
    store = createSupabaseConversationWorkoutReadStore(
      { rpc } as unknown as ServiceClient,
      f.auth,
      f.identity,
      { auth, clinical: { capture } },
    )
  return { ...f, authPort: auth, capture, rpc, events, store }
}

describe('inert workout read adapter with actual shared scope', () => {
  it('uses only the STABLE reconciliation RPC with immutable original identity and full guards', async () => {
    const f = readerSetup()
    expect(f.events).toEqual([])
    const original = structuredClone(f.identity)
    f.identity.commandId = f.auth.authUserId
    expect(await f.store.read()).toEqual(f.wire)
    expect(f.rpc.mock.calls).toEqual([
      [
        'reconcile_conversation_workout',
        {
          p_user_id: original.ownerId,
          p_command_id: original.commandId,
          p_input_hash: original.inputHash,
          p_expected_epoch: original.epoch,
        },
      ],
    ])
    expect(f.events).toEqual([
      'token',
      'admin',
      'patient',
      'profile',
      'token',
      'admin',
      'patient',
      'rpc',
      'token',
      'admin',
      'patient',
      'profile',
      'token',
      'admin',
      'patient',
    ])
  })

  it.each([
    'returned',
    'thrown',
  ])('latches scope revocation after a %s read and dispatches no later RPC', async (mode) => {
    const f = readerSetup()
    f.rpc.mockImplementationOnce(async () => {
      f.authPort.isAdmin.mockResolvedValue(true)
      if (mode === 'thrown') throw new Error('lost read')
      return { data: f.wire, error: null }
    })
    await expect(f.store.read()).rejects.toMatchObject({
      status: 403,
      code: 'patient_admin_account_conflict',
    })
    f.authPort.isAdmin.mockResolvedValue(false)
    await expect(f.store.read()).rejects.toMatchObject({ status: 403 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })

  it('observes after transport error and never retries or invokes a domain writer', async () => {
    const f = readerSetup()
    f.rpc.mockRejectedValueOnce(new Error('synthetic sensitive transport detail'))
    await expect(f.store.read()).rejects.toMatchObject({
      status: 503,
      code: 'conversation_workout_read_unavailable',
    })
    expect(f.capture).toHaveBeenCalledTimes(2)
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
})
