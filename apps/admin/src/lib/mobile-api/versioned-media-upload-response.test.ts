import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from './route'
import {
  privateConversationMediaCatalogEnabled,
  versionedMediaUploadResponse,
} from './versioned-media-upload-response'

const env = {
  MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
  MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED: 'true',
  MOBILE_CONVERSATION_INTAKES_ENABLED: 'true',
  MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
}
describe('private upload server composition policy', () => {
  it('requires the explicit opt-in and existing qualified staging gates together', () => {
    expect(privateConversationMediaCatalogEnabled(env)).toBe(true)
    for (const [key, value] of Object.entries(env)) {
      expect(
        privateConversationMediaCatalogEnabled({
          ...env,
          [key]: value === 'true' ? 'false' : 'other-project',
        }),
      ).toBe(false)
    }
  })
  it('keeps the exact legacy response and performs no private SDK operation when off', async () => {
    const context = { supabase: {} as ServiceClient } as MobileRouteContext
    const original = Response.json({ data: 'legacy' }, { status: 201 })
    const legacy = vi.fn(async () => original)
    expect(
      await versionedMediaUploadResponse(
        context,
        { kind: 'audio_note', mime_type: 'audio/mp4', size_bytes: 8 },
        legacy,
        {},
      ),
    ).toBe(original)
    expect(legacy).toHaveBeenCalledTimes(1)
  })
  it('preserves clinical and document creation even when the private ordinary opt-in is on', async () => {
    const context = { supabase: {} as ServiceClient } as MobileRouteContext
    const original = Response.json({ data: 'dedicated existing kind' }, { status: 201 })
    expect(
      await versionedMediaUploadResponse(
        context,
        { kind: 'body_checkin_photo', mime_type: 'image/jpeg', size_bytes: 8 },
        async () => original,
        env,
      ),
    ).toBe(original)
    expect(
      await versionedMediaUploadResponse(
        context,
        { kind: 'plan_document', mime_type: 'application/pdf', size_bytes: 8 },
        async () => original,
        env,
      ),
    ).toBe(original)
  })
})
