import { calcMealMacros } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  writerBinding,
  writerCommand,
  writerReceipt,
  writerResolved,
  writerSource,
} from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import { buildConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { createOpenRouterConversationMealInterpreter } from './conversation-meal-interpreter'
import { materializeConversationMealInterpretation } from './conversation-meal-materialization'
import { registerPersistedConversationMeal } from './conversation-meal-registration-service'
import { MobileApiError } from './http'

const id = '10000000-0000-4000-8000-000000000010'
function interpretation() {
  const c = writerCommand()
  return {
    schema: 'conversation.meal-interpretation.v1',
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: c.ownerId,
    command_id: c.commandId,
    attempt_id: id,
    input_hash: c.inputHash,
    source_hash: writerSource().sourceHash,
    source_units: ['command_text'],
    decision: 'reported_meal',
    reason: 'explicit_report',
    sources: [
      {
        unit: 'command_text',
        classification: 'reported',
        visual_indexes: [],
        spans: [
          { start: 0, end: 4, kind: 'report', food_index: null },
          { start: 4, end: 5, kind: 'separator', food_index: null },
          { start: 5, end: 10, kind: 'food', food_index: 0 },
          { start: 10, end: 11, kind: 'separator', food_index: null },
          { start: 11, end: 14, kind: 'quantity', food_index: 0 },
          { start: 14, end: 15, kind: 'separator', food_index: null },
          { start: 15, end: 16, kind: 'unit', food_index: 0 },
        ],
      },
    ],
    foods: [
      {
        index: 0,
        name: { unit: 'command_text', start: 5, end: 10 },
        quantity: { unit: 'command_text', start: 11, end: 14 },
        unit: { unit: 'command_text', start: 15, end: 16 },
        visual_index: null,
      },
    ],
    provider_metadata: {
      model: 'synthetic',
      prompt_tokens: 10,
      completion_tokens: 20,
      cost_usd: null,
      latency_ms: 10,
    },
  }
}
function material() {
  const c = writerCommand(),
    food = interpretation().foods[0]
  if (!food) throw new Error('fixture food absent')
  return {
    status: 'materialized',
    schema: 'conversation.meal-materialization.v1',
    input_hash: c.inputHash,
    source_hash: writerSource().sourceHash,
    attempt_id: id,
    inputs: [
      {
        input_index: 0,
        calculation_input: { food_name: 'arroz', quantity_g: 100 },
        source_group_index: 0,
        candidate: {
          candidate_id: 'c1-rice',
          name: 'arroz',
          quantity_g: 100,
          quantity_basis: 'stated',
          count: null,
          unit_label: null,
          confidence: null,
          needs_review: false,
          review_reason: null,
        },
      },
    ],
    source_groups: [
      {
        group_index: 0,
        interpretation_food_indexes: [0],
        input_indexes: [0],
        rule: 'literal',
        source_positions: [
          {
            food_index: 0,
            unit: 'command_text',
            name: food.name,
            quantity: food.quantity,
            unit_ref: food.unit,
            visual_index: null,
          },
        ],
      },
    ],
    nutrition_label: null,
  }
}
function calculation() {
  return {
    items: [
      {
        food_name: 'Arroz branco cozido',
        matched_taco_name: 'Arroz branco cozido',
        matched_taco_id: 1,
        quantity_g: 100,
        kcal: 128,
        protein_g: 2.5,
        carbs_g: 28.1,
        fat_g: 0.2,
        fiber_g: 1,
        similarity: 1,
        source: 'canonical_exact',
      },
    ],
    totals: { kcal: 128, protein_g: 2.5, carbs_g: 28.1, fat_g: 0.2, fiber_g: 1 },
    warnings: [],
    user_warnings: [],
    audit_warnings: [],
    preparation_annotations: [],
  }
}
function dependencies() {
  const source = {
    ...writerSource(),
    action: 'captured',
    sourceReader: {
      ownerId: writerCommand().ownerId,
      asOf: writerSource().capturedAt,
      read: vi.fn(async () => []),
    },
    auditSink: vi.fn(async () => {}),
    sourceReceipts: vi.fn((): { id: string; hash: string }[] => []),
    auditEvents: vi.fn(() => []),
  }
  return {
    source,
    writer: {
      readPrepared: vi.fn().mockResolvedValue({ action: 'absent' }),
      readEffect: vi.fn().mockResolvedValue({ action: 'absent' }),
      prepare: vi.fn().mockResolvedValue({ action: 'prepared', resolvedHash: 'c'.repeat(64) }),
      commit: vi.fn().mockResolvedValue({ action: 'committed', receipt: writerReceipt() }),
    },
    journal: {
      read: vi.fn().mockResolvedValue({ action: 'absent' }),
      admit: vi.fn().mockResolvedValue({ action: 'admitted', binding: writerBinding() }),
      attach: vi.fn(() => {
        throw new Error('old candidate writer forbidden')
      }),
    },
    initializeDay: vi.fn(async () => {}),
    sources: { capture: vi.fn().mockResolvedValue(source) },
    interpreter: {
      interpret: vi.fn(() => {
        throw new Error('legacy/second provider forbidden')
      }),
    },
    interpret: vi.fn().mockResolvedValue(interpretation()),
    materialize: vi.fn().mockResolvedValue(material()),
    calculate: vi.fn().mockResolvedValue(calculation()),
    confidenceThreshold: vi.fn(async () => 0.6),
    feedback: {
      ensureOriginal: vi.fn().mockResolvedValue(null),
      readOriginal: vi.fn().mockResolvedValue(null),
    },
  }
}
const db = {} as ServiceClient
const run = (d: ReturnType<typeof dependencies>, raw: unknown = writerCommand().command) =>
  registerPersistedConversationMeal(db, candidateAuth, `cmsg1:${writerCommand().commandId}`, raw, d)
function stored(receipt: unknown = null, resolved: unknown = null) {
  return {
    action: 'available',
    binding: writerBinding(),
    source: writerSource(),
    resolved,
    receipt,
  }
}

describe('actual source-to-factual meal registration composition', () => {
  it('prepares two source-bound ingredients through real materialization and calculation for the original breakfast report', async () => {
    const d = dependencies(),
      original = writerCommand(),
      command = bindConversationCommand(original.ownerId, `cmsg1:${original.commandId}`, {
        command_protocol: 'conversation.command.v1',
        command_id: original.commandId,
        kind: 'meal.report',
        source: {
          channel: 'text',
          text: 'No café da manhã, consumi 200 mL de leite com 1 medida de whey.',
        },
      }),
      capture = {
        ...d.source,
        context: {
          ...d.source.context,
          input_hash: command.inputHash,
          source_input: command.command,
        },
      },
      source = buildConversationMealInterpretationSource(command, capture),
      wire = {
        schema: 'conversation.meal-source-labels.v1',
        decision: 'reported_meal',
        reason: 'explicit_report',
        sources: {
          command_text: {
            classification: 'reported',
            labels: {
              t0: { kind: 'report', food_index: null },
              t1: { kind: 'report', food_index: null },
              t2: { kind: 'report', food_index: null },
              t3: { kind: 'report', food_index: null },
              t4: { kind: 'report', food_index: null },
              t5: { kind: 'report', food_index: null },
              t6: { kind: 'quantity', food_index: 0 },
              t7: { kind: 'unit', food_index: 0 },
              t8: { kind: 'separator', food_index: null },
              t9: { kind: 'food', food_index: 0 },
              t10: { kind: 'food', food_index: 0 },
              t11: { kind: 'food', food_index: 0 },
              t12: { kind: 'food', food_index: 0 },
              t13: { kind: 'food', food_index: 0 },
              t14: { kind: 'food', food_index: 0 },
              t15: { kind: 'separator', food_index: null },
            },
          },
        },
        foods: [{ index: 0, visual_index: null }],
      },
      complete = vi.fn(async () => ({
        content: JSON.stringify(wire),
        toolCalls: [],
        model: 'anthropic/claude-haiku-4.5',
        promptTokens: 100,
        completionTokens: 100,
        totalTokens: 200,
        costUsd: null,
        latencyMs: 100,
        finishReason: 'stop' as const,
      })),
      semantic = await createOpenRouterConversationMealInterpreter('synthetic', {
        complete,
      }).interpret(source, { attemptId: id, remainingMs: 5000 })
    expect(complete).toHaveBeenCalledTimes(1)
    d.interpret.mockResolvedValue(semantic)
    d.sources.capture.mockResolvedValue(capture)
    d.journal.admit.mockResolvedValue({
      action: 'admitted',
      binding: { ...writerBinding(), input_hash: command.inputHash },
    })
    d.writer.commit.mockResolvedValue({
      action: 'committed',
      receipt: {
        ...writerReceipt(),
        input_hash: command.inputHash,
        meal_type: 'cafe',
        log_ids: ['10000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000006'],
      },
    })
    // Only external reads/writes are doubled. Materializer, calculator, canonical
    // validation, binding and resolved payload construction are the real functions.
    const read = Promise.resolve({ data: [], error: null })
    Object.assign(read, {
      select: () => read,
      eq: () => read,
      or: () => read,
      neq: () => read,
      gte: () => read,
      order: () => read,
      limit: () => read,
    })
    const catalogs = [
      {
        id: 91,
        name_pt: 'Milk, whole, 3.25% milkfat, with added vitamin D',
        kcal_per_100g: 61,
        protein_g: 3.15,
        carbs_g: 4.8,
        fat_g: 3.25,
        fiber_g: 0,
        country_code: 'BR',
      },
      {
        id: 92,
        name_pt: 'Beverages, Protein powder whey based',
        kcal_per_100g: 352,
        protein_g: 78.13,
        carbs_g: 6.25,
        fat_g: 1.56,
        fiber_g: 0,
        country_code: 'BR',
      },
    ]
    const client = {
        from: vi.fn((table: string) => {
          if (table !== 'user_food_corrections') throw new Error('Unexpected table')
          return read
        }),
        rpc: vi.fn(async (_name: string, params: { search_term: string }) => ({
          data: catalogs.filter((row) => row.name_pt.toLowerCase() === params.search_term),
          error: null,
        })),
      } as unknown as ServiceClient,
      materialize = vi.fn(materializeConversationMealInterpretation),
      calculate = vi.fn(calcMealMacros)
    const result = await registerPersistedConversationMeal(
      client,
      candidateAuth,
      `cmsg1:${command.commandId}`,
      command.command,
      { ...d, materialize, calculate },
    )
    expect(result.status).toBe('saved')
    expect(materialize).toHaveBeenCalledTimes(1)
    expect(calculate.mock.calls[0]?.[1]).toEqual([
      { food_name: 'leite integral', quantity_g: 206 },
      { food_name: 'whey', quantity_g: 30 },
    ])
    expect(d.writer.prepare).toHaveBeenCalledTimes(1)
    const [payload] = d.writer.prepare.mock.calls[0] as unknown as [
      {
        resolved: { semantic_proof: { input_count: number }; items: unknown[]; meal_type: string }
      },
    ]
    expect(payload.resolved).toMatchObject({
      meal_type: 'cafe',
      semantic_proof: { input_count: 2 },
      items: [
        {
          name: 'leite integral',
          food_db_id: 91,
          nutrition_source: 'canonical_fuzzy',
          kcal: 125.7,
          protein_g: 6.49,
          quantity_g: 206,
          input_indexes: [0],
          quantity_basis: 'portion_reference',
          display_qty: 200,
          display_unit: 'mL',
        },
        {
          name: 'whey protein em pó',
          food_db_id: 92,
          nutrition_source: 'canonical_fuzzy',
          kcal: 105.6,
          protein_g: 23.44,
          quantity_g: 30,
          input_indexes: [1],
          quantity_basis: 'portion_reference',
          display_qty: 1,
          display_unit: 'scoop',
        },
      ],
    })
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it('passes the actual held binding to server-selected enrichment only after committed facts', async () => {
    const d = dependencies(),
      ensureOriginal = vi.fn().mockResolvedValue(null),
      readOriginal = vi.fn()
    const result = await registerPersistedConversationMeal(
      db,
      candidateAuth,
      `cmsg1:${writerCommand().commandId}`,
      writerCommand().command,
      { ...d, originalEnrichment: { ensureOriginal, readOriginal } },
    )
    expect(result.status).toBe('saved')
    expect(ensureOriginal).toHaveBeenCalledWith({
      auth: candidateAuth,
      command: writerCommand(),
      receipt: writerReceipt(),
      serverBinding: writerBinding(),
    })
    expect(ensureOriginal.mock.invocationCallOrder[0]).toBeGreaterThan(
      d.writer.commit.mock.invocationCallOrder[0],
    )
    expect(d.feedback.ensureOriginal).not.toHaveBeenCalled()
    expect(d.feedback.readOriginal).not.toHaveBeenCalled()
    expect(readOriginal).not.toHaveBeenCalled()
  })
  it.each([
    'prepared',
    'lost',
  ] as const)('keeps selected canonical enrichment readonly for %s effect recovery', async (mode) => {
    const d = dependencies(),
      ensureOriginal = vi.fn(),
      readOriginal = vi.fn().mockResolvedValue(null)
    if (mode === 'prepared')
      d.writer.readPrepared.mockResolvedValue(
        stored(writerReceipt(), {
          resolvedHash: 'c'.repeat(64),
          value: writerResolved(),
          preparedAt: writerSource().capturedAt,
        }),
      )
    else {
      d.writer.commit.mockRejectedValue(new Error('lost'))
      d.writer.readEffect.mockResolvedValue({ action: 'available', receipt: writerReceipt() })
    }
    const result = await registerPersistedConversationMeal(
      db,
      candidateAuth,
      `cmsg1:${writerCommand().commandId}`,
      writerCommand().command,
      { ...d, originalEnrichment: { ensureOriginal, readOriginal } },
    )
    expect(result.status).toBe('saved')
    expect(readOriginal).toHaveBeenCalledTimes(1)
    expect(ensureOriginal).not.toHaveBeenCalled()
    expect(d.feedback.ensureOriginal).not.toHaveBeenCalled()
  })
  it('does not reconcile or process after a known admission quota refusal', async () => {
    const d = dependencies()
    d.journal.admit.mockRejectedValue(
      new MobileApiError(429, 'conversation_admission_rate_limited', 'Wait'),
    )
    await expect(run(d)).rejects.toMatchObject({
      status: 429,
      code: 'conversation_admission_rate_limited',
    })
    expect(d.journal.admit).toHaveBeenCalledTimes(1)
    for (const call of [
      d.journal.read,
      d.initializeDay,
      d.sources.capture,
      d.interpret,
      d.writer.prepare,
      d.writer.commit,
    ])
      expect(call).not.toHaveBeenCalled()
  })

  it('positively preserves explicitly selected breakfast despite a noon server source', async () => {
    const d = dependencies(),
      raw = { ...writerCommand().command, meal_type: 'cafe' as const }
    const bound = bindConversationCommand(
      writerCommand().ownerId,
      `cmsg1:${writerCommand().commandId}`,
      raw,
    )
    Object.assign(d.source.context, { input_hash: bound.inputHash, source_input: raw })
    d.journal.admit.mockResolvedValue({
      action: 'admitted',
      binding: { ...writerBinding(), input_hash: bound.inputHash },
    })
    d.interpret.mockResolvedValue({ ...interpretation(), input_hash: bound.inputHash })
    d.materialize.mockResolvedValue({ ...material(), input_hash: bound.inputHash })
    d.writer.commit.mockResolvedValue({
      action: 'committed',
      receipt: { ...writerReceipt(), input_hash: bound.inputHash, meal_type: 'cafe' },
    })
    expect(await run(d, raw)).toMatchObject({ status: 'saved', receipt: { meal_type: 'cafe' } })
    expect(d.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({ resolved: expect.objectContaining({ meal_type: 'cafe' }) }),
    )
  })
  it('does not silently invent a meal slot when both selection and explicit type are absent', async () => {
    const d = dependencies(),
      { meal_type: omitted, ...raw } = writerCommand().command
    expect(omitted).toBe('almoco')
    const bound = bindConversationCommand(
      writerCommand().ownerId,
      `cmsg1:${writerCommand().commandId}`,
      raw,
    )
    Object.assign(d.source.context, { input_hash: bound.inputHash, source_input: raw })
    d.journal.admit.mockResolvedValue({
      action: 'admitted',
      binding: { ...writerBinding(), input_hash: bound.inputHash },
    })
    d.interpret.mockResolvedValue({ ...interpretation(), input_hash: bound.inputHash })
    d.materialize.mockResolvedValue({ ...material(), input_hash: bound.inputHash })
    expect(await run(d, raw)).toMatchObject({
      status: 'not_recorded',
      reason: 'meal_type_required',
    })
    expect(d.writer.prepare).not.toHaveBeenCalled()
  })
  it('does not retry a recovered winner commit when its receipt read also becomes unavailable', async () => {
    const d = dependencies()
    d.writer.prepare.mockRejectedValue(new Error('lost prepare'))
    d.writer.readPrepared.mockResolvedValueOnce({ action: 'absent' }).mockResolvedValueOnce(
      stored(null, {
        resolvedHash: 'c'.repeat(64),
        preparedAt: writerSource().capturedAt,
        value: writerResolved(),
      }),
    )
    d.writer.commit.mockRejectedValue(new Error('lost commit'))
    d.writer.readEffect.mockRejectedValue(new Error('unavailable read'))
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.writer.prepare).toHaveBeenCalledTimes(1)
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
    expect(d.writer.readPrepared).toHaveBeenCalledTimes(2)
    expect(d.writer.readEffect).toHaveBeenCalledTimes(1)
  })
  it('does not claim all occurrences were covered when materialization dropped one', async () => {
    const d = dependencies(),
      m = material()
    m.source_groups[0]!.interpretation_food_indexes = []
    d.materialize.mockResolvedValue(m)
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.calculate).not.toHaveBeenCalled()
  })
  it('never rounds physical fact items early to match a presentation total', async () => {
    const d = dependencies(),
      c = calculation()
    Object.assign(c.items[0]!, { kcal: 128.04 })
    c.totals.kcal = 128
    d.calculate.mockResolvedValue(c)
    await run(d)
    expect(d.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({
        resolved: expect.objectContaining({
          items: [expect.objectContaining({ kcal: 128.04 })],
          totals: expect.objectContaining({ kcal: 128 }),
        }),
      }),
    )
  })
  it('returns an already committed original before daily, source, interpretation or calculation', async () => {
    const d = dependencies()
    d.writer.readPrepared.mockResolvedValue(
      stored(writerReceipt(), {
        resolvedHash: 'c'.repeat(64),
        preparedAt: writerSource().capturedAt,
        value: writerResolved(),
      }),
    )
    expect(await run(d)).toMatchObject({
      status: 'saved',
      receipt: writerReceipt(),
      historicalFeedback: null,
    })
    for (const callback of [
      d.initializeDay,
      d.sources.capture,
      d.interpret,
      d.materialize,
      d.calculate,
      d.writer.prepare,
      d.writer.commit,
      d.feedback.ensureOriginal,
    ])
      expect(callback).not.toHaveBeenCalled()
    expect(d.feedback.readOriginal).toHaveBeenCalledTimes(1)
  })
  it('resumes a sealed preparation without any new provider, source or nutrition read', async () => {
    const d = dependencies()
    d.writer.readPrepared.mockResolvedValue(
      stored(null, {
        resolvedHash: 'c'.repeat(64),
        preparedAt: writerSource().capturedAt,
        value: writerResolved(),
      }),
    )
    expect(await run(d)).toMatchObject({ status: 'saved' })
    expect(d.writer.commit).toHaveBeenCalledWith({
      command: writerCommand(),
      resolvedHash: 'c'.repeat(64),
    })
    for (const callback of [
      d.initializeDay,
      d.sources.capture,
      d.interpret,
      d.materialize,
      d.calculate,
      d.writer.prepare,
    ])
      expect(callback).not.toHaveBeenCalled()
  })
  it('uses actual opt-in calculation ports and saves only after complete source/materialization', async () => {
    const d = dependencies()
    expect(await run(d)).toMatchObject({ status: 'saved', receipt: writerReceipt() })
    expect(d.journal.admit).toHaveBeenCalledWith(writerCommand())
    expect(d.initializeDay).toHaveBeenCalledTimes(1)
    expect(d.calculate).toHaveBeenCalledWith(
      db,
      [{ food_name: 'arroz', quantity_g: 100 }],
      'BR',
      writerCommand().ownerId,
      expect.objectContaining({
        consumptionPolicy: 'consumed-meal-v1',
        preparationAnnotations: 'consumed.preparation.v1',
        sourceReader: expect.objectContaining({ ownerId: writerCommand().ownerId }),
        auditSink: expect.any(Function),
      }),
    )
    expect(d.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({
        command: writerCommand(),
        resolved: expect.objectContaining({
          meal_type: 'almoco',
          semantic_proof: expect.objectContaining({ complete_source: true, input_count: 1 }),
          source_receipts: [],
        }),
      }),
    )
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
    expect(d.feedback.ensureOriginal).toHaveBeenCalledTimes(1)
    expect(d.journal.attach).not.toHaveBeenCalled()
  })
  it('never changes the explicitly selected breakfast to the meal inferred from the clock', async () => {
    const d = dependencies(),
      command = structuredClone(writerCommand().command)
    Object.assign(command, { meal_type: 'cafe' })
    // Changed content cannot use the old stored source/hash. Refuse rather
    // than silently selecting the noon slot from the unbound fixture.
    await expect(run(d, command)).rejects.toMatchObject({ status: 503 })
    expect(d.writer.commit).not.toHaveBeenCalled()
  })
  it('does not initialize or replace a source that was captured earlier', async () => {
    const d = dependencies()
    d.writer.readPrepared.mockResolvedValue(stored())
    expect(await run(d)).toMatchObject({ status: 'saved' })
    expect(d.initializeDay).not.toHaveBeenCalled()
  })
  it.each([
    'not_reported',
    'clarification_required',
  ])('does not write when interpretation is %s', async (decision) => {
    const d = dependencies()
    d.interpret.mockResolvedValue({ ...interpretation(), decision, reason: 'ambiguous', foods: [] })
    expect(await run(d)).toMatchObject({ status: 'not_recorded' })
    expect(d.materialize).not.toHaveBeenCalled()
    expect(d.calculate).not.toHaveBeenCalled()
    expect(d.writer.prepare).not.toHaveBeenCalled()
  })
  it('keeps indispensable missing quantity as clarification and preserves the original command', async () => {
    const d = dependencies()
    d.materialize.mockResolvedValue({
      status: 'clarification_required',
      reason: 'missing_quantity',
      food_indexes: [0],
    })
    expect(await run(d)).toMatchObject({
      status: 'not_recorded',
      reason: 'missing_quantity',
      foodIndexes: [0],
      command: writerCommand(),
    })
    expect(d.calculate).not.toHaveBeenCalled()
    expect(d.writer.commit).not.toHaveBeenCalled()
  })
  it('never saves unknown nutrition as zero', async () => {
    const d = dependencies(),
      c = calculation()
    Object.assign(c.items[0] ?? {}, {
      source: 'no_match',
      kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    })
    d.calculate.mockResolvedValue(c)
    expect(await run(d)).toMatchObject({ status: 'not_recorded', reason: 'nutrition_unresolved' })
    expect(d.writer.prepare).not.toHaveBeenCalled()
  })
  it('includes every captured nutrition receipt, including a MISS', async () => {
    const d = dependencies(),
      receipts = [{ id: '10000000-0000-4000-8000-000000000020', hash: 'd'.repeat(64) }]
    d.source.sourceReceipts.mockReturnValue(receipts)
    await run(d)
    expect(d.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({ resolved: expect.objectContaining({ source_receipts: receipts }) }),
    )
  })
  it('lost prepare response only reads the actual sealed winner, then commits its hash once', async () => {
    const d = dependencies()
    d.writer.prepare.mockRejectedValue(new Error('lost prepare'))
    d.writer.readPrepared.mockResolvedValueOnce({ action: 'absent' }).mockResolvedValueOnce(
      stored(null, {
        resolvedHash: 'c'.repeat(64),
        preparedAt: writerSource().capturedAt,
        value: writerResolved(),
      }),
    )
    expect(await run(d)).toMatchObject({ status: 'saved' })
    expect(d.writer.prepare).toHaveBeenCalledTimes(1)
    expect(d.calculate).toHaveBeenCalledTimes(1)
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
  })
  it('lost commit response recovers an immutable receipt without another commit or calculation', async () => {
    const d = dependencies()
    d.writer.commit.mockRejectedValue(new Error('lost commit'))
    d.writer.readEffect.mockResolvedValue({ action: 'available', receipt: writerReceipt() })
    expect(await run(d)).toMatchObject({ status: 'saved', receipt: writerReceipt() })
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
    expect(d.writer.readEffect).toHaveBeenCalledTimes(1)
    expect(d.calculate).toHaveBeenCalledTimes(1)
  })
  it('an uncertain commit does not invent success or a new command', async () => {
    const d = dependencies()
    d.writer.commit.mockRejectedValue(new Error('uncertain'))
    await expect(run(d)).rejects.toMatchObject({
      code: 'conversation_meal_registration_reconciliation_required',
    })
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
  })
  it.each([
    'source_conflict',
    'day_closed',
    'stale_epoch',
  ])('refuses %s with no second writer', async (action) => {
    const d = dependencies()
    d.writer.prepare.mockResolvedValue({ action })
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.writer.commit).not.toHaveBeenCalled()
  })
  it('optional feedback failure cannot invalidate a successfully saved factual effect', async () => {
    const d = dependencies()
    d.feedback.ensureOriginal.mockRejectedValue(new Error('private feedback unavailable'))
    expect(await run(d)).toMatchObject({ status: 'saved', historicalFeedback: null })
    expect(d.writer.commit).toHaveBeenCalledTimes(1)
  })
  it('rejects a foreign source before interpretation or writing', async () => {
    const d = dependencies()
    d.sources.capture.mockResolvedValue({
      ...d.source,
      epoch: '10000000-0000-4000-8000-000000000099',
    })
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.interpret).not.toHaveBeenCalled()
    expect(d.writer.commit).not.toHaveBeenCalled()
  })
  it('rejects a foreign or dropped interpretation occurrence before calculation', async () => {
    const d = dependencies()
    d.materialize.mockResolvedValue({
      ...material(),
      attempt_id: '10000000-0000-4000-8000-000000000099',
    })
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.calculate).not.toHaveBeenCalled()
  })
  it('saves no effect after a history reader failure', async () => {
    const d = dependencies()
    d.calculate.mockRejectedValue(new Error('source reader unavailable'))
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.writer.prepare).not.toHaveBeenCalled()
  })
  it('detaches callbacks and command before the first read awaits', async () => {
    const d = dependencies()
    let release!: () => void
    d.writer.readPrepared.mockImplementationOnce(async () => {
      await new Promise<void>((resolve) => {
        release = resolve
      })
      return { action: 'absent' }
    })
    const original = d.calculate,
      raw = structuredClone(writerCommand().command),
      promise = run(d, raw)
    d.calculate = vi.fn().mockRejectedValue(new Error('mutated callback'))
    Object.assign(raw, { source: { channel: 'text', text: 'changed' } })
    release()
    expect(await promise).toMatchObject({ status: 'saved' })
    expect(original).toHaveBeenCalledTimes(1)
    expect(d.calculate).not.toHaveBeenCalled()
  })
})
