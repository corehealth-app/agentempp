import { describe, expect, it } from 'vitest'
import {
  conversationIntakeMediaEnabled,
  negotiateConversationIntakeMedia,
} from './conversation-intake-media-negotiation'

describe('explicit media-provenance negotiation', () => {
  it('preserves legacy clients unless they explicitly request provenance1', () => {
    expect(negotiateConversationIntakeMedia(new Headers())).toBe('legacy')
    expect(
      negotiateConversationIntakeMedia(new Headers({ 'X-Conversation-Media-Provenance': '1' })),
    ).toBe('1')
  })
  it.each(['', '0', '2', 'true', '1, 1'])('refuses unknown provenance selection %j', (value) => {
    expect(() =>
      negotiateConversationIntakeMedia(new Headers({ 'X-Conversation-Media-Provenance': value })),
    ).toThrow()
  })
  it('requires its own trusted opt-in and the complete existing staging intake capability', () => {
    const env = {
      NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
      MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
      MOBILE_CONVERSATION_COMMANDS_ENABLED: 'true',
      MOBILE_CONVERSATION_WORKOUT_COMMANDS_ENABLED: 'true',
      MOBILE_CONVERSATION_INTAKES_ENABLED: 'true',
      MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED: 'true',
    }
    expect(conversationIntakeMediaEnabled(env)).toBe(true)
    for (const key of Object.keys(env))
      expect(conversationIntakeMediaEnabled({ ...env, [key]: '' })).toBe(false)
    expect(
      conversationIntakeMediaEnabled({
        ...env,
        NEXT_PUBLIC_SUPABASE_URL: 'https://xuxehkhdvjivitduarvb.supabase.co',
      }),
    ).toBe(false)
  })
})
