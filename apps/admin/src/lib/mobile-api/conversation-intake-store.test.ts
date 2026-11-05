import { describe, expect, it } from 'vitest'
import {
  bindConversationIntake,
  type ConversationIntake,
  type ConversationIntakeBinding,
  type ConversationIntakeContext,
  type ConversationIntakeSelection,
  parseConversationIntakeSelection,
  parseConversationIntakeSource,
} from './conversation-intake-contracts'
import { createConversationIntakeStore } from './conversation-intake-store'

const owner = '0a1a0000-0000-4000-8000-000000000001',
  id = '0a1a0000-0000-4000-8000-000000000002',
  child = '0a1a0000-0000-4000-8000-000000000003',
  epoch = '0a1a0000-0000-4000-8000-000000000004',
  claim = '0a1a0000-0000-4000-8000-000000000005'
const hash = 'ca56a1db694111ad33d6810121f148ceb4ee0b0853046eb882d67d8f7fcd6072',
  sourceHash = 'a'.repeat(64)
function input() {
  return {
    intake_protocol: 'conversation.intake.v1',
    intake_id: id,
    source: { channel: 'text', text: '  fiz 30 min de caminhada  ' },
  }
}
function bound() {
  return bindConversationIntake(owner, `cintake1:${id}`, input())
}
function binding() {
  return {
    owner_id: owner,
    intake_id: id,
    input_hash: hash,
    epoch,
    admitted_at: '2026-11-05T12:00:00.000001Z',
  }
}
function capture() {
  return {
    action: 'captured',
    source_hash: sourceHash,
    context: {
      schema: 'conversation.intake-source.v1',
      ...binding(),
      source_input: input(),
      captured_at: '2026-11-05T12:00:01.000001Z',
      time_zone: 'America/Sao_Paulo',
      local_date: '2026-11-05',
      media: null,
    },
  }
}
function selection() {
  return {
    schema: 'conversation.intake-selection.v1',
    intake: binding(),
    source_hash: sourceHash,
    decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
    decision: {
      schema: 'conversation.intake-routing.v1',
      kind: 'workout.report',
      reason: 'performed_activity',
    },
    selected_at: '2026-11-05T12:00:03.000001Z',
    command: {
      kind: 'workout.report',
      owner_id: owner,
      command_id: child,
      input_hash: 'e96cf5b1d27f79355e6be9499c3c190cfce7767e3224aab24f824ab224dfd760',
      epoch,
      admitted_at: '2026-11-05T12:00:02.000001Z',
      input: {
        command_protocol: 'conversation.command.v1',
        command_id: child,
        kind: 'workout.report',
        source: input().source,
      },
    },
  }
}
function available() {
  return {
    action: 'available',
    intake: binding(),
    source_input: input(),
    source_hash: sourceHash,
    claimed: true,
    selection: selection(),
  }
}
const identity = { ownerId: owner, intakeId: id, inputHash: hash, epoch }
function harness(
  data: unknown,
  hook?: (count: number) => boolean | Promise<boolean>,
  failure?: Error,
) {
  let checks = 0
  const events: string[] = [],
    calls: { name: string; args: Readonly<Record<string, unknown>> }[] = []
  const raw = { data, error: null }
  const store = createConversationIntakeStore(
    {
      rpc: async (name: string, args: Readonly<Record<string, unknown>>) => {
        events.push('rpc')
        calls.push({ name, args })
        if (failure) throw failure
        return raw
      },
    },
    {
      checkCurrentScope: async (who: unknown) => {
        expect(who).toEqual(identity)
        checks++
        events.push(`scope${checks}`)
        return hook ? await hook(checks) : true
      },
    },
  )
  return { store, raw, events, calls, checks: () => checks }
}
type Store = ReturnType<typeof createConversationIntakeStore>
function invoke(s: Store, method: string) {
  if (method === 'admit') return s.admit(bound(), epoch)
  if (method === 'capture') return s.capture(bound(), epoch)
  if (method === 'claim') return s.claim(bound(), epoch, sourceHash)
  if (method === 'seal') return s.seal(bound(), epoch, sourceHash, claim, selection().decision)
  return s.read(identity)
}
const cases = [
  [
    'admit',
    'admit_conversation_intake',
    { action: 'admitted', intake: binding() },
    { p_user_id: owner, p_expected_epoch: epoch, p_input: input() },
  ],
  [
    'capture',
    'capture_conversation_intake_source',
    capture(),
    { p_user_id: owner, p_intake_id: id, p_input_hash: hash, p_expected_epoch: epoch },
  ],
  [
    'claim',
    'claim_conversation_intake_routing',
    { action: 'claimed', claim_id: claim },
    {
      p_user_id: owner,
      p_intake_id: id,
      p_input_hash: hash,
      p_expected_epoch: epoch,
      p_source_hash: sourceHash,
    },
  ],
  [
    'seal',
    'seal_conversation_intake_routing',
    { action: 'sealed', selection: selection() },
    {
      p_user_id: owner,
      p_intake_id: id,
      p_input_hash: hash,
      p_expected_epoch: epoch,
      p_source_hash: sourceHash,
      p_claim_id: claim,
      p_decision: selection().decision,
    },
  ],
  [
    'read',
    'read_conversation_intake',
    available(),
    { p_user_id: owner, p_intake_id: id, p_input_hash: hash, p_expected_epoch: epoch },
  ],
] as const

describe('Five intake RPCs require pinned Auth fences; no implicit writes or retries', () => {
  it.each(
    cases,
  )('%s sends only its exact RPC and original tuple', async (method, name, data, args) => {
    const f = harness(data),
      result = await invoke(f.store, method)
    expect(result).toEqual(data)
    expect(Object.isFrozen(result)).toBe(true)
    expect(f.calls).toEqual([{ name, args }])
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
  })
  it.each(cases)('%s fences throws and never physically retries', async (method) => {
    const f = harness(null, undefined, new Error('secret provider password must not escape'))
    await expect(invoke(f.store, method)).rejects.not.toThrow('secret provider password')
    expect(f.calls).toHaveLength(1)
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
  })
  it.each([1, 2])('a mandatory refusal at fence%s withholds all data', async (failAt) => {
    const f = harness(available(), (n) => n !== failAt)
    await expect(f.store.read(identity)).rejects.toThrow()
    expect(f.calls).toHaveLength(failAt === 1 ? 0 : 1)
    expect(f.checks()).toBe(failAt)
  })
  it('snapshots the SDK object before the second Auth await, not after', async () => {
    const data = capture()
    const f = harness(data, (n) => {
      if (n === 2) {
        data.context.source_input.source.text = 'cross-account replacement'
        data.context.owner_id = child
      }
      return true
    })
    const result = await f.store.capture(bound(), epoch)
    expect(result).toEqual(capture())
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
  })
  it('does not turn an SDK error into success through an after-fence alias', async () => {
    const f = harness(available(), (n) => {
      if (n === 2) (f.raw as { error: unknown }).error = null
      return true
    })
    ;(f.raw as { error: unknown }).error = { message: 'private credential' }
    await expect(f.store.read(identity)).rejects.not.toThrow('private credential')
    expect(f.calls).toHaveLength(1)
  })
  it('pins the bound input before awaiting Auth without mutating the caller', async () => {
    const mutable = structuredClone(bound())
    const f = harness({ action: 'admitted', intake: binding() }, (n) => {
      if (n === 1) (mutable.input.source as { text: string }).text = 'changed'
      return true
    })
    await f.store.admit(mutable, epoch)
    expect(f.calls[0]?.args).toEqual({
      p_user_id: owner,
      p_expected_epoch: epoch,
      p_input: input(),
    })
  })
  it.each([
    'owner',
    'hash',
    'epoch',
    'extra',
    'claimed',
    'sourcehash',
    'source_input',
    'source-null',
  ])('READ refuses forged %s and never invokes a writer', async (attack) => {
    const data = available()
    const raw: Record<string, unknown> = data
    if (attack === 'owner') data.intake.owner_id = child
    if (attack === 'hash') data.intake.input_hash = sourceHash
    if (attack === 'epoch') data.intake.epoch = child
    if (attack === 'extra') raw.private_state = {}
    if (attack === 'claimed') data.claimed = false
    if (attack === 'sourcehash') data.source_hash = 'b'.repeat(64)
    if (attack === 'source_input') data.source_input.source.text = 'different'
    if (attack === 'source-null') raw.source_hash = null
    const f = harness(data)
    await expect(f.store.read(identity)).rejects.toThrow()
    expect(f.calls.map((c) => c.name)).toEqual(['read_conversation_intake'])
  })
  it('claim replay remains unknown rather than permitting provider recall', async () => {
    const f = harness({ action: 'already_claimed' })
    expect(await f.store.claim(bound(), epoch, sourceHash)).toEqual({ action: 'already_claimed' })
    expect(f.calls.map((c) => c.name)).toEqual(['claim_conversation_intake_routing'])
  })
  it.each([
    'input_conflict',
    'stale_epoch',
    'rate_limited',
  ])('admission preserves closed %s refusal without repair', async (action) => {
    const f = harness({ action })
    expect(await f.store.admit(bound(), epoch)).toEqual({ action })
    expect(f.calls).toHaveLength(1)
  })
  it('holds selected media without fabricating a typed body or consuming a second RPC', async () => {
    const media = {
      intake_protocol: 'conversation.intake.v1',
      intake_id: id,
      source: { channel: 'media', media_asset_id: child, user_action: 'report_actual_record' },
    }
    const b = bindConversationIntake(owner, `cintake1:${id}`, media)
    const calls: string[] = []
    const store = createConversationIntakeStore(
      {
        rpc: async (name: string, args: Readonly<Record<string, unknown>>) => {
          calls.push(name)
          expect(Object.keys(args)).toEqual([
            'p_user_id',
            'p_intake_id',
            'p_input_hash',
            'p_expected_epoch',
            'p_source_hash',
            'p_claim_id',
            'p_decision',
          ])
          expect(args.p_decision).toEqual(selection().decision)
          return { data: { action: 'media_projection_required' }, error: null }
        },
      },
      { checkCurrentScope: async () => true },
    )
    expect(await store.seal(b, epoch, sourceHash, claim, selection().decision)).toEqual({
      action: 'media_projection_required',
    })
    expect(calls).toEqual(['seal_conversation_intake_routing'])
  })
  it('invalid scope ports never silently become authority', () => {
    expect(() =>
      createConversationIntakeStore(
        { rpc: async () => ({ data: { action: 'absent' }, error: null }) },
        {} as never,
      ),
    ).toThrow()
  })
  it('cold read binds the actual persisted hint even when workout input legitimately omits it', async () => {
    const data = available()
    const hinted = 'e432358218a3c327d9271916704f264978f863af9bc2cd5397a11731b33aca63'
    data.intake.input_hash = hinted
    data.selection.intake.input_hash = hinted
    const source_input = { ...input(), meal_type_hint: 'almoco' }
    const payload = { ...data, source_input }
    const result = await createConversationIntakeStore(
      { rpc: async () => ({ data: payload, error: null }) },
      { checkCurrentScope: async () => true },
    ).read({ ...identity, inputHash: hinted })
    expect(result).toEqual(payload)
    expect(result.action === 'available' && result.selection?.command?.input_hash).toBe(
      'e96cf5b1d27f79355e6be9499c3c190cfce7767e3224aab24f824ab224dfd760',
    )
  })
  it('an unclaimed admitted-only READ cannot be upgraded into a capture/claim/typed admission', async () => {
    const data = {
      action: 'available',
      intake: binding(),
      source_input: input(),
      source_hash: null,
      claimed: false,
      selection: null,
    }
    const f = harness(data)
    expect(await f.store.read(identity)).toEqual(data)
    expect(f.calls.map((c) => c.name)).toEqual(['read_conversation_intake'])
  })
  it.each([
    'source_conflict',
    'claim_conflict',
    'decision_conflict',
    'media_projection_required',
    'rate_limited',
    'day_closed',
    'day_changed',
  ])('seal preserves %s without a second mutation', async (action) => {
    const f = harness({ action })
    expect(await f.store.seal(bound(), epoch, sourceHash, claim, selection().decision)).toEqual({
      action,
    })
    expect(f.calls).toHaveLength(1)
  })
  it.each([
    'extra-refusal',
    'unknown-action',
    'missing-data',
    'getters',
  ])('malformed SDK/refusal %s still receives its after fence', async (attack) => {
    const f = harness(
      attack === 'extra-refusal'
        ? { action: 'absent', claim_id: claim }
        : attack === 'unknown-action'
          ? { action: 'saved' }
          : undefined,
    )
    if (attack === 'getters')
      Object.defineProperty(f.raw, 'data', {
        enumerable: true,
        get() {
          throw new Error('untrusted getter')
        },
      })
    await expect(f.store.read(identity)).rejects.toThrow()
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
  })
  it('pins the real port functions, so mutation of dependency objects cannot replace Auth', async () => {
    let called = 0,
      checks = 0
    const rpc = {
      rpc: async () => {
        called++
        return { data: available(), error: null }
      },
    }
    const scope = {
      checkCurrentScope: async () => {
        checks++
        return false
      },
    }
    const store = createConversationIntakeStore(rpc, scope)
    scope.checkCurrentScope = async () => true
    rpc.rpc = async () => {
      throw new Error('changed')
    }
    await expect(store.read(identity)).rejects.toThrow()
    expect(checks).toBe(1)
    expect(called).toBe(0)
  })
  it('a rejected after fence is sticky even when the physical RPC throws', async () => {
    const f = harness(null, (n) => n !== 2, new Error('private'))
    await expect(f.store.read(identity)).rejects.not.toThrow('private')
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
    expect(f.calls).toHaveLength(1)
  })
  it('seal compares its pinned original decision and source instead of adopting a different reply', async () => {
    for (const defect of ['decision', 'source']) {
      const data = { action: 'sealed', selection: selection() }
      if (defect === 'decision') data.selection.decision.reason = 'other_reason'
      else data.selection.source_hash = 'b'.repeat(64)
      const f = harness(data)
      await expect(
        f.store.seal(bound(), epoch, sourceHash, claim, selection().decision),
      ).rejects.toThrow()
      expect(f.calls).toHaveLength(1)
    }
  })
  it.each([
    'capture',
    'seal',
  ])('a positive %s action with missing mandatory payload is never accepted', async (method) => {
    const data =
      method === 'capture' ? { action: 'captured', source_hash: sourceHash } : { action: 'sealed' }
    const f = harness(data)
    await expect(invoke(f.store, method)).rejects.toThrow()
    expect(f.events).toEqual(['scope1', 'rpc', 'scope2'])
  })

  it.each(actualSql.fixtures)('actual synthetic rollback SQL parity: $label', async (row) => {
    const actualBinding = row.admission.intake
    const original = row.source.context.source_input
    const b = bindConversationIntake(
      actualBinding.owner_id,
      `cintake1:${actualBinding.intake_id}`,
      original,
    )
    expect(b.inputHash).toBe(actualBinding.input_hash)
    expect(
      parseConversationIntakeSource(b, actualBinding, {
        source_hash: row.source.source_hash,
        context: row.source.context,
      }).context,
    ).toEqual(row.source.context)
    if (row.seal.action === 'sealed')
      expect(parseConversationIntakeSelection(b, actualBinding, row.seal.selection)).toEqual(
        row.seal.selection,
      )
    const tuple = {
      ownerId: actualBinding.owner_id,
      intakeId: actualBinding.intake_id,
      inputHash: actualBinding.input_hash,
      epoch: actualBinding.epoch,
    }
    for (const method of ['admit', 'capture', 'claim', 'seal', 'read'] as const) {
      const expected =
        method === 'admit'
          ? row.admission
          : method === 'capture'
            ? row.source
            : method === 'claim'
              ? row.claim
              : method === 'seal'
                ? row.seal
                : row.read_result
      const calls: string[] = []
      const store = createConversationIntakeStore(
        {
          rpc: async (name) => {
            calls.push(name)
            return { data: expected, error: null }
          },
        },
        {
          checkCurrentScope: async (who) => {
            expect(who).toEqual(tuple)
            return true
          },
        },
      )
      const result =
        method === 'admit'
          ? await store.admit(b, tuple.epoch)
          : method === 'capture'
            ? await store.capture(b, tuple.epoch)
            : method === 'claim'
              ? await store.claim(b, tuple.epoch, row.source.source_hash)
              : method === 'seal'
                ? await store.seal(
                    b,
                    tuple.epoch,
                    row.source.source_hash,
                    row.claim.claim_id,
                    row.seal.action === 'sealed'
                      ? row.seal.selection.decision
                      : {
                          schema: 'conversation.intake-routing.v1',
                          kind: 'workout.report',
                          reason: 'performed_activity',
                        },
                  )
                : await store.read(tuple)
      expect(result).toEqual(expected)
      expect(calls).toHaveLength(1)
    }
  })
})

// ACTUAL SQL synthetic rollback bodies, not HTTP/provider/E2E. Original whole-file SHA256:
// 153f23214c2027e2e050ce4168469d0890f019cdbf965b38cd1e3a5c5839f7f0
// K owned capture/admission/claim/typed admission/seal/read; opaque source hashes are not recomputed.
interface ActualSqlFixture {
  label: string
  admission: { action: 'admitted'; intake: ConversationIntakeBinding }
  source: { action: 'captured'; source_hash: string; context: ConversationIntakeContext }
  claim: { action: 'claimed'; claim_id: string }
  seal:
    | { action: 'sealed'; selection: ConversationIntakeSelection }
    | { action: 'media_projection_required' }
  read_result: {
    action: 'available'
    intake: ConversationIntakeBinding
    source_input: ConversationIntake
    source_hash: string
    claimed: boolean
    selection: ConversationIntakeSelection | null
  }
}
const actualSql: { schema: string; fixtures: readonly ActualSqlFixture[] } = {
  schema: 't39.actual-sql-intake-golden.v1',
  fixtures: [
    {
      label: 'audio_projection_refused',
      admission: {
        action: 'admitted',
        intake: {
          epoch: 'a0fc7e5b-cca7-4012-b8d7-4029b853e231',
          owner_id: 'c1390000-0000-4000-8000-000000000090',
          intake_id: '8d07bed5-e066-4121-bb1d-56b87f53aa0b',
          input_hash: '312f7f9f01f10ad0ffa3bcd77bf1bac950274c19c6729f57b709bc03a119c469',
          admitted_at: '2026-11-05T11:23:24.016727Z',
        },
      },
      source: {
        action: 'captured',
        context: {
          epoch: 'a0fc7e5b-cca7-4012-b8d7-4029b853e231',
          media: {
            kind: 'audio_note',
            status: 'processed',
            asset_id: '1772c35e-63e4-4e8c-8717-44c8a0d94c32',
            owner_id: 'c1390000-0000-4000-8000-000000000090',
            updated_at: '2026-11-05T11:23:21.316893Z',
            context_text: 'Legenda completa original',
            processed_at: '2026-11-05T11:23:24.013997Z',
            processing_result: {
              text: 'Fiz 30 minutos de caminhada.',
              model: 'synthetic',
              segments: [
                {
                  text: 'Fiz',
                  start: 0.1,
                },
              ],
            },
          },
          schema: 'conversation.intake-source.v1',
          owner_id: 'c1390000-0000-4000-8000-000000000090',
          intake_id: '8d07bed5-e066-4121-bb1d-56b87f53aa0b',
          time_zone: 'UTC',
          input_hash: '312f7f9f01f10ad0ffa3bcd77bf1bac950274c19c6729f57b709bc03a119c469',
          local_date: '2026-11-05',
          admitted_at: '2026-11-05T11:23:24.016727Z',
          captured_at: '2026-11-05T11:23:24.045973Z',
          source_input: {
            source: {
              caption: 'Legenda literal enviada',
              channel: 'media',
              user_action: 'report_actual_record',
              media_asset_id: '1772c35e-63e4-4e8c-8717-44c8a0d94c32',
            },
            intake_id: '8d07bed5-e066-4121-bb1d-56b87f53aa0b',
            intake_protocol: 'conversation.intake.v1',
          },
        },
        source_hash: 'ac15ae25d75fda66f7e7bccc103527dce3f8bdbf8f9bdca11648fe841f8fe897',
      },
      claim: {
        action: 'claimed',
        claim_id: 'aa562030-84bb-4678-a999-912dc422c1c4',
      },
      seal: {
        action: 'media_projection_required',
      },
      read_result: {
        action: 'available',
        intake: {
          epoch: 'a0fc7e5b-cca7-4012-b8d7-4029b853e231',
          owner_id: 'c1390000-0000-4000-8000-000000000090',
          intake_id: '8d07bed5-e066-4121-bb1d-56b87f53aa0b',
          input_hash: '312f7f9f01f10ad0ffa3bcd77bf1bac950274c19c6729f57b709bc03a119c469',
          admitted_at: '2026-11-05T11:23:24.016727Z',
        },
        claimed: true,
        selection: null,
        source_hash: 'ac15ae25d75fda66f7e7bccc103527dce3f8bdbf8f9bdca11648fe841f8fe897',
        source_input: {
          source: {
            caption: 'Legenda literal enviada',
            channel: 'media',
            user_action: 'report_actual_record',
            media_asset_id: '1772c35e-63e4-4e8c-8717-44c8a0d94c32',
          },
          intake_id: '8d07bed5-e066-4121-bb1d-56b87f53aa0b',
          intake_protocol: 'conversation.intake.v1',
        },
      },
    },
    {
      label: 'clarification_required',
      admission: {
        action: 'admitted',
        intake: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
          input_hash: 'b76eaf3484c4f262597e76c49a4a13b0aec7f6bd0e2b097585f2e303eb4463df',
          admitted_at: '2026-11-05T11:23:22.563126Z',
        },
      },
      source: {
        action: 'captured',
        context: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          media: null,
          schema: 'conversation.intake-source.v1',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
          time_zone: 'UTC',
          input_hash: 'b76eaf3484c4f262597e76c49a4a13b0aec7f6bd0e2b097585f2e303eb4463df',
          local_date: '2026-11-05',
          admitted_at: '2026-11-05T11:23:22.563126Z',
          captured_at: '2026-11-05T11:23:22.600823Z',
          source_input: {
            source: {
              text: 'Comi e caminhei.',
              channel: 'text',
            },
            intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
            intake_protocol: 'conversation.intake.v1',
          },
        },
        source_hash: '9421c63b688febe12e28180fbe7e6a7a75059623ecc15cc4c722b63891989e4b',
      },
      claim: {
        action: 'claimed',
        claim_id: '3d4c53f2-b48e-4348-a067-7d5792eb4026',
      },
      seal: {
        action: 'sealed',
        selection: {
          intake: {
            epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
            owner_id: 'c1390000-0000-4000-8000-000000000030',
            intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
            input_hash: 'b76eaf3484c4f262597e76c49a4a13b0aec7f6bd0e2b097585f2e303eb4463df',
            admitted_at: '2026-11-05T11:23:22.563126Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: null,
          decision: {
            kind: 'clarification_required',
            reason: 'record_kind',
            schema: 'conversation.intake-routing.v1',
            question: {
              text: 'Qual registro você quer fazer primeiro?',
              field: 'record_kind',
            },
          },
          selected_at: '2026-11-05T11:23:22.738128Z',
          source_hash: '9421c63b688febe12e28180fbe7e6a7a75059623ecc15cc4c722b63891989e4b',
          decision_hash: '7b2ac585488b68c3e42c61069ffd2d3b6a51869c2f6ba3389922b28ff0f910ae',
        },
      },
      read_result: {
        action: 'available',
        intake: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
          input_hash: 'b76eaf3484c4f262597e76c49a4a13b0aec7f6bd0e2b097585f2e303eb4463df',
          admitted_at: '2026-11-05T11:23:22.563126Z',
        },
        claimed: true,
        selection: {
          intake: {
            epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
            owner_id: 'c1390000-0000-4000-8000-000000000030',
            intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
            input_hash: 'b76eaf3484c4f262597e76c49a4a13b0aec7f6bd0e2b097585f2e303eb4463df',
            admitted_at: '2026-11-05T11:23:22.563126Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: null,
          decision: {
            kind: 'clarification_required',
            reason: 'record_kind',
            schema: 'conversation.intake-routing.v1',
            question: {
              text: 'Qual registro você quer fazer primeiro?',
              field: 'record_kind',
            },
          },
          selected_at: '2026-11-05T11:23:22.738128Z',
          source_hash: '9421c63b688febe12e28180fbe7e6a7a75059623ecc15cc4c722b63891989e4b',
          decision_hash: '7b2ac585488b68c3e42c61069ffd2d3b6a51869c2f6ba3389922b28ff0f910ae',
        },
        source_hash: '9421c63b688febe12e28180fbe7e6a7a75059623ecc15cc4c722b63891989e4b',
        source_input: {
          source: {
            text: 'Comi e caminhei.',
            channel: 'text',
          },
          intake_id: '1e7c81ea-27bf-406b-a7f3-86a20d5f4ff9',
          intake_protocol: 'conversation.intake.v1',
        },
      },
    },
    {
      label: 'meal_text',
      admission: {
        action: 'admitted',
        intake: {
          epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
          owner_id: 'c1390000-0000-4000-8000-000000000020',
          intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
          input_hash: '8cef473db5b9e229ffb1d609fe2651353a4be49760537053440972f9a17615ad',
          admitted_at: '2026-11-05T11:23:22.135813Z',
        },
      },
      source: {
        action: 'captured',
        context: {
          epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
          media: null,
          schema: 'conversation.intake-source.v1',
          owner_id: 'c1390000-0000-4000-8000-000000000020',
          intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
          time_zone: 'UTC',
          input_hash: '8cef473db5b9e229ffb1d609fe2651353a4be49760537053440972f9a17615ad',
          local_date: '2026-11-05',
          admitted_at: '2026-11-05T11:23:22.135813Z',
          captured_at: '2026-11-05T11:23:22.173914Z',
          source_input: {
            source: {
              text: '  Comi arroz.  ',
              channel: 'text',
            },
            intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
            meal_type_hint: 'almoco',
            intake_protocol: 'conversation.intake.v1',
          },
        },
        source_hash: '49aec7b9f815d7628c35d4c7f60a714fcd252081a8d117996a0cf8897ea9a8bc',
      },
      claim: {
        action: 'claimed',
        claim_id: '97ec5f2c-9d26-4d41-a4b2-6d59476311fb',
      },
      seal: {
        action: 'sealed',
        selection: {
          intake: {
            epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
            owner_id: 'c1390000-0000-4000-8000-000000000020',
            intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
            input_hash: '8cef473db5b9e229ffb1d609fe2651353a4be49760537053440972f9a17615ad',
            admitted_at: '2026-11-05T11:23:22.135813Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: {
            kind: 'meal.report',
            epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
            input: {
              kind: 'meal.report',
              source: {
                text: '  Comi arroz.  ',
                channel: 'text',
              },
              meal_type: 'almoco',
              command_id: '4d611a1b-fb6f-4e7d-8185-a656ed6c37e7',
              command_protocol: 'conversation.command.v1',
            },
            owner_id: 'c1390000-0000-4000-8000-000000000020',
            command_id: '4d611a1b-fb6f-4e7d-8185-a656ed6c37e7',
            input_hash: 'a8a78e424d0e948c350574ddacdd4f8232bdc453b1b8d4522657c782cf18b7ee',
            admitted_at: '2026-11-05T11:23:22.283180Z',
          },
          decision: {
            kind: 'meal.report',
            reason: 'performed_meal',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:22.315144Z',
          source_hash: '49aec7b9f815d7628c35d4c7f60a714fcd252081a8d117996a0cf8897ea9a8bc',
          decision_hash: 'a6ea1ac0b10b93ae1b9bb913cbb4e51e2694d2947f014948c0185a0b742b7181',
        },
      },
      read_result: {
        action: 'available',
        intake: {
          epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
          owner_id: 'c1390000-0000-4000-8000-000000000020',
          intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
          input_hash: '8cef473db5b9e229ffb1d609fe2651353a4be49760537053440972f9a17615ad',
          admitted_at: '2026-11-05T11:23:22.135813Z',
        },
        claimed: true,
        selection: {
          intake: {
            epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
            owner_id: 'c1390000-0000-4000-8000-000000000020',
            intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
            input_hash: '8cef473db5b9e229ffb1d609fe2651353a4be49760537053440972f9a17615ad',
            admitted_at: '2026-11-05T11:23:22.135813Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: {
            kind: 'meal.report',
            epoch: 'a91f618f-20e5-4416-83d5-64db25aabae3',
            input: {
              kind: 'meal.report',
              source: {
                text: '  Comi arroz.  ',
                channel: 'text',
              },
              meal_type: 'almoco',
              command_id: '4d611a1b-fb6f-4e7d-8185-a656ed6c37e7',
              command_protocol: 'conversation.command.v1',
            },
            owner_id: 'c1390000-0000-4000-8000-000000000020',
            command_id: '4d611a1b-fb6f-4e7d-8185-a656ed6c37e7',
            input_hash: 'a8a78e424d0e948c350574ddacdd4f8232bdc453b1b8d4522657c782cf18b7ee',
            admitted_at: '2026-11-05T11:23:22.283180Z',
          },
          decision: {
            kind: 'meal.report',
            reason: 'performed_meal',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:22.315144Z',
          source_hash: '49aec7b9f815d7628c35d4c7f60a714fcd252081a8d117996a0cf8897ea9a8bc',
          decision_hash: 'a6ea1ac0b10b93ae1b9bb913cbb4e51e2694d2947f014948c0185a0b742b7181',
        },
        source_hash: '49aec7b9f815d7628c35d4c7f60a714fcd252081a8d117996a0cf8897ea9a8bc',
        source_input: {
          source: {
            text: '  Comi arroz.  ',
            channel: 'text',
          },
          intake_id: '464c511c-aefd-4fcb-bf4b-fe1121641ab5',
          meal_type_hint: 'almoco',
          intake_protocol: 'conversation.intake.v1',
        },
      },
    },
    {
      label: 'not_reported',
      admission: {
        action: 'admitted',
        intake: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
          input_hash: '0fe23191c33972486db82c67a213e6f169d72a4d013824aa9ad35d5a67500de1',
          admitted_at: '2026-11-05T11:23:22.393912Z',
        },
      },
      source: {
        action: 'captured',
        context: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          media: null,
          schema: 'conversation.intake-source.v1',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
          time_zone: 'UTC',
          input_hash: '0fe23191c33972486db82c67a213e6f169d72a4d013824aa9ad35d5a67500de1',
          local_date: '2026-11-05',
          admitted_at: '2026-11-05T11:23:22.393912Z',
          captured_at: '2026-11-05T11:23:22.431354Z',
          source_input: {
            source: {
              text: 'Posso caminhar amanhã?',
              channel: 'text',
            },
            intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
            intake_protocol: 'conversation.intake.v1',
          },
        },
        source_hash: 'e2eb974cd4974e4d19ffab47c1dc7af958a46fa39cd203760ca02051ebd075a6',
      },
      claim: {
        action: 'claimed',
        claim_id: 'd6e3de16-8136-418b-85d4-664cbd05af48',
      },
      seal: {
        action: 'sealed',
        selection: {
          intake: {
            epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
            owner_id: 'c1390000-0000-4000-8000-000000000030',
            intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
            input_hash: '0fe23191c33972486db82c67a213e6f169d72a4d013824aa9ad35d5a67500de1',
            admitted_at: '2026-11-05T11:23:22.393912Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: null,
          decision: {
            kind: 'not_reported',
            reason: 'performed_activity',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:22.561499Z',
          source_hash: 'e2eb974cd4974e4d19ffab47c1dc7af958a46fa39cd203760ca02051ebd075a6',
          decision_hash: '2937059635d33e2a3798613b380858b9da98f9c83d482169a95cd67aa7e0abd7',
        },
      },
      read_result: {
        action: 'available',
        intake: {
          epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
          owner_id: 'c1390000-0000-4000-8000-000000000030',
          intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
          input_hash: '0fe23191c33972486db82c67a213e6f169d72a4d013824aa9ad35d5a67500de1',
          admitted_at: '2026-11-05T11:23:22.393912Z',
        },
        claimed: true,
        selection: {
          intake: {
            epoch: '754375b4-1820-47c9-b558-e4bb81127f91',
            owner_id: 'c1390000-0000-4000-8000-000000000030',
            intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
            input_hash: '0fe23191c33972486db82c67a213e6f169d72a4d013824aa9ad35d5a67500de1',
            admitted_at: '2026-11-05T11:23:22.393912Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: null,
          decision: {
            kind: 'not_reported',
            reason: 'performed_activity',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:22.561499Z',
          source_hash: 'e2eb974cd4974e4d19ffab47c1dc7af958a46fa39cd203760ca02051ebd075a6',
          decision_hash: '2937059635d33e2a3798613b380858b9da98f9c83d482169a95cd67aa7e0abd7',
        },
        source_hash: 'e2eb974cd4974e4d19ffab47c1dc7af958a46fa39cd203760ca02051ebd075a6',
        source_input: {
          source: {
            text: 'Posso caminhar amanhã?',
            channel: 'text',
          },
          intake_id: '0c35ad85-db7e-4604-a650-5d1114aa7424',
          intake_protocol: 'conversation.intake.v1',
        },
      },
    },
    {
      label: 'workout_text',
      admission: {
        action: 'admitted',
        intake: {
          epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
          owner_id: 'c1390000-0000-4000-8000-000000000010',
          intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
          input_hash: '4c981da95dad4c9ba7f7dde97c1a06397db6bcacb3e2415161bf4f183b53331c',
          admitted_at: '2026-11-05T11:23:21.582836Z',
        },
      },
      source: {
        action: 'captured',
        context: {
          epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
          media: null,
          schema: 'conversation.intake-source.v1',
          owner_id: 'c1390000-0000-4000-8000-000000000010',
          intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
          time_zone: 'UTC',
          input_hash: '4c981da95dad4c9ba7f7dde97c1a06397db6bcacb3e2415161bf4f183b53331c',
          local_date: '2026-11-05',
          admitted_at: '2026-11-05T11:23:21.582836Z',
          captured_at: '2026-11-05T11:23:21.615986Z',
          source_input: {
            source: {
              text: 'Fiz 30 minutos de caminhada.',
              channel: 'text',
            },
            intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
            intake_protocol: 'conversation.intake.v1',
          },
        },
        source_hash: '137eae6708ac9d0c7e89fc77fb02fc4e138370c500af71eb6e17d0502c134f65',
      },
      claim: {
        action: 'claimed',
        claim_id: '8c633533-a179-459b-864c-34470903527b',
      },
      seal: {
        action: 'sealed',
        selection: {
          intake: {
            epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
            owner_id: 'c1390000-0000-4000-8000-000000000010',
            intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
            input_hash: '4c981da95dad4c9ba7f7dde97c1a06397db6bcacb3e2415161bf4f183b53331c',
            admitted_at: '2026-11-05T11:23:21.582836Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: {
            kind: 'workout.report',
            epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
            input: {
              kind: 'workout.report',
              source: {
                text: 'Fiz 30 minutos de caminhada.',
                channel: 'text',
              },
              command_id: '1c7b8176-6eae-4207-93c7-f2aaa40e5652',
              command_protocol: 'conversation.command.v1',
            },
            owner_id: 'c1390000-0000-4000-8000-000000000010',
            command_id: '1c7b8176-6eae-4207-93c7-f2aaa40e5652',
            input_hash: '5262760b1d3295c177d85bb4b0ccbcf4fc3d42ed16961a08ab5c2fed159a72a8',
            admitted_at: '2026-11-05T11:23:21.825159Z',
          },
          decision: {
            kind: 'workout.report',
            reason: 'performed_activity',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:21.872821Z',
          source_hash: '137eae6708ac9d0c7e89fc77fb02fc4e138370c500af71eb6e17d0502c134f65',
          decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
        },
      },
      read_result: {
        action: 'available',
        intake: {
          epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
          owner_id: 'c1390000-0000-4000-8000-000000000010',
          intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
          input_hash: '4c981da95dad4c9ba7f7dde97c1a06397db6bcacb3e2415161bf4f183b53331c',
          admitted_at: '2026-11-05T11:23:21.582836Z',
        },
        claimed: true,
        selection: {
          intake: {
            epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
            owner_id: 'c1390000-0000-4000-8000-000000000010',
            intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
            input_hash: '4c981da95dad4c9ba7f7dde97c1a06397db6bcacb3e2415161bf4f183b53331c',
            admitted_at: '2026-11-05T11:23:21.582836Z',
          },
          schema: 'conversation.intake-selection.v1',
          command: {
            kind: 'workout.report',
            epoch: 'de2bf3b3-a206-4e41-9a0c-cbe11b8c9f26',
            input: {
              kind: 'workout.report',
              source: {
                text: 'Fiz 30 minutos de caminhada.',
                channel: 'text',
              },
              command_id: '1c7b8176-6eae-4207-93c7-f2aaa40e5652',
              command_protocol: 'conversation.command.v1',
            },
            owner_id: 'c1390000-0000-4000-8000-000000000010',
            command_id: '1c7b8176-6eae-4207-93c7-f2aaa40e5652',
            input_hash: '5262760b1d3295c177d85bb4b0ccbcf4fc3d42ed16961a08ab5c2fed159a72a8',
            admitted_at: '2026-11-05T11:23:21.825159Z',
          },
          decision: {
            kind: 'workout.report',
            reason: 'performed_activity',
            schema: 'conversation.intake-routing.v1',
          },
          selected_at: '2026-11-05T11:23:21.872821Z',
          source_hash: '137eae6708ac9d0c7e89fc77fb02fc4e138370c500af71eb6e17d0502c134f65',
          decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
        },
        source_hash: '137eae6708ac9d0c7e89fc77fb02fc4e138370c500af71eb6e17d0502c134f65',
        source_input: {
          source: {
            text: 'Fiz 30 minutos de caminhada.',
            channel: 'text',
          },
          intake_id: 'c79fe05b-1e3f-48b8-b396-3595100fb5e2',
          intake_protocol: 'conversation.intake.v1',
        },
      },
    },
  ],
}
