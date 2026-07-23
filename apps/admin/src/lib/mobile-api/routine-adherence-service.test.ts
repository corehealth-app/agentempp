import type { RoutineActionInput } from '@mpp/core'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import {
  acceptMedicationDisclaimer,
  getMedicationDisclaimer,
  type RoutineAdherenceRepository,
  RoutineAdherenceRepositoryError,
  type RoutineAdherenceServiceDependencies,
  recordLegacyRoutineTaken,
  recordRoutineAction,
} from './routine-adherence-service'

const USER_ID = '00000000-0000-0000-0000-000000000801'
const ITEM_ID = '00000000-0000-0000-0000-000000000802'
const RULE_ID = '00000000-0000-0000-0000-000000000803'
const LOG_ID = '00000000-0000-0000-0000-000000000804'
const OCCURRENCE_KEY = 'a'.repeat(64)
const BODY_HASH = 'b'.repeat(64)
const NOW = new Date('2026-07-23T15:00:00.000Z')

const auth: MobileAuthContext = {
  accessToken: 'redacted',
  authUserId: USER_ID,
  userId: USER_ID,
  identity: { id: USER_ID, email: null, emailConfirmedAt: null },
  patient: {
    id: USER_ID,
    authUserId: USER_ID,
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}

const actionResult = {
  adherenceLogId: LOG_ID,
  occurrenceKey: OCCURRENCE_KEY,
  itemType: 'supplement' as const,
  status: 'taken' as const,
}

function repository(
  overrides: Partial<RoutineAdherenceRepository> = {},
): RoutineAdherenceRepository {
  return {
    record: vi.fn(async () => actionResult),
    resolveLegacyOccurrence: vi.fn(async () => ({
      action: 'resolved' as const,
      reminderRuleId: RULE_ID,
      scheduledFor: '2026-07-23T11:00:00.000Z',
    })),
    getMedicationDisclaimer: vi.fn(async () => ({
      documentKey: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      locale: 'pt-BR',
      body: 'Lembrete informativo sem orientacao clinica.',
      bodyHash: BODY_HASH,
      requiredFrom: '2026-07-22T00:00:00.000Z',
    })),
    acceptMedicationDisclaimer: vi.fn(async () => ({
      documentKey: 'medication_reminder_disclaimer',
      acceptedVersion: '2026-07-22.1',
      acceptedAt: '2026-07-23T15:00:00.000Z',
    })),
    ...overrides,
  }
}

function dependencies(
  overrides: Partial<RoutineAdherenceRepository> = {},
): RoutineAdherenceServiceDependencies {
  return { repository: repository(overrides) }
}

function action(overrides: Partial<RoutineActionInput> = {}): RoutineActionInput {
  return {
    status: 'taken',
    reminder_rule_id: RULE_ID,
    scheduled_for: '2026-07-23T11:00:00.000Z',
    occurred_at: '2026-07-23T11:03:00.000Z',
    ...overrides,
  }
}

describe('routine adherence service', () => {
  it('forwards the literal route type and returns a content-free action DTO', async () => {
    const record = vi.fn(async () => actionResult)
    const deps = dependencies({ record })

    const result = await recordRoutineAction(
      deps,
      auth,
      'supplement',
      ITEM_ID,
      action(),
      'routine-action-0801',
      NOW,
    )

    expect(record).toHaveBeenCalledWith({
      userId: USER_ID,
      routineItemId: ITEM_ID,
      itemType: 'supplement',
      input: action(),
      idempotencyKey: 'routine-action-0801',
    })
    expect(result).toEqual({
      adherence_log_id: LOG_ID,
      occurrence_key: OCCURRENCE_KEY,
      item_type: 'supplement',
      status: 'taken',
    })
    expect(JSON.stringify(result)).not.toMatch(/name|dose/i)
  })

  it('accepts the exact seven-day and five-minute offline boundaries', async () => {
    const record = vi.fn(async () => actionResult)
    const deps = dependencies({ record })

    await recordRoutineAction(
      deps,
      auth,
      'supplement',
      ITEM_ID,
      action({
        scheduled_for: '2026-07-16T11:00:00.000Z',
        occurred_at: '2026-07-16T15:00:00.000Z',
      }),
      'routine-boundary-past-0801',
      NOW,
    )
    await recordRoutineAction(
      deps,
      auth,
      'supplement',
      ITEM_ID,
      action({
        scheduled_for: '2026-07-23T15:00:00.000Z',
        occurred_at: '2026-07-23T15:05:00.000Z',
      }),
      'routine-boundary-future-0801',
      NOW,
    )

    expect(record).toHaveBeenCalledTimes(2)
  })

  it.each([
    '2026-07-16T14:59:59.999Z',
    '2026-07-23T15:05:00.001Z',
  ])('rejects occurred_at outside the bounded offline window: %s', async (occurredAt) => {
    const record = vi.fn()
    await expect(
      recordRoutineAction(
        dependencies({ record }),
        auth,
        'supplement',
        ITEM_ID,
        action({ occurred_at: occurredAt }),
        'routine-out-of-range-0801',
        NOW,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'occurred_at_out_of_range' })
    expect(record).not.toHaveBeenCalled()
  })

  it('rejects a future occurrence even when occurred_at is within clock-skew tolerance', async () => {
    const record = vi.fn()

    await expect(
      recordRoutineAction(
        dependencies({ record }),
        auth,
        'supplement',
        ITEM_ID,
        action({
          scheduled_for: '2026-07-23T15:01:00.000Z',
          occurred_at: '2026-07-23T15:02:00.000Z',
        }),
        'routine-future-target-0801',
        NOW,
      ),
    ).rejects.toMatchObject({ status: 404, code: 'routine_item_not_found' })
    expect(record).not.toHaveBeenCalled()
  })

  it.each([15, 30, 60])('accepts the %i-minute same-day snooze preset', async (minutes) => {
    const record = vi.fn(async () => ({ ...actionResult, status: 'snoozed' as const }))
    const occurredAt = new Date('2026-07-23T11:03:00.000Z')
    const snoozedUntil = new Date(occurredAt.getTime() + minutes * 60_000).toISOString()

    await recordRoutineAction(
      dependencies({ record }),
      auth,
      'supplement',
      ITEM_ID,
      action({ status: 'snoozed', snoozed_until: snoozedUntil }),
      `routine-snooze-${minutes}-0801`,
      NOW,
    )

    expect(record).toHaveBeenCalledOnce()
  })

  it('accepts a future custom snooze on the same patient-local day', async () => {
    const record = vi.fn(async () => ({ ...actionResult, status: 'snoozed' as const }))

    await recordRoutineAction(
      dependencies({ record }),
      auth,
      'supplement',
      ITEM_ID,
      action({ status: 'snoozed', snoozed_until: '2026-07-24T02:30:00.000Z' }),
      'routine-snooze-custom-0801',
      NOW,
    )

    expect(record).toHaveBeenCalledOnce()
  })

  it('defers historical snooze day validation when the current timezone changed', async () => {
    const record = vi.fn(async () => ({ ...actionResult, status: 'snoozed' as const }))
    const input = action({
      status: 'snoozed',
      scheduled_for: '2026-07-23T02:30:00.000Z',
      occurred_at: '2026-07-23T02:31:00.000Z',
      snoozed_until: '2026-07-23T03:30:00.000Z',
    })

    await recordRoutineAction(
      dependencies({ record }),
      auth,
      'supplement',
      ITEM_ID,
      input,
      'routine-snooze-historical-timezone-0801',
      NOW,
    )

    expect(record).toHaveBeenCalledWith(
      expect.objectContaining({
        input,
      }),
    )
  })

  it('rejects a snooze that is not after occurred_at', async () => {
    const record = vi.fn()

    await expect(
      recordRoutineAction(
        dependencies({ record }),
        auth,
        'supplement',
        ITEM_ID,
        action({ status: 'snoozed', snoozed_until: '2026-07-23T11:03:00.000Z' }),
        'routine-snooze-invalid-0801',
        NOW,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'routine_snooze_invalid' })
    expect(record).not.toHaveBeenCalled()
  })

  it.each([
    ['routine_item_inactive', 404, 'routine_item_not_found'],
    ['routine_transition_invalid', 409, 'routine_transition_invalid'],
    ['routine_idempotency_conflict', 409, 'idempotency_key_conflict'],
  ] as const)('maps %s without exposing storage details', async (reason, status, code) => {
    const deps = dependencies({
      record: vi.fn(async () => {
        throw new RoutineAdherenceRepositoryError(reason)
      }),
    })

    await expect(
      recordRoutineAction(deps, auth, 'supplement', ITEM_ID, action(), 'routine-error-0801', NOW),
    ).rejects.toMatchObject({ status, code })
  })

  it('returns the same DTO when the repository replays a retry', async () => {
    const record = vi.fn(async () => actionResult)
    const deps = dependencies({ record })
    const args = [deps, auth, 'supplement', ITEM_ID, action(), 'routine-retry-0801', NOW] as const

    const first = await recordRoutineAction(...args)
    const replay = await recordRoutineAction(...args)

    expect(replay).toEqual(first)
    expect(record).toHaveBeenCalledTimes(2)
  })
})

describe('medication disclaimer service', () => {
  it('returns exact locale-selected document fields', async () => {
    await expect(getMedicationDisclaimer(dependencies(), auth)).resolves.toEqual({
      document_key: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      locale: 'pt-BR',
      body: 'Lembrete informativo sem orientacao clinica.',
      body_hash: BODY_HASH,
      required_from: '2026-07-22T00:00:00.000Z',
    })
  })

  it('accepts only the fixed medication document and returns key/version/time', async () => {
    const accept = vi.fn(async () => ({
      documentKey: 'medication_reminder_disclaimer',
      acceptedVersion: '2026-07-22.1',
      acceptedAt: '2026-07-23T15:00:00.000Z',
    }))

    const result = await acceptMedicationDisclaimer(
      dependencies({ acceptMedicationDisclaimer: accept }),
      auth,
      { accepted: true, version: '2026-07-22.1', body_hash: BODY_HASH },
      'legal-accept-0801',
    )

    expect(accept).toHaveBeenCalledWith({
      userId: USER_ID,
      documentKey: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      bodyHash: BODY_HASH,
      idempotencyKey: 'legal-accept-0801',
    })
    expect(result).toEqual({
      document_key: 'medication_reminder_disclaimer',
      version: '2026-07-22.1',
      accepted_at: '2026-07-23T15:00:00.000Z',
    })
    expect(Object.keys(result)).toEqual(['document_key', 'version', 'accepted_at'])
  })

  it('maps a stale exact version or hash to a stable conflict', async () => {
    const deps = dependencies({
      acceptMedicationDisclaimer: vi.fn(async () => {
        throw new RoutineAdherenceRepositoryError('medication_disclaimer_version_stale')
      }),
    })

    await expect(
      acceptMedicationDisclaimer(
        deps,
        auth,
        { accepted: true, version: 'stale', body_hash: BODY_HASH },
        'legal-stale-0801',
      ),
    ).rejects.toMatchObject({ status: 409, code: 'medication_disclaimer_version_stale' })
  })
})

describe('legacy taken service wrapper', () => {
  it('records taken against the only eligible exact occurrence', async () => {
    const record = vi.fn(async () => actionResult)
    const resolveLegacyOccurrence = vi.fn(async () => ({
      action: 'resolved' as const,
      reminderRuleId: RULE_ID,
      scheduledFor: '2026-07-23T11:00:00.000Z',
    }))

    await recordLegacyRoutineTaken(
      dependencies({ record, resolveLegacyOccurrence }),
      auth,
      ITEM_ID,
      'supplement',
      { occurred_at: '2026-07-23T11:03:00.000Z' },
      'legacy-taken-0801',
      NOW,
    )

    expect(resolveLegacyOccurrence).toHaveBeenCalledWith({
      userId: USER_ID,
      routineItemId: ITEM_ID,
      itemType: 'supplement',
      occurredAt: '2026-07-23T11:03:00.000Z',
    })
    expect(record).toHaveBeenCalledWith(
      expect.objectContaining({
        itemType: 'supplement',
        input: {
          status: 'taken',
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-23T11:00:00.000Z',
          occurred_at: '2026-07-23T11:03:00.000Z',
        },
      }),
    )
  })

  it.each([
    ['not_found', 404, 'routine_item_not_found'],
    ['ambiguous', 409, 'routine_occurrence_ambiguous'],
  ] as const)('rejects a legacy %s resolution without recording', async (actionName, status, code) => {
    const record = vi.fn()
    const deps = dependencies({
      record,
      resolveLegacyOccurrence: vi.fn(async () => ({ action: actionName })),
    })

    await expect(
      recordLegacyRoutineTaken(
        deps,
        auth,
        ITEM_ID,
        'supplement',
        { occurred_at: '2026-07-23T11:03:00.000Z' },
        'legacy-taken-error-0801',
        NOW,
      ),
    ).rejects.toMatchObject({ status, code })
    expect(record).not.toHaveBeenCalled()
  })
})
