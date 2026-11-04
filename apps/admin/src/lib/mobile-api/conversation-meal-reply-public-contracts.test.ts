import { readFileSync } from 'node:fs'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture, replyPresentation } from './__fixtures__/conversation-meal-reply'
import {
  bindConversationMealReplySubmission,
  projectConversationMealReplyResult,
} from './conversation-meal-reply-public-contracts'

describe('closed public reply identity and actual child proof', () => {
  it('binds the outbound typed immutable answer and SQL decimal digest', () => {
    const f = replyFixture(),
      v = bindConversationMealReplySubmission({
        ownerId: f.auth.userId,
        parentCommandId: f.identity.parentCommandId,
        epoch: f.identity.epoch,
        idempotencyKey: f.key,
        body: f.submission,
      })
    expect(v.reply.inputHash).toBe(f.identity.replyInputHash)
    expect(v.reply.input).toEqual(f.submission.input)
    expect(Object.isFrozen(v.reply.input)).toBe(true)
  })
  it('matches the saved/needs-reply/held public golden without private parent context', () => {
    const golden = JSON.parse(
      readFileSync(
        new URL('./__fixtures__/conversation-meal-reply-public.json', import.meta.url),
        'utf8',
      ),
    )
    for (const [key, sample] of [
      ['saved', 'saved'],
      ['needs_reply', 'awaiting_reply'],
      ['held', 'prepared'],
    ] as const) {
      const f = replyFixture(sample)
      const value = projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'read',
        outcome: null,
        feedback: null,
      })
      expect(value).toEqual(golden[key].data)
      expect(JSON.stringify(value)).not.toMatch(
        /source_hash|snapshot|answer_chain|semantic|tokens|accessToken|private/,
      )
    }
  })
  it('requires actual own child fulfillment, not a merely prepared receipt claim', () => {
    const f = replyFixture('prepared')
    expect(() =>
      projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'submit',
        outcome: {
          status: 'saved',
          identity: f.identity,
          receipt: replyFixture().state.reply?.receipt,
          historicalFeedback: null,
          feedbackGate: 'continuation_feedback_v2_unavailable',
        },
        feedback: null,
      }),
    ).toThrow()
  })
  it('keeps an unavailable child NULL after an actual parent-only fallback without asserting absence', () => {
    const f = replyFixture('parent_head')
    const value = projectConversationMealReplyResult({
      auth: f.auth,
      identity: f.identity,
      proof: { kind: 'parent_only_after_reply_conflict', state: f.state },
      observation: f.profile,
      mode: 'read',
      outcome: null,
      feedback: null,
    })
    expect(value).toMatchObject({
      status: 'reconciliation_required',
      reason: 'reply_conflict',
      child_binding: null,
      receipt: null,
      question: null,
    })
  })
  it.each([
    'parent',
    'epoch',
    'hash',
    'auth',
    'private',
  ])('refuses damaged actual %s scope', (kind) => {
    const f = replyFixture()
    if (kind === 'parent') f.identity.parentCommandId = f.identity.replyId
    if (kind === 'epoch') f.identity.epoch = f.identity.replyId
    if (kind === 'hash') f.identity.replyInputHash = 'f'.repeat(64)
    if (kind === 'auth') f.auth.patient.authUserId = f.identity.replyId
    if (kind === 'private') Object.assign(f.state, { snapshot: {} })
    expect(() =>
      projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'read',
        outcome: null,
        feedback: null,
      }),
    ).toThrow()
  })
  it('rejects extra submit fields and getters without executing them', () => {
    const f = replyFixture(),
      hook = vi.fn()
    Object.defineProperty(f.submission, 'input', { enumerable: true, get: hook })
    expect(() =>
      bindConversationMealReplySubmission({
        ownerId: f.auth.userId,
        parentCommandId: f.identity.parentCommandId,
        epoch: f.identity.epoch,
        idempotencyKey: f.key,
        body: f.submission,
      }),
    ).toThrow()
    expect(hook).not.toHaveBeenCalled()
  })
  it('drops a damaged optional presentation without executing its getter or invalidating saved food', () => {
    const f = replyFixture(),
      hook = vi.fn(),
      feedback = {}
    Object.defineProperty(feedback, 'schema', { enumerable: true, get: hook })
    const result = projectConversationMealReplyResult({
      auth: f.auth,
      identity: f.identity,
      proof: { kind: 'reply', state: f.state },
      observation: f.profile,
      mode: 'read',
      outcome: null,
      feedback,
    })
    expect(result).toMatchObject({ status: 'saved', feedback: null })
    expect(hook).not.toHaveBeenCalled()
  })
  it('never returns a historical next question after another child fulfilled the parent', () => {
    const f = replyFixture('historical_next_question_after_fulfillment')
    expect(
      projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'read',
        outcome: null,
        feedback: null,
      }),
    ).toMatchObject({ status: 'held', question: null, receipt: null })
  })
  it('withholds a private reason outside the closed public allowlist', () => {
    const f = replyFixture('admitted_quantity_reply')
    const result = projectConversationMealReplyResult({
      auth: f.auth,
      identity: f.identity,
      proof: { kind: 'reply', state: f.state },
      observation: f.profile,
      mode: 'submit',
      outcome: { status: 'held', identity: f.identity, reason: 'unpublished_private_reason' },
      feedback: null,
    })
    expect(result.reason).toBe('clarification_unavailable')
  })

  it('publishes only a valid saved linked presentation bound to actual child facts and current policy', () => {
    const f = replyFixture(),
      feedback = replyPresentation(f),
      result = projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'read',
        outcome: null,
        feedback,
      })
    expect(result.feedback).toEqual(feedback)
    expect(result.feedback?.format).toBe('sections')
  })
  it.each([
    'policy',
    'clock',
    'registration',
    'private',
    'oversize',
  ])('preserves saved facts and drops an optional %s mismatch', (kind) => {
    const f = replyFixture(),
      feedback = replyPresentation(f)
    if (kind === 'policy')
      feedback.current_policy.hide.budget = !feedback.current_policy.hide.budget
    if (kind === 'clock') feedback.provenance.observed_at = '2099-01-01T00:00:00Z'
    if (kind === 'registration') feedback.original.registration_id = f.identity.replyId
    if (kind === 'private') Object.assign(feedback, { source_context: {} })
    if (kind === 'oversize' && feedback.sections) feedback.sections[0].text = 'x'.repeat(250000)
    expect(
      projectConversationMealReplyResult({
        auth: f.auth,
        identity: f.identity,
        proof: { kind: 'reply', state: f.state },
        observation: f.profile,
        mode: 'read',
        outcome: null,
        feedback,
      }),
    ).toMatchObject({ status: 'saved', feedback: null })
  })
})
