import { describe, expect, it } from 'vitest'
import { classifyGapReminderDelivery } from './daily-gap-delivery.js'

describe('classifyGapReminderDelivery', () => {
  it('aceita somente uma entrega sent com providerMessageId', () => {
    expect(
      classifyGapReminderDelivery(
        [{ status: 'sent', providerMessageId: 'wamid-gap-1' }],
        '2026-07-12T23:02:00.000Z',
      ),
    ).toEqual({
      sent: true,
      providerMessageId: 'wamid-gap-1',
      sentAt: '2026-07-12T23:02:00.000Z',
    })
  })

  it.each([
    [[]],
    [[{ status: 'failed' as const, providerMessageId: null, error: 'provider failed' }]],
    [[{ status: 'sent' as const, providerMessageId: null }]],
  ])('não confirma snapshot para resposta %j', (results) => {
    expect(classifyGapReminderDelivery(results, '2026-07-12T23:02:00.000Z')).toMatchObject({
      sent: false,
    })
  })
})
