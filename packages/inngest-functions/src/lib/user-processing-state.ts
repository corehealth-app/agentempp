import type { ServiceClient } from '@mpp/db'
import { throwIfQueryFailed } from './query-error.js'

export type UserProcessingState =
  | { kind: 'active' }
  | { kind: 'paused'; until: string }
  | { kind: 'blocked' }
  | { kind: 'deleted' }

export async function loadUserProcessingState(
  supabase: ServiceClient,
  userId: string,
  now = new Date(),
): Promise<UserProcessingState> {
  const { data, error } = await supabase
    .from('users')
    .select('status, metadata')
    .eq('id', userId)
    .maybeSingle()
  throwIfQueryFailed(error, 'user processing state lookup failed')
  if (!data) throw new Error('user processing state not found')
  const user = data as {
    status: 'active' | 'blocked' | 'deleted'
    metadata: Record<string, unknown> | null
  }

  if (user.status === 'deleted') return { kind: 'deleted' }
  if (user.status === 'blocked') return { kind: 'blocked' }

  const pausedUntil = user.metadata?.paused_until
  if (pausedUntil != null) {
    if (typeof pausedUntil !== 'string' || !Number.isFinite(new Date(pausedUntil).getTime())) {
      throw new Error('invalid paused_until in user metadata')
    }
    if (new Date(pausedUntil).getTime() > now.getTime()) {
      return { kind: 'paused', until: pausedUntil }
    }
  }

  return { kind: 'active' }
}
