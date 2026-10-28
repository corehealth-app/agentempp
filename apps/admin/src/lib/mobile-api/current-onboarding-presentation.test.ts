import { describe, expect, it } from 'vitest'
import { captureCurrentClinicalState } from './current-clinical-state'
import { presentCurrentOnboardingCompletion } from './current-onboarding-presentation'
import { currentOnboardingIDs, currentOnboardingWire } from './testing/current-onboarding-fixture'

describe('historical signup acknowledgement under current presentation', () => {
  it('keeps the original ACK fields but removes its old welcome when current health pauses guidance', async () => {
    const wire = currentOnboardingWire('hold')
    const state = await captureCurrentClinicalState(
      { capture: async () => wire },
      { userId: currentOnboardingIDs.owner, mode: 'profile' },
    )
    const ack = {
      objective: 'recomposicao',
      completed_at: '2026-10-01T12:00:00Z',
      clinical_safety: { no_plan: false },
      protocol_welcome: { protocol: 'recomposicao', paragraphs: ['Old automatic advice'] },
    }
    const result = presentCurrentOnboardingCompletion(ack, state)
    expect(result.objective).toBe('recomposicao')
    expect(result.completed_at).toBe(ack.completed_at)
    expect(result.clinical_safety).toEqual(ack.clinical_safety)
    expect(result.protocol_welcome).toBeNull()
    expect(result.clinical_policy.pause_weight_loss_guidance).toBe(true)
    expect(ack.protocol_welcome).not.toBeNull()
  })
  it('does not present a historical phase welcome after the actual phase changes', async () => {
    const wire = currentOnboardingWire('healthy')
    wire.phase_origin = { kind: 'assigned', phase: 'manutencao' }
    const state = await captureCurrentClinicalState(
      { capture: async () => wire },
      { userId: currentOnboardingIDs.owner, mode: 'profile' },
    )
    const result = presentCurrentOnboardingCompletion(
      {
        objective: 'recomposicao',
        protocol_welcome: { protocol: 'recomposicao', paragraphs: ['Old'] },
      },
      state,
    )
    expect(result.protocol_welcome).toBeNull()
    expect(result.objective).toBe('recomposicao')
    for (const key of ['epoch', 'health_state', 'user_id', 'context_hash', 'calculation_config'])
      expect(result).not.toHaveProperty(key)
  })
})
