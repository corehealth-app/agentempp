import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  createReevaluationPhotoConsentService,
  parseReevaluationPhotoConsentState,
} from './reevaluation-photo-consent'

import {
  consentAuth,
  consentInput,
  consentWire,
  uid,
} from './testing/reevaluation-photo-consent-fixture'

const owner = uid(5600),
  cycle = uid(5601),
  body = consentWire().document.body

describe('recurring consent — exact current text, no old-response cache', () => {
  it('preserves literal body and bigint revision while binding the response to requested cycle', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: consentWire(), error: null })
    const service = createReevaluationPhotoConsentService({ rpc } as unknown as ServiceClient)
    const value = await service.read(consentAuth, cycle)
    expect(value.document?.body).toBe(body)
    expect(value.cycle_revision).toBe('9007199254740993')
    expect(value.cycle_id).toBe(cycle)
    expect(rpc).toHaveBeenCalledWith('get_mobile_reevaluation_photo_consent', {
      p_user_id: owner,
      p_cycle_id: cycle,
    })
    for (const key of ['user_id', 'signup_generation', 'source_hash', 'object_path'])
      expect(JSON.stringify(value)).not.toContain(key)
  })
  it('always calls the authority for ACCEPT replay and forwards the shown identity unchanged', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: consentWire(true), error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { code: '40001', message: 'private stale consent' },
      })
    const service = createReevaluationPhotoConsentService({ rpc } as unknown as ServiceClient),
      input = consentInput()
    expect(
      (await service.accept(consentAuth, cycle, uid(5604), input)).acceptance?.acceptance_id,
    ).toBe(uid(5603))
    await expect(service.accept(consentAuth, cycle, uid(5604), input)).rejects.toMatchObject({
      status: 409,
      code: 'mobile_reevaluation_photo_consent_changed',
    })
    expect(rpc).toHaveBeenCalledTimes(2)
    expect(rpc.mock.calls[0]).toEqual([
      'accept_mobile_reevaluation_photo_consent',
      {
        p_user_id: owner,
        p_cycle_id: cycle,
        p_expected_revision: input.expectedRevision,
        p_document_id: input.document.id,
        p_document_key: input.document.documentKey,
        p_version: input.document.version,
        p_locale: input.document.locale,
        p_body_hash: input.document.bodyHash,
        p_idempotency_key: uid(5604),
      },
    ])
  })
  it('rejects inconsistent state, forged literal body/hash and an unapproved retention duration', () => {
    const good = consentWire(true)
    for (const value of [
      { ...good, document: { ...good.document, body: body.trim() } },
      { ...good, acceptance: { ...good.acceptance, document_id: uid(5690) } },
      { ...good, acceptance: null },
      { ...good, document: { ...good.document, idle_timeout_seconds: 60 } },
      { ...good, cycle_revision: 9007199254740992 },
    ])
      expect(() => parseReevaluationPhotoConsentState(value, cycle)).toThrow()
  })
  it('returns policy-unavailable without inventing a document or acceptance', () => {
    expect(
      parseReevaluationPhotoConsentState(
        {
          version: 1,
          cycle_revision: '1',
          availability: 'unavailable',
          unavailable_reason: 'policy_unavailable',
          document: null,
          acceptance: null,
        },
        cycle,
      ),
    ).toMatchObject({ cycle_id: cycle, document: null, acceptance: null })
  })
  it('invalid public claims fail before the RPC; raw backend errors never escape', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: null, error: { code: 'XX000', message: 'secret provider URL' } })
    const service = createReevaluationPhotoConsentService({ rpc } as unknown as ServiceClient)
    await expect(
      service.accept(consentAuth, cycle, uid(5604), { ...consentInput(), userId: owner }),
    ).rejects.toMatchObject({ status: 422 })
    await expect(service.read({ ...consentAuth, userId: uid(5690) }, cycle)).rejects.toMatchObject({
      status: 403,
    })
    expect(rpc).not.toHaveBeenCalled()
    await expect(service.read(consentAuth, cycle)).rejects.toMatchObject({
      status: 503,
      message: 'Reassessment photo consent is unavailable',
    })
  })
})
