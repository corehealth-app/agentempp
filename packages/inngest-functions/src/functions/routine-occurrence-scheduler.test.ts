import { describe, expect, it, vi } from 'vitest'
import { allFunctions, routineOccurrenceSchedulerFn, routineSnoozeClaimFn } from '../index.js'
import {
  buildRoutineSnoozeDueEvents,
  claimRoutineSnooze,
  createRoutineOccurrenceSchedulerRepository,
  discoverRoutineSnoozeDueEvents,
  finalizeRoutineOccurrences,
  type RoutineFinalizerCursor,
  type RoutineSnoozeClaimResult,
} from './routine-occurrence-scheduler.js'

const LOG_ID = '00000000-0000-4000-8000-000000000901'
const SECOND_LOG_ID = '00000000-0000-4000-8000-000000000902'
const EVENT_ID = '00000000-0000-4000-8000-000000000903'
const USER_ID = '00000000-0000-4000-8000-000000000904'
const RULE_ID = '00000000-0000-4000-8000-000000000905'
const SECOND_RULE_ID = '00000000-0000-4000-8000-000000000906'
const SNOOZED_UNTIL = '2026-07-20T18:15:00.000Z'
const FIRED_AT = '2026-07-20T18:15:42.000Z'

function claimResult(overrides: Partial<RoutineSnoozeClaimResult> = {}): RoutineSnoozeClaimResult {
  return {
    eventId: EVENT_ID,
    status: 'queued',
    suppressionReason: null,
    deliveryCount: 1,
    existing: false,
    ...overrides,
  }
}

describe('routine occurrence scheduler', () => {
  it('builds one technical event per snooze action and collapses duplicate rows', () => {
    const row = { adherence_log_id: LOG_ID, snoozed_until: SNOOZED_UNTIL }

    const events = buildRoutineSnoozeDueEvents([row, row], FIRED_AT)

    expect(events).toEqual([
      {
        id: `bodyflow-routine-snooze:${LOG_ID}:${SNOOZED_UNTIL}`,
        name: 'routine.snooze.due',
        data: { adherenceLogId: LOG_ID, snoozedUntil: SNOOZED_UNTIL },
      },
    ])
    expect(Object.keys(events[0]?.data ?? {}).sort()).toEqual(['adherenceLogId', 'snoozedUntil'])
    expect(JSON.stringify(events[0]?.data)).not.toMatch(
      /itemName|dose|legal|email|phone|wpp|contact/i,
    )
  })

  it('accepts only exact candidates inside the 15-minute discovery window', () => {
    expect(
      buildRoutineSnoozeDueEvents(
        [{ adherence_log_id: LOG_ID, snoozed_until: '2026-07-20T18:00:00.000Z' }],
        FIRED_AT,
      ),
    ).toHaveLength(1)
    expect(() =>
      buildRoutineSnoozeDueEvents(
        [{ adherence_log_id: LOG_ID, snoozed_until: '2026-07-20T17:59:59.999Z' }],
        FIRED_AT,
      ),
    ).toThrow('outside the scheduler window')
    expect(() =>
      buildRoutineSnoozeDueEvents(
        [{ adherence_log_id: LOG_ID, snoozed_until: '2026-07-20T18:16:00.000Z' }],
        FIRED_AT,
      ),
    ).toThrow('outside the scheduler window')
  })

  it('advances the complete snooze keyset across pages', async () => {
    const rows = [
      { adherence_log_id: LOG_ID, snoozed_until: '2026-07-20T18:10:00.000Z' },
      { adherence_log_id: SECOND_LOG_ID, snoozed_until: '2026-07-20T18:10:00.000Z' },
      {
        adherence_log_id: '00000000-0000-4000-8000-000000000907',
        snoozed_until: SNOOZED_UNTIL,
      },
    ]
    const repository = {
      listDueSnoozes: vi
        .fn()
        .mockResolvedValueOnce(rows.slice(0, 2))
        .mockResolvedValueOnce(rows.slice(2)),
      claimSnooze: vi.fn(),
      finalizeDue: vi.fn(),
    }

    const events = await discoverRoutineSnoozeDueEvents(repository, FIRED_AT, 15, 2, 3)

    expect(events).toHaveLength(3)
    expect(repository.listDueSnoozes).toHaveBeenNthCalledWith(1, FIRED_AT, 15, 2, null)
    expect(repository.listDueSnoozes).toHaveBeenNthCalledWith(2, FIRED_AT, 15, 2, {
      snoozedUntil: '2026-07-20T18:10:00.000Z',
      adherenceLogId: SECOND_LOG_ID,
    })
  })

  it('fails closed when snooze discovery reaches its page ceiling', async () => {
    let page = 0
    const repository = {
      listDueSnoozes: vi.fn().mockImplementation(async () => {
        const first = 910 + page * 2
        page += 1
        return [first, first + 1].map((suffix) => ({
          adherence_log_id: `00000000-0000-4000-8000-${suffix.toString().padStart(12, '0')}`,
          snoozed_until: SNOOZED_UNTIL,
        }))
      }),
      claimSnooze: vi.fn(),
      finalizeDue: vi.fn(),
    }

    await expect(discoverRoutineSnoozeDueEvents(repository, FIRED_AT, 15, 2, 2)).rejects.toThrow(
      'routine snooze pagination limit exceeded',
    )
  })

  it('chains the complete finalizer tuple until the database reports completion', async () => {
    const firstCursor: RoutineFinalizerCursor = {
      scheduledFor: '2026-07-19T18:00:00.000Z',
      userId: USER_ID,
      ruleId: RULE_ID,
    }
    const repository = {
      listDueSnoozes: vi.fn(),
      claimSnooze: vi.fn(),
      finalizeDue: vi
        .fn()
        .mockResolvedValueOnce({ processedCount: 2, finalizedCount: 2, nextCursor: firstCursor })
        .mockResolvedValueOnce({ processedCount: 1, finalizedCount: 1, nextCursor: null }),
    }

    await expect(finalizeRoutineOccurrences(repository, FIRED_AT, 2, 3)).resolves.toEqual({
      processedCount: 3,
      finalizedCount: 3,
      pages: 2,
    })
    expect(repository.finalizeDue).toHaveBeenNthCalledWith(1, FIRED_AT, 2, null)
    expect(repository.finalizeDue).toHaveBeenNthCalledWith(2, FIRED_AT, 2, firstCursor)
  })

  it('rejects non-advancing finalizer cursors and page-ceiling exhaustion', async () => {
    const firstCursor: RoutineFinalizerCursor = {
      scheduledFor: '2026-07-19T18:00:00.000Z',
      userId: USER_ID,
      ruleId: RULE_ID,
    }
    const nextCursor: RoutineFinalizerCursor = {
      scheduledFor: '2026-07-19T18:00:00.000Z',
      userId: USER_ID,
      ruleId: SECOND_RULE_ID,
    }
    const stalledRepository = {
      listDueSnoozes: vi.fn(),
      claimSnooze: vi.fn(),
      finalizeDue: vi
        .fn()
        .mockResolvedValueOnce({ processedCount: 1, finalizedCount: 1, nextCursor: firstCursor })
        .mockResolvedValueOnce({ processedCount: 1, finalizedCount: 0, nextCursor: firstCursor }),
    }
    const cappedRepository = {
      listDueSnoozes: vi.fn(),
      claimSnooze: vi.fn(),
      finalizeDue: vi
        .fn()
        .mockResolvedValueOnce({ processedCount: 1, finalizedCount: 1, nextCursor: firstCursor })
        .mockResolvedValueOnce({ processedCount: 1, finalizedCount: 1, nextCursor }),
    }

    await expect(finalizeRoutineOccurrences(stalledRepository, FIRED_AT, 1, 3)).rejects.toThrow(
      'routine finalizer did not advance its cursor',
    )
    await expect(finalizeRoutineOccurrences(cappedRepository, FIRED_AT, 1, 2)).rejects.toThrow(
      'routine finalizer pagination limit exceeded',
    )
  })

  it('claims one snooze action without enabling provider sending', async () => {
    const repository = {
      listDueSnoozes: vi.fn(),
      claimSnooze: vi.fn().mockResolvedValue(claimResult({ existing: true })),
      finalizeDue: vi.fn(),
    }

    await expect(
      claimRoutineSnooze(
        repository,
        { adherenceLogId: LOG_ID, snoozedUntil: SNOOZED_UNTIL },
        FIRED_AT,
      ),
    ).resolves.toEqual({
      status: 'queued',
      suppressionReason: null,
      deliveryCount: 1,
      existing: true,
      providerSendAllowed: false,
    })
    expect(repository.claimSnooze).toHaveBeenCalledWith(LOG_ID, FIRED_AT)
  })

  it('maps only technical RPC fields and registers both local functions', async () => {
    const finalCursor = {
      scheduled_for: '2026-07-19T18:00:00.000Z',
      user_id: USER_ID,
      rule_id: RULE_ID,
    }
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({
        data: [{ adherence_log_id: LOG_ID, snoozed_until: SNOOZED_UNTIL }],
        error: null,
      })
      .mockResolvedValueOnce({
        data: {
          event_id: EVENT_ID,
          status: 'queued',
          suppression_reason: null,
          delivery_count: 1,
          existing: false,
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: { processed_count: 1, finalized_count: 1, next_cursor: finalCursor },
        error: null,
      })
    const repository = createRoutineOccurrenceSchedulerRepository({ rpc } as never)

    await repository.listDueSnoozes(FIRED_AT, 15, 500, {
      snoozedUntil: SNOOZED_UNTIL,
      adherenceLogId: LOG_ID,
    })
    await repository.claimSnooze(LOG_ID, FIRED_AT)
    await repository.finalizeDue(FIRED_AT, 250, {
      scheduledFor: finalCursor.scheduled_for,
      userId: USER_ID,
      ruleId: RULE_ID,
    })

    expect(rpc).toHaveBeenNthCalledWith(1, 'list_due_routine_snoozes', {
      p_fired_at: FIRED_AT,
      p_lookback_minutes: 15,
      p_limit: 500,
      p_after_snoozed_until: SNOOZED_UNTIL,
      p_after_log_id: LOG_ID,
    })
    expect(rpc).toHaveBeenNthCalledWith(2, 'claim_routine_snooze_event', {
      p_adherence_log_id: LOG_ID,
      p_claimed_at: FIRED_AT,
    })
    expect(rpc).toHaveBeenNthCalledWith(3, 'finalize_due_routine_occurrences', {
      p_now: FIRED_AT,
      p_limit: 250,
      p_after_scheduled_for: finalCursor.scheduled_for,
      p_after_user_id: USER_ID,
      p_after_rule_id: RULE_ID,
    })
    expect(allFunctions).toContain(routineOccurrenceSchedulerFn)
    expect(allFunctions).toContain(routineSnoozeClaimFn)
  })
})
