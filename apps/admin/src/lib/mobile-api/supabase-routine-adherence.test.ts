import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { RoutineAdherenceRepositoryError } from './routine-adherence-service'
import { createSupabaseRoutineAdherenceDependencies } from './supabase-routine-adherence'

const USER_ID = '00000000-0000-0000-0000-000000000811'
const ITEM_ID = '00000000-0000-0000-0000-000000000812'
const RULE_ID = '00000000-0000-0000-0000-000000000813'
const SECOND_RULE_ID = '00000000-0000-0000-0000-000000000814'
const LOG_ID = '00000000-0000-0000-0000-000000000815'
const OCCURRENCE_KEY = 'a'.repeat(64)
const BODY_HASH = 'b'.repeat(64)

afterEach(() => {
  vi.restoreAllMocks()
})

describe('Supabase routine adherence adapter', () => {
  it('records an exact action through the trusted patient-source RPC contract', async () => {
    const rpc = vi.fn(async () => ({
      data: {
        adherence_log_id: LOG_ID,
        occurrence_key: OCCURRENCE_KEY,
        item_type: 'medication',
        status: 'snoozed',
      },
      error: null,
    }))
    const repository = createSupabaseRoutineAdherenceDependencies(
      { rpc } as unknown as ServiceClient,
      { requestId: 'request-adherence-0811' },
    ).repository

    await expect(
      repository.record({
        userId: USER_ID,
        routineItemId: ITEM_ID,
        itemType: 'medication',
        input: {
          status: 'snoozed',
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-23T11:00:00.000Z',
          occurred_at: '2026-07-23T11:03:00.000Z',
          snoozed_until: '2026-07-23T11:33:00.000Z',
        },
        idempotencyKey: 'routine-action-0811',
      }),
    ).resolves.toEqual({
      adherenceLogId: LOG_ID,
      occurrenceKey: OCCURRENCE_KEY,
      itemType: 'medication',
      status: 'snoozed',
    })

    expect(rpc).toHaveBeenCalledWith('record_routine_occurrence_action_atomic', {
      p_user_id: USER_ID,
      p_item_id: ITEM_ID,
      p_expected_item_type: 'medication',
      p_reminder_rule_id: RULE_ID,
      p_scheduled_for: '2026-07-23T11:00:00.000Z',
      p_status: 'snoozed',
      p_occurred_at: '2026-07-23T11:03:00.000Z',
      p_snoozed_until: '2026-07-23T11:33:00.000Z',
      p_idempotency_key: 'routine-action-0811',
    })
    const serialized = JSON.stringify(rpc.mock.calls)
    expect(serialized).not.toContain('source')
    expect(serialized).not.toContain('supersedes')
    expect(serialized).not.toContain('occurrence_key')
  })

  it('parses a retry replay as the same exact action result', async () => {
    const payload = {
      adherence_log_id: LOG_ID,
      occurrence_key: OCCURRENCE_KEY,
      item_type: 'supplement',
      status: 'taken',
    }
    const rpc = vi.fn().mockResolvedValue({ data: payload, error: null })
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc,
    } as unknown as ServiceClient).repository
    const command = {
      userId: USER_ID,
      routineItemId: ITEM_ID,
      itemType: 'supplement' as const,
      input: {
        status: 'taken' as const,
        reminder_rule_id: RULE_ID,
        scheduled_for: '2026-07-23T11:00:00.000Z',
        occurred_at: '2026-07-23T11:03:00.000Z',
      },
      idempotencyKey: 'routine-replay-0811',
    }

    const first = await repository.record(command)
    const replay = await repository.record(command)

    expect(replay).toEqual(first)
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it('resolves the only nonterminal occurrence for the exact legacy item and type', async () => {
    const rpc = vi.fn(async () => ({
      data: {
        local_date: '2026-07-23',
        items: [
          {
            id: ITEM_ID,
            item_type: 'supplement',
            schedules: [
              {
                id: RULE_ID,
                occurrence: {
                  scheduled_for: '2026-07-23T11:00:00.000Z',
                  status: 'pending',
                },
              },
              {
                id: SECOND_RULE_ID,
                occurrence: {
                  scheduled_for: '2026-07-23T23:00:00.000Z',
                  status: 'taken',
                },
              },
            ],
          },
        ],
      },
      error: null,
    }))
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc,
    } as unknown as ServiceClient).repository

    await expect(
      repository.resolveLegacyOccurrence({
        userId: USER_ID,
        routineItemId: ITEM_ID,
        itemType: 'supplement',
        occurredAt: '2026-07-23T15:00:00.000Z',
      }),
    ).resolves.toEqual({
      action: 'resolved',
      reminderRuleId: RULE_ID,
      scheduledFor: '2026-07-23T11:00:00.000Z',
    })
    expect(rpc).toHaveBeenCalledWith('list_mobile_routine_items', {
      p_user_id: USER_ID,
      p_item_type: 'supplement',
      p_include_archived: false,
      p_now: '2026-07-23T15:00:00.000Z',
    })
  })

  it.each([
    [[], { action: 'not_found' }],
    [
      [
        {
          id: RULE_ID,
          occurrence: { scheduled_for: '2026-07-23T11:00:00.000Z', status: 'pending' },
        },
        {
          id: SECOND_RULE_ID,
          occurrence: { scheduled_for: '2026-07-23T23:00:00.000Z', status: 'pending' },
        },
      ],
      { action: 'ambiguous' },
    ],
  ] as const)('does not silently choose among %i eligible legacy schedules', async (schedules, expected) => {
    const rpc = vi.fn(async () => ({
      data: {
        local_date: '2026-07-23',
        items: [{ id: ITEM_ID, item_type: 'supplement', schedules }],
      },
      error: null,
    }))
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc,
    } as unknown as ServiceClient).repository

    await expect(
      repository.resolveLegacyOccurrence({
        userId: USER_ID,
        routineItemId: ITEM_ID,
        itemType: 'supplement',
        occurredAt: '2026-07-23T15:00:00.000Z',
      }),
    ).resolves.toEqual(expected)
  })

  it('gets the exact stored-locale medication disclaimer', async () => {
    const rpc = vi.fn(async () => ({
      data: {
        document_key: 'medication_reminder_disclaimer',
        version: '2026-07-22.1',
        locale: 'en-US',
        body: 'Informational reminder text.',
        body_hash: BODY_HASH,
        required_from: '2026-07-22T00:00:00.000Z',
      },
      error: null,
    }))
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc,
    } as unknown as ServiceClient).repository

    await expect(repository.getMedicationDisclaimer(USER_ID)).resolves.toEqual({
      documentKey: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      locale: 'en-US',
      body: 'Informational reminder text.',
      bodyHash: BODY_HASH,
      requiredFrom: '2026-07-22T00:00:00.000Z',
    })
    expect(rpc).toHaveBeenCalledWith('get_mobile_legal_document', {
      p_user_id: USER_ID,
      p_document_key: 'medication_reminder_disclaimer',
    })
  })

  it('accepts the exact document identity through the legal RPC', async () => {
    const rpc = vi.fn(async () => ({
      data: {
        document_key: 'medication_reminder_disclaimer',
        accepted_version: '2026-07-22.1',
        accepted_at: '2026-07-23T15:00:00.000Z',
      },
      error: null,
    }))
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc,
    } as unknown as ServiceClient).repository

    await expect(
      repository.acceptMedicationDisclaimer({
        userId: USER_ID,
        documentKey: 'medication_reminder_disclaimer',
        version: '2026-07-22.1',
        bodyHash: BODY_HASH,
        idempotencyKey: 'legal-accept-0811',
      }),
    ).resolves.toEqual({
      documentKey: 'medication_reminder_disclaimer',
      acceptedVersion: '2026-07-22.1',
      acceptedAt: '2026-07-23T15:00:00.000Z',
    })
    expect(rpc).toHaveBeenCalledWith('accept_mobile_legal_document', {
      p_user_id: USER_ID,
      p_document_key: 'medication_reminder_disclaimer',
      p_version: '2026-07-22.1',
      p_body_hash: BODY_HASH,
      p_idempotency_key: 'legal-accept-0811',
    })
  })

  it.each([
    ['routine_occurrence_terminal', 'routine_transition_invalid'],
    ['routine_occurrence_action_out_of_order', 'routine_transition_invalid'],
    ['invalid_routine_snooze_time', 'routine_snooze_invalid'],
    ['routine_action_idempotency_conflict', 'routine_idempotency_conflict'],
    ['legal_document_version_mismatch', 'medication_disclaimer_version_stale'],
  ] as const)('maps database message %s to %s', async (message, reason) => {
    const repository = createSupabaseRoutineAdherenceDependencies({
      rpc: vi.fn(async () => ({ data: null, error: { code: '22023', message } })),
    } as unknown as ServiceClient).repository

    await expect(
      repository.record({
        userId: USER_ID,
        routineItemId: ITEM_ID,
        itemType: 'supplement',
        input: {
          status: 'taken',
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-23T11:00:00.000Z',
          occurred_at: '2026-07-23T11:03:00.000Z',
        },
        idempotencyKey: 'routine-error-0811',
      }),
    ).rejects.toEqual(new RoutineAdherenceRepositoryError(reason))
  })

  it('logs only request ID, operation, and allowlisted database code for unknown failures', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const repository = createSupabaseRoutineAdherenceDependencies(
      {
        rpc: vi.fn(async () => ({
          data: null,
          error: { code: 'secret-code', message: 'patient name and dose leaked' },
        })),
      } as unknown as ServiceClient,
      { requestId: 'request-adherence-0811' },
    ).repository

    await expect(repository.getMedicationDisclaimer(USER_ID)).rejects.toMatchObject({
      reason: 'internal',
    })
    expect(consoleError).toHaveBeenCalledWith('[mobile-routine-adherence] operation_failed', {
      request_id: 'request-adherence-0811',
      operation: 'get_legal',
      database_code: 'unknown_error',
    })
    const serialized = JSON.stringify(consoleError.mock.calls)
    expect(serialized).not.toContain(USER_ID)
    expect(serialized).not.toContain('patient name')
    expect(serialized).not.toContain('dose')
  })
})
