import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { ModerationPendingStore } from './pending-store'

const context = {
  origin: 'https://admin.example.invalid',
  owner: 'a'.repeat(64),
  login: 'b'.repeat(64),
}
const request = {
  kind: 'profile' as const,
  command: {
    operation_id: '20000000-0000-4000-b000-000000000001',
    member_id: '20000000-0000-4000-9000-000000000001',
    expected_revision: 1,
    action: 'suspend' as const,
  },
}
function fixture() {
  const values = new Map<string, string>()
  let tail = Promise.resolve()
  const driver = {
    origin: context.origin,
    get: (key: string) => values.get(key) ?? null,
    set: (key: string, value: string) => {
      values.set(key, value)
    },
    remove: (key: string) => {
      values.delete(key)
    },
    hash: async (value: string) => createHash('sha256').update(value).digest('hex'),
    withLock: async <T>(_name: string, work: () => Promise<T>): Promise<T> => {
      const previous = tail
      let release = () => {}
      tail = new Promise<void>((r) => {
        release = r
      })
      await previous
      try {
        return await work()
      } finally {
        release()
      }
    },
  }
  return { driver, values, store: new ModerationPendingStore(context, driver) }
}
describe('durable operator pending intents', () => {
  it('reads without initializing, writing or clearing any intent', async () => {
    const f = fixture()
    await expect(f.store.read()).resolves.toBeNull()
    expect(f.values.size).toBe(0)
  })
  it('persists the closed command before allowing dispatch and restores it after reload', async () => {
    const f = fixture()
    const saved = await f.store.reserve(request)
    expect(f.values.size).toBe(1)
    expect(saved).toMatchObject({ version: 1, context, request })
    await expect(new ModerationPendingStore(context, f.driver).read()).resolves.toEqual(saved)
    expect([...f.values.values()][0]).not.toMatch(/token|password|actor_id|auth_user_id/)
  })
  it('does not overwrite a pending command with another operator action', async () => {
    const f = fixture()
    const saved = await f.store.reserve(request)
    await expect(
      f.store.reserve({
        ...request,
        command: { ...request.command, operation_id: '20000000-0000-4000-b000-000000000002' },
      }),
    ).rejects.toMatchObject({ code: 'pending' })
    await expect(f.store.read()).resolves.toEqual(saved)
  })
  it('serializes two independent tab stores so only one command is reserved', async () => {
    const f = fixture()
    const other = new ModerationPendingStore(context, f.driver)
    const results = await Promise.allSettled([f.store.reserve(request), other.reserve(request)])
    expect(results.map((r) => r.status).sort()).toEqual(['fulfilled', 'rejected'])
    expect(f.values.size).toBe(1)
  })
  it('a newer login of the same operator can inspect the old pending, never overwrite it', async () => {
    const f = fixture()
    const saved = await f.store.reserve(request)
    const next = new ModerationPendingStore({ ...context, login: 'c'.repeat(64) }, f.driver)
    await expect(next.read()).resolves.toEqual(saved)
    await expect(next.reserve(request)).rejects.toMatchObject({ code: 'pending' })
  })
  it('keeps another operator namespace invisible and untouched', async () => {
    const f = fixture()
    const saved = await f.store.reserve(request)
    const other = new ModerationPendingStore({ ...context, owner: 'c'.repeat(64) }, f.driver)
    await expect(other.read()).resolves.toBeNull()
    await expect(f.store.read()).resolves.toEqual(saved)
  })
  it('rejects a copied foreign-origin payload without deleting it', async () => {
    const f = fixture()
    await f.store.reserve(request)
    const copied = new ModerationPendingStore(
      { ...context, origin: 'https://other.example.invalid' },
      { ...f.driver, origin: 'https://other.example.invalid' },
    )
    await expect(copied.read()).rejects.toMatchObject({ code: 'corrupt' })
    expect(f.values.size).toBe(1)
  })
  it('detects damaged commands without repairing or removing the evidence', async () => {
    const f = fixture()
    await f.store.reserve(request)
    const saved = [...f.values][0]
    if (!saved) throw new Error('Expected a durable pending fixture')
    const [key, value] = saved
    f.values.set(key, value.replace('suspend', 'restore'))
    await expect(f.store.read()).rejects.toMatchObject({ code: 'corrupt' })
    expect(f.values.get(key)).toContain('restore')
  })
  it('refuses a write if storage cannot persist it', async () => {
    const f = fixture()
    const store = new ModerationPendingStore(context, {
      ...f.driver,
      set: () => {
        throw Error('quota')
      },
    })
    await expect(store.reserve(request)).rejects.toMatchObject({ code: 'unavailable' })
    expect(f.values.size).toBe(0)
  })
  it('acknowledges only the exact snapshot and cannot erase a different intent', async () => {
    const f = fixture()
    const saved = await f.store.reserve(request)
    await expect(f.store.acknowledge({ ...saved, checksum: '0'.repeat(64) })).rejects.toMatchObject(
      { code: 'corrupt' },
    )
    await expect(f.store.read()).resolves.toEqual(saved)
    await f.store.acknowledge(saved)
    expect(f.values.size).toBe(0)
  })
})
