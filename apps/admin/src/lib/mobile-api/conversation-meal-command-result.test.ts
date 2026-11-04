import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { writerReceipt } from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  parseConversationMealHistoricalPresentation,
  projectSavedConversationMealCommandResult,
} from './conversation-meal-command-result'

// Actual cross-language outputs produced by the qualified current-policy
// presentation service. No hand-written representation of its policy flags.
const fixtures = JSON.parse(
  readFileSync(
    new URL(
      '../../../../ios/BodyFlow/BodyFlowTests/Fixtures/ConversationFeedbackPresentationFixtures.json',
      import.meta.url,
    ),
    'utf8',
  ),
)
function input(label = 'unrestricted') {
  const command = bindConversationCommand(fixtures.owner, `cmsg1:${fixtures.command_id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: fixtures.command_id,
    kind: 'meal.report',
    meal_type: fixtures.meal_kind,
    source: { channel: 'text', text: 'leite integral 206 g' },
  })
  return {
    auth: candidateAuth,
    command,
    expectedEpoch: fixtures.epoch,
    serverBinding: {
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      command_protocol: 'conversation.command.v1',
      kind: 'meal.report',
      epoch: fixtures.epoch,
      admitted_at: fixtures.admitted_at,
    },
    receipt: {
      ...writerReceipt(),
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      provider_key: `conversation.meal/${command.ownerId}/${command.commandId}`,
      registration_id: fixtures.registration_id,
      local_date: fixtures.local_date,
      meal_type: fixtures.meal_kind,
      log_ids: fixtures.log_ids,
      timezone: 'UTC',
      consumed_at: '2026-11-03T11:00:00Z',
    },
    feedback: structuredClone(
      fixtures.cases.find((c: { label: string }) => c.label === label)?.payload,
    ),
  }
}
const project = (value = input()) => projectSavedConversationMealCommandResult(value)

describe('closed saved meal result for authenticated transport, not a database proof', () => {
  it('projects exact factual identity and guarded feedback without private command/auth/context', () => {
    const i = input(),
      result = project(i)
    expect(result).toEqual({
      schema: 'conversation.meal-command-result.v1',
      status: 'saved',
      owner_id: i.command.ownerId,
      command_id: i.command.commandId,
      input_hash: i.command.inputHash,
      epoch: i.expectedEpoch,
      admitted_at: i.serverBinding.admitted_at,
      receipt: i.receipt,
      feedback: i.feedback,
    })
    const json = JSON.stringify(result)
    for (const key of [
      'accessToken',
      'synthetic-local-token',
      'source_input',
      'historicalFeedback',
      'clinical',
      'source_hash',
    ])
      expect(json).not.toContain(key)
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.receipt.log_ids)).toBe(true)
  })
  it.each(
    (fixtures.cases as { label: string }[]).map((c) => c.label),
  )('preserves actual %s wrapper verbatim', (label) => {
    const i = input(label)
    expect(project(i).feedback).toEqual(i.feedback)
  })
  it('keeps a factual success when optional feedback is unavailable', () => {
    const i = input()
    i.feedback = null
    expect(project(i)).toMatchObject({ status: 'saved', feedback: null, receipt: i.receipt })
  })
  it.each([
    'private_key',
    'context',
    'raw_v2',
  ])('drops unknown optional feedback field %s rather than publishing it', (field) => {
    const i = input()
    i.feedback[field] = 'must not escape'
    expect(project(i).feedback).toBeNull()
  })
  it.each([
    'epoch',
    'command_id',
  ])('drops feedback from a different provenance %s without invalidating food', (key) => {
    const i = input()
    i.feedback.provenance[key] = '10000000-0000-4000-8000-000000000099'
    expect(project(i)).toMatchObject({ status: 'saved', feedback: null })
  })
  it('drops feedback with missing actual budget flag or mismatched observation', () => {
    const missing = input()
    delete missing.feedback.current_policy.hide.budget
    expect(project(missing).feedback).toBeNull()
    const stale = input()
    stale.feedback.provenance.observed_at = '2026-11-04T12:00:00.000002Z'
    expect(project(stale).feedback).toBeNull()
  })
  it('does not accept opaque legacy when current policy became restricted', () => {
    const i = input('legacy')
    i.feedback.current_policy.hide.budget = true
    expect(project(i).feedback).toBeNull()
  })
  it('drops changed food identity or duplicate facts in optional presentation', () => {
    const i = input()
    i.feedback.recorded.items[0].log_id = '10000000-0000-4000-8000-000000000099'
    expect(project(i).feedback).toBeNull()
    const dup = input()
    dup.feedback.recorded.items.push(dup.feedback.recorded.items[0])
    expect(project(dup).feedback).toBeNull()
  })
  it('drops malformed or oversized sections and preserves the mandatory receipt', () => {
    const i = input()
    i.feedback.sections[1].text = 'x'.repeat(300000)
    expect(project(i)).toMatchObject({ status: 'saved', feedback: null })
    const order = input()
    order.feedback.sections.reverse()
    expect(project(order).feedback).toBeNull()
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
    'provider_key',
    'log_ids',
    'local_date',
    'effect_version',
  ])('rejects an invalid mandatory effect %s', (key) => {
    const i = input()
    Object.assign(i.receipt, {
      [key]: key === 'log_ids' ? [fixtures.log_ids[0], fixtures.log_ids[0]] : 'unbound',
    })
    expect(() => project(i)).toThrow()
  })
  it('refuses a receipt before admission at sub-millisecond precision', () => {
    const i = input()
    i.serverBinding.admitted_at = '2026-11-03T11:00:00.000000002Z'
    i.receipt.consumed_at = '2026-11-03T11:00:00.000000001Z'
    expect(() => project(i)).toThrow()
  })
  it('requires original expected epoch and owner/command binding, never retags', () => {
    const i = input()
    i.expectedEpoch = '10000000-0000-4000-8000-000000000099'
    expect(() => project(i)).toThrow()
    const owner = input()
    owner.serverBinding.owner_id = '10000000-0000-4000-8000-000000000099'
    expect(() => project(owner)).toThrow()
  })
  it('neither mutates supplied values nor needs a writer/service/provider', () => {
    const i = input(),
      before = structuredClone(i)
    expect(project(i)).toEqual(project(i))
    expect(i).toEqual(before)
    // No runtime/client parameter exists on this pure projection boundary.
  })
})

describe('narrow actual-command historical presentation seam', () => {
  it('preserves all previously qualified v1 public fixture outputs', () => {
    for (const c of fixtures.cases) {
      const i = input(c.label),
        r = i.receipt
      expect(
        parseConversationMealHistoricalPresentation(i.feedback, {
          ownerId: i.command.ownerId,
          commandId: i.command.commandId,
          epoch: i.expectedEpoch,
          admittedAt: i.serverBinding.admitted_at,
          receipt: {
            registration_id: r.registration_id,
            local_date: r.local_date,
            meal_type: r.meal_type,
            log_ids: r.log_ids,
          },
        }),
      ).toEqual(project(i).feedback)
    }
  })
  it('qualifies common actual child facts without constructing a report command or v1 receipt', () => {
    const i = input(),
      child = '60000000-0000-4000-8000-000000000002'
    i.feedback.provenance.command_id = child
    const r = i.receipt
    expect(
      parseConversationMealHistoricalPresentation(i.feedback, {
        ownerId: i.command.ownerId,
        commandId: child,
        epoch: i.expectedEpoch,
        admittedAt: i.serverBinding.admitted_at,
        receipt: {
          registration_id: r.registration_id,
          local_date: r.local_date,
          meal_type: r.meal_type,
          log_ids: r.log_ids,
        },
      }),
    ).toEqual(i.feedback)
  })
})
