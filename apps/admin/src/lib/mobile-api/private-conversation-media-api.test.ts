import { createHash } from 'node:crypto'
import type { PrivateMediaAssetV2 } from '@mpp/core/conversation-media'
import { describe, expect, it, vi } from 'vitest'
import {
  createVersionedConversationMediaUpload,
  type VersionedConversationMediaCreationPorts,
} from './private-conversation-media-api'

const owner = 'c1700000-0000-4000-8000-000000000001'
const assetId = 'c1700000-0000-4000-8000-000000000002'
const key = 'private-upload-170'
const hash = createHash('sha256').update(key).digest('hex')
const at = '2026-11-17T19:00:00.000Z',
  until = '2026-12-17T19:00:00.000Z'
const input = {
  kind: 'audio_note' as const,
  mime_type: 'audio/mp4' as const,
  size_bytes: 8,
  context_text: 'Consumido leite com whey',
  duration_ms: 1000,
}
function setup(version: 1 | 2 | null = null) {
  const row: PrivateMediaAssetV2 = {
    id: assetId,
    user_id: owner,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: `conversation-v2/${owner}/${assetId}.m4a`,
    mime_type: 'audio/mp4',
    declared_size_bytes: 8,
    actual_size_bytes: null,
    etag: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: input.context_text,
    processing_request_id: null,
    processing_result: null,
    source_request_hash: hash,
    retention_until: until,
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: at,
    updated_at: at,
  }
  const upload = {
    signed_url: 'https://private.invalid/synthetic',
    method: 'PUT' as const,
    headers: { 'Content-Type': 'audio/mp4', 'x-upsert': 'false' },
    expires_at: '2026-11-17T21:00:00.000Z',
  }
  const ports = {
    enabled: () => true,
    photoEnabled: () => true,
    now: () => new Date(at),
    nonce: () => assetId,
    resolve: vi.fn(async () =>
      version === null
        ? null
        : {
            schema: 'conversation.media-catalog.v2',
            catalog_version: version,
            asset_id: assetId,
            user_id: owner,
            kind: 'audio_note',
          },
    ),
    catalog: {
      create: vi.fn(
        async (
          _input: Parameters<VersionedConversationMediaCreationPorts['catalog']['create']>[0],
        ) => row,
      ),
      findOwned: vi.fn(async () => row),
      findByRequestHash: vi.fn(async () => row),
    },
    issue: vi.fn(async () => upload),
  }
  return { row, upload, ports }
}
describe('versioned conversational media creation', () => {
  it('uses a disjoint private source for a genuinely new ordinary upload and keeps the public DTO', async () => {
    const x = setup()
    const result = await createVersionedConversationMediaUpload(x.ports, owner, input, key)
    expect(result).toEqual({
      action: 'private',
      value: {
        asset: {
          id: assetId,
          kind: 'audio_note',
          mime_type: 'audio/mp4',
          size_bytes: 8,
          status: 'pending_upload',
          failure_stage: null,
          failure_code: null,
          has_context: true,
          retention_until: until,
          uploaded_at: null,
          processed_at: null,
          deleted_at: null,
          result: null,
          created_at: at,
          updated_at: at,
        },
        upload: x.upload,
        replayed: false,
      },
    })
    expect(x.ports.resolve).toHaveBeenCalledWith(owner, hash)
    expect(x.ports.catalog.create).toHaveBeenCalledWith({
      userId: owner,
      assetId,
      kind: 'audio_note',
      mimeType: 'audio/mp4',
      declaredSizeBytes: 8,
      contextText: input.context_text,
      sourceRequestHash: hash,
    })
    expect(JSON.stringify(result)).not.toContain('conversation-v2/')
  })
  it('returns a proved old request to the existing handler without trying a private create or signer', async () => {
    const x = setup(1)
    expect(await createVersionedConversationMediaUpload(x.ports, owner, input, key)).toEqual({
      action: 'legacy',
    })
    expect(x.ports.catalog.create).not.toHaveBeenCalled()
    expect(x.ports.catalog.findByRequestHash).not.toHaveBeenCalled()
    expect(x.ports.issue).not.toHaveBeenCalled()
  })
  it('replays the proved private source rather than creating another asset', async () => {
    const x = setup(2)
    const result = await createVersionedConversationMediaUpload(x.ports, owner, input, key)
    expect(result.action === 'private' && result.value.replayed).toBe(true)
    expect(x.ports.catalog.create).not.toHaveBeenCalled()
    expect(x.ports.issue).toHaveBeenCalledTimes(1)
  })
  it('does no private IO when the trusted feature is off', async () => {
    const x = setup()
    x.ports.enabled = () => false
    expect(await createVersionedConversationMediaUpload(x.ports, owner, input, key)).toEqual({
      action: 'legacy',
    })
    expect(x.ports.resolve).not.toHaveBeenCalled()
  })
  it('keeps nonconversational and clinical creation on the existing handler', async () => {
    const x = setup()
    expect(
      await createVersionedConversationMediaUpload(
        x.ports,
        owner,
        { kind: 'body_checkin_photo', mime_type: 'image/jpeg', size_bytes: 8 },
        key,
      ),
    ).toEqual({ action: 'legacy' })
    expect(x.ports.resolve).not.toHaveBeenCalled()
  })
  it('refuses a foreign routing proof before a signer or catalog lookup', async () => {
    const x = setup(2)
    x.ports.resolve.mockResolvedValue({
      schema: 'conversation.media-catalog.v2',
      catalog_version: 2,
      asset_id: assetId,
      user_id: assetId,
      kind: 'audio_note',
    })
    await expect(
      createVersionedConversationMediaUpload(x.ports, owner, input, key),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    expect(x.ports.issue).not.toHaveBeenCalled()
  })
  it('refuses changed private source properties instead of signing another purpose', async () => {
    const x = setup(2)
    x.row.context_text = 'Outra declaração'
    await expect(
      createVersionedConversationMediaUpload(x.ports, owner, input, key),
    ).rejects.toMatchObject({ code: 'idempotency_key_conflict' })
    expect(x.ports.issue).not.toHaveBeenCalled()
  })
  it('retains the original input across asynchronous catalog resolution', async () => {
    const x = setup()
    const original = { ...input }
    x.ports.resolve.mockImplementation(async () => {
      original.context_text = 'Outro usuário'
      return null
    })
    await createVersionedConversationMediaUpload(x.ports, owner, original, key)
    expect(x.ports.catalog.create.mock.calls[0]?.[0]).toMatchObject({
      contextText: input.context_text,
    })
  })
  it('does not fall back to legacy creation after an uncertain private commit', async () => {
    const x = setup()
    x.ports.catalog.create.mockRejectedValue(Error('private SQL uncertain'))
    await expect(
      createVersionedConversationMediaUpload(x.ports, owner, input, key),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    expect(x.ports.issue).not.toHaveBeenCalled()
  })
  it('refuses declared long audio before catalog creation', async () => {
    const x = setup()
    await expect(
      createVersionedConversationMediaUpload(
        x.ports,
        owner,
        { ...input, duration_ms: 180001 },
        key,
      ),
    ).rejects.toMatchObject({ code: 'audio_too_long' })
    expect(x.ports.resolve).not.toHaveBeenCalled()
  })
  it('returns an already processed technical retry without a new upload capability', async () => {
    const x = setup(2)
    Object.assign(x.row, {
      status: 'processed',
      actual_size_bytes: 8,
      uploaded_at: at,
      processed_at: at,
      processing_request_id: 'a'.repeat(64),
      processing_result: { text: 'Leite com whey' },
    })
    const result = await createVersionedConversationMediaUpload(x.ports, owner, input, key)
    expect(result.action === 'private' && result.value.upload).toBe(null)
    expect(result.action === 'private' && result.value.asset.result).toEqual({
      text: 'Leite com whey',
    })
    expect(x.ports.issue).not.toHaveBeenCalled()
  })
  it('refuses withdrawn private purpose after the signer wait without returning the capability', async () => {
    const x = setup()
    let enabled = true
    x.ports.enabled = () => enabled
    x.ports.issue.mockImplementation(async () => {
      enabled = false
      return x.upload
    })
    await expect(
      createVersionedConversationMediaUpload(x.ports, owner, input, key),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
  })
  it('refuses an invalid clock after the final source read', async () => {
    const x = setup()
    x.ports.catalog.findOwned.mockImplementation(async () => {
      x.ports.now = () => new Date(Number.NaN)
      return x.row
    })
    await expect(
      createVersionedConversationMediaUpload(x.ports, owner, input, key),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
  })
})
