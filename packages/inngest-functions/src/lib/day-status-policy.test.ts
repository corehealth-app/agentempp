import { describe, expect, it } from 'vitest'
import { resolveClosedDayStatus } from './day-status-policy.js'

describe('resolveClosedDayStatus', () => {
  it('marca user_skipped quando houve skip explícito e nenhum gap segue aberto', () => {
    expect(
      resolveClosedDayStatus({
        existingDayStatus: null,
        reminderSent: true,
        hasActivity: true,
        gapCount: 0,
        skippedCount: 1,
        fallbackPattern: false,
      }),
    ).toBe('user_skipped')
  })

  it('gap ainda aberto após lembrete vence um skip parcial e zera o crédito', () => {
    expect(
      resolveClosedDayStatus({
        existingDayStatus: 'user_skipped',
        reminderSent: true,
        hasActivity: true,
        gapCount: 1,
        skippedCount: 1,
        fallbackPattern: false,
      }),
    ).toBe('incomplete_no_response')
  })

  it('mantém complete sem skip e sem gap cobrado', () => {
    expect(
      resolveClosedDayStatus({
        existingDayStatus: null,
        reminderSent: false,
        hasActivity: true,
        gapCount: 2,
        skippedCount: 0,
        fallbackPattern: false,
      }),
    ).toBe('complete')
  })
})
