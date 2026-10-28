import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalDailyService } from './clinical-daily-service'
import { createSupabaseClinicalDailyRepository } from './supabase-clinical-daily'

const owner = 'b3b01000-0000-4000-8000-000000003001'
const key = 'b3b01000-0000-4000-8000-000000003002'
const other = 'b3b01000-0000-4000-8000-000000003003'
const hash = 'a'.repeat(64)
const calculation = {
  version: 1 as const,
  formulaKcal: 2400,
  maintenanceKcal: 2400,
  sedentaryKcal: 1900,
  proteinTarget: 144,
  maintenanceProteinTarget: 144,
}
const receipt = {
  user_id: owner,
  operation_key: key,
  result: {
    version: 1,
    availability: 'unavailable',
    reason: 'clinical_episode_unavailable',
    date: '2026-10-26',
  },
}
function client(reply: unknown = { data: receipt, error: null }) {
  const rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => reply)
  const supabase = { rpc } as unknown as ServiceClient
  return { rpc, supabase, repository: createSupabaseClinicalDailyRepository(supabase) }
}
describe('backend-only clinical daily repository', () => {
  it('constructs without I/O and only looks up the exact original owner/key receipt', async () => {
    const { rpc, repository } = client()
    expect(rpc).not.toHaveBeenCalled()
    expect(await repository.findReceipt(owner, key)).toEqual(receipt)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_clinical_daily_receipt', {
      p_user_id: owner,
      p_operation_key: key,
    })
  })
  it('uses the full APPLICATION capture with no client clock/mode/cycle/body arguments', async () => {
    const { rpc, repository } = client({ data: { user_id: owner }, error: null })
    await repository.capture(owner)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_clinical_daily_context', { p_user_id: owner })
  })
  it('applies exactly once with a detached strict calculation and context hash', async () => {
    let release!: (value: unknown) => void
    const pending = new Promise<unknown>((resolve) => {
      release = resolve
    })
    const rpc = vi.fn(() => pending)
    const repository = createSupabaseClinicalDailyRepository({ rpc } as unknown as ServiceClient)
    const values = { ...calculation }
    const result = repository.apply(owner, key, hash, values)
    values.formulaKcal = 9999
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('apply_mobile_clinical_daily', {
      p_user_id: owner,
      p_operation_key: key,
      p_context_hash: hash,
      p_calculation: calculation,
    })
    release({ data: receipt, error: null })
    expect(await result).toEqual(receipt)
  })
  it('captures the RPC receiver and method once, before awaiting', async () => {
    const contexts: unknown[] = []
    const supabase = {
      rpc: vi.fn(async function (this: unknown) {
        contexts.push(this)
        return { data: null, error: null }
      }),
    }
    const repository = createSupabaseClinicalDailyRepository(supabase as unknown as ServiceClient)
    const original = supabase.rpc
    supabase.rpc = vi.fn(async () => {
      throw new Error('replacement must not run')
    })
    expect(await repository.findReceipt(owner, key)).toBeNull()
    expect(original).toHaveBeenCalledTimes(1)
    expect(contexts).toEqual([supabase])
    expect(supabase.rpc).not.toHaveBeenCalled()
  })
  it.each([
    '40001',
    '55P03',
  ])('maps only closed SQL conflict %s without details or retry', async (code) => {
    const { rpc, repository } = client({
      data: null,
      error: { code, message: 'private risk and SQL details' },
    })
    await expect(repository.findReceipt(owner, key)).rejects.toMatchObject({
      status: 409,
      code: code === '40001' ? 'mobile_clinical_daily_changed' : 'mobile_clinical_daily_busy',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    { data: null, error: { code: '42501', message: 'private' } },
    {},
    { data: null },
    { data: receipt, error: undefined },
    { data: receipt, error: 'private' },
    { data: [], error: null },
  ])('refuses a failed or malformed lookup rather than treating it as no receipt', async (response) => {
    const { rpc, repository } = client(response)
    await expect(repository.findReceipt(owner, key)).rejects.toMatchObject({
      status: 503,
      message: 'Clinical update unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('allows null only for an absent receipt; null capture/apply is unavailable', async () => {
    const { repository } = client({ data: null, error: null })
    expect(await repository.findReceipt(owner, key)).toBeNull()
    await expect(repository.capture(owner)).rejects.toMatchObject({ status: 503 })
    await expect(repository.apply(owner, key, hash, calculation)).rejects.toMatchObject({
      status: 503,
    })
  })
  it.each([
    { ...calculation, clock: '2026-10-01' },
    { ...calculation, formulaKcal: Infinity },
    { ...calculation, proteinTarget: -1 },
    { ...calculation, version: 2 },
  ])('rejects extra or invalid backend calculation before RPC', async (value) => {
    const { rpc, repository } = client()
    await expect(
      repository.apply(owner, key, hash, value as typeof calculation),
    ).rejects.toMatchObject({ status: 503 })
    expect(rpc).not.toHaveBeenCalled()
  })
  it('rejects invalid owner/key/hash before RPC', async () => {
    const { rpc, repository } = client()
    await expect(repository.findReceipt('not-uuid', key)).rejects.toMatchObject({ status: 503 })
    await expect(repository.findReceipt(owner, 'not-uuid')).rejects.toMatchObject({ status: 503 })
    await expect(repository.apply(owner, key, 'wrong', calculation)).rejects.toMatchObject({
      status: 503,
    })
    expect(rpc).not.toHaveBeenCalled()
  })
  it('returns a detached receipt, not a producer-owned alias', async () => {
    const raw = structuredClone(receipt)
    const { repository } = client({ data: raw, error: null })
    const result = await repository.findReceipt(owner, key)
    raw.result.reason = 'changed' as typeof raw.result.reason
    expect(result).toEqual(receipt)
  })
  it('keeps original replay ahead of capture and calculation through the real service', async () => {
    const { rpc, repository } = client()
    const auth: MobileAuthContext = {
      userId: owner,
      authUserId: other,
      accessToken: 'synthetic-only',
      identity: { id: other, email: null, emailConfirmedAt: '2026-10-26T10:00:00Z' },
      patient: {
        id: owner,
        authUserId: other,
        status: 'active',
        name: null,
        email: null,
        timezone: 'America/Sao_Paulo',
        locale: 'pt-BR',
        country: 'BR',
        countryConfirmed: true,
      },
    }
    const service = createClinicalDailyService({ enabled: true, repository })
    expect(
      await service.apply(auth as Parameters<typeof service.apply>[0], { operationKey: key }),
    ).toEqual(receipt.result)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('refuses another owner acknowledgement through the real service', async () => {
    const { rpc, repository } = client({ data: { ...receipt, user_id: other }, error: null })
    const service = createClinicalDailyService({ enabled: true, repository })
    const auth: MobileAuthContext = {
      userId: owner,
      authUserId: other,
      accessToken: 'synthetic-only',
      identity: { id: other, email: null, emailConfirmedAt: '2026-10-26T10:00:00Z' },
      patient: {
        id: owner,
        authUserId: other,
        status: 'active',
        name: null,
        email: null,
        timezone: 'America/Sao_Paulo',
        locale: 'pt-BR',
        country: 'BR',
        countryConfirmed: true,
      },
    }
    await expect(
      service.apply(auth as Parameters<typeof service.apply>[0], { operationKey: key }),
    ).rejects.toMatchObject({ status: 503 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
