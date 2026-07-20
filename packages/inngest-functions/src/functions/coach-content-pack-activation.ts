import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'

const timestampSchema = z.string().datetime({ offset: true })

const activationRpcResultSchema = z.discriminatedUnion('outcome', [
  z.object({ outcome: z.literal('no_due_pack') }).strict(),
  z
    .object({
      outcome: z.literal('activated'),
      pack_id: z.string().uuid(),
      previous_pack_id: z.string().uuid().nullable(),
      entry_count: z.literal(1080),
      activated_at: timestampSchema,
    })
    .strict(),
  z
    .object({
      outcome: z.literal('already_active'),
      pack_id: z.string().uuid(),
      activated_at: timestampSchema,
    })
    .strict(),
])

export type CoachContentPackActivationResult =
  | { outcome: 'no_due_pack' }
  | {
      outcome: 'activated'
      packId: string
      previousPackId: string | null
      entryCount: 1080
      activatedAt: string
    }
  | { outcome: 'already_active'; packId: string; activatedAt: string }

export interface CoachContentPackActivationDependencies {
  repository: {
    activateDue(now: string): Promise<CoachContentPackActivationResult>
  }
}

export async function activateDueCoachContentPack(
  dependencies: CoachContentPackActivationDependencies,
  now = new Date(),
): Promise<CoachContentPackActivationResult> {
  if (Number.isNaN(now.getTime())) throw new Error('coach content pack activation time is invalid')
  return dependencies.repository.activateDue(now.toISOString())
}

export function createCoachContentPackActivationRepository(
  supabase: ServiceClient,
): CoachContentPackActivationDependencies['repository'] {
  return {
    async activateDue(now) {
      const { data, error } = await supabase.rpc('activate_due_coach_content_pack', {
        p_now: now,
      })
      if (error || !data) throw new Error('coach content pack activation failed')

      const parsed = activationRpcResultSchema.safeParse(data)
      if (!parsed.success) throw new Error('coach content pack activation failed')
      if (parsed.data.outcome === 'no_due_pack') return { outcome: 'no_due_pack' }
      if (parsed.data.outcome === 'already_active') {
        return {
          outcome: 'already_active',
          packId: parsed.data.pack_id,
          activatedAt: parsed.data.activated_at,
        }
      }
      return {
        outcome: 'activated',
        packId: parsed.data.pack_id,
        previousPackId: parsed.data.previous_pack_id,
        entryCount: parsed.data.entry_count,
        activatedAt: parsed.data.activated_at,
      }
    },
  }
}

export const coachContentPackActivationFn = inngest.createFunction(
  {
    id: 'bodyflow-coach-content-pack-activation',
    retries: 2,
    concurrency: { limit: 1 },
  },
  { cron: '13 * * * *' },
  async ({ event, step, logger }) => {
    if (event.ts === undefined) throw new Error('cron event timestamp is missing')
    const now = new Date(event.ts)
    const result = await step.run('activate-due-approved-coach-pack', async () => {
      const repository = createCoachContentPackActivationRepository(createWorkerSupabase())
      return activateDueCoachContentPack({ repository }, now)
    })

    logger.info('coach content pack activation checked', {
      outcome: result.outcome,
      entryCount: result.outcome === 'activated' ? result.entryCount : 0,
    })
    return result
  },
)
