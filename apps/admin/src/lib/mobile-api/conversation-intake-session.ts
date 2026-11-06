/** Genuine neutral protocol discovery from a fresh existing-account profile.
 * No typed command, temporary ID, bootstrap, epoch creation or writer exists. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  authenticateConversationPatientReadonly,
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
} from './conversation-current-scope'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { captureCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

function unavailable() {
  return new MobileApiError(503, 'conversation_intake_unavailable', 'Intake is unavailable')
}
export function createConversationIntakeSessionService(
  db: ServiceClient,
  ports: ConversationCurrentScopeDependencies & { readonly enabled?: () => boolean } = {},
) {
  const enabled = ports.enabled?.bind(ports) ?? (() => false)
  return Object.freeze({
    async read(originalAuth: MobileAuthContext) {
      let closed: MobileApiError | null = null
      function available() {
        if (closed) throw closed
        try {
          if (enabled() !== true) throw unavailable()
        } catch {
          closed = unavailable()
          throw closed
        }
      }
      available()
      const auth = workoutSnapshot(originalAuth),
        owner = authenticatedReevaluationOwner(auth),
        a = ports.auth ?? createConversationReadonlyAuth(db),
        authPort = Object.freeze({
          verifyAccessToken: a.verifyAccessToken.bind(a),
          loadPatient: a.loadPatient.bind(a),
          isAdmin: a.isAdmin.bind(a),
        }),
        c = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
        capture = c.capture.bind(c),
        clinical = Object.freeze({
          async capture(request: Parameters<typeof capture>[0]) {
            available()
            const result = workoutSnapshot(await capture(request))
            available()
            return result
          },
        })
      async function authorize() {
        available()
        try {
          const current = await authenticateConversationPatientReadonly(
            new Request('https://internal.invalid/intake-session', {
              headers: { authorization: `Bearer ${auth.accessToken}` },
            }),
            authPort,
          )
          available()
          if (
            !isDeepStrictEqual(
              [current.authUserId, current.userId, current.identity.id],
              [auth.authUserId, owner, auth.identity.id],
            )
          )
            throw new MobileApiError(
              409,
              'conversation_patient_changed',
              'Original patient has changed',
            )
        } catch (error) {
          closed = error instanceof MobileApiError ? error : unavailable()
          throw closed
        }
      }
      await authorize()
      let initial: Awaited<ReturnType<typeof captureCurrentClinicalState>>
      try {
        initial = workoutSnapshot(
          await captureCurrentClinicalState(clinical, { userId: owner, mode: 'profile' }),
        )
      } catch (error) {
        await authorize()
        throw error
      }
      await authorize()
      const epoch = workoutUUID.parse(initial.epoch),
        lane = createConversationCurrentScope(
          db,
          auth,
          { authUserId: auth.authUserId, ownerId: owner, epoch },
          { auth: authPort, clinical },
        ),
        final = workoutSnapshot(await lane.observe())
      available()
      if (
        conversationJournalInstant(final.observed_at) <
        conversationJournalInstant(initial.observed_at)
      )
        throw new MobileApiError(
          409,
          'conversation_scope_changed',
          'Current observation is unavailable',
        )
      return workoutSnapshot({
        schema: 'conversation.intake-session.v1' as const,
        auth_user_id: auth.authUserId,
        owner_id: owner,
        epoch,
        observed_at: final.observed_at,
        intake_protocol: 'conversation.intake.v1' as const,
      })
    },
  })
}
