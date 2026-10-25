import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  cleanupExpiredMedia,
  createRetentionDependencies,
  type MediaRetentionDependencies,
} from './media-retention-cleanup.js'

function makeDeps(): MediaRetentionDependencies {
  return {
    repository: {
      listExpired: vi.fn().mockResolvedValue([
        {
          id: 'asset-1',
          userId: 'user-1',
          bucketId: 'meal-photos',
          objectPath: 'user-1/asset-1.jpg',
        },
      ]),
      markDeleted: vi.fn().mockResolvedValue(undefined),
    },
    storage: { remove: vi.fn().mockResolvedValue(undefined) },
  }
}

describe('media retention cleanup', () => {
  it('deletes an expired object before soft-deleting its catalog row', async () => {
    const deps = makeDeps()

    await expect(cleanupExpiredMedia(deps, new Date('2026-07-20T12:00:00.000Z'))).resolves.toEqual({
      deleted: 1,
    })
    expect(deps.repository.listExpired).toHaveBeenCalledWith('2026-07-20T12:00:00.000Z', 100)
    const storageOrder = vi.mocked(deps.storage.remove).mock.invocationCallOrder[0] ?? 0
    const catalogOrder = vi.mocked(deps.repository.markDeleted).mock.invocationCallOrder[0] ?? 0
    expect(storageOrder).toBeLessThan(catalogOrder)
  })

  it('keeps the catalog active when physical deletion fails so a retry can recover', async () => {
    const deps = makeDeps()
    vi.mocked(deps.storage.remove).mockRejectedValue(new Error('storage unavailable'))

    await expect(cleanupExpiredMedia(deps)).rejects.toThrow('storage unavailable')
    expect(deps.repository.markDeleted).not.toHaveBeenCalled()
  })
})

/** Query port evaluates the actual factory's filters against mixed rows. */
function queryDatabase(schemaAvailable = true) {
  type Row = Record<string, unknown>
  const rows: Row[] = [
    {
      id: 'legacy',
      user_id: 'qa',
      bucket_id: 'body-checkin-photos',
      object_path: 'qa/legacy.jpg',
      retention_until: '2026-10-23T12:00:00Z',
      status: 'uploaded',
      reevaluation_origin_version: null,
    },
    {
      id: 'recurring',
      user_id: 'qa',
      bucket_id: 'body-checkin-photos',
      object_path: 'qa/recurring.jpg',
      retention_until: '2026-10-23T12:00:00Z',
      status: 'uploaded',
      reevaluation_origin_version: 1,
    },
    {
      id: 'future',
      user_id: 'qa',
      bucket_id: 'meal-photos',
      object_path: 'qa/future.jpg',
      retention_until: '2027-10-23T12:00:00Z',
      status: 'uploaded',
      reevaluation_origin_version: null,
    },
    {
      id: 'tombstone',
      user_id: 'qa',
      bucket_id: 'meal-photos',
      object_path: 'qa/tombstone.jpg',
      retention_until: '2026-10-23T12:00:00Z',
      status: 'deleted',
      reevaluation_origin_version: null,
    },
  ]
  const removed: string[] = []
  type Result = { data: Row[] | null; error: { message: string } | null }
  class Query implements PromiseLike<Result> {
    private filters: Array<(row: Row) => boolean> = []
    private patch: Row | null = null
    private missingSchema = false
    private maximum = Number.POSITIVE_INFINITY
    select() {
      return this
    }
    update(patch: Row) {
      this.patch = patch
      return this
    }
    eq(column: string, value: unknown) {
      this.filters.push((row) => row[column] === value)
      return this
    }
    neq(column: string, value: unknown) {
      this.filters.push((row) => row[column] !== value)
      return this
    }
    lte(column: string, value: string) {
      this.filters.push(
        (row) => row[column] != null && Date.parse(String(row[column])) <= Date.parse(value),
      )
      return this
    }
    is(column: string, value: null) {
      if (column !== 'reevaluation_origin_version' || value !== null)
        throw new Error('unexpected is filter')
      this.missingSchema = !schemaAvailable
      this.filters.push((row) => row[column] === value)
      return this
    }
    order(column: string) {
      if (column !== 'retention_until') throw new Error('unexpected order')
      return this
    }
    limit(count: number) {
      this.maximum = count
      return this
    }
    // biome-ignore lint/suspicious/noThenProperty: model the awaited query builder
    then<T = Result, E = never>(
      resolve?: ((value: Result) => T | PromiseLike<T>) | null,
      reject?: ((reason: unknown) => E | PromiseLike<E>) | null,
    ): PromiseLike<T | E> {
      if (this.missingSchema)
        return Promise.resolve({
          data: null,
          error: { message: '42703 missing origin column' },
        }).then(resolve, reject)
      const selected = rows
        .filter((row) => this.filters.every((filter) => filter(row)))
        .slice(0, this.maximum)
      if (this.patch) for (const row of selected) Object.assign(row, this.patch)
      return Promise.resolve({ data: selected, error: null }).then(resolve, reject)
    }
  }
  const client = {
    from: (table: string) => {
      if (table !== 'media_assets') throw new Error('unexpected table')
      return new Query()
    },
    storage: {
      from: (bucket: string) => ({
        remove: async (paths: string[]) => {
          removed.push(...paths.map((path) => `${bucket}/${path}`))
          return { error: null }
        },
      }),
    },
  } as unknown as ServiceClient
  return { rows, removed, deps: createRetentionDependencies(client) }
}

describe('generic retention query boundary', () => {
  it('removes expired legacy bytes only, leaving recurring/future/tombstone rows intact', async () => {
    const { rows, removed, deps } = queryDatabase()
    const before = structuredClone(rows.slice(1))
    expect(await cleanupExpiredMedia(deps, new Date('2026-10-24T12:00:00Z'))).toEqual({
      deleted: 1,
    })
    expect(removed).toEqual(['body-checkin-photos/qa/legacy.jpg'])
    expect(rows[0]?.status).toBe('deleted')
    expect(rows.slice(1)).toEqual(before)
  })
  it('direct catalog update also excludes recurring media', async () => {
    const { rows, deps } = queryDatabase()
    const before = structuredClone(rows)
    await deps.repository.markDeleted('recurring', 'qa', '2026-10-24T12:00:00Z')
    expect(rows).toEqual(before)
  })
  it('missing schema fails before any Storage removal', async () => {
    const { rows, removed, deps } = queryDatabase(false)
    const before = structuredClone(rows)
    await expect(cleanupExpiredMedia(deps, new Date('2026-10-24T12:00:00Z'))).rejects.toThrow(
      '42703',
    )
    expect(removed).toEqual([])
    expect(rows).toEqual(before)
  })
})
