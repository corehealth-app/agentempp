import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import {
  cleanupExpiredMedia,
  createRetentionDependencies,
} from '../../../../../packages/inngest-functions/src/functions/media-retention-cleanup.js'
import {
  createMediaAsset,
  type MediaAssetRecord,
  type MediaServiceDependencies,
} from './media-service.js'

const user = '11110000-0000-4000-8000-000000000001'
const id = '11110000-0000-4000-8000-000000000002'
const claim = '11110000-0000-4000-8000-000000000003'
const path = `${user}/${id}.m4a`
const expiry = '2026-11-12T12:00:00.000Z'
function arena() {
  const row = {
    id,
    user_id: user,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: path,
    mime_type: 'audio/mp4',
    declared_size_bytes: 100,
    actual_size_bytes: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: expiry,
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: '2026-10-13T12:00:00.000Z',
    updated_at: expiry,
  } as MediaAssetRecord
  const objects = new Set<string>()
  let barrier = false
  let debt = false
  class Query {
    private write = false
    private filters: Array<(r: MediaAssetRecord) => boolean> = []
    select() {
      return this
    }
    update() {
      this.write = true
      return this
    }
    eq(k: string, v: unknown) {
      this.filters.push((r) => r[k as keyof MediaAssetRecord] === v)
      return this
    }
    neq(k: string, v: unknown) {
      this.filters.push((r) => r[k as keyof MediaAssetRecord] !== v)
      return this
    }
    is() {
      return this
    }
    in(_k: string, vs: string[]) {
      this.filters.push((r) => vs.includes(r.kind))
      return this
    }
    lte() {
      return this
    }
    order() {
      return this
    }
    limit() {
      return this
    }
    // biome-ignore lint/suspicious/noThenProperty: controlled database query boundary
    then(resolve: (v: unknown) => unknown) {
      const matches = this.filters.every((f) => f(row))
      if (this.write && matches) row.status = 'deleted'
      return Promise.resolve({ data: matches ? [{ ...row }] : [], error: null }).then(resolve)
    }
  }
  const client = {
    from: () => new Query(),
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'claim_conversation_media_expiry_batch') {
        debt = true
        row.status = 'deleted'
        return {
          error: null,
          data: {
            schema: 'conversation.media-expiry-page.v1',
            items: [
              {
                asset_id: id,
                user_id: user,
                kind: row.kind,
                bucket_id: row.bucket_id,
                object_path: path,
                claim_token: claim,
              },
            ],
            has_more: false,
          },
        }
      }
      if (name === 'acknowledge_conversation_media_expiry_sweep') {
        expect(args).toEqual({ p_asset_id: id, p_user_id: user, p_claim_token: claim })
        return {
          error: null,
          data: {
            schema: 'conversation.media-expiry-ack.v1',
            asset_id: id,
            user_id: user,
            claim_token: claim,
            state: 'waiting_for_issuance_drain',
          },
        }
      }
      if (name === 'inspect_conversation_media_payload_revocation')
        return {
          error: null,
          data: {
            schema: 'conversation.media-revocation-state.v1',
            asset_id: id,
            user_id: user,
            claim_token: claim,
            bucket_id: 'audio-notes',
            object_path: path,
            bucket_private: true,
            versioning: 'DISABLED',
            mime_type: 'audio/mp4',
            state: objects.has(path) ? 'payload' : barrier ? 'empty' : 'absent',
            size_bytes: objects.has(path) ? 8 : barrier ? 0 : null,
            object_version:
              objects.has(path) || barrier ? '11110000-0000-4000-8000-000000000004' : null,
          },
        }
      throw Error('Unexpected synthetic RPC')
    },
    storage: {
      from: () => ({
        remove: async () => {
          objects.delete(path)
          barrier = false
          return { error: null }
        },
        upload: async () => {
          if (objects.has(path) || barrier) return { error: new Error('Duplicate') }
          barrier = true
          return { error: null }
        },
      }),
    },
  } as unknown as ServiceClient
  const media = {
    repository: { findByRequestHash: async () => structuredClone(row) },
    storage: {
      createSignedUpload: async () => ({ signedUrl: 'https://synthetic.invalid/upload' }),
    },
  } as unknown as MediaServiceDependencies
  return { row, client, media, objects, hasDebt: () => debt, hasBarrier: () => barrier }
}
const authorize = (a: ReturnType<typeof arena>) =>
  createMediaAsset(
    a.media,
    user,
    { kind: 'audio_note', mime_type: 'audio/mp4', size_bytes: 100 },
    'original-key',
    new Date('2026-11-12T11:59:00.000Z'),
  )
const sweep = (a: ReturnType<typeof arena>) =>
  cleanupExpiredMedia(
    createRetentionDependencies(a.client, { scope: 'conversation' }),
    new Date('2026-11-12T12:01:00.000Z'),
  )

describe('ordinary expiry versus already authorized legacy uploads', () => {
  it('keeps durable cleanup debt when bytes arrive after a successful sweep', async () => {
    const a = arena()
    expect((await authorize(a)).upload).not.toBeNull()
    await sweep(a)
    expect(a.row.status).toBe('deleted')
    a.objects.add(path) // A valid Storage capability does not consult the catalog.
    await sweep(a)
    expect(a.objects.size).toBe(0)
    expect(a.hasDebt()).toBe(true)
    expect(a.hasBarrier()).toBe(true)
  })
  it('also recovers a legacy signing request that finishes after the first tombstone', async () => {
    const a = arena()
    let finish!: () => void
    const barrier = new Promise<void>((resolve) => {
      finish = resolve
    })
    a.media.storage.createSignedUpload = async () => {
      await barrier
      return { signedUrl: 'https://synthetic.invalid/late-upload' }
    }
    const request = authorize(a)
    await Promise.resolve()
    await sweep(a)
    finish()
    expect((await request).upload).not.toBeNull()
    a.objects.add(path)
    await sweep(a)
    expect(a.objects.size).toBe(0)
    expect(a.hasDebt()).toBe(true)
    expect(a.hasBarrier()).toBe(true)
  })
})
