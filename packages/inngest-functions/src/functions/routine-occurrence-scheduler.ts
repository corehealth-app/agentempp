import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'

const ROUTINE_SNOOZE_LOOKBACK_MINUTES = 15
const ROUTINE_SNOOZE_DISCOVERY_LIMIT = 500
const ROUTINE_SNOOZE_DISCOVERY_MAX_PAGES = 20
const ROUTINE_FINALIZER_LIMIT = 250
const ROUTINE_FINALIZER_MAX_PAGES = 20
const ROUTINE_EVENT_BATCH_SIZE = 100

const timestampSchema = z.string().datetime({ offset: true })
const dueRoutineSnoozeRowSchema = z
  .object({
    adherence_log_id: z.string().uuid(),
    snoozed_until: timestampSchema,
  })
  .strict()

const routineSnoozeClaimRowSchema = z
  .object({
    event_id: z.string().uuid(),
    status: z.enum(['queued', 'suppressed', 'resolved']),
    suppression_reason: z.string().min(1).nullable(),
    delivery_count: z.number().int().nonnegative(),
    existing: z.boolean(),
  })
  .strict()

const finalizerCursorRowSchema = z
  .object({
    scheduled_for: timestampSchema,
    user_id: z.string().uuid(),
    rule_id: z.string().uuid(),
  })
  .strict()

const finalizerResultRowSchema = z
  .object({
    processed_count: z.number().int().nonnegative(),
    finalized_count: z.number().int().nonnegative(),
    next_cursor: finalizerCursorRowSchema.nullable(),
  })
  .strict()

const routineSnoozeDueEventDataSchema = z
  .object({
    adherenceLogId: z.string().uuid(),
    snoozedUntil: timestampSchema,
  })
  .strict()

export interface DueRoutineSnoozeRow {
  adherence_log_id: string
  snoozed_until: string
}

export interface RoutineSnoozeCursor {
  snoozedUntil: string
  adherenceLogId: string
}

export interface RoutineFinalizerCursor {
  scheduledFor: string
  userId: string
  ruleId: string
}

export interface RoutineFinalizerResult {
  processedCount: number
  finalizedCount: number
  nextCursor: RoutineFinalizerCursor | null
}

export interface RoutineSnoozeClaimResult {
  eventId: string
  status: 'queued' | 'suppressed' | 'resolved'
  suppressionReason: string | null
  deliveryCount: number
  existing: boolean
}

export interface RoutineOccurrenceSchedulerRepository {
  listDueSnoozes(
    firedAt: string,
    lookbackMinutes: number,
    limit: number,
    cursor: RoutineSnoozeCursor | null,
  ): Promise<DueRoutineSnoozeRow[]>
  claimSnooze(adherenceLogId: string, claimedAt: string): Promise<RoutineSnoozeClaimResult>
  finalizeDue(
    now: string,
    limit: number,
    cursor: RoutineFinalizerCursor | null,
  ): Promise<RoutineFinalizerResult>
}

export interface RoutineSnoozeDueEventData {
  adherenceLogId: string
  snoozedUntil: string
}

export interface RoutineSnoozeDueEvent {
  id: string
  name: 'routine.snooze.due'
  data: RoutineSnoozeDueEventData
}

export interface EvaluatedRoutineSnoozeClaim {
  status: RoutineSnoozeClaimResult['status']
  suppressionReason: string | null
  deliveryCount: number
  existing: boolean
  providerSendAllowed: false
}

interface RoutineRpcClient {
  rpc(
    functionName: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: unknown }>
}

function parseTimestamp(value: string, label: string): number {
  const parsed = timestampSchema.safeParse(value)
  if (!parsed.success) throw new Error(`${label} is invalid`)
  return Date.parse(parsed.data)
}

function compareSnoozeTuple(left: RoutineSnoozeCursor, right: RoutineSnoozeCursor): number {
  const timestampDifference = Date.parse(left.snoozedUntil) - Date.parse(right.snoozedUntil)
  if (timestampDifference !== 0) return timestampDifference
  if (left.adherenceLogId < right.adherenceLogId) return -1
  if (left.adherenceLogId > right.adherenceLogId) return 1
  return 0
}

function compareFinalizerTuple(
  left: RoutineFinalizerCursor,
  right: RoutineFinalizerCursor,
): number {
  const timestampDifference = Date.parse(left.scheduledFor) - Date.parse(right.scheduledFor)
  if (timestampDifference !== 0) return timestampDifference
  if (left.userId < right.userId) return -1
  if (left.userId > right.userId) return 1
  if (left.ruleId < right.ruleId) return -1
  if (left.ruleId > right.ruleId) return 1
  return 0
}

export function buildRoutineSnoozeDueEvents(
  rows: DueRoutineSnoozeRow[],
  firedAt: string,
  lookbackMinutes = ROUTINE_SNOOZE_LOOKBACK_MINUTES,
): RoutineSnoozeDueEvent[] {
  if (!Number.isInteger(lookbackMinutes) || lookbackMinutes < 0 || lookbackMinutes > 15) {
    throw new Error('routine snooze lookback is invalid')
  }

  const firedAtMs = parseTimestamp(firedAt, 'routine scheduler fired_at')
  const firedAtMinuteMs = Math.floor(firedAtMs / 60_000) * 60_000
  const earliestMs = firedAtMinuteMs - lookbackMinutes * 60_000
  const events = new Map<string, RoutineSnoozeDueEvent>()

  for (const rawRow of rows) {
    const row = dueRoutineSnoozeRowSchema.parse(rawRow)
    const snoozedUntilMs = Date.parse(row.snoozed_until)
    if (snoozedUntilMs < earliestMs || snoozedUntilMs > firedAtMinuteMs) {
      throw new Error('due routine snooze is outside the scheduler window')
    }

    const snoozedUntil = new Date(snoozedUntilMs).toISOString()
    const existing = events.get(row.adherence_log_id)
    if (existing && existing.data.snoozedUntil !== snoozedUntil) {
      throw new Error('routine snooze action has conflicting due timestamps')
    }

    events.set(row.adherence_log_id, {
      id: `bodyflow-routine-snooze:${row.adherence_log_id}:${snoozedUntil}`,
      name: 'routine.snooze.due',
      data: {
        adherenceLogId: row.adherence_log_id,
        snoozedUntil,
      },
    })
  }

  return [...events.values()]
}

export async function discoverRoutineSnoozeDueEvents(
  repository: RoutineOccurrenceSchedulerRepository,
  firedAt: string,
  lookbackMinutes = ROUTINE_SNOOZE_LOOKBACK_MINUTES,
  pageLimit = ROUTINE_SNOOZE_DISCOVERY_LIMIT,
  maxPages = ROUTINE_SNOOZE_DISCOVERY_MAX_PAGES,
): Promise<RoutineSnoozeDueEvent[]> {
  if (!Number.isInteger(pageLimit) || pageLimit < 1 || pageLimit > 5000) {
    throw new Error('routine snooze discovery page limit is invalid')
  }
  if (!Number.isInteger(maxPages) || maxPages < 1 || maxPages > 100) {
    throw new Error('routine snooze discovery page count is invalid')
  }

  const allRows: DueRoutineSnoozeRow[] = []
  let cursor: RoutineSnoozeCursor | null = null

  for (let page = 0; page < maxPages; page += 1) {
    const rows = await repository.listDueSnoozes(firedAt, lookbackMinutes, pageLimit, cursor)
    if (rows.length > pageLimit) throw new Error('due routine snooze page exceeded its limit')

    let previous: RoutineSnoozeCursor | null = cursor
    for (const rawRow of rows) {
      const row = dueRoutineSnoozeRowSchema.parse(rawRow)
      const next = {
        snoozedUntil: new Date(row.snoozed_until).toISOString(),
        adherenceLogId: row.adherence_log_id,
      }
      if (previous && compareSnoozeTuple(next, previous) <= 0) {
        throw new Error('due routine snooze page did not advance its cursor')
      }
      allRows.push({
        adherence_log_id: next.adherenceLogId,
        snoozed_until: next.snoozedUntil,
      })
      previous = next
    }

    if (rows.length < pageLimit) {
      return buildRoutineSnoozeDueEvents(allRows, firedAt, lookbackMinutes)
    }
    if (!previous) throw new Error('full due routine snooze page has no cursor')
    cursor = previous
  }

  throw new Error('routine snooze pagination limit exceeded')
}

export async function finalizeRoutineOccurrences(
  repository: RoutineOccurrenceSchedulerRepository,
  now: string,
  pageLimit = ROUTINE_FINALIZER_LIMIT,
  maxPages = ROUTINE_FINALIZER_MAX_PAGES,
): Promise<{ processedCount: number; finalizedCount: number; pages: number }> {
  timestampSchema.parse(now)
  if (!Number.isInteger(pageLimit) || pageLimit < 1 || pageLimit > 5000) {
    throw new Error('routine finalizer page limit is invalid')
  }
  if (!Number.isInteger(maxPages) || maxPages < 1 || maxPages > 100) {
    throw new Error('routine finalizer page count is invalid')
  }

  let cursor: RoutineFinalizerCursor | null = null
  let processedCount = 0
  let finalizedCount = 0

  for (let page = 0; page < maxPages; page += 1) {
    const result = await repository.finalizeDue(now, pageLimit, cursor)
    if (result.processedCount > pageLimit) {
      throw new Error('routine finalizer page exceeded its limit')
    }
    if (result.finalizedCount > result.processedCount) {
      throw new Error('routine finalizer reported an invalid count')
    }

    processedCount += result.processedCount
    finalizedCount += result.finalizedCount

    if (!result.nextCursor) {
      return { processedCount, finalizedCount, pages: page + 1 }
    }
    if (cursor && compareFinalizerTuple(result.nextCursor, cursor) <= 0) {
      throw new Error('routine finalizer did not advance its cursor')
    }
    if (result.processedCount === 0) {
      throw new Error('routine finalizer returned a cursor without processing a row')
    }
    cursor = result.nextCursor
  }

  throw new Error('routine finalizer pagination limit exceeded')
}

function evaluateRoutineSnoozeClaim(result: RoutineSnoozeClaimResult): EvaluatedRoutineSnoozeClaim {
  if (result.status === 'queued') {
    if (result.deliveryCount < 1) throw new Error('queued routine snooze has no delivery')
    if (result.suppressionReason !== null) {
      throw new Error('queued routine snooze has a suppression reason')
    }
  } else {
    if (result.deliveryCount !== 0) throw new Error('non-queued routine snooze has a delivery')
    if (result.status === 'suppressed' && !result.suppressionReason) {
      throw new Error('suppressed routine snooze has no reason')
    }
  }

  return {
    status: result.status,
    suppressionReason: result.suppressionReason,
    deliveryCount: result.deliveryCount,
    existing: result.existing,
    providerSendAllowed: false,
  }
}

export async function claimRoutineSnooze(
  repository: RoutineOccurrenceSchedulerRepository,
  event: RoutineSnoozeDueEventData,
  claimedAt: string,
): Promise<EvaluatedRoutineSnoozeClaim> {
  const validEvent = routineSnoozeDueEventDataSchema.parse(event)
  const validClaimedAt = timestampSchema.parse(claimedAt)
  const result = await repository.claimSnooze(validEvent.adherenceLogId, validClaimedAt)
  return evaluateRoutineSnoozeClaim(result)
}

export function createRoutineOccurrenceSchedulerRepository(
  supabase: ServiceClient,
): RoutineOccurrenceSchedulerRepository {
  const routineRpc = supabase as unknown as RoutineRpcClient

  return {
    async listDueSnoozes(firedAt, lookbackMinutes, limit, cursor) {
      const { data, error } = await routineRpc.rpc('list_due_routine_snoozes', {
        p_fired_at: firedAt,
        p_lookback_minutes: lookbackMinutes,
        p_limit: limit,
        ...(cursor
          ? {
              p_after_snoozed_until: cursor.snoozedUntil,
              p_after_log_id: cursor.adherenceLogId,
            }
          : {}),
      })
      if (error) throw new Error('due routine snooze lookup failed')
      return z.array(dueRoutineSnoozeRowSchema).parse(data ?? [])
    },
    async claimSnooze(adherenceLogId, claimedAt) {
      const { data, error } = await routineRpc.rpc('claim_routine_snooze_event', {
        p_adherence_log_id: adherenceLogId,
        p_claimed_at: claimedAt,
      })
      if (error) throw new Error('routine snooze claim failed')
      const claim = routineSnoozeClaimRowSchema.parse(data)
      return {
        eventId: claim.event_id,
        status: claim.status,
        suppressionReason: claim.suppression_reason,
        deliveryCount: claim.delivery_count,
        existing: claim.existing,
      }
    },
    async finalizeDue(now, limit, cursor) {
      const { data, error } = await routineRpc.rpc('finalize_due_routine_occurrences', {
        p_now: now,
        p_limit: limit,
        ...(cursor
          ? {
              p_after_scheduled_for: cursor.scheduledFor,
              p_after_user_id: cursor.userId,
              p_after_rule_id: cursor.ruleId,
            }
          : {}),
      })
      if (error) throw new Error('routine occurrence finalization failed')
      const result = finalizerResultRowSchema.parse(data)
      return {
        processedCount: result.processed_count,
        finalizedCount: result.finalized_count,
        nextCursor: result.next_cursor
          ? {
              scheduledFor: new Date(result.next_cursor.scheduled_for).toISOString(),
              userId: result.next_cursor.user_id,
              ruleId: result.next_cursor.rule_id,
            }
          : null,
      }
    },
  }
}

function chunkEvents(events: RoutineSnoozeDueEvent[]): RoutineSnoozeDueEvent[][] {
  const chunks: RoutineSnoozeDueEvent[][] = []
  for (let offset = 0; offset < events.length; offset += ROUTINE_EVENT_BATCH_SIZE) {
    chunks.push(events.slice(offset, offset + ROUTINE_EVENT_BATCH_SIZE))
  }
  return chunks
}

export const routineOccurrenceSchedulerFn = inngest.createFunction(
  { id: 'bodyflow-routine-occurrence-scheduler', retries: 3, concurrency: { limit: 1 } },
  { cron: '* * * * *' },
  async ({ event, step, logger }) => {
    if (event.ts === undefined) throw new Error('cron event timestamp is missing')
    const firedAt = new Date(event.ts).toISOString()

    const events = await step.run('list-due-routine-snoozes', async () => {
      const repository = createRoutineOccurrenceSchedulerRepository(createWorkerSupabase())
      return discoverRoutineSnoozeDueEvents(
        repository,
        firedAt,
        ROUTINE_SNOOZE_LOOKBACK_MINUTES,
        ROUTINE_SNOOZE_DISCOVERY_LIMIT,
        ROUTINE_SNOOZE_DISCOVERY_MAX_PAGES,
      )
    })

    const finalized = await step.run('finalize-due-routine-occurrences', async () => {
      const repository = createRoutineOccurrenceSchedulerRepository(createWorkerSupabase())
      return finalizeRoutineOccurrences(
        repository,
        firedAt,
        ROUTINE_FINALIZER_LIMIT,
        ROUTINE_FINALIZER_MAX_PAGES,
      )
    })

    for (const [index, batch] of chunkEvents(events).entries()) {
      await step.sendEvent(`emit-due-routine-snoozes-${index}`, batch)
    }

    logger.info('routine occurrence scheduler completed', {
      dueCount: events.length,
      processedCount: finalized.processedCount,
      finalizedCount: finalized.finalizedCount,
    })
    return {
      dueCount: events.length,
      processedCount: finalized.processedCount,
      finalizedCount: finalized.finalizedCount,
    }
  },
)

export const routineSnoozeClaimFn = inngest.createFunction(
  {
    id: 'bodyflow-routine-snooze-claim',
    retries: 3,
    concurrency: { key: 'event.data.adherenceLogId', limit: 1 },
  },
  { event: 'routine.snooze.due' },
  async ({ event, step, logger }) => {
    const result = await step.run('claim-routine-snooze-event', async () => {
      const repository = createRoutineOccurrenceSchedulerRepository(createWorkerSupabase())
      return claimRoutineSnooze(repository, event.data, new Date().toISOString())
    })

    logger.info('routine snooze claim recorded', {
      status: result.status,
      suppressionReason: result.suppressionReason,
      deliveryCount: result.deliveryCount,
      existing: result.existing,
    })
    return result
  },
)
