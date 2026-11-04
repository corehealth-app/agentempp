import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import {
  authenticateConversationReplyPatient,
  createConversationMealReplyScope,
} from './conversation-meal-reply-scope'

function setup() {
  const f = replyFixture(),
    verifyAccessToken = vi.fn().mockResolvedValue(f.auth.identity),
    loadPatient = vi.fn().mockResolvedValue(f.auth.patient),
    bootstrapPatient = vi.fn(() => {
      throw new Error('NOBOOTSTRAP')
    }),
    capture = vi.fn().mockResolvedValue(f.profile)
  const deps = {
    auth: {
      verifyAccessToken,
      loadPatient,
      isAdmin: vi.fn().mockResolvedValue(false),
      bootstrapPatient,
    },
    clinical: { capture },
  }
  const scope = createConversationMealReplyScope({} as ServiceClient, f.auth, f.identity, deps)
  return { ...f, verifyAccessToken, loadPatient, bootstrapPatient, capture, scope, deps }
}
describe('actual readonly Auth patient epoch scope', () => {
  it('is inert and verifies the original token, actual patient mapping and actual epoch observation', async () => {
    const f = setup()
    expect(f.verifyAccessToken).not.toHaveBeenCalled()
    expect(await f.scope.check()).toBe(true)
    expect(f.verifyAccessToken).toHaveBeenCalledWith(f.auth.accessToken)
    expect(f.loadPatient).toHaveBeenCalledWith(f.auth.authUserId)
    expect(f.capture).toHaveBeenCalledWith({
      userId: f.identity.ownerId,
      mode: 'profile',
      expectedEpoch: f.identity.epoch,
    })
    expect(f.bootstrapPatient).not.toHaveBeenCalled()
    expect(f.auth.authUserId).not.toBe(f.identity.ownerId)
  })
  it('never reacquires scope after a failed check', async () => {
    const f = setup()
    f.verifyAccessToken.mockResolvedValueOnce(null)
    expect(await f.scope.check()).toBe(false)
    f.verifyAccessToken.mockResolvedValue(f.auth.identity)
    expect(await f.scope.check()).toBe(false)
    expect(f.verifyAccessToken).toHaveBeenCalledTimes(1)
    await expect(f.scope.observe()).rejects.toMatchObject({ status: 401 })
  })
  it.each([
    'patient',
    'auth',
    'epoch',
    'inactive',
  ])('refuses changed %s before any caller effect', async (key) => {
    const f = setup()
    if (key === 'patient')
      f.loadPatient.mockResolvedValue({ ...f.auth.patient, id: f.auth.authUserId })
    if (key === 'auth')
      f.verifyAccessToken.mockResolvedValue({ ...f.auth.identity, id: f.identity.ownerId })
    if (key === 'epoch') f.capture.mockResolvedValue({ ...f.profile, epoch: f.auth.authUserId })
    if (key === 'inactive')
      f.loadPatient.mockResolvedValue({ ...f.auth.patient, status: 'deleted' })
    expect(await f.scope.check()).toBe(false)
    expect(f.bootstrapPatient).not.toHaveBeenCalled()
  })
  it('authenticates an existing patient read-only, without profile bootstrap', async () => {
    const f = setup()
    const auth = await authenticateConversationReplyPatient(
      new Request('https://app.invalid', {
        headers: { Authorization: `Bearer ${f.auth.accessToken}` },
      }),
      f.deps.auth,
    )
    expect(auth).toEqual(f.auth)
    expect(f.bootstrapPatient).not.toHaveBeenCalled()
  })
  it('does not execute a getter returned by a substituted clinical transport', async () => {
    const f = setup(),
      raw = structuredClone(f.profile),
      hook = vi.fn(() => f.identity.epoch)
    Object.defineProperty(raw, 'epoch', { enumerable: true, get: hook })
    f.capture.mockResolvedValue(raw)
    expect(await f.scope.check()).toBe(false)
    expect(hook).not.toHaveBeenCalled()
  })
  it('serializes real scope observations so parallel nutrition work cannot publish an out-of-order epoch read', async () => {
    const f = setup()
    let release: () => void = () => {}
    const first = new Promise<void>((r) => {
      release = r
    })
    f.capture.mockImplementationOnce(async () => {
      await first
      return f.profile
    })
    const a = f.scope.check()
    await vi.waitFor(() => expect(f.capture).toHaveBeenCalledTimes(1))
    const b = f.scope.check(),
      authCallsBeforeRelease = f.verifyAccessToken.mock.calls.length
    release()
    expect(await Promise.all([a, b])).toEqual([true, true])
    expect(authCallsBeforeRelease).toBe(1)
    expect(f.capture).toHaveBeenCalledTimes(2)
  })

  it('preserves bootstrap existing admin/patient separation through a readonly membership check', async () => {
    const f = setup()
    f.deps.auth.isAdmin.mockResolvedValue(true)
    await expect(
      authenticateConversationReplyPatient(
        new Request('https://app.invalid', {
          headers: { Authorization: `Bearer ${f.auth.accessToken}` },
        }),
        f.deps.auth,
      ),
    ).rejects.toMatchObject({ status: 403, code: 'patient_admin_account_conflict' })
    expect(f.bootstrapPatient).not.toHaveBeenCalled()
  })
})
