import type { z } from 'zod'
import type { socialProfileSchema } from '../mobile-api/journey-social-contracts'
import {
  type ModerationAction,
  type ModerationActionPort,
  type ModerationActionResult,
  moderationActionResult,
  type OperatorContext,
  sameOperatorContext,
} from './action-contracts'
import { type ModerationQueue, recoverModerationCommand } from './contracts'
import {
  type ModerationPending,
  type ModerationPendingStore,
  ModerationStorageError,
} from './pending-store'

type Profile = z.infer<typeof socialProfileSchema>
export interface ModerationPanelState {
  ready: boolean
  closed: boolean
  busy: boolean
  queue: ModerationQueue | null
  profile: Profile | null
  pending: ModerationPending | null
  error: string | null
  notice: string | null
}
class PanelFailure extends Error {
  constructor(readonly code: string) {
    super(code)
  }
}
function message(error: unknown) {
  if (error instanceof ModerationStorageError) return error.message
  if (error instanceof PanelFailure && error.code === 'pending')
    return 'Há uma pendência. Verifique seu resultado antes de outra ação.'
  if (error instanceof PanelFailure && error.code === 'missing')
    return 'Participante ou denúncia indisponível. Atualize a consulta.'
  if (error instanceof PanelFailure && error.code === 'changed')
    return 'Os dados mudaram. Atualize a consulta e confira a pendência antes de outra ação.'
  return 'Não foi possível conferir a resposta. Verifique a pendência antes de outra ação.'
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function proves(
  pending: ModerationPending,
  result: Extract<ModerationActionResult, { ok: true }>,
): boolean {
  const request = pending.request,
    command = request.command
  if (
    result.type === 'recover' &&
    (result.value.kind !== request.kind ||
      result.value.operation_id !== command.operation_id ||
      result.value.expected_revision !== command.expected_revision)
  )
    return false
  if (result.type === 'recover' && result.value.status === 'fenced')
    return result.value.receipt === null
  if (!['moderate', 'resolveReport', 'recover'].includes(result.type)) return false
  const receipt =
    result.type === 'moderate' || result.type === 'resolveReport' || result.type === 'recover'
      ? result.value.receipt
      : null
  if (
    !receipt ||
    receipt.operation_id !== command.operation_id ||
    receipt.revision !== command.expected_revision + 1
  )
    return false
  if (request.kind === 'profile')
    return (
      'member_id' in receipt &&
      receipt.member_id === request.command.member_id &&
      receipt.moderation === (request.command.action === 'suspend' ? 'suspended' : 'active')
    )
  return (
    'report_id' in receipt &&
    receipt.report_id === request.command.report_id &&
    receipt.report_status === request.command.status
  )
}

export function createModerationPanelModel(
  initialRaw: unknown,
  api: ModerationActionPort,
  store: ModerationPendingStore,
  uuid: () => string,
) {
  const initial = moderationActionResult.parse(initialRaw)
  if (!initial.ok || initial.type !== 'queue') throw new PanelFailure('unavailable')
  const context: OperatorContext = freeze(initial.context)
  let state: Readonly<ModerationPanelState> = freeze({
    ready: false,
    closed: false,
    busy: false,
    queue: initial.value,
    profile: null,
    pending: null,
    error: null,
    notice: null,
  })
  const listeners = new Set<() => void>()
  function patch(update: Partial<ModerationPanelState>) {
    if (state.closed && update.closed !== true) return
    state = freeze({ ...state, ...update })
    for (const listener of listeners) listener()
  }
  function close() {
    if (state.closed) return
    patch({
      closed: true,
      ready: false,
      busy: false,
      queue: null,
      profile: null,
      pending: null,
      error: 'A sessão mudou. Reabra esta página para continuar.',
      notice: null,
    })
    listeners.clear()
  }
  async function call(action: ModerationAction) {
    const result = moderationActionResult.parse(await api(action))
    if (state.closed) return null
    if (!result.ok) {
      if (result.code === 'unauthorized' || result.code === 'forbidden') close()
      throw new PanelFailure(result.code)
    }
    if (!sameOperatorContext(result.context, context)) {
      close()
      throw new PanelFailure('unauthorized')
    }
    if (result.type !== action.type) throw new PanelFailure('unavailable')
    return result
  }
  async function run(work: () => Promise<void>, clearNotice = false) {
    if (state.closed || state.busy) return
    patch({ busy: true, error: null, ...(clearNotice ? { notice: null } : {}) })
    try {
      await work()
    } catch (error) {
      if (!state.closed) {
        if (error instanceof ModerationStorageError) {
          try {
            patch({ pending: await store.read() })
          } catch {
            patch({ ready: false })
          }
        }
        patch({ error: message(error) })
      }
    } finally {
      if (!state.closed) patch({ busy: false })
    }
  }
  async function readPending() {
    const pending = await store.read()
    if (!state.closed) patch({ pending, ready: true })
  }
  async function queue(append: boolean) {
    const cursor = append ? state.queue?.next_cursor : null
    if (append && !cursor) return
    const result = await call({
      type: 'queue',
      context,
      query: { limit: 20, cursor: cursor ?? null },
    })
    if (!result || result.type !== 'queue') return
    const entries = append
      ? [...(state.queue?.entries ?? []), ...result.value.entries]
      : result.value.entries
    if (new Set(entries.map((x) => x.report_id)).size !== entries.length) {
      patch({ queue: null })
      throw new PanelFailure('changed')
    }
    patch({ queue: { entries, next_cursor: result.value.next_cursor } })
  }
  async function select(member_id: string) {
    patch({ profile: null })
    const result = await call({ type: 'profile', context, member_id })
    if (!result || result.type !== 'profile') return
    if (result.value.member_id !== member_id) throw new PanelFailure('changed')
    patch({ profile: result.value })
  }
  async function finish(
    pending: ModerationPending,
    result: Extract<ModerationActionResult, { ok: true }>,
  ) {
    if (state.closed || !proves(pending, result)) throw new PanelFailure('unavailable')
    const cancelled = result.type === 'recover' && result.value.status === 'fenced'
    patch({
      notice: cancelled
        ? 'Envio cancelado antes de ser aplicado.'
        : 'Ação salva. O resultado foi conferido.',
    })
    if (result.type === 'moderate') patch({ profile: result.value.profile })
    await store.acknowledge(pending)
    if (state.closed) return
    patch({ pending: null })
    try {
      if (result.type === 'recover' && pending.request.kind === 'profile' && !cancelled)
        await select(pending.request.command.member_id)
      await queue(false)
    } catch (error) {
      if (!state.closed) {
        patch({ queue: null, error: message(error) })
      }
    }
  }
  async function write(request: unknown) {
    if (!state.ready || state.pending) throw new PanelFailure('pending')
    const parsed = recoverModerationCommand.parse(request)
    const pending = await store.reserve(parsed)
    if (state.closed) return
    patch({ pending })
    const result = await call(
      parsed.kind === 'profile'
        ? { type: 'moderate', context, command: parsed.command }
        : { type: 'resolveReport', context, command: parsed.command },
    )
    if (result) await finish(pending, result)
  }
  return {
    context,
    get snapshot() {
      return state
    },
    subscribe(listener: () => void) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    close,
    initialize() {
      return run(readPending)
    },
    syncPending() {
      return run(readPending)
    },
    refresh() {
      return run(async () => {
        await readPending()
        try {
          await queue(false)
        } catch (error) {
          if (!state.closed) patch({ queue: null })
          throw error
        }
      })
    },
    nextPage() {
      return run(async () => {
        try {
          await queue(true)
        } catch (error) {
          if (!state.closed) patch({ queue: null })
          throw error
        }
      })
    },
    selectMember(member_id: string) {
      return run(() => select(member_id), true)
    },
    moderate(action: 'suspend' | 'restore') {
      return run(async () => {
        const target = state.profile
        if (!target?.member_id) throw new PanelFailure('missing')
        await write({
          kind: 'profile',
          command: {
            operation_id: uuid(),
            member_id: target.member_id,
            expected_revision: target.revision,
            action,
          },
        })
      }, true)
    },
    resolveReport(report_id: string, status: 'resolved' | 'dismissed') {
      return run(async () => {
        const entry = state.queue?.entries.find((e) => e.report_id === report_id)
        if (!entry) throw new PanelFailure('missing')
        await write({
          kind: 'report',
          command: { operation_id: uuid(), report_id, expected_revision: entry.revision, status },
        })
      }, true)
    },
    recover() {
      return run(async () => {
        const pending = await store.read()
        if (state.closed) return
        patch({ pending })
        if (!pending) return
        const result = await call({
          type: 'recover',
          context,
          pending_owner: pending.context.owner,
          request: pending.request,
        })
        if (result) await finish(pending, result)
      }, true)
    },
  }
}
export type ModerationPanelModel = ReturnType<typeof createModerationPanelModel>
