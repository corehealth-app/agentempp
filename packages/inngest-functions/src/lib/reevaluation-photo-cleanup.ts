import { z } from 'zod'
import type {
  ReevaluationPhotoDispositionOutcome,
  ReevaluationPhotoDispositionScope,
} from './reevaluation-photo-disposition.js'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const pageSchema = z
  .object({
    version: z.literal(1),
    items: z
      .array(z.object({ user_id: uuid, cycle_id: uuid, acceptance_id: uuid }).strict())
      .max(1),
    has_more: z.boolean(),
  })
  .strict()
const outcomeSchema = z.discriminatedUnion('state', [
  z
    .object({
      state: z.enum(['live', 'waiting', 'settled']),
      newlyDeleted: z.number().int().min(0).max(20000),
    })
    .strict(),
  z
    .object({
      state: z.literal('incomplete'),
      reason: z.enum(['invalid_receipt', 'unavailable', 'timeout', 'page_limit']),
      newlyDeleted: z.number().int().min(0).max(20000),
    })
    .strict(),
])
export interface ReevaluationPhotoCleanupDependencies {
  /** SQL commits a durable fair visit before this claim returns. */
  claim(limit: number, signal: AbortSignal): Promise<unknown>
  drain(
    scope: ReevaluationPhotoDispositionScope,
    options: { timeoutMs: number; maxPages: number; signal: AbortSignal },
  ): Promise<ReevaluationPhotoDispositionOutcome>
}
type Stop =
  | 'batch_end'
  | 'retry_deferred'
  | 'scope_limit'
  | 'timeout'
  | 'unavailable'
  | 'invalid_receipt'
  | 'invalid_input'
export interface ReevaluationPhotoCleanupResult {
  attempted: number
  live: number
  waiting: number
  settled: number
  incomplete: number
  newlyDeleted: number
  hasMore: boolean
  stopped: Stop
}
/** No environment, scheduler, Storage implementation or identity-bearing logs.
 * A failing scope yields to other owners; a later run reconciles its real state. */
export async function cleanupReevaluationPhotos(
  deps: ReevaluationPhotoCleanupDependencies,
  options: { timeoutMs?: number; maxScopes?: number } = {},
): Promise<ReevaluationPhotoCleanupResult> {
  const limits = z
    .object({
      timeoutMs: z.number().int().min(1).max(10000),
      maxScopes: z.number().int().min(1).max(100),
    })
    .safeParse({ timeoutMs: options.timeoutMs ?? 8000, maxScopes: options.maxScopes ?? 20 })
  const result: ReevaluationPhotoCleanupResult = {
    attempted: 0,
    live: 0,
    waiting: 0,
    settled: 0,
    incomplete: 0,
    newlyDeleted: 0,
    hasMore: false,
    stopped: 'batch_end',
  }
  if (!limits.success) return { ...result, stopped: 'invalid_input' }
  const config = limits.data,
    controller = new AbortController(),
    deadline = performance.now() + config.timeoutMs
  let stopped = false
  let timer: ReturnType<typeof setTimeout> | undefined
  const seen = new Map<string, string>()
  const guard = () => !stopped && performance.now() < deadline
  const finish = (reason: Stop) => {
    stopped = true
    controller.abort()
    return { ...result, stopped: reason }
  }
  async function work(): Promise<ReevaluationPhotoCleanupResult> {
    while (guard() && result.attempted < config.maxScopes) {
      let raw: unknown
      try {
        raw = await deps.claim(1, controller.signal)
      } catch {
        return finish(guard() ? 'unavailable' : 'timeout')
      }
      if (!guard()) return finish('timeout')
      const page = pageSchema.safeParse(raw)
      if (!page.success || (page.data.has_more && page.data.items.length !== 1))
        return finish('invalid_receipt')
      result.hasMore = page.data.has_more
      const item = page.data.items[0]
      if (!item) return finish('batch_end')
      const identity = `${item.user_id}/${item.cycle_id}`
      if (seen.has(item.acceptance_id))
        return finish(
          seen.get(item.acceptance_id) === identity ? 'retry_deferred' : 'invalid_receipt',
        )
      seen.set(item.acceptance_id, identity)
      result.attempted += 1
      try {
        const rawOutcome = await deps.drain(
          { userId: item.user_id, cycleId: item.cycle_id, acceptanceId: item.acceptance_id },
          {
            timeoutMs: Math.max(1, Math.min(3000, Math.floor(deadline - performance.now()))),
            maxPages: 5,
            signal: controller.signal,
          },
        )
        if (!guard()) return finish('timeout')
        const outcome = outcomeSchema.safeParse(rawOutcome)
        if (!outcome.success) return finish('invalid_receipt')
        result[outcome.data.state] += 1
        result.newlyDeleted += outcome.data.newlyDeleted
      } catch {
        if (!guard()) return finish('timeout')
        result.incomplete += 1
      }
      if (!result.hasMore) return finish('batch_end')
    }
    return finish(guard() ? 'scope_limit' : 'timeout')
  }
  const timeout = new Promise<ReevaluationPhotoCleanupResult>((resolve) => {
    timer = setTimeout(() => resolve(finish('timeout')), config.timeoutMs)
  })
  try {
    return await Promise.race([work(), timeout])
  } finally {
    stopped = true
    controller.abort()
    if (timer !== undefined) clearTimeout(timer)
  }
}
