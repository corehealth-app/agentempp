import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  candidateCommand,
  candidateId,
  candidateOwner,
} from './__fixtures__/conversation-candidate'
import { createSupabaseConversationMealSourceFactory } from './conversation-meal-source'

const asOf = '2026-11-04T00:00:00.123456+00:00'
const epoch = '10000000-0000-4000-8000-000000000004'
const receiptId = '10000000-0000-4000-8000-000000000005'
function capture() {
  const command = candidateCommand()
  return {
    action: 'captured',
    source_hash: 'a'.repeat(64),
    captured_at: asOf,
    context: {
      schema: 'conversation.meal-source.v1',
      owner_id: candidateOwner,
      command_id: candidateId,
      input_hash: command.inputHash,
      epoch,
      source_input: command.command,
      source_units: ['command_text'],
      source_evidence: {},
      media: null,
      catalog: { epoch, revision: '1' },
      owner: {
        timezone: 'America/Sao_Paulo',
        locale: 'pt-BR',
        country: 'BR',
        country_confirmed: true,
      },
      clinical: { schema: 'private-test-clinical', safety: { status: 'stable' } },
      day: {
        date: '2026-11-03',
        day_closed: false,
        calories_target: null,
        protein_target: null,
        current_protocol: null,
        target_revision: '0',
        calorie_origin: null,
      },
    },
  }
}
function row() {
  return {
    id: '10000000-0000-4000-8000-000000000006',
    user_id: candidateOwner,
    created_at: '2026-11-03T10:00:00.123456+00:00',
    food_name: 'arroz',
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
function lookup(rows: unknown[] = [row()]) {
  return {
    action: 'captured',
    owner_id: candidateOwner,
    command_id: candidateId,
    source_receipt_id: receiptId,
    source_receipt_hash: 'b'.repeat(64),
    as_of: asOf,
    rows,
  }
}
function db() {
  const rpc = vi.fn().mockResolvedValueOnce({ data: capture(), error: null })
  const from = vi.fn(() => {
    throw new Error('live history and product_events forbidden')
  })
  return { client: { rpc, from } as unknown as ServiceClient, rpc, from }
}

describe('real command-bound meal source factory', () => {
  it('construction is inert; explicit capture binds original owner/command and exact DB clock', async () => {
    const d = db(),
      raw = capture()
    d.rpc.mockReset().mockResolvedValueOnce({ data: raw, error: null })
    const factory = createSupabaseConversationMealSourceFactory(d.client)
    expect(d.rpc).not.toHaveBeenCalled()
    const source = await factory.capture(candidateCommand())
    expect(d.rpc).toHaveBeenCalledWith('capture_conversation_meal_source', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
    })
    expect(source).toMatchObject({
      action: 'captured',
      sourceHash: 'a'.repeat(64),
      capturedAt: asOf,
      epoch,
    })
    expect(source.sourceReader.ownerId).toBe(candidateOwner)
    expect(source.sourceReader.asOf).toBe(asOf)
    expect(source.sourceReceipts()).toEqual([])
    expect(source.auditEvents()).toEqual([])
    raw.context.clinical.safety.status = 'changed'
    expect(source.context.clinical).toEqual({
      schema: 'private-test-clinical',
      safety: { status: 'stable' },
    })
    expect(source.context.clinical).not.toHaveProperty('observed_at')
    expect(Object.isFrozen(source.sourceReader)).toBe(true)
    expect(Object.isFrozen(source.context)).toBe(true)
    expect(d.from).not.toHaveBeenCalled()
  })

  it('rejects a forged original bound command before any RPC', async () => {
    for (const change of [
      { ownerId: 'invalid-owner' },
      { commandId: candidateOwner },
      { inputHash: '0'.repeat(64) },
      { extra: true },
    ]) {
      const d = db()
      await expect(
        createSupabaseConversationMealSourceFactory(d.client).capture({
          ...candidateCommand(),
          ...change,
        }),
      ).rejects.toMatchObject({ status: 503, code: 'conversation_meal_source_unavailable' })
      expect(d.rpc).not.toHaveBeenCalled()
    }
  })

  it('uses only the real RPC and deduplicates every lookup receipt including MISS and replay', async () => {
    const d = db()
    d.rpc
      .mockResolvedValueOnce({ data: lookup(), error: null })
      .mockResolvedValueOnce({
        data: { ...lookup([]), source_receipt_id: epoch, source_receipt_hash: 'c'.repeat(64) },
        error: null,
      })
      .mockResolvedValueOnce({ data: { ...lookup(), action: 'replay' }, error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    expect(await source.sourceReader.read('trusted_recent', null)).toEqual([row()])
    expect(await source.sourceReader.read('exact_median', '  Arroz % original  ')).toEqual([])
    expect(await source.sourceReader.read('trusted_recent', null)).toEqual([row()])
    expect(d.rpc.mock.calls.slice(1)).toEqual([
      [
        'read_conversation_meal_nutrition_source',
        {
          p_user_id: candidateOwner,
          p_command_id: candidateId,
          p_kind: 'trusted_recent',
          p_food_name: null,
        },
      ],
      [
        'read_conversation_meal_nutrition_source',
        {
          p_user_id: candidateOwner,
          p_command_id: candidateId,
          p_kind: 'exact_median',
          p_food_name: '  Arroz % original  ',
        },
      ],
      [
        'read_conversation_meal_nutrition_source',
        {
          p_user_id: candidateOwner,
          p_command_id: candidateId,
          p_kind: 'trusted_recent',
          p_food_name: null,
        },
      ],
    ])
    expect(source.sourceReceipts()).toEqual([
      { id: receiptId, hash: 'b'.repeat(64) },
      { id: epoch, hash: 'c'.repeat(64) },
    ])
    expect(Object.isFrozen(source.sourceReceipts())).toBe(true)
    expect(d.from).not.toHaveBeenCalled()
  })

  it('captures command and RPC callback before awaits and detaches returned rows deeply', async () => {
    const d = db(),
      original = structuredClone(candidateCommand()),
      rawRow = row(),
      raw = lookup([rawRow])
    let release!: (value: unknown) => void
    d.rpc
      .mockReset()
      .mockReturnValueOnce(
        new Promise((resolve) => {
          release = resolve
        }),
      )
      .mockResolvedValueOnce({ data: raw, error: null })
    const pending = createSupabaseConversationMealSourceFactory(d.client).capture(original)
    Object.assign(original, { ownerId: candidateId, inputHash: '0'.repeat(64) })
    const replacement = vi.fn()
    Object.assign(d.client, { rpc: replacement })
    release({ data: capture(), error: null })
    const source = await pending
    const result = await source.sourceReader.read('trusted_recent', null)
    Object.assign(rawRow, { kcal: 9999 })
    Object.assign(rawRow.food_db, { is_verified: false })
    expect(result[0]).toEqual(row())
    expect(Object.isFrozen(result[0]?.food_db)).toBe(true)
    expect(replacement).not.toHaveBeenCalled()
  })

  it.each([
    'source_receipt_id',
    'source_receipt_hash',
    'rows',
  ] as const)('refuses changed %s on the same lookup', async (field) => {
    const d = db(),
      changed = lookup()
    if (field === 'source_receipt_id') changed.source_receipt_id = epoch
    else if (field === 'source_receipt_hash') changed.source_receipt_hash = 'c'.repeat(64)
    else changed.rows = [{ ...row(), kcal: 131 }]
    d.rpc
      .mockResolvedValueOnce({ data: lookup(), error: null })
      .mockResolvedValueOnce({ data: changed, error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    await source.sourceReader.read('trusted_recent', null)
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toEqual([{ id: receiptId, hash: 'b'.repeat(64) }])
  })

  it('always exposes an owner-bound memory audit collector, never product_events', async () => {
    const d = db(),
      source = await createSupabaseConversationMealSourceFactory(d.client).capture(
        candidateCommand(),
      )
    const event = {
      user_id: candidateOwner,
      event: 'meal_calc.history_reused',
      properties: { nested: { id: 'private' } },
    }
    await source.auditSink(event)
    event.properties.nested.id = 'changed'
    expect(source.auditEvents()).toEqual([
      {
        user_id: candidateOwner,
        event: 'meal_calc.history_reused',
        properties: { nested: { id: 'private' } },
      },
    ])
    expect(Object.isFrozen(source.auditEvents()[0]?.properties)).toBe(true)
    await expect(source.auditSink({ ...event, user_id: candidateId })).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(d.from).not.toHaveBeenCalled()
  })

  it.each([
    ['foreign owner', { owner_id: candidateId }],
    ['foreign command', { command_id: candidateOwner }],
    ['changed exact cutoff', { as_of: '2026-11-04T00:00:00.123456Z' }],
    ['unknown envelope field', { private_secret: 'private-sentinel' }],
    ['invalid receipt UUID', { source_receipt_id: 'not-a-uuid' }],
    ['invalid receipt hash', { source_receipt_hash: 'BAD' }],
    ['foreign row owner', { rows: [{ ...row(), user_id: candidateId }] }],
    ['invalid row UUID', { rows: [{ ...row(), id: 'legacy-text' }] }],
    ['unknown row field', { rows: [{ ...row(), extra: 'private-sentinel' }] }],
    [
      'unknown food reference field',
      { rows: [{ ...row(), food_db: { is_verified: true, extra: 1 } }] },
    ],
    ['nonfinite nutrition', { rows: [{ ...row(), protein_g: Number.NaN }] }],
    ['string nutrition', { rows: [{ ...row(), kcal: '130' }] }],
    ['unsafe reference ID', { rows: [{ ...row(), food_db_id: Number.MAX_SAFE_INTEGER + 1 }] }],
    ['contradictory joined reference', { rows: [{ ...row(), food_db_id: null }] }],
    ['untrusted source', { rows: [{ ...row(), source: 'vision_estimate' }] }],
    ['nonpositive recent kcal', { rows: [{ ...row(), kcal: 0 }] }],
    ['invalid civil timestamp', { rows: [{ ...row(), created_at: '2026-02-30T10:00:00Z' }] }],
    [
      'one microsecond after cutoff',
      { rows: [{ ...row(), created_at: '2026-11-04T00:00:00.123457+00:00' }] },
    ],
    [
      'one microsecond outside window',
      { rows: [{ ...row(), created_at: '2026-10-05T00:00:00.123455+00:00' }] },
    ],
    ['duplicate row ID', { rows: [row(), row()] }],
    ['too many recent rows', { rows: Array.from({ length: 51 }, row) }],
  ])('rejects malformed lookup: %s without registering its receipt', async (_name, change) => {
    const d = db()
    d.rpc.mockResolvedValueOnce({ data: { ...lookup(), ...change }, error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toEqual([])
    expect(d.from).not.toHaveBeenCalled()
  })

  it('keeps exact cutoff/window boundaries, nullable rows and lookup-specific limit', async () => {
    const d = db()
    const rows = [
      {
        ...row(),
        created_at: asOf,
        food_db_id: null,
        food_db: null,
        quantity_g: null,
        kcal: null,
        protein_g: null,
        carbs_g: null,
        fat_g: null,
      },
      { ...row(), id: receiptId, created_at: '2026-10-05T00:00:00.123456+00:00' },
    ]
    d.rpc
      .mockResolvedValueOnce({ data: lookup(rows), error: null })
      .mockResolvedValueOnce({ data: lookup(Array.from({ length: 21 }, row)), error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    expect(await source.sourceReader.read('exact_median', 'arroz')).toEqual(rows)
    await expect(source.sourceReader.read('exact_median', 'other')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toHaveLength(1)
  })

  it('rejects out-of-order history and reuse of one receipt for different lookups', async () => {
    const d = db()
    d.rpc
      .mockResolvedValueOnce({ data: lookup(), error: null })
      .mockResolvedValueOnce({ data: lookup(), error: null })
      .mockResolvedValueOnce({
        data: lookup([
          { ...row(), created_at: '2026-11-02T10:00:00Z' },
          { ...row(), id: receiptId },
        ]),
        error: null,
      })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    await source.sourceReader.read('trusted_recent', null)
    await expect(source.sourceReader.read('exact_median', 'arroz')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    await expect(source.sourceReader.read('exact_median', 'feijao')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(source.sourceReceipts()).toHaveLength(1)
  })

  it.each([
    ['owner', { owner_id: candidateId }],
    ['command', { command_id: candidateOwner }],
    ['hash', { input_hash: 'b'.repeat(64) }],
    ['epoch', { epoch: 'invalid' }],
    ['original input', { source_input: { ...candidateCommand().command, meal_type: 'jantar' } }],
    ['unknown context field', { extra: 'private-sentinel' }],
    ['duplicate evidence units', { source_units: ['command_text', 'command_text'] }],
    ['wrong evidence unit', { source_units: ['vision_items'] }],
    ['non-JSON clinical number', { clinical: { target: Number.POSITIVE_INFINITY } }],
    [
      'JSON field silently removed by decoder',
      { clinical: JSON.parse('{"__proto__":{"x":1},"status":"stable"}') },
    ],
  ])('rejects invalid capture context: %s', async (_name, change) => {
    const d = db(),
      raw = capture()
    d.rpc
      .mockReset()
      .mockResolvedValue({ data: { ...raw, context: { ...raw.context, ...change } }, error: null })
    await expect(
      createSupabaseConversationMealSourceFactory(d.client).capture(candidateCommand()),
    ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
  })

  it('accepts capture replay but rejects malformed cutoff, envelope and invalid lookup before RPC', async () => {
    const d = db()
    d.rpc
      .mockReset()
      .mockResolvedValueOnce({ data: { ...capture(), action: 'replay' }, error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    expect(source.action).toBe('replay')
    await expect(source.sourceReader.read('trusted_recent', 'arroz')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    await expect(source.sourceReader.read('exact_median', ' \uFEFF')).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
    for (const raw of [
      { ...capture(), captured_at: '2026-02-30T00:00:00Z' },
      { ...capture(), extra: true },
      { action: 'stale_epoch', extra: 'private-sentinel' },
    ]) {
      d.rpc.mockResolvedValueOnce({ data: raw, error: null })
      await expect(
        createSupabaseConversationMealSourceFactory(d.client).capture(candidateCommand()),
      ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
    }
  })

  it('redacts thrown transport failures on reads without a history fallback', async () => {
    const d = db()
    d.rpc.mockRejectedValueOnce(new Error('private-sentinel-token'))
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      code: 'conversation_meal_source_unavailable',
    })
    expect(d.from).not.toHaveBeenCalled()
  })

  it.each([
    'absent',
    'stale_epoch',
    'day_closed',
  ])('shapes capture refusal %s without private error details', async (action) => {
    const d = db()
    d.rpc.mockReset().mockResolvedValue({ data: { action }, error: null })
    await expect(
      createSupabaseConversationMealSourceFactory(d.client).capture(candidateCommand()),
    ).rejects.toMatchObject({ status: 409, code: `conversation_meal_source_${action}` })
  })
  it.each([
    'absent',
    'stale_epoch',
    'source_required',
    'source_conflict',
    'sealed',
  ])('shapes lookup refusal %s without fallback', async (action) => {
    const d = db()
    d.rpc.mockResolvedValueOnce({ data: { action }, error: null })
    const source = await createSupabaseConversationMealSourceFactory(d.client).capture(
      candidateCommand(),
    )
    await expect(source.sourceReader.read('trusted_recent', null)).rejects.toMatchObject({
      status: 409,
      code: `conversation_meal_source_${action}`,
    })
    expect(source.sourceReceipts()).toEqual([])
    expect(d.from).not.toHaveBeenCalled()
  })
  it.each(['55P03', '40001', 'XX000'])('redacts SQL failure %s', async (code) => {
    const d = db()
    d.rpc.mockReset().mockResolvedValue({
      data: null,
      error: { code, message: 'private-sentinel', details: 'signed-url-token' },
    })
    try {
      await createSupabaseConversationMealSourceFactory(d.client).capture(candidateCommand())
      throw new Error('expected refusal')
    } catch (error) {
      expect(error).toMatchObject({
        status: code === '40001' ? 409 : 503,
        code:
          code === '55P03'
            ? 'conversation_meal_source_busy'
            : code === '40001'
              ? 'conversation_meal_source_conflict'
              : 'conversation_meal_source_unavailable',
      })
      expect(String(error)).not.toContain('private-sentinel')
      expect(JSON.stringify(error)).not.toContain('signed-url-token')
    }
  })
})
