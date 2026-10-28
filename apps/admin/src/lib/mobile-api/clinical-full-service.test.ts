import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { clinicalFullPublicCandidateId } from './clinical-full-public-command'
import { createClinicalFullService } from './clinical-full-service'
import { createSupabaseClinicalFullRepository } from './supabase-clinical-full'
import wire from './testing/clinical-full-wire.json'

const owner = wire.context.user_id,
  key = wire.prepared.operation_key
const preview = wire.prepared.preview.preview_id,
  confirmation = wire.confirmed.operation_key
const other = 'b3b01000-0000-4000-8000-000000004399'
function auth(): MobileAuthContext {
  return {
    userId: owner,
    authUserId: other,
    accessToken: 'synthetic-session',
    identity: { id: other, email: null, emailConfirmedAt: null },
    patient: {
      id: owner,
      authUserId: other,
      email: null,
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
function input() {
  return {
    form: structuredClone(wire.receipt.form),
    choice: { kind: 'keep' },
    bodyFat: structuredClone(wire.receipt.intent.bodyFat),
  }
}
function prepared() {
  return {
    ...structuredClone(wire.prepared),
    command_version: 1,
    command_hash: 'd'.repeat(64),
    normalization_context: { sex: 'masculino', heightCm: 180 },
    command: { ...input(), measureConfirmed: false },
    package: structuredClone({
      form: wire.receipt.form,
      intent: wire.receipt.intent,
      proposal: wire.receipt.proposal,
    }),
  }
}
const presentation = {
  version: 1,
  hide: { objective: false, calories: false, protein: false },
  professionalAssessmentRecommended: false,
  pauseWeightLossGuidance: false,
}
const prepareRequest = () => ({
  kind: 'REGULAR',
  cycleId: wire.context.cycle_id,
  operationKey: key,
  input: input(),
})
const confirmRequest = () => ({
  kind: 'REGULAR',
  cycleId: wire.context.cycle_id,
  previewId: preview,
  operationKey: confirmation,
  input: input(),
})
function setup() {
  const rpc =
    vi.fn<
      (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
    >()
  const repository = {
    ...createSupabaseClinicalFullRepository({ rpc } as unknown as ServiceClient),
  }
  const service = createClinicalFullService({ enabled: true, repository })
  const reply = (data: unknown) => rpc.mockResolvedValueOnce({ data, error: null })
  return { rpc, repository, service, reply }
}
const current = () => ({
  ...structuredClone(wire.context),
  observed_at: '2026-10-26T16:01:02.000000Z',
})
describe('authenticated FULL command orchestration', () => {
  const publicInput = () => ({
    activityPurpose: wire.receipt.form.activityPurpose,
    answers: structuredClone(wire.receipt.form.answers),
    preference: null,
    choice: { kind: 'keep' },
    measureConfirmed: false,
    bodyFat: {
      confirmed: true,
      candidateId: clinicalFullPublicCandidateId(
        { userId: owner, kind: 'REGULAR', cycleId: wire.context.cycle_id },
        wire.receipt.intent.bodyFat,
      ),
    },
  })
  it('public prepare binds the displayed photo identity to the real mean only after a missing original lookup', async () => {
    const x = setup()
    x.reply(null)
    x.reply(current())
    x.reply({ ...prepared(), presentation })
    expect(
      await x.service.preparePublic(auth(), { ...prepareRequest(), input: publicInput() }),
    ).toEqual({ ...prepared(), presentation })
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command',
      'get_mobile_clinical_full_context',
      'prepare_mobile_clinical_full_presented_command',
    ])
    expect(x.rpc.mock.calls[2]?.[1]).toMatchObject({
      p_command: { bodyFat: wire.receipt.intent.bodyFat },
      p_presentation: presentation,
    })
    expect(JSON.stringify(x.rpc.mock.calls[2]?.[1])).not.toContain('candidateId')
  })
  it('public preparation replays the original measurement without current capture or expiry extension', async () => {
    const x = setup()
    x.reply(prepared())
    expect(
      await x.service.preparePublic(auth(), { ...prepareRequest(), input: publicInput() }),
    ).toEqual(prepared())
    expect(x.rpc).toHaveBeenCalledOnce()
  })
  it('public confirmation ACK remains receipt-first after reset/risk and never rebinds a new photo mean', async () => {
    const x = setup()
    x.reply({ ...structuredClone(wire.receipt), prepared: prepared() })
    expect(
      await x.service.confirmPublic(auth(), { ...confirmRequest(), input: publicInput() }),
    ).toEqual(wire.confirmed)
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual(['get_mobile_clinical_full_command_receipt'])
  })
  it('public alias binds only the original private package without capture', async () => {
    const x = setup()
    x.reply({
      ...structuredClone(wire.receipt),
      operation_key: other,
      operation_matched: false,
      prepared: prepared(),
    })
    x.reply({ ...structuredClone(wire.confirmed), operation_key: other })
    expect(
      await x.service.confirmPublic(auth(), {
        ...confirmRequest(),
        operationKey: other,
        input: publicInput(),
      }),
    ).toEqual({ ...wire.confirmed, operation_key: other })
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command_receipt',
      'confirm_mobile_clinical_full_command',
    ])
  })
  it('public commands cannot smuggle phase, no-plan origin, raw source or calculated mean', async () => {
    for (const extra of [
      { phase: 'manutencao' },
      { noPlanOrigin: {} },
      { targets: { afterKcal: 1 } },
      { bodyFat: wire.receipt.intent.bodyFat },
    ]) {
      const x = setup()
      await expect(
        x.service.preparePublic(auth(), {
          ...prepareRequest(),
          input: { ...publicInput(), ...extra },
        }),
      ).rejects.toMatchObject({ status: 422 })
      expect(x.rpc).not.toHaveBeenCalled()
    }
  })
  it('an old pending preview without display evidence cannot be newly confirmed through the public entry', async () => {
    const x = setup()
    x.reply(null)
    x.reply(prepared())
    await expect(
      x.service.confirmPublic(auth(), { ...confirmRequest(), input: publicInput() }),
    ).rejects.toMatchObject({ status: 409, code: 'mobile_clinical_full_changed' })
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command_receipt',
      'get_mobile_clinical_full_command',
    ])
  })
  it('prepares a new server calculation only after missing original lookup', async () => {
    const x = setup()
    x.reply(null)
    x.reply(current())
    x.reply(prepared())
    expect(await x.service.prepare(auth(), prepareRequest())).toEqual(prepared())
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command',
      'get_mobile_clinical_full_context',
      'prepare_mobile_clinical_full_command',
    ])
    expect(x.rpc.mock.calls[2]?.[1]).toMatchObject({
      p_user_id: owner,
      p_command: prepared().command,
      p_proposal: prepared().package.proposal,
    })
  })
  it('returns original preparation after reset/expiry without capture, extending expiry or applying effects', async () => {
    const x = setup()
    const old = prepared()
    old.preview.valid_until = '2026-10-26T16:01:01.240000Z'
    x.reply(old)
    expect(await x.service.prepare(auth(), prepareRequest())).toEqual(old)
    expect(x.rpc).toHaveBeenCalledTimes(1)
  })
  it('uses original female n21 refusal despite any current profile and does not retain rejected input', async () => {
    const x = setup(),
      old = prepared(),
      request = prepareRequest()
    old.normalization_context.sex = 'feminino'
    Object.assign(request.input.form, {
      preference: { action: 'change', value: { kind: 'body_fat', percent: 11 } },
    })
    x.reply(old)
    expect(await x.service.prepare(auth(), request)).toEqual(old)
    expect(x.rpc).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(x.rpc.mock.calls)).not.toContain('percent')
  })
  it('same-key completed confirmation returns original ACK before any current capture', async () => {
    const x = setup()
    x.reply({ ...structuredClone(wire.receipt), prepared: prepared() })
    expect(await x.service.confirm(auth(), confirmRequest())).toEqual(wire.confirmed)
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual(['get_mobile_clinical_full_command_receipt'])
  })
  it('unmatched alias binds the original command/package once before any capture', async () => {
    const x = setup()
    const request = { ...confirmRequest(), operationKey: other }
    x.reply({
      ...structuredClone(wire.receipt),
      operation_key: other,
      operation_matched: false,
      prepared: prepared(),
    })
    x.reply({ ...structuredClone(wire.confirmed), operation_key: other })
    expect(await x.service.confirm(auth(), request)).toEqual({
      ...wire.confirmed,
      operation_key: other,
    })
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command_receipt',
      'confirm_mobile_clinical_full_command',
    ])
    expect(x.rpc.mock.calls[1]?.[1]).toMatchObject({
      p_command: prepared().command,
      p_proposal: prepared().package.proposal,
    })
  })
  it('pending confirmation compares historical command before fresh authority and calculation', async () => {
    const x = setup()
    x.reply(null)
    x.reply(prepared())
    x.reply(current())
    x.reply(wire.confirmed)
    expect(await x.service.confirm(auth(), confirmRequest())).toEqual(wire.confirmed)
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command_receipt',
      'get_mobile_clinical_full_command',
      'get_mobile_clinical_full_context',
      'confirm_mobile_clinical_full_command',
    ])
  })
  it.each([
    'choice',
    'measure',
    'accepted_preference',
    'scope',
  ])('changed original %s conflicts before capture or effects', async (fault) => {
    const x = setup(),
      request = confirmRequest()
    x.reply(null)
    x.reply(prepared())
    if (fault === 'choice') request.input.choice.kind = 'activity'
    if (fault === 'measure') Object.assign(request.input, { measureConfirmed: true })
    if (fault === 'accepted_preference')
      Object.assign(request.input.form, {
        preference: { action: 'change', value: { kind: 'body_fat', percent: 15 } },
      })
    if (fault === 'scope') request.cycleId = other
    await expect(x.service.confirm(auth(), request)).rejects.toMatchObject({ status: 409 })
    expect(x.rpc).toHaveBeenCalledTimes(2)
  })
  it.each([
    'hash',
    'expiry',
  ])('pending stale %s cannot apply or prepare automatically', async (fault) => {
    const x = setup(),
      raw = current()
    x.reply(null)
    x.reply(prepared())
    if (fault === 'hash') raw.context_hash = 'e'.repeat(64)
    else {
      raw.observed_at = raw.valid_until
      raw.valid_until = '2026-10-26T16:03:00.000000Z'
    }
    x.reply(raw)
    await expect(x.service.confirm(auth(), confirmRequest())).rejects.toMatchObject({ status: 409 })
    expect(x.rpc).toHaveBeenCalledTimes(3)
  })
  it('does not treat unavailable original lookup as absence or retry a failed write', async () => {
    const x = setup()
    x.rpc.mockResolvedValueOnce({ data: null, error: { code: 'XX001' } })
    await expect(x.service.prepare(auth(), prepareRequest())).rejects.toMatchObject({ status: 503 })
    expect(x.rpc).toHaveBeenCalledTimes(1)
    const second = setup()
    second.reply(null)
    second.reply(current())
    second.rpc.mockResolvedValueOnce({ data: null, error: { code: '55P03' } })
    await expect(second.service.prepare(auth(), prepareRequest())).rejects.toMatchObject({
      status: 409,
    })
    expect(second.rpc).toHaveBeenCalledTimes(3)
  })
  it('captures owner/input/callbacks before awaiting original preparation', async () => {
    const x = setup(),
      context = auth(),
      request = prepareRequest()
    let finish!: (value: { data: unknown; error: null }) => void
    x.rpc.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    )
    x.reply(current())
    x.reply(prepared())
    const pending = x.service.prepare(context, request)
    context.userId = other
    context.patient.id = other
    request.input.form.answers.weightKg = 81
    x.repository.capture = vi.fn().mockRejectedValue(new Error('substituted'))
    finish({ data: null, error: null })
    expect(await pending).toEqual(prepared())
    expect(x.rpc.mock.calls[0]?.[1]?.p_user_id).toBe(owner)
    expect(x.rpc.mock.calls.map((c) => c[0])).toEqual([
      'get_mobile_clinical_full_command',
      'get_mobile_clinical_full_context',
      'prepare_mobile_clinical_full_command',
    ])
  })
  it('rejects invalid identity, client effects and disabled composition before all I/O', async () => {
    const x = setup(),
      context = auth()
    context.patient.authUserId = owner
    await expect(x.service.prepare(context, prepareRequest())).rejects.toMatchObject({
      status: 403,
    })
    await expect(
      x.service.prepare(auth(), { ...prepareRequest(), proposal: {} }),
    ).rejects.toMatchObject({ status: 422 })
    const disabled = createClinicalFullService({
      enabled: false,
      get repository(): never {
        throw new Error('must not read')
      },
    })
    await expect(disabled.prepare(auth(), prepareRequest())).rejects.toMatchObject({ status: 503 })
    expect(x.rpc).not.toHaveBeenCalled()
  })
})
