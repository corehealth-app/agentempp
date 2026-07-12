import type { ServiceClient } from '@mpp/db'

interface LossyCancellationRecoveryInput {
  userId: string
  pendingId: string
  subsetMealLogIds: string[]
  subsetKcalTotal: number
  proposalKcalTotal: number
  subsetMatchRatio: number
  resolvedAtAgeMs: number
}

/**
 * Reopens a cancelled pending without mutating nutrition rows. The subsequent
 * confirmation uses register_meal_atomic to replace logs and recompute the
 * snapshot in one transaction, so a failure cannot strand partial state.
 */
export async function reopenLossyCancellationPending(
  supabase: ServiceClient,
  input: LossyCancellationRecoveryInput,
): Promise<boolean> {
  const { data: reopened, error: reopenError } = await supabase
    .from('pending_registrations')
    .update({ status: 'pending', resolved_at: null })
    .eq('id', input.pendingId)
    .eq('status', 'cancelled')
    .select('id')
    .maybeSingle()

  if (reopenError) {
    throw new Error(reopenError.message ?? 'pending recovery CAS failed')
  }
  if (!reopened) return false

  const { error: eventError } = await supabase.from('product_events').insert({
    user_id: input.userId,
    event: 'pending.recovered_from_lossy_cancellation',
    properties: {
      pendingId: input.pendingId,
      subset_meal_log_ids: input.subsetMealLogIds,
      subset_kcal_total: input.subsetKcalTotal,
      proposal_kcal_total: input.proposalKcalTotal,
      subset_match_ratio: input.subsetMatchRatio,
      resolved_at_age_ms: input.resolvedAtAgeMs,
      deletion_deferred_to_atomic_register: true,
    },
  })
  if (eventError) {
    // Telemetry must not undo a successful state transition.
    console.warn('[lossy-cancellation-recovery] telemetry insert failed', eventError.message)
  }

  return true
}
