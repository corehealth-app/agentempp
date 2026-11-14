import { describe, expect, it } from 'vitest'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { trainingExecutionInstant } from './training-execution-instant'

describe('isolated training clock preserves established nanosecond semantics', () => {
  it('retains exact existing UTC/offset/submillisecond ordering without importing meal storage at runtime', () => {
    for (const timestamp of [
      '2026-11-14T00:00:00Z',
      '2026-11-13T21:00:00-03:00',
      '2026-11-14T00:00:00.000001Z',
      '2026-11-14T00:00:00.000001001+00:00',
    ])
      expect(trainingExecutionInstant(timestamp)).toBe(conversationJournalInstant(timestamp))
    expect(trainingExecutionInstant('2026-11-14T00:00:00.000001001Z')).toBeGreaterThan(
      trainingExecutionInstant('2026-11-14T00:00:00.000001000Z'),
    )
  })
  it('rejects invalid calendar dates, year zero, missing offset and excessive precision', () => {
    for (const timestamp of [
      '2026-02-30T00:00:00Z',
      '0000-01-01T00:00:00Z',
      '2026-11-14T00:00:00',
      '2026-11-14T00:00:00.0000010001Z',
      'not a clock',
    ])
      expect(() => trainingExecutionInstant(timestamp)).toThrow()
  })
})
