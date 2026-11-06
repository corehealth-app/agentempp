/** Real owned PostgreSQL sources/reports from rollback-only T49 qualification.
 * These recorded values are not an authenticated HTTP or provider test. */
import { describe, expect, it } from 'vitest'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'
import { pinConversationWorkoutPreparation } from './conversation-workout-writer'
import actual from './testing/conversation-workout-report-parity-pg-golden.json'

describe('real SQL v2 workout report and unchanged TS resolver parity', () => {
  it.each(actual.cases)('preserves actual $kind source/report/preparation', ({
    source: raw,
    report,
    preparation,
  }) => {
    const context = raw.context,
      command = bindConversationWorkoutCommand(
        context.owner_id,
        `cmsg1:${context.command_id}`,
        context.source_input,
      ),
      source = parseConversationWorkoutSource(command, raw)
    expect(command.inputHash).toBe(context.input_hash)
    expect(resolveConversationWorkoutReport(source)).toEqual(report)
    expect(preparation.action).toBe('prepared')
    expect(workoutDigest(preparation.prepared)).toBe(preparation.prepared_hash)
    if (report.status === 'ready') {
      const proved = pinConversationWorkoutPreparation(source, preparation.prepared)
      expect(proved).toEqual(preparation.prepared)
      expect(proved.activity.estimated_kcal).toBeNull()
    } else expect(preparation.prepared).toEqual(report)
    expect(preparation.prepared).not.toHaveProperty('report_version')
  })
})
