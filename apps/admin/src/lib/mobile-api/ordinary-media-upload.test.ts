import { describe, expect, it, vi } from 'vitest'
import type { MediaAssetRecord } from './media-service'
import {
  issueOrdinaryMediaUpload,
  type OrdinaryMediaUploadDependencies,
} from './ordinary-media-upload'

const id = (n: number) => `11110000-0000-4000-8000-${String(n).padStart(12, '0')}`
const origin = 'https://synthetic.invalid',
  now = new Date('2026-11-13T03:00:00.000Z')
function setup() {
  const asset = {
    id: id(2),
    user_id: id(1),
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: `${id(1)}/${id(2)}.m4a`,
    mime_type: 'audio/mp4',
    size_bytes: 100,
    status: 'pending_upload',
    retention_until: '2026-12-13T03:00:00.000Z',
  }
  const original = {
    ...asset,
    declared_size_bytes: 100,
    actual_size_bytes: null,
    failure_stage: null,
    failure_code: null,
    context_text: null,
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
  } as MediaAssetRecord
  const ticket = {
    id: id(3),
    asset_id: asset.id,
    user_id: asset.user_id,
    prepared_at: now.toISOString(),
    provider_expires_at: null,
    registered_at: null,
  }
  const expiry = '2026-11-13T05:00:15.000Z'
  const order: string[] = [],
    persisted: string[] = []
  const token = (claims: Record<string, unknown>) =>
    [
      Buffer.from('{"alg":"HS256"}').toString('base64url'),
      Buffer.from(JSON.stringify(claims)).toString('base64url'),
      Buffer.from('synthetic-signature').toString('base64url'),
    ].join('.')
  const url = (expires = expiry) =>
    `${origin}/storage/v1/object/upload/sign/${asset.bucket_id}/${asset.object_path}?token=${token({ exp: Date.parse(expires) / 1000, url: `${asset.bucket_id}/${asset.object_path}`, upsert: false })}`
  const prepared = {
    schema: 'conversation.upload-prepared.v1',
    asset: structuredClone(asset),
    ticket: structuredClone(ticket),
  }
  const receipt = (expires: string) => ({
    schema: 'conversation.upload-registered.v1',
    ticket: { ...ticket, provider_expires_at: expires, registered_at: now.toISOString() },
  })
  const deps: OrdinaryMediaUploadDependencies = {
    storageOrigin: origin,
    now: () => now,
    nonce: () => id(3),
    prepare: vi.fn(async () => {
      order.push('prepare')
      return structuredClone(prepared)
    }),
    sign: vi.fn(async () => {
      order.push('sign')
      return { signedUrl: url() }
    }),
    register: vi.fn(async (_scope, _ticket, expires) => {
      order.push('register')
      persisted.push(expires)
      return receipt(expires)
    }),
    current: vi.fn(async () => {
      order.push('current')
      return { schema: 'conversation.upload-state.v1', asset: structuredClone(asset) }
    }),
  }
  return { asset, original, ticket, expiry, deps, order, persisted, prepared, receipt, url, token }
}
describe('tracked ordinary media signing lifecycle', () => {
  it('prepares before signing and registers actual provider expiry before checking current authority', async () => {
    const a = setup()
    const result = await issueOrdinaryMediaUpload(a.deps, a.original)
    expect(a.order).toEqual(['prepare', 'sign', 'register', 'current'])
    expect(a.persisted).toEqual([a.expiry])
    expect(result.expires_at).toBe(a.expiry)
    expect(result.signed_url).toBe(a.url())
    expect(result.headers).toEqual({ 'Content-Type': 'audio/mp4', 'x-upsert': 'false' })
  })
  it('never returns a capability before its expiry registration completes', async () => {
    const a = setup()
    let finish!: (v: unknown) => void
    let returned = false
    a.deps.register = async () => {
      a.order.push('register')
      return new Promise((resolve) => {
        finish = resolve
      })
    }
    const pending = issueOrdinaryMediaUpload(a.deps, a.original).then((v) => {
      returned = true
      return v
    })
    for (let i = 0; i < 5 && !finish; i++) await Promise.resolve()
    expect(finish).toBeTypeOf('function')
    expect(returned).toBe(false)
    finish(a.receipt(a.expiry))
    await pending
    expect(returned).toBe(true)
  })
  it('keeps signing uncertainty as an unregistered obligation and exposes no raw error', async () => {
    const a = setup()
    a.deps.sign = async () => {
      a.order.push('sign')
      throw Error('private token provider-response')
    }
    const failure = await issueOrdinaryMediaUpload(a.deps, a.original).catch((e) => e)
    expect(failure).toMatchObject({ status: 503, code: 'ordinary_media_upload_unavailable' })
    expect(a.order).toEqual(['prepare', 'sign'])
    expect(String(failure)).not.toContain('private token')
  })
  it('withholds the URL if registration fails without canceling or bypassing its obligation', async () => {
    const a = setup()
    a.deps.register = async () => {
      a.order.push('register')
      throw Error('private SQL or URL')
    }
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 503,
    })
    expect(a.order).toEqual(['prepare', 'sign', 'register'])
  })
  it('persists the issued expiry even when disposal closes authority during signing', async () => {
    const a = setup()
    a.deps.current = async () => null
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 409,
    })
    expect(a.persisted).toEqual([a.expiry])
  })
  it('refuses mismatched prepared ownership before calling Storage', async () => {
    const a = setup()
    a.deps.prepare = async () => ({ ...a.prepared, asset: { ...a.asset, user_id: id(99) } })
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 503,
    })
    expect(a.order).toEqual([])
  })
  it.each([
    'https://foreign.invalid/ticket',
    'https://synthetic.invalid/storage/v1/object/upload/sign/foreign/path?token=not-valid',
  ])('refuses unbound provider URLs without propagating them: %s', async (bad) => {
    const a = setup()
    a.deps.sign = async () => ({ signedUrl: bad })
    const failure = await issueOrdinaryMediaUpload(a.deps, a.original).catch((e) => e)
    expect(failure).toMatchObject({ status: 503 })
    expect(String(failure)).not.toContain(bad)
    expect(a.persisted).toEqual([])
  })
  it('persists an anomalously long actual expiry but never returns its capability', async () => {
    const a = setup(),
      long = '2030-11-13T05:00:00.000Z'
    a.deps.sign = async () => ({ signedUrl: a.url(long) })
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 503,
    })
    expect(a.persisted).toEqual([long])
    expect(a.order).not.toContain('current')
  })
  it('refuses an acknowledgment bound to another ticket', async () => {
    const a = setup()
    a.deps.register = async () => ({
      ...a.receipt(a.expiry),
      ticket: { ...a.receipt(a.expiry).ticket, id: id(77) },
    })
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 503,
    })
    expect(a.order).not.toContain('current')
  })
  it('refuses a changed current purpose after successful registration', async () => {
    const a = setup()
    a.deps.current = async () => ({
      schema: 'conversation.upload-state.v1',
      asset: { ...a.asset, kind: 'conversation_photo', bucket_id: 'meal-photos' },
    })
    await expect(issueOrdinaryMediaUpload(a.deps, a.original)).rejects.toMatchObject({
      status: 503,
    })
    expect(a.persisted).toEqual([a.expiry])
  })
})
