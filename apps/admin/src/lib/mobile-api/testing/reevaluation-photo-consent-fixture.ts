import { createHash } from 'node:crypto'
import type { MobileAuthContext } from '../auth'

export const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const owner = uid(5600),
  subject = uid(5699),
  body = 'Texto exato.\n\nFotos privadas por 24 horas.  '
export const consentAuth = {
  userId: owner,
  authUserId: subject,
  identity: { id: subject },
  patient: { id: owner, authUserId: subject, status: 'active', locale: 'pt-BR' },
} as MobileAuthContext
export function consentWire(accepted = false) {
  const document = {
    id: uid(5602),
    document_key: 'body_photo_reevaluation_consent',
    version: 'local.1',
    locale: 'pt-BR',
    body,
    body_hash: createHash('sha256').update(body).digest('hex'),
    required_from: '2026-10-01T00:00:00.000000Z',
    idle_timeout_seconds: 86400,
  }
  return {
    version: 1,
    cycle_revision: accepted ? '9007199254740994' : '9007199254740993',
    availability: accepted ? 'available' : 'unavailable',
    unavailable_reason: accepted ? null : 'consent_required',
    document,
    acceptance: accepted
      ? {
          acceptance_id: uid(5603),
          document_id: document.id,
          document_key: document.document_key,
          version: document.version,
          locale: document.locale,
          body_hash: document.body_hash,
          accepted_at: '2026-10-27T12:00:00.000000Z',
          idle_expires_at: '2026-10-28T12:00:00.000000Z',
        }
      : null,
  }
}
export function consentInput() {
  const { id, document_key, version, locale, body_hash } = consentWire().document
  return {
    expectedRevision: '9007199254740993',
    document: { id, documentKey: document_key, version, locale, bodyHash: body_hash },
  }
}
