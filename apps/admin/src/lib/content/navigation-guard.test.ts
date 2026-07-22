import { describe, expect, it, vi } from 'vitest'
import {
  attemptContentNavigation,
  contentNavigationBlocked,
  registerContentNavigationGuard,
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
})
