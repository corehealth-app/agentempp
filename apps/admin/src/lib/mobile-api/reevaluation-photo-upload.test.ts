import { describe, expect, it, vi } from 'vitest'
import { issueReevaluationPhotoUpload } from './reevaluation-photo-upload'

const id = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const scope = { userId: id(1), cycleId: id(2), assetId: id(3) }
const now = new Date('2026-10-25T01:00:00Z')
const at = '2026-10-25T01:00:00.000000Z'
const origin = 'https://test-project.supabase.co'
function setup() {
  const asset = {
    id: scope.assetId,
    user_id: scope.userId,
    signup_generation: id(4),
    cycle_id: scope.cycleId,
    consent_acceptance_id: id(5),
    origin: 'reevaluation_cycle_v1',
    pose: 'front',
    bucket_id: 'body-checkin-photos',
    object_path: `${scope.userId}/${scope.assetId}.jpg`,
    mime_type: 'image/jpeg',
    size_bytes: 1200,
    status: 'pending_upload',
    created_at: at,
    retention_until: '2026-10-26T01:00:00.000000Z',
  }
  const prepared = {
    version: 1,
    cycle_revision: '2',
    asset,
    ticket: {
      id: id(6),
      asset_id: asset.id,
      user_id: asset.user_id,
      signup_generation: asset.signup_generation,
      cycle_id: asset.cycle_id,
      consent_acceptance_id: asset.consent_acceptance_id,
      prepared_at: at,
      provider_expires_at: null,
      registered_at: null,
    },
  }
  const expiry = '2026-10-25T03:00:15.000Z'
  const payload = {
    exp: Date.parse(expiry) / 1000,
    url: `${asset.bucket_id}/${asset.object_path}`,
    upsert: false,
  }
  const token = (claims = payload) =>
    [
      Buffer.from('{"alg":"HS256"}').toString('base64url'),
      Buffer.from(JSON.stringify(claims)).toString('base64url'),
      Buffer.from('synthetic-signature').toString('base64url'),
    ].join('.')
  const signed = (value = token()) =>
    `${origin}/storage/v1/object/upload/sign/${asset.bucket_id}/${asset.object_path}?token=${value}`
  const order: string[] = []
  const observed: string[] = []
  const deps = {
    storageOrigin: origin,
    now: () => now,
    nonce: () => id(6),
    prepare: vi.fn(async (_scope: unknown, _ticketId: string) => {
      order.push('prepare')
      return structuredClone(prepared)
    }),
    sign: vi.fn(async () => {
      order.push('sign')
      return { signedUrl: signed() }
    }),
    register: vi.fn(async (_p: unknown, expiresAt: string) => {
      order.push('register')
      observed.push(expiresAt)
      return {
        version: 1,
        ticket: {
          ...prepared.ticket,
          provider_expires_at: expiresAt.replace('.000Z', '.000000Z'),
          registered_at: at,
        },
      }
    }),
    current: vi.fn(async () => {
      order.push('current')
      return { version: 1, cycle_revision: '2', asset: structuredClone(asset) } as unknown
    }),
  }
  return { asset, prepared, deps, order, observed, expiry, payload, token, signed }
}

describe('recurring signed upload handoff', () => {
  it.each([
    '2026-10-25T03:02:01.000Z',
    '2030-10-25T03:00:00.000Z',
  ])('persists but never returns a provider capability beyond the 2h + 120s clock bound: %s', async (expiry) => {
    const f = setup()
    f.deps.sign.mockResolvedValue({
      signedUrl: f.signed(f.token({ ...f.payload, exp: Date.parse(expiry) / 1000 })),
    })
    const error = await issueReevaluationPhotoUpload(f.deps, scope).catch((e: Error) => e)
    expect(error).toMatchObject({ status: 503 })
    expect(String(error)).not.toContain('token=')
    expect(f.observed).toEqual([expiry])
    expect(f.deps.sign).toHaveBeenCalledOnce()
    expect(f.deps.current).not.toHaveBeenCalled()
  })
  it('permits exactly the bounded 120s skew without truncating the observed expiry', async () => {
    const f = setup()
    const expiry = '2026-10-25T03:02:00.000Z'
    f.deps.sign.mockResolvedValue({
      signedUrl: f.signed(f.token({ ...f.payload, exp: Date.parse(expiry) / 1000 })),
    })
    expect((await issueReevaluationPhotoUpload(f.deps, scope)).upload.expires_at).toBe(expiry)
    expect(f.observed).toEqual([expiry])
  })
  it('slow registration cannot widen the bound captured at the signing response', async () => {
    const f = setup()
    const expiry = '2026-10-25T03:03:00.000Z'
    let clock = now
    f.deps.now = () => clock
    f.deps.sign.mockResolvedValue({
      signedUrl: f.signed(f.token({ ...f.payload, exp: Date.parse(expiry) / 1000 })),
    })
    const register = f.deps.register.getMockImplementation()
    if (!register) throw new Error('Missing test register port')
    f.deps.register.mockImplementation(async (value, expiresAt) => {
      clock = new Date('2026-10-25T01:03:00Z')
      return register(value, expiresAt)
    })
    await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.observed).toEqual([expiry])
    expect(f.deps.current).not.toHaveBeenCalled()
  })
  it('records provider expiry before current authority and returning the URL; no guessed earlier TTL', async () => {
    const f = setup()
    const result = await issueReevaluationPhotoUpload(f.deps, scope)
    expect(f.order).toEqual(['prepare', 'sign', 'register', 'current'])
    expect(f.observed).toEqual([f.expiry])
    expect(result.upload).toEqual({
      signed_url: f.signed(),
      method: 'PUT',
      headers: { 'Content-Type': 'image/jpeg', 'x-upsert': 'false' },
      expires_at: f.expiry,
    })
    expect(f.deps.sign).toHaveBeenCalledOnce()
  })
  it.each([
    'reset',
    'softdelete',
    'expired',
    'discarded',
    'language changed',
  ])('retains observed expiry but returns no capability when %s closes authority during sign', async () => {
    const f = setup()
    f.deps.current.mockImplementation(async () => {
      f.order.push('current')
      throw new Error('synthetic closed authority')
    })
    await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.observed).toEqual([f.expiry])
    expect(f.order).toEqual(['prepare', 'sign', 'register', 'current'])
  })
  it('absent current or changed acceptance prevents returning the issued capability', async () => {
    for (const current of [
      null,
      {
        version: 1,
        cycle_revision: '2',
        asset: { ...setup().asset, consent_acceptance_id: id(90) },
      },
    ]) {
      const f = setup()
      f.deps.current.mockResolvedValue(current)
      await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
        status: 409,
      })
      expect(f.observed).toEqual([f.expiry])
    }
  })
  it('uncertain registration stops without another sign or a current lookup', async () => {
    const f = setup()
    f.deps.register.mockRejectedValue(new Error(`private token ${f.token()}`))
    const error = await issueReevaluationPhotoUpload(f.deps, scope).catch((e: Error) => e)
    expect(error).toMatchObject({ status: 503 })
    expect(String(error)).not.toContain(f.token())
    expect(f.order).toEqual(['prepare', 'sign'])
    expect(f.deps.sign).toHaveBeenCalledOnce()
    expect(f.deps.register).toHaveBeenCalledOnce()
    expect(f.deps.current).not.toHaveBeenCalled()
  })
  it.each([
    'host',
    'path',
    'upsert',
    'expiry',
    'token',
    'duplicate token',
    'userinfo',
    'fragment',
  ])('refuses malformed or unbound %s without recording/returning it', async (caseName) => {
    const f = setup()
    let url = f.signed()
    if (caseName === 'host') url = url.replace(origin, 'https://attacker.test')
    if (caseName === 'path') url = url.replace(f.asset.object_path, `${scope.userId}/${id(98)}.jpg`)
    if (caseName === 'upsert') url = f.signed(f.token({ ...f.payload, upsert: true }))
    if (caseName === 'expiry') url = f.signed(f.token({ ...f.payload, exp: 0 }))
    if (caseName === 'token') url = f.signed('malformed')
    if (caseName === 'duplicate token') url += '&token=another'
    if (caseName === 'userinfo') url = url.replace('https://', 'https://user:pass@')
    if (caseName === 'fragment') url += '#ignored'
    f.deps.sign.mockResolvedValue({ signedUrl: url })
    await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.deps.register).not.toHaveBeenCalled()
    expect(f.deps.current).not.toHaveBeenCalled()
  })
  it('registered receipt must confirm exact asset, acceptance and expiry', async () => {
    const f = setup()
    f.deps.register.mockResolvedValue({
      version: 1,
      ticket: {
        ...f.prepared.ticket,
        asset_id: id(99),
        provider_expires_at: f.expiry,
        registered_at: at,
      },
    })
    await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.deps.current).not.toHaveBeenCalled()
  })
  it('expired at delivery is still registered, then withheld', async () => {
    const f = setup()
    f.deps.now = () => new Date('2026-10-25T04:00:00Z')
    await expect(issueReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({ status: 409 })
    expect(f.observed).toEqual([f.expiry])
  })
  it('each successful fresh sign keeps its own nonce and expiry', async () => {
    const f = setup()
    let n = 5
    f.deps.nonce = () => id(++n)
    f.deps.prepare.mockImplementation(async (_s: unknown, ticketId: string) => ({
      ...structuredClone(f.prepared),
      ticket: { ...f.prepared.ticket, id: ticketId },
    }))
    f.deps.register.mockImplementation(async (value: unknown, expiry: string) => ({
      version: 1,
      ticket: {
        ...(value as typeof f.prepared).ticket,
        provider_expires_at: expiry.replace('.000Z', '.000000Z'),
        registered_at: at,
      },
    }))
    await issueReevaluationPhotoUpload(f.deps, scope)
    await issueReevaluationPhotoUpload(f.deps, scope)
    expect(f.deps.prepare.mock.calls.map((call) => call[1])).toEqual([id(6), id(7)])
    expect(f.deps.sign).toHaveBeenCalledTimes(2)
  })
})
