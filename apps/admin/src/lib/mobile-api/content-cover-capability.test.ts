import { createCipheriv, hkdfSync } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { createContentCoverCapabilityCodec } from './content-cover-capability'

const SECRET = 'synthetic-service-role-secret-that-is-not-a-provider-token'
const USER_ID = '00000000-0000-0000-0000-000000000501'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000502'
const NOW_SECONDS = 1_784_635_200
const KEY_INFO = 'bodyflow:mobile-content-cover-capability:key:v1'
const AAD = 'bodyflow:mobile-content-cover-capability:token:v1'

function forgeToken(payload: Record<string, unknown>): string {
  const nonce = Buffer.alloc(12, 9)
  const key = Buffer.from(
    hkdfSync('sha256', Buffer.from(SECRET), Buffer.alloc(0), Buffer.from(KEY_INFO), 32),
  )
  const cipher = createCipheriv('aes-256-gcm', key, nonce)
  cipher.setAAD(Buffer.from(AAD))
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(payload), 'utf8'), cipher.final()])
  return Buffer.concat([Buffer.from([1]), nonce, ciphertext, cipher.getAuthTag()]).toString(
    'base64url',
  )
}

describe('content cover capabilities', () => {
  it('issues an opaque authenticated token that expires in exactly 300 seconds', () => {
    const codec = createContentCoverCapabilityCodec({
      secret: SECRET,
      clock: () => NOW_SECONDS * 1000,
      nonce: () => new Uint8Array(12).fill(7),
    })

    const capability = codec.issue({ userId: USER_ID, publicationId: PUBLICATION_ID, version: 4 })

    expect(capability.expiresAt).toBe('2026-07-21T12:05:00.000Z')
    expect(codec.open(capability.token)).toEqual({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      version: 4,
      issuedAt: NOW_SECONDS,
      expiresAt: NOW_SECONDS + 300,
    })
    expect(capability.token).toMatch(/^[A-Za-z0-9_-]+$/)
    const encodedBytes = Buffer.from(capability.token, 'base64url').toString('utf8')
    for (const privateValue of [
      USER_ID,
      PUBLICATION_ID,
      'content-covers',
      'content/private-cover.webp',
      SECRET,
    ]) {
      expect(capability.token).not.toContain(privateValue)
      expect(encodedBytes).not.toContain(privateValue)
    }
  })

  it('rejects tampered, expired, malformed, and overlong capabilities identically', () => {
    let now = NOW_SECONDS * 1000
    const codec = createContentCoverCapabilityCodec({
      secret: SECRET,
      clock: () => now,
      nonce: () => new Uint8Array(12).fill(3),
    })
    const valid = codec.issue({ userId: USER_ID, publicationId: PUBLICATION_ID, version: 4 })
    const tampered = `${valid.token.slice(0, -1)}${valid.token.endsWith('A') ? 'B' : 'A'}`
    const overlong = forgeToken({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      version: 4,
      issuedAt: NOW_SECONDS,
      expiresAt: NOW_SECONDS + 301,
    })
    const invalidPayload = forgeToken({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      version: 4,
      issuedAt: NOW_SECONDS,
      expiresAt: NOW_SECONDS + 300,
      objectPath: 'content/private-cover.webp',
    })

    for (const token of [tampered, overlong, invalidPayload, 'not-a-capability']) {
      expect(() => codec.open(token)).toThrowError('Invalid content cover capability')
    }

    now = (NOW_SECONDS + 300) * 1000
    expect(() => codec.open(valid.token)).toThrowError('Invalid content cover capability')
  })
})
