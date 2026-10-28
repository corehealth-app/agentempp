import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import type { CurrentClinicalSnapshot } from './current-clinical-state'

/** Original ACK is historical evidence. Current policy is never persisted in
 * its receipt, and an old welcome cannot revive a former/currently paused phase. */
export function presentCurrentOnboardingCompletion<T extends Record<string, unknown>>(
  data: T,
  current: CurrentClinicalSnapshot,
) {
  const policy = projectCurrentClinicalPublicPolicy(current)
  const origin = current.phase_origin
  const samePhase = origin.kind === 'assigned' && origin.phase === data.objective
  return {
    ...data,
    protocol_welcome:
      samePhase && !policy.pause_weight_loss_guidance && !policy.hide.objective
        ? (data.protocol_welcome ?? null)
        : null,
    clinical_policy: policy,
  }
}
