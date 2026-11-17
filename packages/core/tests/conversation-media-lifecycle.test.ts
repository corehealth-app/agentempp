import { describe, expect, it } from 'vitest'
import {
  privateMediaAssetReplyV2Schema,
  privateMediaProcessingClaimV2Schema,
  privateMediaUploadPreparedV2Schema,
  privateMediaUploadRegisteredV2Schema,
  privateMediaUploadStateV2Schema,
} from '../src/conversation-media-lifecycle'
import { createConversationMediaIdentityV2 } from '../src/conversation-media-namespace'

const owner = 'c3670000-0000-4000-8000-000000000001'
const asset = 'c3670000-0000-4000-8000-000000000002'
const nonce = 'c3670000-0000-4000-8000-000000000003'
const at = '2026-11-17T12:00:00.000Z'
const until = '2026-12-17T12:00:00.000Z'
const identity = createConversationMediaIdentityV2({
  userId: owner,
  assetId: asset,
  kind: 'audio_note',
  mimeType: 'audio/mp4',
  declaredSizeBytes: 8,
})
const wire = {
  identity,
  state: { status: 'pending_upload', created_at: at, retention_until: until },
}
const ticket = {
  id: nonce,
  asset_id: asset,
  user_id: owner,
  prepared_at: at,
  provider_expires_at: null,
  registered_at: null,
}
const prepared = { schema: 'conversation.upload-prepared.v2', asset: wire, ticket }
const row = {
  id: asset,
  user_id: owner,
  kind: 'audio_note',
  bucket_id: 'audio-notes',
  object_path: identity.object_path,
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
  retention_until: until,
  uploaded_at: null,
  processed_at: null,
  deleted_at: null,
  created_at: at,
  updated_at: at,
}
const reply = { schema: 'conversation.media-asset.v2', catalog_version: 2, asset: row }

describe('private media lifecycle contracts', () => {
  it('accepts the canonical raw catalog reply and prepared private snapshot', () => {
    expect(privateMediaAssetReplyV2Schema.parse(reply)).toEqual(reply)
    expect(privateMediaUploadPreparedV2Schema.parse(prepared)).toEqual(prepared)
    const state = { schema: 'conversation.upload-state.v2', asset: wire }
    expect(privateMediaUploadStateV2Schema.parse(state)).toEqual(state)
  })

  it.each([
    { id: 'not-a-uuid' },
    { asset_id: nonce },
    { user_id: nonce },
    { provider_expires_at: '2026-11-17T14:00:00.000Z', registered_at: null },
    { provider_expires_at: null, registered_at: at },
    {
      prepared_at: '2026-11-17T12:01:00.000Z',
      provider_expires_at: '2026-11-17T14:00:00.000Z',
      registered_at: at,
    },
    { secret_url: 'https://example.invalid' },
  ])('refuses a changed or incorrectly observed ticket: %j', (change) => {
    expect(
      privateMediaUploadPreparedV2Schema.safeParse({
        ...prepared,
        ticket: { ...ticket, ...change },
      }).success,
    ).toBe(false)
  })

  it('keeps actual expiry observation separate from current upload admission', () => {
    const observed = {
      schema: 'conversation.upload-registered.v2',
      ticket: { ...ticket, provider_expires_at: '2026-11-17T11:59:59.000Z', registered_at: at },
    }
    expect(privateMediaUploadRegisteredV2Schema.parse(observed)).toEqual(observed)
    expect(privateMediaUploadRegisteredV2Schema.safeParse({ ...observed, ticket }).success).toBe(
      false,
    )
    expect(
      privateMediaUploadPreparedV2Schema.safeParse({ ...prepared, ticket: observed.ticket })
        .success,
    ).toBe(false)
  })

  it.each([
    { schema: 'conversation.upload-prepared.v1' },
    { asset: { ...wire, identity: { ...identity, catalog_version: 1 } } },
    { asset: { ...wire, identity: { ...identity, object_path: `${owner}/${asset}.m4a` } } },
    { asset: { ...wire, state: { ...wire.state, status: 'deleted' } } },
    { asset: { ...wire, state: { ...wire.state, retention_until: '2026-12-18T12:00:00.000Z' } } },
    { asset: { ...wire, status: 'pending_upload' } },
  ])('refuses a legacy or changed source snapshot: %j', (change) => {
    expect(privateMediaUploadPreparedV2Schema.safeParse({ ...prepared, ...change }).success).toBe(
      false,
    )
  })

  it.each([
    { object_path: `${owner}/${asset}.m4a` },
    { user_id: nonce },
    { kind: 'body_checkin_photo' },
    { actual_size_bytes: 9 },
    { declared_size_bytes: 0 },
    { source_request_hash: 'not-a-hash' },
    { status: 'uploaded' },
    { status: 'processing', processing_request_id: 'c'.repeat(64) },
    { status: 'processed', processed_at: at },
    { status: 'deleted' },
    { status: 'failed', failure_stage: null, failure_code: 'provider_error' },
    { processing_result: { text: 'not yet processed' } },
    { updated_at: '2026-11-17T11:59:59.000Z' },
    { signup_origin: true },
    { reevaluation_origin_version: 1 },
  ])('refuses inconsistent raw private state: %j', (change) => {
    expect(
      privateMediaAssetReplyV2Schema.safeParse({ ...reply, asset: { ...row, ...change } }).success,
    ).toBe(false)
  })

  it('requires a leased current private snapshot for processing', () => {
    const claim = {
      schema: 'conversation.media-processing-claim.v2',
      action: 'claimed',
      asset: {
        ...wire,
        state: { ...wire.state, status: 'processing' },
        context_text: null,
        processing_request_id: 'c'.repeat(64),
      },
      claim: { token: nonce, lease_until: '2026-11-17T12:05:00.000Z' },
    }
    expect(privateMediaProcessingClaimV2Schema.parse(claim)).toEqual(claim)
    expect(
      privateMediaProcessingClaimV2Schema.safeParse({
        ...claim,
        asset: { ...claim.asset, processing_request_id: '' },
      }).success,
    ).toBe(false)
    expect(
      privateMediaProcessingClaimV2Schema.safeParse({
        ...claim,
        claim: { token: 'wrong', lease_until: at },
      }).success,
    ).toBe(false)
    expect(
      privateMediaProcessingClaimV2Schema.safeParse({
        ...claim,
        asset: { ...claim.asset, state: wire.state },
      }).success,
    ).toBe(false)
  })

  it('distinguishes a busy lease from a terminal unavailable source', () => {
    const busy = {
      schema: 'conversation.media-processing-claim.v2',
      action: 'busy',
      retry_at: '2026-11-17T12:05:00.000Z',
    }
    const terminal = { schema: 'conversation.media-processing-claim.v2', action: 'unavailable' }
    expect(privateMediaProcessingClaimV2Schema.parse(busy)).toEqual(busy)
    expect(privateMediaProcessingClaimV2Schema.parse(terminal)).toEqual(terminal)
    expect(
      privateMediaProcessingClaimV2Schema.safeParse({ ...terminal, asset: wire }).success,
    ).toBe(false)
    expect(privateMediaProcessingClaimV2Schema.safeParse({ ...busy, retry_at: null }).success).toBe(
      false,
    )
  })
})
