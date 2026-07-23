import { encodeRoutineHistoryCursor } from '@mpp/core'
import { describe, expect, it, vi } from 'vitest'
import {
  archiveRoutineItem,
  createRoutineItem,
  listRoutineItemHistory,
  listRoutineItems,
  type RoutineItemPageRecord,
  type RoutineItemRepository,
  RoutineItemRepositoryError,
  type RoutineItemServiceDependencies,
  updateRoutineItem,
} from './routine-item-service'

const USER_ID = '00000000-0000-0000-0000-000000000701'
const AUTH_USER_ID = '00000000-0000-0000-0000-000000000702'
const ITEM_ID = '00000000-0000-0000-0000-000000000703'
const RULE_MORNING_ID = '00000000-0000-0000-0000-000000000704'
const RULE_EVENING_ID = '00000000-0000-0000-0000-000000000705'
const LOG_ID = '00000000-0000-0000-0000-000000000706'
const NEXT_LOG_ID = '00000000-0000-0000-0000-000000000707'
const NOW = new Date('2026-07-22T14:30:00.000Z')
const NEXT_CURSOR = encodeRoutineHistoryCursor({
  occurredAt: '2026-07-21T12:03:00.000Z',
  logId: NEXT_LOG_ID,
})

const auth = {
  accessToken: 'redacted-test-token',
  authUserId: AUTH_USER_ID,
  userId: USER_ID,
  identity: {
    id: AUTH_USER_ID,
    email: 'synthetic@example.invalid',
    emailConfirmedAt: '2026-07-22T10:00:00.000Z',
  },
  patient: {
    id: USER_ID,
    authUserId: AUTH_USER_ID,
    email: 'synthetic@example.invalid',
    name: 'Synthetic',
    locale: 'pt-BR' as const,
    timezone: 'America/New_York',
    country: 'US',
    countryConfirmed: true,
    status: 'active' as const,
  },
}

function itemPage(): RoutineItemPageRecord {
  return {
    localDate: '2026-07-22',
    items: [
      {
        id: ITEM_ID,
        itemType: 'supplement',
        name: 'Creatina',
        doseText: '3 g',
        origin: 'professional',
        remindersEnabled: true,
        active: true,
        archivedAt: null,
        version: 4,
        createdAt: '2026-07-20T12:00:00.000Z',
        updatedAt: '2026-07-22T12:00:00.000Z',
        schedules: [
          {
            id: RULE_EVENING_ID,
            localTime: '20:00',
            weekdays: [1, 3, 5],
            occurrence: null,
          },
          {
            id: RULE_MORNING_ID,
            localTime: '08:00',
            weekdays: [0, 1, 2, 3, 4, 5, 6],
            occurrence: {
              occurrenceKey: 'a'.repeat(64),
              scheduledFor: '2026-07-22T12:00:00.000Z',
              status: 'snoozed',
              lastActionAt: '2026-07-22T12:01:00.000Z',
              snoozedUntil: '2026-07-22T12:31:00.000Z',
            },
          },
        ],
      },
    ],
  }
}

function repository(overrides: Partial<RoutineItemRepository> = {}): RoutineItemRepository {
  return {
    list: vi.fn(async () => itemPage()),
    create: vi.fn(async () => ({ routineItemId: ITEM_ID, version: 1, archivedAt: null })),
    update: vi.fn(async () => ({ routineItemId: ITEM_ID, version: 5, archivedAt: null })),
    archive: vi.fn(async () => ({
      routineItemId: ITEM_ID,
      version: 5,
      archivedAt: '2026-07-22T15:00:00.000Z',
    })),
    history: vi.fn(async () => ({
      items: [
        {
          id: LOG_ID,
          routineItemId: ITEM_ID,
          itemType: 'supplement' as const,
          status: 'taken' as const,
          reminderRuleId: RULE_MORNING_ID,
          occurrenceKey: 'b'.repeat(64),
          scheduledFor: '2026-07-22T12:00:00.000Z',
          occurredAt: '2026-07-22T12:03:00.000Z',
          snoozedUntil: null,
          source: 'patient' as const,
          supersedesLogId: null,
          createdAt: '2026-07-22T12:03:01.000Z',
        },
      ],
      nextCursor: NEXT_CURSOR,
    })),
    ...overrides,
  }
}

function dependencies(
  overrides: Partial<RoutineItemRepository> = {},
): RoutineItemServiceDependencies {
  return { repository: repository(overrides) }
}

describe('mobile routine item service', () => {
  it('forwards the literal item type, archived filter, and server now and maps the canonical DTO', async () => {
    const deps = dependencies()

    const result = await listRoutineItems(deps, auth, 'supplement', { include_archived: true }, NOW)

    expect(deps.repository.list).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      includeArchived: true,
      now: '2026-07-22T14:30:00.000Z',
    })
    expect(result).toEqual({
      local_date: '2026-07-22',
      items: [
        {
          id: ITEM_ID,
          item_type: 'supplement',
          name: 'Creatina',
          dose_text: '3 g',
          origin: 'professional',
          reminders_enabled: true,
          active: true,
          archived_at: null,
          version: 4,
          created_at: '2026-07-20T12:00:00.000Z',
          updated_at: '2026-07-22T12:00:00.000Z',
          frequency_summary: { times_per_week: 10 },
          schedules: [
            {
              id: RULE_EVENING_ID,
              local_time: '20:00',
              weekdays: [1, 3, 5],
              occurrence: null,
            },
            {
              id: RULE_MORNING_ID,
              local_time: '08:00',
              weekdays: [0, 1, 2, 3, 4, 5, 6],
              occurrence: {
                scheduled_for: '2026-07-22T12:00:00.000Z',
                status: 'snoozed',
                last_action_at: '2026-07-22T12:01:00.000Z',
                snoozed_until: '2026-07-22T12:31:00.000Z',
              },
            },
          ],
        },
      ],
    })
    expect(JSON.stringify(result)).not.toContain('occurrenceKey')
    expect(JSON.stringify(result)).not.toContain('occurrence_key')
    expect(JSON.stringify(vi.mocked(deps.repository.list).mock.calls)).not.toContain(
      'America/New_York',
    )
  })

  it('forwards create input and returns only the canonical mutation result', async () => {
    const deps = dependencies()
    const input = {
      name: 'Creatina',
      dose_text: '3 g',
      origin: 'user' as const,
      reminders_enabled: true,
      schedules: [{ local_time: '08:00', weekdays: [1, 3, 5] }],
    }

    await expect(
      createRoutineItem(deps, auth, 'supplement', input, 'routine-create-0701', 'c'.repeat(64)),
    ).resolves.toEqual({ routine_item_id: ITEM_ID, version: 1 })
    expect(deps.repository.create).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      input,
      idempotencyKey: 'routine-create-0701',
      requestHash: 'c'.repeat(64),
    })
  })

  it('preflights active updates and retryable archives with the exact type', async () => {
    const deps = dependencies()
    const patch = { expected_version: 4, dose_text: '5 g' }

    await expect(
      updateRoutineItem(
        deps,
        auth,
        'supplement',
        ITEM_ID,
        patch,
        'routine-update-0701',
        'd'.repeat(64),
        NOW,
      ),
    ).resolves.toEqual({ routine_item_id: ITEM_ID, version: 5 })
    await expect(
      archiveRoutineItem(
        deps,
        auth,
        'supplement',
        ITEM_ID,
        'routine-archive-0701',
        'e'.repeat(64),
        NOW,
      ),
    ).resolves.toEqual({
      routine_item_id: ITEM_ID,
      version: 5,
      archived_at: '2026-07-22T15:00:00.000Z',
    })
    expect(deps.repository.list).toHaveBeenNthCalledWith(1, {
      userId: USER_ID,
      itemType: 'supplement',
      includeArchived: false,
      now: NOW.toISOString(),
    })
    expect(deps.repository.list).toHaveBeenNthCalledWith(2, {
      userId: USER_ID,
      itemType: 'supplement',
      includeArchived: true,
      now: NOW.toISOString(),
    })
    expect(deps.repository.update).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      routineItemId: ITEM_ID,
      input: patch,
      idempotencyKey: 'routine-update-0701',
      requestHash: 'd'.repeat(64),
    })
    expect(deps.repository.archive).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      routineItemId: ITEM_ID,
      idempotencyKey: 'routine-archive-0701',
      requestHash: 'e'.repeat(64),
    })
  })

  it('uses one non-disclosing 404 when typed preflight cannot see an active item', async () => {
    const deps = dependencies({ list: vi.fn(async () => ({ localDate: '2026-07-22', items: [] })) })

    await expect(
      updateRoutineItem(
        deps,
        auth,
        'medication',
        ITEM_ID,
        { expected_version: 4, name: 'Medication' },
        'routine-update-0702',
        'f'.repeat(64),
        NOW,
      ),
    ).rejects.toMatchObject({ status: 404, code: 'routine_item_not_found' })
    expect(deps.repository.update).not.toHaveBeenCalled()
  })

  it('reaches the durable archive receipt when the outer completion failed after commit', async () => {
    let archived = false
    const routineItem = itemPage().items[0]
    if (!routineItem) throw new Error('Routine item fixture is required')
    const archiveResult = {
      routineItemId: ITEM_ID,
      version: 5,
      archivedAt: '2026-07-22T15:00:00.000Z',
    }
    const list = vi.fn(async (input: { includeArchived: boolean }) => ({
      localDate: '2026-07-22',
      items:
        !archived || input.includeArchived
          ? [
              {
                ...routineItem,
                active: !archived,
                archivedAt: archived ? archiveResult.archivedAt : null,
              },
            ]
          : [],
    }))
    const archive = vi.fn(async () => {
      archived = true
      return archiveResult
    })
    const deps = dependencies({ list, archive })

    let committedResult: Awaited<ReturnType<typeof archiveRoutineItem>> | undefined
    await expect(
      (async () => {
        committedResult = await archiveRoutineItem(
          deps,
          auth,
          'supplement',
          ITEM_ID,
          'routine-archive-replay-0701',
          'e'.repeat(64),
          NOW,
        )
        throw new Error('Outer idempotency completion failed')
      })(),
    ).rejects.toThrow('Outer idempotency completion failed')
    const retry = await archiveRoutineItem(
      deps,
      auth,
      'supplement',
      ITEM_ID,
      'routine-archive-replay-0701',
      'e'.repeat(64),
      NOW,
    )

    expect(retry).toEqual(committedResult)
    expect(archive).toHaveBeenCalledTimes(2)
    expect(list).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ itemType: 'supplement', includeArchived: true }),
    )
  })

  it('keeps wrong-type archive targets non-disclosing', async () => {
    const archive = vi.fn()
    const deps = dependencies({
      list: vi.fn(async () => ({ localDate: '2026-07-22', items: [] })),
      archive,
    })

    await expect(
      archiveRoutineItem(
        deps,
        auth,
        'medication',
        ITEM_ID,
        'routine-archive-hidden-0701',
        'f'.repeat(64),
        NOW,
      ),
    ).rejects.toMatchObject({ status: 404, code: 'routine_item_not_found' })
    expect(archive).not.toHaveBeenCalled()
  })

  it('maps history without exposing occurrence keys and preserves its opaque cursor', async () => {
    const deps = dependencies()
    const cursor = encodeRoutineHistoryCursor({
      occurredAt: '2026-07-22T13:00:00.000Z',
      logId: LOG_ID,
    })

    const result = await listRoutineItemHistory(deps, auth, 'supplement', ITEM_ID, {
      limit: 10,
      cursor,
    })

    expect(deps.repository.history).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      routineItemId: ITEM_ID,
      limit: 10,
      cursor,
    })
    expect(result).toEqual({
      items: [
        {
          id: LOG_ID,
          routine_item_id: ITEM_ID,
          item_type: 'supplement',
          status: 'taken',
          reminder_rule_id: RULE_MORNING_ID,
          scheduled_for: '2026-07-22T12:00:00.000Z',
          occurred_at: '2026-07-22T12:03:00.000Z',
          snoozed_until: null,
          source: 'patient',
          supersedes_log_id: null,
          created_at: '2026-07-22T12:03:01.000Z',
        },
      ],
      next_cursor: NEXT_CURSOR,
    })
    expect(JSON.stringify(result)).not.toContain('occurrence_key')
  })

  it.each([
    ['routine_item_not_found', 404, 'routine_item_not_found'],
    ['routine_item_inactive', 404, 'routine_item_not_found'],
    ['routine_item_type_mismatch', 404, 'routine_item_not_found'],
    ['routine_occurrence_not_found', 404, 'routine_item_not_found'],
    ['routine_occurrence_ambiguous', 404, 'routine_item_not_found'],
    ['routine_item_version_conflict', 409, 'routine_item_version_conflict'],
    ['routine_schedule_conflict', 409, 'routine_schedule_conflict'],
    ['routine_transition_invalid', 409, 'routine_transition_invalid'],
    ['routine_idempotency_conflict', 409, 'idempotency_key_conflict'],
    ['routine_schedule_invalid', 422, 'routine_schedule_invalid'],
    ['routine_snooze_invalid', 422, 'routine_snooze_invalid'],
  ] as const)('maps repository code %s to %i without leaking repository details', async (reason, status, code) => {
    const deps = dependencies({
      create: vi.fn(async () => {
        throw new RoutineItemRepositoryError(reason)
      }),
    })

    const error = await createRoutineItem(
      deps,
      auth,
      'medication',
      {
        name: 'Medication',
        dose_text: '1 unit',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [1] }],
      },
      'routine-create-map-0701',
      '1'.repeat(64),
    ).catch((caught: unknown) => caught)

    expect(error).toMatchObject({ status, code })
    expect((error as { details?: unknown }).details).toBeUndefined()
    expect((error as Error).message).not.toBe(reason)
  })

  it.each([
    'medication_disclaimer_required',
    'medication_disclaimer_version_stale',
  ] as const)('returns the current legal identity for %s without exposing legal copy', async (reason) => {
    const repositoryError = Object.assign(new RoutineItemRepositoryError(reason), {
      disclaimerRequirement: {
        documentKey: 'medication_reminder_disclaimer',
        version: '2026-07-22.1',
      },
    })
    const deps = dependencies({
      create: vi.fn(async () => {
        throw repositoryError
      }),
    })

    const error = await createRoutineItem(
      deps,
      auth,
      'medication',
      {
        name: 'Medication',
        dose_text: '1 unit',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [1] }],
      },
      'routine-create-legal-0701',
      '1'.repeat(64),
    ).catch((caught: unknown) => caught)

    expect(error).toMatchObject({
      status: 428,
      code: 'medication_disclaimer_required',
      details: {
        document_key: 'medication_reminder_disclaimer',
        version: '2026-07-22.1',
      },
    })
    expect(JSON.stringify(error)).not.toContain('body')
  })
})
