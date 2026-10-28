import type { FlowClinicalDraftKey } from '@mpp/agent'
import { vi } from 'vitest'
import { projectCurrentClinicalState, readCurrentClinicalState } from '../current-clinical-state'
import type {
  CurrentFlowDraftAuthority,
  CurrentFlowDraftWrite,
} from '../current-flow-draft-authority'
import type { currentOnboardingWire } from './current-onboarding-fixture'
import { consentAuth, uid } from './reevaluation-photo-consent-fixture'

export function currentFlowDraftFixture(state: ReturnType<typeof currentOnboardingWire>) {
  const day = {
    snapshot_id: uid(6900),
    date: state.date,
    calories_target: 1800,
    protein_target: 140,
    current_protocol: 'recomposicao',
    target_revision: '0',
    calorie_origin: null,
  }
  const authority = {
    capture: vi.fn(async () => {
      const policy = projectCurrentClinicalState(
          readCurrentClinicalState(structuredClone(state), consentAuth.userId),
        ),
        training = !policy.hide.objective
      return {
        version: 1,
        state: structuredClone(state),
        day: structuredClone(day),
        allowed: {
          training,
          nutrition:
            training &&
            !policy.pauseWeightLossGuidance &&
            !policy.hide.calories &&
            !policy.hide.protein &&
            day.calories_target > 0 &&
            day.protein_target > 0,
        },
      }
    }),
    findTurn: vi.fn(async (_input: Readonly<FlowClinicalDraftKey>) => uid(6901)),
    lookup: vi.fn<CurrentFlowDraftAuthority['lookup']>(async (_input) => null),
    create: vi.fn(async (input: Readonly<CurrentFlowDraftWrite>) => ({
      id: uid(6902),
      status: input.status,
      payload: structuredClone(input.payload),
      inserted: true,
    })),
  }
  return { authority, day }
}
