import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import { clinical } from './__fixtures__/feedback-v2-source'
import type { ConversationReadonlyAuth } from './conversation-current-scope'
import { createConversationSessionInitialization } from './conversation-session-initialization'
import { type CurrentClinicalStateSource, currentClinicalError } from './current-clinical-state'

function fixture(missing = true) {
  const state = { ...clinical(), user_id: candidateAuth.userId },
    auth = {
      verifyAccessToken: vi.fn<ConversationReadonlyAuth['verifyAccessToken']>(async () => ({
        ...candidateAuth.identity,
        email: 'qa@example.invalid',
        emailConfirmedAt: state.observed_at,
      })),
      loadPatient: vi.fn<ConversationReadonlyAuth['loadPatient']>(
        async () => candidateAuth.patient,
      ),
      isAdmin: vi.fn<ConversationReadonlyAuth['isAdmin']>(async () => false),
    },
    source = {
      capture: vi.fn<CurrentClinicalStateSource['capture']>(async () => ({
        ...state,
        epoch: missing ? null : state.epoch,
      })),
    },
    initializeEpoch = vi.fn(async () => {
      missing = false
      return { userId: state.user_id, epoch: state.epoch }
    }),
    service = createConversationSessionInitialization({} as ServiceClient, {
      auth,
      clinical: source,
      initializeEpoch,
    })
  return { auth, source, initializeEpoch, service, state }
}
describe('explicit owned conversation session initialization', () => {
  it('uses the real Supabase epoch adapter without admitting a signup or conversation command', async () => {
    const f = fixture()
    let initialized = false
    const rpc = vi.fn(async () => {
      initialized = true
      return {
        data: {
          status: 'observed',
          observation: {
            ownerID: candidateAuth.userId,
            epoch: f.state.epoch,
            changedAt: f.state.observed_at,
          },
        },
        error: null,
      }
    })
    const service = createConversationSessionInitialization({ rpc } as unknown as ServiceClient, {
      auth: f.auth,
      clinical: {
        capture: async () => ({ ...f.state, epoch: initialized ? f.state.epoch : null }),
      },
    })
    expect(await service.initialize(candidateAuth)).toMatchObject({ epoch: f.state.epoch })
    expect(rpc.mock.calls).toEqual([
      ['observe_mobile_signup_strength_epoch', { p_user_id: candidateAuth.userId }],
    ])
  })
  it('initializes an absent epoch once, then only observes that exact epoch on repeat', async () => {
    const f = fixture()
    const one = await f.service.initialize(candidateAuth),
      two = await f.service.initialize(candidateAuth)
    expect(one).toEqual(two)
    expect(one).toMatchObject({
      schema: 'conversation.session.v1',
      auth_user_id: candidateAuth.authUserId,
      owner_id: candidateAuth.userId,
      epoch: f.state.epoch,
    })
    expect(f.initializeEpoch).toHaveBeenCalledTimes(1)
    expect(f.initializeEpoch).toHaveBeenCalledWith({ userId: candidateAuth.userId })
    expect(f.auth.verifyAccessToken.mock.calls.length).toBeGreaterThanOrEqual(4)
  })
  it('never renews an existing epoch or invokes an initialization write', async () => {
    const f = fixture(false)
    expect(await f.service.initialize(candidateAuth)).toMatchObject({ epoch: f.state.epoch })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('refuses a revoked token before any initialization', async () => {
    const f = fixture()
    f.auth.verifyAccessToken.mockResolvedValue(null)
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 401 })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('refuses admin membership before any initialization', async () => {
    const f = fixture()
    f.auth.isAdmin.mockResolvedValue(true)
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 403 })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('refuses a changed patient mapping before any initialization', async () => {
    const f = fixture()
    f.auth.loadPatient.mockResolvedValue({
      ...candidateAuth.patient,
      id: '10000000-0000-4000-8000-000000000099',
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 409 })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('refuses an incomplete profile instead of completing signup', async () => {
    const f = fixture()
    const base = clinical()
    f.source.capture.mockResolvedValue({
      ...base,
      epoch: null,
      generation_token: {
        ...base.generation_token,
        onboarding_completed: false,
        onboarding_completed_at: null,
      },
      first_completion: true,
      phase_origin: { kind: 'not_completed' },
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({
      status: 409,
      code: 'conversation_session_profile_required',
    })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('does not publish scope when auth is revoked while initialization is in flight', async () => {
    const f = fixture()
    f.initializeEpoch.mockImplementation(async () => {
      f.auth.verifyAccessToken.mockResolvedValue(null)
      return { userId: candidateAuth.userId, epoch: f.state.epoch }
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 401 })
    expect(f.initializeEpoch).toHaveBeenCalledTimes(1)
  })
  it('rejects a different owner returned by the epoch port', async () => {
    const f = fixture()
    f.initializeEpoch.mockResolvedValue({
      userId: '10000000-0000-4000-8000-000000000099',
      epoch: f.state.epoch,
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 503 })
  })
  it('rejects a reset during initialization rather than adopting the replacement epoch', async () => {
    const f = fixture()
    f.initializeEpoch.mockImplementation(async () => {
      f.source.capture.mockImplementation(async (request) => {
        if (request.expectedEpoch !== undefined) throw currentClinicalError('changed')
        return { ...f.state, epoch: '50000000-0000-4000-8000-000000000099' }
      })
      return { userId: candidateAuth.userId, epoch: f.state.epoch }
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 409 })
  })
  it('sanitizes an uncertain initializer failure and never automatically replays it', async () => {
    const f = fixture()
    f.initializeEpoch.mockRejectedValue(new Error('private provider detail'))
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({
      status: 503,
      code: 'conversation_session_initialization_unavailable',
    })
    expect(f.initializeEpoch).toHaveBeenCalledTimes(1)
  })
  it('refuses an account change during the initial clinical read before initializing', async () => {
    const f = fixture()
    f.source.capture.mockImplementation(async () => {
      f.auth.isAdmin.mockResolvedValue(true)
      return { ...f.state, epoch: null }
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 403 })
    expect(f.initializeEpoch).not.toHaveBeenCalled()
  })
  it('refuses post-initialization admin membership without returning a session', async () => {
    const f = fixture()
    f.initializeEpoch.mockImplementation(async () => {
      f.auth.isAdmin.mockResolvedValue(true)
      return { userId: candidateAuth.userId, epoch: f.state.epoch }
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({ status: 403 })
  })
  it('does not publish a final observation older than the pre-initialization observation', async () => {
    const f = fixture(false),
      older = '2026-11-03T11:59:59.000001Z'
    f.source.capture.mockResolvedValueOnce(f.state).mockResolvedValue({
      ...f.state,
      observed_at: older,
      safety: { ...f.state.safety, observed_at: older },
    })
    await expect(f.service.initialize(candidateAuth)).rejects.toMatchObject({
      status: 409,
      code: 'conversation_scope_changed',
    })
  })
})
