/** Synthetic output from the real local PostgreSQL rollback qualification, not
 * a manufactured child/receipt. Paired executable source: supabase/tests/
 * conversation_intake_media_lineage.sql. No provider or customer data. */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-intake-media-actual.json'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import { buildConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { createSupabaseConversationMealSourceFactory } from './conversation-meal-source'
import { parseConversationMealStoredSource } from './conversation-meal-writer-contracts'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'

describe('actual SQL neutral media projection conforms to internal execution codecs', () => {
  for (const row of actual.cases)
    it(row.kind, async () => {
      const selected = row.selection.selection,
        child = selected.command,
        owner = selected.intake.owner_id,
        parentInput = {
          intake_protocol: 'conversation.intake.v1',
          intake_id: selected.intake.intake_id,
          source: child.input.source,
        },
        parent = bindConversationIntake(
          owner,
          `cintake1:${selected.intake.intake_id}`,
          parentInput,
        ),
        selection = parseConversationIntakeSelection(parent, selected.intake, selected)
      expect(selection.command?.input_hash).toBe(child.input_hash)
      expect(child.input.source.user_action).toBe('report_actual_record')
      if (child.kind === 'meal.report') {
        const command = bindConversationCommand(owner, `cmsg1:${child.command_id}`, child.input),
          db = { rpc: async () => ({ data: row.source, error: null }) } as unknown as ServiceClient,
          source = await createSupabaseConversationMealSourceFactory(db).capture(command),
          interpreted = buildConversationMealInterpretationSource(command, source),
          stored = parseConversationMealStoredSource(source, command)
        expect(stored.context.schema).toBe('conversation.meal-source.v2')
        expect(interpreted.sources.map((s) => s.unit)).toEqual([
          'media_caption',
          'media_context',
          'vision_items',
        ])
      } else {
        const command = bindConversationWorkoutCommand(
            owner,
            `cmsg1:${child.command_id}`,
            child.input,
          ),
          source = parseConversationWorkoutSource(command, row.source),
          report = resolveConversationWorkoutReport(source),
          sqlReport =
            row.prepared && 'prepared' in row.prepared ? row.prepared.prepared : row.prepared
        expect(source.context.schema).toBe('conversation.workout-source.v2')
        if (sqlReport && 'activity' in sqlReport) {
          const {
            performed_at: _at,
            local_date: _date,
            time_zone: _zone,
            energy: _energy,
            ...plain
          } = sqlReport
          const { estimated_kcal: _kcal, ...activity } = plain.activity
          expect(report).toEqual({ ...plain, activity })
        } else expect(report).toEqual(sqlReport)
      }
    })
})
