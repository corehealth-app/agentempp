import { calcMealMacros, consumedFoodDefault } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import actual from './__fixtures__/conversation-meal-continuation-read-sql.json'
import type { MobileAuthContext } from './auth'
import { bindConversationMealReply } from './conversation-meal-continuation-input'
import { parseConversationMealContinuationRead } from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealContinuationScope,
  createConversationMealContinuationService,
} from './conversation-meal-continuation-service'
import { createSupabaseConversationMealContinuationSourceFactory } from './conversation-meal-continuation-source'
import { materializeStoredConversationMealContinuation } from './conversation-meal-materialization'

function fixture(key: keyof typeof actual.samples = 'admitted_meal_type_reply') {
  const state = structuredClone(
    actual.samples[key],
  ) as typeof actual.samples.admitted_meal_type_reply
  const identity = {
    ownerId: state.parent.binding.owner_id,
    parentCommandId: state.parent.binding.command_id,
    parentInputHash: state.parent.binding.input_hash,
    epoch: state.parent.binding.epoch,
    replyId: state.reply.binding.command_id,
    replyInputHash: state.reply.binding.input_hash,
  }
  const bound = bindConversationMealReply({
    binding: {
      ownerId: identity.ownerId,
      parentCommandId: identity.parentCommandId,
      parentInputHash: identity.parentInputHash,
      epoch: identity.epoch,
      decisionHash: state.parent.decision.decision_hash,
    },
    replyId: identity.replyId,
    idempotencyKey: `cmreply1:${identity.replyId}`,
    input: state.reply.body,
  })
  const authID = 'c3cc0000-0000-4000-8000-000000000002'
  const auth: MobileAuthContext = {
    accessToken: 'synthetic-never-used',
    authUserId: authID,
    userId: identity.ownerId,
    identity: { id: authID, email: null, emailConfirmedAt: null },
    patient: {
      id: identity.ownerId,
      authUserId: authID,
      email: null,
      name: null,
      locale: 'pt-BR',
      timezone: 'UTC',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  return { state, identity, bound, auth }
}
function setup(key: keyof typeof actual.samples = 'admitted_meal_type_reply') {
  const f = fixture(key)
  let prepared: unknown = null
  const writer = {
    read: vi.fn(async () => f.state),
    admit: vi.fn(async () => ({ status: 'observed' as const, state: f.state })),
    prepare: vi.fn(async (_identity: unknown, prep: unknown) => {
      prepared = structuredClone(prep)
      const next = structuredClone(
        actual.samples[
          Reflect.get(prep as object, 'status') === 'ready' ? 'prepared' : 'awaiting_reply'
        ],
      )
      if (next.reply.preparation)
        Reflect.set(next.reply.preparation, 'preparation', structuredClone(prep))
      return { status: 'observed' as const, state: next }
    }),
    commit: vi.fn(async () => {
      const next = structuredClone(actual.samples.saved)
      if (prepared && next.reply.preparation)
        Reflect.set(next.reply.preparation, 'preparation', structuredClone(prepared))
      return { status: 'observed' as const, state: next }
    }),
  }
  const rpc = vi.fn(async (name: string, args: unknown) => {
    if (name === 'search_food_trgm') {
      const entry = consumedFoodDefault('arroz', 'BR')
      if (!entry) throw new Error('approved rice reference required')
      return {
        data: [
          {
            id: 91,
            name_pt: entry.catalog_name,
            ...entry.per_100g,
            kcal_per_100g: entry.per_100g.kcal,
            country_code: 'BR',
            fiber_g: 0,
          },
        ],
        error: null,
      }
    }
    if (name !== 'read_conversation_meal_continuation_nutrition_source')
      throw new Error('unexpected RPC')
    const exact = Reflect.get(args as object, 'p_kind') === 'exact_median'
    const rows = exact
      ? [
          {
            id: '40000000-0000-4000-8000-000000000003',
            user_id: f.identity.ownerId,
            created_at: f.state.reply.source.captured_at,
            food_name: 'arroz',
            food_db_id: 91,
            quantity_g: 100,
            kcal: 130,
            protein_g: 3,
            carbs_g: 27,
            fat_g: 1,
            source: 'canonical_exact',
            food_db: { is_verified: true },
          },
        ]
      : []
    return {
      data: {
        action: 'captured',
        owner_id: f.identity.ownerId,
        command_id: f.identity.replyId,
        as_of: f.state.reply.source.captured_at,
        source_receipt_id: exact
          ? '40000000-0000-4000-8000-000000000001'
          : '40000000-0000-4000-8000-000000000002',
        source_receipt_hash: 'a'.repeat(64),
        rows,
      },
      error: null,
    }
  })
  const from = vi.fn(() => {
    const query = Promise.resolve({ data: [], error: null })
    return Object.assign(query, {
      select: () => query,
      eq: () => query,
      neq: () => query,
      gte: () => query,
      or: () => query,
      order: () => query,
      limit: () => query,
    })
  })
  const checkCurrentScope = vi.fn(async (_scope: ConversationMealContinuationScope) => true),
    threshold = vi.fn(async () => 0.6)
  const db = { rpc, from } as unknown as ServiceClient
  const create = (extra: Record<string, unknown> = {}) =>
    createConversationMealContinuationService(db, {
      writer,
      checkCurrentScope,
      confidenceThreshold: threshold,
      ...extra,
    } as Parameters<typeof createConversationMealContinuationService>[1])
  return { ...f, writer, rpc, from, db, create, checkCurrentScope, threshold }
}
describe('actual private linked continuation shared-calculation service', () => {
  it('constructs without I/O and requires the actual revocation callback', () => {
    const s = setup()
    s.create()
    expect(s.rpc).not.toHaveBeenCalled()
    expect(s.writer.read).not.toHaveBeenCalled()
    expect(() => createConversationMealContinuationService(s.db, {} as never)).toThrow()
  })
  it('runs the real stored-answer materializer and shared calculator, then prepares and commits once', async () => {
    const s = setup(),
      result = await s.create().submit(s.auth, s.bound)
    expect(result.status).toBe('saved')
    expect(s.writer.admit).not.toHaveBeenCalled()
    expect(s.writer.prepare).toHaveBeenCalledTimes(1)
    expect(s.writer.commit).toHaveBeenCalledTimes(1)
    const prep = s.writer.prepare.mock.calls[0]?.[1] as Record<string, unknown>
    expect(prep).toMatchObject({
      schema: 'conversation.meal-continuation-preparation.v1',
      input_hash: s.identity.replyInputHash,
      source_hash: s.state.reply.source.source_hash,
      status: 'ready',
      meal: { meal_type: 'almoco', items: [{ quantity_g: 100 }] },
    })
    expect(prep).not.toHaveProperty('semantic_proof')
    const meal = prep.meal as {
      items: { kcal: number; nutrition_source: string }[]
      source_receipts: unknown[]
    }
    expect(meal.items[0]?.kcal).toBeGreaterThan(0)
    expect(meal.items[0]?.nutrition_source).not.toBe('user_kcal')
    expect(result).toMatchObject({
      historicalFeedback: null,
      feedbackGate: 'continuation_feedback_v2_unavailable',
    })
    expect(s.checkCurrentScope.mock.calls[0]?.[0]).toMatchObject({
      authUserId: s.auth.authUserId,
      ownerId: s.identity.ownerId,
      epoch: s.identity.epoch,
    })
  })
  it('uses fresh nutrition ports and includes their actual HIT/MISS receipts', async () => {
    const s = setup(),
      calculate = vi.fn<typeof calcMealMacros>(async (db, inputs, country, owner, options) => {
        expect(options?.sourceReader?.asOf).toBe(s.state.reply.source.captured_at)
        await options?.sourceReader?.read('exact_median', 'arroz')
        await options?.sourceReader?.read('trusted_recent', null)
        return calcMealMacros(db, inputs, country, owner, options)
      })
    const result = await s.create({ calculate }).submit(s.auth, s.bound)
    expect(result.status).toBe('saved')
    const prep = s.writer.prepare.mock.calls[0]?.[1] as { meal: { source_receipts: unknown[] } }
    expect(prep.meal.source_receipts).toEqual([
      { id: '40000000-0000-4000-8000-000000000001', hash: 'a'.repeat(64) },
      { id: '40000000-0000-4000-8000-000000000002', hash: 'a'.repeat(64) },
    ])
    expect(
      s.rpc.mock.calls.filter(
        ([name]) => name === 'read_conversation_meal_continuation_nutrition_source',
      ).length,
    ).toBeGreaterThanOrEqual(2)
  })
  it('returns the immutable actual saved effect without recalculation or enrichment', async () => {
    const s = setup('saved'),
      calculate = vi.fn()
    const r = await s.create({ calculate }).submit(s.auth, s.bound)
    expect(r).toMatchObject({ status: 'saved', receipt: s.state.reply.receipt })
    expect(s.writer.commit).not.toHaveBeenCalled()
    expect(s.threshold).not.toHaveBeenCalled()
    expect(calculate).not.toHaveBeenCalled()
  })
  it('commits an existing ready preparation using only its actual opaque hash', async () => {
    const s = setup('prepared'),
      calculate = vi.fn()
    const r = await s.create({ calculate }).submit(s.auth, s.bound)
    expect(r.status).toBe('saved')
    expect(s.writer.commit).toHaveBeenCalledWith(
      s.identity,
      actual.samples.prepared.reply.preparation.prepared_hash,
    )
    expect(s.writer.prepare).not.toHaveBeenCalled()
    expect(calculate).not.toHaveBeenCalled()
    expect(s.threshold).not.toHaveBeenCalled()
  })
  it('asks the real current meal question after quantity resolution, without calculating before target selection', async () => {
    const s = setup('admitted_quantity_reply'),
      calculate = vi.fn()
    const r = await s.create({ calculate }).submit(s.auth, s.bound)
    expect(r).toMatchObject({
      status: 'needs_reply',
      question: actual.samples.awaiting_reply.head.question,
    })
    expect(s.writer.prepare.mock.calls[0]?.[1]).toMatchObject({
      status: 'needs_reply',
      next_need: { kind: 'meal_type', food_index: null },
    })
    expect(calculate).not.toHaveBeenCalled()
    expect(s.writer.commit).not.toHaveBeenCalled()
  })
  it('returns only the current head question, never the historical question after fulfillment', async () => {
    const s = setup('historical_next_question_after_fulfillment')
    const r = await s.create().submit(s.auth, s.bound)
    expect(r).toMatchObject({ status: 'held', reason: 'parent_fulfilled' })
    expect(r).not.toHaveProperty('question')
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('performs one read-only reconciliation with no calculation, admission or commit', async () => {
    const s = setup('saved'),
      r = await s.create().reconcile(s.auth, s.identity)
    expect(r.status).toBe('saved')
    expect(s.writer.read).toHaveBeenCalledTimes(1)
    expect(s.writer.admit).not.toHaveBeenCalled()
    expect(s.writer.prepare).not.toHaveBeenCalled()
    expect(s.writer.commit).not.toHaveBeenCalled()
    expect(s.threshold).not.toHaveBeenCalled()
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it.each([
    'absent',
    'reply_conflict',
  ] as const)('admits once only after definite %s', async (action) => {
    const s = setup()
    s.writer.read.mockResolvedValueOnce({ action } as never)
    expect((await s.create().submit(s.auth, s.bound)).status).toBe('saved')
    expect(s.writer.admit).toHaveBeenCalledTimes(1)
    expect(s.writer.admit).toHaveBeenCalledWith(s.bound)
  })
  it.each([
    'stale_epoch',
    'input_conflict',
    'ineligible',
    'event_conflict',
  ] as const)('does not admit on %s', async (action) => {
    const s = setup()
    s.writer.read.mockResolvedValueOnce({ action } as never)
    expect((await s.create().submit(s.auth, s.bound)).status).toBe('held')
    expect(s.writer.admit).not.toHaveBeenCalled()
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('stops on a failed initial read, without guessing absence', async () => {
    const s = setup()
    s.writer.read.mockRejectedValueOnce(new Error('lost read'))
    expect((await s.create().submit(s.auth, s.bound)).status).toBe('reconciliation_required')
    expect(s.writer.admit).not.toHaveBeenCalled()
  })
  it.each([
    'admit',
    'prepare',
    'commit',
  ] as const)('never retries an uncertain %s or starts another stage', async (stage) => {
    const s = setup()
    if (stage === 'admit') s.writer.read.mockResolvedValueOnce({ action: 'absent' } as never)
    s.writer[stage].mockResolvedValueOnce({
      status: 'reconciliation_required',
      state: null,
      refusal: null,
    } as never)
    const r = await s.create().submit(s.auth, s.bound)
    expect(r.status).toBe('reconciliation_required')
    expect(s.writer[stage]).toHaveBeenCalledTimes(1)
    if (stage !== 'commit') expect(s.writer.commit).not.toHaveBeenCalled()
    if (stage === 'admit') expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('rejects foreign Auth ownership and a damaged bound body before any writer', async () => {
    const s = setup(),
      auth = structuredClone(s.auth)
    auth.userId = auth.patient.id = '40000000-0000-4000-8000-000000000099'
    await expect(s.create().submit(auth, s.bound)).rejects.toThrow()
    const broken = structuredClone(s.bound)
    Reflect.set(broken.input.answer, 'meal_type', 'jantar')
    expect(() => s.create().submit(s.auth, broken)).toThrow()
    expect(s.writer.read).not.toHaveBeenCalled()
  })
  it('does not expose saved data when scope is already revoked', async () => {
    const s = setup('saved')
    s.checkCurrentScope.mockResolvedValue(false)
    const r = await s.create().submit(s.auth, s.bound)
    expect(r).toMatchObject({ status: 'reconciliation_required', reason: 'scope_changed' })
    expect(r).not.toHaveProperty('receipt')
    expect(s.writer.read).not.toHaveBeenCalled()
  })
  it.each([
    'read',
    'prepare',
    'commit',
  ] as const)('checks revocation after awaiting %s before publication or the next writer', async (stage) => {
    const s = setup()
    let current = true
    s.checkCurrentScope.mockImplementation(async () => current)
    const original = s.writer[stage].getMockImplementation()
    s.writer[stage].mockImplementationOnce((async (...args: unknown[]) => {
      const r = await (original as (...v: unknown[]) => Promise<unknown>)(...args)
      current = false
      return r
    }) as never)
    const r = await s.create().submit(s.auth, s.bound)
    expect(r).toMatchObject({ status: 'reconciliation_required', reason: 'scope_changed' })
    expect(r).not.toHaveProperty('receipt')
    if (stage !== 'commit') expect(s.writer.commit).not.toHaveBeenCalled()
  })
  it('pins the scope callback, writer methods, Auth and body before the first await', async () => {
    const s = setup()
    let resume: (() => void) | undefined
    const waiting = new Promise<void>((r) => {
      resume = r
    })
    s.checkCurrentScope.mockImplementationOnce(async () => {
      await waiting
      return true
    })
    const service = s.create(),
      promise = service.submit(s.auth, s.bound)
    s.auth.userId = '40000000-0000-4000-8000-000000000099'
    const replacement = vi.fn(async () => ({ action: 'absent' }))
    Reflect.set(s.writer, 'read', replacement)
    resume?.()
    expect((await promise).status).toBe('saved')
    expect(replacement).not.toHaveBeenCalled()
  })
  it('rejects a cross-bound read before materialization', async () => {
    const s = setup()
    s.writer.read.mockResolvedValueOnce({
      ...s.state,
      parent: {
        ...s.state.parent,
        binding: { ...s.state.parent.binding, owner_id: '40000000-0000-4000-8000-000000000099' },
      },
    } as never)
    expect((await s.create().submit(s.auth, s.bound)).status).toBe('reconciliation_required')
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('holds unresolved nutrition without zero calories, user calories or a preparation write', async () => {
    const s = setup(),
      calculate = vi.fn(async () => ({
        items: [],
        totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
      }))
    expect(await s.create({ calculate }).submit(s.auth, s.bound)).toMatchObject({
      status: 'held',
      reason: 'nutrition_unresolved',
    })
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('uses fully qualified actual-shaped fixtures for every observed controlled state', () => {
    for (const name of [
      'admitted_meal_type_reply',
      'admitted_quantity_reply',
      'prepared',
      'saved',
      'awaiting_reply',
    ] as const) {
      const f = fixture(name)
      expect(parseConversationMealContinuationRead(f.state, f.identity)).toEqual(f.state)
    }
  })
})

describe('continuation effects, source leases and atomic recovery boundaries', () => {
  it('uses the real default writer/read codec and recovers a lost commit response with one POST', async () => {
    const s = setup()
    let state: unknown = s.state,
      prep: unknown = null
    const previous = s.rpc.getMockImplementation()
    s.rpc.mockImplementation(async (name, args) => {
      const envelope = (data: unknown) => ({
        data,
        error: null,
        count: null,
        status: 200,
        statusText: 'OK',
      })
      if (name === 'read_conversation_meal_continuation') return envelope(state) as never
      if (name === 'prepare_conversation_meal_continuation') {
        prep = Reflect.get(args as object, 'p_preparation')
        const next = structuredClone(actual.samples.prepared)
        Reflect.set(next.reply.preparation, 'preparation', structuredClone(prep))
        state = next
        return envelope({ action: 'prepared' }) as never
      }
      if (name === 'commit_conversation_meal_continuation') {
        const next = structuredClone(actual.samples.saved)
        Reflect.set(next.reply.preparation, 'preparation', structuredClone(prep))
        state = next
        throw new Error('lost response after controlled durable commit')
      }
      return await (previous as (n: string, a: unknown) => Promise<never>)(name, args)
    })
    const r = await s.create({ writer: undefined }).submit(s.auth, s.bound)
    expect(r.status).toBe('saved')
    const calls = s.rpc.mock.calls
      .map(([name]) => name)
      .filter((name) => name !== 'search_food_trgm')
    expect(calls).toEqual([
      'read_conversation_meal_continuation',
      'prepare_conversation_meal_continuation',
      'read_conversation_meal_continuation',
      'commit_conversation_meal_continuation',
      'read_conversation_meal_continuation',
    ])
    expect(s.writer.read).not.toHaveBeenCalled()
  })
  it('guards each fresh lookup and stops after revocation before another receipt or writer', async () => {
    const s = setup()
    let active = true
    s.checkCurrentScope.mockImplementation(async () => active)
    const calculate = vi.fn<typeof calcMealMacros>(async (db, inputs, country, owner, options) => {
      await options?.sourceReader?.read('exact_median', 'arroz')
      active = false
      await options?.sourceReader?.read('trusted_recent', null)
      return calcMealMacros(db, inputs, country, owner, options)
    })
    const r = await s.create({ calculate }).submit(s.auth, s.bound)
    expect(r).toMatchObject({ status: 'reconciliation_required', reason: 'scope_changed' })
    expect(
      s.rpc.mock.calls.filter(
        ([name]) => name === 'read_conversation_meal_continuation_nutrition_source',
      ),
    ).toHaveLength(1)
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('pins actual source ports and immutable source clocks before a threshold await', async () => {
    const s = setup(),
      original = createSupabaseConversationMealContinuationSourceFactory(s.db).fromRead(
        s.identity,
        s.state,
      )
    const fresh = {
      ...original.resolutionSource,
      sourceReader: { ...original.resolutionSource.sourceReader },
    }
    const sources = { fromRead: () => ({ ...original, resolutionSource: fresh }) },
      forged = vi.fn()
    const threshold = vi.fn(async () => {
      Reflect.set(fresh.sourceReader, 'read', forged)
      Reflect.set(fresh, 'sourceReceipts', forged)
      return 0.6
    })
    const calculate = vi.fn<typeof calcMealMacros>(async (db, inputs, country, owner, options) => {
      await options?.sourceReader?.read('trusted_recent', null)
      return calcMealMacros(db, inputs, country, owner, options)
    })
    expect(
      (
        await s
          .create({ sources, confidenceThreshold: threshold, calculate })
          .submit(s.auth, s.bound)
      ).status,
    ).toBe('saved')
    expect(forged).not.toHaveBeenCalled()
  })
  it('refuses a substituted fresh authority before threshold, materialization or calculator', async () => {
    const s = setup(),
      original = createSupabaseConversationMealContinuationSourceFactory(s.db).fromRead(
        s.identity,
        s.state,
      )
    const sources = {
      fromRead: () => ({
        ...original,
        resolutionSource: { ...original.resolutionSource, sourceHash: 'f'.repeat(64) },
      }),
    }
    expect((await s.create({ sources }).submit(s.auth, s.bound)).status).toBe(
      'reconciliation_required',
    )
    expect(s.threshold).not.toHaveBeenCalled()
    expect(s.writer.prepare).not.toHaveBeenCalled()
  })
  it('holds a label and an unsupported materialization without using a manual calorie escape', async () => {
    for (const label of [false, true]) {
      const s = setup(),
        materialize = vi.fn<typeof materializeStoredConversationMealContinuation>(
          async (...args) => {
            const value = await materializeStoredConversationMealContinuation(...args)
            if (value.materialization.status !== 'materialized')
              throw new Error('fixture materialized')
            if (!label)
              return {
                ...value,
                materialization: {
                  status: 'clarification_required',
                  reason: 'unsupported_quantity',
                  food_indexes: [0],
                },
              }
            return {
              ...value,
              materialization: {
                ...value.materialization,
                nutrition_label: {
                  product_name: 'test',
                  serving_size_g: null,
                  per_serving: null,
                  per_100g: null,
                  confidence: null,
                  applies_to_candidate_id: null,
                },
              },
            }
          },
        )
      const calculate = vi.fn()
      expect(await s.create({ materialize, calculate }).submit(s.auth, s.bound)).toMatchObject({
        status: 'held',
        reason: label ? 'nutrition_label_confirmation_required' : 'unsupported_quantity',
      })
      expect(calculate).not.toHaveBeenCalled()
      expect(s.writer.prepare).not.toHaveBeenCalled()
    }
  })
  it('refuses a prepared outcome for different input rather than committing its hash', async () => {
    const s = setup()
    s.writer.prepare.mockResolvedValueOnce({
      status: 'observed',
      state: actual.samples.prepared,
    } as never)
    expect((await s.create().submit(s.auth, s.bound)).status).toBe('reconciliation_required')
    expect(s.writer.commit).not.toHaveBeenCalled()
  })
  it('does not expose reconciliation data after an Auth/patient/epoch scope change', async () => {
    const s = setup('saved')
    let active = true
    s.checkCurrentScope.mockImplementation(async () => active)
    s.writer.read.mockImplementationOnce(async () => {
      active = false
      return s.state
    })
    const r = await s.create().reconcile(s.auth, s.identity)
    expect(r).toMatchObject({ status: 'reconciliation_required', reason: 'scope_changed' })
    expect(r).not.toHaveProperty('receipt')
    expect(r).not.toHaveProperty('question')
    expect(s.writer.admit).not.toHaveBeenCalled()
  })
  it('cannot silently renew an epoch after an old stored body was admitted', async () => {
    const s = setup(),
      newer = structuredClone(s.bound)
    Reflect.set(newer.binding, 'epoch', '40000000-0000-4000-8000-000000000099')
    expect((await s.create().submit(s.auth, newer)).status).toBe('reconciliation_required')
    expect(s.writer.prepare).not.toHaveBeenCalled()
    expect(s.writer.admit).not.toHaveBeenCalled()
  })
  it('handles two legitimate concurrent calls with the same operation identity and unchanged body', async () => {
    const s = setup('saved'),
      service = s.create()
    const [a, b] = await Promise.all([
      service.submit(s.auth, s.bound),
      service.submit(s.auth, s.bound),
    ])
    expect(a).toEqual(b)
    expect(a.status).toBe('saved')
    expect(s.writer.commit).not.toHaveBeenCalled()
    expect(s.writer.admit).not.toHaveBeenCalled()
  })
  it('preserves the actual admission quota refusal without calculation or another mutation', async () => {
    const s = setup(),
      read = vi.fn().mockResolvedValue({ action: 'reply_conflict' }),
      admit = vi.fn().mockResolvedValue({
        status: 'reconciliation_required',
        state: { action: 'reply_conflict' },
        refusal: 'rate_limited',
      })
    const result = await s.create({ writer: { ...s.writer, read, admit } }).submit(s.auth, s.bound)
    expect(result).toMatchObject({ status: 'held', reason: 'rate_limited' })
    expect(admit).toHaveBeenCalledTimes(1)
    expect(s.writer.prepare).not.toHaveBeenCalled()
    expect(s.writer.commit).not.toHaveBeenCalled()
  })
})
