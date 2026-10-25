import snapshotFixture from './reevaluation-photo-snapshot.json'

export { snapshotFixture }

const photo = snapshotFixture.snapshot.photos[0].photo
export const processingScope = {
  userId: photo.user_id,
  cycleId: photo.cycle_id,
  assetId: photo.asset_id,
  requestId: 'b3b01000-0000-4000-8000-000000000901',
}
function at(seconds: number) {
  return new Date(Date.parse(snapshotFixture.snapshot.observed_at) + seconds * 1000)
    .toISOString()
    .replace(/([0-9]{3})Z$/, '$1000Z')
}
export function processingWire(status = 'claimed') {
  return {
    version: 1,
    cycle_revision: snapshotFixture.snapshot.cycle_revision,
    source_revision: '2',
    asset: {
      id: photo.asset_id,
      user_id: photo.user_id,
      cycle_id: photo.cycle_id,
      signup_generation: photo.signup_generation,
      consent_acceptance_id: photo.consent_acceptance_id,
      origin: 'reevaluation_cycle_v1',
      pose: 'front',
      bucket_id: 'body-checkin-photos',
      object_path: `${photo.user_id}/${photo.asset_id}.jpg`,
      mime_type: 'image/jpeg',
      size_bytes: 1200,
      status: status === 'succeeded' ? 'processed' : 'processing',
      created_at: photo.created_at,
      retention_until: at(3600),
    },
    attempt: {
      id: processingScope.requestId,
      asset_id: photo.asset_id,
      user_id: photo.user_id,
      signup_generation: photo.signup_generation,
      cycle_id: photo.cycle_id,
      consent_acceptance_id: photo.consent_acceptance_id,
      pose: 'front',
      source_revision: '2',
      processing_request_id: 'a'.repeat(64),
      claimed_at: at(0),
      lease_until: at(300),
      provider_started_at: status === 'claimed' ? null : at(1),
      provider_authorized_until: status === 'claimed' ? null : at(300),
      status,
      finished_at: status === 'succeeded' || status === 'failed' ? at(2) : null,
      result:
        status === 'succeeded' ? { type: 'body', view: 'front', bf_percent_estimate: 22 } : null,
      failure_code: status === 'failed' ? 'invalid_analysis' : null,
    },
  }
}
export function jpegBytes() {
  const bytes = new Uint8Array(1200)
  bytes.set([255, 216, 255])
  return bytes
}
