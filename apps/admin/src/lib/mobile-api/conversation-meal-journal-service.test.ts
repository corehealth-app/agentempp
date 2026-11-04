import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  anotherJournalCommand,
  journalAuth,
  journalClinical,
  journalCommand,
  journalEdit,
  journalFixturePage,
  journalPage,
  journalQuery,
} from './__fixtures__/conversation-journal'
import { writerCommand, writerEpoch } from './__fixtures__/conversation-meal-writer'
import {
  createConversationMealJournalService,
  decodeConversationMealJournalCursor,
  encodeConversationMealJournalCursor,
} from './conversation-meal-journal-service'
import { parseConversationMealJournalPage } from './conversation-meal-journal-store'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { currentClinicalError, readCurrentClinicalState } from './current-clinical-state'

function fixture(raw = journalPage([journalEdit(), journalCommand('not_recorded')])) {
  const read = vi.fn().mockResolvedValue(parseConversationMealJournalPage(raw, journalQuery())),
    capture = vi
      .fn()
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockResolvedValueOnce(journalClinical()),
    readHistorical = vi.fn().mockResolvedValue(null),
    store = { read },
    clinical = { capture },
    presentation = { readHistorical },
    service = createConversationMealJournalService({} as ServiceClient, {
      store,
      clinical,
      presentation,
    })
  return {
    read,
    capture,
    readHistorical,
    store,
    clinical,
    presentation,
    service,
    request: { epoch: writerEpoch, limit: 10, cursor: null },
  }
}
describe('public journal read-only projection and scope', () => {
  it('matches the frozen cross-language public packet exactly', async () => {
    const f = fixture(journalFixturePage()),
      expected = JSON.parse(
        readFileSync(
          new URL('./__fixtures__/conversation-journal-public.json', import.meta.url),
          'utf8',
        ),
      )
    expect(await f.service.read(journalAuth(), f.request)).toEqual(expected.data)
  })
  it('returns closed terminal delivery and sanitized edit events under actual Auth not patient UUID', async () => {
    const f = fixture(),
      page = await f.service.read(journalAuth(), f.request)
    expect(page).toMatchObject({
      schema: 'conversation.journal-page.v1',
      auth_user_id: journalAuth().authUserId,
      owner_id: writerCommand().ownerId,
      epoch: writerEpoch,
      observed_at: journalClinical().observed_at,
      has_more: false,
      next_cursor: null,
    })
    expect(page.auth_user_id).not.toBe(page.owner_id)
    expect(Object.keys(page).sort()).toEqual(
      [
        'schema',
        'auth_user_id',
        'owner_id',
        'epoch',
        'observed_at',
        'items',
        'has_more',
        'next_cursor',
      ].sort(),
    )
    expect(page.items[0]).toMatchObject({
      kind: 'edit',
      event_id: journalEdit().event_id,
      result: {
        schema: 'conversation.meal-edit-result.v1',
        input_hash: writerCommand().inputHash,
        receipt: { schema: 'conversation.meal-edit-effect-public.v1', input_hash: 'e'.repeat(64) },
      },
    })
    expect(Object.keys(page.items[0]).sort()).toEqual(['event_id', 'at', 'kind', 'result'].sort())
    const entry = page.items[1]
    expect(entry).toMatchObject({
      kind: 'command',
      original_command: writerCommand().command,
      result: { status: 'not_recorded', reason: 'future' },
      terminal_receipt: {
        schema: 'conversation.meal-decision-public.v1',
        decision_hash: 'd'.repeat(64),
      },
    })
    expect(JSON.stringify(page)).not.toMatch(
      /snapshot|daily_balance|semantic_result_hash|attempt_id|source_hash|accessToken|source_input|before_group|clinical/,
    )
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
    expect(f.readHistorical).not.toHaveBeenCalled()
  })
  it('uses current guarded historical feedback only for saved entries and retains factual success on failure', async () => {
    const f = fixture(journalPage([journalCommand('registered')]))
    f.readHistorical.mockRejectedValue(new Error('private source unavailable'))
    const page = await f.service.read(journalAuth(), f.request)
    expect(page.items[0].result).toMatchObject({ status: 'saved', feedback: null })
    expect(f.readHistorical).toHaveBeenCalledTimes(1)
    expect(f.readHistorical.mock.calls[0][0]).toMatchObject({
      command: writerCommand(),
      serverBinding: journalCommand().command,
    })
    expect(f.capture.mock.invocationCallOrder[0]).toBeLessThan(f.read.mock.invocationCallOrder[0])
    expect(f.read.mock.invocationCallOrder[0]).toBeLessThan(
      f.readHistorical.mock.invocationCallOrder[0],
    )
    expect(f.readHistorical.mock.invocationCallOrder[0]).toBeLessThan(
      f.capture.mock.invocationCallOrder[1],
    )
  })
  it.each([
    'profile_hash',
    'body',
    'health_state',
  ])('refuses changed current policy/scope %s without a mixed page', async (key) => {
    const f = fixture(),
      changed = journalClinical()
    if (key === 'profile_hash') changed.profile_hash = 'e'.repeat(64)
    else if (key === 'body') changed.body.weight_kg = 81
    else {
      changed.health_state.safety_revision = '2'
      changed.health_state.last_declared_at = '2026-11-04T12:00:00.000001Z'
    }
    f.capture
      .mockReset()
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockResolvedValueOnce(changed)
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
  })
  it('preserves the actual current-source changed-epoch refusal', async () => {
    const f = fixture()
    f.capture
      .mockReset()
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockRejectedValueOnce(currentClinicalError('changed'))
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
  })
  it('can include a legitimate new event read between the two profile observations', async () => {
    const command = anotherJournalCommand(
        '10000000-0000-4000-8000-000000000009',
        '2026-11-04T12:02:30.000001Z',
      ),
      f = fixture(journalPage([command]))
    expect((await f.service.read(journalAuth(), f.request)).items[0].at).toBe(command.at)
  })
  it('snapshots auth, request and callback ports before await', async () => {
    const f = fixture(),
      auth = journalAuth(),
      request = { ...f.request },
      originalRead = f.read
    f.capture.mockImplementationOnce(async () => {
      auth.authUserId = journalEdit().receipt.operation_id
      request.epoch = journalEdit().receipt.operation_id
      f.store.read = vi.fn().mockRejectedValue(new Error('replaced callback'))
      return journalClinical('2026-11-04T12:02:00.000001Z')
    })
    const promise = f.service.read(auth, request),
      result = await promise
    expect(result.auth_user_id).toBe(journalAuth().authUserId)
    expect(originalRead).toHaveBeenCalledWith(journalQuery())
  })
  it('binds a canonical opaque cursor to owner/epoch and rejects alternate encodings and extra fields', () => {
    const anchor = { at: journalCommand().at, id: journalCommand().event_id },
      cursor = encodeConversationMealJournalCursor(journalQuery().ownerId, writerEpoch, anchor)
    expect(
      decodeConversationMealJournalCursor(cursor, journalQuery().ownerId, writerEpoch),
    ).toEqual(anchor)
    expect(() =>
      decodeConversationMealJournalCursor(cursor, journalEdit().receipt.operation_id, writerEpoch),
    ).toThrow()
    expect(() =>
      decodeConversationMealJournalCursor(`${cursor}=`, journalQuery().ownerId, writerEpoch),
    ).toThrow()
    const extra = Buffer.from(
      JSON.stringify({
        v: 1,
        owner_id: journalQuery().ownerId,
        epoch: writerEpoch,
        ...anchor,
        extra: true,
      }),
    ).toString('base64url')
    expect(() =>
      decodeConversationMealJournalCursor(extra, journalQuery().ownerId, writerEpoch),
    ).toThrow()
  })
  it('preserves SQL keyset cursor and pending entries without a terminal receipt or ACK', async () => {
    const first = anotherJournalCommand(
        '10000000-0000-4000-8000-000000000009',
        journalCommand().at,
      ),
      raw = {
        ...journalPage([first]),
        has_more: true,
        next_cursor: { at: first.at, id: first.event_id },
      },
      f = fixture()
    f.read.mockResolvedValue(parseConversationMealJournalPage(raw, { ...journalQuery(), limit: 1 }))
    const page = await f.service.read(journalAuth(), { ...f.request, limit: 1 })
    expect(page.items[0]).toMatchObject({ result: { status: 'pending' }, terminal_receipt: null })
    expect(page.has_more).toBe(true)
    expect(
      decodeConversationMealJournalCursor(
        required(page.next_cursor),
        journalQuery().ownerId,
        writerEpoch,
      ),
    ).toEqual(raw.next_cursor)
  })
  it.each([
    'absent',
    'stale_epoch',
    'cursor_conflict',
    'event_conflict',
  ] as const)('fails closed on SQL refusal %s without presentation', async (action) => {
    const f = fixture()
    f.read.mockResolvedValue({ action })
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
    expect(f.readHistorical).not.toHaveBeenCalled()
  })
  it('stops before a whole entry above 240000 UTF8 bytes and continues from the last included event', async () => {
    const first = anotherJournalCommand(
        '10000000-0000-4000-8000-000000000009',
        journalCommand().at,
        'registered',
      ),
      last = journalCommand('registered'),
      f = fixture(journalPage([first, last]))
    f.readHistorical.mockImplementation(async ({ command, receipt }) =>
      feedback(command.commandId, receipt, 'é'.repeat(14000)),
    )
    const page = await f.service.read(journalAuth(), f.request)
    expect(Buffer.byteLength(JSON.stringify(page), 'utf8')).toBeLessThanOrEqual(240000)
    expect(page.items).toHaveLength(1)
    expect(page.items[0].event_id).toBe(first.event_id)
    expect(page.has_more).toBe(true)
    const anchor = decodeConversationMealJournalCursor(
      required(page.next_cursor),
      journalQuery().ownerId,
      writerEpoch,
    )
    expect(anchor).toEqual({ at: first.at, id: first.event_id })
    f.read.mockResolvedValueOnce(
      parseConversationMealJournalPage(journalPage([last]), { ...journalQuery(), cursor: anchor }),
    )
    f.capture
      .mockResolvedValueOnce(journalClinical('2026-11-04T12:02:00.000001Z'))
      .mockResolvedValueOnce(journalClinical())
    const next = await f.service.read(journalAuth(), { ...f.request, cursor: page.next_cursor })
    expect(next.items.map((e) => e.event_id)).toEqual([last.event_id])
    expect(next.has_more).toBe(false)
    expect(next.next_cursor).toBeNull()
  })
  it('rejects a mixed feedback policy instead of forwarding numbers under an unrelated observation', async () => {
    const f = fixture(journalPage([journalCommand('registered')])),
      value = feedback(
        writerCommand().commandId,
        required(journalCommand('registered').receipt),
        'ok',
      )
    value.current_policy.hide.calories = true
    f.readHistorical.mockResolvedValue(value)
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
  })
  it('refuses a mismatched Auth-patient mapping before observations or history', async () => {
    const f = fixture(),
      auth = journalAuth()
    auth.patient.authUserId = journalEdit().receipt.operation_id
    await expect(f.service.read(auth, f.request)).rejects.toMatchObject({ status: 403 })
    expect(f.capture).not.toHaveBeenCalled()
    expect(f.read).not.toHaveBeenCalled()
  })
  it('does not trust an extra private field from a substituted typed port', async () => {
    const f = fixture()
    f.read.mockResolvedValue({
      ...parseConversationMealJournalPage(journalPage(), journalQuery()),
      private_context: 'never publish',
    })
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 503 })
  })
  it('rejects a decision sealed after the final server observation', async () => {
    const command = journalCommand('not_recorded')
    required(command.decision).sealed_at = '2026-11-04T12:04:00.000001Z'
    const f = fixture(journalPage([command]))
    await expect(f.service.read(journalAuth(), f.request)).rejects.toMatchObject({ status: 409 })
  })
  it('includes the exact 240000-byte packet and keeps the next whole entry when one more byte would overflow', async () => {
    const first = anotherJournalCommand(
        '10000000-0000-4000-8000-000000000009',
        journalCommand().at,
        'registered',
      ),
      second = journalCommand('registered'),
      firstFeedback = feedback(
        first.command.command_id,
        required(first.receipt),
        'a'.repeat(16000),
      ),
      secondFeedback = feedback(
        writerCommand().commandId,
        required(second.receipt),
        'a'.repeat(16000),
      )
    const render = async () => {
      const f = fixture(journalPage([first, second]))
      f.readHistorical.mockImplementation(async ({ command }) =>
        command.commandId === first.command.command_id ? firstFeedback : secondFeedback,
      )
      return f.service.read(journalAuth(), f.request)
    }
    const small = await render(),
      remaining = 240000 - Buffer.byteLength(JSON.stringify(small), 'utf8')
    expect(remaining).toBeGreaterThan(0)
    secondFeedback.sections[0].text += 'a'.repeat(remaining)
    expect(secondFeedback.sections[0].text.length).toBeLessThanOrEqual(64000)
    const exact = await render()
    expect(exact.items).toHaveLength(2)
    expect(Buffer.byteLength(JSON.stringify(exact), 'utf8')).toBe(240000)
    secondFeedback.sections[0].text += 'a'
    const overflow = await render()
    expect(overflow.items).toHaveLength(1)
    expect(overflow.has_more).toBe(true)
    expect(
      decodeConversationMealJournalCursor(
        required(overflow.next_cursor),
        journalQuery().ownerId,
        writerEpoch,
      ),
    ).toEqual({ at: first.at, id: first.event_id })
  })
})

function feedback(
  commandId: string,
  receipt: NonNullable<ReturnType<typeof journalCommand>['receipt']>,
  text: string,
) {
  const observed = journalClinical('2026-11-04T12:02:30.000001Z'),
    policy = projectCurrentClinicalPublicPolicy(
      readCurrentClinicalState(observed, journalQuery().ownerId),
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
    provenance: { epoch: writerEpoch, command_id: commandId, observed_at: observed.observed_at },
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

function required<T>(value: T | null | undefined): T {
  if (value === null || value === undefined)
    throw new Error('Required synthetic fixture value absent')
  return value
}
