import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { validateConversationMealReplyQuestion } from './conversation-meal-continuation-input'
import { createConversationMealQuestionReadService } from './conversation-meal-question-read'
import { createConversationMealReplyPublicService } from './conversation-meal-reply-public-service'

function setup(key: Parameters<typeof replyFixture>[0] = 'parent_head', sdk = false) {
  const f = replyFixture(key),
    state = { ...f.state, reply: null },
    read = vi.fn().mockResolvedValue(state),
    rpc = vi.fn().mockResolvedValue({ data: state, error: null }),
    from = vi.fn(() => {
      throw new Error('No unrelated SDK read or write')
    }),
    verifyAccessToken = vi.fn().mockResolvedValue(f.auth.identity),
    loadPatient = vi.fn().mockResolvedValue(f.auth.patient),
    isAdmin = vi.fn().mockResolvedValue(false),
    capture = vi.fn().mockResolvedValue(f.profile),
    db = { rpc, from } as unknown as ServiceClient,
    service = createConversationMealQuestionReadService(db, {
      ...(sdk ? {} : { reader: { read } }),
      auth: { verifyAccessToken, loadPatient, isAdmin },
      clinical: { capture },
    }),
    run = () =>
      service.read(f.auth, f.identity.parentCommandId, f.identity.epoch, {
        parent_input_hash: f.identity.parentInputHash,
      })
  return {
    ...f,
    state,
    read,
    rpc,
    from,
    verifyAccessToken,
    loadPatient,
    isAdmin,
    capture,
    service,
    run,
  }
}

describe('parent-only linked meal question observation', () => {
  it.each([
    ['parent_head', 'quantity', 'needs_reply'],
    ['awaiting_reply', 'meal_type', 'needs_reply'],
    ['fulfilled_without_requested_reply', null, 'closed'],
  ] as const)('projects genuine %s without a reply identity or side effect', async (sample, kind, status) => {
    const f = setup(sample),
      result = await f.run()
    expect(result).toEqual({
      schema: 'conversation.meal-question-read.v1',
      auth_user_id: f.auth.authUserId,
      owner_id: f.identity.ownerId,
      epoch: f.identity.epoch,
      parent_command_id: f.identity.parentCommandId,
      parent_input_hash: f.identity.parentInputHash,
      parent_decision_hash: f.state.parent.decision.decision_hash,
      parent_binding: f.state.parent.binding,
      head_revision: f.state.head.revision,
      observed_at: f.state.observed_at,
      status,
      question: f.state.head.question,
      reason: status === 'closed' ? 'parent_fulfilled' : null,
    })
    expect(result.question?.kind ?? null).toBe(kind)
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.parent_binding)).toBe(true)
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledWith({
      ownerId: f.identity.ownerId,
      parentCommandId: f.identity.parentCommandId,
      parentInputHash: f.identity.parentInputHash,
      epoch: f.identity.epoch,
    })
    expect(f.capture).toHaveBeenCalledTimes(2)
    expect(f.capture.mock.invocationCallOrder[0]).toBeLessThan(f.read.mock.invocationCallOrder[0])
    expect(f.read.mock.invocationCallOrder[0]).toBeLessThan(f.capture.mock.invocationCallOrder[1])
    expect(f.rpc).not.toHaveBeenCalled()
    expect(f.from).not.toHaveBeenCalled()
  })

  it('uses only the existing readonly RPC with null reply arguments in the default adapter', async () => {
    const f = setup('parent_head', true)
    expect((await f.run()).status).toBe('needs_reply')
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.rpc).toHaveBeenCalledWith('read_conversation_meal_continuation', {
      p_user_id: f.identity.ownerId,
      p_parent_command_id: f.identity.parentCommandId,
      p_expected_epoch: f.identity.epoch,
      p_parent_input_hash: f.identity.parentInputHash,
      p_reply_id: null,
      p_reply_input_hash: null,
    })
    expect(f.from).not.toHaveBeenCalled()
  })

  it('connects genuine quantity and meal-type observations to the existing answer service and saved proof', async () => {
    // UNIT composition of actual SQL samples, not HTTP or a new writer proof.
    const quantity = await setup('parent_head').run(),
      mealType = await setup('awaiting_reply').run()
    for (const [offer, sample] of [
      [quantity, 'awaiting_reply'],
      [mealType, 'saved'],
    ] as const) {
      const f = replyFixture(sample),
        submission = f.submission,
        submit = vi.fn().mockResolvedValue(null),
        reader = { read: vi.fn().mockResolvedValue(f.state) },
        db = { rpc: vi.fn(), from: vi.fn() } as unknown as ServiceClient,
        service = createConversationMealReplyPublicService(db, {
          reader,
          processor: () => ({ submit }),
          auth: {
            verifyAccessToken: vi.fn().mockResolvedValue(f.auth.identity),
            loadPatient: vi.fn().mockResolvedValue(f.auth.patient),
            isAdmin: vi.fn().mockResolvedValue(false),
          },
          clinical: { capture: vi.fn().mockResolvedValue(f.profile) },
          feedback: () => ({
            ensureOriginal: vi.fn(),
            readHistorical: vi.fn().mockResolvedValue(null),
          }),
        })
      expect(offer.status).toBe('needs_reply')
      expect(offer.parent_binding).toEqual(f.state.parent.binding)
      expect(submission.parent_input_hash).toBe(offer.parent_input_hash)
      expect(submission.parent_decision_hash).toBe(offer.parent_decision_hash)
      expect(submission.input.expected_revision).toBe(offer.head_revision)
      expect(submission.input.question_key).toBe(offer.question?.question_key)
      expect(() =>
        validateConversationMealReplyQuestion(submission.input, offer.question),
      ).not.toThrow()
      const result = await service.submit(
        f.auth,
        offer.parent_command_id,
        offer.epoch,
        submission,
        f.key,
      )
      expect(result.status).toBe(sample === 'saved' ? 'saved' : 'needs_reply')
      expect(result.question).toEqual(sample === 'saved' ? null : mealType.question)
      expect(result.receipt).toEqual(sample === 'saved' ? f.state.reply?.receipt : null)
      expect(submit).toHaveBeenCalledTimes(1)
      expect(reader.read).toHaveBeenCalledTimes(1)
    }
  })

  it('pins all read facts before the asynchronous post-read scope observation', async () => {
    const f = setup(),
      original = structuredClone(f.state)
    f.capture.mockImplementation(async () => {
      if (f.read.mock.calls.length) {
        f.state.parent.binding.admitted_at = '2026-11-04T00:00:00Z'
        f.state.parent.decision.decision_hash = 'f'.repeat(64)
        f.state.head.question = null
      }
      return f.profile
    })
    const result = await f.run()
    expect(result.parent_binding).toEqual(original.parent.binding)
    expect(result.parent_decision_hash).toBe(original.parent.decision.decision_hash)
    expect(result.question).toEqual(original.head.question)
  })

  it.each([
    'absent',
    'stale_epoch',
    'input_conflict',
    'ineligible',
    'reply_conflict',
    'event_conflict',
  ])('fails closed on %s without another lookup', async (action) => {
    const f = setup()
    f.read.mockResolvedValue({ action })
    await expect(f.run()).rejects.toMatchObject({ status: 409 })
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
  })

  it.each([
    (s: ReturnType<typeof setup>['state']) => {
      s.parent.binding.owner_id = 'c3cc0000-0000-4000-8000-000000000099'
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.parent.binding.epoch = 'c3cc0000-0000-4000-8000-000000000099'
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.parent.binding.input_hash = 'f'.repeat(64)
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.parent.decision.decision_hash = 'invalid-hash'
    },
    (s: ReturnType<typeof setup>['state']) => {
      Object.assign(s.parent.decision, { input_hash: 'f'.repeat(64) })
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.head.revision += 1
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.head.question = null
    },
    (s: ReturnType<typeof setup>['state']) => {
      Object.assign(s.parent.binding, { kind: 'workout.report' })
    },
    (s: ReturnType<typeof setup>['state']) => {
      Object.assign(s, { grant_write: true })
    },
    (s: ReturnType<typeof setup>['state']) => {
      s.observed_at = '2099-01-01T00:00:00Z'
    },
  ])('rejects untrusted, mismatched or future private metadata', async (damage) => {
    const f = setup()
    damage(f.state)
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.read).toHaveBeenCalledTimes(1)
  })

  it('rejects accessor metadata without invoking it', async () => {
    const f = setup(),
      getter = vi.fn(() => f.state.head)
    Object.defineProperty(f.state, 'head', { enumerable: true, get: getter })
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(getter).not.toHaveBeenCalled()
  })

  it('performs the post-read Auth guard even when the one read fails', async () => {
    const f = setup()
    f.read.mockImplementation(async () => {
      f.verifyAccessToken.mockResolvedValue(null)
      throw new Error('read transport unknown')
    })
    await expect(f.run()).rejects.toMatchObject({ status: 401 })
    expect(f.read).toHaveBeenCalledTimes(1)
  })

  it('never retries an uncertain read or fabricates a question', async () => {
    const f = setup()
    f.read.mockRejectedValue(new Error('transport unknown'))
    await expect(f.run()).rejects.toMatchObject({ status: 503 })
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
  })

  it.each([
    'signed_out',
    'admin',
    'wrong_patient',
    'stale_epoch',
  ])('rejects %s before reading private state', async (kind) => {
    const f = setup()
    if (kind === 'signed_out') f.verifyAccessToken.mockResolvedValue(null)
    if (kind === 'admin') f.isAdmin.mockResolvedValue(true)
    if (kind === 'wrong_patient')
      f.loadPatient.mockResolvedValue({ ...f.auth.patient, id: f.auth.authUserId })
    if (kind === 'stale_epoch')
      f.capture.mockResolvedValue({ ...f.profile, epoch: 'c3cc0000-0000-4000-8000-000000000099' })
    await expect(f.run()).rejects.toMatchObject({
      status:
        kind === 'signed_out' ? 401 : kind === 'admin' ? 403 : kind === 'stale_epoch' ? 500 : 409,
    })
    expect(f.read).not.toHaveBeenCalled()
  })

  it.each([
    'signed_out',
    'admin',
    'account_switch',
    'epoch_change',
  ])('discards the read after %s during it', async (kind) => {
    const f = setup()
    f.read.mockImplementation(async () => {
      if (kind === 'signed_out') f.verifyAccessToken.mockResolvedValue(null)
      if (kind === 'admin') f.isAdmin.mockResolvedValue(true)
      if (kind === 'account_switch')
        f.verifyAccessToken.mockResolvedValue({ ...f.auth.identity, id: f.identity.ownerId })
      if (kind === 'epoch_change')
        f.capture.mockResolvedValue({ ...f.profile, epoch: 'c3cc0000-0000-4000-8000-000000000099' })
      return f.state
    })
    await expect(f.run()).rejects.toMatchObject({
      status:
        kind === 'signed_out' ? 401 : kind === 'admin' ? 403 : kind === 'epoch_change' ? 500 : 409,
    })
    expect(f.read).toHaveBeenCalledTimes(1)
  })

  it('keeps this leaf free of processor, provider, feedback and write composition', () => {
    const source = readFileSync(
      new URL('./conversation-meal-question-read.ts', import.meta.url),
      'utf8',
    )
    expect(source).not.toMatch(
      /createConversationMealContinuationService|ensureOriginal|createConversationFeedback|interpretConversation|calculateConversation|\.insert\(|\.update\(|\.delete\(/,
    )
  })
})
