import { createHash } from 'node:crypto'
import type { PrivateMediaAssetV2 } from '@mpp/core/conversation-media'
import { describe, expect, it, vi } from 'vitest'
import { ownedConversationMediaOperation } from './private-conversation-media-owned'

const owner = 'c1710000-0000-4000-8000-000000000001'
const id = 'c1710000-0000-4000-8000-000000000002'
const at = '2026-11-17T20:00:00.000Z'
const until = '2026-12-17T20:00:00.000Z'
const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
function setup(version: 1 | 2 | null = 2) {
  const row: PrivateMediaAssetV2 = {
    id,
    user_id: owner,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: `conversation-v2/${owner}/${id}.m4a`,
    mime_type: 'audio/mp4',
    declared_size_bytes: 8,
    actual_size_bytes: null,
    etag: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: 'Leite com whey',
    processing_request_id: null,
    processing_result: null,
    source_request_hash: createHash('sha256').update('r171').digest('hex'),
    retention_until: until,
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: at,
    updated_at: at,
  }
  const url = `${origin}/storage/v1/object/sign/audio-notes/conversation-v2/${owner}/${id}.m4a?token=synthetic-only`
  const ports = {
    enabled: () => true,
    photoEnabled: () => true,
    now: () => new Date(at),
    storageOrigin: origin,
    resolve: vi.fn(async () =>
      version === null
        ? null
        : {
            schema: 'conversation.media-catalog.v2',
            catalog_version: version,
            asset_id: id,
            user_id: owner,
            kind: 'audio_note',
          },
    ),
    catalog: {
      findOwned: vi.fn(async () => ({ ...row })),
      completeUpload: vi.fn(
        async (_scope: unknown, info: { size: number; mimeType: string; etag: string | null }) => {
          Object.assign(row, {
            status: 'uploaded',
            actual_size_bytes: info.size,
            etag: info.etag,
            uploaded_at: at,
          })
          return { ...row }
        },
      ),
    },
    info: vi.fn(async () => ({ size: 8, contentType: 'audio/mp4; codecs=mp4a', etag: 'etag' })),
    signDownload: vi.fn(async () => ({ signedUrl: url })),
    close: vi.fn(async () => {
      Object.assign(row, { status: 'deleted', deleted_at: at })
      return true
    }),
  }
  return { row, ports, url }
}
describe('owned private media read and completion', () => {
  it('completes the exact declared private upload and exposes only the existing public DTO', async () => {
    const x = setup()
    const result = await ownedConversationMediaOperation(x.ports, owner, id, 'complete')
    expect(result).toMatchObject({
      action: 'private',
      value: {
        id,
        kind: 'audio_note',
        status: 'uploaded',
        size_bytes: 8,
        uploaded_at: at,
        result: null,
      },
    })
    expect(x.ports.catalog.completeUpload).toHaveBeenCalledWith(
      { userId: owner, assetId: id },
      { size: 8, mimeType: 'audio/mp4', etag: 'etag' },
    )
    expect(JSON.stringify(result)).not.toContain('conversation-v2/')
    expect(x.ports.close).not.toHaveBeenCalled()
  })
  it('replays an already completed upload without rereading bytes or changing the source', async () => {
    const x = setup()
    Object.assign(x.row, {
      status: 'uploaded',
      actual_size_bytes: 8,
      uploaded_at: at,
      etag: 'etag',
    })
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'complete')).toMatchObject({
      action: 'private',
      value: { status: 'uploaded' },
    })
    expect(x.ports.info).not.toHaveBeenCalled()
    expect(x.ports.catalog.completeUpload).not.toHaveBeenCalled()
  })
  it('delegates a proved legacy source without private read or Storage access', async () => {
    const x = setup(1)
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'read')).toEqual({
      action: 'legacy',
    })
    expect(x.ports.catalog.findOwned).not.toHaveBeenCalled()
    expect(x.ports.signDownload).not.toHaveBeenCalled()
  })
  it('uses no private IO when the opt-in is off', async () => {
    const x = setup()
    x.ports.enabled = () => false
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'complete')).toEqual({
      action: 'legacy',
    })
    expect(x.ports.resolve).not.toHaveBeenCalled()
  })
  it('returns not found for a missing routing proof, without trying another catalog', async () => {
    const x = setup(null)
    await expect(ownedConversationMediaOperation(x.ports, owner, id, 'read')).rejects.toMatchObject(
      { code: 'media_not_found' },
    )
    expect(x.ports.catalog.findOwned).not.toHaveBeenCalled()
  })
  it('refuses foreign source proof before any private read', async () => {
    const x = setup()
    x.ports.resolve.mockResolvedValue({
      schema: 'conversation.media-catalog.v2',
      catalog_version: 2,
      asset_id: id,
      user_id: id,
      kind: 'audio_note',
    })
    await expect(ownedConversationMediaOperation(x.ports, owner, id, 'read')).rejects.toMatchObject(
      { code: 'media_catalog_unavailable' },
    )
    expect(x.ports.catalog.findOwned).not.toHaveBeenCalled()
  })
  it('never exposes a newly substituted private source', async () => {
    const x = setup()
    x.ports.catalog.findOwned.mockResolvedValue({
      ...x.row,
      user_id: id,
      object_path: `conversation-v2/${id}/${id}.m4a`,
    })
    await expect(ownedConversationMediaOperation(x.ports, owner, id, 'read')).rejects.toMatchObject(
      { code: 'media_catalog_unavailable' },
    )
    expect(x.ports.signDownload).not.toHaveBeenCalled()
  })
  it('does not issue downloads for pending or deleted sources', async () => {
    const x = setup()
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'read')).toMatchObject({
      action: 'private',
      value: { status: 'pending_upload', download: null },
    })
    Object.assign(x.row, { status: 'deleted', deleted_at: at })
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'read')).toMatchObject({
      action: 'private',
      value: { status: 'deleted', download: null },
    })
    expect(x.ports.signDownload).not.toHaveBeenCalled()
  })
  it('signs only the selected private path, with the existing five minute maximum', async () => {
    const x = setup()
    Object.assign(x.row, { status: 'uploaded', actual_size_bytes: 8, uploaded_at: at })
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'read')).toMatchObject({
      action: 'private',
      value: { download: { signed_url: x.url, expires_in_seconds: 300 } },
    })
    expect(x.ports.signDownload).toHaveBeenCalledWith(
      expect.objectContaining({
        asset_id: id,
        user_id: owner,
        object_path: `conversation-v2/${owner}/${id}.m4a`,
      }),
      300,
    )
  })
  it('bounds download lifetime by the actual remaining retention', async () => {
    const x = setup()
    Object.assign(x.row, { status: 'uploaded', actual_size_bytes: 8, uploaded_at: at })
    x.ports.now = () => new Date(Date.parse(until) - 3200)
    expect(await ownedConversationMediaOperation(x.ports, owner, id, 'read')).toMatchObject({
      action: 'private',
      value: { download: { expires_in_seconds: 3 } },
    })
  })
  it('refuses expired media without reading bytes or issuing a download', async () => {
    const x = setup()
    x.ports.now = () => new Date(until)
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_expired' })
    expect(x.ports.info).not.toHaveBeenCalled()
  })
  it.each([
    { size: 9, contentType: 'audio/mp4', etag: 'etag' },
    { size: 8, contentType: 'image/png', etag: 'etag' },
    { size: 0, contentType: 'audio/mp4', etag: 'etag' },
  ])('closes durable disposal authority for a mismatched object %j', async (info) => {
    const x = setup()
    x.ports.info.mockResolvedValue(info)
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_upload_mismatch' })
    expect(x.ports.close).toHaveBeenCalledWith(owner, id)
    expect(x.ports.catalog.completeUpload).not.toHaveBeenCalled()
  })
  it('closes a missing upload without marking it complete', async () => {
    const x = setup()
    x.ports.info.mockResolvedValue(null as never)
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_upload_missing' })
    expect(x.ports.close).toHaveBeenCalledWith(owner, id)
  })
  it('keeps uncertain Storage failure retryable without pretending the object is missing', async () => {
    const x = setup()
    x.ports.info.mockRejectedValue(Error('Storage unavailable'))
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    expect(x.ports.close).not.toHaveBeenCalled()
  })
  it('refuses an uncertain disposal commit rather than reporting a successful close', async () => {
    const x = setup()
    x.ports.info.mockResolvedValue({ size: 9, contentType: 'audio/mp4', etag: 'etag' })
    x.ports.close.mockResolvedValue(false)
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
  })
  it('never returns a capability when the source is disposed during signing', async () => {
    const x = setup()
    Object.assign(x.row, { status: 'uploaded', actual_size_bytes: 8, uploaded_at: at })
    x.ports.signDownload.mockImplementation(async () => {
      Object.assign(x.row, { status: 'deleted', deleted_at: at })
      return { signedUrl: x.url }
    })
    await expect(ownedConversationMediaOperation(x.ports, owner, id, 'read')).rejects.toMatchObject(
      { code: 'media_catalog_unavailable' },
    )
  })
  it('refuses a download for another key or Storage origin', async () => {
    for (const url of [
      'https://foreign.invalid/storage/v1/object/sign/audio-notes/file?token=x',
      `${origin}/storage/v1/object/sign/audio-notes/another.m4a?token=x`,
    ]) {
      const x = setup()
      Object.assign(x.row, { status: 'uploaded', actual_size_bytes: 8, uploaded_at: at })
      x.ports.signDownload.mockResolvedValue({ signedUrl: url })
      await expect(
        ownedConversationMediaOperation(x.ports, owner, id, 'read'),
      ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    }
  })
  it('refuses a clock or gate withdrawal after Storage completion', async () => {
    const x = setup()
    x.ports.catalog.completeUpload.mockImplementation(async () => {
      x.ports.enabled = () => false
      return { ...x.row, status: 'uploaded', actual_size_bytes: 8, uploaded_at: at }
    })
    await expect(
      ownedConversationMediaOperation(x.ports, owner, id, 'complete'),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
  })
})
