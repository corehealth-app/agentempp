import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { journalAuth, journalClinical } from './__fixtures__/conversation-journal'
import {
  encodeConversationJournalV3Cursor,
  parseConversationJournalV3Page,
} from './conversation-journal-v3-contracts'
import { createConversationMealQuestionOriginsService } from './conversation-meal-question-origins'
import { mealOriginPage } from './testing/conversation-meal-question-origins-fixture'

function setup() {
  const page = mealOriginPage(),
    owner = page.owner_id,
    epoch = page.epoch,
    authID = '10000000-0000-4000-8000-000000000099',
    auth = {
      ...journalAuth(),
      userId: owner,
      authUserId: authID,
      accessToken: 'synthetic-unit-token',
      identity: {
        id: authID,
        email: 'unit@example.invalid',
        emailConfirmedAt: '2026-01-01T00:00:00Z',
      },
      patient: { ...journalAuth().patient, id: owner, authUserId: authID },
    },
    verifyAccessToken = vi.fn(async () => ({
      id: authID,
      email: 'unit@example.invalid',
      emailConfirmedAt: '2026-01-01T00:00:00Z',
    })),
    loadPatient = vi.fn(async () => ({
      id: owner,
      authUserId: authID,
      email: 'unit@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    })),
    isAdmin = vi.fn(async () => false),
    profile = { ...journalClinical(page.observed_at), epoch },
    capture = vi.fn(async () => structuredClone(profile)),
    rpc = vi.fn(async (_name: string, _args: Record<string, unknown>) => ({
      data: page,
      error: null,
    })),
    from = vi.fn(() => {
      throw new Error('No unrelated SDK access')
    }),
    db = { rpc, from } as unknown as ServiceClient,
    service = createConversationMealQuestionOriginsService(db, {
      auth: { verifyAccessToken, loadPatient, isAdmin },
      clinical: { capture },
    }),
    run = (input = { limit: 10, cursor: null as string | null }) => service.read(auth, epoch, input)
  return {
    page,
    auth,
    owner,
    epoch,
    verifyAccessToken,
    loadPatient,
    isAdmin,
    capture,
    rpc,
    from,
    run,
  }
}

describe('cold meal question origin discovery', () => {
  it('validates two distinct initial UNIT capsules through the existing complete private parser', () => {
    const page = mealOriginPage(),
      result = parseConversationJournalV3Page(page, {
        ownerId: page.owner_id,
        epoch: page.epoch,
        limit: 10,
        cursor: null,
      })
    expect(result.action).toBe('available')
  })
  it('returns genuine lookup-only lineage for two initial questions with no write or answer authority', async () => {
    const f = setup(),
      result = await f.run()
    expect(result.schema).toBe('conversation.meal-question-origins.v1')
    expect(result.mode).toBe('lookup_only')
    expect(result.auth_user_id).toBe(f.auth.authUserId)
    expect(result.items.map((i) => i.intake.intake_id)).toEqual(
      f.page.items.map((i) => i.intake_id),
    )
    expect(result.items[0].selection.command.command_id).not.toBe(
      result.items[1].selection.command.command_id,
    )
    expect(Object.keys(result.items[0]).sort()).toEqual(['intake', 'selection', 'source'])
    expect(JSON.stringify(result)).not.toMatch(
      /question_key|head_revision|parent_decision_hash|write_authority|terminal_receipt/,
    )
    expect(result.items[0].selection.command.input_hash).toBe(
      f.page.intakes[0].selection.command.input_hash,
    )
    expect(result.items[0].source).toEqual(f.page.intakes[0].source_input.source)
    expect(Object.isFrozen(result.items[0].selection.command)).toBe(true)
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.rpc).toHaveBeenCalledWith('read_conversation_journal_page_v3', {
      p_user_id: f.owner,
      p_expected_epoch: f.epoch,
      p_limit: 10,
      p_cursor: null,
    })
    expect(f.from).not.toHaveBeenCalled()
    expect(f.capture).toHaveBeenCalledTimes(2)
  })
  it('keeps empty candidate pages traversable when more real history remains', async () => {
    const f = setup()
    f.page.meal_page.threads.forEach((t) => {
      t.continuation = null
    })
    f.page.has_more = true
    const last = f.page.items.at(-1)
    if (!last) throw new Error('The synthetic page must have two original events')
    f.page.next_cursor = { at: last.at, id: last.event_id }
    const result = await f.run({ limit: 2, cursor: null })
    expect(result.items).toEqual([])
    expect(result.has_more).toBe(true)
    expect(result.next_cursor).toBeTypeOf('string')
    const second = setup()
    second.page.intakes = []
    second.page.items = []
    second.page.meal_page.threads = []
    second.page.meal_page.items = []
    await second.run({ limit: 2, cursor: result.next_cursor })
    expect(second.rpc.mock.calls[0][1].p_cursor).toEqual(f.page.next_cursor)
  })
  it('pins SDK data before the post-read observation can mutate it', async () => {
    const f = setup(),
      original = structuredClone(f.page)
    f.capture.mockImplementation(async () => {
      if (f.rpc.mock.calls.length) f.page.intakes[0].selection.command.input_hash = 'f'.repeat(64)
      return { ...journalClinical(original.observed_at), epoch: f.epoch }
    })
    expect((await f.run()).items[0].selection.command.input_hash).toBe(
      original.intakes[0].selection.command.input_hash,
    )
  })
  it('omits fulfilled and unrelated terminal parents while preserving the two original rows', async () => {
    const f = setup(),
      threads = f.page.meal_page.threads
    threads[0].continuation = {
      revision: 1,
      question: null,
      fulfilled_by: '10000000-0000-4000-8000-000000000041',
    }
    threads[1].terminal_receipt.reason = 'future'
    threads[1].continuation = null
    expect((await f.run()).items).toEqual([])
    expect(f.page.items).toHaveLength(2)
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('projects origins in real primary event order independent of dependency array order', async () => {
    const f = setup(),
      ids = f.page.items.map((item) => item.intake_id)
    f.page.intakes.reverse()
    expect((await f.run()).items.map((item) => item.intake.intake_id)).toEqual(ids)
  })
  it.each([
    'owner',
    'epoch',
  ])('rejects a cursor belonging to another %s without a database read', async (field) => {
    const f = setup(),
      anchor = { at: f.page.items[0].at, id: f.page.items[0].event_id },
      cursor = encodeConversationJournalV3Cursor(
        field === 'owner' ? f.auth.authUserId : f.owner,
        field === 'epoch' ? f.auth.authUserId : f.epoch,
        anchor,
      )
    await expect(f.run({ limit: 10, cursor })).rejects.toMatchObject({ status: 409 })
    expect(f.rpc).not.toHaveBeenCalled()
  })
  it('does not retry an uncertain readonly call and still observes Auth afterward', async () => {
    const f = setup()
    f.rpc.mockRejectedValue(new Error('Unknown transport outcome'))
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
  })
  it.each([
    'wrong_owner',
    'wrong_epoch',
    'wrong_child',
    'wrong_hash',
    'extra_key',
    'future_clock',
  ])('refuses corrupted private %s', async (kind) => {
    const f = setup()
    if (kind === 'wrong_owner') f.page.owner_id = f.auth.authUserId
    if (kind === 'wrong_epoch') f.page.epoch = f.auth.authUserId
    if (kind === 'wrong_child')
      f.page.intakes[0].selection.command.command_id = f.page.intakes[0].intake.intake_id
    if (kind === 'wrong_hash') f.page.intakes[0].selection.command.input_hash = 'f'.repeat(64)
    if (kind === 'extra_key') Object.assign(f.page, { grant_write: true })
    if (kind === 'future_clock') f.page.observed_at = '2099-01-01T00:00:00.000001Z'
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'signed_out',
    'admin',
    'owner_changed',
    'epoch_changed',
  ])('rejects %s before reading origins', async (kind) => {
    const f = setup()
    if (kind === 'signed_out') f.verifyAccessToken.mockResolvedValue(null as never)
    if (kind === 'admin') f.isAdmin.mockResolvedValue(true)
    if (kind === 'owner_changed')
      f.loadPatient.mockResolvedValue({ ...(await f.loadPatient()), id: f.auth.authUserId })
    if (kind === 'epoch_changed')
      f.capture.mockResolvedValue({ ...(await f.capture()), epoch: f.auth.authUserId })
    await expect(f.run()).rejects.toBeDefined()
    expect(f.rpc).not.toHaveBeenCalled()
  })
  it('revalidates the original Auth after the read and never retries it', async () => {
    const f = setup()
    f.rpc.mockImplementation(async () => {
      f.verifyAccessToken.mockResolvedValue(null as never)
      return { data: f.page, error: null }
    })
    await expect(f.run()).rejects.toMatchObject({ status: 401 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
})
