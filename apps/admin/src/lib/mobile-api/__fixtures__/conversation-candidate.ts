import type { MobileAuthContext } from '../auth'
import type { ConversationJournalBinding } from '../conversation-command-candidate-contracts'
import { bindConversationCommand } from '../conversation-command-contracts'
import type { ConversationMealPreparation } from '../conversation-meal-preparation'

export const candidateOwner = '10000000-0000-4000-8000-000000000001'
export const candidateId = '10000000-0000-4000-8000-000000000002'
export const candidateEpoch = '10000000-0000-4000-8000-000000000003'
export const candidateAuth: MobileAuthContext = {
  userId: candidateOwner,
  authUserId: candidateOwner,
  accessToken: 'synthetic-local-token',
  identity: { id: candidateOwner, email: null, emailConfirmedAt: null },
  patient: {
    id: candidateOwner,
    authUserId: candidateOwner,
    status: 'active',
    locale: 'pt-BR',
    email: null,
    name: null,
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
  },
}
export function candidateCommand() {
  return bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: candidateId,
    kind: 'meal.report',
    meal_type: 'cafe',
    source: { channel: 'text', text: 'Comi arroz 200 g' },
  })
}
export function candidateBinding(): ConversationJournalBinding {
  const c = candidateCommand()
  return {
    owner_id: c.ownerId,
    command_id: c.commandId,
    input_hash: c.inputHash,
    command_protocol: 'conversation.command.v1',
    kind: 'meal.report',
    epoch: candidateEpoch,
    admitted_at: '2026-11-03T10:00:00.123456Z',
  }
}
export function candidatePreparation(): ConversationMealPreparation {
  return {
    status: 'prepared',
    command: candidateCommand(),
    intent: { decision: 'actual_report', basis: 'first_person_report', foodText: 'arroz 200 g' },
    draft: {
      source: 'text',
      media_asset_id: null,
      transcript: null,
      context_note: null,
      nutrition_label: null,
      extraction: { method: 'deterministic', model: null },
      items: [
        {
          candidate_id: 'c0-rice',
          name: 'arroz',
          quantity_g: 200,
          quantity_basis: 'stated',
          count: null,
          unit_label: null,
          confidence: null,
          needs_review: false,
          review_reason: null,
        },
      ],
    },
    mediaBinding: null,
    sourceEvidence: { caption: null, transcript: null },
  }
}
export function candidateEnvelope() {
  return {
    schema: 'conversation.meal-candidate.v1',
    input_hash: candidateCommand().inputHash,
    status: 'prepared',
    candidate: candidatePreparation(),
  }
}
export function candidateRead(attached = true) {
  return structuredClone({
    action: 'available',
    command: candidateBinding(),
    state: attached ? 'candidate_attached' : 'admitted',
    source_input: candidateCommand().command,
    candidate: attached ? candidateEnvelope() : null,
    candidate_hash: attached ? 'a'.repeat(64) : null,
  })
}
