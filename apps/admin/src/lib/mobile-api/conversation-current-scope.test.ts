import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationCurrentScope } from './conversation-current-scope'
import { createConversationMealReplyScope } from './conversation-meal-reply-scope'

function setup() {
  const f = replyFixture(),
    binding = { authUserId: f.auth.authUserId, ownerId: f.auth.userId, epoch: f.identity.epoch },
    auth = {
      verifyAccessToken: vi.fn().mockResolvedValue(f.auth.identity),
      loadPatient: vi.fn().mockResolvedValue(f.auth.patient),
      isAdmin: vi.fn().mockResolvedValue(false),
    },
    capture = vi.fn().mockResolvedValue(f.profile),
    scope = createConversationCurrentScope({} as ServiceClient, f.auth, binding, {
      auth,
      clinical: { capture },
    })
  return { ...f, binding, authPort: auth, capture, scope }
}

describe('shared current conversation owner and epoch observation', () => {
  it('checks a root command without inventing a parent or reply identity', async () => {
    const f = setup()
    expect(f.auth.authUserId).not.toBe(f.auth.userId)
    expect(await f.scope.observe(f.binding)).toEqual(f.profile)
    expect(f.authPort.verifyAccessToken.mock.calls).toEqual([
      [f.auth.accessToken],
      [f.auth.accessToken],
    ])
    expect(f.authPort.isAdmin.mock.calls).toEqual([[f.auth.authUserId], [f.auth.authUserId]])
    expect(f.capture.mock.calls).toEqual([
      [{ userId: f.auth.userId, mode: 'profile', expectedEpoch: f.identity.epoch }],
    ])
  })

  it('latches an admin transition during profile observation before returning authority', async () => {
    const f = setup()
    f.authPort.isAdmin.mockResolvedValueOnce(false).mockResolvedValueOnce(true)
    expect(await f.scope.check()).toBe(false)
    f.authPort.isAdmin.mockResolvedValue(false)
    expect(await f.scope.check()).toBe(false)
    expect(f.capture).toHaveBeenCalledTimes(1)
    await expect(f.scope.observe()).rejects.toMatchObject({
      status: 403,
      code: 'patient_admin_account_conflict',
    })
  })

  it('serializes observations and permanently refuses a backwards profile clock', async () => {
    const f = setup()
    let release: () => void = () => {}
    const pending = new Promise<void>((r) => {
      release = r
    })
    f.capture.mockImplementationOnce(async () => {
      await pending
      return f.profile
    })
    const first = f.scope.check()
    await vi.waitFor(() => expect(f.capture).toHaveBeenCalledTimes(1))
    const second = f.scope.check()
    expect(f.authPort.verifyAccessToken).toHaveBeenCalledTimes(1)
    f.capture.mockResolvedValueOnce({ ...f.profile, observed_at: '2020-01-01T00:00:00Z' })
    release()
    expect(await Promise.all([first, second])).toEqual([true, false])
    expect(await f.scope.check()).toBe(false)
    expect(f.capture).toHaveBeenCalledTimes(2)
  })

  it('binds caller scope metadata without changing owner or epoch', async () => {
    const f = setup()
    expect(await f.scope.check({ ...f.binding, epoch: f.auth.authUserId })).toBe(false)
    expect(await f.scope.check(f.binding)).toBe(false)
    expect(f.authPort.verifyAccessToken).not.toHaveBeenCalled()
  })

  it('preserves reply construction and the observed refusal of an original noncanonical Auth ID', async () => {
    const f = setup(),
      who = structuredClone(f.auth)
    who.authUserId = who.authUserId.toUpperCase()
    who.identity.id = who.authUserId
    who.patient.authUserId = who.authUserId
    const scope = createConversationMealReplyScope({} as ServiceClient, who, f.identity, {
      auth: f.authPort,
      clinical: { capture: f.capture },
    })
    expect(await scope.check()).toBe(false)
    await expect(scope.observe()).rejects.toMatchObject({ code: 'conversation_patient_changed' })
  })
})
