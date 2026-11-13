import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { cleanupExpiredMedia, createRetentionDependencies } from './media-retention-cleanup.js'

const user = '11110000-0000-4000-8000-000000000001'
const asset = '11110000-0000-4000-8000-000000000002'
const claim = '11110000-0000-4000-8000-000000000003'
const path = `${user}/${asset}.m4a`
// Boundary double models non-upsert Storage effects, not provider concurrency.
// The break caught here is deleting an existing barrier or acknowledging bytes.
function arena(initial: number | null) {
  let size = initial
  let inspections = 0
  let acks = 0
  let removals = 0
  let uploads = 0
  let uncertain = false
  let competingPayload = false
  let invalidState = false
  let inspectionOverride: Record<string, unknown> = {}
  let failRemoval = false
  let failPostcondition = false
  let raceWithNewerBarrier = false
  let version = '11110000-0000-4000-8000-000000000004'
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'claim_conversation_media_expiry_batch')
        return {
          error: null,
          data: {
            schema: 'conversation.media-expiry-page.v1',
            items: [
              {
                asset_id: asset,
                user_id: user,
                kind: 'audio_note',
                bucket_id: 'audio-notes',
                object_path: path,
                claim_token: claim,
              },
            ],
            has_more: false,
          },
        }
      if (name === 'inspect_conversation_media_payload_revocation') {
        expect(args).toEqual({ p_asset_id: asset, p_user_id: user, p_claim_token: claim })
        inspections++
        return {
          error: null,
          data: {
            schema: 'conversation.media-revocation-state.v1',
            asset_id: invalidState ? user : asset,
            user_id: user,
            claim_token: claim,
            bucket_id: 'audio-notes',
            object_path: path,
            bucket_private: true,
            versioning: 'DISABLED',
            state:
              failPostcondition && inspections > 1
                ? 'payload'
                : size === null
                  ? 'absent'
                  : size === 0
                    ? 'empty'
                    : 'payload',
            size_bytes: failPostcondition && inspections > 1 ? 8 : size,
            mime_type: 'audio/mp4',
            object_version: size === null ? null : version,
            ...inspectionOverride,
          },
        }
      }
      if (name === 'acknowledge_conversation_media_expiry_sweep') {
        acks++
        return {
          error: null,
          data: {
            schema: 'conversation.media-expiry-ack.v1',
            asset_id: asset,
            user_id: user,
            claim_token: claim,
            state: 'waiting_for_issuance_drain',
          },
        }
      }
      throw Error('Unexpected synthetic RPC')
    },
    storage: {
      from: (bucket: string) => {
        expect(bucket).toBe('audio-notes')
        return {
          remove: async (paths: Array<string | { path: string; versionId: string }>) => {
            removals++
            if (failRemoval) return { error: new Error('private deletion response') }
            if (raceWithNewerBarrier) {
              size = 0
              version = '11110000-0000-4000-8000-000000000005'
            }
            const entry = paths[0]
            if (typeof entry !== 'string' && entry?.path === path && entry.versionId !== version)
              return { error: null }
            expect(typeof entry === 'string' ? entry : entry?.path).toBe(path)
            size = null
            if (raceWithNewerBarrier) size = 8 // A stale plain-path delete reopened the capability.
            return { error: null }
          },
          upload: async (key: string, body: Uint8Array, options: unknown) => {
            expect(key).toBe(path)
            expect(body.byteLength).toBe(0)
            expect(options).toEqual({ upsert: false, contentType: 'audio/mp4', cacheControl: '0' })
            uploads++
            if (competingPayload) {
              size = 8
              return { error: new Error('Duplicate') }
            }
            if (size !== null) return { error: new Error('Duplicate') }
            size = 0
            return { error: uncertain ? new Error('private provider failure') : null }
          },
        }
      },
    },
  } as unknown as ServiceClient
  return {
    run: () => cleanupExpiredMedia(createRetentionDependencies(client, { scope: 'conversation' })),
    state: () => ({ size, inspections, acks, removals, uploads }),
    uncertain: (v: boolean) => {
      uncertain = v
    },
    competing: (v: boolean) => {
      competingPayload = v
    },
    invalid: () => {
      invalidState = true
    },
    inspectAs: (v: Record<string, unknown>) => {
      inspectionOverride = v
    },
    failRemoval: () => {
      failRemoval = true
    },
    failPostcondition: () => {
      failPostcondition = true
    },
    raceWithNewerBarrier: () => {
      raceWithNewerBarrier = true
    },
  }
}
describe('ordinary media payload barrier', () => {
  it('removes original bytes and occupies the exact non-upsert path with zero bytes', async () => {
    const a = arena(8)
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 1, removals: 1, uploads: 1 })
  })
  it('preserves an existing empty object on every retry, without reopening the path', async () => {
    const a = arena(0)
    await a.run()
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 2, removals: 0, uploads: 0 })
  })
  it('seals an absent path without first removing anything', async () => {
    const a = arena(null)
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 1, removals: 0, uploads: 1 })
  })
  it('does not touch Storage or acknowledge an unbound inspection', async () => {
    const a = arena(8)
    a.invalid()
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 8, inspections: 1, acks: 0, removals: 0, uploads: 0 })
  })
  it('reconciles an uncertain successful write on retry without deleting that barrier', async () => {
    const a = arena(8)
    a.uncertain(true)
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 0, inspections: 1, acks: 0, removals: 1, uploads: 1 })
    a.uncertain(false)
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 1, removals: 1, uploads: 1 })
  })
  it('retains the obligation if a competing payload wins, then removes it on the next claim', async () => {
    const a = arena(null)
    a.competing(true)
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 8, inspections: 1, acks: 0, removals: 0, uploads: 1 })
    a.competing(false)
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 3, acks: 1, removals: 1, uploads: 2 })
  })
  it.each([
    { bucket_private: false },
    { versioning: 'ENABLED' },
    { user_id: asset },
    { claim_token: asset },
    { object_path: `${asset}/${asset}.m4a` },
    { bucket_id: 'meal-photos' },
    { mime_type: 'image/jpeg' },
    { state: 'empty', size_bytes: 8 },
    { state: 'absent', size_bytes: 0 },
    { size_bytes: -1 },
    { size_bytes: 26214401 },
    { undeclared_provider_field: true },
  ])('refuses malformed, mismatched or unsafe metadata before any write: %j', async (value) => {
    const a = arena(8)
    a.inspectAs(value)
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 8, inspections: 1, acks: 0, removals: 0, uploads: 0 })
  })
  it('does not replace or acknowledge a payload after failed removal', async () => {
    const a = arena(8)
    a.failRemoval()
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 8, inspections: 1, acks: 0, removals: 1, uploads: 0 })
  })
  it('does not acknowledge a successful provider response without an empty readback', async () => {
    const a = arena(null)
    a.failPostcondition()
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 0, removals: 0, uploads: 1 })
  })
  it('cannot erase a newer barrier when an old cleanup resumes after losing its lease', async () => {
    const a = arena(8)
    a.raceWithNewerBarrier()
    await expect(a.run()).rejects.toThrow('Conversation media revocation unavailable')
    expect(a.state()).toEqual({ size: 0, inspections: 1, acks: 0, removals: 1, uploads: 1 })
    await a.run()
    expect(a.state()).toEqual({ size: 0, inspections: 2, acks: 1, removals: 1, uploads: 1 })
  })
})
