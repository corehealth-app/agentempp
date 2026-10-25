import { z } from 'zod'
import type {
  ReevaluationPhotoDispositionOutcome,
  ReevaluationPhotoDispositionScope,
} from './reevaluation-photo-disposition.js'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const inputSchema = z.object({
  userId: uuid,
  cutoff: z
    .string()
    .datetime()
    .refine((value) => {
      const date = new Date(value)
      return Number.isFinite(date.getTime()) && date.toISOString() === value
    }),
})
const pageSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    eligible: z.boolean(),
    items: z.array(z.object({ cycle_id: uuid, acceptance_id: uuid }).strict()).max(20),
    has_more: z.boolean(),
    cursor: uuid.nullable(),
  })
  .strict()
export interface ReevaluationPhotoAccountPurgeDependencies {
  purge(userId: string, cutoff: string, signal: AbortSignal): Promise<unknown>
  listScopes(
    userId: string,
    cutoff: string,
    after: string | null,
    limit: number,
    signal: AbortSignal,
  ): Promise<unknown>
  drain(
    scope: ReevaluationPhotoDispositionScope,
    options: { timeoutMs: number; signal: AbortSignal },
  ): Promise<ReevaluationPhotoDispositionOutcome>
}

/** Coordinates backend proof. False defers this owner without losing durable progress.
 * No client creation, scheduler registration, logs or environment imports. */
export async function prepareReevaluationPhotoAccountPurge(
  deps: ReevaluationPhotoAccountPurgeDependencies,
  userId: string,
  cutoff: string,
  options: { timeoutMs?: number; maxScopes?: number } = {},
): Promise<boolean> {
  const input = inputSchema.safeParse({ userId, cutoff })
  const limits = z
    .object({
      timeoutMs: z.number().int().min(1).max(10000),
      maxScopes: z.number().int().min(1).max(100),
    })
    .safeParse({ timeoutMs: options.timeoutMs ?? 4500, maxScopes: options.maxScopes ?? 20 })
  if (!input.success || !limits.success) return false
  const current = input.data
  const configuration = limits.data
  const controller = new AbortController()
  const deadline = performance.now() + configuration.timeoutMs
  let stopped = false
  let timer: ReturnType<typeof setTimeout> | undefined
  function guard() {
    if (stopped || performance.now() >= deadline) throw new Error('recurring_purge_stopped')
  }
  async function purge() {
    guard()
    const value = await deps.purge(current.userId, current.cutoff, controller.signal)
    guard()
    if (typeof value !== 'boolean') throw new Error('invalid_recurring_purge_receipt')
    return value
  }
  async function work() {
    try {
      if (await purge()) return true
      let cursor: string | null = null
      let visited = 0
      while (visited < configuration.maxScopes) {
        guard()
        const limit = Math.min(20, configuration.maxScopes - visited)
        const page = pageSchema.parse(
          await deps.listScopes(current.userId, current.cutoff, cursor, limit, controller.signal),
        )
        guard()
        if (
          !page.eligible ||
          page.user_id !== current.userId ||
          page.items.length > limit ||
          page.cursor !== (page.items.at(-1)?.acceptance_id ?? null) ||
          (page.has_more && page.items.length !== limit) ||
          !page.items.every(
            (item, i) =>
              item.acceptance_id > (i ? (page.items[i - 1]?.acceptance_id ?? '') : (cursor ?? '')),
          )
        )
          return false
        for (const item of page.items) {
          guard()
          const outcome = await deps.drain(
            { userId: current.userId, cycleId: item.cycle_id, acceptanceId: item.acceptance_id },
            {
              timeoutMs: Math.max(1, Math.floor(deadline - performance.now())),
              signal: controller.signal,
            },
          )
          guard()
          if (outcome.state !== 'settled' && outcome.state !== 'waiting') return false
          visited += 1
        }
        if (!page.has_more) return await purge()
        cursor = page.cursor
      }
      return false
    } catch {
      return false
    }
  }
  const timeout = new Promise<false>((resolve) => {
    timer = setTimeout(() => {
      stopped = true
      controller.abort()
      resolve(false)
    }, configuration.timeoutMs)
  })
  try {
    return await Promise.race([work(), timeout])
  } finally {
    stopped = true
    controller.abort()
    if (timer !== undefined) clearTimeout(timer)
  }
}
