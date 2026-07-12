import type { ServiceClient } from '@mpp/db'

export type PendingRegistrationStatus = 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled'

interface PendingStatusTransition {
  pendingId: string
  from: PendingRegistrationStatus
  to: PendingRegistrationStatus
  resolvedAt: string | null
}

export async function transitionPendingStatus(
  supabase: ServiceClient,
  transition: PendingStatusTransition,
): Promise<void> {
  const { data: updated, error } = await supabase
    .from('pending_registrations')
    .update({ status: transition.to, resolved_at: transition.resolvedAt })
    .eq('id', transition.pendingId)
    .eq('status', transition.from)
    .select('id')
    .maybeSingle()

  if (error) throw new Error(error.message ?? 'pending status transition failed')
  if (!updated) throw new Error('pending status transition lost race')
}
