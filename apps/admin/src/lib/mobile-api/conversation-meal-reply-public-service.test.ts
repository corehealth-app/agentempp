import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture, replyPresentation } from './__fixtures__/conversation-meal-reply'
import {
  type ConversationMealReplyPublicPorts,
  createConversationMealReplyPublicService,
} from './conversation-meal-reply-public-service'

function setup(key: Parameters<typeof replyFixture>[0] = 'saved') {
  const f = replyFixture(key),
    submit = vi.fn().mockResolvedValue({
      status: 'saved',
      identity: f.identity,
      receipt: f.state.reply?.receipt,
      historicalFeedback: null,
      feedbackGate: 'continuation_feedback_v2_unavailable',
    }),
    processor = vi.fn(() => ({ submit })),
    read = vi.fn().mockResolvedValue(f.state),
    verifyAccessToken = vi.fn().mockResolvedValue(f.auth.identity),
    loadPatient = vi.fn().mockResolvedValue(f.auth.patient),
    capture = vi.fn().mockResolvedValue(f.profile),
    ensureOriginal = vi.fn(),
    readHistorical = vi.fn().mockResolvedValue(null),
    feedback = vi.fn<NonNullable<ConversationMealReplyPublicPorts['feedback']>>(() => ({
      ensureOriginal,
      readHistorical,
    }))
  const service = createConversationMealReplyPublicService(
    { rpc: vi.fn(), from: vi.fn() } as unknown as ServiceClient,
    {
      processor,
      reader: { read },
      auth: { verifyAccessToken, loadPatient, isAdmin: vi.fn().mockResolvedValue(false) },
      clinical: { capture },
      feedback,
    },
  )
  return {
    ...f,
    submit,
    processor,
    read,
    verifyAccessToken,
    loadPatient,
    capture,
    ensureOriginal,
    readHistorical,
    feedback,
    service,
  }
}
describe('real public reply flow and explicit readonly recovery', () => {
  it('pins the actual read response before post-scope callbacks can mutate its receipt', async () => {
    const f = setup(),
      transport = structuredClone(f.state),
      i = f.identity
    f.read.mockResolvedValue(transport)
    f.capture.mockImplementation(async () => {
      if (f.read.mock.calls.length && transport.reply?.receipt)
        transport.reply.receipt.log_ids = ['c3cc0000-0000-4000-8000-000000000099']
      return f.profile
    })
    const result = await f.service.reconcile(f.auth, i.parentCommandId, i.replyId, i.epoch, {
      parent_input_hash: i.parentInputHash,
      reply_input_hash: i.replyInputHash,
    })
    expect(result.status).toBe('saved')
    expect(result.receipt).toEqual(f.state.reply?.receipt)
    expect(f.ensureOriginal).not.toHaveBeenCalled()
    expect(f.submit).not.toHaveBeenCalled()
  })
  it('submits once then requires an actual same-identity complete read before optional enrichment', async () => {
    const f = setup()
    expect(f.processor).not.toHaveBeenCalled()
    const result = await f.service.submit(
      f.auth,
      f.identity.parentCommandId,
      f.identity.epoch,
      f.submission,
      f.key,
    )
    expect(result.status).toBe('saved')
    expect(result.child_binding?.command_protocol).toBe('conversation.clarification.v1')
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledWith(f.identity)
    expect(f.ensureOriginal).toHaveBeenCalledTimes(1)
    expect(f.readHistorical).toHaveBeenCalledTimes(1)
    expect(f.submit.mock.invocationCallOrder[0]).toBeLessThan(f.read.mock.invocationCallOrder[0])
    expect(f.read.mock.invocationCallOrder[0]).toBeLessThan(
      f.ensureOriginal.mock.invocationCallOrder[0],
    )
  })
  it('GET uses only complete reads and readHistorical, never processor or ensure', async () => {
    const f = setup()
    const result = await f.service.reconcile(
      f.auth,
      f.identity.parentCommandId,
      f.identity.replyId,
      f.identity.epoch,
      {
        parent_input_hash: f.identity.parentInputHash,
        reply_input_hash: f.identity.replyInputHash,
      },
    )
    expect(result.status).toBe('saved')
    expect(f.processor).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
    expect(f.readHistorical).toHaveBeenCalledTimes(1)
  })
  it('does not repeat a submit after an unknown response and recovers actual saved proof', async () => {
    const f = setup()
    f.submit.mockRejectedValue(new Error('lostreply'))
    expect(
      (
        await f.service.submit(
          f.auth,
          f.identity.parentCommandId,
          f.identity.epoch,
          f.submission,
          f.key,
        )
      ).status,
    ).toBe('saved')
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledTimes(1)
  })
  it('never repeats an uncertain complete read or publishes an invented binding', async () => {
    const f = setup()
    f.read.mockRejectedValue(new Error('readlost'))
    await expect(
      f.service.submit(f.auth, f.identity.parentCommandId, f.identity.epoch, f.submission, f.key),
    ).rejects.toMatchObject({ status: 503 })
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it('performs only one parent-only fallback for actual reply_conflict with a nullable child', async () => {
    const f = setup('parent_head')
    f.read
      .mockReset()
      .mockResolvedValueOnce({ action: 'reply_conflict' })
      .mockResolvedValueOnce(f.state)
    const result = await f.service.reconcile(
      f.auth,
      f.identity.parentCommandId,
      f.identity.replyId,
      f.identity.epoch,
      {
        parent_input_hash: f.identity.parentInputHash,
        reply_input_hash: f.identity.replyInputHash,
      },
    )
    expect(result).toMatchObject({
      child_binding: null,
      status: 'reconciliation_required',
      reason: 'reply_conflict',
      receipt: null,
      question: null,
    })
    expect(f.read).toHaveBeenCalledTimes(2)
    expect(f.processor).not.toHaveBeenCalled()
    expect(f.read.mock.calls[1][0]).toEqual({
      ownerId: f.identity.ownerId,
      parentCommandId: f.identity.parentCommandId,
      parentInputHash: f.identity.parentInputHash,
      epoch: f.identity.epoch,
    })
  })
  it('preserves actual quota refusal as429 without another write', async () => {
    const f = setup()
    f.submit.mockResolvedValue({ status: 'held', identity: f.identity, reason: 'rate_limited' })
    await expect(
      f.service.submit(f.auth, f.identity.parentCommandId, f.identity.epoch, f.submission, f.key),
    ).rejects.toMatchObject({ status: 429 })
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it('refuses an expired original token before calling processor/read', async () => {
    const f = setup()
    f.verifyAccessToken.mockResolvedValue(null)
    await expect(
      f.service.submit(f.auth, f.identity.parentCommandId, f.identity.epoch, f.submission, f.key),
    ).rejects.toMatchObject({ status: 401 })
    expect(f.processor).not.toHaveBeenCalled()
    expect(f.read).not.toHaveBeenCalled()
  })
  it('preserves actual saved food if the optional feedback factory fails', async () => {
    const f = setup()
    f.feedback.mockImplementation(() => {
      throw new Error('optional unavailable')
    })
    expect(
      (
        await f.service.submit(
          f.auth,
          f.identity.parentCommandId,
          f.identity.epoch,
          f.submission,
          f.key,
        )
      ).status,
    ).toBe('saved')
    expect(f.submit).toHaveBeenCalledTimes(1)
  })
  it('does not enrich or read private state after the original Auth changes during submit', async () => {
    const f = setup()
    f.submit.mockImplementation(async () => {
      f.verifyAccessToken.mockResolvedValue(null)
      throw new Error('unknown effect')
    })
    await expect(
      f.service.submit(f.auth, f.identity.parentCommandId, f.identity.epoch, f.submission, f.key),
    ).rejects.toMatchObject({ status: 401 })
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.read).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it.each([
    'stale_epoch',
    'input_conflict',
    'ineligible',
    'event_conflict',
  ])('fails closed on actual %s with no parent fallback', async (action) => {
    const f = setup()
    f.read.mockResolvedValue({ action })
    await expect(
      f.service.reconcile(
        f.auth,
        f.identity.parentCommandId,
        f.identity.replyId,
        f.identity.epoch,
        {
          parent_input_hash: f.identity.parentInputHash,
          reply_input_hash: f.identity.replyInputHash,
        },
      ),
    ).rejects.toMatchObject({ status: 409 })
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.processor).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it('refuses changed parent decision before publishing or enriching a wrong binding', async () => {
    const f = setup()
    f.submission.parent_decision_hash = 'f'.repeat(64)
    await expect(
      f.service.submit(f.auth, f.identity.parentCommandId, f.identity.epoch, f.submission, f.key),
    ).rejects.toMatchObject({ status: 409 })
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })

  it('optional seal loss never repeats food and a separately read sealed original is publishable', async () => {
    const f = setup()
    f.ensureOriginal.mockRejectedValue(new Error('lost seal'))
    f.readHistorical.mockResolvedValue(replyPresentation(f))
    const result = await f.service.submit(
      f.auth,
      f.identity.parentCommandId,
      f.identity.epoch,
      f.submission,
      f.key,
    )
    expect(result.status).toBe('saved')
    expect(result.feedback?.format).toBe('sections')
    expect(f.submit).toHaveBeenCalledTimes(1)
    expect(f.ensureOriginal).toHaveBeenCalledTimes(1)
    expect(f.readHistorical).toHaveBeenCalledTimes(1)
  })
  it('checks the actual original feedback callback scope and rejects invented identity capabilities', async () => {
    const f = setup(),
      checks: boolean[] = []
    f.feedback.mockImplementation((_sdk, check) => ({
      async ensureOriginal(input) {
        checks.push(await check(input))
        checks.push(
          await check({
            ...input,
            auth: { ...input.auth, authUserId: input.binding.childBinding.owner_id },
          }),
        )
        return null
      },
      async readHistorical() {
        return null
      },
    }))
    await f.service.submit(
      f.auth,
      f.identity.parentCommandId,
      f.identity.epoch,
      f.submission,
      f.key,
    )
    expect(checks).toEqual([true, false])
  })
  it('closes publication after a patient remap during optional historical presentation', async () => {
    const f = setup()
    f.readHistorical.mockImplementation(async () => {
      f.loadPatient.mockResolvedValue({ ...f.auth.patient, id: f.auth.authUserId })
      return replyPresentation(f)
    })
    await expect(
      f.service.reconcile(
        f.auth,
        f.identity.parentCommandId,
        f.identity.replyId,
        f.identity.epoch,
        {
          parent_input_hash: f.identity.parentInputHash,
          reply_input_hash: f.identity.replyInputHash,
        },
      ),
    ).rejects.toMatchObject({ status: 409 })
    expect(f.processor).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
})
