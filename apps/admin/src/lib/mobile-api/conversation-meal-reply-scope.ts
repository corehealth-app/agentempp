/** Reply compatibility boundary over the shared existing-account observer. */
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  type ConversationCurrentScopeDependencies,
  type ConversationReadonlyAuth,
  createConversationCurrentScope,
} from './conversation-current-scope'
import {
  type ConversationMealContinuationReadIdentity,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import type { ConversationMealContinuationScope } from './conversation-meal-continuation-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export {
  authenticateConversationPatientReadonly as authenticateConversationReplyPatient,
  createConversationReadonlyAuth as createConversationMealReplyReadonlyAuth,
} from './conversation-current-scope'
export type ConversationMealReplyReadonlyAuth = ConversationReadonlyAuth
export type ConversationMealReplyScopeDependencies = ConversationCurrentScopeDependencies

export function createConversationMealReplyScope(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  rawIdentity: ConversationMealContinuationReadIdentity,
  dependencies: ConversationMealReplyScopeDependencies = {},
) {
  const auth = freezeInterpretation(
      detachConversationContinuationReadJson(originalAuth) as MobileAuthContext,
    ),
    owner = authenticatedReevaluationOwner(auth),
    identity = parseConversationMealContinuationReadIdentity(rawIdentity)
  if (owner !== identity.ownerId || !identity.replyId || !identity.replyInputHash)
    throw new MobileApiError(
      409,
      'conversation_patient_changed',
      'The original authenticated patient scope is unavailable',
    )
  return createConversationCurrentScope<ConversationMealContinuationScope>(
    db,
    auth,
    {
      authUserId: auth.authUserId,
      ownerId: owner,
      epoch: identity.epoch,
      parentCommandId: identity.parentCommandId,
      replyId: identity.replyId,
    },
    dependencies,
  )
}
export type ConversationMealReplyScope = ReturnType<typeof createConversationMealReplyScope>
