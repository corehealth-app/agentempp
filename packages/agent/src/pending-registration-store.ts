import type { Json, ServiceClient } from '@mpp/db'
import { throwIfQueryFailed } from './db-query-error.js'

export type PendingMealRow = {
  id: string
  proposal: Json | null
  created_at: string
}

export type EditedPendingMealRow = {
  id: string
  proposal: Json | null
  resolved_at: string | null
}

export async function loadRecentPendingMeal(
  supabase: ServiceClient,
  userId: string,
  now: Date = new Date(),
): Promise<PendingMealRow | null> {
  const lookback = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, created_at')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .eq('proposal->>kind', 'meal')
    .gte('created_at', lookback)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  throwIfQueryFailed(error, 'recent pending meal lookup failed')
  return (data as PendingMealRow | null) ?? null
}

export async function loadRecentEditedMealPending(
  supabase: ServiceClient,
  userId: string,
  mealType: string,
  now: Date = new Date(),
): Promise<EditedPendingMealRow | null> {
  const lookback = new Date(now.getTime() - 30 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, resolved_at')
    .eq('user_id', userId)
    .eq('status', 'edited')
    .eq('proposal->>kind', 'meal')
    .eq('proposal->>mealType', mealType)
    .gte('resolved_at', lookback)
    .order('resolved_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  throwIfQueryFailed(error, 'recent edited pending meal lookup failed')
  return (data as EditedPendingMealRow | null) ?? null
}

export async function cancelOpenPendingRegistrations(
  supabase: ServiceClient,
  userId: string,
  resolvedAt: Date = new Date(),
): Promise<void> {
  const { error } = await supabase
    .from('pending_registrations')
    .update({ status: 'cancelled', resolved_at: resolvedAt.toISOString() })
    .eq('user_id', userId)
    .eq('status', 'pending')

  throwIfQueryFailed(error, 'open pending cancellation failed')
}

export async function createPendingRegistration(
  supabase: ServiceClient,
  input: {
    userId: string
    proposal: Json
    expiresAt: string
    requestKey?: string | null
  },
): Promise<string> {
  const { data, error } = await (
    supabase as unknown as {
      rpc: (
        name: string,
        params: Record<string, unknown>,
      ) => Promise<{ data: unknown; error: unknown }>
    }
  ).rpc('replace_pending_registration_atomic', {
    p_user_id: input.userId,
    p_proposal: input.proposal,
    p_expires_at: input.expiresAt,
    p_request_key: input.requestKey ?? null,
  })

  throwIfQueryFailed(error, 'pending registration transaction failed')
  const pendingId = (data as { pending_id?: string } | null)?.pending_id
  if (!pendingId) throw new Error('pending registration insert returned no id')
  return pendingId
}
