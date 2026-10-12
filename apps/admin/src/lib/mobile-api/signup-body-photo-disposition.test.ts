import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { disposeSignupBodyPhotos } from './signup-body-photo-disposition'

const OWNER = '00000000-0000-4000-8000-000000000101'
const OTHER = '00000000-0000-4000-8000-000000000102'
const GENERATION = '2026-10-12T02:00:00.123456Z'
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
type Params = Record<string, unknown>
type Call = { name: string; params: Params }
type AssetState = 'deleted' | 'absent' | 'failed_upload_preserved'

/** Declared synthetic RPC protocol. No database, Storage, Auth or network proof. */
function protocol(
  size: number,
  options: {
    manifestCount?: number
    remainingCount?: number
    completed?: boolean
    initialCursor?: string
    mutatePrepare?: (scope: Record<string, unknown>) => void
    mutatePage?: (page: Record<string, unknown>) => void
    mutateAck?: (ack: Record<string, unknown>) => void
    states?: AssetState[]
    remove?: () => Promise<{ data: unknown; error: unknown }>
  } = {},
) {
  const calls: Call[] = []
  const removals: string[][] = []
  const items = Array.from({ length: size }, (_, i) => ({
    asset_id: id(i + 1),
    bucket_id: 'body-checkin-photos',
    object_path: `${OWNER}/${id(i + 1)}.jpg`,
  }))
  let cursor: string | null = options.initialCursor ?? null
  const rpc = (name: string, params: Params) => {
    calls.push({ name, params })
    let data: Record<string, unknown>
    const identity = { version: 1, user_id: OWNER }
    if (name === 'prepare_mobile_signup_body_photo_disposition') {
      data = (params.p_swept_generations as string[]).includes(GENERATION)
        ? { ...identity, kind: 'empty', current_profile_completed: options.completed ?? true }
        : {
            ...identity,
            kind: 'ready',
            current_profile_completed: options.completed ?? true,
            generation: GENERATION,
            policy: 'delete_all_signup_v1',
            estimate_state: 'unusable',
            sweep_no: 2,
            cursor,
            manifest_count: options.manifestCount ?? size,
            remaining_count:
              options.remainingCount ??
              items.filter((item) => cursor === null || item.asset_id > cursor).length,
          }
      options.mutatePrepare?.(data)
    } else if (name === 'get_mobile_signup_body_photo_disposition_page') {
      const remaining = items.filter((item) => cursor === null || item.asset_id > cursor)
      data = {
        ...identity,
        generation: GENERATION,
        sweep_no: 2,
        cursor,
        has_more: remaining.length > 200,
        items: remaining.slice(0, 200).map((item) => ({ ...item })),
      }
      options.mutatePage?.(data)
    } else if (name === 'commit_mobile_signup_body_photo_disposition_page') {
      const ids = params.p_asset_ids as string[]
      const previous = cursor
      cursor = ids.at(-1) ?? null
      data = {
        ...identity,
        generation: GENERATION,
        sweep_no: 2,
        previous_cursor: previous,
        cursor,
        sweep_complete: cursor === items.at(-1)?.asset_id,
        assets: ids.map((assetId) => {
          const index = items.findIndex((item) => item.asset_id === assetId)
          const state = options.states?.[index] ?? 'deleted'
          return {
            asset_id: assetId,
            state,
            processing_result: null,
            newly_deleted: state === 'deleted',
            deleted_at: state === 'deleted' ? GENERATION : null,
            failure_stage: state === 'failed_upload_preserved' ? 'upload' : null,
            failure_code: state === 'failed_upload_preserved' ? 'upload_failed' : null,
          }
        }),
      }
      options.mutateAck?.(data)
    } else throw new Error('undeclared RPC')
    return Object.assign(Promise.resolve({ data, error: null }), {
      abortSignal: (_signal: AbortSignal) => Promise.resolve({ data, error: null }),
    })
  }
  const client = {
    rpc,
    storage: {
      from: (bucket: string) => {
        expect(bucket).toBe('body-checkin-photos')
        return {
          remove: async (paths: string[]) => {
            removals.push([...paths])
            return options.remove ? options.remove() : { data: [], error: null }
          },
        }
      },
    },
  } as unknown as ServiceClient
  return { client, calls, removals, items }
}

beforeEach(() => vi.spyOn(console, 'warn').mockImplementation(() => undefined))
afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('durable signup photo disposition orchestration', () => {
  it('validation reaching the deadline cannot authorize the next page', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(0)
    const db = protocol(1, {
      mutatePrepare: (scope) => {
        Object.defineProperty(scope, 'current_profile_completed', {
          enumerable: true,
          get: () => {
            clock.mockReturnValue(3000)
            return true
          },
        })
      },
    })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false }),
    ).toMatchObject({
      state: 'provenance_unknown',
      phase: 'persist',
      reason: 'timeout',
      newlyDeleted: 0,
    })
    expect(db.calls).toHaveLength(1)
    expect(db.removals).toEqual([])
  })
  it('rejects a final page of 1 when the sealed manifest contains 3', async () => {
    const db = protocol(1, { manifestCount: 3, remainingCount: 3 })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false }),
    ).toMatchObject({
      state: 'provenance_committed_cleanup_pending',
      reason: 'invalid_receipt',
      newlyDeleted: 0,
    })
    expect(db.removals).toEqual([])
    expect(db.calls.map((call) => call.name)).toEqual([
      'prepare_mobile_signup_body_photo_disposition',
      'get_mobile_signup_body_photo_disposition_page',
    ])
  })

  it('never removes another asset of the same owner when page ID and basename disagree', async () => {
    const db = protocol(1, {
      mutatePage: (page) => {
        ;(page.items as Record<string, unknown>[])[0].object_path = `${OWNER}/${id(999)}.jpg`
      },
    })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false }),
    ).toMatchObject({ reason: 'invalid_receipt', newlyDeleted: 0 })
    expect(db.removals).toEqual([])
    expect(db.calls).toHaveLength(2)
  })

  it.each([
    1001, 2001,
  ])('visits every sealed asset in %i rows through stable ordered pages', async (size) => {
    const db = protocol(size)
    expect(await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false })).toEqual(
      { state: 'complete', completed: true, newlyDeleted: size },
    )
    expect(db.removals.flat()).toEqual(db.items.map((item) => item.object_path))
    expect(db.removals).toHaveLength(Math.ceil(size / 200))
    expect(db.removals.every((page) => page.length <= 200)).toBe(true)
    const reads = db.calls.filter(
      (call) => call.name === 'get_mobile_signup_body_photo_disposition_page',
    )
    expect(reads.map((call) => call.params.p_expected_after)).toEqual([
      null,
      ...Array.from({ length: reads.length - 1 }, (_, n) => id((n + 1) * 200)),
    ])
  })

  it('counts only new transitions and still removes failed-upload and absent paths', async () => {
    const db = protocol(3, { states: ['deleted', 'failed_upload_preserved', 'absent'] })
    expect(await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false })).toEqual(
      { state: 'complete', completed: true, newlyDeleted: 1 },
    )
    expect(db.removals.flat()).toEqual(db.items.map((item) => item.object_path))
  })

  it('resumes a cursor and does not re-remove acknowledged assets from that sweep', async () => {
    const db = protocol(201, { initialCursor: id(200) })
    expect(await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false })).toEqual(
      { state: 'complete', completed: true, newlyDeleted: 1 },
    )
    expect(db.removals).toEqual([[`${OWNER}/${id(201)}.jpg`]])
  })

  it('rejects a resumed final page missing one of the remaining sealed assets', async () => {
    const db = protocol(2, { initialCursor: id(1), manifestCount: 3, remainingCount: 2 })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false }),
    ).toMatchObject({ reason: 'invalid_receipt', newlyDeleted: 0 })
    expect(db.removals).toEqual([])
    expect(db.calls).toHaveLength(2)
  })

  it('resweeps a historical completed generation while the current signup is open after reset', async () => {
    const db = protocol(2, {
      completed: false,
      mutateAck: (ack) => {
        for (const asset of ack.assets as Record<string, unknown>[]) asset.newly_deleted = false
      },
    })
    expect(await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: true })).toEqual({
      state: 'complete',
      completed: false,
      newlyDeleted: 0,
    })
    expect(db.removals.flat()).toEqual(db.items.map((item) => item.object_path))
    expect(db.calls.at(-1)).toEqual({
      name: 'prepare_mobile_signup_body_photo_disposition',
      params: { p_user_id: OWNER, p_generation: null, p_swept_generations: [GENERATION] },
    })
  })

  it.each([
    (page: Record<string, unknown>) => {
      page.user_id = OTHER
    },
    (page: Record<string, unknown>) => {
      page.generation = '2026-10-12T02:00:00.123457Z'
    },
    (page: Record<string, unknown>) => {
      page.cursor = id(99)
    },
    (page: Record<string, unknown>) => {
      ;(page.items as Record<string, unknown>[]).reverse()
    },
    (page: Record<string, unknown>) => {
      ;(page.items as Record<string, unknown>[])[0].object_path = `${OTHER}/${id(1)}.jpg`
    },
    (page: Record<string, unknown>) => {
      ;(page.items as Record<string, unknown>[])[0].object_path = `${OWNER}/../${id(1)}.jpg`
    },
  ])('rejects a mismatched or unsafe page before Storage', async (mutatePage) => {
    const db = protocol(2, { mutatePage })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false }),
    ).toMatchObject({ reason: 'invalid_receipt', newlyDeleted: 0 })
    expect(db.removals).toEqual([])
    expect(db.calls).toHaveLength(2)
  })

  it('a partial ACK after successful removal never authorizes skipping that generation', async () => {
    const db = protocol(2, {
      mutateAck: (ack) => {
        ;(ack.assets as unknown[]).pop()
      },
    })
    expect(
      await disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: true }),
    ).toMatchObject({ state: 'cleanup_unknown', reason: 'invalid_receipt', newlyDeleted: 0 })
    expect(db.removals).toHaveLength(1)
    expect(db.calls).toHaveLength(3)
  })

  it('late Storage completion after the total 3s deadline starts no SQL ACK', async () => {
    vi.useFakeTimers({ toFake: ['Date', 'setTimeout', 'clearTimeout'] })
    vi.setSystemTime(0)
    vi.spyOn(performance, 'now').mockImplementation(() => Date.now())
    let finish: (receipt: { data: unknown; error: unknown }) => void = () => undefined
    let entered: () => void = () => undefined
    const didEnter = new Promise<void>((resolve) => {
      entered = resolve
    })
    const db = protocol(1, {
      remove: () => {
        entered()
        return new Promise((resolve) => {
          finish = resolve
        })
      },
    })
    const pending = disposeSignupBodyPhotos(db.client, OWNER, { drainAllGenerations: false })
    await didEnter
    await vi.advanceTimersByTimeAsync(3000)
    expect(await pending).toMatchObject({
      state: 'cleanup_unknown',
      phase: 'remove',
      reason: 'timeout',
    })
    finish({ data: [], error: null })
    await vi.advanceTimersByTimeAsync(1)
    expect(db.calls.map((call) => call.name)).toEqual([
      'prepare_mobile_signup_body_photo_disposition',
      'get_mobile_signup_body_photo_disposition_page',
    ])
  })
})
