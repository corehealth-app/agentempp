import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto'
import { z } from 'zod'

const CAPABILITY_VERSION = 1
const CAPABILITY_TTL_SECONDS = 300
const NONCE_BYTES = 12
const AUTH_TAG_BYTES = 16
const KEY_INFO = 'bodyflow:mobile-content-cover-capability:key:v1'
const AAD = 'bodyflow:mobile-content-cover-capability:token:v1'

const payloadSchema = z
  .object({
    userId: z.string().uuid(),
    publicationId: z.string().uuid(),
    version: z.number().int().positive(),
    issuedAt: z.number().int().nonnegative(),
    expiresAt: z.number().int().positive(),
  })
  .strict()

export type ContentCoverCapabilityPayload = z.infer<typeof payloadSchema>

export interface ContentCoverCapabilityCodec {
  issue(input: { userId: string; publicationId: string; version: number }): {
    token: string
    expiresAt: string
  }
  open(token: string): ContentCoverCapabilityPayload
}

export interface ContentCoverCapabilityOptions {
  secret: string
  clock?: () => number
  nonce?: () => Uint8Array
}

export class ContentCoverCapabilityError extends Error {
  constructor() {
    super('Invalid content cover capability')
    this.name = 'ContentCoverCapabilityError'
  }
}

function deriveKey(secret: string): Buffer {
  if (!secret) throw new Error('Content cover capability secret is unavailable')
  return Buffer.from(
    hkdfSync('sha256', Buffer.from(secret), Buffer.alloc(0), Buffer.from(KEY_INFO), 32),
  )
}

function invalidCapability(): never {
  throw new ContentCoverCapabilityError()
}

export function createContentCoverCapabilityCodec(
  options: ContentCoverCapabilityOptions,
): ContentCoverCapabilityCodec {
  const key = deriveKey(options.secret)
  const clock = options.clock ?? Date.now
  const createNonce = options.nonce ?? (() => randomBytes(NONCE_BYTES))

  return {
    issue(input) {
      const issuedAt = Math.floor(clock() / 1000)
      const payload = payloadSchema.parse({
        ...input,
        issuedAt,
        expiresAt: issuedAt + CAPABILITY_TTL_SECONDS,
      })
      const nonce = Buffer.from(createNonce())
      if (nonce.byteLength !== NONCE_BYTES) throw new Error('Invalid capability nonce length')

      const cipher = createCipheriv('aes-256-gcm', key, nonce)
      cipher.setAAD(Buffer.from(AAD))
      const ciphertext = Buffer.concat([
        cipher.update(JSON.stringify(payload), 'utf8'),
        cipher.final(),
      ])
      const token = Buffer.concat([
        Buffer.from([CAPABILITY_VERSION]),
        nonce,
        ciphertext,
        cipher.getAuthTag(),
      ]).toString('base64url')

      return {
        token,
        expiresAt: new Date(payload.expiresAt * 1000).toISOString(),
      }
    },

    open(token) {
      try {
        if (!/^[A-Za-z0-9_-]+$/.test(token)) invalidCapability()
        const envelope = Buffer.from(token, 'base64url')
        if (envelope.toString('base64url') !== token) invalidCapability()
        if (envelope.byteLength <= 1 + NONCE_BYTES + AUTH_TAG_BYTES) invalidCapability()
        if (envelope[0] !== CAPABILITY_VERSION) invalidCapability()

        const nonceStart = 1
        const ciphertextStart = nonceStart + NONCE_BYTES
        const tagStart = envelope.byteLength - AUTH_TAG_BYTES
        const decipher = createDecipheriv(
          'aes-256-gcm',
          key,
          envelope.subarray(nonceStart, ciphertextStart),
        )
        decipher.setAAD(Buffer.from(AAD))
        decipher.setAuthTag(envelope.subarray(tagStart))
        const plaintext = Buffer.concat([
          decipher.update(envelope.subarray(ciphertextStart, tagStart)),
          decipher.final(),
        ])
        const payload = payloadSchema.parse(JSON.parse(plaintext.toString('utf8')))
        const now = Math.floor(clock() / 1000)
        const ttl = payload.expiresAt - payload.issuedAt
        if (
          ttl <= 0 ||
          ttl > CAPABILITY_TTL_SECONDS ||
          payload.issuedAt > now ||
          payload.expiresAt <= now
        ) {
          invalidCapability()
        }
        return payload
      } catch (error) {
        if (error instanceof ContentCoverCapabilityError) throw error
        return invalidCapability()
      }
    },
  }
}

export function createDefaultContentCoverCapabilityCodec(): ContentCoverCapabilityCodec {
  return createContentCoverCapabilityCodec({
    secret: process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
  })
}
