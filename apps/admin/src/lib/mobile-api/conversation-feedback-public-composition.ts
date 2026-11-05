/** Actual immutable canonical reads composed with the separate current-safe
 * renderer. This adapter does not admit, prepare or commit a domain effect. */
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import type { ConversationCurrentScopeDependencies } from './conversation-current-scope'
import { createConversationFeedbackPresentationV2Service } from './conversation-feedback-presentation-v2'
import {
  type ConversationFeedbackV3OriginalBridge,
  createConversationFeedbackV3OriginalBridge,
} from './conversation-feedback-v3-original-bridge'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'

export interface ConversationFeedbackPublicCompositionDependencies
  extends ConversationCurrentScopeDependencies {
  readonly original?: ConversationFeedbackV3OriginalBridge
}
export function createConversationFeedbackPublicComposition(
  db: ServiceClient,
  auth: MobileAuthContext,
  epoch: string,
  deps: ConversationFeedbackPublicCompositionDependencies = {},
) {
  const bridge = deps.original ?? createConversationFeedbackV3OriginalBridge(db, auth, epoch, deps),
    readRoot = bridge.readRoot.bind(bridge),
    readReply = bridge.readReply.bind(bridge),
    readWorkout = bridge.readWorkout.bind(bridge),
    ensureRoot = bridge.ensureRoot.bind(bridge),
    ensureReply = bridge.ensureReply.bind(bridge),
    ensureWorkout = bridge.ensureWorkout.bind(bridge),
    service = createConversationFeedbackPresentationV2Service(db, {
      ...(deps.auth ? { auth: deps.auth } : {}),
      ...(deps.clinical ? { clinical: deps.clinical } : {}),
      original: {
        async readOriginal(input) {
          const p = input.proof
          switch (p.kind) {
            case 'meal.report':
              return readRoot({
                auth: input.auth,
                command: p.command,
                serverBinding: conversationJournalBindingSchema.parse(p.serverBinding),
                receipt: p.receipt,
              })
            case 'meal.clarify':
              return readReply({
                auth: input.auth,
                binding: parseConversationMealContinuationFeedbackBinding(p.binding),
              })
            case 'workout.report':
              return readWorkout({ source: p.source, prepared: p.prepared, effect: p.effect })
          }
        },
      },
    })
  return Object.freeze({
    readHistorical: service.readHistorical.bind(service),
    readRoot,
    ensureRoot,
    ensureReply,
    ensureWorkout,
  })
}
export type ConversationFeedbackPublicComposition = ReturnType<
  typeof createConversationFeedbackPublicComposition
>
export type ConversationFeedbackPublicCompositionFactory = (
  auth: MobileAuthContext,
  epoch: string,
) => ConversationFeedbackPublicComposition
