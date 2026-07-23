import { encodeRoutineHistoryCursor } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { RoutineItemRepositoryError } from './routine-item-service'
import { createSupabaseRoutineItemDependencies } from './supabase-routine-items'

const USER_ID = '00000000-0000-0000-0000-000000000711'
const ITEM_ID = '00000000-0000-0000-0000-000000000712'
const RULE_ID = '00000000-0000-0000-0000-000000000713'
const LOG_ID = '00000000-0000-0000-0000-000000000714'
const BEFORE_LOG_ID = '00000000-0000-0000-0000-000000000715'
const NOW = '2026-07-22T14:30:00.000Z'

function listPayload(overrides: Record<string, unknown> = {}) {
  return {
    local_date: '2026-07-22',
    items: [
      {
        id: ITEM_ID,
        item_type: 'supplement',
        name: 'Creatina',
        dose_text: '3 g',
        origin: 'user',
        reminders_enabled: true,
        active: true,
        archived_at: null,
        version: 2,
        created_at: '2026-07-20T12:00:00.000Z',
        updated_at: '2026-07-22T12:00:00.000Z',
        schedules: [
          {
            id: RULE_ID,
            local_time: '08:00',
            weekdays: [1, 3, 5],
            occurrence: {
              occurrence_key: 'a'.repeat(64),
              scheduled_for: '2026-07-22T12:00:00.000Z',
              status: 'pending',
              last_action_at: null,
              snoozed_until: null,
            },
          },
        ],
      },
    ],
    ...overrides,
  }
}

function historyPayload(overrides: Record<string, unknown> = {}) {
  return {
    items: [
      {
        id: LOG_ID,
        routine_item_id: ITEM_ID,
        item_type: 'supplement',
        status: 'taken',
        reminder_rule_id: RULE_ID,
        occurrence_key: 'b'.repeat(64),
        scheduled_for: '2026-07-22T12:00:00.000Z',
        occurred_at: '2026-07-22T12:03:00.000Z',
        snoozed_until: null,
        source: 'patient',
        supersedes_log_id: null,
        created_at: '2026-07-22T12:03:01.000Z',
      },
    ],
    next_cursor: {
      occurred_at: '2026-07-22T12:03:00.000Z',
      log_id: LOG_ID,
    },
    ...overrides,
  }
}

function serviceClient(rpc: ReturnType<typeof vi.fn>, from = vi.fn()): ServiceClient {
  return { rpc, from } as unknown as ServiceClient
}

afterEach(() => {
  vi.restoreAllMocks()
})

describe('Supabase routine item adapter', () => {
  it('lists with the exact Task 3 RPC parameters and parses stable schedule order', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: listPayload(), error: null })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc), {
      requestId: 'request-routine-0711',
    }).repository

    await expect(
      repository.list({
        userId: USER_ID,
        itemType: 'supplement',
        includeArchived: true,
        now: NOW,
      }),
    ).resolves.toEqual({
      localDate: '2026-07-22',
      items: [
        expect.objectContaining({
          id: ITEM_ID,
          itemType: 'supplement',
          doseText: '3 g',
          schedules: [
            {
              id: RULE_ID,
              localTime: '08:00',
              weekdays: [1, 3, 5],
              occurrence: {
                occurrenceKey: 'a'.repeat(64),
                scheduledFor: '2026-07-22T12:00:00.000Z',
                status: 'pending',
                lastActionAt: null,
                snoozedUntil: null,
              },
            },
          ],
        }),
      ],
    })
    expect(rpc).toHaveBeenCalledWith('list_mobile_routine_items', {
      p_user_id: USER_ID,
      p_item_type: 'supplement',
      p_include_archived: true,
      p_now: NOW,
    })
  })

  it('creates from the canonical RPC result and never performs a follow-up table read', async () => {
    const from = vi.fn()
    const rpc = vi.fn().mockResolvedValue({
      data: { routine_item_id: ITEM_ID, version: 1 },
      error: null,
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc, from)).repository
    const input = {
      name: 'Creatina',
      dose_text: '3 g',
      origin: 'professional' as const,
      reminders_enabled: true,
      schedules: [{ local_time: '08:00', weekdays: [1, 3, 5] }],
    }

    await expect(
      repository.create({
        userId: USER_ID,
        itemType: 'supplement',
        input,
        idempotencyKey: 'routine-create-0711',
        requestHash: 'c'.repeat(64),
      }),
    ).resolves.toEqual({ routineItemId: ITEM_ID, version: 1, archivedAt: null })
    expect(rpc).toHaveBeenCalledWith('create_mobile_routine_item', {
      p_user_id: USER_ID,
      p_item_type: 'supplement',
      p_payload: input,
      p_idempotency_key: 'routine-create-0711',
      p_request_hash: 'c'.repeat(64),
    })
    expect(from).not.toHaveBeenCalled()
  })

  it('updates with expected_version outside the exact patch and returns the RPC result directly', async () => {
    const from = vi.fn()
    const rpc = vi.fn().mockResolvedValue({
      data: { routine_item_id: ITEM_ID, version: 5 },
      error: null,
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc, from)).repository

    await expect(
      repository.update({
        userId: USER_ID,
        itemType: 'medication',
        routineItemId: ITEM_ID,
        input: { expected_version: 4, name: 'Medication', reminders_enabled: false },
        idempotencyKey: 'routine-update-0711',
        requestHash: 'd'.repeat(64),
      }),
    ).resolves.toEqual({ routineItemId: ITEM_ID, version: 5, archivedAt: null })
    expect(rpc).toHaveBeenCalledWith('update_mobile_routine_item', {
      p_user_id: USER_ID,
      p_item_id: ITEM_ID,
      p_expected_version: 4,
      p_patch: { name: 'Medication', reminders_enabled: false },
      p_idempotency_key: 'routine-update-0711',
      p_request_hash: 'd'.repeat(64),
    })
    expect(from).not.toHaveBeenCalled()
  })

  it('archives with the exact Task 3 RPC parameters and parses archived_at', async () => {
    const from = vi.fn()
    const rpc = vi.fn().mockResolvedValue({
      data: {
        routine_item_id: ITEM_ID,
        version: 6,
        archived_at: '2026-07-22T15:00:00.000Z',
      },
      error: null,
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc, from)).repository

    await expect(
      repository.archive({
        userId: USER_ID,
        itemType: 'medication',
        routineItemId: ITEM_ID,
        idempotencyKey: 'routine-archive-0711',
        requestHash: 'e'.repeat(64),
      }),
    ).resolves.toEqual({
      routineItemId: ITEM_ID,
      version: 6,
      archivedAt: '2026-07-22T15:00:00.000Z',
    })
    expect(rpc).toHaveBeenCalledWith('archive_mobile_routine_item', {
      p_user_id: USER_ID,
      p_item_id: ITEM_ID,
      p_idempotency_key: 'routine-archive-0711',
      p_request_hash: 'e'.repeat(64),
    })
    expect(from).not.toHaveBeenCalled()
  })

  it('decodes the incoming history cursor and encodes the database tuple opaquely', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: historyPayload(), error: null })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc)).repository
    const cursor = encodeRoutineHistoryCursor({
      occurredAt: '2026-07-21T10:00:00.000Z',
      logId: BEFORE_LOG_ID,
    })

    const result = await repository.history({
      userId: USER_ID,
      itemType: 'supplement',
      routineItemId: ITEM_ID,
      limit: 10,
      cursor,
    })

    expect(rpc).toHaveBeenCalledWith('list_mobile_routine_history', {
      p_user_id: USER_ID,
      p_item_id: ITEM_ID,
      p_item_type: 'supplement',
      p_limit: 10,
      p_before_occurred_at: '2026-07-21T10:00:00.000Z',
      p_before_log_id: BEFORE_LOG_ID,
    })
    expect(result).toEqual({
      items: [
        expect.objectContaining({
          id: LOG_ID,
          occurrenceKey: 'b'.repeat(64),
          occurredAt: '2026-07-22T12:03:00.000Z',
        }),
      ],
      nextCursor: encodeRoutineHistoryCursor({
        occurredAt: '2026-07-22T12:03:00.000Z',
        logId: LOG_ID,
      }),
    })
    expect(result.nextCursor).not.toContain(LOG_ID)
  })

  it('sends null cursor tuple values and preserves a null next cursor', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: historyPayload({ items: [], next_cursor: null }),
      error: null,
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc)).repository

    await expect(
      repository.history({
        userId: USER_ID,
        itemType: 'medication',
        routineItemId: ITEM_ID,
        limit: 20,
      }),
    ).resolves.toEqual({ items: [], nextCursor: null })
    expect(rpc).toHaveBeenCalledWith(
      'list_mobile_routine_history',
      expect.objectContaining({ p_before_occurred_at: null, p_before_log_id: null }),
    )
  })

  it('rejects malformed input and output cursors before exposing storage details', async () => {
    const inputRpc = vi.fn()
    const inputRepository = createSupabaseRoutineItemDependencies(
      serviceClient(inputRpc),
    ).repository
    await expect(
      inputRepository.history({
        userId: USER_ID,
        itemType: 'supplement',
        routineItemId: ITEM_ID,
        limit: 20,
        cursor: 'not-a-cursor',
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError('invalid_cursor'))
    expect(inputRpc).not.toHaveBeenCalled()

    const outputRpc = vi.fn().mockResolvedValue({
      data: historyPayload({ next_cursor: { occurred_at: 'secret', log_id: LOG_ID } }),
      error: null,
    })
    const outputRepository = createSupabaseRoutineItemDependencies(
      serviceClient(outputRpc),
    ).repository
    await expect(
      outputRepository.history({
        userId: USER_ID,
        itemType: 'supplement',
        routineItemId: ITEM_ID,
        limit: 20,
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
  })

  it.each([
    ['routine_item_not_found', 'routine_item_not_found'],
    ['routine_item_inactive', 'routine_item_inactive'],
    ['routine_item_type_mismatch', 'routine_item_type_mismatch'],
    ['routine_item_version_conflict', 'routine_item_version_conflict'],
    ['routine_schedule_invalid', 'routine_schedule_invalid'],
    ['routine_schedule_conflict', 'routine_schedule_conflict'],
    ['routine_occurrence_not_found', 'routine_occurrence_not_found'],
    ['routine_occurrence_ambiguous', 'routine_occurrence_ambiguous'],
    ['routine_transition_invalid', 'routine_transition_invalid'],
    ['routine_snooze_invalid', 'routine_snooze_invalid'],
    ['routine_idempotency_conflict', 'routine_idempotency_conflict'],
    ['medication_disclaimer_required', 'medication_disclaimer_required'],
    ['medication_disclaimer_version_stale', 'medication_disclaimer_version_stale'],
    ['routine_mutation_idempotency_conflict', 'routine_idempotency_conflict'],
    ['medication_legal_acceptance_required', 'medication_disclaimer_required'],
    ['legal_document_version_mismatch', 'medication_disclaimer_version_stale'],
    ['invalid_routine_schedules', 'routine_schedule_invalid'],
    ['duplicate_routine_schedule', 'routine_schedule_invalid'],
  ] as const)('normalizes database message %s to %s', async (message, reason) => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'P0001', message } })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc)).repository

    await expect(
      repository.create({
        userId: USER_ID,
        itemType: 'medication',
        input: {
          name: 'Medication',
          dose_text: '1 unit',
          origin: 'user',
          reminders_enabled: true,
          schedules: [{ local_time: '08:00', weekdays: [1] }],
        },
        idempotencyKey: 'routine-create-map-0711',
        requestHash: 'f'.repeat(64),
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError(reason))
  })

  it('treats P0002 as non-disclosing not found even when the provider message changes', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: 'P0002', message: 'private provider detail' },
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc)).repository

    await expect(
      repository.history({
        userId: USER_ID,
        itemType: 'supplement',
        routineItemId: ITEM_ID,
        limit: 20,
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError('routine_item_not_found'))
  })

  it('maps an inaccessible archive RPC to the same non-disclosing repository reason', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: 'P0002', message: 'private archive ownership detail' },
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc)).repository

    await expect(
      repository.archive({
        userId: USER_ID,
        itemType: 'medication',
        routineItemId: ITEM_ID,
        idempotencyKey: 'routine-archive-hidden-0711',
        requestHash: '4'.repeat(64),
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError('routine_item_not_found'))
  })

  it.each([
    ['list', listPayload({ unexpected: true })],
    ['create', { routine_item_id: ITEM_ID, version: 0 }],
    ['history', historyPayload({ extra: 'not allowed' })],
  ])('rejects malformed %s RPC payloads through the opaque storage error', async (operation, data) => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({ data, error: null })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc), {
      requestId: 'request-routine-parse-0711',
    }).repository

    if (operation === 'list') {
      await expect(
        repository.list({
          userId: USER_ID,
          itemType: 'supplement',
          includeArchived: false,
          now: NOW,
        }),
      ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    } else if (operation === 'create') {
      await expect(
        repository.create({
          userId: USER_ID,
          itemType: 'supplement',
          input: {
            name: 'Creatina',
            dose_text: '3 g',
            origin: 'user',
            reminders_enabled: true,
            schedules: [{ local_time: '08:00', weekdays: [1] }],
          },
          idempotencyKey: 'routine-create-parse-0711',
          requestHash: '1'.repeat(64),
        }),
      ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    } else {
      await expect(
        repository.history({
          userId: USER_ID,
          itemType: 'supplement',
          routineItemId: ITEM_ID,
          limit: 20,
        }),
      ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    }

    expect(consoleError).toHaveBeenCalledWith('[mobile-routine-items] operation_failed', {
      request_id: 'request-routine-parse-0711',
      operation: `parse_${operation}`,
      database_code: 'invalid_response',
    })
  })

  it.each([
    ['update', null],
    ['update', { routine_item_id: ITEM_ID, version: 0 }],
    ['archive', null],
    ['archive', { routine_item_id: ITEM_ID, version: 6 }],
  ] as const)('fails closed for %s payload %j with technical-only logging', async (operation, data) => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({ data, error: null })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc), {
      requestId: 'request-routine-mutation-parse-0711',
    }).repository

    if (operation === 'update') {
      await expect(
        repository.update({
          userId: USER_ID,
          itemType: 'supplement',
          routineItemId: ITEM_ID,
          input: { expected_version: 5, dose_text: '5 g' },
          idempotencyKey: 'routine-update-parse-0711',
          requestHash: '2'.repeat(64),
        }),
      ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    } else {
      await expect(
        repository.archive({
          userId: USER_ID,
          itemType: 'supplement',
          routineItemId: ITEM_ID,
          idempotencyKey: 'routine-archive-parse-0711',
          requestHash: '3'.repeat(64),
        }),
      ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    }

    expect(consoleError).toHaveBeenCalledWith('[mobile-routine-items] operation_failed', {
      request_id: 'request-routine-mutation-parse-0711',
      operation: `parse_${operation}`,
      database_code: 'invalid_response',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(USER_ID)
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(ITEM_ID)
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('5 g')
  })

  it('logs only request_id, safe operation, and a normalized database code for unknown failures', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: {
        code: 'synthetic-patient@example.invalid',
        message: 'secret SQL message for a patient',
      },
    })
    const repository = createSupabaseRoutineItemDependencies(serviceClient(rpc), {
      requestId: 'request-routine-0711',
    }).repository

    await expect(
      repository.list({
        userId: USER_ID,
        itemType: 'supplement',
        includeArchived: false,
        now: NOW,
      }),
    ).rejects.toEqual(new RoutineItemRepositoryError('internal'))
    expect(consoleError).toHaveBeenCalledWith('[mobile-routine-items] operation_failed', {
      request_id: 'request-routine-0711',
      operation: 'list',
      database_code: 'unknown_error',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('secret SQL')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(USER_ID)
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(ITEM_ID)
  })

  it('keeps the Supabase RPC receiver bound', async () => {
    const client = {
      marker: 'service-client',
      rpc(this: { marker: string }) {
        if (this.marker !== 'service-client') throw new Error('lost receiver')
        return Promise.resolve({ data: { local_date: '2026-07-22', items: [] }, error: null })
      },
    }
    const repository = createSupabaseRoutineItemDependencies(
      client as unknown as ServiceClient,
    ).repository

    await expect(
      repository.list({
        userId: USER_ID,
        itemType: 'supplement',
        includeArchived: false,
        now: NOW,
      }),
    ).resolves.toEqual({ localDate: '2026-07-22', items: [] })
  })
})
