import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import actualSQL from './__fixtures__/conversation-meal-continuation-read-sql.json'
import { createSupabaseConversationMealContinuationSourceFactory } from './conversation-meal-continuation-source'

type Available = typeof actualSQL.samples.admitted_quantity_reply
const receiptID = '40000000-0000-4000-8000-000000000001'
const missID = '40000000-0000-4000-8000-000000000002'
const foreign = '40000000-0000-4000-8000-000000000003'
function at<T>(values: T[]): T {
  const value = values[0]
  if (value === undefined) throw new Error('fixture value')
  return value
}
function fixture(key: keyof typeof actualSQL.samples = 'admitted_quantity_reply') {
  const raw = structuredClone(actualSQL.samples[key]) as unknown as Available
  const identity = {
    ownerId: raw.parent.binding.owner_id,
    parentCommandId: raw.parent.binding.command_id,
    parentInputHash: raw.parent.binding.input_hash,
    epoch: raw.parent.binding.epoch,
    replyId: raw.reply?.binding.command_id ?? null,
    replyInputHash: raw.reply?.binding.input_hash ?? null,
  }
  return { raw, identity }
}
function row(f = fixture()) {
  if (!f.raw.reply) throw new Error('synthetic fixture reply')
  return {
    id: foreign,
    user_id: f.identity.ownerId,
    created_at: f.raw.reply.source.captured_at,
    food_name: 'arroz cozido',
    food_db_id: 1,
    quantity_g: 100,
    kcal: 130,
    protein_g: 3,
    carbs_g: 27,
    fat_g: 1,
    source: 'canonical_exact',
    food_db: { is_verified: true },
  }
}
function lookup(f = fixture(), rows: ReturnType<typeof row>[] = [row(f)]) {
  if (!f.raw.reply) throw new Error('synthetic fixture reply')
  return {
    action: 'captured',
    owner_id: f.identity.ownerId,
    command_id: f.raw.reply.binding.command_id,
    source_receipt_id: receiptID,
    source_receipt_hash: 'a'.repeat(64),
    as_of: f.raw.reply.source.captured_at,
    rows,
  }
}
function db() {
  const rpc = vi.fn()
  const from = vi.fn(() => {
    throw new Error('live history forbidden')
  })
  return { rpc, from, client: { rpc, from } as unknown as ServiceClient }
}

describe('inert original/fresh linked source ports', () => {
  it.each([
    'admitted_quantity_reply',
    'admitted_meal_type_reply',
    'awaiting_reply',
    'prepared',
    'saved',
    'superseded',
    'historical_next_question_after_fulfillment',
  ] as const)('retains exact stored parent and child authority from actual SQL %s', (key) => {
    const f = fixture(key),
      d = db()
    const factory = createSupabaseConversationMealContinuationSourceFactory(d.client)
    expect(d.rpc).not.toHaveBeenCalled()
    const value = factory.fromRead(f.identity, f.raw)
    const child = f.raw.reply
    if (!child) throw new Error('fixture reply')
    expect(Object.keys(value).sort()).toEqual([
      'command',
      'interpretation',
      'originalSource',
      'resolutionSource',
    ])
    expect(value.command.commandId).toBe(f.identity.parentCommandId)
    expect(value.command.inputHash).toBe(f.identity.parentInputHash)
    expect(isDeepStrictEqual(value.command.command, f.raw.parent.source.context.source_input)).toBe(
      true,
    )
    expect(isDeepStrictEqual(value.interpretation, f.raw.parent.semantic.result)).toBe(true)
    expect(isDeepStrictEqual(value.originalSource.context, f.raw.parent.source.context)).toBe(true)
    expect(
      isDeepStrictEqual(value.resolutionSource.context, child.source.context.authority.context),
    ).toBe(true)
    expect(value.originalSource.sourceHash).toBe(f.raw.parent.source.source_hash)
    expect(value.originalSource.capturedAt).toBe(f.raw.parent.source.captured_at)
    expect(value.resolutionSource.sourceHash).toBe(child.source.context.authority.source_hash)
    expect(value.resolutionSource.sourceHash).not.toBe(child.source.source_hash)
    expect(value.resolutionSource.capturedAt).toBe(child.source.captured_at)
    for (const source of [value.originalSource, value.resolutionSource]) {
      expect(source.action).toBe('replay')
      expect(source.context.command_id).toBe(f.identity.parentCommandId)
      expect(source.context.owner.country).toBe('BR')
      expect(source.sourceReader.ownerId).toBe(f.identity.ownerId)
      expect(source.sourceReader.asOf).toBe(source.capturedAt)
      expect(source.sourceReceipts()).toEqual([])
      expect(source.auditEvents()).toEqual([])
      expect(Object.isFrozen(source)).toBe(true)
      expect(Object.isFrozen(source.context)).toBe(true)
      expect(Object.isFrozen(source.sourceReader)).toBe(true)
    }
    expect(Object.isFrozen(value)).toBe(true)
    expect(Object.isFrozen(value.interpretation)).toBe(true)
    expect(d.rpc).not.toHaveBeenCalled()
    expect(d.from).not.toHaveBeenCalled()
  })

  it('pins SDK callback at factory construction and calls only the real child lookup ID', async () => {
    const f = fixture(),
      d = db(),
      raw = lookup(f),
      factory = createSupabaseConversationMealContinuationSourceFactory(d.client)
    d.rpc.mockResolvedValue({ data: raw, error: null })
    const replacement = vi.fn()
    Object.assign(d.client, { rpc: replacement })
    const value = factory.fromRead(f.identity, f.raw)
    const originalIdentity = { ...f.identity }
    f.identity.ownerId = foreign
    f.identity.replyId = foreign
    if (!f.raw.reply) throw new Error('fixture')
    f.raw.reply.source.context.authority.context.owner.country = 'US'
    Object.assign(f.raw.parent.source.context.clinical, { changed: true })
    const rows = await value.resolutionSource.sourceReader.read('trusted_recent', null)
    expect(rows).toEqual([row(fixture())])
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(d.rpc).toHaveBeenCalledWith('read_conversation_meal_continuation_nutrition_source', {
      p_user_id: originalIdentity.ownerId,
      p_reply_id: originalIdentity.replyId,
      p_kind: 'trusted_recent',
      p_food_name: null,
    })
    expect(replacement).not.toHaveBeenCalled()
    expect(value.resolutionSource.context.owner.country).toBe('BR')
    expect(value.originalSource.context.clinical).not.toHaveProperty('changed')
    at(raw.rows).kcal = 9999
    expect(rows[0]?.kcal).toBe(130)
    expect(Object.isFrozen(rows[0]?.food_db)).toBe(true)
  })

  it('keeps original and fresh clocks/receipt collectors separate; never captures again', async () => {
    const f = fixture(),
      d = db()
    d.rpc
      .mockResolvedValueOnce({ data: lookup(f), error: null })
      .mockResolvedValueOnce({
        data: { ...lookup(f, []), source_receipt_id: missID, source_receipt_hash: 'b'.repeat(64) },
        error: null,
      })
      .mockResolvedValueOnce({ data: { ...lookup(f), action: 'replay' }, error: null })
      .mockResolvedValueOnce({
        data: {
          ...lookup(f, []),
          command_id: f.identity.parentCommandId,
          as_of: f.raw.parent.source.captured_at,
          source_receipt_id: foreign,
        },
        error: null,
      })
    const value = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    )
    const fresh = value.resolutionSource,
      original = value.originalSource
    expect(await fresh.sourceReader.read('trusted_recent', null)).toHaveLength(1)
    expect(await fresh.sourceReader.read('exact_median', '  Arroz % original  ')).toEqual([])
    await fresh.sourceReader.read('trusted_recent', null)
    expect(fresh.sourceReceipts()).toEqual([
      { id: receiptID, hash: 'a'.repeat(64) },
      { id: missID, hash: 'b'.repeat(64) },
    ])
    expect(original.sourceReceipts()).toEqual([])
    await original.sourceReader.read('trusted_recent', null)
    expect(d.rpc.mock.calls[1]).toEqual([
      'read_conversation_meal_continuation_nutrition_source',
      {
        p_user_id: f.identity.ownerId,
        p_reply_id: f.identity.replyId,
        p_kind: 'exact_median',
        p_food_name: '  Arroz % original  ',
      },
    ])
    expect(d.rpc.mock.calls[3]).toEqual([
      'read_conversation_meal_nutrition_source',
      {
        p_user_id: f.identity.ownerId,
        p_command_id: f.identity.parentCommandId,
        p_kind: 'trusted_recent',
        p_food_name: null,
      },
    ])
    expect(original.sourceReceipts()).toHaveLength(1)
    expect(fresh.sourceReceipts()).toHaveLength(2)
    expect(d.rpc.mock.calls.every(([name]) => !String(name).includes('capture'))).toBe(true)
    expect(d.from).not.toHaveBeenCalled()
  })

  it('retains owner-bound audit intent only in RAM and separates old/new collectors', async () => {
    const f = fixture(),
      d = db(),
      value = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
        f.identity,
        f.raw,
      )
    const event = {
      user_id: f.identity.ownerId,
      event: 'meal_calc.history_reused',
      properties: { nested: { id: 'synthetic' } },
    }
    await value.resolutionSource.auditSink(event)
    event.properties.nested.id = 'changed'
    expect(value.resolutionSource.auditEvents()).toEqual([
      {
        user_id: f.identity.ownerId,
        event: 'meal_calc.history_reused',
        properties: { nested: { id: 'synthetic' } },
      },
    ])
    expect(value.originalSource.auditEvents()).toEqual([])
    expect(Object.isFrozen(value.resolutionSource.auditEvents()[0]?.properties)).toBe(true)
    await expect(
      value.resolutionSource.auditSink({ ...event, user_id: foreign }),
    ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
    expect(d.rpc).not.toHaveBeenCalled()
    expect(d.from).not.toHaveBeenCalled()
  })

  it.each([
    'parent_head',
    'fulfilled_without_requested_reply',
  ] as const)('requires a real requested child source: %s', (key) => {
    const f = fixture(key),
      d = db()
    expect(() =>
      createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(f.identity, f.raw),
    ).toThrow()
    expect(d.rpc).not.toHaveBeenCalled()
  })

  it.each([
    'owner',
    'epoch',
    'hash',
    'country',
    'clock',
    'input',
    'semantic',
    'extra',
  ] as const)('refuses crossed %s before any lookup', (attack) => {
    const f = fixture(),
      d = db()
    if (!f.raw.reply) throw new Error('fixture')
    if (attack === 'owner') f.identity.ownerId = foreign
    if (attack === 'epoch') f.identity.epoch = foreign
    if (attack === 'hash') f.identity.parentInputHash = 'f'.repeat(64)
    if (attack === 'country') f.raw.reply.source.context.authority.context.owner.country = 'US'
    if (attack === 'clock') f.raw.reply.source.captured_at = f.raw.parent.source.captured_at
    if (attack === 'input')
      Object.assign(f.raw.reply.source.context.authority.context.source_input, {
        meal_type: 'jantar',
      })
    if (attack === 'semantic')
      Object.assign(f.raw.parent.semantic.result, { decision: 'not_a_meal' })
    if (attack === 'extra') Object.assign(f.raw, { extra: 'private-sentinel' })
    expect(() =>
      createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(f.identity, f.raw),
    ).toThrow()
    expect(d.rpc).not.toHaveBeenCalled()
  })

  it('does not execute a caller getter while revalidating the complete read', () => {
    const f = fixture(),
      d = db()
    let effects = 0
    Object.defineProperty(f.raw, 'reply', {
      enumerable: true,
      get() {
        effects++
        return null
      },
    })
    expect(() =>
      createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(f.identity, f.raw),
    ).toThrow()
    expect(effects).toBe(0)
    expect(d.rpc).not.toHaveBeenCalled()
  })
})

describe('shared exact nutrition lookup qualification with fresh cutoff', () => {
  it.each([
    'owner',
    'parent-id',
    'as-of',
    'late-row',
    'old-row',
    'foreign-row',
    'extra-row',
    'extra-result',
    'duplicate',
    'ordering',
    'unsafe-id',
    'join',
    'nonfinite',
    'limit',
  ] as const)('refuses child result %s without a receipt', async (attack) => {
    const f = fixture(),
      d = db(),
      result = lookup(f)
    if (attack === 'owner') result.owner_id = foreign
    if (attack === 'parent-id') result.command_id = f.identity.parentCommandId
    if (attack === 'as-of') result.as_of = f.raw.parent.source.captured_at
    if (attack === 'late-row') at(result.rows).created_at = '2099-01-01T00:00:00Z'
    if (attack === 'old-row') at(result.rows).created_at = '2000-01-01T00:00:00Z'
    if (attack === 'foreign-row') at(result.rows).user_id = foreign
    if (attack === 'extra-row') Object.assign(at(result.rows), { private_value: true })
    if (attack === 'extra-result') Object.assign(result, { private_value: true })
    if (attack === 'duplicate') result.rows.push(at(result.rows))
    if (attack === 'ordering')
      result.rows.push({ ...at(result.rows), id: 'f0000000-0000-4000-8000-000000000004' })
    if (attack === 'unsafe-id') at(result.rows).food_db_id = Number.MAX_SAFE_INTEGER + 1
    if (attack === 'join') Object.assign(at(result.rows), { food_db_id: null })
    if (attack === 'nonfinite') at(result.rows).kcal = NaN
    if (attack === 'limit') result.rows = Array.from({ length: 51 }, () => row(f))
    d.rpc.mockResolvedValue({ data: result, error: null })
    const value = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    )
    await expect(
      value.resolutionSource.sourceReader.read('trusted_recent', null),
    ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
    expect(value.resolutionSource.sourceReceipts()).toEqual([])
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    'id',
    'hash',
    'rows',
    'cross-lookup',
  ] as const)('rejects changed correction/source receipt %s', async (attack) => {
    const f = fixture(),
      d = db(),
      first = lookup(f),
      second = lookup(f)
    if (attack === 'id') second.source_receipt_id = missID
    if (attack === 'hash') second.source_receipt_hash = 'b'.repeat(64)
    if (attack === 'rows') at(second.rows).kcal = 131
    d.rpc
      .mockResolvedValueOnce({ data: first, error: null })
      .mockResolvedValueOnce({ data: second, error: null })
    const value = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    ).resolutionSource
    await value.sourceReader.read('trusted_recent', null)
    await expect(
      value.sourceReader.read(
        attack === 'cross-lookup' ? 'exact_median' : 'trusted_recent',
        attack === 'cross-lookup' ? 'arroz' : null,
      ),
    ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
    expect(value.sourceReceipts()).toHaveLength(1)
  })

  it.each([
    'absent',
    'stale_epoch',
    'source_required',
    'source_conflict',
    'sealed',
    'event_conflict',
  ] as const)('retains SQL refusal %s without retry/fallback', async (action) => {
    const f = fixture(),
      d = db()
    d.rpc.mockResolvedValue({ data: { action }, error: null })
    const source = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    ).resolutionSource
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      status: 409,
      code: `conversation_meal_source_${action}`,
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    expect(source.sourceReceipts()).toEqual([])
  })

  it('redacts transport/SQL failures and validates lookup arguments before RPC', async () => {
    const f = fixture(),
      d = db(),
      source = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
        f.identity,
        f.raw,
      ).resolutionSource
    await expect(source.sourceReader.read('trusted_recent', 'arroz')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    await expect(source.sourceReader.read('exact_median', ' ')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(d.rpc).not.toHaveBeenCalled()
    d.rpc.mockRejectedValueOnce(new Error('private-sentinel'))
    try {
      await source.sourceReader.read('trusted_recent', null)
      throw new Error('expected')
    } catch (error) {
      expect(String(error)).not.toContain('private-sentinel')
    }
    d.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '40001', message: 'private-sentinel' },
    })
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_source_conflict',
    })
    expect(source.sourceReceipts()).toEqual([])
    expect(d.rpc).toHaveBeenCalledTimes(2)
  })
})

describe('literal fresh cutoff precision', () => {
  it('refuses even an equivalent normalized as_of string rather than replacing the SQL literal', async () => {
    const f = fixture(),
      d = db(),
      result = lookup(f)
    const changed = result.as_of.replace('+00:00', 'Z')
    expect(changed).not.toBe(result.as_of)
    result.as_of = changed
    d.rpc.mockResolvedValue({ data: result, error: null })
    const source = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    ).resolutionSource
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toEqual([])
  })

  it('rejects a nutrition row one microsecond after the fresh capture and keeps NULL facts for exact lookups', async () => {
    const f = fixture(),
      d = db(),
      result = lookup(f)
    const parts = /^(.*\.)(\d{6})(\+00:00)$/.exec(result.as_of)
    if (!parts?.[1] || !parts[2] || !parts[3] || Number(parts[2]) >= 999999)
      throw new Error('actual fixture microsecond clock')
    at(result.rows).created_at = parts[1] + String(Number(parts[2]) + 1).padStart(6, '0') + parts[3]
    const nullable = {
      ...lookup(f),
      rows: [
        {
          ...row(f),
          food_db_id: null,
          food_db: null,
          quantity_g: null,
          kcal: null,
          protein_g: null,
          carbs_g: null,
          fat_g: null,
        },
      ],
    }
    d.rpc
      .mockResolvedValueOnce({ data: result, error: null })
      .mockResolvedValueOnce({ data: nullable, error: null })
    const source = createSupabaseConversationMealContinuationSourceFactory(d.client).fromRead(
      f.identity,
      f.raw,
    ).resolutionSource
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toEqual([])
    expect(await source.sourceReader.read('exact_median', 'arroz')).toEqual(nullable.rows)
    expect(source.sourceReceipts()).toEqual([{ id: receiptID, hash: 'a'.repeat(64) }])
  })
})
