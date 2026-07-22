import { describe, expect, it } from 'vitest'
import {
  decodeRoutineHistoryCursor,
  deriveRoutineOccurrenceStatus,
  encodeRoutineHistoryCursor,
  medicationDisclaimerAcceptanceInputSchema,
  routineActionInputSchema,
  routineHistoryQuerySchema,
  routineItemCreateInputSchema,
  routineItemListQuerySchema,
  routineItemPatchInputSchema,
  routinePreviewModeSchema,
} from './routine.js'

const UUID = '9baf14c8-6376-4a47-a9b8-9fcf2e5cefc1'
const OCCURRED_AT = '2026-07-22T08:00:00.000Z'
const CREATED_AT = '2026-07-22T08:01:00.000Z'

function validSchedule(overrides: Record<string, unknown> = {}) {
  return { local_time: '08:00', weekdays: [1, 3, 5], ...overrides }
}

function validCreate(overrides: Record<string, unknown> = {}) {
  return {
    name: 'Creatina',
    dose_text: '3 g',
    origin: 'user',
    reminders_enabled: true,
    schedules: [validSchedule()],
    ...overrides,
  }
}

function action(
  status: 'taken' | 'snoozed' | 'skipped' | 'missed',
  overrides: Record<string, unknown> = {},
) {
  return {
    status,
    occurredAt: OCCURRED_AT,
    createdAt: CREATED_AT,
    id: UUID,
    ...overrides,
  }
}

describe('routine contracts', () => {
  it('exposes the exact public enum values', () => {
    expect(routinePreviewModeSchema.options).toEqual(['private', 'name', 'name_and_dose'])
  })

  it('trims text and canonicalizes weekdays in a strict create input', () => {
    expect(
      routineItemCreateInputSchema.parse({
        name: ' Creatina ',
        dose_text: ' 3 g ',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [6, 1, 1] }],
      }),
    ).toEqual({
      name: 'Creatina',
      dose_text: '3 g',
      origin: 'professional',
      reminders_enabled: true,
      schedules: [{ local_time: '08:00', weekdays: [1, 6] }],
    })
  })

  it('enforces exact text, time, weekday, and schedule limits', () => {
    expect(routineItemCreateInputSchema.safeParse(validCreate({ name: ' ' })).success).toBe(false)
    expect(
      routineItemCreateInputSchema.safeParse(validCreate({ name: 'a'.repeat(201) })).success,
    ).toBe(false)
    expect(
      routineItemCreateInputSchema.safeParse(validCreate({ dose_text: 'a'.repeat(121) })).success,
    ).toBe(false)
    expect(routineItemCreateInputSchema.safeParse(validCreate({ origin: 'clinic' })).success).toBe(
      false,
    )
    expect(routineItemCreateInputSchema.safeParse(validCreate({ schedules: [] })).success).toBe(
      false,
    )
    expect(
      routineItemCreateInputSchema.safeParse({
        ...validCreate(),
        schedules: Array.from({ length: 17 }, (_, index) =>
          validSchedule({ local_time: `0${index}:00` }),
        ),
      }).success,
    ).toBe(false)
    for (const local_time of ['7:00', '24:00', '08:60', '08:0']) {
      expect(
        routineItemCreateInputSchema.safeParse(
          validCreate({ schedules: [validSchedule({ local_time })] }),
        ).success,
      ).toBe(false)
    }
    for (const weekdays of [[-1], [7], [1.5], []]) {
      expect(
        routineItemCreateInputSchema.safeParse(
          validCreate({ schedules: [validSchedule({ weekdays })] }),
        ).success,
      ).toBe(false)
    }
    expect(
      routineItemCreateInputSchema.safeParse(
        validCreate({
          schedules: [
            validSchedule({ weekdays: [1, 1, 3] }),
            validSchedule({ weekdays: [3, 1, 1] }),
          ],
        }),
      ).success,
    ).toBe(false)
    expect(
      routineItemCreateInputSchema.safeParse({ ...validCreate(), unexpected: true }).success,
    ).toBe(false)
  })

  it('normalizes a patch and requires a positive integer version', () => {
    expect(
      routineItemPatchInputSchema.parse({
        expected_version: 2,
        name: '  Vitamina D ',
        dose_text: ' 1 capsule ',
        schedules: [validSchedule({ weekdays: [5, 2, 2] })],
      }),
    ).toEqual({
      expected_version: 2,
      name: 'Vitamina D',
      dose_text: '1 capsule',
      schedules: [{ local_time: '08:00', weekdays: [2, 5] }],
    })
    for (const expected_version of [0, -1, 1.5]) {
      expect(routineItemPatchInputSchema.safeParse({ expected_version }).success).toBe(false)
    }
    expect(
      routineItemPatchInputSchema.safeParse({ expected_version: 1, unexpected: true }).success,
    ).toBe(false)
  })

  it('maps only the supported include_archived query values', () => {
    expect(routineItemListQuerySchema.parse({})).toEqual({ include_archived: false })
    expect(routineItemListQuerySchema.parse({ include_archived: undefined })).toEqual({
      include_archived: false,
    })
    for (const value of [false, 'false']) {
      expect(routineItemListQuerySchema.parse({ include_archived: value })).toEqual({
        include_archived: false,
      })
    }
    for (const value of [true, 'true']) {
      expect(routineItemListQuerySchema.parse({ include_archived: value })).toEqual({
        include_archived: true,
      })
    }
    for (const value of [0, 1, '0', '1', 'TRUE', 'False', null, []]) {
      expect(routineItemListQuerySchema.safeParse({ include_archived: value }).success).toBe(false)
    }
    expect(routineItemListQuerySchema.safeParse({ unknown: true }).success).toBe(false)
  })

  it('validates exact medication disclaimer acceptance', () => {
    const input = { accepted: true, version: 'medication-v1', body_hash: 'a'.repeat(64) }
    expect(medicationDisclaimerAcceptanceInputSchema.parse(input)).toEqual(input)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, accepted: false }).success,
    ).toBe(false)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, body_hash: 'A'.repeat(64) })
        .success,
    ).toBe(false)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, body_hash: 'a'.repeat(63) })
        .success,
    ).toBe(false)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, version: '' }).success,
    ).toBe(false)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, version: 'v'.repeat(65) })
        .success,
    ).toBe(false)
    expect(
      medicationDisclaimerAcceptanceInputSchema.safeParse({ ...input, extra: true }).success,
    ).toBe(false)
  })

  it('couples snooze timestamps to snoozed actions', () => {
    const base = {
      reminder_rule_id: UUID,
      scheduled_for: OCCURRED_AT,
      occurred_at: CREATED_AT,
    }
    expect(
      routineActionInputSchema.parse({
        ...base,
        status: 'snoozed',
        snoozed_until: '2026-07-22T09:00:00.000Z',
      }),
    ).toMatchObject({ status: 'snoozed' })
    expect(routineActionInputSchema.safeParse({ ...base, status: 'snoozed' }).success).toBe(false)
    expect(
      routineActionInputSchema.safeParse({ ...base, status: 'snoozed', snoozed_until: OCCURRED_AT })
        .success,
    ).toBe(false)
    for (const status of ['taken', 'skipped'] as const) {
      expect(
        routineActionInputSchema.safeParse({ ...base, status, snoozed_until: OCCURRED_AT }).success,
      ).toBe(false)
    }
    expect(
      routineActionInputSchema.safeParse({ ...base, status: 'taken', extra: true }).success,
    ).toBe(false)
  })

  it('defaults and validates history query pagination', () => {
    expect(routineHistoryQuerySchema.parse({})).toEqual({ limit: 20 })
    expect(routineHistoryQuerySchema.parse({ limit: '10' })).toEqual({ limit: 10 })
    expect(routineHistoryQuerySchema.safeParse({ limit: 0 }).success).toBe(false)
    expect(routineHistoryQuerySchema.safeParse({ limit: 51 }).success).toBe(false)
    expect(routineHistoryQuerySchema.safeParse({ limit: 1, extra: true }).success).toBe(false)
  })
})

describe('routine history cursors', () => {
  it('encodes canonical JSON as unpadded base64url and decodes it', () => {
    const input = { occurredAt: OCCURRED_AT, logId: UUID }
    const cursor = encodeRoutineHistoryCursor(input)
    expect(cursor).toBe(Buffer.from(JSON.stringify(input), 'utf8').toString('base64url'))
    expect(cursor).not.toContain('=')
    expect(decodeRoutineHistoryCursor(cursor)).toEqual(input)
  })

  it('rejects non-canonical, oversized, malformed, and unknown-key cursors', () => {
    const input = { occurredAt: OCCURRED_AT, logId: UUID }
    const cursor = encodeRoutineHistoryCursor(input)
    const payloadWithExtra = Buffer.from(
      JSON.stringify({ ...input, extra: true }),
      'utf8',
    ).toString('base64url')
    const reversedKeys = Buffer.from(
      JSON.stringify({ logId: input.logId, occurredAt: input.occurredAt }),
      'utf8',
    ).toString('base64url')
    const padded = `${cursor}=`
    for (const value of [padded, 'not-base64', payloadWithExtra, reversedKeys, 'a'.repeat(513)]) {
      expect(() => decodeRoutineHistoryCursor(value)).toThrow()
    }
    expect(() => encodeRoutineHistoryCursor({ ...input, occurredAt: 'tomorrow' })).toThrow()
    expect(() =>
      decodeRoutineHistoryCursor(Buffer.from('{bad', 'utf8').toString('base64url')),
    ).toThrow()
  })
})

describe('deriveRoutineOccurrenceStatus', () => {
  const base = { now: '2026-07-22T10:00:00.000Z', localDayEndExclusive: '2026-07-23T00:00:00.000Z' }

  it('returns pending before day end and missed at or after day end without an action', () => {
    expect(deriveRoutineOccurrenceStatus({ actions: [], ...base })).toBe('pending')
    expect(
      deriveRoutineOccurrenceStatus({ actions: [], ...base, now: base.localDayEndExclusive }),
    ).toBe('missed')
  })

  it('returns the latest stored status and supports corrective actions after missed', () => {
    expect(deriveRoutineOccurrenceStatus({ actions: [action('snoozed')], ...base })).toBe('snoozed')
    expect(
      deriveRoutineOccurrenceStatus({
        actions: [action('snoozed'), action('taken', { occurredAt: '2026-07-22T09:00:00.000Z' })],
        ...base,
      }),
    ).toBe('taken')
    expect(deriveRoutineOccurrenceStatus({ actions: [action('skipped')], ...base })).toBe('skipped')
    expect(deriveRoutineOccurrenceStatus({ actions: [action('missed')], ...base })).toBe('missed')
    expect(
      deriveRoutineOccurrenceStatus({
        actions: [action('missed'), action('taken', { occurredAt: '2026-07-23T00:01:00.000Z' })],
        ...base,
      }),
    ).toBe('taken')
  })

  it('uses occurredAt, createdAt, then descending id to break ties without mutation', () => {
    const actions = [
      action('skipped', { id: '00000000-0000-4000-8000-000000000001' }),
      action('taken', { id: '00000000-0000-4000-8000-000000000002' }),
    ]
    const copy = structuredClone(actions)
    expect(deriveRoutineOccurrenceStatus({ actions, ...base })).toBe('taken')
    expect(actions).toEqual(copy)

    const createdTie = [
      action('skipped', {
        createdAt: '2026-07-22T08:02:00.000Z',
        id: '00000000-0000-4000-8000-000000000002',
      }),
      action('taken', {
        createdAt: '2026-07-22T08:03:00.000Z',
        id: '00000000-0000-4000-8000-000000000001',
      }),
    ]
    expect(deriveRoutineOccurrenceStatus({ actions: createdTie, ...base })).toBe('taken')
  })
})
