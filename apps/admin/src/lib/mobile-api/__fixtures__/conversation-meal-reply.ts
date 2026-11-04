import presentations from '../../../../../ios/BodyFlow/BodyFlowTests/Fixtures/ConversationFeedbackPresentationFixtures.json'
import type { MobileAuthContext } from '../auth'
import { projectCurrentClinicalPublicPolicy } from '../current-clinical-read-model'
import { readCurrentClinicalState } from '../current-clinical-state'
import actual from './conversation-meal-continuation-read-sql.json'
import { clinical } from './feedback-v2-source'
export type ReplySample = keyof typeof actual.samples
export function replyFixture(key: ReplySample = 'saved') {
  const state = structuredClone(actual.samples[key]),
    p = state.parent.binding,
    r = state.reply ?? actual.samples.saved.reply
  const authId = 'c3cc0000-0000-4000-8000-000000000002'
  const auth: MobileAuthContext = {
    accessToken: 'synthetic-reply-token',
    authUserId: authId,
    userId: p.owner_id,
    identity: {
      id: authId,
      email: 'reply.synthetic@example.invalid',
      emailConfirmedAt: '2026-11-01T00:00:00Z',
    },
    patient: {
      id: p.owner_id,
      authUserId: authId,
      email: null,
      name: null,
      locale: 'pt-BR',
      timezone: 'UTC',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  const identity = {
    ownerId: p.owner_id,
    parentCommandId: p.command_id,
    parentInputHash: p.input_hash,
    epoch: p.epoch,
    replyId: r.binding.command_id,
    replyInputHash: r.binding.input_hash,
  }
  const submission = {
    schema: 'conversation.meal-reply-submit.v1',
    reply_id: r.binding.command_id,
    parent_input_hash: p.input_hash,
    parent_decision_hash: state.parent.decision.decision_hash,
    input: r.body,
  }
  const raw = clinical()
  raw.user_id = p.owner_id
  raw.epoch = p.epoch
  raw.health_state.user_id = p.owner_id
  raw.date = state.observed_at.slice(0, 10)
  raw.observed_at = state.observed_at
  raw.safety.date = raw.date
  raw.safety.observed_at = raw.observed_at
  const profile = structuredClone(readCurrentClinicalState(raw, p.owner_id))
  return { state, auth, identity, submission, profile, key: `cmreply1:${r.binding.command_id}` }
}

/** Synthetic presentation assembled from the actual qualified renderer golden;
 * the receipt/binding remains the separately qualified SQL sample. */
export function replyPresentation(f = replyFixture()) {
  const sample = presentations.cases.find((x) => x.label === 'unrestricted')
  if (!sample) throw new Error('Missing synthetic presentation')
  const value = structuredClone(sample.payload),
    r = f.state.reply?.receipt
  const recorded = value.recorded
  if (!r || !recorded || !('items' in recorded)) throw new Error('Missing actual synthetic effect')
  value.original.registration_id = r.registration_id
  value.original.local_date = r.local_date
  value.provenance.epoch = f.identity.epoch
  value.provenance.command_id = f.identity.replyId
  value.provenance.observed_at = f.profile.observed_at
  value.current_policy = structuredClone(projectCurrentClinicalPublicPolicy(f.profile))
  recorded.meal_kind = r.meal_type
  recorded.items = r.log_ids.map((id, index) => ({
    ...recorded.items[index % recorded.items.length],
    log_id: id,
  }))
  return { ...value, recorded }
}
