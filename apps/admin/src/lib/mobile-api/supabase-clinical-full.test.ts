import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseClinicalFullRepository } from './supabase-clinical-full'
import wire from './testing/clinical-full-wire.json'

const owner = wire.context.user_id
const scope = { userId: owner, kind: 'REGULAR' as const, cycleId: wire.context.cycle_id }
const key = wire.receipt.operation_key
const preview = wire.receipt.preview_id
const other = 'b3b01000-0000-4000-8000-000000004151'
const bundle = () =>
  structuredClone({
    form: wire.receipt.form,
    intent: wire.receipt.intent,
    proposal: wire.receipt.proposal,
  })
function client(data: unknown) {
  const rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => ({
    data,
    error: null,
  }))
  const repository = createSupabaseClinicalFullRepository({ rpc } as unknown as ServiceClient)
  return { repository, rpc }
}
describe('narrow backend-only FULL repository', () => {
  it('requires upstream form normalization before hashing and never rewrites an original receipt', async () => {
    const input = bundle()
    Object.assign(input.form.answers, { adherence: 'prefiro_nao_responder' })
    const first = client(wire.prepared)
    await expect(
      first.repository.prepare(
        scope,
        wire.prepared.operation_key,
        wire.context.context_hash,
        input,
      ),
    ).rejects.toMatchObject({ status: 503 })
    expect(first.rpc).not.toHaveBeenCalled()
    const raw = structuredClone(wire.receipt)
    Object.assign(raw.form.answers, { adherence: 'prefiro_nao_responder' })
    const original = client(raw)
    await expect(original.repository.findReceipt(owner, preview, key)).rejects.toMatchObject({
      status: 503,
    })
    expect(original.rpc).toHaveBeenCalledTimes(1)
  })
  it('refuses a protein target that would be rounded differently by SQL before any write', async () => {
    const { repository, rpc } = client(wire.prepared)
    const input = bundle()
    input.proposal.targets.afterProtein = 126.001
    await expect(
      repository.prepare(scope, wire.prepared.operation_key, wire.context.context_hash, input),
    ).rejects.toMatchObject({ status: 503 })
    expect(rpc).not.toHaveBeenCalled()
  })
  it('validates the actual SQL context while preserving complete private facts for the evaluator', async () => {
    const { repository, rpc } = client(wire.context)
    expect(rpc).not.toHaveBeenCalled()
    expect(await repository.capture(scope)).toEqual(wire.context)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_clinical_full_context', {
      p_user_id: owner,
      p_kind: 'REGULAR',
      p_cycle_id: scope.cycleId,
    })
  })
  it('prepares one detached strict package bound to the snapshot, without a clock argument', async () => {
    let finish!: (v: unknown) => void
    const rpc = vi.fn(
      (_name: string, _args: Record<string, unknown>) =>
        new Promise<unknown>((resolve) => {
          finish = resolve
        }),
    )
    const repository = createSupabaseClinicalFullRepository({ rpc } as unknown as ServiceClient)
    const input = bundle()
    const waiting = repository.prepare(
      scope,
      wire.prepared.operation_key,
      wire.context.context_hash,
      input,
    )
    input.proposal.targets.afterKcal = 9999
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('prepare_mobile_clinical_full', {
      p_user_id: owner,
      p_kind: 'REGULAR',
      p_cycle_id: scope.cycleId,
      p_operation_key: wire.prepared.operation_key,
      p_context_hash: wire.context.context_hash,
      p_form: wire.receipt.form,
      p_intent: wire.receipt.intent,
      p_proposal: wire.receipt.proposal,
    })
    expect(Object.isFrozen(rpc.mock.calls[0]?.[1]?.p_proposal)).toBe(true)
    finish({ data: wire.prepared, error: null })
    expect(await waiting).toEqual(wire.prepared)
    expect(Object.isFrozen(input)).toBe(false)
  })
  it('looks up original receipt first without any capture or current-epoch requirement', async () => {
    const { repository, rpc } = client(wire.receipt)
    const found = await repository.findReceipt(owner, preview, key)
    expect(found).toEqual(wire.receipt)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_clinical_full_receipt', {
      p_user_id: owner,
      p_preview_id: preview,
      p_operation_key: key,
    })
    if (!found) throw new Error('fixture receipt missing')
    expect(found.review_no).toBe('1')
  })
  it('preserves unmatched alias status; receipt lookup alone never confirms or reserves a key', async () => {
    const { repository, rpc } = client({
      ...wire.receipt,
      operation_key: other,
      operation_matched: false,
    })
    expect((await repository.findReceipt(owner, preview, other))?.operation_matched).toBe(false)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0]?.[0]).toBe('get_mobile_clinical_full_receipt')
  })
  it('returns SQL NULL only for missing original receipt', async () => {
    const { repository, rpc } = client(null)
    expect(await repository.findReceipt(owner, preview, key)).toBeNull()
    await expect(repository.capture(scope)).rejects.toMatchObject({ status: 503 })
    expect(rpc).toHaveBeenCalledTimes(2)
  })
  it('confirms once with original package and checks the acknowledgement', async () => {
    const { repository, rpc } = client(wire.confirmed)
    expect(await repository.confirm(scope, preview, key, bundle())).toEqual(wire.confirmed)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('confirm_mobile_clinical_full', {
      p_user_id: owner,
      p_preview_id: preview,
      p_operation_key: key,
      p_form: wire.receipt.form,
      p_intent: wire.receipt.intent,
      p_proposal: wire.receipt.proposal,
    })
  })
  it('accepts the new completed cycle created by SAFETY despite the original null cycle', async () => {
    const input = bundle()
    Object.assign(input.form, { kind: 'SAFETY' })
    Object.assign(input.form.answers, {
      weightKg: null,
      adherence: null,
      energy: null,
      hunger: null,
      healthCheck: null,
    })
    Object.assign(input.intent, { principalConfirmed: true, bodyFat: null })
    input.proposal.principal = 'neutral_exit'
    const result = {
      ...wire.confirmed,
      result: {
        ...wire.confirmed.result,
        kind: 'SAFETY',
        principal: 'neutral_exit',
        body_fat_percent: null,
      },
    }
    const { repository } = client(result)
    expect(
      await repository.confirm(
        { userId: owner, kind: 'SAFETY', cycleId: null },
        preview,
        key,
        input,
      ),
    ).toEqual(result)
  })
  it.each([
    'user_id',
    'operation_key',
    'preview_id',
  ])('refuses substituted receipt %s instead of returning another operation', async (field) => {
    const { repository } = client({ ...wire.receipt, [field]: other })
    await expect(repository.findReceipt(owner, preview, key)).rejects.toMatchObject({ status: 503 })
  })
  it('refuses result kind, cycle, target, BF and review mismatches', async () => {
    for (const patch of [
      { kind: 'EARLY_FULL', body_fat_percent: null },
      { cycle_id: other },
      { review_id: other },
      { body_fat_percent: 25 },
      { targets: { ...wire.receipt.result.targets, afterKcal: 9999 } },
    ]) {
      const { repository } = client({
        ...wire.confirmed,
        result: { ...wire.confirmed.result, ...patch },
      })
      await expect(repository.confirm(scope, preview, key, bundle())).rejects.toMatchObject({
        status: 503,
      })
    }
  })
  it('refuses preview hash/scope changes and malformed packages before the write', async () => {
    const { repository, rpc } = client({
      ...wire.prepared,
      preview: { ...wire.prepared.preview, context_hash: 'a'.repeat(64) },
    })
    await expect(
      repository.prepare(scope, wire.prepared.operation_key, wire.context.context_hash, bundle()),
    ).rejects.toMatchObject({ status: 503 })
    for (const patch of [
      { effect: {} },
      { proposal: { ...bundle().proposal, extra: 1 } },
      { intent: { principalConfirmed: false } },
    ]) {
      await expect(
        repository.prepare(scope, key, wire.context.context_hash, { ...bundle(), ...patch }),
      ).rejects.toMatchObject({ status: 503 })
    }
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    ['40001', 409, 'changed'],
    ['55P03', 409, 'busy'],
    ['42501', 503, 'unavailable'],
    ['XX000', 503, 'unavailable'],
  ])('maps SQL %s without retry or private error disclosure', async (code, status, kind) => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { code, message: 'private SQL or credential details' },
    }))
    const repository = createSupabaseClinicalFullRepository({ rpc } as unknown as ServiceClient)
    await expect(repository.findReceipt(owner, preview, key)).rejects.toMatchObject({
      status,
      code: `mobile_clinical_full_${kind}`,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('pins the RPC method and receiver once, and never changes construction into I/O', async () => {
    const receivers: unknown[] = []
    const supabase = {
      rpc: vi.fn(async function (this: unknown) {
        receivers.push(this)
        return { data: null, error: null }
      }),
    }
    const repository = createSupabaseClinicalFullRepository(supabase as unknown as ServiceClient)
    const original = supabase.rpc
    supabase.rpc = vi.fn(async () => {
      throw new Error('replacement')
    })
    expect(
      await repository.findReceipt(owner.toUpperCase(), preview.toUpperCase(), key.toUpperCase()),
    ).toBeNull()
    expect(original).toHaveBeenCalledTimes(1)
    expect(receivers).toEqual([supabase])
    expect(supabase.rpc).not.toHaveBeenCalled()
  })
})
