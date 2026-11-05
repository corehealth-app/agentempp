/** Actual whole-close SQL values, captured from the owned rollback-only stack.
 * This is contract/replay evidence, not authenticated HTTP/native QA. */
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { clinicalClosedResultSchema } from './clinical-day-close-contracts'
import { createClinicalDayCloseService } from './clinical-day-close-service'
import actual from './testing/conversation-workout-close-pg-golden.json'

describe('actual PG closer acknowledgement availability', () => {
  it.each(
    actual.workout_close_golden,
  )('preserves the exact $kind receipt through strict parser and consumer replay', async ({
    kind,
    envelope,
  }) => {
    expect(clinicalClosedResultSchema.parse(envelope.result)).toEqual(envelope.result)
    const auth: MobileAuthContext = {
      userId: envelope.user_id,
      authUserId: '139c0000-0000-4000-8000-000000000098',
      accessToken: 'synthetic-only',
      identity: {
        id: '139c0000-0000-4000-8000-000000000098',
        email: 'closer@example.invalid',
        emailConfirmedAt: '2026-11-04T00:00:00Z',
      },
      patient: {
        id: envelope.user_id,
        authUserId: '139c0000-0000-4000-8000-000000000098',
        email: 'closer@example.invalid',
        name: null,
        locale: 'pt-BR',
        timezone: envelope.request.timezone,
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    }
    const capture = vi.fn(async () => {
      throw new Error('No regeneration of original receipt')
    })
    const apply = vi.fn(async () => {
      throw new Error('No repeat close')
    })
    const service = createClinicalDayCloseService({
      enabled: true,
      repository: {
        findReceipt: async () => envelope,
        capture,
        apply,
      },
    })
    const result = await service.run(auth, {
      operationKey: envelope.operation_key,
      from: envelope.request.from,
      date: envelope.request.date,
      timezone: envelope.request.timezone,
    })
    expect(result).toEqual(envelope.result)
    expect(result).toMatchObject({ detail: { exerciseCalories: kind === 'unknown' ? null : 0 } })
    expect(capture).not.toHaveBeenCalled()
    expect(apply).not.toHaveBeenCalled()
  })
  it('rejects null without v2, numeric partial with v2 and contradictory availability', () => {
    const original = actual.workout_close_golden.find((c) => c.kind === 'unknown')?.envelope.result
    if (!original) throw new Error('Missing actual unknown receipt')
    const unknown = structuredClone(original)
    expect(
      clinicalClosedResultSchema.safeParse({ ...unknown, calculation_version: undefined }).success,
    ).toBe(false)
    expect(
      clinicalClosedResultSchema.safeParse({
        ...unknown,
        detail: { ...unknown.detail, exerciseCalories: 0 },
      }).success,
    ).toBe(false)
    expect(
      clinicalClosedResultSchema.safeParse({
        ...unknown,
        detail: { ...unknown.detail, exerciseEnergy: { status: 'available' } },
      }).success,
    ).toBe(false)
    expect(
      clinicalClosedResultSchema.safeParse({
        ...unknown,
        detail: { ...unknown.detail, blockCredit: 100 },
      }).success,
    ).toBe(false)
  })
})
