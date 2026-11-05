/** Synthetic wrapper over existing reviewed source/actual PG golden inputs.
 * New v3 metadata models the current SQL schema; old literal fixtures stay intact. */
import type { Json } from '@mpp/db'
import { parseFeedbackV2Capture } from '../registration-feedback-v2-store'
import workout from '../testing/conversation-workout-pg-golden.json'
import { context, instant } from './feedback-v2-source'

export function pendingV3Capture() {
  const old = context()
  const current = {
    ...old,
    snapshot: { ...old.snapshot, exercise_energy_complete: true, updated_at: instant },
  }
  const who = {
    userId: old.user_id,
    registrationId: old.registration_id,
    kind: 'meal' as const,
    origin: 'pending_registration' as const,
  }
  const facts = parseFeedbackV2Capture(current, {
    userId: who.userId,
    registrationId: who.registrationId,
    kind: who.kind,
  }).facts
  const dayWorkouts: Array<Record<string, Json>> = []
  return {
    who,
    context: {
      version: 3,
      origin: who.origin,
      user_id: who.userId,
      registration_id: who.registrationId,
      event_hash: 'a'.repeat(64),
      local_date: facts.localDate,
      record: structuredClone(facts.registration),
      source: { kind: 'pending_registration', capture: current, command: null },
      logs: current.logs,
      snapshot: current.snapshot,
      day_workouts: dayWorkouts,
      progress: current.progress,
      clinical: current.clinical,
    },
  }
}
export function workoutV3Capture(kind: 'known' | 'unknown') {
  const golden = workout.workout_actual_golden.find((row) => row.kind === kind)
  if (!golden) throw new Error('Missing actual workout golden')
  const r = golden.effect.receipt
  const who = {
    userId: r.owner_id,
    registrationId: r.registration_id,
    kind: 'workout' as const,
    origin: 'conversation_workout' as const,
  }
  const saved = golden.effect.original_facts.workout
  const snapshot = {
    ...pendingV3Capture().context.snapshot,
    ...golden.effect.original_facts.snapshot,
    exercise_calories: kind === 'known' ? saved.estimated_kcal : 0,
    exercise_energy_complete: kind === 'known',
    updated_at: r.committed_at,
  }
  return {
    who,
    context: {
      version: 3,
      origin: who.origin,
      user_id: who.userId,
      registration_id: who.registrationId,
      event_hash: 'b'.repeat(64),
      local_date: r.local_date,
      record: { kind: 'workout', log_id: r.workout_id, ...r.activity },
      source: {
        kind: 'conversation_workout',
        input: golden.source.context.source_input,
        captured: golden.source,
        prepared: golden.preparation.prepared,
        effect: golden.effect,
        feedback_context: structuredClone({
          logs: [saved],
          snapshot,
          progress: null,
          clinical: golden.source.context.clinical,
        }),
      },
      logs: [saved],
      snapshot,
      day_workouts: null,
      progress: null,
      clinical: golden.source.context.clinical,
    },
  }
}

/** Synthetic metadata over the actual frozen-v2 capture contract. No old
 * wire literal changes; missing coverage explicitly remains unproved. */
export function frozenMealV3Capture() {
  const f = pendingV3Capture(),
    commandId = '80000000-0000-4000-8000-000000000001'
  const inputHash = 'c'.repeat(64)
  const proposal = f.context.source.capture.confirmed.proposal
  Object.assign(proposal, {
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
    source_provider_message_id: `conversation.meal/${f.who.userId}/${commandId}`,
  })
  for (const row of f.context.logs)
    row.raw_provider_message_id = `conversation.meal/${f.who.userId}/${commandId}`
  const receipt = {
    schema: 'conversation.meal-effect.v1',
    owner_id: f.who.userId,
    command_id: commandId,
    input_hash: inputHash,
    registration_id: f.who.registrationId,
    provider_key: `conversation.meal/${f.who.userId}/${commandId}`,
    meal_type: f.context.record.kind === 'meal' ? f.context.record.meal_kind : 'outro',
    local_date: f.context.local_date,
    timezone: 'UTC',
    consumed_at: '2026-11-03T12:00:00.000001Z',
    log_ids: f.context.logs.map((row) => row.id),
    effect_version: `cmeal1:${'d'.repeat(64)}`,
  }
  return {
    ...f,
    context: {
      ...f.context,
      source: {
        ...f.context.source,
        command: {
          command_id: commandId,
          epoch: f.context.clinical.epoch,
          input_hash: inputHash,
          receipt,
          continuation: null,
        },
      },
      day_workouts: null,
    },
  }
}

export function linkedMealV3Capture() {
  const f = frozenMealV3Capture(),
    parent = '80000000-0000-4000-8000-000000000002'
  const old = f.context.source.command,
    provider = `conversation.clarification/${f.who.userId}/${parent}`
  const receipt = {
    ...old.receipt,
    schema: 'conversation.meal-continuation-effect.v1',
    provider_key: provider,
    parent_command_id: parent,
    parent_input_hash: 'e'.repeat(64),
    parent_decision_hash: 'f'.repeat(64),
    epoch: old.epoch,
  }
  Object.assign(f.context.source.capture.confirmed.proposal, {
    command_protocol: 'conversation.clarification.v1',
    source_provider_message_id: provider,
  })
  for (const row of f.context.logs) row.raw_provider_message_id = provider
  const continuation = {
    parentBinding: {
      owner_id: f.who.userId,
      command_id: parent,
      input_hash: receipt.parent_input_hash,
      command_protocol: 'conversation.command.v1',
      kind: 'meal.report',
      epoch: old.epoch,
      admitted_at: '2026-11-03T10:00:00.000001Z',
    },
    childBinding: {
      owner_id: f.who.userId,
      command_id: old.command_id,
      input_hash: old.input_hash,
      command_protocol: 'conversation.clarification.v1',
      kind: 'meal.clarify',
      epoch: old.epoch,
      admitted_at: '2026-11-03T11:00:00.000001Z',
    },
    parentDecisionHash: receipt.parent_decision_hash,
    receipt,
  }
  return {
    ...f,
    context: {
      ...f.context,
      source: { ...f.context.source, command: { ...old, receipt, continuation } },
    },
  }
}
