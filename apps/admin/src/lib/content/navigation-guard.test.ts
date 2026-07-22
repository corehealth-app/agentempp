import { describe, expect, it, vi } from 'vitest'
import {
  attemptContentNavigation,
  attemptContentSignOut,
  contentNavigationBlocked,
  createContentHistoryNavigationController,
  registerContentNavigationGuard,
  shouldBlockContentBeforeUnload,
  stampContentHistoryPosition,
} from './navigation-guard'

describe('content navigation guard', () => {
  it('blocks a programmatic navigation while edits, cover upload, or cover resolution are pending', () => {
    const navigate = vi.fn()
    const unregister = registerContentNavigationGuard(() =>
      contentNavigationBlocked({ dirty: false, coverBusy: true, pendingCoverResolution: false }),
    )

    try {
      expect(attemptContentNavigation(navigate, () => false)).toBe(false)
      expect(navigate).not.toHaveBeenCalled()
    } finally {
      unregister()
    }
  })

  it('allows guarded programmatic navigation only after confirmation', () => {
    const navigate = vi.fn()
    const unregister = registerContentNavigationGuard(() =>
      contentNavigationBlocked({ dirty: true, coverBusy: false, pendingCoverResolution: false }),
    )

    try {
      expect(attemptContentNavigation(navigate, () => true)).toBe(true)
      expect(navigate).toHaveBeenCalledTimes(1)
    } finally {
      unregister()
    }
  })

  it('signs out only after confirmation and bypasses exactly one resulting unload prompt', async () => {
    const calls: string[] = []
    const unregister = registerContentNavigationGuard(() => true)

    try {
      await expect(
        attemptContentSignOut({
          confirm: () => true,
          signOut: async () => {
            calls.push('sign-out')
          },
          navigate: () => calls.push('navigate'),
        }),
      ).resolves.toBe(true)

      expect(calls).toEqual(['sign-out', 'navigate'])
      expect(shouldBlockContentBeforeUnload()).toBe(false)
      expect(shouldBlockContentBeforeUnload()).toBe(true)
    } finally {
      unregister()
    }
  })

  it('keeps the session and unload guard intact when sign-out navigation is canceled', async () => {
    const signOut = vi.fn(async () => undefined)
    const navigate = vi.fn()
    const unregister = registerContentNavigationGuard(() => true)

    try {
      await expect(
        attemptContentSignOut({
          confirm: () => false,
          signOut,
          navigate,
        }),
      ).resolves.toBe(false)

      expect(signOut).not.toHaveBeenCalled()
      expect(navigate).not.toHaveBeenCalled()
      expect(shouldBlockContentBeforeUnload()).toBe(true)
    } finally {
      unregister()
    }
  })

  it('restores the unload guard when Supabase fulfills sign-out with an error', async () => {
    const signOutError = new Error('sign-out failed')
    const navigate = vi.fn()

    await expect(
      attemptContentSignOut({
        confirm: () => true,
        signOut: async () => ({ error: signOutError }),
        navigate,
      }),
    ).rejects.toBe(signOutError)

    expect(navigate).not.toHaveBeenCalled()
    expect(shouldBlockContentBeforeUnload()).toBe(true)
  })

  it('cancels Back once and restores the draft entry without a duplicate confirmation or loop', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
    })

    controller.handlePop({ __bodyflowContentHistoryPosition: 19 })
    controller.handlePop({ __bodyflowContentHistoryPosition: 20 })

    expect(confirm).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledWith(1)
  })

  it('cancels Forward once and restores the draft entry without a duplicate confirmation or loop', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
    })

    controller.handlePop({ __bodyflowContentHistoryPosition: 21 })
    controller.handlePop({ __bodyflowContentHistoryPosition: 20 })

    expect(confirm).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledWith(-1)
  })

  it('cancels unmarked Back using the real history index without a duplicate confirmation or loop', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    let currentEntryIndex: number | null = 19
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
      positionForPop: () => currentEntryIndex,
    } as Parameters<typeof createContentHistoryNavigationController>[0] & {
      positionForPop: () => number | null
    })

    controller.handlePop(null)
    currentEntryIndex = 20
    controller.handlePop(null)

    expect(confirm).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledWith(1)
  })

  it('cancels unmarked Forward using the real history index without a duplicate confirmation or loop', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    let currentEntryIndex: number | null = 21
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
      positionForPop: () => currentEntryIndex,
    } as Parameters<typeof createContentHistoryNavigationController>[0] & {
      positionForPop: () => number | null
    })

    controller.handlePop(null)
    currentEntryIndex = 20
    controller.handlePop(null)

    expect(confirm).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledTimes(1)
    expect(restore).toHaveBeenCalledWith(-1)
  })

  it('preserves unrelated history state and restores an unmarked Back conservatively', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    const restoreUnmarked = vi.fn()
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
      restoreUnmarked,
      positionForPop: () => null,
    } as Parameters<typeof createContentHistoryNavigationController>[0] & {
      positionForPop: () => number | null
    })

    expect(stampContentHistoryPosition({ __NA: true, tree: ['keep'] }, 20)).toEqual({
      __NA: true,
      tree: ['keep'],
      __bodyflowContentHistoryPosition: 20,
    })
    controller.handlePop(null)

    expect(confirm).toHaveBeenCalledTimes(1)
    expect(restore).not.toHaveBeenCalled()
    expect(restoreUnmarked).toHaveBeenCalledTimes(1)
  })
})
