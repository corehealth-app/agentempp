import { describe, expect, it } from 'vitest'
import { resolveReevaluationPhotoCandidate } from './reevaluation-photo-candidate'

const OWNER = 'a1000000-0000-4000-8000-000000000001'
const GENERATION = 'a1000000-0000-4000-8000-000000000002'
const CYCLE = 'a1000000-0000-4000-8000-000000000003'
const DOCUMENT = 'a1000000-0000-4000-8000-000000000004'
const ACCEPTANCE = 'a1000000-0000-4000-8000-000000000005'
const OTHER = 'a1000000-0000-4000-8000-000000000099'
const HASH = 'a'.repeat(64)
const ASSETS = [
  'a1000000-0000-4000-8000-000000000011',
  'a1000000-0000-4000-8000-000000000012',
  'a1000000-0000-4000-8000-000000000013',
]
function expected() {
  return {
    userId: OWNER,
    signupGeneration: GENERATION,
    cycleId: CYCLE,
    cycleRevision: '9007199254740993',
    currentConsent: {
      documentId: DOCUMENT,
      documentKey: 'body_photo_reevaluation_consent' as const,
      version: 'v1',
      locale: 'pt-BR' as const,
      bodyHash: HASH,
    },
  }
}
function snapshot() {
  return {
    version: 1,
    user_id: OWNER,
    signup_generation: GENERATION,
    cycle_id: CYCLE,
    cycle_revision: '9007199254740993',
    opened_at: '2026-10-15T03:00:00.000000Z',
    observed_at: '2026-10-15T04:00:00.000000Z',
    consent: {
      acceptance_id: ACCEPTANCE,
      document_id: DOCUMENT,
      document_key: 'body_photo_reevaluation_consent',
      version: 'v1',
      locale: 'pt-BR',
      body_hash: HASH,
      accepted_at: '2026-10-15T03:01:00.000000Z',
    },
    photos: (['front', 'side', 'back'] as const).map((pose, index) => ({
      pose,
      photo: {
        asset_id: ASSETS[index],
        user_id: OWNER,
        signup_generation: GENERATION,
        cycle_id: CYCLE,
        consent_acceptance_id: ACCEPTANCE,
        origin: 'reevaluation_cycle_v1',
        status: 'processed',
        created_at: '2026-10-15T03:02:00.000000Z',
        uploaded_at: '2026-10-15T03:03:00.000000Z',
        processed_at: '2026-10-15T03:04:00.000000Z',
        analysis: { type: 'body', view: pose as string, bf_percent_estimate: 20 + index },
      },
    })),
  }
}

describe('recurring body photo candidate from a server snapshot', () => {
  it('requires the complete triad and uses the existing arithmetic and rounding', () => {
    const result = resolveReevaluationPhotoCandidate(expected(), snapshot())
    expect(result).toMatchObject({
      status: 'ready',
      source_ids: { front: ASSETS[0], side: ASSETS[1], back: ASSETS[2] },
      estimate: {
        is_estimate: true,
        by_sex: {
          masculino: { usable: true, body_fat_percent: 21 },
          feminino: { usable: true, body_fat_percent: 21 },
        },
      },
      photo_fingerprint: expect.stringMatching(/^[0-9a-f]{64}$/),
    })
    const input = snapshot()
    for (const slot of input.photos) slot.photo.analysis.bf_percent_estimate = 20.015
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toMatchObject({
      estimate: { by_sex: { masculino: { body_fat_percent: 20.02 } } },
    })
  })

  it('orders slots canonically rather than treating array order as a different candidate', () => {
    const input = snapshot()
    input.photos.reverse()
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual(
      resolveReevaluationPhotoCandidate(expected(), snapshot()),
    )
  })

  it.each([
    'user_id',
    'signup_generation',
    'cycle_id',
    'cycle_revision',
  ] as const)('rejects a stale snapshot %s before producing a candidate', (key) => {
    const input = snapshot()
    input[key] = key === 'cycle_revision' ? '9007199254740994' : OTHER
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual({
      status: 'unavailable',
      reason: 'stale_cycle',
    })
  })

  it('requires current consent even if three readings are present', () => {
    expect(
      resolveReevaluationPhotoCandidate({ ...expected(), currentConsent: null }, snapshot()),
    ).toEqual({ status: 'unavailable', reason: 'consent_required' })
    expect(resolveReevaluationPhotoCandidate(expected(), { ...snapshot(), consent: null })).toEqual(
      { status: 'unavailable', reason: 'consent_required' },
    )
  })

  it.each([
    { document_id: OTHER },
    { document_key: 'body_photo_estimate_consent' },
    { version: 'old-version' },
    { locale: 'en-US' },
    { body_hash: 'b'.repeat(64) },
  ])('does not reuse an acceptance with a different full legal identity %#', (change) => {
    const input = snapshot()
    expect(
      resolveReevaluationPhotoCandidate(expected(), {
        ...input,
        consent: { ...input.consent, ...change },
      }),
    ).toEqual({ status: 'unavailable', reason: 'consent_required' })
  })

  it('rejects missing photos without substituting an old or partial average', () => {
    const input = snapshot()
    expect(
      resolveReevaluationPhotoCandidate(expected(), {
        ...input,
        photos: input.photos.map((slot, i) => (i === 1 ? { ...slot, photo: null } : slot)),
      }),
    ).toEqual({ status: 'unavailable', reason: 'photos_incomplete' })
  })

  it.each([
    'pending_upload',
    'uploaded',
    'processing',
    'deleted',
  ])('does not average a photo in status %s', (status) => {
    const input = snapshot()
    input.photos[0].photo.status = status
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual({
      status: 'unavailable',
      reason: 'photos_incomplete',
    })
  })

  it('treats failed or missing analysis as unreadable rather than a numeric fallback', () => {
    const input = snapshot()
    input.photos[1].photo.status = 'failed'
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual({
      status: 'unavailable',
      reason: 'photo_unreadable',
    })
    const missing = snapshot()
    expect(
      resolveReevaluationPhotoCandidate(expected(), {
        ...missing,
        photos: missing.photos.map((slot, i) =>
          i === 1 ? { ...slot, photo: { ...slot.photo, analysis: null } } : slot,
        ),
      }),
    ).toEqual({ status: 'unavailable', reason: 'photo_unreadable' })
  })

  it.each([
    'unknown',
    'side',
    'back',
  ])('does not replace the detected pose %s with the requested front slot', (view) => {
    const input = snapshot()
    input.photos[0].photo.analysis.view = view
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual({
      status: 'unavailable',
      reason: 'pose_mismatch',
    })
  })

  it.each([
    2.99, 60.01, -1, 100,
  ])('rejects out of range reading %s without changing the clinical range', (value) => {
    const input = snapshot()
    input.photos[1].photo.analysis.bf_percent_estimate = value
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual({
      status: 'unavailable',
      reason: 'reading_out_of_range',
    })
  })

  it.each([
    { user_id: OTHER },
    { signup_generation: OTHER },
    { cycle_id: OTHER },
    { origin: 'signup' },
    { created_at: '2026-10-14T03:02:00.000000Z' },
    { uploaded_at: '2026-10-15T03:01:00.000000Z' },
    { processed_at: '2026-10-15T03:02:00.000000Z' },
    { processed_at: '2026-10-16T03:04:00.000000Z' },
    { created_at: '2026-02-30T03:02:00.000000Z' },
  ])('rejects corrupt photo authority or chronology %#', (change) => {
    const input = snapshot()
    input.photos[0].photo = { ...input.photos[0].photo, ...change }
    expect(() => resolveReevaluationPhotoCandidate(expected(), input)).toThrow(
      expect.objectContaining({ code: 'mobile_reevaluation_photo_invalid_snapshot', status: 500 }),
    )
  })

  it('rejects duplicate slots and duplicate assets rather than selecting one arbitrarily', () => {
    const duplicateSlot = snapshot()
    duplicateSlot.photos[1].pose = 'front'
    expect(() => resolveReevaluationPhotoCandidate(expected(), duplicateSlot)).toThrow()
    const duplicateAsset = snapshot()
    duplicateAsset.photos[1].photo.asset_id = ASSETS[0]
    expect(() => resolveReevaluationPhotoCandidate(expected(), duplicateAsset)).toThrow()
    expect(() =>
      resolveReevaluationPhotoCandidate(expected(), { ...snapshot(), photos: [] }),
    ).toThrow()
  })

  it.each([
    { cycle_revision: 9007199254740992 },
    { cycle_revision: '01' },
    { observed_at: '2026-10-14T03:00:00.000000Z' },
    { observed_at: '2026-10-15T04:00:00.000Z' },
    { consent: { ...snapshot().consent, accepted_at: '2026-10-14T03:01:00.000000Z' } },
    { consent: { ...snapshot().consent, accepted_at: '2026-10-16T03:01:00.000000Z' } },
    { profile: { body_fat_percent: 25 } },
  ])('rejects malformed server snapshots %#', (change) => {
    expect(() =>
      resolveReevaluationPhotoCandidate(expected(), { ...snapshot(), ...change }),
    ).toThrow()
  })

  it('rejects nonfinite values, unsupported provider views and missing timestamps', () => {
    for (const change of [
      { analysis: { type: 'body', view: 'front', bf_percent_estimate: Number.NaN } },
      { analysis: { type: 'body', view: 'selfie', bf_percent_estimate: 20 } },
      { uploaded_at: null },
      { processed_at: null },
    ]) {
      const input = snapshot()
      expect(() =>
        resolveReevaluationPhotoCandidate(expected(), {
          ...input,
          photos: input.photos.map((slot, i) =>
            i === 0 ? { ...slot, photo: { ...slot.photo, ...change } } : slot,
          ),
        }),
      ).toThrow()
    }
  })

  it('keeps the fingerprint stable on reread and strips free provider fields', () => {
    const input = snapshot()
    const changed = {
      ...input,
      observed_at: '2026-10-15T05:00:00.000000Z',
      photos: input.photos.map((slot) => ({
        ...slot,
        photo: {
          ...slot.photo,
          analysis: {
            ...slot.photo.analysis,
            raw_response: 'private-provider-fixture',
            composition_notes: 'sensitive-fixture',
            private_url: 'private-fixture',
          },
        },
      })),
    }
    const result = resolveReevaluationPhotoCandidate(expected(), changed)
    expect(result).toEqual(resolveReevaluationPhotoCandidate(expected(), snapshot()))
    expect(JSON.stringify(result)).not.toContain('private')
    expect(JSON.stringify(result)).not.toContain('sensitive')
  })

  it('changes the fingerprint for a new source, reading, consent identity or acceptance', () => {
    const original = resolveReevaluationPhotoCandidate(expected(), snapshot())
    expect(original.status).toBe('ready')
    const source = snapshot()
    source.photos[0].photo.asset_id = OTHER
    const reading = snapshot()
    reading.photos[0].photo.analysis.bf_percent_estimate = 23
    const acceptance = snapshot()
    acceptance.consent.accepted_at = '2026-10-15T03:01:00.000001Z'
    for (const changed of [source, reading, acceptance]) {
      const result = resolveReevaluationPhotoCandidate(expected(), changed)
      expect(result.status).toBe('ready')
      if (result.status === 'ready' && original.status === 'ready')
        expect(result.photo_fingerprint).not.toBe(original.photo_fingerprint)
    }
    const context = expected()
    context.currentConsent.bodyHash = 'b'.repeat(64)
    const changedDoc = snapshot()
    changedDoc.consent.body_hash = context.currentConsent.bodyHash
    const result = resolveReevaluationPhotoCandidate(context, changedDoc)
    expect(result.status).toBe('ready')
    if (result.status === 'ready' && original.status === 'ready')
      expect(result.photo_fingerprint).not.toBe(original.photo_fingerprint)
  })

  it('rejects an asset created in this cycle before the current acceptance', () => {
    const input = snapshot()
    input.photos[0].photo.created_at = '2026-10-15T03:00:30.000000Z'
    expect(() => resolveReevaluationPhotoCandidate(expected(), input)).toThrow(
      expect.objectContaining({ code: 'mobile_reevaluation_photo_invalid_snapshot' }),
    )
  })

  it('normalizes UUID spelling without changing the evidence identity', () => {
    const input = snapshot()
    input.user_id = OWNER.toUpperCase()
    for (const slot of input.photos) {
      slot.photo.user_id = OWNER.toUpperCase()
      slot.photo.asset_id = slot.photo.asset_id.toUpperCase()
    }
    expect(resolveReevaluationPhotoCandidate(expected(), input)).toEqual(
      resolveReevaluationPhotoCandidate(expected(), snapshot()),
    )
    input.photos[1].photo.asset_id = input.photos[0].photo.asset_id.toLowerCase()
    expect(() => resolveReevaluationPhotoCandidate(expected(), input)).toThrow()
  })

  it('requires every asset to be bound to the same current cycle acceptance', () => {
    const input = snapshot()
    input.photos[0].photo.consent_acceptance_id = OTHER
    expect(() => resolveReevaluationPhotoCandidate(expected(), input)).toThrow(
      expect.objectContaining({ code: 'mobile_reevaluation_photo_invalid_snapshot' }),
    )
  })

  it('includes the bound acceptance identity in the photo fingerprint', () => {
    const input = snapshot()
    input.consent.acceptance_id = OTHER
    for (const slot of input.photos) slot.photo.consent_acceptance_id = OTHER
    const result = resolveReevaluationPhotoCandidate(expected(), input)
    const original = resolveReevaluationPhotoCandidate(expected(), snapshot())
    expect(result.status).toBe('ready')
    if (result.status === 'ready' && original.status === 'ready')
      expect(result.photo_fingerprint).not.toBe(original.photo_fingerprint)
  })
})
