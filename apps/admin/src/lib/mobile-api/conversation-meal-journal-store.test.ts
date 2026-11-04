import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  anotherJournalCommand,
  journalCommand,
  journalEdit,
  journalPage,
  journalQuery,
} from './__fixtures__/conversation-journal'
import { writerBinding, writerCommand } from './__fixtures__/conversation-meal-writer'
import { parseConversationMealEditHistoricalReceipt } from './conversation-meal-edit-contracts'
import {
  createSupabaseConversationMealJournalStore,
  parseConversationMealJournalPage,
} from './conversation-meal-journal-store'

describe('private read-only journal page codec and adapter', () => {
  it('is inert and executes one actual RPC with closed owned arguments', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: journalPage(), error: null }),
      from = vi.fn(() => {
        throw Error('no domain read')
      }),
      store = createSupabaseConversationMealJournalStore({ rpc, from } as unknown as ServiceClient)
    expect(rpc).not.toHaveBeenCalled()
    const page = await store.read(journalQuery())
    expect(page).toMatchObject({
      action: 'available',
      ownerId: journalQuery().ownerId,
      epoch: journalQuery().epoch,
      hasMore: false,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('read_conversation_meal_journal_page', {
      p_user_id: journalQuery().ownerId,
      p_expected_epoch: journalQuery().epoch,
      p_limit: 10,
      p_cursor: null,
    })
    expect(from).not.toHaveBeenCalled()
    if (page.action !== 'available' || page.items[0].kind !== 'command')
      throw Error('missing actual command')
    expect(page.items[0].command).toEqual(writerCommand())
    expect(Object.isFrozen(page.items[0].command.command.source)).toBe(true)
  })
  it('accepts actual historical edit receipt without inventing its absent operation body', () => {
    const e = journalEdit(),
      parsed = parseConversationMealEditHistoricalReceipt(e.receipt, e.command)
    expect(parsed).toEqual(e.receipt)
    const page = parseConversationMealJournalPage(
      journalPage([e, journalCommand('registered')]),
      journalQuery(),
    )
    expect(page.action).toBe('available')
  })
  it.each([
    { snapshot: { ...journalEdit().receipt.snapshot, private: true } },
    { owner_id: journalEdit().receipt.operation_id },
    { new_item_ids: journalEdit().receipt.removed_item_ids },
    { undo_expires_at: '2026-11-04T12:06:00.123457Z' },
    { applied_at: '2026-11-04T11:59:00.000001Z' },
  ])('retains closed historical receipt invariants %#', (patch) => {
    expect(() =>
      parseConversationMealEditHistoricalReceipt(
        { ...journalEdit().receipt, ...patch },
        writerBinding(),
      ),
    ).toThrow()
  })
  it.each([
    { owner_id: journalEdit().receipt.operation_id },
    { epoch: journalEdit().receipt.operation_id },
    {
      items: [
        {
          ...journalCommand(),
          source_input: {
            ...writerCommand().command,
            source: { channel: 'text', text: 'changed' },
          },
        },
      ],
    },
    { items: [{ ...journalCommand(), receipt: journalCommand('registered').receipt }] },
    { items: [{ ...journalCommand('registered'), receipt: null }] },
    {
      items: [
        {
          ...journalCommand('not_recorded'),
          decision: { ...journalCommand('not_recorded').decision, input_hash: 'f'.repeat(64) },
        },
      ],
    },
    { items: [{ ...journalEdit(), event_id: `edit/${journalEdit().receipt.operation_id}` }] },
    { has_more: true },
    { next_cursor: { at: journalCommand().at, id: journalCommand().event_id } },
    { secret: 'never strip a private field' },
  ])('rejects malformed or mixed actual page %#', (patch) => {
    expect(() =>
      parseConversationMealJournalPage({ ...journalPage(), ...patch }, journalQuery()),
    ).toThrow()
  })
  it('keeps ties in server C order and requires the actual last returned cursor', () => {
    const earlier = journalCommand(),
      later = anotherJournalCommand('10000000-0000-4000-8000-000000000009', earlier.at)
    const raw = {
        ...journalPage([later, earlier]),
        has_more: true,
        next_cursor: { at: earlier.at, id: earlier.event_id },
      },
      query = { ...journalQuery(), limit: 2 }
    expect(parseConversationMealJournalPage(raw, query).action).toBe('available')
    expect(() =>
      parseConversationMealJournalPage({ ...raw, items: [earlier, later] }, query),
    ).toThrow()
    expect(() =>
      parseConversationMealJournalPage(
        { ...raw, next_cursor: { at: later.at, id: later.event_id } },
        query,
      ),
    ).toThrow()
  })
  it('does not retry an unknown read and redacts errors', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('secret database credential')),
      store = createSupabaseConversationMealJournalStore({ rpc } as unknown as ServiceClient)
    await expect(store.read(journalQuery())).rejects.toMatchObject({
      status: 503,
      code: 'conversation_journal_unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
