import {
  parseFeedbackV3Registration,
  prepareRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import linkedActual from '../../../../../ios/BodyFlow/BodyFlowTests/Fixtures/ConversationLinkedActualHTTPFixtures.json'
import rootActual from '../../../../../ios/BodyFlow/BodyFlowTests/Fixtures/FlowMealEditLifecycleFixtures.json'
import { bindConversationCommand } from '../conversation-command-contracts'
import type { ConversationFeedbackPresentationV2Proof } from '../conversation-feedback-presentation-v2'
import { projectCurrentClinicalPublicPolicy } from '../current-clinical-read-model'
import { readCurrentClinicalState } from '../current-clinical-state'
import { replyFixture } from './conversation-meal-reply'
import { clinical } from './feedback-v2-source'

// UNIT canonical3 from genuine immutable receipt facts. Not an HTTP canonical3
// observation, reseal, conversion or new persisted registration.
function requireValue<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) throw new Error('Missing genuine fixture value')
  return value
}

export function publicFeedbackV3Fixture(kind: 'root' | 'linked' = 'root') {
  const packet =
    kind === 'root' ? rootActual.original_saved.data : linkedActual.saved_reply.packet.data
  const receipt = packet.receipt
  const source = kind === 'root' ? rootActual : linkedActual
  const who = structuredClone(replyFixture().auth)
  who.authUserId = source.auth_user_id
  who.identity.id = source.auth_user_id
  who.patient.authUserId = source.auth_user_id
  who.userId = receipt.owner_id
  who.patient.id = receipt.owner_id
  const state = clinical()
  state.user_id = receipt.owner_id
  state.health_state.user_id = receipt.owner_id
  state.epoch = packet.epoch
  state.date = state.safety.date = receipt.local_date
  state.observed_at = state.safety.observed_at = requireValue(
    packet.feedback,
  ).provenance.observed_at
  const proof: ConversationFeedbackPresentationV2Proof =
    kind === 'root'
      ? {
          kind: 'meal.report',
          command: bindConversationCommand(
            receipt.owner_id,
            `cmsg1:${rootActual.original_command.command_id}`,
            rootActual.original_command,
          ),
          serverBinding: {
            owner_id: receipt.owner_id,
            command_id: receipt.command_id,
            input_hash: receipt.input_hash,
            command_protocol: 'conversation.command.v1',
            kind: 'meal.report',
            epoch: packet.epoch,
            admitted_at: rootActual.original_saved.data.admitted_at,
          },
          receipt,
        }
      : {
          kind: 'meal.clarify',
          binding: {
            parentBinding: linkedActual.saved_reply.packet.data.parent_binding,
            childBinding: linkedActual.saved_reply.packet.data.child_binding,
            parentDecisionHash: linkedActual.saved_reply.packet.data.parent_decision_hash,
            receipt,
          },
        }
  const parsedState = readCurrentClinicalState(state, receipt.owner_id)
  const canonical = prepareRegistrationFeedbackV3({
    registrationId: receipt.registration_id,
    localDate: receipt.local_date,
    locale: 'pt-BR',
    registration: parseFeedbackV3Registration(requireValue(packet.feedback).recorded),
    officialDay: null,
    policy: projectCurrentClinicalPublicPolicy(parsedState),
    educationAvailable: false,
  })
  return {
    who,
    state: { ...structuredClone(parsedState), epoch: requireValue(parsedState.epoch) },
    proof,
    canonical,
    receipt,
    legacyPresentation: packet.feedback,
  }
}
