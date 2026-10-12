/**
 * B4b origin regressions. Synthetic repositories exercise the real signup
 * service and raw media helper, including the second lookup and a create
 * adapter resolving 23505 to a historical row. No database/provider call.
 */
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createMediaAsset, type MediaAssetRecord } from './media-service'
import {
  completeSignupBodyPhoto,
  createSignupBodyPhoto,
  type SignupBodyPhotoDependencies,
} from './signup-body-photo-service'
import { createSupabaseMediaDependencies } from './supabase-media'
import { SignupBodyPhotoMemoryDb } from './testing/signup-body-photo-memory-db'

const USER = '00000000-0000-4000-8000-000000000321'
const ID = '00000000-0000-4000-8000-000000000c20'
const NOW = new Date('2026-10-11T15:00:00.000Z')
const KEY = 'signup-origin-synthetic-001'
const INPUT = { pose: 'front' as const, mime_type: 'image/jpeg' as const, size_bytes: 1200 }

function asset(origin: boolean | null): MediaAssetRecord & { signup_origin: boolean | null } {
  return {
    id: ID,
    user_id: USER,
    kind: 'body_checkin_photo',
    bucket_id: 'body-checkin-photos',
    object_path: `${USER}/${ID}.jpg`,
    mime_type: 'image/jpeg',
    declared_size_bytes: 1200,
    actual_size_bytes: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: 'Foto de frente.',
    signup_origin: origin,
    signup_disposition_version: origin === true ? 1 : null,
    signup_disposition_assigned: false,
    signup_upload_open: origin === true,
    retention_until: '2028-10-10T15:00:00.000Z',
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: NOW.toISOString(),
    updated_at: NOW.toISOString(),
  }
}

function memory(created = asset(true)) {
  const repository = {
    findByRequestHash: vi.fn(async () => null as MediaAssetRecord | null),
    create: vi.fn(async () => created),
    findOwned: vi.fn(async () => created),
    markUploaded: vi.fn(),
    markUploadFailed: vi.fn(),
    markDeleted: vi.fn(),
  }
  const storage = {
    createSignedUpload: vi.fn(async () => ({ signedUrl: 'https://storage.test/synthetic' })),
    getObjectInfo: vi.fn(),
    createSignedDownload: vi.fn(),
    remove: vi.fn(),
  }
  const deps: SignupBodyPhotoDependencies = {
    enabled: true,
    consent: {
      currentDocument: vi.fn(async () => ({
        documentKey: 'body_photo_estimate_consent' as const,
        version: 'synthetic-v1',
        locale: 'pt-BR' as const,
        body: 'TEST consent only',
        bodyHash: 'a'.repeat(64),
      })),
      acceptedAt: vi.fn(async () => NOW.toISOString()),
      accept: vi.fn(),
    },
    catalogue: {
      listOpen: vi.fn(async () => []),
      listEvery: vi.fn(async () => []),
      countCreatedSince: vi.fn(async () => 0),
      markDeleted: vi.fn(),
      removeObjects: vi.fn(),
      onboardingCompleted: vi.fn(async () => false),
    },
    media: { repository, storage, events: { sendProcessingRequested: vi.fn() } },
  }
  return { deps, repository, storage }
}

function create(deps: SignupBodyPhotoDependencies) {
  return createSignupBodyPhoto(deps, { userId: USER } as MobileAuthContext, INPUT, KEY, NOW)
}

describe('trusted origin before signup upload tickets', () => {
  it('D4 already uploaded photo closes during catalogue read and dispatches no late reading', async () => {
    const fresh = {
      ...asset(true),
      status: 'uploaded' as const,
      actual_size_bytes: 1200,
      uploaded_at: NOW.toISOString(),
      signup_disposition_assigned: false,
      signup_upload_open: true,
    }
    const closed = { ...fresh, signup_disposition_assigned: true, signup_upload_open: false }
    const { deps, repository, storage } = memory(fresh)
    vi.mocked(deps.catalogue.listOpen).mockImplementation(async () => {
      repository.findOwned.mockResolvedValue(closed)
      return []
    })
    await expect(
      completeSignupBodyPhoto(deps, { userId: USER } as MobileAuthContext, ID, KEY, NOW),
    ).rejects.toMatchObject({ status: 409, code: 'media_upload_not_pending' })
    expect(deps.media.events.sendProcessingRequested).not.toHaveBeenCalled()
    expect(storage.getObjectInfo).not.toHaveBeenCalled()
    expect(deps.catalogue.removeObjects).not.toHaveBeenCalled()
    expect(deps.catalogue.markDeleted).not.toHaveBeenCalled()
  })
  it('D4 version1 historical membership refuses a replay before signing even after reset', async () => {
    const historical = {
      ...asset(true),
      signup_disposition_assigned: true,
      signup_upload_open: false,
    }
    const { deps, repository, storage } = memory(historical)
    repository.findByRequestHash.mockResolvedValue(historical)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'media_upload_not_pending',
    })
    expect(storage.createSignedUpload).not.toHaveBeenCalled()
    expect(repository.create).not.toHaveBeenCalled()
  })

  it('D4 close while signing never returns the late upload ticket', async () => {
    const fresh = { ...asset(true), signup_disposition_assigned: false, signup_upload_open: true }
    const closed = { ...fresh, signup_disposition_assigned: true, signup_upload_open: false }
    const { deps, repository, storage } = memory(fresh)
    repository.findByRequestHash.mockResolvedValue(fresh)
    repository.findOwned.mockResolvedValue(closed)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'media_upload_not_pending',
    })
    expect(storage.createSignedUpload).toHaveBeenCalledOnce()
    expect(repository.findOwned).toHaveBeenCalledWith(USER, ID)
    expect(repository.create).not.toHaveBeenCalled()
  })
  it.each([
    'first lookup',
    'second lookup',
    '23505 lookup',
  ])('D4 legacy TRUE without fence version is preserved at %s before signing', async (phase) => {
    const historical = { ...asset(true), signup_disposition_version: null }
    const { deps, repository, storage } = memory(historical)
    if (phase === 'first lookup') repository.findByRequestHash.mockResolvedValue(historical)
    if (phase === 'second lookup')
      repository.findByRequestHash.mockResolvedValueOnce(null).mockResolvedValueOnce(historical)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(storage.createSignedUpload).not.toHaveBeenCalled()
    expect(historical.signup_origin).toBe(true)
    expect(historical.signup_disposition_version).toBeNull()
    expect(repository.create).toHaveBeenCalledTimes(phase === '23505 lookup' ? 1 : 0)
  })
  it.each([
    false,
    null,
  ])('B4B-ORIGIN-04 first hash replay UNKNOWN=%s refuses without a ticket or retag', async (origin) => {
    const { deps, repository, storage } = memory()
    const historical = asset(origin)
    repository.findByRequestHash.mockResolvedValue(historical)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(storage.createSignedUpload).not.toHaveBeenCalled()
    expect(repository.create).not.toHaveBeenCalled()
    expect(historical.signup_origin).toBe(origin)
    expect(deps.consent.currentDocument).not.toHaveBeenCalled()
  })

  it.each([
    false,
    null,
  ])('B4B-ORIGIN-05 second hash lookup UNKNOWN=%s refuses before a ticket', async (origin) => {
    const { deps, repository, storage } = memory()
    const historical = asset(origin)
    repository.findByRequestHash.mockResolvedValueOnce(null).mockResolvedValueOnce(historical)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(repository.findByRequestHash).toHaveBeenCalledTimes(2)
    expect(storage.createSignedUpload).not.toHaveBeenCalled()
    expect(repository.create).not.toHaveBeenCalled()
    expect(historical.signup_origin).toBe(origin)
  })

  it.each([
    false,
    null,
  ])('B4B-ORIGIN-06 create/23505 resolves UNKNOWN=%s and refuses before a ticket', async (origin) => {
    const historical = asset(origin)
    const { deps, repository, storage } = memory(historical)
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(repository.create).toHaveBeenCalledTimes(1)
    expect(storage.createSignedUpload).not.toHaveBeenCalled()
    expect(historical.signup_origin).toBe(origin)
  })

  it('B4B-ORIGIN-07 signup marks only the INSERT and exposes no origin field', async () => {
    const { deps, repository } = memory()
    const result = await create(deps)
    expect(repository.create).toHaveBeenCalledWith(expect.objectContaining({ signupOrigin: true }))
    expect(result.photo).toEqual({
      id: ID,
      pose: 'front',
      status: 'pending_upload',
      created_at: NOW.toISOString(),
    })
    expect(JSON.stringify(result)).not.toContain('signup_origin')
    expect(JSON.stringify(result)).not.toContain('signupOrigin')
  })

  it('B4B-ORIGIN-08 generic helper does not opt into signup origin', async () => {
    const { deps, repository } = memory({
      ...asset(false),
      kind: 'meal_photo',
      bucket_id: 'meal-photos',
    })
    const result = await createMediaAsset(
      deps.media,
      USER,
      {
        kind: 'meal_photo',
        mime_type: 'image/jpeg',
        size_bytes: 1200,
      },
      KEY,
      NOW,
      ID,
    )
    expect(repository.create).toHaveBeenCalledWith(
      expect.not.objectContaining({ signupOrigin: true }),
    )
    expect(JSON.stringify(result)).not.toContain('signup_origin')
  })

  it.each([
    false,
    null,
  ])('B4B-ORIGIN-09 strict DB23505 resolves historical UNKNOWN=%s without retag/ticket', async (origin) => {
    class CollisionDb extends SignupBodyPhotoMemoryDb {
      protected override record(operation: string, detail: unknown = null) {
        if (operation === 'insert:media_assets') {
          const { payload } = detail as { payload: { source_request_hash: string } }
          this.seedMediaAsset({
            id: ID,
            user_id: USER,
            context_text: 'Foto de frente.',
            signup_origin: origin,
            source_request_hash: payload.source_request_hash,
          })
        }
        return super.record(operation, detail)
      }
    }
    const database = new CollisionDb()
    database.addAccount({ id: USER, authUserId: USER, token: 'synthetic-origin-test' })
    database.profiles.set(USER, { onboarding_completed: false, onboarding_completed_at: null })
    const { deps } = memory()
    deps.media = createSupabaseMediaDependencies(database.client, { signupPhotos: true })
    await expect(create(deps)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(database.mediaAssets).toHaveLength(1)
    expect(database.mediaAssets[0]?.signup_origin).toBe(origin)
    expect(
      database.operations.filter(
        (operation) => operation === 'rpc:get_mobile_signup_body_photo_asset',
      ),
    ).toHaveLength(3)
    expect(
      database.operations.filter((operation) => operation === 'insert:media_assets'),
    ).toHaveLength(1)
    expect(
      database.operations.some(
        (operation) => operation.startsWith('update:') || operation.startsWith('storage:'),
      ),
    ).toBe(false)
    const inserted = database.calls.find((call) => call.operation === 'insert:media_assets')
      ?.detail as { payload: Record<string, unknown> }
    expect(inserted.payload.signup_origin).toBe(true)
  })

  it('B4B-ORIGIN-10 generic adapter keeps its old projection/default INSERT', async () => {
    const database = new SignupBodyPhotoMemoryDb()
    const result = await createMediaAsset(
      createSupabaseMediaDependencies(database.client),
      USER,
      {
        kind: 'meal_photo',
        mime_type: 'image/jpeg',
        size_bytes: 1200,
      },
      KEY,
      NOW,
      ID,
    )
    expect(database.mediaAssets[0]?.signup_origin).toBe(false)
    const queries = database.calls.filter((call) => call.operation.endsWith(':media_assets'))
    for (const query of queries) {
      const detail = query.detail as { columns: string; payload: Record<string, unknown> | null }
      expect(detail.columns).not.toContain('signup_origin')
      if (detail.payload) expect(detail.payload).not.toHaveProperty('signup_origin')
    }
    expect(JSON.stringify(result)).not.toContain('signup_origin')
  })
})
