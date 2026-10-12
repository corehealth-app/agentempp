import { createHash } from 'node:crypto'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import type { SignupPhotoSnapshot } from './signup-body-photo-confirmation'
import {
  deleteSignupBodyPhotos,
  getSignupBodyPhotoState,
  type SignupBodyPhotoDependencies,
} from './signup-body-photo-service'

const OWNER = '00000000-0000-4000-8000-000000000321'
const AUTH_ID = '00000000-0000-4000-8000-000000000322'
const SOURCES = {
  front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
}
const AT = '2026-10-12T01:00:00.000Z'
const auth: MobileAuthContext = {
  accessToken: 'synthetic-test-token',
  authUserId: AUTH_ID,
  userId: OWNER,
  identity: { id: AUTH_ID, email: null, emailConfirmedAt: null },
  patient: {
    id: OWNER,
    authUserId: AUTH_ID,
    email: null,
    name: 'Synthetic',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}

function snapshot(): SignupPhotoSnapshot {
  const body = 'Synthetic CURRENT consent only.'
  return {
    version: 1,
    user_id: OWNER,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    poses: (['front', 'side', 'back'] as const).map((pose) => ({
      pose,
      photo: { id: SOURCES[pose], status: 'read', created_at: AT },
    })),
    remaining_uploads: 6,
    consent: {
      legal_document_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      document_key: 'body_photo_estimate_consent',
      version: 'synthetic-v2',
      locale: 'pt-BR',
      body,
      body_hash: createHash('sha256').update(body).digest('hex'),
      accepted_at: AT,
    },
    estimate: {
      is_estimate: true,
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
    },
    candidate: {
      method: 'arithmetic_mean_v1',
      body_fat_percent: 24,
      source_ids: SOURCES,
      fingerprint: 'a'.repeat(64),
    },
    confirmation: null,
  }
}

function dependencies(current = snapshot()) {
  const activation: { enabled: boolean } = { enabled: true }
  const deps = {
    ...activation,
    consent: {
      currentDocument: vi.fn(async () => ({
        documentKey: 'body_photo_estimate_consent' as const,
        version: 'synthetic-v1',
        locale: 'pt-BR' as const,
        body: 'Synthetic OLDER consent.',
        bodyHash: 'b'.repeat(64),
      })),
      acceptedAt: vi.fn(async () => AT),
      accept: vi.fn(),
    },
    catalogue: {
      listOpen: vi.fn(async () => []),
      listEvery: vi.fn(async () => []),
      countCreatedSince: vi.fn(async () => 9),
      markDeleted: vi.fn(),
      removeObjects: vi.fn(),
      onboardingCompleted: vi.fn(async () => false),
    },
    media: {
      repository: {
        findByRequestHash: vi.fn(),
        create: vi.fn(),
        findOwned: vi.fn(),
        markUploaded: vi.fn(),
        markUploadFailed: vi.fn(),
        markDeleted: vi.fn(),
      },
      storage: {
        createSignedUpload: vi.fn(),
        getObjectInfo: vi.fn(),
        createSignedDownload: vi.fn(),
        remove: vi.fn(),
      },
      events: { sendProcessingRequested: vi.fn() },
    },
    repairCompleted: vi.fn(
      async (): Promise<{ completed: boolean; newlyDeleted?: number }> => ({ completed: false }),
    ),
    loadStateSnapshot: vi.fn(async () => current),
  } satisfies SignupBodyPhotoDependencies
  return deps
}

describe('body photo state from one official snapshot', () => {
  it('projects three original readings from one snapshot with no catalogue lookup', async () => {
    const current = snapshot()
    const estimate = current.estimate
    const candidate = current.candidate
    if (!estimate || !candidate) throw new Error('invalid synthetic snapshot fixture')
    const readings = [18.125, 24.125, 30.125].map((value, index) => ({
      pose: (['front', 'side', 'back'] as const)[index],
      body_fat_percent: value,
    }))
    estimate.readings = readings
    estimate.by_sex = {
      masculino: { usable: true, body_fat_percent: 24.13 },
      feminino: { usable: true, body_fat_percent: 24.13 },
    }
    candidate.body_fat_percent = 24.13
    const deps = dependencies(current)
    const dto = await getSignupBodyPhotoState(deps, auth)
    expect(dto.estimate?.readings).toEqual(readings)
    expect(dto.estimate?.source_ids).toEqual(SOURCES)
    expect(dto.estimate?.fingerprint).toBe('a'.repeat(64))
    expect(dto.estimate?.by_sex.masculino).toEqual({ usable: true, body_fat_percent: 24.13 })
    expect(deps.loadStateSnapshot).toHaveBeenCalledTimes(1)
    expect(deps.catalogue.listOpen).not.toHaveBeenCalled()
    for (const field of [
      'notes',
      'confidence',
      'processing_result',
      'object_path',
      'uploaded_at_us',
    ])
      expect(JSON.stringify(dto.estimate?.readings)).not.toContain(`"${field}"`)
  })

  it('successive worker snapshots keep their own readings, mean and IDs together', async () => {
    const first = snapshot()
    const firstEstimate = first.estimate
    if (!firstEstimate) throw new Error('invalid synthetic snapshot fixture')
    firstEstimate.readings = [18, 24, 30].map((value, index) => ({
      pose: (['front', 'side', 'back'] as const)[index],
      body_fat_percent: value,
    }))
    const second = structuredClone(first)
    const secondEstimate = second.estimate
    const side = second.poses[1]?.photo
    const sideReading = secondEstimate?.readings?.[1]
    if (!secondEstimate || !side || !sideReading)
      throw new Error('invalid synthetic snapshot fixture')
    const newSide = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
    side.id = newSide
    sideReading.body_fat_percent = 25
    secondEstimate.by_sex = {
      masculino: { usable: true, body_fat_percent: 24.33 },
      feminino: { usable: true, body_fat_percent: 24.33 },
    }
    second.candidate = {
      method: 'arithmetic_mean_v1',
      body_fat_percent: 24.33,
      source_ids: { ...SOURCES, side: newSide },
      fingerprint: 'b'.repeat(64),
    }
    const deps = dependencies(first)
    deps.loadStateSnapshot.mockResolvedValueOnce(first).mockResolvedValueOnce(second)
    const a = await getSignupBodyPhotoState(deps, auth)
    const b = await getSignupBodyPhotoState(deps, auth)
    expect(a.estimate).toMatchObject({
      readings: firstEstimate.readings,
      source_ids: SOURCES,
      fingerprint: 'a'.repeat(64),
    })
    expect(b.estimate).toMatchObject({
      readings: secondEstimate.readings,
      source_ids: second.candidate.source_ids,
      fingerprint: 'b'.repeat(64),
      by_sex: secondEstimate.by_sex,
    })
    expect(deps.loadStateSnapshot).toHaveBeenCalledTimes(2)
    expect(deps.catalogue.listOpen).not.toHaveBeenCalled()
  })
  it.each([
    true,
    false,
  ])('DELETE retains two real deletions from repair when current completed=%s', async (completed) => {
    const deps = dependencies()
    deps.repairCompleted.mockResolvedValue({ completed, newlyDeleted: 2 })
    expect(await deleteSignupBodyPhotos(deps, auth)).toEqual({ deleted: 2 })
    expect(deps.catalogue.markDeleted).not.toHaveBeenCalled()
    expect(deps.catalogue.removeObjects).not.toHaveBeenCalled()
    expect(deps.catalogue.listEvery).toHaveBeenCalledTimes(completed ? 0 : 1)
  })
  it('projects current consent, poses, mean24, remaining6 and the same official IDs/hash', async () => {
    const current = snapshot()
    const deps = dependencies(current)
    const dto = await getSignupBodyPhotoState(deps, auth)
    expect(dto.estimate).toEqual({
      is_estimate: true,
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
      source_ids: SOURCES,
      fingerprint: 'a'.repeat(64),
    })
    expect(dto.poses).toEqual(current.poses)
    expect(dto.remaining_uploads).toBe(6)
    expect(dto.consent).toMatchObject({
      version: 'synthetic-v2',
      body: 'Synthetic CURRENT consent only.',
    })
    expect(deps.loadStateSnapshot).toHaveBeenCalledTimes(1)
    expect(deps.loadStateSnapshot).toHaveBeenCalledWith(OWNER)
    expect(deps.catalogue.listOpen).not.toHaveBeenCalled()
    expect(deps.catalogue.countCreatedSince).not.toHaveBeenCalled()
    expect(deps.consent.acceptedAt).not.toHaveBeenCalled()
    const serialized = JSON.stringify(dto)
    for (const field of [
      'generation_token',
      'legal_document_id',
      'confirmation',
      'processing_result',
      'readings',
      'confidence',
      'object_path',
    ])
      expect(serialized).not.toContain(`"${field}"`)
  })

  it('does not read a snapshot, consent or catalogue with the feature OFF', async () => {
    const deps = dependencies()
    deps.enabled = false
    const dto = await getSignupBodyPhotoState(deps, auth)
    expect(dto).toMatchObject({
      available: false,
      unavailable_reason: 'disabled',
      estimate: null,
      remaining_uploads: 0,
    })
    expect(deps.loadStateSnapshot).not.toHaveBeenCalled()
    expect(deps.consent.currentDocument).not.toHaveBeenCalled()
    expect(deps.repairCompleted).not.toHaveBeenCalled()
  })

  it('does not offer a candidate if completion is observed during the one repair', async () => {
    const deps = dependencies()
    deps.repairCompleted.mockResolvedValue({ completed: true })
    const dto = await getSignupBodyPhotoState(deps, auth)
    expect(dto.estimate).toBeNull()
    expect(dto.poses).toEqual(['front', 'side', 'back'].map((pose) => ({ pose, photo: null })))
    expect(dto.remaining_uploads).toBe(0)
    expect(deps.repairCompleted).toHaveBeenCalledTimes(1)
    expect(deps.loadStateSnapshot).toHaveBeenCalledTimes(1)
  })

  it('does not disguise pending cleanup as a successful state', async () => {
    const deps = dependencies()
    const error = new Error('synthetic cleanup pending')
    deps.repairCompleted.mockRejectedValue(error)
    await expect(getSignupBodyPhotoState(deps, auth)).rejects.toBe(error)
    expect(deps.repairCompleted).toHaveBeenCalledTimes(1)
  })
})
