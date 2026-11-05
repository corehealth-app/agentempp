/** Presentation compatibility only. No canonical writer/version, permission,
 * command bytes/hash, receipt or idempotency key is selected here. */
export const CONVERSATION_FEEDBACK_PRESENTATION_HEADER = 'X-Conversation-Feedback-Presentation'
export type ConversationFeedbackPresentationNegotiation = 'legacy' | '2'
export function negotiateConversationFeedbackPresentation(
  headers: Pick<Headers, 'get'>,
): ConversationFeedbackPresentationNegotiation {
  return headers.get(CONVERSATION_FEEDBACK_PRESENTATION_HEADER) === '2' ? '2' : 'legacy'
}
export function conversationFeedbackPresentationSchema(
  selected: ConversationFeedbackPresentationNegotiation,
  canonicalSchema:
    | 'registration.feedback.v1'
    | 'registration.feedback.v2'
    | 'registration.feedback.v3',
): 'conversation.feedback-presentation.v1' | 'conversation.feedback-presentation.v2' | null {
  if (canonicalSchema !== 'registration.feedback.v3') return 'conversation.feedback-presentation.v1'
  return selected === '2' ? 'conversation.feedback-presentation.v2' : null
}
/** Header fragment only; a route must merge Vary with any existing fields and
 * retain its authenticated no-store response. Existing protocol headers stay. */
export function conversationFeedbackPresentationResponseHeaders(
  selected: ConversationFeedbackPresentationNegotiation,
): Readonly<Record<string, string>> {
  if (selected === '2')
    return Object.freeze({
      [CONVERSATION_FEEDBACK_PRESENTATION_HEADER]: '2',
      Vary: CONVERSATION_FEEDBACK_PRESENTATION_HEADER,
    })
  return Object.freeze({})
}

/** Authenticated route merge. The established Authorization variance remains. */
export function conversationFeedbackPresentationMobileHeaders(
  selected: ConversationFeedbackPresentationNegotiation,
): Readonly<Record<string, string>> {
  const fragment = conversationFeedbackPresentationResponseHeaders(selected)
  return selected === '2'
    ? Object.freeze({ ...fragment, Vary: `Authorization, ${fragment.Vary}` })
    : fragment
}
