import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { normalizeClinicalFullCommand } from './clinical-full-command'
import { createSupabaseClinicalFullRepository } from './supabase-clinical-full'
import wire from './testing/clinical-full-wire.json'

const scope = { userId: wire.context.user_id, kind: 'REGULAR', cycleId: wire.context.cycle_id }
const key = wire.prepared.operation_key
const preview = wire.prepared.preview.preview_id
const confirmation = wire.confirmed.operation_key
const other = 'b3b01000-0000-4000-8000-000000004399'
const bundle = () =>
  structuredClone({
    form: wire.receipt.form,
    intent: wire.receipt.intent,
    proposal: wire.receipt.proposal,
  })
const command = () => ({
  form: bundle().form,
  choice: { kind: 'keep' },
  measureConfirmed: false,
  bodyFat: bundle().intent.bodyFat,
})
const original = () => ({
  ...structuredClone(wire.prepared),
  command_version: 1,
  command: command(),
  command_hash: 'd'.repeat(64),
  normalization_context: { sex: 'masculino', heightCm: 180 },
  package: bundle(),
})
function setup(data: unknown) {
  const rpc = vi.fn(
    async (
      _name: string,
      _args: Record<string, unknown>,
    ): Promise<{ data: unknown; error: unknown }> => ({ data, error: null }),
  )
  return { rpc, repo: createSupabaseClinicalFullRepository({ rpc } as unknown as ServiceClient) }
}

describe('original normalized FULL command', () => {
  it('uses only the supplied historical sex for rejected BF, preserving accepted male input', () => {
    const input = command()
    Object.assign(input.form, {
      preference: { action: 'change', value: { kind: 'body_fat', percent: 11 } },
    })
    const copy = structuredClone(input)
    for (const sex of ['feminino', null]) {
      const result = normalizeClinicalFullCommand(input, { sex, heightCm: 180 })
      expect(result.command.form.preference).toBeNull()
      expect(result.preference.normalizedPreference).toBeNull()
    }
    expect(
      normalizeClinicalFullCommand(input, { sex: 'masculino', heightCm: 180 }).command.form
        .preference,
    ).toEqual(input.form.preference)
    expect(input).toEqual(copy)
  })
  it('binds weight refusal to original height without rounding or a current profile', () => {
    const input = command()
    Object.assign(input.form, {
      preference: { action: 'change', value: { kind: 'weight', kg: 60 } },
    })
    expect(
      normalizeClinicalFullCommand(input, { sex: 'masculino', heightCm: 200.01 }).command.form
        .preference,
    ).toBeNull()
    expect(
      normalizeClinicalFullCommand(input, { sex: 'masculino', heightCm: 160 }).command.form
        .preference,
    ).toEqual(input.form.preference)
  })
  it('normalizes refused values to one identity, while binding choice and measure independently', () => {
    const first = command(),
      second = command()
    Object.assign(first.form, {
      preference: { action: 'change', value: { kind: 'body_fat', percent: 8 } },
    })
    Object.assign(second.form, {
      preference: { action: 'change', value: { kind: 'body_fat', percent: 9 } },
    })
    const ctx = { sex: 'masculino', heightCm: 180 }
    expect(normalizeClinicalFullCommand(first, ctx).command).toEqual(
      normalizeClinicalFullCommand(second, ctx).command,
    )
    second.measureConfirmed = true
    expect(normalizeClinicalFullCommand(first, ctx).command).not.toEqual(
      normalizeClinicalFullCommand(second, ctx).command,
    )
    expect(() => normalizeClinicalFullCommand({ ...first, calories: 999 }, ctx)).toThrow()
  })
  it('adds only raw-input defaults; malformed historical context is never repaired', () => {
    const input = command()
    const { measureConfirmed: _measure, ...raw } = input
    expect(
      normalizeClinicalFullCommand(raw, { sex: null, heightCm: null }).command.measureConfirmed,
    ).toBe(false)
    for (const ctx of [
      {},
      { sex: 'masculino', heightCm: 0 },
      { sex: null, heightCm: null, currentSex: 'feminino' },
    ])
      expect(() => normalizeClinicalFullCommand(raw, ctx)).toThrow()
  })
  it('supplies only the original private no-plan origin and refuses a substituted origin', () => {
    const form = {
      ...bundle().form,
      phase: null,
      noPlanOrigin: {
        kind: 'confirmed_no_plan',
        signupGeneration: other,
        signupEpoch: other,
        completedAt: '2026-10-01T00:00:00.000000Z',
      },
      answers: {
        ...Object.fromEntries(Object.keys(bundle().form.answers).map((k) => [k, null])),
        weightKg: 84,
        healthCheck: { kind: 'none' },
      },
      preference: null,
    }
    const { noPlanOrigin: _origin, ...publicForm } = form
    const input = { ...command(), form: publicForm }
    expect(
      normalizeClinicalFullCommand(input, { sex: null, heightCm: null }, form).command.form,
    ).toEqual(form)
    expect(() =>
      normalizeClinicalFullCommand(
        {
          ...input,
          form: { ...form, noPlanOrigin: { ...form.noPlanOrigin, signupEpoch: confirmation } },
        },
        { sex: null, heightCm: null },
        form,
      ),
    ).toThrow()
  })
})

describe('command-aware FULL transport', () => {
  it('looks up exactly one original key or preview without capture, clock or reservation', async () => {
    const { repo, rpc } = setup(original())
    expect(await repo.findPrepared(scope.userId, { prepareOperationKey: key })).toEqual(original())
    expect(rpc.mock.calls).toEqual([
      [
        'get_mobile_clinical_full_command',
        { p_user_id: scope.userId, p_preview_id: null, p_prepare_operation_key: key },
      ],
    ])
    expect(await repo.findPrepared(scope.userId, { previewId: preview })).toEqual(original())
    for (const lookup of [{}, { previewId: preview, prepareOperationKey: key }])
      await expect(repo.findPrepared(scope.userId, lookup)).rejects.toMatchObject({ status: 503 })
    expect(rpc).toHaveBeenCalledTimes(2)
  })
  it('returns NULL only for absent command lookup, never a failed query', async () => {
    const { repo, rpc } = setup(null)
    expect(await repo.findPrepared(scope.userId, { previewId: preview })).toBeNull()
    rpc.mockResolvedValue({ data: null, error: { code: '40001' } })
    await expect(repo.findPrepared(scope.userId, { previewId: preview })).rejects.toMatchObject({
      status: 409,
    })
    expect(rpc).toHaveBeenCalledTimes(2)
  })
  it('preserves original prepared ACK when a racing same-key prepare has a newer calculated package', async () => {
    const { repo, rpc } = setup(original())
    const newer = bundle()
    newer.proposal.targets.afterKcal = 1999
    expect(await repo.prepareCommand(scope, key, 'e'.repeat(64), command(), newer)).toEqual(
      original(),
    )
    expect(rpc.mock.calls[0]?.[0]).toBe('prepare_mobile_clinical_full_command')
    expect(rpc.mock.calls[0]?.[1]?.p_command).toEqual(command())
    expect(Object.isFrozen(rpc.mock.calls[0]?.[1]?.p_command)).toBe(true)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('binds command/form/photo identity before write and refuses a changed command in prepared ACK', async () => {
    const { repo, rpc } = setup(original())
    const changed = command()
    changed.measureConfirmed = true
    await expect(
      repo.prepareCommand(scope, key, wire.context.context_hash, changed, bundle()),
    ).rejects.toMatchObject({ status: 503 })
    const altered = command()
    altered.form.answers.weightKg = 81
    await expect(
      repo.prepareCommand(scope, key, wire.context.context_hash, altered, bundle()),
    ).rejects.toMatchObject({ status: 503 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('distinguishes original prepare key from confirmation/alias key and validates the original package', async () => {
    const data = { ...structuredClone(wire.receipt), prepared: original() }
    const { repo, rpc } = setup(data)
    expect(await repo.findCommandReceipt(scope.userId, preview, confirmation)).toEqual(data)
    expect(rpc.mock.calls[0]?.[0]).toBe('get_mobile_clinical_full_command_receipt')
    const alias = { ...data, operation_key: other, operation_matched: false }
    const second = setup(alias)
    expect(
      (await second.repo.findCommandReceipt(scope.userId, preview, other))?.operation_matched,
    ).toBe(false)
    expect(second.rpc).toHaveBeenCalledTimes(1)
    const mismatch = structuredClone(data)
    mismatch.prepared.package.proposal.targets.afterKcal = 1999
    await expect(
      setup(mismatch).repo.findCommandReceipt(scope.userId, preview, confirmation),
    ).rejects.toMatchObject({ status: 503 })
  })
  it('confirms original command/package once and validates the original result', async () => {
    const { repo, rpc } = setup(wire.confirmed)
    expect(await repo.confirmCommand(scope, preview, confirmation, command(), bundle())).toEqual(
      wire.confirmed,
    )
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({
      p_user_id: scope.userId,
      p_preview_id: preview,
      p_operation_key: confirmation,
      p_command: command(),
    })
    expect(rpc.mock.calls[0]?.[0]).toBe('confirm_mobile_clinical_full_command')
  })
  it.each([
    'owner',
    'scope',
    'normalization',
    'command',
    'package',
    'defaults',
  ])('refuses corrupt original %s without fallback', async (fault) => {
    const raw = original()
    if (fault === 'owner') raw.preview.user_id = other
    if (fault === 'scope') raw.preview.cycle_id = other
    if (fault === 'normalization') Object.assign(raw.normalization_context, { sex: 'invalid' })
    if (fault === 'command') raw.command.bodyFat.meanHundredths += 1
    if (fault === 'package') raw.package.form.answers.weightKg = 82
    if (fault === 'defaults')
      Object.assign(raw.command.form.answers, { adherence: 'prefiro_nao_responder' })
    const { repo, rpc } = setup(raw)
    if (fault === 'scope')
      await expect(
        repo.prepareCommand(scope, key, wire.context.context_hash, command(), bundle()),
      ).rejects.toMatchObject({ status: 503 })
    else
      await expect(repo.findPrepared(scope.userId, { previewId: preview })).rejects.toMatchObject({
        status: 503,
      })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
