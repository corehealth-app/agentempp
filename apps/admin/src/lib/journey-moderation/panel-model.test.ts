import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import type { ModerationAction, ModerationActionResult } from './action-contracts'
import { createModerationPanelModel } from './panel-model'
import {
  ModerationPendingStore,
  type ModerationStorageDriver,
  ModerationStorageError,
} from './pending-store'

const context = {
  origin: 'https://admin.example.invalid',
  owner: 'a'.repeat(64),
  login: 'b'.repeat(64),
}
const member = '20000000-0000-4000-9000-000000000001'
const report = '20000000-0000-4000-b000-000000000001'
const operation = '20000000-0000-4000-b000-000000000002'
const profile = {
  member_id: member,
  revision: 1,
  moderation: 'active' as const,
  opted_in: true,
  nickname: 'Pessoa consulta',
}
const entry = {
  member_id: member,
  report_id: report,
  revision: 1,
  profile_revision: 1,
  moderation: 'active' as const,
  nickname: 'Pessoa consulta',
  reason: 'nickname' as const,
  status: 'pending' as const,
  created_at: '2026-11-18T22:00:00.123456Z',
}
const initial = {
  ok: true as const,
  type: 'queue' as const,
  context,
  value: { entries: [entry], next_cursor: null },
}
function fixture(options: { values?: Map<string, string>; context?: typeof context } = {}) {
  const values = options.values ?? new Map<string, string>(),
    fixed = options.context ?? context
  const calls: ModerationAction[] = []
  let fail = false
  let malformed = false
  let deferred: Promise<void> | null = null
  const driver: ModerationStorageDriver = {
    origin: context.origin,
    get: (k) => values.get(k) ?? null,
    set: (k, v) => {
      values.set(k, v)
    },
    remove: (k) => {
      values.delete(k)
    },
    hash: async (v) => createHash('sha256').update(v).digest('hex'),
    withLock: async (_k, f) => f(),
  }
  const store = new ModerationPendingStore(fixed, driver)
  const api = async (action: ModerationAction): Promise<ModerationActionResult> => {
    calls.push(action)
    if (deferred) await deferred
    if (fail) throw Error('network')
    if (action.type === 'queue') return { ...initial, context: fixed }
    if (action.type === 'profile')
      return { ok: true, type: action.type, context: fixed, value: profile }
    if (action.type === 'moderate') {
      expect(values.size).toBe(1) // actual durable intent exists before physical call
      return {
        ok: true,
        type: action.type,
        context: fixed,
        value: {
          status: 'applied',
          profile: { ...profile, revision: 2, moderation: 'suspended' },
          receipt: {
            operation_id: malformed ? report : operation,
            member_id: member,
            revision: 2,
            previous_moderation: 'active',
            moderation: 'suspended',
          },
        },
      }
    }
    if (action.type === 'resolveReport')
      return {
        ok: true,
        type: action.type,
        context: fixed,
        value: {
          status: 'applied',
          receipt: {
            operation_id: operation,
            report_id: report,
            revision: 2,
            report_status: 'resolved',
          },
        },
      }
    return {
      ok: true,
      type: action.type,
      context: fixed,
      value: {
        status: 'fenced',
        kind: action.request.kind,
        operation_id: action.request.command.operation_id,
        expected_revision: action.request.command.expected_revision,
        receipt: null,
      },
    }
  }
  const model = createModerationPanelModel(
    { ...initial, context: fixed },
    api,
    store,
    () => operation,
  )
  return {
    model,
    calls,
    values,
    store,
    api,
    fail: () => {
      fail = true
    },
    malformed: () => {
      malformed = true
    },
    defer: (p: Promise<void>) => {
      deferred = p
    },
    driver,
  }
}
describe('operational moderation screen behavior', () => {
  it('does not overwrite closed session state after a delayed storage-error inspection', async () => {
    const f = fixture()
    let blocked = false
    let release = () => {}
    let entered = () => {}
    const gate = new Promise<void>((r) => {
        release = r
      }),
      reading = new Promise<void>((r) => {
        entered = r
      })
    class DelayedStore extends ModerationPendingStore {
      override async reserve(_request: unknown): Promise<never> {
        throw new ModerationStorageError('pending')
      }
      override async read() {
        if (blocked) {
          entered()
          await gate
        }
        return super.read()
      }
    }
    const model = createModerationPanelModel(
      initial,
      f.api,
      new DelayedStore(context, f.driver),
      () => operation,
    )
    await model.initialize()
    await model.selectMember(member)
    blocked = true
    const pending = model.moderate('suspend')
    await reading
    model.close()
    const closed = model.snapshot
    release()
    await pending
    expect(model.snapshot).toEqual(closed)
    expect(model.snapshot.error).toContain('sessão mudou')
  })
  it('opens by inspecting local pending only; refresh reads without writes', async () => {
    const f = fixture()
    await f.model.initialize()
    expect(f.calls).toEqual([])
    expect(f.model.snapshot.queue?.entries[0]?.report_id).toBe(report)
    await f.model.refresh()
    expect(f.calls.map((x) => x.type)).toEqual(['queue'])
    expect(f.values.size).toBe(0)
  })
  it('saves one explicit moderation, with persisted intent, then reads the updated queue', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.model.selectMember(member)
    await f.model.moderate('suspend')
    expect(f.calls.map((x) => x.type)).toEqual(['profile', 'moderate', 'queue'])
    expect(f.calls[1]).toEqual({
      type: 'moderate',
      context,
      command: {
        operation_id: operation,
        member_id: member,
        expected_revision: 1,
        action: 'suspend',
      },
    })
    expect(f.model.snapshot.profile?.moderation).toBe('suspended')
    expect(f.model.snapshot.pending).toBeNull()
    expect(f.values.size).toBe(0)
  })
  it('resolves a report without sending a profile moderation command', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.model.resolveReport(report, 'resolved')
    expect(f.calls.map((x) => x.type)).toEqual(['resolveReport', 'queue'])
    expect(f.model.snapshot.notice).toContain('salva')
  })
  it('keeps a lost response across reload without resending it; explicit recovery only fences/reads', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.model.selectMember(member)
    f.fail()
    await f.model.moderate('suspend')
    expect(f.values.size).toBe(1)
    f.model.close()
    const next = fixture({ values: f.values })
    await next.model.initialize()
    expect(next.calls).toEqual([])
    expect(next.model.snapshot.pending).not.toBeNull()
    await next.model.recover()
    expect(next.calls.map((x) => x.type)).toEqual(['recover', 'queue'])
    expect(next.values.size).toBe(0)
    expect(next.model.snapshot.notice).toContain('cancelado')
  })
  it('refuses a different action while a pending result exists', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.store.reserve({
      kind: 'profile',
      command: {
        operation_id: operation,
        member_id: member,
        expected_revision: 1,
        action: 'suspend',
      },
    })
    await f.model.syncPending()
    await f.model.resolveReport(report, 'resolved')
    expect(f.calls).toEqual([])
    expect(f.values.size).toBe(1)
  })
  it('does not dispatch when durable storage fails', async () => {
    const f = fixture()
    const store = new ModerationPendingStore(context, {
      ...f.driver,
      set: () => {
        throw Error('quota')
      },
    })
    const model = createModerationPanelModel(initial, f.api, store, () => operation)
    await model.initialize()
    await model.selectMember(member)
    await model.moderate('suspend')
    expect(f.calls.map((x) => x.type)).toEqual(['profile'])
    expect(model.snapshot.error).toBeTruthy()
  })
  it('does not acknowledge a mismatched receipt', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.model.selectMember(member)
    f.malformed()
    await f.model.moderate('suspend')
    expect(f.values.size).toBe(1)
    expect(f.model.snapshot.pending).not.toBeNull()
    expect(f.model.snapshot.notice).toBeNull()
  })
  it('closes synchronously and refuses late publication or pending erasure', async () => {
    const f = fixture()
    await f.model.initialize()
    await f.model.selectMember(member)
    let release = () => {}
    const wait = new Promise<void>((r) => {
      release = r
    })
    f.defer(wait)
    const result = f.model.moderate('suspend')
    while (f.calls.length < 2) await new Promise((r) => setTimeout(r, 0))
    f.model.close()
    expect(f.model.snapshot.queue).toBeNull()
    expect(f.model.snapshot.profile).toBeNull()
    release()
    await result
    expect(f.values.size).toBe(1)
    expect(f.model.snapshot.notice).toBeNull()
  })
  it('allows only explicit recovery after a new login of the same operator', async () => {
    const f = fixture()
    await f.store.reserve({
      kind: 'profile',
      command: {
        operation_id: operation,
        member_id: member,
        expected_revision: 1,
        action: 'suspend',
      },
    })
    const next = fixture({ values: f.values, context: { ...context, login: 'c'.repeat(64) } })
    await next.model.initialize()
    expect(next.calls).toEqual([])
    await next.model.recover()
    expect(next.calls[0]).toMatchObject({
      type: 'recover',
      context: { login: 'c'.repeat(64) },
      pending_owner: context.owner,
    })
    expect(next.calls.some((x) => x.type === 'moderate')).toBe(false)
  })
  it('another account cannot observe the old operator pending', async () => {
    const f = fixture()
    await f.store.reserve({
      kind: 'profile',
      command: {
        operation_id: operation,
        member_id: member,
        expected_revision: 1,
        action: 'suspend',
      },
    })
    const next = fixture({ values: f.values, context: { ...context, owner: 'd'.repeat(64) } })
    await next.model.initialize()
    expect(next.model.snapshot.pending).toBeNull()
    expect(f.values.size).toBe(1)
  })
})
