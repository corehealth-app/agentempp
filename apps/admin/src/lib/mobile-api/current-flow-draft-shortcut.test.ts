import { describe, expect, it, vi } from 'vitest'
import { createCurrentFlowDraftLookup } from './current-flow-draft-shortcut'
import { currentFlowDraftFixture } from './testing/current-flow-draft-fixture'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

function setup(kind: 'healthy' | 'no_plan' = 'healthy') {
  const fixture = currentFlowDraftFixture(currentOnboardingWire(kind))
  fixture.authority.lookup.mockResolvedValue({
    id: uid(6902),
    status: 'ready_for_review',
    payload: { notes: 'private plan' },
  })
  const candidates = {
    findForTurn: vi.fn(async () => ({
      id: uid(6902),
      domain: 'nutrition' as const,
    })),
  }
  return {
    ...fixture,
    candidates,
    lookup: createCurrentFlowDraftLookup(consentAuth.userId, fixture.authority, candidates),
  }
}
describe('current Flow draft lookup composition', () => {
  it('certifies the exact original turn and returns metadata only', async () => {
    const s = setup(),
      turn = `mobile_flow/${consentAuth.userId}/original-key`
    expect(await s.lookup.findForTurn(consentAuth.userId, turn)).toEqual({
      id: uid(6902),
      domain: 'nutrition',
    })
    expect(s.candidates.findForTurn).toHaveBeenCalledWith(consentAuth.userId, turn)
    expect(s.authority.lookup).toHaveBeenCalledWith(
      expect.objectContaining({
        domain: 'nutrition',
        requestKey: `${turn}:propoe_plano_dieta`,
        sourceMessageId: uid(6901),
      }),
    )
    expect(s.authority.create).not.toHaveBeenCalled()
  })
  it('refuses a foreign owner before any candidate or authority read', async () => {
    const s = setup()
    await expect(s.lookup.findForTurn(uid(6999), 'original-key')).rejects.toThrow()
    expect(s.authority.capture).not.toHaveBeenCalled()
    expect(s.candidates.findForTurn).not.toHaveBeenCalled()
  })
  it('does not locate an old shortcut when current policy hides both domains', async () => {
    const s = setup('no_plan')
    expect(await s.lookup.findForTurn(consentAuth.userId, 'original-key')).toBeNull()
    expect(s.candidates.findForTurn).not.toHaveBeenCalled()
    expect(s.authority.findTurn).not.toHaveBeenCalled()
  })
  it('does not accept another candidate ID or a non-reviewable stored draft', async () => {
    const s = setup()
    s.authority.lookup.mockResolvedValueOnce({
      id: uid(6998),
      status: 'ready_for_review',
      payload: {},
    })
    expect(await s.lookup.findForTurn(consentAuth.userId, 'original-key')).toBeNull()
    s.authority.lookup.mockResolvedValueOnce({ id: uid(6902), status: 'confirmed', payload: {} })
    expect(await s.lookup.findForTurn(consentAuth.userId, 'original-key')).toBeNull()
  })
  it('refuses a changed-and-restored target revision during lookup', async () => {
    const s = setup()
    s.authority.lookup.mockImplementationOnce(async () => {
      s.day.target_revision = '2'
      return { id: uid(6902), status: 'ready_for_review', payload: {} }
    })
    await expect(s.lookup.findForTurn(consentAuth.userId, 'original-key')).rejects.toMatchObject({
      code: 'mobile_current_clinical_changed',
    })
    expect(s.authority.create).not.toHaveBeenCalled()
  })
  it('binds original receivers before any caller can replace callbacks', async () => {
    const s = setup(),
      capture = s.authority.capture,
      find = s.candidates.findForTurn
    s.authority.capture = vi.fn(async () => {
      throw new Error('replacement')
    })
    s.candidates.findForTurn = vi.fn(async () => {
      throw new Error('replacement')
    })
    expect(await s.lookup.findForTurn(consentAuth.userId, 'original-key')).toEqual({
      id: uid(6902),
      domain: 'nutrition',
    })
    expect(capture).toHaveBeenCalled()
    expect(find).toHaveBeenCalledTimes(1)
  })
})
