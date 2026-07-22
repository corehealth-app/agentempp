import { describe, expect, it, vi } from 'vitest'
import {
  attemptContentNavigation,
  contentNavigationBlocked,
  createContentHistoryNavigationController,
  registerContentNavigationGuard,
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

  it('preserves unrelated history state and does not invent a direction without an index or marker', () => {
    const confirm = vi.fn(() => false)
    const restore = vi.fn()
    const controller = createContentHistoryNavigationController({
      currentPosition: 20,
      confirm,
      restore,
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
  })
})
