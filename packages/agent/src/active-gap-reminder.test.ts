import { describe, expect, it } from 'vitest'
import { resolveActiveGapReminderMealTypes } from './active-gap-reminder.js'

describe('resolveActiveGapReminderMealTypes', () => {
  const reference = new Date('2026-07-10T02:30:00.000Z')

  it('retorna apenas gaps do lembrete ativo enviado antes da mensagem', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: '2026-07-10T02:00:00.000Z' },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['almoco', 'jantar'] } }],
        reference,
      ),
    ).toEqual(['almoco', 'jantar'])
  })

  it('ignora snapshot apenas aberto sem lembrete', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: null },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['jantar'] } }],
        reference,
      ),
    ).toEqual([])
  })

  it('ignora lembrete que ocorreu depois do timestamp da mensagem', () => {
    expect(
      resolveActiveGapReminderMealTypes(
        { day_status: 'pending_close', gap_reminder_sent_at: '2026-07-10T03:00:00.000Z' },
        [{ raw_payload: { source: 'daily_gap_checker', gap: ['jantar'] } }],
        reference,
      ),
    ).toEqual([])
  })
})
