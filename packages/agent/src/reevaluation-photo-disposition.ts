import { z } from 'zod'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const revision = z
  .string()
  .regex(/^[1-9][0-9]{0,18}$/)
  .refine((value) => value.length < 19 || value <= '9223372036854775807')
const count = z.union([z.literal('0'), revision])
const instant = z.string().refine((value) => {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(value) || value.startsWith('0000'))
    return false
  const milliseconds = `${value.slice(0, 23)}Z`
  const date = new Date(milliseconds)
  return Number.isFinite(date.getTime()) && date.toISOString() === milliseconds
})
const scopeSchema = z.object({ userId: uuid, cycleId: uuid, acceptanceId: uuid }).strict()
const headerSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    acceptance_id: uuid,
    reason: z.enum([
      'discarded',
      'expired',
      'consent_changed',
      'cycle_changed',
      'completed',
      'account_deleted',
    ]),
    request_revision: revision,
    sealed_at: instant,
    manifest_count: count,
    capability_revision: revision,
    sweep_no: revision,
    sweep_capability_revision: revision,
    sweep_started_at: instant,
    sweep_state: z.enum(['pending', 'waiting', 'settled']),
    cursor: uuid.nullable(),
    next_sweep_at: instant.nullable(),
    last_ack_at: instant.nullable(),
  })
  .strict()
const prepareSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    cycle_id: uuid,
    acceptance_id: uuid,
    kind: z.enum(['live', 'ready', 'waiting', 'settled']),
    disposition: headerSchema.nullable(),
  })
  .strict()
const identity = {
  version: z.literal(1),
  user_id: uuid,
  signup_generation: uuid,
  cycle_id: uuid,
  acceptance_id: uuid,
  disposition_id: uuid,
  sweep_no: revision,
  capability_revision: revision,
}
const pageSchema = z
  .object({
    ...identity,
    cursor: uuid.nullable(),
    has_more: z.boolean(),
    items: z
      .array(
        z
          .object({
            asset_id: uuid,
            bucket_id: z.literal('body-checkin-photos'),
            object_path: z.string(),
          })
          .strict(),
      )
      .min(1)
      .max(200),
  })
  .strict()
const ackSchema = z
  .object({
    ...identity,
    previous_cursor: uuid.nullable(),
    cursor: uuid,
    sweep_complete: z.boolean(),
    state: z.enum(['pending', 'waiting', 'settled']),
    assets: z
      .array(
        z
          .object({
            asset_id: uuid,
            newly_deleted: z.boolean(),
            catalogue_state: z.enum(['deleted', 'failed_upload_preserved']),
          })
          .strict(),
      )
      .min(1)
      .max(200),
  })
  .strict()
export type ReevaluationPhotoDispositionScope = z.infer<typeof scopeSchema>
export type ReevaluationPhotoDispositionHeader = z.infer<typeof headerSchema>
export interface ReevaluationPhotoDispositionDependencies {
  prepare(scope: ReevaluationPhotoDispositionScope, signal: AbortSignal): Promise<unknown>
  page(
    header: ReevaluationPhotoDispositionHeader,
    cursor: string | null,
    signal: AbortSignal,
  ): Promise<unknown>
  remove(paths: readonly string[]): Promise<void>
  commit(
    header: ReevaluationPhotoDispositionHeader,
    cursor: string | null,
    assetIds: readonly string[],
    signal: AbortSignal,
  ): Promise<unknown>
}
type Reason = 'invalid_receipt' | 'unavailable' | 'timeout' | 'page_limit'
export type ReevaluationPhotoDispositionOutcome =
  | { state: 'live' | 'waiting' | 'settled'; newlyDeleted: number }
  | { state: 'incomplete'; reason: Reason; newlyDeleted: number }
class InvalidReceipt extends Error {}
function requireMatch(ok: boolean): asserts ok {
  if (!ok) throw new InvalidReceipt()
}
function matchIdentity(
  value: z.infer<typeof pageSchema> | z.infer<typeof ackSchema>,
  header: ReevaluationPhotoDispositionHeader,
) {
  return (
    value.user_id === header.user_id &&
    value.signup_generation === header.signup_generation &&
    value.cycle_id === header.cycle_id &&
    value.acceptance_id === header.acceptance_id &&
    value.disposition_id === header.id &&
    value.sweep_no === header.sweep_no &&
    value.capability_revision === header.capability_revision
  )
}

/** Pure module: no event, runtime client, route, job or environment startup.
 * A successful remove is a backend attestation, not proof of all future PUTs. */
export async function drainReevaluationPhotoDisposition(
  deps: ReevaluationPhotoDispositionDependencies,
  input: ReevaluationPhotoDispositionScope,
  options: { timeoutMs?: number; maxPages?: number; signal?: AbortSignal } = {},
): Promise<ReevaluationPhotoDispositionOutcome> {
  let newlyDeleted = 0
  const scope = scopeSchema.safeParse(input)
  const limits = z
    .object({
      timeoutMs: z.number().int().min(1).max(10000),
      maxPages: z.number().int().min(1).max(100),
    })
    .safeParse({ timeoutMs: options.timeoutMs ?? 3000, maxPages: options.maxPages ?? 5 })
  if (!scope.success || !limits.success)
    return { state: 'incomplete', reason: 'invalid_receipt', newlyDeleted }
  const currentScope = scope.data
  const configuration = limits.data
  const controller = new AbortController()
  const deadline = performance.now() + configuration.timeoutMs
  let stopped: ReevaluationPhotoDispositionOutcome | undefined
  let timer: ReturnType<typeof setTimeout> | undefined
  function stop(reason: Reason): ReevaluationPhotoDispositionOutcome {
    if (!stopped) {
      stopped = { state: 'incomplete', reason, newlyDeleted }
      controller.abort()
    }
    return stopped
  }
  function guard() {
    if (stopped || options.signal?.aborted || performance.now() >= deadline) {
      stop('timeout')
      throw new Error('disposition_stopped')
    }
  }
  async function work(): Promise<ReevaluationPhotoDispositionOutcome> {
    try {
      guard()
      const prepared = prepareSchema.parse(await deps.prepare(currentScope, controller.signal))
      guard()
      requireMatch(
        prepared.user_id === currentScope.userId &&
          prepared.cycle_id === currentScope.cycleId &&
          prepared.acceptance_id === currentScope.acceptanceId,
      )
      if (prepared.kind === 'live') {
        requireMatch(prepared.disposition === null)
        return { state: 'live', newlyDeleted }
      }
      const h = prepared.disposition
      requireMatch(
        h !== null &&
          h.user_id === currentScope.userId &&
          h.cycle_id === currentScope.cycleId &&
          h.acceptance_id === currentScope.acceptanceId &&
          h.sweep_capability_revision === h.capability_revision &&
          h.sweep_started_at >= h.sealed_at &&
          (h.last_ack_at === null || h.last_ack_at >= h.sweep_started_at),
      )
      requireMatch(
        (prepared.kind === 'ready' &&
          h.sweep_state === 'pending' &&
          h.next_sweep_at === null &&
          h.manifest_count !== '0') ||
          (prepared.kind === 'waiting' &&
            h.sweep_state === 'waiting' &&
            h.last_ack_at !== null &&
            h.next_sweep_at !== null) ||
          (prepared.kind === 'settled' &&
            h.sweep_state === 'settled' &&
            h.last_ack_at !== null &&
            h.next_sweep_at === null),
      )
      if (prepared.kind !== 'ready') return { state: prepared.kind, newlyDeleted }
      let cursor = h.cursor
      let visited = 0n
      for (let pageNo = 0; pageNo < configuration.maxPages; pageNo++) {
        guard()
        const page = pageSchema.parse(await deps.page(h, cursor, controller.signal))
        guard()
        requireMatch(
          matchIdentity(page, h) &&
            page.cursor === cursor &&
            (!page.has_more || page.items.length === 200),
        )
        const ids = Object.freeze(page.items.map((item) => item.asset_id))
        requireMatch(
          ids.every((id, i) => id > (i ? (ids[i - 1] ?? '') : (cursor ?? ''))) &&
            page.items.every((item) =>
              ['jpg', 'png', 'webp', 'heic', 'heif'].some(
                (extension) => item.object_path === `${h.user_id}/${item.asset_id}.${extension}`,
              ),
            ),
        )
        visited += BigInt(ids.length)
        requireMatch(
          visited <= BigInt(h.manifest_count) &&
            (page.has_more || h.cursor !== null || visited === BigInt(h.manifest_count)),
        )
        const paths = Object.freeze(page.items.map((item) => item.object_path))
        guard()
        await deps.remove(paths)
        guard()
        const ack = ackSchema.parse(await deps.commit(h, cursor, ids, controller.signal))
        guard()
        const last = ids.at(-1)
        requireMatch(
          matchIdentity(ack, h) &&
            ack.previous_cursor === cursor &&
            ack.cursor === last &&
            ack.sweep_complete === !page.has_more &&
            (ack.sweep_complete ? ack.state !== 'pending' : ack.state === 'pending') &&
            ack.assets.length === ids.length &&
            ack.assets.every(
              (asset, i) =>
                asset.asset_id === ids[i] &&
                (asset.catalogue_state !== 'failed_upload_preserved' || !asset.newly_deleted),
            ),
        )
        newlyDeleted += ack.assets.filter((asset) => asset.newly_deleted).length
        cursor = ack.cursor
        if (ack.sweep_complete)
          return { state: ack.state === 'settled' ? 'settled' : 'waiting', newlyDeleted }
      }
      return stop('page_limit')
    } catch (error) {
      return (
        stopped ??
        stop(
          error instanceof z.ZodError || error instanceof InvalidReceipt
            ? 'invalid_receipt'
            : 'unavailable',
        )
      )
    }
  }
  const timeout = new Promise<ReevaluationPhotoDispositionOutcome>((resolve) => {
    timer = setTimeout(() => resolve(stop('timeout')), configuration.timeoutMs)
  })
  let abort: (() => void) | undefined
  const parent = new Promise<ReevaluationPhotoDispositionOutcome>((resolve) => {
    abort = () => resolve(stop('timeout'))
    if (options.signal?.aborted) abort()
    else options.signal?.addEventListener('abort', abort, { once: true })
  })
  try {
    return await Promise.race([work(), timeout, parent])
  } finally {
    if (timer !== undefined) clearTimeout(timer)
    if (abort !== undefined) options.signal?.removeEventListener('abort', abort)
  }
}
