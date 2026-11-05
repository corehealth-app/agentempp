import { describe, expect, it } from 'vitest'
import {
  CONVERSATION_FEEDBACK_PRESENTATION_HEADER,
  conversationFeedbackPresentationResponseHeaders,
  conversationFeedbackPresentationSchema,
  negotiateConversationFeedbackPresentation,
} from './conversation-feedback-presentation-negotiation'

describe('presentation-only explicit header negotiation', () => {
  it.each([
    null,
    '1',
    'v2',
    'V2',
    '02',
    '2, 2',
    '2; x=1',
  ])('keeps %s on the literal legacy presentation family', (value) => {
    const h = new Headers()
    if (value !== null) h.set(CONVERSATION_FEEDBACK_PRESENTATION_HEADER, value)
    const selected = negotiateConversationFeedbackPresentation(h)
    expect(selected).toBe('legacy')
    expect(conversationFeedbackPresentationSchema(selected, 'registration.feedback.v3')).toBe(null)
    expect(conversationFeedbackPresentationSchema(selected, 'registration.feedback.v2')).toBe(
      'conversation.feedback-presentation.v1',
    )
    expect(conversationFeedbackPresentationResponseHeaders(selected)).toEqual({})
  })
  it('selects only presentation2 and retains prior canonical identities', () => {
    const h = new Headers({ 'x-conversation-feedback-presentation': '2' })
    const selected = negotiateConversationFeedbackPresentation(h)
    h.set(CONVERSATION_FEEDBACK_PRESENTATION_HEADER, 'invalid-late-change')
    expect(selected).toBe('2')
    expect(conversationFeedbackPresentationSchema(selected, 'registration.feedback.v3')).toBe(
      'conversation.feedback-presentation.v2',
    )
    for (const schema of ['registration.feedback.v1', 'registration.feedback.v2'] as const)
      expect(conversationFeedbackPresentationSchema(selected, schema)).toBe(
        'conversation.feedback-presentation.v1',
      )
    expect(conversationFeedbackPresentationResponseHeaders(selected)).toEqual({
      'X-Conversation-Feedback-Presentation': '2',
      Vary: 'X-Conversation-Feedback-Presentation',
    })
    expect(Object.isFrozen(conversationFeedbackPresentationResponseHeaders(selected))).toBe(true)
  })
  it('does not accept duplicate header values as opt in', () => {
    const h = new Headers()
    h.append(CONVERSATION_FEEDBACK_PRESENTATION_HEADER, '2')
    h.append(CONVERSATION_FEEDBACK_PRESENTATION_HEADER, '2')
    expect(negotiateConversationFeedbackPresentation(h)).toBe('legacy')
  })
})
