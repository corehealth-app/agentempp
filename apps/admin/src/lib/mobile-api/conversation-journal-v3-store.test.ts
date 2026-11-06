import { describe, expect, it, vi } from 'vitest'
import {
  ConversationJournalV3ScopeRefusal,
  createConversationJournalV3Store,
} from './conversation-journal-v3-store'

const ownerId = 'c1450000-0000-4000-8000-000000000001',
  epoch = 'c1450000-0000-4000-8000-000000000002',
  at = '2026-11-05T12:00:01.000001Z',
  query = { ownerId, epoch, limit: 10, cursor: null }
function setup() {
  // A synthetic empty SQL page tests the adapter, not PostgreSQL persistence.
  const raw = {
      action: 'available',
      schema: 'conversation.journal-page-private.v3',
      owner_id: ownerId,
      epoch,
      observed_at: at,
      intakes: [],
      workouts: [],
      items: [],
      has_more: false,
      next_cursor: null,
      meal_page: {
        action: 'available',
        schema: 'conversation.journal-page-private.v2',
        owner_id: ownerId,
        epoch,
        observed_at: at,
        threads: [],
        items: [],
        has_more: false,
        next_cursor: null,
      },
    },
    rpc = vi.fn(
      async (_name: string, _args: Readonly<Record<string, unknown>>): Promise<unknown> => ({
        data: raw,
        error: null,
      }),
    ),
    checkCurrentScope = vi.fn(
      async (_identity: Readonly<{ ownerId: string; epoch: string }>) => true,
    ),
    store = createConversationJournalV3Store({ rpc }, { checkCurrentScope })
  return { raw, rpc, checkCurrentScope, store }
}
describe('private journal v3 physical read adapter', () => {
  it('makes exactly one readonly page RPC under mandatory original current scope', async () => {
    const h = setup(),
      result = await h.store.read(query)
    expect(result.action).toBe('available')
    expect(h.rpc.mock.calls).toEqual([
      [
        'read_conversation_journal_page_v3',
        {
          p_user_id: ownerId,
          p_expected_epoch: epoch,
          p_limit: 10,
          p_cursor: null,
        },
      ],
    ])
    expect(h.checkCurrentScope.mock.calls).toEqual([[{ ownerId, epoch }], [{ ownerId, epoch }]])
    expect(Object.isFrozen(result)).toBe(true)
  })
  it.each([
    'before',
    'after',
    'throw',
  ] as const)('keeps %s scope refusal sticky, even if a later call has invalid arguments', async (when) => {
    const h = setup()
    if (when === 'before') h.checkCurrentScope.mockResolvedValueOnce(false)
    else if (when === 'throw')
      h.checkCurrentScope.mockRejectedValueOnce(new Error('Mapping lookup failed'))
    else h.checkCurrentScope.mockResolvedValueOnce(true).mockResolvedValueOnce(false)
    await expect(h.store.read(query)).rejects.toBeInstanceOf(ConversationJournalV3ScopeRefusal)
    h.checkCurrentScope.mockResolvedValue(true)
    await expect(h.store.read({ ...query, epoch: 'bad' })).rejects.toBeInstanceOf(
      ConversationJournalV3ScopeRefusal,
    )
    expect(h.rpc).toHaveBeenCalledTimes(when === 'after' ? 1 : 0)
  })
  it('performs the post-check on SDK throw and never retries or writes', async () => {
    const h = setup()
    h.rpc.mockRejectedValueOnce(new Error('SDK transport uncertain'))
    await expect(h.store.read(query)).rejects.toMatchObject({
      status: 503,
      code: 'conversation_journal_unavailable',
    })
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
    expect(h.rpc).toHaveBeenCalledOnce()
  })
  it('detaches SDK aliases before the asynchronous post-observer', async () => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValueOnce(true).mockImplementationOnce(async () => {
      h.raw.observed_at = '2020-01-01T00:00:00.000001Z'
      return true
    })
    const value = await h.store.read(query)
    expect(value.action).toBe('available')
    if (value.action !== 'available') throw new Error('Missing original page')
    expect(value.observedAt).toBe(at)
  })
  it('pins transport and observer methods to their original receivers', async () => {
    const h = setup(),
      rpcPort = { rpc: h.rpc },
      scopePort = { checkCurrentScope: h.checkCurrentScope },
      store = createConversationJournalV3Store(rpcPort, scopePort)
    rpcPort.rpc = vi.fn(async () => {
      throw new Error('Replacement must not run')
    })
    scopePort.checkCurrentScope = vi.fn(async () => false)
    expect((await store.read(query)).action).toBe('available')
    expect(rpcPort.rpc).not.toHaveBeenCalled()
    expect(scopePort.checkCurrentScope).not.toHaveBeenCalled()
    expect(h.rpc).toHaveBeenCalledOnce()
  })
})
