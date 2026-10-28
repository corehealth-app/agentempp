import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { clinicalCloseError } from './clinical-day-close-contracts'
import {
  type ClinicalDayCloseRepository,
  createClinicalDayCloseService,
} from './clinical-day-close-service'
import { createSupabaseClinicalDayCloseRepository } from './supabase-clinical-day-close'
import original from './testing/clinical-day-close-wire.json'

const owner = original.user_id
const key = 'b3b01000-1000-4000-8000-000000003400'
const other = 'b3b01000-0000-4000-8000-000000003401'
const command = () => ({
  operationKey: key,
  from: original.request.from,
  date: original.request.date as string | null,
  timezone: original.request.timezone,
})
const scope = () => ({
  userId: owner,
  from: original.request.from,
  date: original.request.date as string | null,
  timezone: original.request.timezone,
})
const auth = (): MobileAuthContext => ({
  userId: owner,
  authUserId: other,
  accessToken: 'synthetic-only',
  identity: { id: other, email: 'qa@example.invalid', emailConfirmedAt: original.observed_at },
  patient: {
    id: owner,
    authUserId: other,
    email: 'qa@example.invalid',
    name: null,
    locale: 'pt-BR',
    timezone: original.request.timezone,
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
})
const acknowledgement = () => ({
  user_id: owner,
  operation_key: key,
  request: original.request,
  result: {
    date: original.request.date,
    closed: true,
    dryRun: false,
    late: true,
    detail: {
      caloriesConsumed: 1600,
      exerciseCalories: 0,
      storedCaloriesTarget: 2000,
      caloriesTarget: 2000,
      storedProteinTarget: 130,
      proteinTarget: 130,
      dayStatus: 'complete',
      xpEarned: 15,
      blockCredit: 900,
      newBadges: [],
      progress: {
        xpTotal: 15,
        level: 1,
        currentStreak: 1,
        longestStreak: 1,
        blocksCompleted: 0,
        deficitBlock: 900,
        badgesEarned: [],
        lastActiveDate: original.request.date,
      },
    },
  },
})
function repository() {
  return {
    findReceipt: vi.fn<ClinicalDayCloseRepository['findReceipt']>(async () => null),
    capture: vi.fn<ClinicalDayCloseRepository['capture']>(async () => structuredClone(original)),
    apply: vi.fn<ClinicalDayCloseRepository['apply']>(async () => acknowledgement()),
  }
}
describe('dormant whole day-close service', () => {
  it('looks up the original receipt before capture and real calculation, applying exactly once', async () => {
    const repo = repository(),
      service = createClinicalDayCloseService({ enabled: true, repository: repo })
    const result = await service.run(auth(), command())
    expect(result).toEqual(acknowledgement().result)
    expect(repo.findReceipt).toHaveBeenCalledWith(owner, key)
    expect(repo.capture).toHaveBeenCalledWith(scope())
    expect(repo.apply).toHaveBeenCalledTimes(1)
    expect(repo.apply.mock.calls[0]).toEqual([
      scope(),
      key,
      original.context_hash,
      expect.objectContaining({
        kind: 'close',
        blockCredit: 900,
        fields: expect.objectContaining({ xp_earned: 15 }),
        progress: expect.objectContaining({ deficitBlock: 900 }),
      }),
    ])
  })
  it('replays the original after a reset without current capture, calculation or application', async () => {
    const repo = repository()
    repo.findReceipt.mockResolvedValueOnce(acknowledgement())
    repo.capture.mockRejectedValueOnce(new Error('reset context no longer exists'))
    expect(
      await createClinicalDayCloseService({ enabled: true, repository: repo }).run(
        auth(),
        command(),
      ),
    ).toEqual(acknowledgement().result)
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it('binds owner, command and repository callbacks before the first asynchronous boundary', async () => {
    const repo = repository(),
      context = auth(),
      input = command()
    const capture = repo.capture,
      apply = repo.apply
    repo.findReceipt.mockImplementationOnce(async () => {
      context.userId = other
      input.operationKey = other
      input.date = '2026-10-24'
      repo.capture = vi.fn<ClinicalDayCloseRepository['capture']>(async () => {
        throw new Error('replaced')
      })
      repo.apply = vi.fn<ClinicalDayCloseRepository['apply']>(async () => {
        throw new Error('replaced')
      })
      return null
    })
    const service = createClinicalDayCloseService({ enabled: true, repository: repo })
    await service.run(context, input)
    expect(capture).toHaveBeenCalledWith(scope())
    expect(apply).toHaveBeenCalledTimes(1)
    expect(apply.mock.calls[0]?.[0]).toEqual(scope())
  })
  it('does no work when disabled', async () => {
    const repo = repository()
    expect(
      await createClinicalDayCloseService({ enabled: false, repository: repo }).run(
        auth(),
        command(),
      ),
    ).toMatchObject({ kind: 'unavailable', reason: 'disabled' })
    expect(repo.findReceipt).not.toHaveBeenCalled()
  })
  it.each([
    'changed',
    'busy',
    'unavailable',
  ] as const)('preserves only the closed %s error and never falls back or retries', async (kind) => {
    const repo = repository()
    repo.apply.mockRejectedValueOnce(clinicalCloseError(kind))
    await expect(
      createClinicalDayCloseService({ enabled: true, repository: repo }).run(auth(), command()),
    ).rejects.toMatchObject({ code: `mobile_clinical_close_${kind}` })
    expect(repo.apply).toHaveBeenCalledTimes(1)
  })
  it('does not treat a lookup failure as absence or expose provider text', async () => {
    const repo = repository()
    repo.findReceipt.mockRejectedValueOnce(new Error('private SQL payload'))
    await expect(
      createClinicalDayCloseService({ enabled: true, repository: repo }).run(auth(), command()),
    ).rejects.toMatchObject({
      code: 'mobile_clinical_close_unavailable',
      message: 'Day closure unavailable',
    })
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
  it.each([
    'owner',
    'key',
    'scope',
    'date',
  ] as const)('refuses a mismatched original %s receipt without recapturing', async (field) => {
    const repo = repository(),
      ack = acknowledgement()
    if (field === 'owner') ack.user_id = other
    if (field === 'key') ack.operation_key = other
    if (field === 'scope') ack.request = { ...ack.request, from: '2026-10-01' }
    if (field === 'date') ack.result.date = '2026-10-24'
    repo.findReceipt.mockResolvedValueOnce(ack)
    await expect(
      createClinicalDayCloseService({ enabled: true, repository: repo }).run(auth(), command()),
    ).rejects.toThrow()
    expect(repo.capture).not.toHaveBeenCalled()
    expect(repo.apply).not.toHaveBeenCalled()
  })
})
describe('backend-only whole-close RPC adapter', () => {
  it('binds the receiver and exposes only the three narrow RPCs with no clock', async () => {
    const rpc = vi.fn(async function (this: unknown, name: string) {
      expect(this).toBe(client)
      return {
        data: name === 'get_mobile_clinical_day_close_receipt' ? null : original,
        error: null,
      }
    })
    const client = { rpc }
    const repo = createSupabaseClinicalDayCloseRepository(client as unknown as ServiceClient)
    client.rpc = vi.fn(async () => {
      throw new Error('replaced')
    })
    expect(await repo.findReceipt(owner, key)).toBeNull()
    expect(await repo.capture(scope())).toEqual(original)
    expect(rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_day_close_receipt',
      'capture_mobile_clinical_day_close',
    ])
    expect(rpc.mock.calls[1]).toEqual([
      'capture_mobile_clinical_day_close',
      {
        p_user_id: owner,
        p_from: scope().from,
        p_close_date: scope().date,
        p_expected_timezone: scope().timezone,
      },
    ])
  })
  it.each([
    ['40001', 'changed'],
    ['55P03', 'busy'],
    ['XX000', 'unavailable'],
  ] as const)('maps SQLSTATE %s without copying SQL details', async (code, kind) => {
    const rpc = vi.fn(async () => ({ data: null, error: { code, message: 'private SQL payload' } }))
    const repo = createSupabaseClinicalDayCloseRepository({ rpc } as unknown as ServiceClient)
    await expect(repo.capture(scope())).rejects.toMatchObject({
      code: `mobile_clinical_close_${kind}`,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
