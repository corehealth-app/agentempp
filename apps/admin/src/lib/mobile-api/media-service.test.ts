import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import {
  completeMediaUpload,
  createMediaAsset,
  deleteMediaAsset,
  getMediaAsset,
  type MediaAssetRecord,
  type MediaServiceDependencies,
  requestMediaProcessing,
} from './media-service'

const USER_ID = '00000000-0000-0000-0000-000000000101'
const ASSET_ID = '00000000-0000-0000-0000-000000000201'

function asset(overrides: Partial<MediaAssetRecord> = {}): MediaAssetRecord {
  return {
    id: ASSET_ID,
    user_id: USER_ID,
    kind: 'body_checkin_photo',
    bucket_id: 'body-checkin-photos',
    object_path: `${USER_ID}/${ASSET_ID}.jpg`,
    mime_type: 'image/jpeg',
    declared_size_bytes: 1200,
    actual_size_bytes: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: '2028-07-20T12:00:00.000Z',
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: '2026-07-20T12:00:00.000Z',
    updated_at: '2026-07-20T12:00:00.000Z',
    ...overrides,
  }
}

function makeDeps(existing: MediaAssetRecord | null = null): MediaServiceDependencies & {
  repository: MediaServiceDependencies['repository']
  storage: MediaServiceDependencies['storage']
  events: MediaServiceDependencies['events']
} {
  return {
    repository: {
      findByRequestHash: vi.fn().mockResolvedValue(existing),
      create: vi.fn().mockResolvedValue(asset()),
      findOwned: vi.fn().mockResolvedValue(existing ?? asset()),
      markUploaded: vi.fn().mockImplementation(async (_userId, _assetId, details) =>
        asset({
          status: 'uploaded',
          actual_size_bytes: details.actualSizeBytes,
          uploaded_at: details.uploadedAt,
        }),
      ),
      markUploadFailed: vi.fn().mockResolvedValue(undefined),
      markDeleted: vi
        .fn()
        .mockImplementation(async () =>
          asset({ status: 'deleted', deleted_at: '2026-07-20T12:10:00.000Z' }),
        ),
    },
    storage: {
      createSignedUpload: vi.fn().mockResolvedValue({
        signedUrl: 'https://storage.test/upload/token',
      }),
      getObjectInfo: vi.fn().mockResolvedValue({
        size: 1200,
        contentType: 'image/jpeg',
        etag: 'etag-1',
      }),
      createSignedDownload: vi.fn().mockResolvedValue('https://storage.test/download/token'),
      remove: vi.fn().mockResolvedValue(undefined),
    },
    events: {
      sendProcessingRequested: vi.fn().mockResolvedValue(undefined),
    },
  }
}

describe('mobile media service', () => {
  it('creates an immutable body-checkin path with private retention and a temporary upload', async () => {
    const deps = makeDeps()

    const result = await createMediaAsset(
      deps,
      USER_ID,
      {
        kind: 'body_checkin_photo',
        mime_type: 'image/jpeg',
        size_bytes: 1200,
      },
      'mobile-media-request-0001',
      new Date('2026-07-20T12:00:00.000Z'),
      ASSET_ID,
    )

    expect(deps.repository.create).toHaveBeenCalledWith(
      expect.objectContaining({
        id: ASSET_ID,
        userId: USER_ID,
        bucketId: 'body-checkin-photos',
        objectPath: `${USER_ID}/${ASSET_ID}.jpg`,
        retentionUntil: '2028-07-19T12:00:00.000Z',
        sourceRequestHash: expect.stringMatching(/^[a-f0-9]{64}$/),
      }),
    )
    expect(deps.storage.createSignedUpload).toHaveBeenCalledWith(
      'body-checkin-photos',
      `${USER_ID}/${ASSET_ID}.jpg`,
    )
    expect(result.upload?.expires_at).toBe('2026-07-20T14:00:00.000Z')
    expect(result.upload).toMatchObject({
      method: 'PUT',
      headers: {
        'Content-Type': 'image/jpeg',
        'x-upsert': 'false',
      },
    })
    expect(result.upload).not.toHaveProperty('token')
  })

  it('stores a plan document in its own bucket, as PDF, with no automatic retention date', async () => {
    const deps = makeDeps()

    await createMediaAsset(
      deps,
      USER_ID,
      { kind: 'plan_document', mime_type: 'application/pdf', size_bytes: 20 * 1024 * 1024 },
      'mobile-media-request-0010',
      new Date('2026-07-20T12:00:00.000Z'),
      ASSET_ID,
    )

    expect(deps.repository.create).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: 'plan_document',
        bucketId: 'plan-documents',
        objectPath: `${USER_ID}/${ASSET_ID}.pdf`,
        mimeType: 'application/pdf',
        retentionUntil: null,
      }),
    )
  })

  it('a plan document is read only through the import, never by a direct request', async () => {
    const deps = makeDeps(asset({ kind: 'plan_document', status: 'uploaded' }))

    await expect(
      requestMediaProcessing(deps, USER_ID, ASSET_ID, 'mobile-media-request-0011'),
    ).rejects.toMatchObject({ status: 422, code: 'media_kind_not_supported' })
    expect(deps.events.sendProcessingRequested).not.toHaveBeenCalled()
  })

  it('a document whose draft is open is not deleted; without a draft it is', async () => {
    const document = asset({ kind: 'plan_document', status: 'uploaded' })
    const inUse = {
      ...makeDeps(document),
      planDrafts: { hasOpenDraftOfMedia: vi.fn().mockResolvedValue(true) },
    }
    await expect(deleteMediaAsset(inUse, USER_ID, ASSET_ID)).rejects.toMatchObject({
      status: 409,
      code: 'media_in_use_by_plan_draft',
    })
    expect(inUse.planDrafts.hasOpenDraftOfMedia).toHaveBeenCalledWith(USER_ID, ASSET_ID)
    expect(inUse.storage.remove).not.toHaveBeenCalled()
    expect(inUse.repository.markDeleted).not.toHaveBeenCalled()

    const free = {
      ...makeDeps(document),
      planDrafts: { hasOpenDraftOfMedia: vi.fn().mockResolvedValue(false) },
    }
    await expect(deleteMediaAsset(free, USER_ID, ASSET_ID)).resolves.toMatchObject({
      status: 'deleted',
    })
    expect(free.storage.remove).toHaveBeenCalledOnce()

    // Other kinds never ask about drafts.
    const photo = {
      ...makeDeps(asset({ kind: 'meal_photo', status: 'uploaded' })),
      planDrafts: { hasOpenDraftOfMedia: vi.fn().mockResolvedValue(true) },
    }
    await deleteMediaAsset(photo, USER_ID, ASSET_ID)
    expect(photo.planDrafts.hasOpenDraftOfMedia).not.toHaveBeenCalled()
  })

  it('refuses an audio declared longer than 180 seconds before creating anything', async () => {
    const deps = makeDeps()
    const audio = { kind: 'audio_note' as const, mime_type: 'audio/mp4' as const, size_bytes: 1200 }

    await expect(
      createMediaAsset(
        deps,
        USER_ID,
        { ...audio, duration_ms: 180_001 },
        'mobile-media-request-0002',
        new Date('2026-07-20T12:00:00.000Z'),
        ASSET_ID,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'audio_too_long' })
    expect(deps.repository.create).not.toHaveBeenCalled()
    expect(deps.storage.createSignedUpload).not.toHaveBeenCalled()

    await expect(
      createMediaAsset(
        deps,
        USER_ID,
        { ...audio, duration_ms: 180_000 },
        'mobile-media-request-0003',
        new Date('2026-07-20T12:00:00.000Z'),
        ASSET_ID,
      ),
    ).resolves.toMatchObject({ replayed: false })
  })

  it('reuses the asset for a repeated source request without inserting a duplicate', async () => {
    const existing = asset({ kind: 'meal_photo', bucket_id: 'meal-photos' })
    const deps = makeDeps(existing)

    const result = await createMediaAsset(
      deps,
      USER_ID,
      { kind: 'meal_photo', mime_type: 'image/jpeg', size_bytes: 1200 },
      'mobile-media-request-0002',
      new Date('2026-07-20T12:00:00.000Z'),
      ASSET_ID,
    )

    expect(deps.repository.create).not.toHaveBeenCalled()
    expect(result.asset.id).toBe(ASSET_ID)
    expect(deps.storage.createSignedUpload).toHaveBeenCalledTimes(1)
  })

  it('verifies object metadata before marking an upload complete', async () => {
    const deps = makeDeps()

    await expect(
      completeMediaUpload(deps, USER_ID, ASSET_ID, new Date('2026-07-20T12:05:00.000Z')),
    ).resolves.toMatchObject({ status: 'uploaded', size_bytes: 1200 })
    expect(deps.repository.markUploaded).toHaveBeenCalledWith(USER_ID, ASSET_ID, {
      actualSizeBytes: 1200,
      etag: 'etag-1',
      uploadedAt: '2026-07-20T12:05:00.000Z',
    })
  })

  it('removes and rejects an object whose verified type or size differs', async () => {
    const deps = makeDeps()
    vi.mocked(deps.storage.getObjectInfo).mockResolvedValue({
      size: 1300,
      contentType: 'image/png',
      etag: 'etag-bad',
    })

    await expect(completeMediaUpload(deps, USER_ID, ASSET_ID)).rejects.toMatchObject({
      status: 422,
      code: 'media_upload_mismatch',
    })
    expect(deps.storage.remove).toHaveBeenCalledWith(
      'body-checkin-photos',
      `${USER_ID}/${ASSET_ID}.jpg`,
    )
    expect(deps.repository.markUploadFailed).toHaveBeenCalledWith(
      USER_ID,
      ASSET_ID,
      'metadata_mismatch',
    )
  })

  it('marks a missing object failed while preserving transient Storage retries', async () => {
    const missingDeps = makeDeps()
    vi.mocked(missingDeps.storage.getObjectInfo).mockRejectedValue(
      new MobileApiError(409, 'media_upload_not_found', 'Uploaded media was not found'),
    )

    await expect(completeMediaUpload(missingDeps, USER_ID, ASSET_ID)).rejects.toMatchObject({
      status: 422,
      code: 'media_upload_missing',
    })
    expect(missingDeps.repository.markUploadFailed).toHaveBeenCalledWith(
      USER_ID,
      ASSET_ID,
      'object_missing',
    )

    const unavailableDeps = makeDeps()
    vi.mocked(unavailableDeps.storage.getObjectInfo).mockRejectedValue(
      new MobileApiError(503, 'media_storage_unavailable', 'Media storage is unavailable'),
    )
    await expect(completeMediaUpload(unavailableDeps, USER_ID, ASSET_ID)).rejects.toMatchObject({
      status: 503,
      code: 'media_storage_unavailable',
    })
    expect(unavailableDeps.repository.markUploadFailed).not.toHaveBeenCalled()
  })

  it('scopes every lookup to the patient and uses shorter body-photo download URLs', async () => {
    const deps = makeDeps(asset({ status: 'processed' }))

    const result = await getMediaAsset(deps, USER_ID, ASSET_ID)

    expect(deps.repository.findOwned).toHaveBeenCalledWith(USER_ID, ASSET_ID)
    expect(deps.storage.createSignedDownload).toHaveBeenCalledWith(
      'body-checkin-photos',
      `${USER_ID}/${ASSET_ID}.jpg`,
      60,
    )
    expect(result.download?.expires_in_seconds).toBe(60)
  })

  it('uses five-minute downloads for ordinary meal media', async () => {
    const deps = makeDeps(
      asset({
        kind: 'meal_photo',
        bucket_id: 'meal-photos',
        status: 'uploaded',
      }),
    )

    await getMediaAsset(deps, USER_ID, ASSET_ID)

    expect(deps.storage.createSignedDownload).toHaveBeenCalledWith(
      'meal-photos',
      `${USER_ID}/${ASSET_ID}.jpg`,
      300,
    )
  })

  it('physically removes media before marking its catalog row deleted', async () => {
    const deps = makeDeps(asset({ status: 'processed' }))

    await deleteMediaAsset(deps, USER_ID, ASSET_ID, new Date('2026-07-20T12:10:00.000Z'))

    const removeOrder = vi.mocked(deps.storage.remove).mock.invocationCallOrder[0]
    const deleteOrder = vi.mocked(deps.repository.markDeleted).mock.invocationCallOrder[0]
    expect(removeOrder).toBeLessThan(deleteOrder ?? 0)
  })

  it('dispatches processing without leaking caption text into the event', async () => {
    const deps = makeDeps(asset({ status: 'uploaded', context_text: 'Sensitive meal caption' }))

    const result = await requestMediaProcessing(
      deps,
      USER_ID,
      ASSET_ID,
      'mobile-media-process-0001',
    )

    expect(deps.events.sendProcessingRequested).toHaveBeenCalledWith({
      assetId: ASSET_ID,
      userId: USER_ID,
      requestId: expect.stringMatching(/^[a-f0-9]{64}$/),
    })
    expect(JSON.stringify(vi.mocked(deps.events.sendProcessingRequested).mock.calls)).not.toContain(
      'Sensitive meal caption',
    )
    expect(result).toMatchObject({ id: ASSET_ID, status: 'uploaded' })
  })
})
