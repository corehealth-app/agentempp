import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationCurrentScope } from './conversation-current-scope'
import { createConversationMealReplyScope } from './conversation-meal-reply-scope'

function setup(parallelMappingReads = false) {
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
      parallelMappingReads,
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

  it('overlaps only verified mapping reads and still waits for both before observing clinical state', async () => {
    const f = setup(true)
    let confirmAuth!: () => void
    const auth = new Promise<void>((resolve) => {
      confirmAuth = resolve
    })
    let confirmNonAdmin!: () => void
    const nonAdmin = new Promise<void>((resolve) => {
      confirmNonAdmin = resolve
    })
    f.authPort.verifyAccessToken.mockImplementationOnce(async () => {
      await auth
      return f.auth.identity
    })
    f.authPort.isAdmin.mockImplementationOnce(async () => {
      await nonAdmin
      return false
    })

    const pending = f.scope.observe(f.binding)
    try {
      await vi.waitFor(() => expect(f.authPort.verifyAccessToken).toHaveBeenCalledOnce())
      expect(f.authPort.isAdmin).not.toHaveBeenCalled()
      expect(f.authPort.loadPatient).not.toHaveBeenCalled()
      confirmAuth()
      await vi.waitFor(() => expect(f.authPort.loadPatient).toHaveBeenCalledWith(f.auth.authUserId))
      expect(f.authPort.isAdmin).toHaveBeenCalledWith(f.auth.authUserId)
      expect(f.capture).not.toHaveBeenCalled()
    } finally {
      confirmAuth()
      confirmNonAdmin()
      await pending
    }
    expect(await pending).toEqual(f.profile)
    expect(f.authPort.verifyAccessToken).toHaveBeenCalledTimes(2)
    expect(f.authPort.isAdmin).toHaveBeenCalledTimes(2)
    expect(f.authPort.loadPatient).toHaveBeenCalledTimes(2)
  })

  it('refuses authority and future observations when an overlapping role read discovers an admin', async () => {
    const f = setup(true)
    f.authPort.isAdmin.mockResolvedValueOnce(true)
    await expect(f.scope.observe(f.binding)).rejects.toMatchObject({
      status: 403,
      code: 'patient_admin_account_conflict',
    })
    expect(f.authPort.loadPatient).toHaveBeenCalledWith(f.auth.authUserId)
    expect(f.capture).not.toHaveBeenCalled()
    expect(await f.scope.check(f.binding)).toBe(false)
    expect(f.authPort.verifyAccessToken).toHaveBeenCalledOnce()
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
