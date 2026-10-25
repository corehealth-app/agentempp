/** Real generic handlers/services/adapters after a supplied authenticated context.
 * Auth and HTTP idempotency wrappers are outside this query-boundary test;
 * existing signup audit tests exercise those wrappers with the same handlers.
 */
import type { ServiceClient } from '@mpp/db'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { POST } from '@/app/api/mobile/v1/media/[id]/complete/route'
import { DELETE, GET } from '@/app/api/mobile/v1/media/[id]/route'
import { MobileApiError, mobileErrorResponse } from './http'
import { createSupabaseMediaDependencies } from './supabase-media'
import { SignupBodyPhotoMemoryDb } from './testing/signup-body-photo-memory-db'

const world = vi.hoisted(() => ({ db: undefined as unknown }))
const USER = 'b3b01000-0000-4000-8000-000000000601'
const ID = 'b3b01000-0000-4000-8000-000000000602'
const NOW = '2026-10-24T23:00:00.000Z'

vi.mock('@mpp/inngest-functions', () => ({ inngest: { send: vi.fn() } }))
vi.mock('./route', () => ({
  createMobileRouteWithContext:
    (handler: (context: unknown, routeContext: unknown) => Promise<Response>) =>
    async (_request: Request, routeContext: unknown) => {
      try {
        return await handler(
          {
            supabase: (world.db as SignupBodyPhotoMemoryDb).client,
            auth: { userId: USER },
            requestId: 'qa',
          },
          routeContext,
        )
      } catch (error) {
        if (error instanceof MobileApiError) return mobileErrorResponse(error, 'qa')
        throw error
      }
    },
}))
vi.mock('./idempotency', () => ({
  executeSupabaseIdempotent: (_context: unknown, _body: unknown, run: () => Promise<Response>) =>
    run(),
}))

class MediaDb extends SignupBodyPhotoMemoryDb {
  readonly sign = vi.fn(async () => ({
    data: { signedUrl: 'https://storage.test/synthetic' },
    error: null,
  }))
  override get client(): ServiceClient {
    const base = super.client
    return {
      ...base,
      storage: {
        from: (bucket: string) => ({ ...base.storage.from(bucket), createSignedUrl: this.sign }),
      },
    } as unknown as ServiceClient
  }
}

function db() {
  return world.db as MediaDb
}
function seed(marker: 1 | null, status = 'pending_upload', signup = false) {
  const row = db().seedMediaAsset({
    id: ID,
    user_id: USER,
    signup_origin: signup,
    reevaluation_origin_version: marker,
    status,
    actual_size_bytes: status === 'uploaded' ? 1200 : null,
    uploaded_at: status === 'uploaded' ? NOW : null,
  })
  db().upload(row, { size: 1200, contentType: 'image/jpeg' })
  return row
}
const operations = { get: GET, complete: POST, delete: DELETE }
function call(name: keyof typeof operations) {
  return operations[name](
    new Request(`https://app.test/media/${ID}`, {
      method: name === 'get' ? 'GET' : name === 'delete' ? 'DELETE' : 'POST',
    }),
    { params: Promise.resolve({ id: ID }) },
  )
}
beforeEach(() => {
  world.db = new MediaDb()
})

describe('recurring media cannot enter generic paths', () => {
  it.each([
    'get',
    'complete',
    'delete',
  ] as const)('%s refuses marked media before any Storage or mutation', async (name) => {
    const row = seed(1, name === 'get' ? 'uploaded' : 'pending_upload')
    const before = structuredClone(row)
    const response = await call(name)
    expect(response.status).toBe(404)
    expect(row).toEqual(before)
    expect(db().sign).not.toHaveBeenCalled()
    expect(db().operations.filter((op) => /^storage:|^update:/.test(op))).toEqual([])
    expect(db().objects.size).toBe(1)
  })

  it.each([
    false,
    true,
  ])('legacy NULL marker preserves generic get/complete/delete, signup=%s', async (signup) => {
    const row = seed(null, 'uploaded', signup)
    expect((await call('get')).status).toBe(200)
    expect(db().sign).toHaveBeenCalledOnce()
    expect((await call('complete')).status).toBe(200)
    expect((await call('delete')).status).toBe(200)
    expect(row.status).toBe('deleted')
    expect(db().objects.size).toBe(0)
  })

  it.each([
    'get',
    'complete',
    'delete',
  ] as const)('%s fails closed on missing schema without legacy fallback', async (name) => {
    seed(null, name === 'get' ? 'uploaded' : 'pending_upload')
    db().reevaluationSchemaAvailable = false
    const response = await call(name)
    expect(response.status).toBe(500)
    expect(db().operations.filter((op) => op === 'select:media_assets')).toHaveLength(1)
    expect(db().operations.filter((op) => /^storage:|^update:/.test(op))).toEqual([])
    expect(db().sign).not.toHaveBeenCalled()
    expect(db().objects.size).toBe(1)
  })

  it('new-mode hash lookup and all direct mutations exclude marked rows', async () => {
    const row = seed(1)
    const before = structuredClone(row)
    const { repository } = createSupabaseMediaDependencies(db().client, {
      reevaluationSchema: true,
    })
    expect(await repository.findByRequestHash(USER, row.source_request_hash)).toBeNull()
    await expect(
      repository.markUploaded(USER, ID, { actualSizeBytes: 1200, etag: null, uploadedAt: NOW }),
    ).rejects.toMatchObject({ code: 'media_storage_failed' })
    await repository.markUploadFailed(USER, ID, 'synthetic')
    await expect(repository.markDeleted(USER, ID, NOW)).rejects.toMatchObject({
      code: 'media_storage_failed',
    })
    expect(row).toEqual(before)
  })

  it('default library mode still works without the new schema', async () => {
    seed(null)
    db().reevaluationSchemaAvailable = false
    expect(
      await createSupabaseMediaDependencies(db().client).repository.findOwned(USER, ID),
    ).toMatchObject({ id: ID })
  })
})
