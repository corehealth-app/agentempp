import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-private-media-actual.json'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
  parseConversationIntakeSource,
} from './conversation-intake-contracts'
import { assertConversationIntakeMediaCapture } from './conversation-intake-media-origin'
import { buildConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import {
  type ConversationMealStoredSource,
  parseConversationMealStoredSource,
} from './conversation-meal-writer-contracts'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'

describe('actual private-media SQL lineage through server contracts', () => {
  for (const row of actual.rows) {
    it(`retains explicit private provenance through neutral capture and selection: ${row.kind}`, () => {
      const c = row.neutral.context
      const parent = bindConversationIntake(c.owner_id, `cintake1:${c.intake_id}`, c.source_input)
      const captured = parseConversationIntakeSource(parent, row.selection.intake, {
        source_hash: row.neutral.source_hash,
        context: c,
      })
      expect(captured.context).toEqual(c)
      expect(captured.context.media).toMatchObject({ catalog_version: 2 })
      const selected = parseConversationIntakeSelection(parent, row.selection.intake, row.selection)
      expect(selected.media_projection).toEqual(row.selection.media_projection)
    })

    it(`keeps the original processing result and version for typed interpretation: ${row.kind}`, () => {
      const selected = row.selection.command
      if (selected.kind === 'meal.report') {
        const command = bindConversationCommand(
          selected.owner_id,
          `cmsg1:${selected.command_id}`,
          selected.input,
        )
        assertConversationIntakeMediaCapture(command, row.typed.context)
        const capturedAt = row.typed.captured_at
        if (typeof capturedAt !== 'string')
          throw new Error('Actual meal SQL fixture must carry its captured instant')
        const captured = {
          sourceHash: row.typed.source_hash,
          capturedAt,
          epoch: row.typed.context.epoch,
          context: row.typed.context,
        }
        // JSON is intentionally untrusted at this decoder boundary; the real
        // writer parser, rather than a fixture builder, validates every field.
        const stored = parseConversationMealStoredSource(
          captured as unknown as ConversationMealStoredSource,
          command,
        )
        expect(stored.context.media).toMatchObject({ catalog_version: 2 })
        const source = buildConversationMealInterpretationSource(command, captured)
        expect(source.media_binding).toMatchObject({ catalog_version: 2 })
        expect(source.source_hash).toBe(row.typed.source_hash)
      } else {
        const command = bindConversationWorkoutCommand(
          selected.owner_id,
          `cmsg1:${selected.command_id}`,
          selected.input,
        )
        assertConversationIntakeMediaCapture(command, row.typed.context)
        const source = parseConversationWorkoutSource(command, {
          source_hash: row.typed.source_hash,
          context: row.typed.context,
        })
        expect(source.context.media).toMatchObject({ catalog_version: 2 })
        expect(source.context.media?.processing_result).toEqual(
          row.typed.context.media.processing_result,
        )
      }
    })

    it.each([
      'drop-media-version',
      'drop-projection-version',
      'legacy-version',
      'unknown-version',
    ])(`refuses a changed source version (${row.kind}): %s`, (change) => {
      const selected = row.selection.command
      const command =
        selected.kind === 'meal.report'
          ? bindConversationCommand(
              selected.owner_id,
              `cmsg1:${selected.command_id}`,
              selected.input,
            )
          : bindConversationWorkoutCommand(
              selected.owner_id,
              `cmsg1:${selected.command_id}`,
              selected.input,
            )
      const context = structuredClone(row.typed.context)
      if (change === 'drop-media-version') Reflect.deleteProperty(context.media, 'catalog_version')
      if (change === 'drop-projection-version')
        Reflect.deleteProperty(context.intake_projection.media, 'catalog_version')
      if (change === 'legacy-version') Object.assign(context.media, { catalog_version: 1 })
      if (change === 'unknown-version')
        Object.assign(context.intake_projection.media, { catalog_version: 99 })
      expect(() => assertConversationIntakeMediaCapture(command, context)).toThrow()
    })
  }
})
