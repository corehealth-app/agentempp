/** Actual complete reconcile DTOs from the owned local PostgreSQL function,
 * emitted in an existing rollback-only qualification with synthetic accounts.
 * This closes the row-shape gap in the private adapter, not an HTTP/Auth gate. */
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { bindConversationWorkoutCommand } from './conversation-workout-contracts'
import { parseConversationWorkoutReconciliation } from './conversation-workout-read'
import actual from './testing/conversation-workout-reconcile-pg-golden.json'

describe('actual PostgreSQL workout reconciliation agreement', () => {
  it('binds the exported rows to the exact integrated SQL producer', () => {
    const source = readFileSync(
      new URL(
        '../../../../../supabase/migrations/20261104235316_conversation_workout_atomic.sql',
        import.meta.url,
      ),
      'utf8',
    )
    expect(createHash('sha256').update(source).digest('hex')).toBe(
      actual.qualification.core_migration_sha256,
    )
    const body = source.match(
      /CREATE FUNCTION public\.reconcile_conversation_workout\([^;]*?AS \$\$([\s\S]*?)\$\$;/u,
    )?.[1]
    expect(body).toBeDefined()
    expect(
      createHash('sha256')
        .update(body ?? '')
        .digest('hex'),
    ).toBe(actual.reconcile_prosrc_sha256)
    expect(actual.qualification.transaction).toBe('ROLLBACK')
    expect(actual.workout_reconcile_actual_golden.map((row) => row.kind)).toEqual([
      'known_workout',
      'unknown_workout',
    ])
  })

  it.each(
    actual.workout_reconcile_actual_golden,
  )('decodes the complete real $kind source, effect and current rows unchanged', (row) => {
    const command = bindConversationWorkoutCommand(
        row.bound_command.ownerId,
        `cmsg1:${row.bound_command.commandId}`,
        row.bound_command.command,
      ),
      raw = structuredClone(row.response),
      before = JSON.stringify(raw),
      decoded = parseConversationWorkoutReconciliation(raw, {
        ownerId: command.ownerId,
        commandId: command.commandId,
        inputHash: command.inputHash,
        epoch: row.epoch,
      })
    expect(command).toEqual(row.bound_command)
    expect(JSON.stringify(decoded)).toBe(before)
    expect(JSON.stringify(raw)).toBe(before)
    expect(Object.isFrozen(decoded)).toBe(true)
    expect(decoded).toMatchObject({
      action: 'available',
      effect: {
        receipt: {
          provenance: 'conversation.workout.v1',
          activity: { estimated_kcal: row.kind === 'known_workout' ? 154 : null },
        },
      },
      current: {
        status: 'present',
        snapshot: { exercise_energy_complete: row.kind === 'known_workout' },
      },
    })
  })
})
