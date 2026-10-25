import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  issueReevaluationPhotoUpload,
  type PhotoUploadAsset,
  type PreparedPhotoUpload,
} from './reevaluation-photo-upload'
import { createSupabaseReevaluationPhotoUploadDependencies } from './supabase-reevaluation-photo-upload'

const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const scope = { userId: uid(1), cycleId: uid(2), assetId: uid(3) }
const at = '2026-10-25T01:00:00.000000Z'
function setup() {
  const asset: PhotoUploadAsset = {
    id: uid(3),
    user_id: uid(1),
    signup_generation: uid(4),
    cycle_id: uid(2),
    consent_acceptance_id: uid(5),
    origin: 'reevaluation_cycle_v1',
    pose: 'front',
    bucket_id: 'body-checkin-photos',
    object_path: `${uid(1)}/${uid(3)}.jpg`,
    mime_type: 'image/jpeg',
    size_bytes: 1200,
    status: 'pending_upload',
    created_at: at,
    retention_until: '2026-10-26T01:00:00.000000Z',
  }
  const prepared: PreparedPhotoUpload = {
    version: 1,
    cycle_revision: '2',
    asset,
    ticket: {
      id: uid(6),
      asset_id: uid(3),
      user_id: uid(1),
      signup_generation: uid(4),
      cycle_id: uid(2),
      consent_acceptance_id: uid(5),
      prepared_at: at,
      provider_expires_at: null,
      registered_at: null,
    },
  }
  const rpc = vi.fn(async (_name: string, _args: Record<string, string>) => ({
    data: structuredClone(prepared) as unknown,
    error: null as unknown,
  }))
  const sign = vi.fn(async () => ({
    data: { signedUrl: 'https://storage.test/unused', path: asset.object_path, token: 'unused' },
    error: null,
  }))
  const from = vi.fn(() => ({ createSignedUploadUrl: sign }))
  const client = { rpc, storage: { from } } as unknown as ServiceClient
  const deps = createSupabaseReevaluationPhotoUploadDependencies(client, {
    storageOrigin: 'https://test-project.supabase.co',
  })
  return { asset, prepared, rpc, sign, from, deps }
}
describe('dedicated recurring upload RPC adapter', () => {
  it('real service and adapter persist the actual capability expiry before exposing its URL', async () => {
    const f = setup()
    const expiry = '2026-10-25T03:00:15.000Z'
    const token = [
      Buffer.from('{"alg":"HS256"}').toString('base64url'),
      Buffer.from(
        JSON.stringify({
          exp: Date.parse(expiry) / 1000,
          url: `${f.asset.bucket_id}/${f.asset.object_path}`,
          upsert: false,
        }),
      ).toString('base64url'),
      Buffer.from('synthetic-signature').toString('base64url'),
    ].join('.')
    const signedUrl = `https://test-project.supabase.co/storage/v1/object/upload/sign/${f.asset.bucket_id}/${f.asset.object_path}?token=${token}`
    f.sign.mockResolvedValue({ data: { signedUrl, token, path: f.asset.object_path }, error: null })
    f.rpc
      .mockResolvedValueOnce({ data: f.prepared, error: null })
      .mockResolvedValueOnce({
        data: {
          version: 1,
          ticket: {
            ...f.prepared.ticket,
            provider_expires_at: expiry.replace('.000Z', '.000000Z'),
            registered_at: at,
          },
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: { version: 1, cycle_revision: '2', asset: f.asset },
        error: null,
      })
    f.deps.nonce = () => uid(6)
    f.deps.now = () => new Date(at)
    const result = await issueReevaluationPhotoUpload(f.deps, scope)
    expect(result.upload.signed_url).toBe(signedUrl)
    expect(result.upload.expires_at).toBe(expiry)
    expect(f.from).toHaveBeenCalledWith('body-checkin-photos')
    expect(f.sign).toHaveBeenCalledWith(f.asset.object_path, { upsert: false })
    expect(f.rpc.mock.calls.map((call) => call[0])).toEqual([
      'prepare_mobile_reevaluation_photo_upload',
      'register_mobile_reevaluation_photo_upload_ticket',
      'get_mobile_reevaluation_photo_asset',
    ])
    expect(f.rpc.mock.invocationCallOrder[0]).toBeLessThan(f.sign.mock.invocationCallOrder[0] ?? 0)
    expect(f.sign.mock.invocationCallOrder[0]).toBeLessThan(f.rpc.mock.invocationCallOrder[1] ?? 0)
  })
  it('uses the exact trusted prepare RPC and validates full returned scope', async () => {
    const f = setup()
    expect(await f.deps.prepare(scope, uid(6))).toEqual(f.prepared)
    expect(f.rpc).toHaveBeenCalledWith('prepare_mobile_reevaluation_photo_upload', {
      p_user_id: uid(1),
      p_cycle_id: uid(2),
      p_asset_id: uid(3),
      p_ticket_id: uid(6),
    })
    expect(f.sign).not.toHaveBeenCalled()
  })
  it.each([
    'asset',
    'owner',
    'cycle',
    'acceptance',
    'ticket',
  ])('rejects the wrong %s in an otherwise valid response', async (field) => {
    const f = setup()
    const bad = structuredClone(f.prepared)
    if (field === 'asset') bad.asset.id = uid(99)
    if (field === 'owner') bad.asset.user_id = uid(99)
    if (field === 'cycle') bad.asset.cycle_id = uid(99)
    if (field === 'acceptance') bad.ticket.consent_acceptance_id = uid(99)
    if (field === 'ticket') bad.ticket.id = uid(99)
    f.rpc.mockResolvedValue({ data: bad, error: null })
    await expect(f.deps.prepare(scope, uid(6))).rejects.toMatchObject({ status: 503 })
    expect(f.sign).not.toHaveBeenCalled()
  })
  it('records expiry in a separate RPC without silently retrying', async () => {
    const f = setup()
    const expiry = '2026-10-25T03:00:00.000Z'
    const receipt = {
      version: 1,
      ticket: {
        ...f.prepared.ticket,
        provider_expires_at: expiry.replace('.000Z', '.000000Z'),
        registered_at: at,
      },
    }
    f.rpc.mockResolvedValue({ data: receipt, error: null })
    expect(await f.deps.register(f.prepared, expiry)).toEqual(receipt)
    expect(f.rpc).toHaveBeenCalledOnce()
    expect(f.rpc).toHaveBeenCalledWith('register_mobile_reevaluation_photo_upload_ticket', {
      p_user_id: uid(1),
      p_cycle_id: uid(2),
      p_asset_id: uid(3),
      p_ticket_id: uid(6),
      p_provider_expires_at: expiry,
    })
  })
  it('current null remains unavailable; database errors never expose provider text', async () => {
    const f = setup()
    f.rpc.mockResolvedValueOnce({ data: null, error: null })
    expect(await f.deps.current(scope)).toBeNull()
    f.rpc.mockResolvedValue({
      data: null,
      error: { code: '40001', message: 'secret provider URL' },
    })
    const error = await f.deps.current(scope).catch((e: Error) => e)
    expect(error).toMatchObject({ status: 409 })
    expect(String(error)).not.toContain('secret')
  })
})
