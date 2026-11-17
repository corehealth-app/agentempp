import { describe, expect, it, vi } from 'vitest'
import { issuePrivateConversationMediaUpload } from './private-conversation-media-upload'

const owner = 'c3672000-0000-4000-8000-000000000001'
const asset = 'c3672000-0000-4000-8000-000000000002'
const ticketId = 'c3672000-0000-4000-8000-000000000003'
const at = '2026-11-17T12:00:00.000Z',
  until = '2026-12-17T12:00:00.000Z'
const expiry = '2026-11-17T14:00:00.000Z',
  origin = 'https://storage.example.invalid'
const identity = {
  catalog_version: 2 as const,
  asset_id: asset,
  user_id: owner,
  kind: 'audio_note' as const,
  bucket_id: 'audio-notes' as const,
  object_path: `conversation-v2/${owner}/${asset}.m4a`,
  mime_type: 'audio/mp4' as const,
  declared_size_bytes: 8,
}
const source = {
  id: asset,
  user_id: owner,
  kind: 'audio_note' as const,
  bucket_id: 'audio-notes' as const,
  object_path: identity.object_path,
  mime_type: identity.mime_type,
  declared_size_bytes: 8,
  actual_size_bytes: null,
  etag: null,
  status: 'pending_upload' as const,
  failure_stage: null,
  failure_code: null,
  context_text: null,
  processing_request_id: null,
  processing_result: null,
  source_request_hash: 'a'.repeat(64),
  retention_until: until,
  uploaded_at: null,
  processed_at: null,
  deleted_at: null,
  created_at: at,
  updated_at: at,
}
const wire = {
  identity,
  state: { status: 'pending_upload', created_at: at, retention_until: until },
}
const ticket = {
  id: ticketId,
  asset_id: asset,
  user_id: owner,
  prepared_at: at,
  provider_expires_at: null,
  registered_at: null,
}
function url(overrides: Record<string, unknown> = {}) {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url')
  const token = `${encode({ alg: 'HS256' })}.${encode({ url: `audio-notes/${identity.object_path}`, exp: Date.parse(expiry) / 1000, upsert: false, ...overrides })}.c2lnbmF0dXJl`
  return `${origin}/storage/v1/object/upload/sign/audio-notes/${identity.object_path}?token=${token}`
}
function fixture() {
  const order: string[] = []
  const catalog = {
    prepareUpload: vi.fn().mockImplementation(async () => {
      order.push('prepare')
      return {
        schema: 'conversation.upload-prepared.v2',
        asset: structuredClone(wire),
        ticket: structuredClone(ticket),
      }
    }),
    registerUpload: vi.fn().mockImplementation(async (_scope, _id, actualExpiry) => {
      order.push('register')
      return {
        schema: 'conversation.upload-registered.v2',
        ticket: {
          ...ticket,
          provider_expires_at: actualExpiry,
          registered_at: '2026-11-17T12:00:01.000Z',
        },
      }
    }),
    uploadState: vi.fn().mockImplementation(async () => {
      order.push('current')
      return { schema: 'conversation.upload-state.v2', asset: structuredClone(wire) }
    }),
  }
  const deps = {
    catalog,
    storageOrigin: origin,
    nonce: () => ticketId,
    now: () => new Date('2026-11-17T12:00:01.000Z'),
    sign: vi.fn().mockImplementation(async () => {
      order.push('sign')
      return { signedUrl: url() }
    }),
  }
  return { deps, catalog, order }
}

describe('private conversational media upload issuance', () => {
  it('persists preparation and real expiry before rereading the current private scope', async () => {
    const { deps, order } = fixture()
    expect(await issuePrivateConversationMediaUpload(deps, source)).toEqual({
      signed_url: url(),
      method: 'PUT',
      headers: { 'Content-Type': 'audio/mp4', 'x-upsert': 'false' },
      expires_at: expiry,
    })
    expect(order).toEqual(['prepare', 'sign', 'register', 'current'])
    expect(deps.catalog.prepareUpload).toHaveBeenCalledWith(
      { userId: owner, assetId: asset },
      ticketId,
    )
    expect(deps.catalog.registerUpload).toHaveBeenCalledWith(
      { userId: owner, assetId: asset },
      ticketId,
      expiry,
    )
    expect(deps.sign).toHaveBeenCalledWith(identity)
  })

  it('never signs a changed source returned by preparation', async () => {
    const { deps } = fixture()
    deps.catalog.prepareUpload.mockResolvedValue({
      schema: 'conversation.upload-prepared.v2',
      asset: { ...wire, identity: { ...identity, declared_size_bytes: 9 } },
      ticket,
    })
    await expect(issuePrivateConversationMediaUpload(deps, source)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(deps.sign).not.toHaveBeenCalled()
    expect(deps.catalog.registerUpload).not.toHaveBeenCalled()
  })

  it.each([
    'foreign-origin',
    'wrong-path',
    'upsert',
    'extra-query',
  ])('refuses an unexpected returned capability: %s', async (change) => {
    const { deps } = fixture()
    const signedUrl =
      change === 'foreign-origin'
        ? url().replace(origin, 'https://other.example.invalid')
        : change === 'wrong-path'
          ? url().replace('conversation-v2/', 'legacy/')
          : change === 'upsert'
            ? url({ upsert: true })
            : `${url()}&extra=1`
    deps.sign.mockResolvedValue({ signedUrl })
    await expect(issuePrivateConversationMediaUpload(deps, source)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(deps.catalog.registerUpload).not.toHaveBeenCalled()
  })

  it('retains the observed expiry before refusing an expired response', async () => {
    const { deps, order } = fixture()
    deps.sign.mockImplementation(async () => {
      order.push('sign')
      return { signedUrl: url({ exp: Date.parse(at) / 1000 }) }
    })
    await expect(issuePrivateConversationMediaUpload(deps, source)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(order).toEqual(['prepare', 'sign', 'register', 'current'])
    expect(deps.catalog.registerUpload).toHaveBeenCalledWith(
      { userId: owner, assetId: asset },
      ticketId,
      at,
    )
  })

  it('records a late signing response even when the catalog has since disappeared', async () => {
    const { deps, order } = fixture()
    deps.catalog.uploadState.mockImplementation(async () => {
      order.push('current')
      return null
    })
    await expect(issuePrivateConversationMediaUpload(deps, source)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(order).toEqual(['prepare', 'sign', 'register', 'current'])
    expect(deps.sign).toHaveBeenCalledTimes(1)
  })

  it('does not automatically repeat an uncertain signing request', async () => {
    const { deps } = fixture()
    deps.sign.mockRejectedValue(new Error('do not expose provider error'))
    await expect(issuePrivateConversationMediaUpload(deps, source)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(deps.catalog.prepareUpload).toHaveBeenCalledTimes(1)
    expect(deps.sign).toHaveBeenCalledTimes(1)
    expect(deps.catalog.registerUpload).not.toHaveBeenCalled()
  })
})
