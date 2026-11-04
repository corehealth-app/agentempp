import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  anotherJournalCommand,
  journalAuth,
  journalClinical,
  journalCommand,
} from './__fixtures__/conversation-journal'
import { replyPresentation } from './__fixtures__/conversation-meal-reply'
import {
  threadGoldenPage,
  threadPage,
  threadQuery,
  threadSavedReport,
} from './__fixtures__/conversation-thread-page'
import {
  createConversationMealThreadPageService,
  decodeConversationMealThreadCursor,
  encodeConversationMealThreadCursor,
} from './conversation-meal-thread-page-service'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { currentClinicalError, readCurrentClinicalState } from './current-clinical-state'

function setup(raw: unknown = threadPage()) {
  const read = vi.fn().mockResolvedValue(raw),
    capture = vi
      .fn()
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockResolvedValueOnce(journalClinical()),
    readHistorical = vi.fn().mockResolvedValue(null)
  const service = createConversationMealThreadPageService({} as ServiceClient, {
    store: { read },
    clinical: { capture },
    presentation: { readHistorical },
  })
  return {
    read,
    capture,
    readHistorical,
    service,
    request: { epoch: threadQuery().epoch, limit: 10, cursor: null },
  }
}
describe('real public v2 read projection', () => {
  it('reads actual linked historical feedback with real parent/child binding and never enriches on GET', async () => {
    const raw = threadPage(),
      fx = raw.items[0] as ReturnType<
        typeof import('./__fixtures__/conversation-thread-page').threadFulfillment
      >
    Object.assign(fx, {
      feedback_ref: {
        schema: 'registration.feedback.v2',
        registration_id: fx.receipt.registration_id,
      },
    })
    const read = vi.fn().mockResolvedValue(raw),
      capture = vi
        .fn()
        .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
        .mockResolvedValueOnce(journalClinical()),
      readHistorical = vi.fn().mockResolvedValue(null),
      ensureOriginal = vi.fn()
    const linkedPresentation = { readHistorical, ensureOriginal }
    const service = createConversationMealThreadPageService({} as ServiceClient, {
      store: { read },
      clinical: { capture },
      presentation: { readHistorical: vi.fn() },
      linkedPresentation,
    })
    const result = await service.read(journalAuth(), { epoch: raw.epoch, limit: 10, cursor: null })
    expect(result.items[0]).toMatchObject({ kind: 'fulfillment', feedback: null })
    expect(readHistorical).toHaveBeenCalledWith({
      auth: journalAuth(),
      binding: {
        parentBinding: raw.threads[0].parent_binding,
        childBinding: fx.child_binding,
        parentDecisionHash: raw.threads[0].terminal_receipt.decision_hash,
        receipt: fx.receipt,
      },
    })
    expect(ensureOriginal).not.toHaveBeenCalled()
  })

  it('publishes qualified child historical sections using only actual common receipt facts', async () => {
    const raw = threadPage(),
      fx = raw.items[0] as ReturnType<
        typeof import('./__fixtures__/conversation-thread-page').threadFulfillment
      >,
      presentation = replyPresentation()
    Object.assign(fx, {
      feedback_ref: {
        schema: 'registration.feedback.v2',
        registration_id: fx.receipt.registration_id,
      },
    })
    const current = readCurrentClinicalState(journalClinical(), raw.owner_id)
    presentation.original.registration_id = fx.receipt.registration_id
    presentation.original.local_date = fx.receipt.local_date
    presentation.provenance.command_id = fx.child_binding.command_id
    presentation.provenance.epoch = raw.epoch
    presentation.provenance.observed_at = current.observed_at
    presentation.current_policy = structuredClone(projectCurrentClinicalPublicPolicy(current))
    presentation.recorded.meal_kind = fx.receipt.meal_type
    presentation.recorded.items = fx.receipt.log_ids.map((id, index) => ({
      ...presentation.recorded.items[index % presentation.recorded.items.length],
      log_id: id,
    }))
    const f = setup(raw),
      readHistorical = vi.fn().mockResolvedValue(presentation),
      capture = vi
        .fn()
        .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
        .mockResolvedValueOnce(journalClinical())
    const service = createConversationMealThreadPageService({} as ServiceClient, {
      store: { read: f.read },
      clinical: { capture },
      presentation: { readHistorical: f.readHistorical },
      linkedPresentation: { readHistorical },
    })
    const result = await service.read(journalAuth(), f.request)
    expect(result.items[0]).toMatchObject({ kind: 'fulfillment', feedback: presentation })
    expect(f.readHistorical).not.toHaveBeenCalled()
    expect(readHistorical).toHaveBeenCalledTimes(1)
  })

  it('matches the five-variant literal public golden for native consumers', async () => {
    const f = setup(threadGoldenPage())
    const expected = JSON.parse(
      readFileSync(
        new URL('./__fixtures__/conversation-thread-page-public.json', import.meta.url),
        'utf8',
      ),
    )
    expect(await f.service.read(journalAuth(), f.request)).toEqual(expected.data)
  })

  it('returns the original negative and genuine child effect distinctly, no private context and no v1 fiction', async () => {
    const f = setup()
    expect(f.read).not.toHaveBeenCalled()
    const p = await f.service.read(journalAuth(), f.request)
    expect(p.schema).toBe('conversation.journal-page.v2')
    expect(p.auth_user_id).toBe(journalAuth().authUserId)
    expect(p.auth_user_id).not.toBe(p.owner_id)
    expect(p.threads[0].terminal_receipt?.reason).toBe('missing_quantity')
    expect(p.items[0]).toMatchObject({
      kind: 'fulfillment',
      receipt: { schema: 'conversation.meal-continuation-effect.v1' },
      feedback: null,
    })
    expect(JSON.stringify(p)).not.toMatch(
      /feedback_ref|source_context|snapshot|model|tokens|before_group/,
    )
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
    expect(f.readHistorical).not.toHaveBeenCalled()
  })
  it('applies the whole 240000-byte UTF8 cap atomically with new descriptors and continues without skipping', async () => {
    const a = threadSavedReport(
        anotherJournalCommand(
          '10000000-0000-4000-8000-000000000009',
          journalCommand().at,
          'registered',
        ),
      ),
      b = threadSavedReport(journalCommand('registered')),
      raw = { ...threadPage(), threads: [b.descriptor, a.descriptor], items: [a.event, b.event] },
      fa = feedback(a.event.receipt, 'a'.repeat(16000)),
      fb = feedback(b.event.receipt, 'a'.repeat(16000))
    const run = async () => {
      const f = setup(raw)
      f.readHistorical.mockImplementation(async ({ command }) =>
        command.commandId === a.descriptor.thread_id ? fa : fb,
      )
      return f.service.read(journalAuth(), f.request)
    }
    const small = await run()
    expect(small.items).toHaveLength(2)
    const remaining = 240000 - Buffer.byteLength(JSON.stringify(small), 'utf8')
    expect(remaining).toBeGreaterThan(0)
    fb.sections[0].text += 'a'.repeat(remaining)
    expect(fb.sections[0].text.length).toBeLessThanOrEqual(64000)
    const exact = await run()
    expect(Buffer.byteLength(JSON.stringify(exact), 'utf8')).toBe(240000)
    fb.sections[0].text += 'é'
    const capped = await run()
    expect(capped.items).toHaveLength(1)
    expect(capped.threads.map((t) => t.thread_id)).toEqual([a.descriptor.thread_id])
    expect(capped.has_more).toBe(true)
    const cursor = capped.next_cursor
    if (!cursor) throw new Error('Expected continuation')
    const anchor = decodeConversationMealThreadCursor(
      cursor,
      threadQuery().ownerId,
      threadQuery().epoch,
    )
    expect(anchor).toEqual({ at: a.event.at, id: a.event.event_id })
    const next = setup({ ...raw, threads: [b.descriptor], items: [b.event] })
    const result = await next.service.read(journalAuth(), { ...next.request, cursor })
    expect(result.items.map((e) => e.event_id)).toEqual([b.event.event_id])
    expect(result.has_more).toBe(false)
  })
  it('keeps a bounded single original effect with its independently capped optional presentation', async () => {
    const saved = threadSavedReport(journalCommand('registered'))
    const f = setup({ ...threadPage(), threads: [saved.descriptor], items: [saved.event] })
    const value = feedback(saved.event.receipt, 'é'.repeat(16000))
    f.readHistorical.mockResolvedValue(value)
    const p = await f.service.read(journalAuth(), f.request)
    expect(p.items).toHaveLength(
      1,
    ) /* feedback codec independently caps each presentation at200000 */
  })
  it('publishes actual historical facts on optional feedback failure without sealing or recapture', async () => {
    const saved = threadSavedReport(journalCommand('registered'))
    const f = setup({ ...threadPage(), threads: [saved.descriptor], items: [saved.event] })
    f.readHistorical.mockRejectedValue(new Error('private frozen capture unavailable'))
    const p = await f.service.read(journalAuth(), f.request)
    expect(p.items[0]).toMatchObject({
      kind: 'report',
      status: 'registered',
      receipt: saved.event.receipt,
      feedback: null,
    })
    expect(f.readHistorical).toHaveBeenCalledTimes(1)
  })
  it('accepts a stable current HOLD policy while leaving unqualified linked feedback null', async () => {
    const f = setup()
    const before = journalClinical('2026-11-04T12:02:00.000001Z'),
      after = journalClinical()
    for (const s of [before, after]) {
      Object.assign(s.health_state, {
        hold_active: true,
        safety_revision: '1',
        last_declared_at: '2026-11-04T12:00:00.000001Z',
        items: [{ code: 'reduced_intake', declared_at: '2026-11-04T12:00:00.000001Z' }],
      })
      Object.assign(required(s.safety), { hold_active: true, no_plan: false, hide_protein: false })
    }
    f.capture.mockReset().mockResolvedValueOnce(before).mockResolvedValueOnce(after)
    const p = await f.service.read(journalAuth(), f.request)
    expect(p.items[0]).toMatchObject({ kind: 'fulfillment', feedback: null })
  })
  it('rejects a substituted private port and Auth/patient mismatch before publication', async () => {
    const f = setup()
    f.read.mockResolvedValue({ ...threadPage(), source_context: {} })
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 503 })
    const g = setup(),
      auth = journalAuth()
    auth.patient.authUserId = threadQuery().epoch
    await expect(g.service.read(auth, g.request)).rejects.toMatchObject({ status: 403 })
    expect(g.read).not.toHaveBeenCalled()
  })
  it('captures request/auth/callbacks before the first await', async () => {
    const f = setup(),
      auth = journalAuth(),
      input = { ...f.request }
    f.capture.mockImplementationOnce(async () => {
      auth.authUserId = threadQuery().epoch
      input.limit = 1
      return journalClinical('2026-11-04T12:02:00.000001Z')
    })
    const p = await f.service.read(auth, input)
    expect(p.auth_user_id).toBe(journalAuth().authUserId)
    expect(f.read).toHaveBeenCalledWith(threadQuery())
  })
  it.each([
    'x'.repeat(1025),
    'not_base64!',
    Buffer.from(
      JSON.stringify({
        v: 2,
        owner_id: threadQuery().ownerId,
        epoch: threadQuery().epoch,
        at: threadPage().items[0].at,
        id: threadPage().items[0].event_id,
        extra: 'private',
      }),
    ).toString('base64url'),
  ])('rejects cursor bloat and noncanonical aliases before current-profile reads', async (cursor) => {
    const f = setup()
    await expect(f.service.read(journalAuth(), { ...f.request, cursor })).rejects.toThrow()
    expect(f.read).not.toHaveBeenCalled()
    expect(f.capture).not.toHaveBeenCalled()
  })
  it('canonical cursor isolates v2 from v1 and binds actual patient/epoch', () => {
    const q = threadQuery(),
      anchor = { at: threadPage().items[0].at, id: threadPage().items[0].event_id }
    const c = encodeConversationMealThreadCursor(q.ownerId, q.epoch, anchor)
    expect(decodeConversationMealThreadCursor(c, q.ownerId, q.epoch)).toEqual(anchor)
    expect(() => decodeConversationMealThreadCursor(c, q.epoch, q.epoch)).toThrow()
    expect(() =>
      decodeConversationMealThreadCursor(
        Buffer.from(
          JSON.stringify({ v: 1, owner_id: q.ownerId, epoch: q.epoch, ...anchor }),
        ).toString('base64url'),
        q.ownerId,
        q.epoch,
      ),
    ).toThrow()
  })
  it('rejects current policy drift after read without publishing old facts', async () => {
    const f = setup(),
      after = journalClinical()
    after.profile_hash = 'e'.repeat(64)
    f.capture
      .mockReset()
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockResolvedValueOnce(after)
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
  })
  it('rejects reset before RPC', async () => {
    const f = setup()
    f.capture.mockReset().mockRejectedValue(currentClinicalError('changed'))
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
    expect(f.read).not.toHaveBeenCalled()
  })
  it('does not retry unknown read failures or construct any writer/provider', async () => {
    const f = setup()
    f.read.mockRejectedValue(new Error('private'))
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 503 })
    expect(f.read).toHaveBeenCalledTimes(1)
  })
})

function feedback(
  receipt: NonNullable<ReturnType<typeof journalCommand>['receipt']>,
  text: string,
) {
  const observed = journalClinical('2026-11-04T12:02:30.000001Z'),
    policy = projectCurrentClinicalPublicPolicy(
      readCurrentClinicalState(observed, threadQuery().ownerId),
    )
  return {
    schema: 'conversation.feedback-presentation.v1',
    mode: 'historical',
    assistant: 'Flow AI',
    status: 'available',
    format: 'sections',
    original: {
      schema: 'registration.feedback.v2',
      registration_id: receipt.registration_id,
      kind: 'meal',
      local_date: receipt.local_date,
    },
    current_policy: structuredClone(policy),
    provenance: {
      epoch: threadQuery().epoch,
      command_id: receipt.command_id,
      observed_at: observed.observed_at,
    },
    recorded: {
      kind: 'meal',
      meal_kind: receipt.meal_type,
      items: receipt.log_ids.map((id) => ({
        log_id: id,
        food_name: 'arroz sintetico',
        quantity_g: 100,
        quantity: { value: 100, unit: 'g', estimated: false, reference_id: null },
        nutrition_source: 'user_kcal',
        kcal: 130,
        protein_g: 2.3,
        carbs_g: 28.2,
        fat_g: 0.2,
      })),
      totals: { kcal: 130, protein_g: 2.3, carbs_g: 28.2, fat_g: 0.2 },
    },
    sections: ['saved', 'items', 'summary', 'day', 'block', 'education'].map((key) => ({
      key,
      text,
    })),
  }
}

function required<T>(v: T | null | undefined): T {
  if (v === null || v === undefined) throw new Error('Required synthetic fixture absent')
  return v
}
