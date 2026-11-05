import { prepareRegistrationFeedbackV3 } from '@mpp/agent/registration-feedback-v3'
import { describe, expect, it, vi } from 'vitest'
import { legacyFeedback } from './__fixtures__/feedback-v2-source'
import { pendingV3Capture } from './__fixtures__/feedback-v3-source'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { parseFeedbackV3Capture } from './registration-feedback-v3-contracts'
import { createRegistrationFeedbackV3Store } from './registration-feedback-v3-store'

function setup() {
  const f = pendingV3Capture()
  const rpc = vi.fn(async (_name: string, _args: Readonly<Record<string, unknown>>) => ({
    data: { action: 'available', feedback: legacyFeedback() } as unknown,
    error: null as unknown,
  }))
  const checkCurrentScope = vi.fn(async (_identity: unknown) => true)
  const store = createRegistrationFeedbackV3Store({ rpc }, { checkCurrentScope }, f.who)
  const observation = parseFeedbackV3Capture(f.context, f.who)
  const feedback = prepareRegistrationFeedbackV3({
    registrationId: f.who.registrationId,
    localDate: observation.localDate,
    locale: 'pt-BR',
    registration: observation.registration,
    policy: projectCurrentClinicalPublicPolicy(observation.clinical),
    officialDay: null,
  })
  return { ...f, rpc, checkCurrentScope, store, observation, feedback }
}
describe('feedback v3 physical RPC scope and canonical receipt store', () => {
  it('is inert at construction and reads the exact first-version historical receipt with two fresh guards', async () => {
    const h = setup()
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.checkCurrentScope).not.toHaveBeenCalled()
    await expect(h.store.readReceipt()).resolves.toEqual({
      action: 'available',
      feedback: legacyFeedback(),
    })
    expect(h.rpc).toHaveBeenCalledWith('read_mobile_registration_feedback_v3', {
      p_user_id: h.who.userId,
      p_registration_id: h.who.registrationId,
      p_origin: h.who.origin,
    })
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })
  it('never dispatches after revocation before the first RPC, even on later calls', async () => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValue(false)
    await expect(h.store.readReceipt()).rejects.toThrow()
    await expect(h.store.capture()).rejects.toThrow()
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(1)
  })
  it('latches revocation after await and rejects a returned success without any later RPC', async () => {
    const h = setup()
    h.checkCurrentScope.mockResolvedValueOnce(true).mockResolvedValueOnce(false)
    await expect(h.store.readReceipt()).rejects.toThrow()
    await expect(h.store.capture()).rejects.toThrow()
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })
  it('checks scope after a thrown RPC and hides provider text', async () => {
    const h = setup()
    h.rpc.mockRejectedValueOnce(new Error('PRIVATE PROVIDER TOKEN'))
    await expect(h.store.readReceipt()).rejects.not.toThrow('PRIVATE PROVIDER TOKEN')
    expect(h.checkCurrentScope).toHaveBeenCalledTimes(2)
  })
  it('pins callback identities before awaits and does not accept a switched RPC or scope implementation', async () => {
    const f = pendingV3Capture(),
      rpc = vi.fn(async () => ({ data: { action: 'absent' }, error: null })),
      check = vi.fn(async () => true)
    const port = { rpc },
      scope = { checkCurrentScope: check }
    const store = createRegistrationFeedbackV3Store(port, scope, f.who)
    port.rpc = vi.fn(async () => {
      throw new Error('changed method')
    })
    scope.checkCurrentScope = vi.fn(async () => false)
    f.who.registrationId = '99999999-0000-4000-8000-000000000001'
    expect(await store.readReceipt()).toEqual({ action: 'absent' })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(check).toHaveBeenCalledTimes(2)
  })
  it('parses the captured actual provenance and detaches response aliases', async () => {
    const h = setup()
    h.rpc.mockResolvedValueOnce({ data: { action: 'available', context: h.context }, error: null })
    const result = await h.store.capture()
    expect(result.action).toBe('available')
    if (result.action !== 'available') throw new Error('Expected capture')
    h.context.snapshot.exercise_energy_complete = false
    expect(result.observation.energyComplete).toBe(true)
    expect(Object.isFrozen(result.observation.context.snapshot)).toBe(true)
  })
  it('requires the committed v3 body to match the prepared immutable payload and binds exact source arguments', async () => {
    const h = setup()
    h.rpc.mockResolvedValueOnce({
      data: { action: 'committed', feedback: h.feedback },
      error: null,
    })
    expect(await h.store.commit(h.observation, h.feedback)).toEqual({
      action: 'committed',
      feedback: h.feedback,
    })
    expect(h.rpc).toHaveBeenCalledWith('commit_mobile_registration_feedback_v3', {
      p_user_id: h.who.userId,
      p_registration_id: h.who.registrationId,
      p_origin: h.who.origin,
      p_expected_context: h.observation.context,
      p_feedback: h.feedback,
    })
    const changed = structuredClone(h.feedback)
    changed.locale = 'en'
    h.rpc.mockResolvedValueOnce({ data: { action: 'committed', feedback: changed }, error: null })
    await expect(h.store.commit(h.observation, h.feedback)).rejects.toThrow()
  })
  it('permits a concurrent older-version winner as exact replay and rejects extra envelope fields', async () => {
    const h = setup()
    h.rpc.mockResolvedValueOnce({
      data: { action: 'replay', feedback: legacyFeedback() },
      error: null,
    })
    expect(await h.store.commit(h.observation, h.feedback)).toEqual({
      action: 'replay',
      feedback: legacyFeedback(),
    })
    h.rpc.mockResolvedValueOnce({ data: { action: 'absent', private: true }, error: null })
    await expect(h.store.readReceipt()).rejects.toThrow()
  })
})

it('detaches the SDK response before the fresh post-dispatch guard can await or mutate its alias', async () => {
  const h = setup(),
    feedback = legacyFeedback()
  const raw = { data: { action: 'available', feedback }, error: null }
  const expected = structuredClone(feedback)
  h.rpc.mockResolvedValue(raw)
  let calls = 0
  h.checkCurrentScope.mockImplementation(async () => {
    if (++calls === 2) {
      const line = feedback.lines[0]
      if (!line) throw new Error('Missing actual legacy line')
      line.text = 'Late SDK alias mutation'
    }
    return true
  })
  expect(await h.store.readReceipt()).toEqual({ action: 'available', feedback: expected })
})
