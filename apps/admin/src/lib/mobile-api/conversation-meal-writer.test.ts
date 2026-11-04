import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  writerBinding,
  writerPrepared,
  writerReceipt,
  writerResolved,
  writerSource,
} from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import { createSupabaseConversationMealWriter } from './conversation-meal-writer'

const owner = '10000000-0000-4000-8000-000000000001'
const commandId = '10000000-0000-4000-8000-000000000002'
const epoch = '10000000-0000-4000-8000-000000000003'
const command = () =>
  bindConversationCommand(owner, `cmsg1:${commandId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
    kind: 'meal.report',
    meal_type: 'almoco',
    source: { channel: 'text', text: 'Comi arroz 100 g' },
  })

function transport(
  handler: (name: string, args: Record<string, unknown>) => unknown | Promise<unknown>,
) {
  const calls: { name: string; args: Record<string, unknown> }[] = []
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      return { data: await handler(name, args), error: null }
    },
    from() {
      throw new Error('direct tables are forbidden')
    },
  } as unknown as ServiceClient
  return { writer: createSupabaseConversationMealWriter(client), calls, client }
}
describe('writer transport is explicit and source bound', () => {
  it('reads captured-but-unprepared state as a legitimate resumable stage', async () => {
    const raw = writerPrepared()
    Object.assign(raw, { resolved: null })
    expect(await transport(() => raw).writer.readPrepared(command())).toEqual({
      action: 'available',
      binding: writerBinding(),
      source: writerSource(),
      resolved: null,
      receipt: null,
    })
  })
  it.each([
    { action: 'available', ...{ unexpected: true } },
    { action: 'not_a_real_sql_action' },
    { action: 'absent', receipt: null },
    { action: 'available', command: writerBinding(), source: null, resolved: null },
  ])('fails closed on malformed wire envelope %#', async (raw) => {
    await expect(transport(() => raw).writer.readPrepared(command())).rejects.toMatchObject({
      code: 'conversation_meal_writer_unavailable',
    })
  })
  it('rejects changed full bound input before contacting any transport', async () => {
    const t = transport(() => ({ action: 'absent' })),
      bound = structuredClone(command())
    Object.assign(bound.command.source, { text: 'Comi feijão 100 g' })
    await expect(t.writer.readPrepared(bound)).rejects.toMatchObject({
      code: 'conversation_meal_writer_unavailable',
    })
    await expect(
      t.writer.prepare({ command: bound, source: writerSource(), resolved: writerResolved() }),
    ).rejects.toMatchObject({ code: 'conversation_meal_writer_unavailable' })
    await expect(
      t.writer.commit({ command: bound, resolvedHash: 'c'.repeat(64) }),
    ).rejects.toMatchObject({ code: 'conversation_meal_writer_unavailable' })
    expect(t.calls).toEqual([])
  })
  it('returns a sealed resolved winner before any calculation and detaches every nested private field', async () => {
    const raw = writerPrepared(),
      t = transport(() => raw)
    const result = await t.writer.readPrepared(command())
    expect(result.action).toBe('available')
    if (result.action !== 'available') return
    expect(result.binding).toEqual(writerBinding())
    expect(result.source).toEqual(writerSource())
    expect(result.resolved).toEqual({
      resolvedHash: 'c'.repeat(64),
      preparedAt: '2026-11-04T12:00:00.000003Z',
      value: writerResolved(),
    })
    raw.source.context.clinical.policy.status = 'changed'
    expect(result.source?.context.clinical).toEqual({
      policy: { status: 'available' },
      safety: { reasons: [] },
    })
    expect(Object.isFrozen(result.source?.context.clinical.policy)).toBe(true)
    expect(t.calls.map((c) => c.name)).toEqual(['read_conversation_meal_prepared'])
  })
  it('prepares exactly the validated full DTO and treats the DB hash as opaque', async () => {
    const t = transport(() => ({ action: 'prepared', resolved_hash: 'f'.repeat(64) })),
      raw = writerResolved()
    const promise = t.writer.prepare({ command: command(), source: writerSource(), resolved: raw })
    raw.items[0].name = 'after call'
    const result = await promise
    expect(result).toEqual({ action: 'prepared', resolvedHash: 'f'.repeat(64) })
    expect(t.calls).toEqual([
      {
        name: 'prepare_conversation_meal',
        args: { p_user_id: owner, p_command_id: commandId, p_resolved: writerResolved() },
      },
    ])
    expect(Object.isFrozen(t.calls[0]?.args.p_resolved)).toBe(true)
  })
  it('preserves legitimate preparation replay and conflict actions without another operation', async () => {
    for (const data of [
      { action: 'replay', resolved_hash: 'f'.repeat(64) },
      ...[
        'absent',
        'stale_epoch',
        'resolved_conflict',
        'source_required',
        'source_conflict',
        'day_closed',
      ].map((action) => ({ action })),
    ]) {
      const t = transport(() => data),
        result = await t.writer.prepare({
          command: command(),
          source: writerSource(),
          resolved: writerResolved(),
        })
      expect(result).toEqual(
        'resolved_hash' in data ? { action: data.action, resolvedHash: data.resolved_hash } : data,
      )
      expect(t.calls.length).toBe(1)
    }
  })
  it('recovers a lost prepare reply only through an explicit read and adopts the actual sealed payload', async () => {
    const raw = writerPrepared(),
      t = transport((name) => {
        if (name === 'prepare_conversation_meal') throw new Error('lost after commit, private URL')
        if (name === 'read_conversation_meal_prepared') return raw
        throw new Error('unexpected operation')
      })
    await expect(
      t.writer.prepare({ command: command(), source: writerSource(), resolved: writerResolved() }),
    ).rejects.toMatchObject({ code: 'conversation_meal_writer_unavailable' })
    expect(t.calls.map((c) => c.name)).toEqual(['prepare_conversation_meal'])
    expect(await t.writer.readPrepared(command())).toMatchObject({
      resolved: { resolvedHash: 'c'.repeat(64), value: writerResolved() },
    })
    expect(t.calls.map((c) => c.name)).toEqual([
      'prepare_conversation_meal',
      'read_conversation_meal_prepared',
    ])
  })
  it('does not retry an unknown domain commit and recovers the original receipt by explicit read', async () => {
    const t = transport((name) => {
      if (name === 'commit_conversation_meal') throw new Error('lost response')
      return { action: 'available', receipt: writerReceipt() }
    })
    await expect(
      t.writer.commit({ command: command(), resolvedHash: 'c'.repeat(64) }),
    ).rejects.toMatchObject({ code: 'conversation_meal_writer_unavailable' })
    expect(t.calls.length).toBe(1)
    expect(await t.writer.readEffect(command())).toEqual({
      action: 'available',
      receipt: writerReceipt(),
    })
    expect(t.calls.map((c) => c.name)).toEqual([
      'commit_conversation_meal',
      'read_conversation_meal_effect',
    ])
  })
  it('returns the first committed winner even when a replay hash is obsolete or malformed', async () => {
    const t = transport(() => ({ action: 'replay', receipt: writerReceipt() }))
    expect(await t.writer.commit({ command: command(), resolvedHash: 'obsolete' })).toEqual({
      action: 'replay',
      receipt: writerReceipt(),
    })
    expect(t.calls[0]).toEqual({
      name: 'commit_conversation_meal',
      args: { p_user_id: owner, p_command_id: commandId, p_resolved_hash: 'obsolete' },
    })
  })
  it.each([
    'committed',
    'replay',
  ])('strictly decodes %s factual effect and sealed read after C11', async (action) => {
    const t = transport(() => ({ action, receipt: writerReceipt() }))
    expect(await t.writer.commit({ command: command(), resolvedHash: 'c'.repeat(64) })).toEqual({
      action,
      receipt: writerReceipt(),
    })
    const raw = writerPrepared()
    raw.receipt = writerReceipt()
    const recovered = await transport(() => raw).writer.readPrepared(command())
    expect(recovered).toMatchObject({ action: 'available', receipt: writerReceipt() })
  })
  it.each([
    'absent',
    'stale_epoch',
    'resolved_required',
    'resolved_conflict',
    'source_conflict',
    'day_closed',
  ])('preserves commit refusal %s', async (action) => {
    const t = transport(() => ({ action }))
    expect(await t.writer.commit({ command: command(), resolvedHash: 'c'.repeat(64) })).toEqual({
      action,
    })
    expect(t.calls.length).toBe(1)
  })
  it.each(['absent', 'stale_epoch'])('preserves read refusal %s', async (action) => {
    const t = transport(() => ({ action }))
    expect(await t.writer.readPrepared(command())).toEqual({ action })
    expect(await t.writer.readEffect(command())).toEqual({ action })
  })
  it('fails closed on event_conflict without a write, calculation or provider fallback', async () => {
    const t = transport(() => ({ action: 'event_conflict' }))
    await expect(t.writer.readPrepared(command())).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_writer_event_conflict',
    })
    expect(t.calls.map((c) => c.name)).toEqual(['read_conversation_meal_prepared'])
  })
  it.each([
    'source',
    'resolved',
    'receipt',
  ])('rejects malformed presence dependency %s', async (field) => {
    const raw = writerPrepared()
    Object.assign(raw, { [field]: null })
    if (field === 'resolved') raw.receipt = writerReceipt()
    if (field === 'receipt') {
      raw.receipt = writerReceipt()
      Object.assign(raw, { resolved: null })
    }
    await expect(transport(() => raw).writer.readPrepared(command())).rejects.toMatchObject({
      code: 'conversation_meal_writer_unavailable',
    })
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
    'epoch',
  ])('rejects stored binding %s mismatch', async (field) => {
    const raw = writerPrepared()
    Object.assign(raw.command, { [field]: '00000000-0000-0000-0000-000000000000' })
    await expect(transport(() => raw).writer.readPrepared(command())).rejects.toMatchObject({
      code: 'conversation_meal_writer_unavailable',
    })
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
    'provider_key',
    'meal_type',
    'local_date',
    'timezone',
    'log_ids',
    'effect_version',
  ])('rejects invalid factual receipt %s', async (field) => {
    const receipt = writerReceipt()
    Object.assign(receipt, {
      [field]: field === 'log_ids' ? [receipt.log_ids[0], receipt.log_ids[0]] : 'bad',
    })
    await expect(
      transport(() => ({ action: 'available', receipt })).writer.readEffect(command()),
    ).rejects.toMatchObject({ code: 'conversation_meal_writer_unavailable' })
  })
  it('snapshots full command and captures the SDK method before awaits', async () => {
    let release: (value: unknown) => void = () => {}
    const deferred = new Promise((resolve) => {
      release = resolve
    })
    const t = transport(() => deferred),
      input = structuredClone(command()),
      promise = t.writer.readPrepared(input)
    Object.assign(input.command, { source: { channel: 'text', text: 'modified' } })
    t.client.rpc = (() => {
      throw new Error('mutated SDK')
    }) as ServiceClient['rpc']
    release({
      action: 'available',
      command: writerBinding(),
      source: null,
      resolved: null,
      receipt: null,
    })
    expect(await promise).toMatchObject({ action: 'available', binding: writerBinding() })
    expect(await t.writer.readPrepared(command())).toMatchObject({ action: 'available' })
  })
  it.each([
    ['40001', 'conflict'],
    ['55P03', 'busy'],
  ])('preserves SQL %s as redacted %s', async (code, suffix) => {
    const rpc = vi.fn(async () => ({
        data: null,
        error: { code, message: 'secret database connection' },
      })),
      writer = createSupabaseConversationMealWriter({ rpc } as unknown as ServiceClient)
    await expect(writer.readPrepared(command())).rejects.toMatchObject({
      status: 409,
      code: `conversation_meal_writer_${suffix}`,
      message: 'Meal registration state is unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})

describe('private meal writer recovery', () => {
  it('reads admitted state without calculating, registering or claiming a provider invocation', async () => {
    const raw = {
      action: 'available',
      command: {
        owner_id: owner,
        command_id: commandId,
        input_hash: command().inputHash,
        command_protocol: 'conversation.command.v1',
        kind: 'meal.report',
        epoch,
        admitted_at: '2026-11-04T12:00:00.000Z',
      },
      source: null,
      resolved: null,
      receipt: null,
    }
    const calls: string[] = []
    const rpc = vi.fn(async (name: string, args: unknown) => {
      calls.push(name)
      expect(args).toEqual({ p_user_id: owner, p_command_id: commandId })
      return { data: raw, error: null }
    })
    const db = {
      rpc,
      from() {
        throw new Error('live source or domain forbidden')
      },
    } as unknown as ServiceClient
    const writer = createSupabaseConversationMealWriter(db)
    expect(calls).toEqual([])
    const result = await writer.readPrepared(command())
    expect(result).toEqual({
      action: 'available',
      binding: raw.command,
      source: null,
      resolved: null,
      receipt: null,
    })
    expect(calls).toEqual(['read_conversation_meal_prepared'])
    expect(Object.isFrozen(result)).toBe(true)
  })
})
