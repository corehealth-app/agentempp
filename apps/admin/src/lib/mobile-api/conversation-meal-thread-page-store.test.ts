import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { anotherJournalCommand, journalCommand } from './__fixtures__/conversation-journal'
import { editReceipt } from './__fixtures__/conversation-meal-edit'
import {
  type threadFulfillment,
  threadPage,
  threadQuery,
  threadReply,
  threadReport,
  threadResult,
  threadSavedReport,
} from './__fixtures__/conversation-thread-page'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  createSupabaseConversationMealThreadPageStore,
  parseConversationMealThreadPage,
} from './conversation-meal-thread-page-store'

type Page = ReturnType<typeof threadPage>
function reply(p: Page) {
  return p.items[2] as ReturnType<typeof threadReply>
}
function fx(p: Page) {
  return p.items[0] as ReturnType<typeof threadFulfillment>
}
function admittedPage() {
  const p = threadPage(),
    t = p.threads[0]
  return {
    ...p,
    threads: [
      { ...t, continuation: { revision: 0, question: threadReply().question, fulfilled_by: null } },
    ],
    items: [threadReply(), threadReport()],
  }
}
describe('closed compact actual thread transport', () => {
  it('constructs inertly, calls only the real RPC once and returns immutable actual child protocol', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: threadPage(), error: null })
    const s = createSupabaseConversationMealThreadPageStore({ rpc } as unknown as ServiceClient)
    expect(rpc).not.toHaveBeenCalled()
    const p = await s.read(threadQuery())
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('read_conversation_meal_journal_page_v2', {
      p_user_id: threadQuery().ownerId,
      p_expected_epoch: threadQuery().epoch,
      p_limit: 10,
      p_cursor: null,
    })
    expect(p).toEqual(threadPage())
    expect(Object.isFrozen(p)).toBe(true)
  })
  it.each([
    'absent',
    'stale_epoch',
    'cursor_conflict',
    'event_conflict',
  ])('preserves actual refusal %s', (a) =>
    expect(parseConversationMealThreadPage({ action: a }, threadQuery())).toEqual({ action: a }))
  it.each([
    ['unknown private key', (p: Page) => Object.assign(p.items[0], { snapshot: {} })],
    ['unused descriptor', (p: Page) => (p.items = [])],
    ['duplicate descriptor', (p: Page) => p.threads.push(p.threads[0])],
    ['missing descriptor', (p: Page) => (p.threads = [])],
    ['foreign epoch', (p: Page) => (p.threads[0].parent_binding.epoch = p.threads[0].thread_id)],
    ['changed original', (p: Page) => (p.threads[0].original_command.source.text = 'other')],
    ['foreign child', (p: Page) => (fx(p).child_binding.owner_id = p.threads[0].thread_id)],
    ['forged parent link', (p: Page) => (fx(p).receipt.parent_decision_hash = 'b'.repeat(64))],
    ['fake v1 child', (p: Page) => (fx(p).receipt.schema = 'conversation.meal-effect.v1')],
    ['lost question binding', (p: Page) => (reply(p).body.question_key = 'b'.repeat(64))],
    ['private question key', (p: Page) => Object.assign(reply(p).question, { source_context: {} })],
    ['changed question units', (p: Page) => (reply(p).question.allowed_units = ['g', 'kg'])],
    ['wrong event clock', (p: Page) => (p.items[2].at = '2026-11-04T12:00:01.000000Z')],
    ['unordered', (p: Page) => p.items.reverse()],
    ['future event', (p: Page) => (p.observed_at = p.items[p.items.length - 1].at)],
    [
      'false report',
      (p: Page) => Object.assign(p.items[p.items.length - 1], { status: 'registered' }),
    ],
    [
      'bad cursor',
      (p: Page) => {
        p.has_more = true
        Object.assign(p, { next_cursor: { at: p.items[0].at, id: p.items[0].event_id } })
      },
    ],
    ['duplicate event', (p: Page) => p.items.push(p.items[0])],
    [
      'wrong fulfillment head',
      (p: Page) => (p.threads[0].continuation.fulfilled_by = p.threads[0].thread_id),
    ],
  ])('fails closed %s', (_name, mutate) => {
    const p = threadPage()
    mutate(p)
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
  })
  it('reads an actual newly admitted child at the unchanged current revision and exact current question', () => {
    const p = admittedPage()
    expect(parseConversationMealThreadPage(p, threadQuery())).toEqual(p)
  })
  it('reads ready preparation before commit while SQL keeps the current head revision/question', () => {
    const p = admittedPage()
    const raw = { ...p, items: [threadResult(), ...p.items] }
    expect(parseConversationMealThreadPage(raw, threadQuery())).toEqual(raw)
  })
  it('refuses equal revision with a mismatched actual current question', () => {
    const p = admittedPage()
    p.threads[0].continuation.question.question_key = 'b'.repeat(64)
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
  })
  it('refuses a future reply revision even when its own body and historical question match', () => {
    const p = admittedPage()
    const r = p.items[0] as ReturnType<typeof threadReply>
    r.body.expected_revision = 1
    r.question.revision = 1
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
  })
  it('refuses an unfulfilled existing head with no actual current question', () => {
    const p = admittedPage()
    const raw = {
      ...p,
      threads: [
        { ...p.threads[0], continuation: { revision: 0, question: null, fulfilled_by: null } },
      ],
      items: [threadReport()],
    }
    expect(() => parseConversationMealThreadPage(raw, threadQuery())).toThrow()
  })
  it('accepts read-only historical needs_reply after a later child fulfilled the current head', () => {
    const p = threadPage(),
      old = p.threads[0],
      result = threadResult()
    // Quantity was answered first; missing meal type was answered by a later
    // child. This page contains only the older readonly quantity reply/result.
    const { meal_type: _explicitMeal, ...original } = old.original_command
    const command = bindConversationCommand(
      old.parent_binding.owner_id,
      `cmsg1:${old.thread_id}`,
      original,
    )
    const next = {
      schema: 'conversation.meal-question.v1',
      question_key: 'c'.repeat(64),
      revision: 1,
      kind: 'meal_type',
      food_index: null,
      food_name: null,
      allowed_units: [],
      quantity_reference: null,
    }
    Object.assign(result, { status: 'needs_reply', next_question: next })
    const raw = {
      ...p,
      threads: [
        {
          ...old,
          original_command: original,
          parent_binding: { ...old.parent_binding, input_hash: command.inputHash },
          terminal_receipt: { ...old.terminal_receipt, input_hash: command.inputHash },
          continuation: {
            revision: 2,
            question: null,
            fulfilled_by: '10000000-0000-4000-8000-000000000042',
          },
        },
      ],
      items: [result, threadReply()],
    }
    expect(parseConversationMealThreadPage(raw, threadQuery())).toEqual(raw)
  })
  it('rejects a fulfillment before its actual prepared event', () => {
    const p = threadPage()
    const r = p.items[1] as ReturnType<typeof threadResult>
    r.at = '2026-11-04T12:00:04.000001Z'
    p.items.sort((a, b) => b.at.localeCompare(a.at))
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
  })
  it('preserves compact sanitized edit facts and refuses impossible compensation versions', () => {
    const saved = threadSavedReport(journalCommand('registered')),
      privateReceipt = editReceipt('e'.repeat(64)),
      { snapshot: _snapshot, ...receipt } = privateReceipt
    const event = {
      event_id: `edit/${receipt.command_id}/${receipt.operation_id}`,
      at: '2026-11-04T12:01:00.123456Z',
      kind: 'edit',
      thread_id: saved.descriptor.thread_id,
      effect_binding: saved.descriptor.parent_binding,
      receipt: { ...receipt, schema: 'conversation.meal-edit-effect-public.v1' },
    }
    const p = { ...threadPage(), threads: [saved.descriptor], items: [event] }
    expect(parseConversationMealThreadPage(p, threadQuery())).toEqual(p)
    event.receipt.removed_item_ids.push('10000000-0000-4000-8000-000000000095')
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
  })
  it('does not rehash numeric JSONB child history', () => {
    const p = threadPage()
    reply(p).body.answer.amount = 0.0000001
    expect(parseConversationMealThreadPage(p, threadQuery())).toEqual(p)
  })
  it('rejects getters without executing them', () => {
    const p = threadPage()
    const trap = vi.fn()
    Object.defineProperty(p, 'threads', { enumerable: true, get: trap })
    expect(() => parseConversationMealThreadPage(p, threadQuery())).toThrow()
    expect(trap).not.toHaveBeenCalled()
  })
  it('preserves C-collation ties and requires the exact last owned cursor anchor', () => {
    const p = threadPage()
    p.items[0].at = p.items[1].at
    fx(p).receipt.consumed_at = p.items[1].at
    p.items.sort((a, b) =>
      a.at === b.at ? (a.event_id > b.event_id ? -1 : 1) : a.at > b.at ? -1 : 1,
    )
    Object.assign(p, {
      has_more: true,
      next_cursor: { at: p.items[3].at, id: p.items[3].event_id },
    })
    expect(parseConversationMealThreadPage(p, { ...threadQuery(), limit: 4 })).toEqual(p)
  })
  it.each([
    { data: null, error: null },
    { data: threadPage(), error: { message: 'secret error' } },
    { data: { action: 'event_conflict', snapshot: {} }, error: null },
  ])('redacts a failed or malformed actual RPC response', async (response) => {
    const rpc = vi.fn().mockResolvedValue(response)
    const s = createSupabaseConversationMealThreadPageStore({ rpc } as unknown as ServiceClient)
    await expect(s.read(threadQuery())).rejects.toThrow('Conversation history is unavailable')
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('rejects one registry UUID claimed simultaneously as a report parent and a clarification child', () => {
    const p = threadPage(),
      saved = threadSavedReport(
        anotherJournalCommand(
          threadReply().child_binding.command_id,
          '2026-11-04T12:00:01.000001Z',
          'registered',
        ),
      )
    const raw = {
      ...p,
      threads: [...p.threads, saved.descriptor].sort((a, b) =>
        a.thread_id < b.thread_id ? -1 : 1,
      ),
      items: [...p.items, saved.event].sort((a, b) =>
        a.at === b.at ? (a.event_id > b.event_id ? -1 : 1) : a.at > b.at ? -1 : 1,
      ),
    }
    expect(() => parseConversationMealThreadPage(raw, threadQuery())).toThrow()
  })
  it('does not retry a lost RPC response', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('private transport'))
    const s = createSupabaseConversationMealThreadPageStore({ rpc } as unknown as ServiceClient)
    await expect(s.read(threadQuery())).rejects.toThrow('Conversation history is unavailable')
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
