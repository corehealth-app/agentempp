import 'server-only'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { JourneyModerationError, type JourneyModerationRPCPort } from './service'
import { createJourneyModerationSession } from './session'

/** Server-only composition, distinct from the cached page/navigation guard. */
export async function loadJourneyModerationOperator() {
  if (process.env.MOBILE_JOURNEY_SOCIAL_ENABLED !== 'true')
    throw new JourneyModerationError('unavailable')
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!url) throw new JourneyModerationError('unavailable')
  const client = await createClient()
  return createJourneyModerationSession({
    enabled: () => process.env.MOBILE_JOURNEY_SOCIAL_ENABLED === 'true',
    expectedIssuer: `${url.replace(/\/$/u, '')}/auth/v1`,
    now: () => Math.floor(Date.now() / 1000),
    readCookieAccessToken: async () => {
      const result = await client.auth.getSession()
      return result.error ? null : (result.data.session?.access_token ?? null)
    },
    verifyAccessToken: async (token) => {
      const result = await client.auth.getUser(token)
      return result.error ? null : result.data.user ? { id: result.data.user.id } : null
    },
    readOperatorRole: async (id) => {
      const result = await client.from('admin_users').select('id,role').eq('id', id).maybeSingle()
      return result.error ? null : result.data
    },
    // Legacy generated DB types predate the additive social functions. The
    // narrow port is checked by closed input/output schemas and real SQL tests.
    createRPCPort: () => createServiceClient() as unknown as JourneyModerationRPCPort,
  })
}
