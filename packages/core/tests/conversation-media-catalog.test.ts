import { describe, expect, it, vi } from 'vitest'
import { createPrivateMediaCatalogV2 } from '../src/conversation-media-catalog'

const user = 'c3671000-0000-4000-8000-000000000001'
const asset = 'c3671000-0000-4000-8000-000000000002'
const other = 'c3671000-0000-4000-8000-000000000003'
const scope = { userId: user, assetId: asset }
const at = '2026-11-17T12:00:00.000Z'
const row = {
  id: asset,
  user_id: user,
  kind: 'audio_note',
  bucket_id: 'audio-notes',
  object_path: `conversation-v2/${user}/${asset}.m4a`,
  mime_type: 'audio/mp4',
  declared_size_bytes: 8,
  actual_size_bytes: null,
  etag: null,
  status: 'pending_upload',
  failure_stage: null,
  failure_code: null,
  context_text: null,
  processing_request_id: null,
  processing_result: null,
  source_request_hash: 'a'.repeat(64),
  retention_until: '2026-12-17T12:00:00.000Z',
  uploaded_at: null,
  processed_at: null,
  deleted_at: null,
  created_at: at,
  updated_at: at,
}
const reply = { schema: 'conversation.media-asset.v2', catalog_version: 2, asset: row }

describe('private media catalog RPC ports', () => {
  it('uses only the exact owner and one private read selector', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: reply, error: null })
    const catalog = createPrivateMediaCatalogV2(rpc)
    expect(await catalog.findOwned(scope)).toEqual(row)
    expect(rpc).toHaveBeenCalledWith('get_conversation_media_asset_v2', {
      p_user_id: user,
      p_asset_id: asset,
      p_source_request_hash: null,
    })
    expect(await catalog.findByRequestHash(user, 'a'.repeat(64))).toEqual(row)
    expect(rpc).toHaveBeenLastCalledWith('get_conversation_media_asset_v2', {
      p_user_id: user,
      p_asset_id: null,
      p_source_request_hash: 'a'.repeat(64),
    })
  })

  it('does not fall back to the public catalog when absent or unavailable', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: null })
      .mockResolvedValueOnce({ data: null, error: { code: '42P01', message: 'private detail' } })
    const catalog = createPrivateMediaCatalogV2(rpc)
    expect(await catalog.findOwned(scope)).toBeNull()
    await expect(catalog.findOwned(scope)).rejects.toMatchObject({
      kind: 'unavailable',
      message: 'Private media operation unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it.each([
    { ...reply, catalog_version: 1 },
    {
      ...reply,
      asset: { ...row, user_id: other, object_path: `conversation-v2/${other}/${asset}.m4a` },
    },
    { ...reply, asset: { ...row, id: other, object_path: `conversation-v2/${user}/${other}.m4a` } },
    { ...reply, asset: { ...row, object_path: `${user}/${asset}.m4a` } },
  ])('refuses an unbound source returned by a port', async (data) => {
    const catalog = createPrivateMediaCatalogV2(vi.fn().mockResolvedValue({ data, error: null }))
    await expect(catalog.findOwned(scope)).rejects.toThrow('Private media operation unavailable')
  })

  it('validates the requested immutable source on creation, including a concurrent replay', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: reply, error: null })
    const catalog = createPrivateMediaCatalogV2(rpc)
    const input = {
      userId: user,
      assetId: other,
      kind: 'audio_note' as const,
      mimeType: 'audio/mp4',
      declaredSizeBytes: 8,
      contextText: null,
      sourceRequestHash: 'a'.repeat(64),
    }
    expect(await catalog.create(input)).toEqual(row)
    expect(rpc).toHaveBeenCalledWith('create_conversation_media_asset_v2', {
      p_user_id: user,
      p_asset_id: other,
      p_kind: 'audio_note',
      p_mime_type: 'audio/mp4',
      p_declared_size_bytes: 8,
      p_context_text: null,
      p_source_request_hash: 'a'.repeat(64),
    })
    await expect(catalog.create({ ...input, contextText: 'different' })).rejects.toThrow(
      'Private media operation unavailable',
    )
    await expect(catalog.create({ ...input, sourceRequestHash: 'b'.repeat(64) })).rejects.toThrow(
      'Private media operation unavailable',
    )
  })

  it('snapshots the owner before awaiting an RPC', async () => {
    let resolve: (value: unknown) => void = () => undefined
    const rpc = vi.fn().mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    const mutable = { ...scope },
      catalog = createPrivateMediaCatalogV2(rpc)
    const read = catalog.findOwned(mutable)
    mutable.userId = other
    resolve({ data: reply, error: null })
    expect(await read).toEqual(row)
    expect(rpc.mock.calls[0]?.[1].p_user_id).toBe(user)
  })

  it('requires actual boolean acknowledgments without retrying a lost processing claim', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: false, error: null })
      .mockResolvedValueOnce({ data: 'true', error: null })
    const catalog = createPrivateMediaCatalogV2(rpc)
    expect(
      await catalog.completeProcessing(scope, 'c'.repeat(64), other, { text: 'Leite com whey' }),
    ).toBe(false)
    await expect(
      catalog.failProcessing(scope, 'c'.repeat(64), other, 'provider_error'),
    ).rejects.toThrow('Private media operation unavailable')
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it('sanitizes database and transport failures without disclosing provider data', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: { code: '40001', message: 'do not expose' } })
      .mockRejectedValueOnce(new Error('do not expose either'))
    const catalog = createPrivateMediaCatalogV2(rpc)
    await expect(catalog.findOwned(scope)).rejects.toMatchObject({
      kind: 'changed',
      message: 'Private media operation unavailable',
    })
    await expect(catalog.findOwned(scope)).rejects.toMatchObject({
      kind: 'unavailable',
      message: 'Private media operation unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(2)
  })
})
