import { describe, expect, it } from 'vitest'
import {
  conversationPhotoMobileEnabled,
  conversationPhotoWorkerEnabled,
} from './conversation-photo-purpose.js'

const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
describe('explicit staging-only nonclinical photo purpose', () => {
  const mobile = {
    MOBILE_CONVERSATION_PHOTOS_ENABLED: 'true',
    MOBILE_CONVERSATION_INTAKES_ENABLED: 'true',
    MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    NEXT_PUBLIC_SUPABASE_URL: origin,
  }
  const worker = {
    MOBILE_CONVERSATION_PHOTOS_ENABLED: 'true',
    INNGEST_FUNCTION_SET: 'media-clinical-staging',
    SUPABASE_URL: origin,
  }
  it('requires every mobile capability and the exact current staging database', () => {
    expect(conversationPhotoMobileEnabled(mobile)).toBe(true)
    for (const key of Object.keys(mobile))
      expect(conversationPhotoMobileEnabled({ ...mobile, [key]: '' })).toBe(false)
    expect(
      conversationPhotoMobileEnabled({ ...mobile, NEXT_PUBLIC_SUPABASE_URL: `${origin}/` }),
    ).toBe(true)
  })
  it('supports the exact conversational staging worker with the same nonclinical opt-in and target guards', () => {
    const value = { ...worker, INNGEST_FUNCTION_SET: 'media-conversation-staging' }
    expect(conversationPhotoWorkerEnabled(value)).toBe(true)
    expect(
      conversationPhotoWorkerEnabled({ ...value, MOBILE_CONVERSATION_PHOTOS_ENABLED: 'false' }),
    ).toBe(false)
    expect(
      conversationPhotoWorkerEnabled({
        ...value,
        SUPABASE_URL: '',
        NEXT_PUBLIC_SUPABASE_URL: origin,
      }),
    ).toBe(false)
    expect(
      conversationPhotoWorkerEnabled({
        ...value,
        SUPABASE_URL: 'https://xuxehkhdvjivitduarvb.supabase.co',
      }),
    ).toBe(false)
  })
  it('requires the existing isolated worker set and respects an empty explicit URL', () => {
    expect(conversationPhotoWorkerEnabled(worker)).toBe(true)
    for (const key of Object.keys(worker))
      expect(conversationPhotoWorkerEnabled({ ...worker, [key]: '' })).toBe(false)
    expect(
      conversationPhotoWorkerEnabled({
        ...worker,
        SUPABASE_URL: '',
        NEXT_PUBLIC_SUPABASE_URL: origin,
      }),
    ).toBe(false)
    expect(
      conversationPhotoWorkerEnabled({ ...worker, INNGEST_FUNCTION_SET: 'media-staging' }),
    ).toBe(false)
  })
  it.each([
    'https://xuxehkhdvjivitduarvb.supabase.co',
    `${origin}/other`,
    `${origin}?key=anything`,
    'https://foreign.invalid',
  ])('refuses another target %s without fallback', (url) => {
    expect(conversationPhotoMobileEnabled({ ...mobile, NEXT_PUBLIC_SUPABASE_URL: url })).toBe(false)
    expect(conversationPhotoWorkerEnabled({ ...worker, SUPABASE_URL: url })).toBe(false)
  })
})
