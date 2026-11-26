import { createHash } from 'node:crypto'
import { getGapForDate, getLocalDateString, getLocalHour, getPersonalMealWindows } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { createFlowMealGapPush } from '../lib/flow-meal-gap-apns.js'
import { type FlowMealGapFacts, selectFlowMealGap } from '../lib/flow-meal-gap-policy.js'

const instant = z.string().datetime({ offset: true })
const activity = z.object({
  blocked: z.boolean(),
  last_intake_at: instant.nullable(),
  accepted: z.array(
    z.object({
      mode: z.enum(['daytime', 'before_close']),
      meal: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia']),
      at: instant,
    }),
  ),
})
const claim = z.object({
  id: z.string().uuid(),
  claim_id: z.string().uuid(),
  token: z.string(),
  environment: z.enum(['sandbox', 'production']),
  expires_at: instant,
})
const targets = z
  .array(
    z.object({
      user_id: z.string().uuid(),
      device_id: z.string().uuid(),
      timezone: z.string(),
      locale: z.string().nullable(),
      daytime_enabled: z.boolean(),
      daily_limit: z.number().int().min(1).max(20),
    }),
  )
  .max(16)
type Target = z.infer<typeof targets>[number]
type SendPush = ReturnType<typeof createFlowMealGapPush>

// Only the new RPCs use the narrow gateway until generated types are refreshed.
// Tokens and personal facts stay inside the step, never in its log or result.
function gapRpc(db: ServiceClient) {
  return async (name: string, params: Record<string, unknown>) => {
    const { data, error } = await (
      db as unknown as {
        rpc: (
          name: string,
          params: Record<string, unknown>,
        ) => Promise<{ data: unknown; error: unknown }>
      }
    ).rpc(name, params)
    if (error) throw new Error('Flow reminder data unavailable')
    return data
  }
}

async function deliverToTarget(
  db: ServiceClient,
  target: Target,
  topic: string,
  send: SendPush,
  instant: Date,
) {
  const localHour = getLocalHour(target.timezone, instant)
  const daytime = localHour >= 10 && localHour < 20
  const beforeClose = localHour >= 21 && localHour < 24
  if ((!daytime && !beforeClose) || (daytime && !target.daytime_enabled)) return false
  const localDate = getLocalDateString(target.timezone, instant)
  const rpc = gapRpc(db)
  const raw = await rpc('read_flow_meal_gap_activity', {
    p_user_id: target.user_id,
    p_date: localDate,
  })
  if (raw === null) return false
  const current = activity.parse(raw)
  if (current.blocked) return false

  const gapPromise = getGapForDate(db, target.user_id, target.timezone, localDate)
  const windowsPromise = getPersonalMealWindows(db, target.user_id, target.timezone, instant, {
    excludeAtOrAfterReference: true,
  })
  const dateSnapshot = db
    .from('daily_snapshots')
    .select('protein_g, protein_target, day_closed')
    .eq('user_id', target.user_id)
    .eq('date', localDate)
    .maybeSingle()
  const lastMeal = db
    .from('meal_logs')
    .select('created_at')
    .eq('user_id', target.user_id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  const [gap, windows, snapshot, last] = await Promise.all([
    gapPromise,
    windowsPromise,
    dateSnapshot,
    lastMeal,
  ])
  if (snapshot.error || last.error) throw new Error('Flow reminder diary unavailable')
  const personalEndHours: FlowMealGapFacts['personalEndHours'] = {}
  for (const window of windows.windows.values()) personalEndHours[window.meal_type] = window.p90

  const decision = selectFlowMealGap({
    now: instant.getTime(),
    localHour,
    optedIn: true,
    daytimeEnabled: target.daytime_enabled,
    dayClosed: snapshot.data?.day_closed === true,
    patternReliable: !gap.pattern.fallbackUsed,
    expected: gap.pattern.expected,
    registered: gap.registered,
    skipped: gap.skipped,
    personalEndHours,
    dayProteinGrams: snapshot.data?.protein_g ?? null,
    dayProteinTargetGrams: snapshot.data?.protein_target ?? null,
    lastMealLoggedAt: last.data?.created_at ? Date.parse(last.data.created_at) : null,
    lastIntakeAt: current.last_intake_at ? Date.parse(current.last_intake_at) : null,
    intakeProcessing: current.blocked,
    dailyLimit: target.daily_limit,
    priorNotices: current.accepted.map((sent) => ({ ...sent, at: Date.parse(sent.at) })),
  })
  if (!decision) return false

  const leased = await rpc('claim_flow_meal_gap_notice', {
    p_user_id: target.user_id,
    p_device_id: target.device_id,
    p_topic: topic,
    p_date: localDate,
    p_mode: decision.mode,
    p_meal: decision.meal,
  })
  if (leased === null) return false
  const notice = claim.parse(leased)
  const outcome = await send({
    environment: notice.environment,
    token: notice.token,
    id: notice.id,
    ownerKey: createHash('sha256').update(target.user_id).digest('hex').slice(0, 8),
    language: target.locale === 'en-US' ? 'en-US' : 'pt-BR',
    expiresAt: Date.parse(notice.expires_at),
  })
  const finished = await rpc('finish_flow_meal_gap_notice', {
    p_id: notice.id,
    p_claim_id: notice.claim_id,
    p_outcome: outcome,
  })
  if (finished !== true) throw new Error('Flow reminder delivery lease changed')
  return outcome === 'accepted'
}

export const flowMealGapPushFn = inngest.createFunction(
  { id: 'performe-flow-meal-gap-push', retries: 1, concurrency: { limit: 1 } },
  { cron: '0 * * * *' },
  async ({ step, logger }) => {
    assertClinicalStagingWorkerTarget(process.env, 'media-conversation-staging')
    if (process.env.MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED !== 'true') return { accepted: 0 }
    const topic = process.env.MOBILE_FLOW_APNS_TOPIC
    const privateKey = process.env.MOBILE_FLOW_APNS_PRIVATE_KEY
    const teamId = process.env.MOBILE_FLOW_APNS_TEAM_ID
    const keyId = process.env.MOBILE_FLOW_APNS_KEY_ID
    if (!topic || !privateKey || !teamId || !keyId) throw new Error('Flow push is not configured')
    const send = createFlowMealGapPush({ topic, privateKey, teamId, keyId })
    let after: string | null = null
    let accepted = 0
    let failed = 0
    for (let batch = 0; batch < 20; batch++) {
      const result: { fetched: number; after: string | null; accepted: number; failed: number } =
        await step.run(`flow-meal-gap-batch-${batch}`, async () => {
          const db = createWorkerSupabase()
          const rpc = gapRpc(db)
          const page = targets.parse(
            await rpc('list_flow_meal_gap_targets', {
              p_topic: topic,
              p_after: after,
              p_limit: 16,
            }),
          )
          let accepted = 0
          let failed = 0
          for (let index = 0; index < page.length; index += 4) {
            const now = new Date()
            const results = await Promise.allSettled(
              page
                .slice(index, index + 4)
                .map((target) => deliverToTarget(db, target, topic, send, now)),
            )
            accepted += results.filter((r) => r.status === 'fulfilled' && r.value).length
            failed += results.filter((r) => r.status === 'rejected').length
          }
          return { fetched: page.length, after: page.at(-1)?.user_id ?? null, accepted, failed }
        })
      accepted += result.accepted
      failed += result.failed
      if (!result.after || result.fetched < 16) break
      if (after === result.after) throw new Error('Flow reminder batch did not advance')
      after = result.after
      if (batch === 19) throw new Error('Flow reminder batch limit exceeded')
    }
    logger.info('flow meal reminder tick', { accepted, failed })
    return { accepted, failed }
  },
)
