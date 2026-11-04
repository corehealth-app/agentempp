import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { isDeepStrictEqual } from 'node:util'
import { resolveDraftItem } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import actualSQL from './__fixtures__/conversation-meal-continuation-read-sql.json'
import { bindConversationCommand } from './conversation-command-contracts'
import type { ConversationMealContinuationReadOutcome } from './conversation-meal-continuation-read-contracts'
import { detachConversationContinuationReadJson } from './conversation-meal-continuation-read-contracts'
import { createSupabaseConversationMealContinuationReadStore } from './conversation-meal-continuation-read-store'
import { mobileQuantityDisplay } from './mobile-quantity-display'

const owner = '10000000-0000-4000-8000-000000000001'
const parent = '10000000-0000-4000-8000-000000000002'
const epoch = '10000000-0000-4000-8000-000000000003'
const attempt = '10000000-0000-4000-8000-000000000004'
const replyId = '10000000-0000-4000-8000-000000000005'
const sourceHash = 'a'.repeat(64),
  resultHash = 'b'.repeat(64),
  decisionHash = 'c'.repeat(64)
function fixture() {
  const command = bindConversationCommand(owner, `cmsg1:${parent}`, {
    command_protocol: 'conversation.command.v1',
    command_id: parent,
    kind: 'meal.report',
    source: { channel: 'text', text: 'arroz' },
    meal_type: 'almoco',
  })
  const binding = {
    owner_id: owner,
    command_id: parent,
    input_hash: command.inputHash,
    command_protocol: 'conversation.command.v1',
    kind: 'meal.report',
    epoch,
    admitted_at: '2026-11-05T01:00:00.000001Z',
  }
  const context = {
    schema: 'conversation.meal-source.v1',
    owner_id: owner,
    command_id: parent,
    input_hash: command.inputHash,
    epoch,
    source_input: command.command,
    source_units: ['command_text'],
    source_evidence: {},
    media: null,
    catalog: { epoch, revision: '1' },
    owner: {
      country: 'BR',
      country_confirmed: true,
      timezone: 'America/Sao_Paulo',
      locale: 'pt-BR',
    },
    clinical: {},
    day: {
      date: '2026-11-04',
      day_closed: false,
      calories_target: null,
      protein_target: null,
      current_protocol: null,
      target_revision: '1',
      calorie_origin: null,
    },
  }
  const model = {
    schema: 'conversation.meal-interpretation.v1',
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: owner,
    command_id: parent,
    input_hash: command.inputHash,
    source_hash: sourceHash,
    attempt_id: attempt,
    source_units: ['command_text'],
    decision: 'reported_meal',
    reason: 'nominal_food_list',
    sources: [
      {
        unit: 'command_text',
        classification: 'nominal_list',
        spans: [{ start: 0, end: 5, kind: 'food', food_index: 0 }],
        visual_indexes: [],
      },
    ],
    foods: [
      {
        index: 0,
        name: { unit: 'command_text', start: 0, end: 5 },
        quantity: null,
        unit: null,
        visual_index: null,
      },
    ],
    provider_metadata: {
      model: 'synthetic',
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: null,
      latency_ms: 0,
    },
  }
  const decision = {
    schema: 'conversation.meal-decision.v1',
    status: 'not_recorded',
    reason: 'missing_quantity',
    food_indexes: [0],
    owner_id: owner,
    command_id: parent,
    epoch,
    input_hash: command.inputHash,
    source_hash: sourceHash,
    attempt_id: attempt,
    semantic_result_hash: resultHash,
    decision_hash: decisionHash,
    sealed_at: '2026-11-05T01:00:03.000003Z',
  }
  return {
    identity: {
      ownerId: owner,
      parentCommandId: parent,
      parentInputHash: command.inputHash,
      epoch,
    },
    value: {
      action: 'available',
      parent: {
        binding,
        source: { source_hash: sourceHash, captured_at: '2026-11-05T01:00:01.000002Z', context },
        semantic: {
          interpreter_version: 'conversation.meal-interpreter.v1',
          attempt_id: attempt,
          result_hash: resultHash,
          result: model,
        },
        decision,
      },
      head: {
        revision: 0,
        question: {
          schema: 'conversation.meal-question.v1',
          question_key: 'd'.repeat(64),
          revision: 0,
          kind: 'quantity',
          food_index: 0,
          food_name: 'arroz',
          allowed_units: ['g', 'kg'],
          quantity_reference: null,
        },
        answers_hash: 'e'.repeat(64),
        answers: [],
        fulfilled_by: null,
      },
      reply: null,
      fulfillment: null,
      observed_at: '2026-11-05T01:00:04.000004Z',
    },
  }
}
function sdk(value: unknown) {
  const rpc = vi.fn(async () => ({
    data: value,
    error: null,
    count: null,
    status: 200,
    statusText: 'OK',
  }))
  const db = { rpc } as unknown as ServiceClient
  return { rpc, db, store: createSupabaseConversationMealContinuationReadStore(db) }
}

describe('one-shot private linked continuation reader', () => {
  it('reads exact initial parent/head once, preserves original literals and supplies no callbacks', async () => {
    const f = fixture(),
      s = sdk(f.value),
      result = await s.store.read(f.identity)
    expect(result).toEqual(f.value)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    expect(s.rpc).toHaveBeenCalledWith('read_conversation_meal_continuation', {
      p_user_id: owner,
      p_parent_command_id: parent,
      p_expected_epoch: epoch,
      p_parent_input_hash: f.identity.parentInputHash,
      p_reply_id: null,
      p_reply_input_hash: null,
    })
    expect(Object.isFrozen(result)).toBe(true)
    if (result.action !== 'available') throw new Error('missing success')
    expect(Object.isFrozen(result.parent.source.context)).toBe(true)
    expect(result.parent.source.captured_at).toBe(f.value.parent.source.captured_at)
    expect(result.parent.source).not.toHaveProperty('sourceReader')
    expect(result.parent.semantic.result).toEqual(f.value.parent.semantic.result)
  })
  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'ineligible',
    'reply_conflict',
    'event_conflict',
  ])('returns only exact read refusal %s', async (action) => {
    const f = fixture(),
      s = sdk({ action })
    expect(await s.store.read(f.identity)).toEqual({ action })
    expect(s.rpc).toHaveBeenCalledTimes(1)
    await expect(sdk({ action, private: 'extra' }).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
  })
  it.each([
    'owner',
    'parent',
    'epoch',
    'hash',
    'source-owner',
    'source-hash',
    'attempt',
    'result-hash',
    'decision-input',
    'question-name',
    'question-revision',
    'head-revision',
    'head-extra',
    'source-extra',
    'model-extra',
    'clock',
  ])('rejects malformed or crossed %s', async (attack) => {
    const f = fixture(),
      v = f.value
    if (attack === 'owner') v.parent.binding.owner_id = replyId
    if (attack === 'parent') v.parent.binding.command_id = replyId
    if (attack === 'epoch') v.parent.binding.epoch = replyId
    if (attack === 'hash') v.parent.binding.input_hash = 'f'.repeat(64)
    if (attack === 'source-owner') v.parent.source.context.owner_id = replyId
    if (attack === 'source-hash') v.parent.source.source_hash = 'f'.repeat(64)
    if (attack === 'attempt') v.parent.semantic.attempt_id = replyId
    if (attack === 'result-hash') v.parent.semantic.result_hash = 'f'.repeat(64)
    if (attack === 'decision-input') v.parent.decision.input_hash = 'f'.repeat(64)
    if (attack === 'question-name') v.head.question.food_name = 'feijão'
    if (attack === 'question-revision') v.head.question.revision = 1
    if (attack === 'head-revision') v.head.revision = 1
    if (attack === 'head-extra') Object.assign(v.head, { owner_id: owner })
    if (attack === 'source-extra') Object.assign(v.parent.source, { epoch })
    if (attack === 'model-extra') Object.assign(v.parent.semantic.result, { secret: 'extra' })
    if (attack === 'clock') v.observed_at = '2026-11-05T01:00:00.000000Z'
    await expect(sdk(v).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
  })
  it.each([
    { replyId },
    { replyInputHash: 'f'.repeat(64) },
    { replyId: null, replyInputHash: 'f'.repeat(64) },
    { ownerId: owner.toUpperCase() },
    { extra: true },
  ])('refuses invalid identity before RPC %#', async (patch) => {
    const f = fixture(),
      s = sdk(f.value)
    // All-zero-numeric UUID needs a letter to exercise uppercase format refusal.
    const identity = { ...f.identity, ...patch }
    if ('ownerId' in patch) identity.ownerId = 'abcdefab-0000-4000-8000-000000000001'.toUpperCase()
    await expect(s.store.read(identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
    expect(s.rpc).not.toHaveBeenCalled()
  })
  it('pins SDK callback and immutable args before awaiting and does not retry outages', async () => {
    const f = fixture()
    let finish: (v: unknown) => void = () => {}
    const rpc = vi.fn(
        (_name: string, _args: Record<string, string | null>) =>
          new Promise((resolve) => {
            finish = resolve
          }),
      ),
      db = { rpc } as unknown as ServiceClient
    const store = createSupabaseConversationMealContinuationReadStore(db),
      replacement = vi.fn()
    Object.assign(db, { rpc: replacement })
    const pending = store.read(f.identity)
    f.identity.ownerId = replyId
    finish({ data: f.value, error: null })
    expect((await pending).action).toBe('available')
    expect(replacement).not.toHaveBeenCalled()
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({ p_user_id: owner })
    const broken = vi.fn(async () => {
      throw new Error('private-connection-token')
    })
    await expect(
      createSupabaseConversationMealContinuationReadStore({
        rpc: broken,
      } as unknown as ServiceClient).read(fixture().identity),
    ).rejects.toMatchObject({ code: 'conversation_continuation_read_unavailable' })
    expect(broken).toHaveBeenCalledTimes(1)
  })
  it('rejects unknown data keys/non-JSON/getters without invoking or leaking them', async () => {
    const f = fixture()
    let reads = 0
    const getter = Object.defineProperty(structuredClone(f.value), 'parent', {
      enumerable: true,
      get() {
        reads++
        return f.value.parent
      },
    })
    await expect(sdk(getter).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
    expect(reads).toBe(0)
    for (const value of [
      { ...f.value, extra: undefined },
      { ...f.value, callback: () => {} },
      { ...f.value, extra: true },
      { ...f.value, observed_at: new Date() },
    ])
      await expect(sdk(value).store.read(f.identity)).rejects.toMatchObject({
        code: 'conversation_continuation_read_unavailable',
      })
  })
})

type Mutable<T> = T extends readonly (infer V)[]
  ? Mutable<V>[]
  : T extends object
    ? { -readonly [K in keyof T]: Mutable<T[K]> }
    : T
type WireAvailable = Mutable<
  Extract<ConversationMealContinuationReadOutcome, { action: 'available' }>
>
function at<T>(values: readonly T[], index = 0): T {
  const v = values[index]
  if (v === undefined) throw new Error('fixture element missing')
  return v
}
function recoveryFixture(
  state: 'admitted' | 'prepared' | 'awaiting_reply' | 'saved' | 'superseded' = 'admitted',
) {
  const f = fixture(),
    v = structuredClone(f.value) as unknown as WireAvailable
  const childHash = '1'.repeat(64),
    childSourceHash = '2'.repeat(64),
    chainHash = '3'.repeat(64)
  const body = {
    schema: 'conversation.meal-clarification.v1' as const,
    expected_revision: 0,
    question_key: 'd'.repeat(64),
    answer: { kind: 'quantity' as const, food_index: 0, amount: 200, unit: 'g' as const },
  }
  const chain = [
    {
      reply_id: replyId,
      reply_input_hash: childHash,
      question_key: body.question_key,
      answer: body.answer,
    },
  ]
  const parentRef = {
    command_id: parent,
    input_hash: f.identity.parentInputHash,
    source_hash: sourceHash,
    attempt_id: attempt,
    result_hash: resultHash,
    decision_hash: decisionHash,
  }
  const binding = {
    owner_id: owner,
    command_id: replyId,
    input_hash: childHash,
    command_protocol: 'conversation.clarification.v1' as const,
    kind: 'meal.clarify' as const,
    epoch,
    admitted_at: '2026-11-05T01:00:04.000004Z',
  }
  const candidate = resolveDraftItem({ name: 'arroz', grams_stated: 200 }, 0)
  if (!candidate || candidate.quantity_g === null) throw new Error('candidate fixture')
  const m = {
    schema: 'conversation.meal-materialization.v1' as const,
    status: 'materialized' as const,
    input_hash: f.identity.parentInputHash,
    source_hash: sourceHash,
    attempt_id: attempt,
    inputs: [
      {
        input_index: 0,
        calculation_input: { food_name: 'arroz', quantity_g: 200 },
        candidate: {
          ...candidate,
          quantity_g: candidate.quantity_g,
          quantity_basis: 'stated' as const,
        },
        source_group_index: 0,
      },
    ],
    source_groups: [
      {
        group_index: 0,
        interpretation_food_indexes: [0],
        input_indexes: [0],
        rule: 'literal' as const,
        source_positions: [
          {
            food_index: 0,
            unit: 'command_text' as const,
            name: { unit: 'command_text' as const, start: 0, end: 5 },
            quantity: null,
            unit_ref: null,
            visual_index: null,
          },
        ],
      },
    ],
    nutrition_label: null,
  }
  const prep = {
    schema: 'conversation.meal-continuation-preparation.v1' as const,
    status: 'ready' as const,
    input_hash: childHash,
    source_hash: childSourceHash,
    parent_ref: parentRef,
    answer_chain_hash: chainHash,
    quantity_witnesses: [
      {
        reply_id: replyId,
        food_index: 0,
        amount: 200,
        unit: 'g' as const,
        quantity_g: 200,
        quantity_basis: 'stated' as const,
        quantity_display: null,
        input_indexes: [0],
      },
    ],
    materialization: m,
    meal: {
      meal_type: 'almoco' as const,
      items: [
        {
          name: 'arroz branco cozido',
          food_db_id: null,
          nutrition_source: 'rule_based' as const,
          quantity_g: 200,
          kcal: 260,
          protein_g: 5,
          carbs_g: 55,
          fat_g: 1.6,
          confidence: null,
          input_indexes: [0],
          quantity_basis: 'stated' as const,
          display_qty: null,
          display_unit: null,
        },
      ],
      totals: { kcal: 260, protein_g: 5, carbs_g: 55, fat_g: 1.6 },
      preparation_annotations: [],
      source_receipts: [],
    },
  }
  v.reply = {
    binding,
    body,
    source: {
      source_hash: childSourceHash,
      captured_at: '2026-11-05T01:00:05.000005Z',
      context: {
        schema: 'conversation.meal-continuation-source.v1',
        owner_id: owner,
        command_id: replyId,
        input_hash: childHash,
        epoch,
        source_input: body,
        parent: parentRef,
        answer_chain_hash: chainHash,
        answer_chain: chain,
        authority: {
          source_hash: '4'.repeat(64),
          context: structuredClone(v.parent.source.context),
        },
      },
    },
    preparation: null,
    receipt: null,
    state: 'admitted',
  }
  v.observed_at = '2026-11-05T01:00:12.000012Z'
  if (state === 'prepared' || state === 'saved' || state === 'superseded') {
    v.reply.preparation = {
      prepared_hash: '5'.repeat(64),
      prepared_at: '2026-11-05T01:00:06.000006Z',
      preparation: prep,
      next_question: null,
    }
    v.reply.state = 'prepared'
  }
  if (state === 'saved' || state === 'superseded') {
    const receipt = {
      schema: 'conversation.meal-continuation-effect.v1' as const,
      owner_id: owner,
      command_id: replyId,
      input_hash: childHash,
      parent_command_id: parent,
      parent_input_hash: f.identity.parentInputHash,
      parent_decision_hash: decisionHash,
      epoch,
      registration_id: '10000000-0000-4000-8000-000000000007',
      provider_key: `conversation.clarification/${owner}/${parent}`,
      meal_type: 'almoco' as const,
      local_date: '2026-11-04',
      timezone: 'America/Sao_Paulo',
      consumed_at: '2026-11-05T01:00:10.000010Z',
      log_ids: ['10000000-0000-4000-8000-000000000008'],
      effect_version: `cmeal1:${'6'.repeat(64)}`,
    }
    v.reply.receipt = receipt
    v.reply.state = 'saved'
    v.head = {
      revision: 1,
      question: null,
      answers_hash: chainHash,
      answers: chain,
      fulfilled_by: replyId,
    }
    v.fulfillment = { parent_binding: v.parent.binding, child_binding: binding, receipt }
    if (state === 'superseded') {
      const winner = '10000000-0000-4000-8000-000000000009',
        winHash = '7'.repeat(64)
      v.reply.receipt = null
      v.reply.state = 'superseded'
      v.head.answers = [{ ...at(chain), reply_id: winner, reply_input_hash: winHash }]
      v.head.fulfilled_by = winner
      v.head.answers_hash = '8'.repeat(64)
      v.fulfillment = {
        parent_binding: v.parent.binding,
        child_binding: { ...binding, command_id: winner, input_hash: winHash },
        receipt: { ...receipt, command_id: winner, input_hash: winHash },
      }
    }
  }
  if (state === 'awaiting_reply') {
    const sourceInput = { ...v.parent.source.context.source_input }
    delete sourceInput.meal_type
    const command = bindConversationCommand(owner, `cmsg1:${parent}`, sourceInput),
      hash = command.inputHash
    f.identity.parentInputHash = hash
    v.parent.binding.input_hash = hash
    Object.assign(v.parent.source.context, { input_hash: hash, source_input: command.command })
    v.parent.semantic.result.input_hash = hash
    v.parent.decision.input_hash = hash
    v.reply.source.context.parent.input_hash = hash
    Object.assign(v.reply.source.context.authority.context, {
      input_hash: hash,
      source_input: command.command,
    })
    m.input_hash = hash
    const next = {
      schema: 'conversation.meal-question.v1' as const,
      question_key: '9'.repeat(64),
      revision: 1,
      kind: 'meal_type' as const,
      food_index: null,
      food_name: null,
      allowed_units: [],
      quantity_reference: null,
    }
    const { meal: _meal, status: _status, ...base } = prep
    v.reply.preparation = {
      prepared_hash: '5'.repeat(64),
      prepared_at: '2026-11-05T01:00:06.000006Z',
      preparation: {
        ...base,
        status: 'needs_reply',
        next_need: { kind: 'meal_type', food_index: null },
      },
      next_question: next,
    }
    v.reply.state = 'awaiting_reply'
    v.head = {
      revision: 1,
      question: next,
      answers_hash: chainHash,
      answers: chain,
      fulfilled_by: null,
    }
  }
  return { identity: { ...f.identity, replyId, replyInputHash: childHash }, value: v }
}

describe('complete versioned linked recovery DTOs', () => {
  it.each([
    'admitted',
    'prepared',
    'awaiting_reply',
    'saved',
    'superseded',
  ] as const)('preserves actual-shaped %s wire without v1 effect substitution', async (state) => {
    const f = recoveryFixture(state),
      s = sdk(f.value),
      actual = await s.store.read(f.identity)
    expect(actual).toEqual(f.value)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    if (actual.action !== 'available') throw new Error('missing available')
    expect(actual.reply?.state).toBe(state)
    expect(actual.reply?.body).toEqual(f.value.reply?.body)
    if (state === 'saved')
      expect(actual.reply?.receipt?.schema).toBe('conversation.meal-continuation-effect.v1')
  })
  it.each([
    'reply-owner',
    'reply-epoch',
    'reply-id',
    'reply-hash',
    'source-parent',
    'source-decision',
    'source-body',
    'chain-reply',
    'chain-hash',
    'head-state',
    'prep-hash',
    'prep-source',
    'prep-parent',
    'prep-chain',
    'mat-source',
    'mat-position',
    'mat-quantity',
    'witness-missing',
    'witness-amount',
    'witness-map',
    'prep-next',
    'receipt-schema',
    'receipt-owner',
    'receipt-parent',
    'receipt-token',
    'receipt-provider',
    'receipt-date',
    'receipt-zone',
    'receipt-log-count',
    'fulfillment-clock',
    'meal-trim',
    'meal-total',
    'meal-source',
    'meal-density',
    'meal-macro-mass',
    'receipt-log-duplicate',
    'fulfillment-child',
    'fulfillment-parent',
    'fulfillment-missing',
    'extra',
  ])('refuses crossed complete %s', async (attack) => {
    const f = recoveryFixture('saved'),
      v = f.value,
      r = v.reply
    if (!r?.preparation || !r.receipt || !v.fulfillment) throw new Error('fixture missing')
    const p = r.preparation.preparation
    if (attack === 'reply-owner') r.binding.owner_id = attempt
    if (attack === 'reply-epoch') r.binding.epoch = attempt
    if (attack === 'reply-id') r.binding.command_id = attempt
    if (attack === 'reply-hash') r.binding.input_hash = 'f'.repeat(64)
    if (attack === 'source-parent') r.source.context.parent.command_id = attempt
    if (attack === 'source-decision') r.source.context.parent.decision_hash = 'f'.repeat(64)
    if (attack === 'source-body')
      r.source.context.source_input = { ...r.body, expected_revision: 1 }
    if (attack === 'chain-reply') at(r.source.context.answer_chain).reply_id = attempt
    if (attack === 'chain-hash') r.source.context.answer_chain_hash = 'f'.repeat(64)
    if (attack === 'head-state') r.state = 'admitted'
    if (attack === 'prep-hash') r.preparation.prepared_hash = 'bad'
    if (attack === 'prep-source') p.source_hash = 'f'.repeat(64)
    if (attack === 'prep-parent') p.parent_ref.input_hash = 'f'.repeat(64)
    if (attack === 'prep-chain') p.answer_chain_hash = 'f'.repeat(64)
    if (p.materialization.status !== 'materialized') throw new Error('materialization missing')
    if (attack === 'mat-source') p.materialization.source_hash = 'f'.repeat(64)
    if (attack === 'mat-position')
      at(at(p.materialization.source_groups).source_positions).name = {
        unit: 'command_text',
        start: 1,
        end: 5,
      }
    if (attack === 'mat-quantity') at(p.materialization.inputs).calculation_input.quantity_g = 100
    if (attack === 'witness-missing') p.quantity_witnesses = []
    if (attack === 'witness-amount') at(p.quantity_witnesses).amount = 100
    if (attack === 'witness-map') at(p.quantity_witnesses).input_indexes = []
    if (attack === 'prep-next') Object.assign(r.preparation, { next_question: v.parent.decision })
    if (attack === 'receipt-schema')
      Object.assign(r.receipt, { schema: 'conversation.meal-effect.v1' })
    if (attack === 'receipt-owner') r.receipt.owner_id = attempt
    if (attack === 'receipt-parent') r.receipt.parent_command_id = attempt
    if (attack === 'receipt-token') r.receipt.parent_decision_hash = 'f'.repeat(64)
    if (attack === 'receipt-provider')
      r.receipt.provider_key = `conversation.meal/${owner}/${parent}`
    if (attack === 'receipt-date') r.receipt.local_date = '2026-11-05'
    if (attack === 'receipt-zone') {
      r.receipt.timezone = 'UTC'
      r.receipt.local_date = '2026-11-05'
    }
    if (attack === 'receipt-log-count') r.receipt.log_ids.push(attempt)
    if (attack === 'fulfillment-clock')
      v.fulfillment.child_binding = {
        ...v.fulfillment.child_binding,
        admitted_at: '2026-11-05T01:00:04.500000Z',
      }
    if (p.status !== 'ready') throw new Error('ready fixture')
    if (attack === 'meal-trim') at(p.meal.items).name = ' arroz branco cozido'
    if (attack === 'meal-total') p.meal.totals.kcal += 1
    if (attack === 'meal-source') at(p.meal.items).nutrition_source = 'canonical_exact'
    if (attack === 'meal-density') {
      at(p.meal.items).kcal = 20000
      p.meal.totals.kcal = 20000
    }
    if (attack === 'meal-macro-mass') {
      at(p.meal.items).protein_g = 300
      p.meal.totals.protein_g = 300
    }
    if (attack === 'receipt-log-duplicate') r.receipt.log_ids.push(at(r.receipt.log_ids))
    if (attack === 'fulfillment-child') v.fulfillment.child_binding.command_id = attempt
    if (attack === 'fulfillment-parent') v.fulfillment.parent_binding.input_hash = 'f'.repeat(64)
    if (attack === 'fulfillment-missing') v.fulfillment = null
    if (attack === 'extra') Object.assign(r.preparation, { private: 'extra' })
    await expect(sdk(v).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
  })
  it('accepts complete combined private contexts above1MiB and refuses above4MiB without truncation', async () => {
    const f = recoveryFixture('admitted'),
      r = f.value.reply
    if (!r) throw new Error('reply fixture')
    f.value.parent.source.context.clinical.fixture_padding = 'é'.repeat(300000)
    r.source.context.authority.context.clinical.fixture_padding = 'é'.repeat(300000)
    expect(Buffer.byteLength(JSON.stringify(f.value), 'utf8')).toBeGreaterThan(1048576)
    expect(isDeepStrictEqual(await sdk(f.value).store.read(f.identity), f.value)).toBe(true)
    f.value.parent.source.context.clinical.fixture_padding = 'é'.repeat(2200000)
    await expect(sdk(f.value).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
  })
})

describe('byte-exact actual SQL continuation recovery fixtures', () => {
  it('uses the original nine synthetic rollback-only SQL captures', () => {
    // Values originate from J-owned c3 fixtures; no private payload is logged.
    expect(actualSQL.real_SQL).toBe(true)
    expect(actualSQL.HTTP_or_native).toBe(false)
    expect(actualSQL.provider_calls).toBe(0)
    expect(Object.keys(actualSQL.samples)).toHaveLength(9)
    expect(
      createHash('sha256')
        .update(
          readFileSync(
            new URL('./__fixtures__/conversation-meal-continuation-read-sql.json', import.meta.url),
          ),
        )
        .digest('hex'),
    ).toBe('929a5e677fb9ef3c96a3f1714b6dd178fdc89c063ac2ad4b3341bdc9a53666c7')
  })
  it.each(
    Object.entries(actualSQL.samples),
  )('decodes actual %s without private field rewriting', async (_name, raw) => {
    const v = raw as unknown as WireAvailable,
      b = v.parent.binding
    const identity = {
      ownerId: b.owner_id,
      parentCommandId: b.command_id,
      parentInputHash: b.input_hash,
      epoch: b.epoch,
      ...(v.reply
        ? { replyId: v.reply.binding.command_id, replyInputHash: v.reply.binding.input_hash }
        : {}),
    }
    const s = sdk(raw),
      result = await s.store.read(identity)
    expect(isDeepStrictEqual(result, raw)).toBe(true)
    expect(s.rpc).toHaveBeenCalledTimes(1)
    // Opaque SQL hashes and original timestamp strings are preserved bytewise.
    if (result.action !== 'available') throw new Error('missing actual available')
    expect(result.parent.source.source_hash).toBe(v.parent.source.source_hash)
    expect(result.observed_at).toBe(v.observed_at)
  })
})

describe('private bounded SDK/JSON surface', () => {
  it('exports read only and never invokes envelope accessors', async () => {
    const f = fixture()
    let reads = 0
    const response = Object.defineProperty({ error: null }, 'data', {
      enumerable: true,
      get() {
        reads++
        return f.value
      },
    })
    const rpc = vi.fn(async () => response),
      store = createSupabaseConversationMealContinuationReadStore({
        rpc,
      } as unknown as ServiceClient)
    expect(Object.keys(store)).toEqual(['read'])
    await expect(store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
    expect(reads).toBe(0)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('redacts SDK failures and refuses unknown envelope fields without retry', async () => {
    const f = fixture()
    for (const response of [
      { data: f.value, error: { message: 'private-token-123' } },
      { data: f.value, error: null, foreign: 'private-token-123' },
    ]) {
      const rpc = vi.fn(async () => response),
        store = createSupabaseConversationMealContinuationReadStore({
          rpc,
        } as unknown as ServiceClient)
      let outcome: unknown
      try {
        await store.read(f.identity)
      } catch (error) {
        outcome = error
      }
      expect(outcome).toMatchObject({
        code: 'conversation_continuation_read_unavailable',
        message: 'Linked meal state is unavailable',
      })
      expect(rpc).toHaveBeenCalledTimes(1)
    }
  })
  it('applies the exact4MiB UTF8 bound and rejects invalid key/value Unicode and depth', () => {
    const exact = { pad: 'a'.repeat(4194294) }
    expect(Buffer.byteLength(JSON.stringify(exact), 'utf8')).toBe(4194304)
    expect(Object.isFrozen(detachConversationContinuationReadJson(exact))).toBe(true)
    expect(() => detachConversationContinuationReadJson({ pad: `${exact.pad}a` })).toThrow()
    const cycle: Record<string, unknown> = {}
    cycle.self = cycle
    let deep: unknown = 'leaf'
    for (let i = 0; i < 66; i++) deep = { child: deep }
    for (const value of [
      cycle,
      deep,
      { 'bad\ud800': 'key' },
      { key: 'bad\udc00' },
      { key: 'bad\u0000' },
      Object.assign([], { extra: true }),
    ])
      expect(() => detachConversationContinuationReadJson(value)).toThrow()
  })
})

function partialQuantityFixture() {
  const f = recoveryFixture('admitted'),
    v = f.value,
    r = v.reply
  if (!r) throw new Error('reply fixture')
  const command = bindConversationCommand(owner, `cmsg1:${parent}`, {
      ...v.parent.source.context.source_input,
      source: { channel: 'text', text: 'arroz; feijão' },
    }),
    hash = command.inputHash
  f.identity.parentInputHash = hash
  v.parent.binding.input_hash = hash
  Object.assign(v.parent.source.context, { input_hash: hash, source_input: command.command })
  const model = v.parent.semantic.result
  model.input_hash = hash
  model.foods.push({
    index: 1,
    name: { unit: 'command_text', start: 7, end: 13 },
    quantity: null,
    unit: null,
    visual_index: null,
  })
  at(model.sources).spans = [
    { start: 0, end: 5, kind: 'food', food_index: 0 },
    { start: 5, end: 7, kind: 'separator', food_index: null },
    { start: 7, end: 13, kind: 'food', food_index: 1 },
  ]
  v.parent.decision.input_hash = hash
  r.source.context.parent.input_hash = hash
  Object.assign(r.source.context.authority.context, {
    input_hash: hash,
    source_input: command.command,
  })
  const next: NonNullable<WireAvailable['head']['question']> = {
    schema: 'conversation.meal-question.v1',
    question_key: '9'.repeat(64),
    revision: 1,
    kind: 'quantity',
    food_index: 1,
    food_name: 'feijão',
    allowed_units: ['g', 'kg'],
    quantity_reference: null,
  }
  r.preparation = {
    prepared_hash: '5'.repeat(64),
    prepared_at: '2026-11-05T01:00:06.000006Z',
    next_question: next,
    preparation: {
      schema: 'conversation.meal-continuation-preparation.v1',
      status: 'needs_reply',
      input_hash: r.binding.input_hash,
      source_hash: r.source.source_hash,
      parent_ref: structuredClone(r.source.context.parent),
      answer_chain_hash: r.source.context.answer_chain_hash,
      quantity_witnesses: [
        {
          reply_id: replyId,
          food_index: 0,
          amount: 200,
          unit: 'g',
          quantity_g: 200,
          quantity_basis: 'stated',
          quantity_display: null,
          input_indexes: [],
        },
      ],
      materialization: {
        status: 'clarification_required',
        reason: 'missing_quantity',
        food_indexes: [1],
      },
      next_need: { kind: 'quantity', food_index: 1 },
    },
  }
  r.state = 'awaiting_reply'
  v.head = {
    revision: 1,
    question: next,
    answers_hash: r.source.context.answer_chain_hash,
    answers: structuredClone(r.source.context.answer_chain),
    fulfilled_by: null,
  }
  return f
}
describe('actual-shaped incomplete quantity preparation', () => {
  it('retains [] witness indexes until materialization exists, without fabricating partial slots', async () => {
    const f = partialQuantityFixture(),
      result = await sdk(f.value).store.read(f.identity)
    expect(isDeepStrictEqual(result, f.value)).toBe(true)
    if (result.action !== 'available') throw new Error('missing available')
    expect(result.reply?.preparation?.preparation.quantity_witnesses[0]?.input_indexes).toEqual([])
  })
  it.each([
    'invented-index',
    'wrong-next',
    'wrong-material-index',
  ])('refuses incomplete %s', async (attack) => {
    const f = partialQuantityFixture(),
      p = f.value.reply?.preparation?.preparation
    if (!p || p.status !== 'needs_reply' || p.materialization.status !== 'clarification_required')
      throw new Error('partial fixture')
    if (attack === 'invented-index') at(p.quantity_witnesses).input_indexes = [0]
    if (attack === 'wrong-next') p.next_need.food_index = 0
    if (attack === 'wrong-material-index') p.materialization.food_indexes = [0]
    await expect(sdk(f.value).store.read(f.identity)).rejects.toMatchObject({
      code: 'conversation_continuation_read_unavailable',
    })
  })
})

describe('fresh read-only reconciliation', () => {
  it('reads admitted then real saved winner through the same store without response cache or writer', async () => {
    const before = recoveryFixture('admitted'),
      after = recoveryFixture('saved')
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: before.value, error: null })
      .mockResolvedValueOnce({ data: after.value, error: null })
    const store = createSupabaseConversationMealContinuationReadStore({
      rpc,
    } as unknown as ServiceClient)
    const first = await store.read(before.identity),
      second = await store.read(after.identity)
    expect(first.action === 'available' && first.reply?.state === 'admitted').toBe(true)
    expect(second.action === 'available' && second.reply?.state === 'saved').toBe(true)
    expect(rpc).toHaveBeenCalledTimes(2)
    expect(rpc.mock.calls.every((call) => call[0] === 'read_conversation_meal_continuation')).toBe(
      true,
    )
  })
})

describe('post-review P2 exact JSON and current-question guards', () => {
  it.each([
    'function',
    'getter',
    'null',
  ] as const)('rejects custom Array prototype %s before any inherited hook can run', async (kind) => {
    const f = fixture()
    let effects = 0
    const proto = kind === 'null' ? null : Object.create(Array.prototype)
    if (proto && kind === 'function')
      Object.defineProperty(proto, 'toJSON', {
        value() {
          effects++
          return []
        },
      })
    if (proto && kind === 'getter')
      Object.defineProperty(proto, 'toJSON', {
        get() {
          effects++
          return () => {
            effects++
            return []
          }
        },
      })
    Object.setPrototypeOf(f.value.head.answers, proto)
    let accepted = false
    try {
      await sdk(f.value).store.read(f.identity)
      accepted = true
    } catch {}
    expect(accepted).toBe(false)
    expect(effects).toBe(0)
  })
  it.each([
    'key',
    'kind',
  ] as const)('requires the actual same-current-head question %s to match the immutable body', async (attack) => {
    const raw = structuredClone(
      actualSQL.samples.admitted_quantity_reply,
    ) as unknown as WireAvailable
    if (!raw.reply || !raw.head.question) throw new Error('admitted fixture')
    const b = raw.parent.binding,
      identity = {
        ownerId: b.owner_id,
        parentCommandId: b.command_id,
        parentInputHash: b.input_hash,
        epoch: b.epoch,
        replyId: raw.reply.binding.command_id,
        replyInputHash: raw.reply.binding.input_hash,
      }
    expect(raw.head.revision).toBe(raw.reply.body.expected_revision)
    if (attack === 'key') raw.head.question.question_key = 'f'.repeat(64)
    else
      raw.head.question = {
        ...raw.head.question,
        kind: 'meal_type',
        food_index: null,
        food_name: null,
        allowed_units: [],
        quantity_reference: null,
      }
    let accepted = false
    try {
      await sdk(raw).store.read(identity)
      accepted = true
    } catch {}
    expect(accepted).toBe(false)
  })
})

describe('historical witness exact approved conversion', () => {
  it('refuses a self-consistent changed mass across witness, candidate and final meal', async () => {
    const f = recoveryFixture('prepared'),
      r = f.value.reply
    if (!r?.preparation || r.preparation.preparation.status !== 'ready') throw new Error('fixture')
    const prep = r.preparation.preparation
    if (prep.materialization.status !== 'materialized') throw new Error('fixture')
    at(prep.quantity_witnesses).quantity_g = 201
    at(prep.materialization.inputs).calculation_input.quantity_g = 201
    at(prep.materialization.inputs).candidate.quantity_g = 201
    at(prep.meal.items).quantity_g = 201
    let accepted = false
    try {
      await sdk(f.value).store.read(f.identity)
      accepted = true
    } catch {}
    expect(accepted).toBe(false)
  })
})

// Synthetic only: preserve the complete admitted parent/source/answer structure,
// replacing its single original whole-name occurrence and the explicit quantity.
function referenceWitnessFixture(
  name: string,
  amount: number,
  unit: 'mL' | 'scoop',
  grams: number,
) {
  const original = recoveryFixture('prepared')
  const command = bindConversationCommand(owner, `cmsg1:${parent}`, {
    command_protocol: 'conversation.command.v1',
    command_id: parent,
    kind: 'meal.report',
    source: { channel: 'text', text: name },
    meal_type: 'almoco',
  })
  const oldHash = original.identity.parentInputHash
  const rewritten = JSON.parse(
    JSON.stringify(original.value).replaceAll(oldHash, command.inputHash),
  ) as WireAvailable
  const f = {
    identity: { ...original.identity, parentInputHash: command.inputHash },
    value: rewritten,
  }
  const v = f.value,
    r = v.reply
  if (!r?.preparation || !v.head.question || v.head.question.kind !== 'quantity')
    throw new Error('fixture')
  const prep = r.preparation.preparation
  if (prep.status !== 'ready' || prep.materialization.status !== 'materialized')
    throw new Error('fixture')
  v.parent.source.context.source_input = command.command
  r.source.context.authority.context.source_input = structuredClone(command.command)
  const model = v.parent.semantic.result
  const originalFood = at(model.foods)
  if (!originalFood.name) throw new Error('fixture')
  originalFood.name.end = name.length
  at(at(model.sources).spans).end = name.length
  const reference = mobileQuantityDisplay(name)
  if (!reference) throw new Error('fixture reference')
  Object.assign(v.head.question, {
    food_name: name,
    allowed_units: unit === 'mL' ? ['g', 'kg', 'mL', 'L', 'caneca'] : ['g', 'kg', 'scoop'],
    quantity_reference: reference,
  })
  const answer = { kind: 'quantity' as const, food_index: 0, amount, unit }
  r.body.answer = answer
  r.source.context.source_input.answer = structuredClone(answer)
  at(r.source.context.answer_chain).answer = structuredClone(answer)
  Object.assign(at(prep.quantity_witnesses), {
    amount,
    unit,
    quantity_g: grams,
    quantity_basis: 'portion_reference',
    quantity_display: reference,
  })
  const entry = at(prep.materialization.inputs)
  entry.calculation_input = { food_name: name, quantity_g: grams }
  const candidate = resolveDraftItem({ name, grams_stated: grams }, 0)
  if (!candidate || candidate.quantity_g === null) throw new Error('fixture candidate')
  entry.candidate = {
    ...candidate,
    quantity_g: grams,
    quantity_basis: 'portion_reference',
    quantity_display: reference,
  }
  const position = at(at(prep.materialization.source_groups).source_positions)
  if (!position.name) throw new Error('fixture position')
  position.name.end = name.length
  const syntheticMacros = { kcal: 10, protein_g: 1, carbs_g: 1, fat_g: 0 }
  Object.assign(at(prep.meal.items), {
    name,
    quantity_g: grams,
    quantity_basis: 'portion_reference',
    ...syntheticMacros,
  })
  prep.meal.totals = syntheticMacros
  return f
}

describe('actual original-name reference witness binding', () => {
  it.each([
    ['leite', 200, 'mL', 206],
    ['whey', 1, 'scoop', 30],
  ] as const)('accepts approved %s %s %s = %sg without recreating a historical question', async (name, amount, unit, grams) => {
    const f = referenceWitnessFixture(name, amount, unit, grams)
    const read = await sdk(f.value).store.read(f.identity)
    expect(isDeepStrictEqual(read, f.value)).toBe(true)
  })

  it.each([
    'grams',
    'factor',
    'underflow',
  ] as const)('refuses historical reference witness %s drift', async (attack) => {
    const f = referenceWitnessFixture('leite', 200, 'mL', 206),
      r = f.value.reply
    if (!r?.preparation || r.preparation.preparation.status !== 'ready') throw new Error('fixture')
    const prep = r.preparation.preparation,
      w = at(prep.quantity_witnesses)
    if (prep.materialization.status !== 'materialized') throw new Error('fixture')
    if (attack === 'factor') {
      if (!w.quantity_display) throw new Error('fixture')
      w.quantity_display.grams_per_unit = 1
    } else {
      if (attack === 'underflow') {
        const answer = {
          kind: 'quantity' as const,
          food_index: 0,
          amount: Number.MIN_VALUE,
          unit: 'mL' as const,
        }
        r.body.answer = answer
        r.source.context.source_input.answer = structuredClone(answer)
        at(r.source.context.answer_chain).answer = structuredClone(answer)
        w.amount = Number.MIN_VALUE
      }
      w.quantity_g = 200
      at(prep.materialization.inputs).calculation_input.quantity_g = 200
      at(prep.materialization.inputs).candidate.quantity_g = 200
      at(prep.meal.items).quantity_g = 200
    }
    let accepted = false
    try {
      await sdk(f.value).store.read(f.identity)
      accepted = true
    } catch {}
    expect(accepted).toBe(false)
  })
})
