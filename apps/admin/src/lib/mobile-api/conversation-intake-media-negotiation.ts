import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { conversationWorkoutCommandsEnabled } from './conversation-workout-command-routes'
import { MobileApiError } from './http'

/** A response-codec opt-in, never a client grant to upload, route or write. */
export type ConversationIntakeMediaNegotiation = 'legacy' | '1'
export function negotiateConversationIntakeMedia(
  headers: Headers,
): ConversationIntakeMediaNegotiation {
  const value = headers.get('X-Conversation-Media-Provenance')
  if (value === null) return 'legacy'
  if (value === '1') return '1'
  throw new MobileApiError(
    422,
    'conversation_intake_media_version_invalid',
    'Unsupported media provenance version',
  )
}
export function conversationIntakeMediaEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED === 'true' &&
    env.MOBILE_CONVERSATION_INTAKES_ENABLED === 'true' &&
    conversationMealCommandsEnabled(env) &&
    conversationWorkoutCommandsEnabled(env)
  )
}
