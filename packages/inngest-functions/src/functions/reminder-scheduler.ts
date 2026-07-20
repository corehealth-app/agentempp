import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'

const REMINDER_LOOKBACK_MINUTES = 5
const REMINDER_DISCOVERY_LIMIT = 500
const REMINDER_EVENT_BATCH_SIZE = 100

const timestampSchema = z.string().datetime({ offset: true })
const dueReminderRowSchema = z
  .object({
    reminder_rule_id: z.string().uuid(),
    scheduled_for: timestampSchema,
  })
  .strict()

const reminderClaimRowSchema = z
  .object({
    event_id: z.string().uuid(),
    status: z.enum(['queued', 'suppressed', 'resolved']),
    suppression_reason: z.string().min(1).nullable(),
    delivery_count: z.number().int().nonnegative(),
    existing: z.boolean(),
  })
  .strict()

export interface DueReminderRow {
  reminder_rule_id: string
  scheduled_for: string
}

export interface ReminderClaimResult {
  eventId: string
  status: 'queued' | 'suppressed' | 'resolved'
  suppressionReason: string | null
  deliveryCount: number
  existing: boolean
}

export interface ReminderSchedulerRepository {
  listDue(firedAt: string, lookbackMinutes: number, limit: number): Promise<DueReminderRow[]>
  claim(
    reminderRuleId: string,
    scheduledFor: string,
    claimedAt: string,
  ): Promise<ReminderClaimResult>
}

export interface ReminderDueEventData {
  reminderRuleId: string
  scheduledFor: string
}

export interface ReminderDueEvent {
  id: string
  name: 'reminder.rule.due'
  data: ReminderDueEventData
}

export interface EvaluatedReminderClaim {
  status: ReminderClaimResult['status']
  suppressionReason: string | null
  deliveryCount: number
  existing: boolean
  providerSendAllowed: false
}

function parseTimestamp(value: string, label: string): number {
  const parsed = timestampSchema.safeParse(value)
  if (!parsed.success) throw new Error(`${label} is invalid`)
  return Date.parse(parsed.data)
}

export function buildReminderDueEvents(
  rows: DueReminderRow[],
  firedAt: string,
  lookbackMinutes = REMINDER_LOOKBACK_MINUTES,
): ReminderDueEvent[] {
  if (!Number.isInteger(lookbackMinutes) || lookbackMinutes < 0 || lookbackMinutes > 15) {
    throw new Error('reminder lookback is invalid')
  }

  const firedAtMs = parseTimestamp(firedAt, 'scheduler fired_at')
  const firedAtMinuteMs = Math.floor(firedAtMs / 60_000) * 60_000
  const earliestMs = firedAtMinuteMs - lookbackMinutes * 60_000
  const events = new Map<string, ReminderDueEvent>()

  for (const rawRow of rows) {
    const row = dueReminderRowSchema.parse(rawRow)
    const scheduledForMs = Date.parse(row.scheduled_for)
    if (scheduledForMs < earliestMs || scheduledForMs > firedAtMinuteMs) {
      throw new Error('due reminder is outside the scheduler window')
    }

    const scheduledFor = new Date(scheduledForMs).toISOString()
    const id = `bodyflow-reminder:${row.reminder_rule_id}:${scheduledFor}`
    events.set(id, {
      id,
      name: 'reminder.rule.due',
      data: {
        reminderRuleId: row.reminder_rule_id,
        scheduledFor,
      },
    })
  }

  return [...events.values()]
}

export function evaluateReminderClaim(result: ReminderClaimResult): EvaluatedReminderClaim {
  if (result.status === 'queued') {
    if (result.deliveryCount < 1) throw new Error('queued reminder has no delivery')
    if (result.suppressionReason !== null) {
      throw new Error('queued reminder has a suppression reason')
    }
  } else {
    if (result.deliveryCount !== 0) throw new Error('non-queued reminder has a delivery')
    if (result.status === 'suppressed' && !result.suppressionReason) {
      throw new Error('suppressed reminder has no reason')
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

export async function claimDueReminder(
  repository: ReminderSchedulerRepository,
  event: ReminderDueEventData,
  claimedAt: string,
): Promise<EvaluatedReminderClaim> {
  const reminderRuleId = z.string().uuid().parse(event.reminderRuleId)
  const scheduledFor = timestampSchema.parse(event.scheduledFor)
  const validClaimedAt = timestampSchema.parse(claimedAt)
  const claim = await repository.claim(reminderRuleId, scheduledFor, validClaimedAt)
  return evaluateReminderClaim(claim)
}

export function createReminderSchedulerRepository(
  supabase: ServiceClient,
): ReminderSchedulerRepository {
  return {
    async listDue(firedAt, lookbackMinutes, limit) {
      const { data, error } = await supabase.rpc('list_due_reminder_rules', {
        p_fired_at: firedAt,
        p_lookback_minutes: lookbackMinutes,
        p_limit: limit,
      })
      if (error) throw new Error('due reminder lookup failed')
      return z.array(dueReminderRowSchema).parse(data ?? [])
    },
    async claim(reminderRuleId, scheduledFor, claimedAt) {
      const { data, error } = await supabase.rpc('claim_reminder_event', {
        p_reminder_rule_id: reminderRuleId,
        p_scheduled_for: scheduledFor,
        p_claimed_at: claimedAt,
      })
      if (error) throw new Error('reminder claim failed')
      const claim = reminderClaimRowSchema.parse(data)
      return {
        eventId: claim.event_id,
        status: claim.status,
        suppressionReason: claim.suppression_reason,
        deliveryCount: claim.delivery_count,
        existing: claim.existing,
      }
    },
  }
}

function chunkEvents(events: ReminderDueEvent[]): ReminderDueEvent[][] {
  const chunks: ReminderDueEvent[][] = []
  for (let offset = 0; offset < events.length; offset += REMINDER_EVENT_BATCH_SIZE) {
    chunks.push(events.slice(offset, offset + REMINDER_EVENT_BATCH_SIZE))
  }
  return chunks
}

export const reminderSchedulerFn = inngest.createFunction(
  { id: 'bodyflow-reminder-scheduler', retries: 3, concurrency: { limit: 1 } },
  { cron: '* * * * *' },
  async ({ event, step, logger }) => {
    if (event.ts === undefined) throw new Error('cron event timestamp is missing')
    const firedAt = new Date(event.ts).toISOString()
    const rows = await step.run('list-due-reminder-rules', async () => {
      const repository = createReminderSchedulerRepository(createWorkerSupabase())
      return repository.listDue(firedAt, REMINDER_LOOKBACK_MINUTES, REMINDER_DISCOVERY_LIMIT)
    })
    const events = buildReminderDueEvents(rows, firedAt)

    for (const [index, batch] of chunkEvents(events).entries()) {
      await step.sendEvent(`emit-due-reminders-${index}`, batch)
    }

    logger.info('reminder scheduler completed', { dueCount: events.length })
    return { dueCount: events.length }
  },
)

export const reminderClaimFn = inngest.createFunction(
  {
    id: 'bodyflow-reminder-claim',
    retries: 3,
    concurrency: { key: 'event.data.reminderRuleId', limit: 1 },
  },
  { event: 'reminder.rule.due' },
  async ({ event, step, logger }) => {
    const result = await step.run('claim-reminder-event', async () => {
      const repository = createReminderSchedulerRepository(createWorkerSupabase())
      return claimDueReminder(repository, event.data, new Date().toISOString())
    })

    logger.info('reminder claim recorded', {
      status: result.status,
      suppressionReason: result.suppressionReason,
      deliveryCount: result.deliveryCount,
      existing: result.existing,
    })
    return result
  },
)
