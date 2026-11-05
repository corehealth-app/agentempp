/** Golden values were emitted by the real owned local PostgreSQL core in one
 * rollback-only qualification. This checks TS/SQL agreement; it is not HTTP QA. */
import { describe, expect, it } from 'vitest'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'
import {
  parseConversationWorkoutEffect,
  pinConversationWorkoutPreparation,
} from './conversation-workout-writer'
import actual from './testing/conversation-workout-pg-golden.json'

describe('actual PostgreSQL workout core golden agreement', () => {
  it.each(
    actual.workout_actual_golden,
  )('validates actual $kind source/preparation/strength receipt without ui-v1', ({
    kind,
    source: raw,
    preparation,
    effect,
  }) => {
    const c = raw.context
    const command = bindConversationWorkoutCommand(
      c.owner_id,
      `cmsg1:${c.command_id}`,
      c.source_input,
    )
    expect(command.inputHash).toBe(c.input_hash)
    const source = parseConversationWorkoutSource(command, raw)
    const prepared = pinConversationWorkoutPreparation(source, preparation.prepared)
    expect(workoutDigest(prepared)).toBe(preparation.prepared_hash)
    const {
      performed_at: _performed,
      local_date: _date,
      time_zone: _zone,
      energy: _energy,
      ...decision
    } = prepared
    expect(resolveConversationWorkoutReport(source)).toEqual({
      ...decision,
      activity: {
        workout_type: prepared.activity.workout_type,
        duration_min: prepared.activity.duration_min,
        intensity: prepared.activity.intensity,
      },
    })
    const proved = parseConversationWorkoutEffect(source, prepared, effect)
    expect(proved.receipt.provenance).toBe('conversation.workout.v1')
    expect(proved.receipt.activity.estimated_kcal === null).toBe(kind === 'unknown')
  })
})
