import { describe, expect, it, vi } from 'vitest'
import {
  buildReminderDueEvents,
  claimDueReminder,
  createReminderSchedulerRepository,
  evaluateReminderClaim,
  type ReminderClaimResult,
} from './reminder-scheduler.js'

const RULE_ID = '00000000-0000-4000-8000-000000000801'
const EVENT_ID = '00000000-0000-4000-8000-000000000802'
const SCHEDULED_FOR = '2026-07-20T18:00:00.000Z'
const FIRED_AT = '2026-07-20T18:02:00.000Z'

function claimResult(overrides: Partial<ReminderClaimResult> = {}): ReminderClaimResult {
  return {
    eventId: EVENT_ID,
    status: 'queued',
    suppressionReason: null,
    deliveryCount: 1,
    existing: false,
    ...overrides,
  }
}

describe('reminder scheduler', () => {
  it('builds deterministic events containing only a rule id and scheduled instant', () => {
    const events = buildReminderDueEvents(
      [{ reminder_rule_id: RULE_ID, scheduled_for: SCHEDULED_FOR }],
      FIRED_AT,
    )

    expect(events).toEqual([
      {
        id: `bodyflow-reminder:${RULE_ID}:${SCHEDULED_FOR}`,
        name: 'reminder.rule.due',
        data: { reminderRuleId: RULE_ID, scheduledFor: SCHEDULED_FOR },
      },
    ])
    expect(Object.keys(events[0]?.data ?? {}).sort()).toEqual(['reminderRuleId', 'scheduledFor'])
  })

  it('deduplicates retries and rejects candidates outside the discovery window', () => {
    const due = { reminder_rule_id: RULE_ID, scheduled_for: SCHEDULED_FOR }

    expect(buildReminderDueEvents([due, due], FIRED_AT)).toHaveLength(1)
    expect(() =>
      buildReminderDueEvents(
        [{ reminder_rule_id: RULE_ID, scheduled_for: '2026-07-20T18:03:00.000Z' }],
        FIRED_AT,
      ),
    ).toThrow('outside the scheduler window')
    expect(() =>
      buildReminderDueEvents(
        [{ reminder_rule_id: RULE_ID, scheduled_for: '2026-07-20T17:56:00.000Z' }],
        FIRED_AT,
      ),
    ).toThrow('outside the scheduler window')
  })

  it('uses minute boundaries and canonical timestamps for stable scheduler retries', () => {
    const [event] = buildReminderDueEvents(
      [
        {
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-20T17:57:00+00:00',
        },
      ],
      '2026-07-20T18:02:42.000Z',
    )

    expect(event).toEqual({
      id: `bodyflow-reminder:${RULE_ID}:2026-07-20T17:57:00.000Z`,
      name: 'reminder.rule.due',
      data: { reminderRuleId: RULE_ID, scheduledFor: '2026-07-20T17:57:00.000Z' },
    })
  })

  it.each([
    ['resolved', claimResult({ status: 'resolved', deliveryCount: 0 }), null],
    [
      'quiet hours',
      claimResult({ status: 'suppressed', suppressionReason: 'quiet_hours', deliveryCount: 0 }),
      'quiet_hours',
    ],
    [
      'daily limit',
      claimResult({ status: 'suppressed', suppressionReason: 'daily_limit', deliveryCount: 0 }),
      'daily_limit',
    ],
    [
      'missing official context',
      claimResult({
        status: 'suppressed',
        suppressionReason: 'missing_official_context',
        deliveryCount: 0,
      }),
      'missing_official_context',
    ],
  ] as const)('keeps %s out of provider delivery', (_label, result, expectedReason) => {
    expect(evaluateReminderClaim(result)).toEqual({
      status: result.status,
      suppressionReason: expectedReason,
      deliveryCount: 0,
      existing: false,
      providerSendAllowed: false,
    })
  })

  it('accepts an idempotent retry without creating a provider side effect', async () => {
    const repository = {
      listDue: vi.fn(),
      claim: vi.fn().mockResolvedValue(claimResult({ existing: true })),
    }

    await expect(
      claimDueReminder(
        repository,
        { reminderRuleId: RULE_ID, scheduledFor: SCHEDULED_FOR },
        FIRED_AT,
      ),
    ).resolves.toEqual({
      status: 'queued',
      suppressionReason: null,
      deliveryCount: 1,
      existing: true,
      providerSendAllowed: false,
    })
    expect(repository.claim).toHaveBeenCalledWith(RULE_ID, SCHEDULED_FOR, FIRED_AT)
    expect(Object.keys(repository)).toEqual(['listDue', 'claim'])
  })

  it('rejects inconsistent claim results instead of pretending a delivery was queued', () => {
    expect(() => evaluateReminderClaim(claimResult({ deliveryCount: 0 }))).toThrow(
      'queued reminder has no delivery',
    )
    expect(() =>
      evaluateReminderClaim(
        claimResult({ status: 'suppressed', suppressionReason: null, deliveryCount: 0 }),
      ),
    ).toThrow('suppressed reminder has no reason')
  })

  it('maps Supabase RPC rows without selecting device tokens or message text', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({
        data: [{ reminder_rule_id: RULE_ID, scheduled_for: SCHEDULED_FOR }],
        error: null,
      })
      .mockResolvedValueOnce({
        data: {
          event_id: EVENT_ID,
          status: 'suppressed',
          suppression_reason: 'quiet_hours',
          delivery_count: 0,
          existing: false,
        },
        error: null,
      })
    const repository = createReminderSchedulerRepository({ rpc } as never)

    await expect(repository.listDue(FIRED_AT, 5, 500)).resolves.toEqual([
      { reminder_rule_id: RULE_ID, scheduled_for: SCHEDULED_FOR },
    ])
    await expect(repository.claim(RULE_ID, SCHEDULED_FOR, FIRED_AT)).resolves.toEqual(
      claimResult({ status: 'suppressed', suppressionReason: 'quiet_hours', deliveryCount: 0 }),
    )
    expect(rpc).toHaveBeenNthCalledWith(1, 'list_due_reminder_rules', {
      p_fired_at: FIRED_AT,
      p_limit: 500,
      p_lookback_minutes: 5,
    })
    expect(rpc).toHaveBeenNthCalledWith(2, 'claim_reminder_event', {
      p_claimed_at: FIRED_AT,
      p_reminder_rule_id: RULE_ID,
      p_scheduled_for: SCHEDULED_FOR,
    })
  })
})
