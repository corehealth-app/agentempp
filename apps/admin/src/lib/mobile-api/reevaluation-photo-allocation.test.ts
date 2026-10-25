import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import {
  allocateReevaluationPhoto,
  REEVALUATION_PHOTO_QUOTA,
} from './reevaluation-photo-allocation'
import { createSupabaseReevaluationPhotoAllocationRepository } from './supabase-reevaluation-photo-allocation'
import fixture from './testing/reevaluation-photo-allocation-fixture.json'

const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const AUTH = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const request = fixture.request
function auth(): MobileAuthContext {
  return {
    userId: fixture.owner,
    authUserId: AUTH,
    accessToken: 'synthetic-local-only',
    identity: { id: AUTH, email: 'qa@example.invalid', emailConfirmedAt: '2026-10-01T00:00:00Z' },
    patient: {
      id: fixture.owner,
      authUserId: AUTH,
      email: 'qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
function setup(data: unknown = fixture.response) {
  const rpc = vi.fn().mockResolvedValue({ data, error: null })
  return {
    rpc,
    dependencies: {
      enabled: true,
      repository: createSupabaseReevaluationPhotoAllocationRepository({
        rpc,
      } as unknown as ServiceClient),
    },
  }
}
describe('dormant recurring photo allocation, verified identity and SQL quota', () => {
  it('parses actual six-slot local SQL output and calls exactly one owner-bound RPC', async () => {
    const { rpc, dependencies } = setup()
    await expect(allocateReevaluationPhoto(auth(), request, dependencies)).resolves.toEqual({
      availability: 'available',
      ...fixture.response,
    })
    expect(rpc.mock.calls).toEqual([
      [
        'create_mobile_reevaluation_photo_asset',
        {
          p_user_id: fixture.owner,
          p_cycle_id: request.cycleId,
          p_expected_revision: request.expectedRevision,
          p_acceptance_id: request.acceptanceId,
          p_pose: request.pose,
          p_mime_type: request.mimeType,
          p_size_bytes: request.sizeBytes,
          p_request_key: request.requestKey,
        },
      ],
    ])
    expect(REEVALUATION_PHOTO_QUOTA).toEqual({ max_new_photos: 6, window_seconds: 86400 })
  })
  it('disabled performs no repository access', async () => {
    const deps = {
      enabled: false,
      get repository(): never {
        throw new Error('unused')
      },
    }
    await expect(allocateReevaluationPhoto(auth(), request, deps)).resolves.toEqual({
      availability: 'unavailable',
      reason: 'disabled',
    })
  })
  it.each([
    { userId: B },
    { authUserId: B },
    { identity: { ...auth().identity, id: B } },
    { patient: { ...auth().patient, id: B } },
    { patient: { ...auth().patient, authUserId: B } },
    { patient: { ...auth().patient, status: 'deleted' } },
    { userId: 'invalid' },
  ])('rejects bad authenticated identity before writing %#', async (patch) => {
    const { rpc, dependencies } = setup()
    await expect(
      allocateReevaluationPhoto(
        { ...auth(), ...patch } as MobileAuthContext,
        request,
        dependencies,
      ),
    ).rejects.toMatchObject({
      status: 403,
      code: 'mobile_reevaluation_photo_allocation_identity_invalid',
    })
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    null,
    {},
    { ...request, userId: B },
    { ...request, objectPath: 'other' },
    { ...request, observedAt: '2026-10-01' },
    { ...request, expectedRevision: '0' },
    { ...request, expectedRevision: 2 },
    { ...request, expectedRevision: '9223372036854775808' },
    { ...request, cycleId: 'bad' },
    { ...request, acceptanceId: null },
    { ...request, requestKey: '' },
    { ...request, pose: 'unknown' },
    { ...request, mimeType: 'application/pdf' },
    { ...request, sizeBytes: 0 },
    { ...request, sizeBytes: 15728641 },
  ])('rejects malformed or client-owned authority before RPC %#', async (value) => {
    const { rpc, dependencies } = setup()
    await expect(allocateReevaluationPhoto(auth(), value, dependencies)).rejects.toMatchObject({
      status: 422,
    })
    expect(rpc).not.toHaveBeenCalled()
  })
  it.each([
    { user_id: B },
    { cycle_id: B },
    { consent_acceptance_id: B },
    { pose: 'back' },
    { mime_type: 'image/png' },
    { size_bytes: 1300 },
    { object_path: 'foreign/path.jpg' },
    { origin: 'signup' },
    { status: 'deleted' },
    { signup_generation: null },
  ])('rejects mismatched SQL asset projection %#', async (patch) => {
    const { dependencies } = setup({
      ...fixture.response,
      asset: { ...fixture.response.asset, ...patch },
    })
    await expect(allocateReevaluationPhoto(auth(), request, dependencies)).rejects.toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_photo_allocation_invalid_response',
    })
  })
  it('allows replay with a newer clinical revision, rejects a backwards revision', async () => {
    const { dependencies } = setup({ ...fixture.response, cycle_revision: '3' })
    await expect(allocateReevaluationPhoto(auth(), request, dependencies)).resolves.toHaveProperty(
      'cycle_revision',
      '3',
    )
    const backwards = setup({ ...fixture.response, cycle_revision: '1' })
    await expect(
      allocateReevaluationPhoto(auth(), request, backwards.dependencies),
    ).rejects.toMatchObject({ status: 500 })
  })
  it('normalizes request UUIDs while binding public owner separately from auth ID', async () => {
    const { dependencies, rpc } = setup()
    await allocateReevaluationPhoto(
      { ...auth(), userId: fixture.owner.toUpperCase() },
      {
        ...request,
        cycleId: request.cycleId.toUpperCase(),
        acceptanceId: request.acceptanceId.toUpperCase(),
        requestKey: request.requestKey.toUpperCase(),
      },
      dependencies,
    )
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({
      p_user_id: fixture.owner,
      p_cycle_id: request.cycleId,
    })
  })
  it('never invents an allocation when SQL returns no currently usable asset', async () => {
    const { dependencies, rpc } = setup(null)
    await expect(allocateReevaluationPhoto(auth(), request, dependencies)).rejects.toMatchObject({
      status: 409,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
