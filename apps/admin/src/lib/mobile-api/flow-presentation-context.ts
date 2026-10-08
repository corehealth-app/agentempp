/** Request-owned presentation authority. Never uses the protocol of a historical day. */
import type { FlowPresentationObjective } from '@mpp/agent/flow-public-metrics'
import { normalizeProtocol } from '@mpp/core'
import { MobileApiError } from './http'
import type { MobileRouteContext } from './route'

export async function loadFlowPresentationContext(
  context: MobileRouteContext,
): Promise<FlowPresentationObjective> {
  try {
    const { data, error } = await context.supabase
      .from('user_profiles')
      .select('current_protocol')
      .eq('user_id', context.auth.userId)
      .maybeSingle()
    if (error) throw new Error('objective lookup failed')
    return { currentProtocol: normalizeProtocol(data?.current_protocol) }
  } catch {
    // A failed read is not an absent profile; neither query detail nor raw reply is public.
    throw new MobileApiError(500, 'data_access_failed', 'Unable to read Flow presentation context')
  }
}
