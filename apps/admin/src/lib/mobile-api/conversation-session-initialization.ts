import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  assertConversationReadonlyNonAdmin,
  type ConversationReadonlyAuth,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
  parseConversationReadonlyIdentity,
  parseConversationReadonlyPatient,
} from './conversation-current-scope'
import type { ConversationSessionObservation } from './conversation-meal-command-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  conversationJournalInstant,
  conversationJournalUUID,
} from './conversation-meal-journal-store'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'
import { createSupabaseSignupStrengthAuthoritySource } from './supabase-signup-strength-authority'

export interface ConversationSessionInitializationPorts {
  auth?: ConversationReadonlyAuth
  clinical?: CurrentClinicalStateSource
  initializeEpoch?: (input: { userId: string }) => Promise<{ userId: string; epoch: string }>
}
export function createConversationSessionInitialization(
  db: ServiceClient,
  ports: ConversationSessionInitializationPorts = {},
) {
  const auth = ports.auth ?? createConversationReadonlyAuth(db),
    clinical = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    initializeEpoch =
      ports.initializeEpoch ?? createSupabaseSignupStrengthAuthoritySource(db).observe
  // Initialization is an explicit operation, never a fallback in a reader.
  // The existing RPC locks the owner and inserts only an absent authority row;
  // it cannot rotate an existing epoch or admit a historical command.
  return Object.freeze({
    async initialize(original: MobileAuthContext): Promise<ConversationSessionObservation> {
      try {
        const who = freezeInterpretation(structuredClone(original)),
          owner = authenticatedReevaluationOwner(who),
          subject = conversationJournalUUID.parse(who.authUserId)
        const verify = async () => {
          const identity = parseConversationReadonlyIdentity(
            await auth.verifyAccessToken(who.accessToken),
          )
          if (identity.id !== subject || identity.id !== who.identity.id) throw changed()
          assertConversationReadonlyNonAdmin(await auth.isAdmin(identity.id))
          const patient = parseConversationReadonlyPatient(
            await auth.loadPatient(identity.id),
            identity.id,
          )
          if (patient.id !== owner) throw changed()
        }
        await verify()
        const before = await captureCurrentClinicalState(clinical, {
          userId: owner,
          mode: 'profile',
        })
        if (!before.profile_present || before.generation_token?.onboarding_completed !== true) {
          throw new MobileApiError(
            409,
            'conversation_session_profile_required',
            'Complete the existing profile before opening conversation',
          )
        }
        await verify()
        let epoch = before.epoch
        if (epoch === null) {
          const initialized = await initializeEpoch({ userId: owner })
          if (initialized.userId !== owner) throw unavailable()
          epoch = conversationJournalUUID.parse(initialized.epoch)
        }
        const scope = createConversationCurrentScope(
            db,
            who,
            { authUserId: subject, ownerId: owner, epoch },
            { auth, clinical },
          ),
          final = await scope.observe()
        if (
          conversationJournalInstant(final.observed_at) <
          conversationJournalInstant(before.observed_at)
        )
          throw new MobileApiError(
            409,
            'conversation_scope_changed',
            'Conversation observation changed',
          )
        return freezeInterpretation({
          schema: 'conversation.session.v1',
          auth_user_id: subject,
          owner_id: owner,
          epoch,
          observed_at: final.observed_at,
          meal_command_protocol: 'conversation.command.v1',
        })
      } catch (error) {
        if (error instanceof MobileApiError) throw error
        throw unavailable()
      }
    },
  })
}
function unavailable() {
  return new MobileApiError(
    503,
    'conversation_session_initialization_unavailable',
    'Session initialization unavailable',
  )
}
function changed() {
  return new MobileApiError(
    409,
    'conversation_patient_changed',
    'The authenticated patient has changed',
  )
}
