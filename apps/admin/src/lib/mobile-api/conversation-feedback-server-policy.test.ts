import { describe, expect, it } from 'vitest'
import { conversationFeedbackV3WriterEnabled } from './conversation-feedback-server-policy'

const staging = {
  MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
}
describe('trusted additive canonical writer policy', () => {
  it('requires exact3 and the established explicit staging target', () => {
    expect(
      conversationFeedbackV3WriterEnabled({
        ...staging,
        MOBILE_CONVERSATION_FEEDBACK_VERSION: '3',
      }),
    ).toBe(true)
    for (const value of [undefined, '', '2', '03', ' 3', '3 '])
      expect(
        conversationFeedbackV3WriterEnabled({
          ...staging,
          MOBILE_CONVERSATION_FEEDBACK_VERSION: value,
        }),
      ).toBe(false)
    for (const env of [
      {},
      { ...staging, NEXT_PUBLIC_SUPABASE_URL: 'https://other.supabase.co' },
      { ...staging, MOBILE_CURRENT_CLINICAL_PROJECT_REF: undefined },
    ])
      expect(
        conversationFeedbackV3WriterEnabled({ ...env, MOBILE_CONVERSATION_FEEDBACK_VERSION: '3' }),
      ).toBe(false)
  })
  it('never interprets a presentation header as writer policy', () => {
    expect(
      conversationFeedbackV3WriterEnabled({
        ...staging,
        'X-Conversation-Feedback-Presentation': '2',
      }),
    ).toBe(false)
  })
})
