'use client'

import { useEffect } from 'react'

const UNSAVED_CHANGES_WARNING = 'Existem alteracoes nao salvas. Deseja descarta-las e continuar?'

type NavigationGuard = () => boolean
type ConfirmNavigation = () => boolean

const HISTORY_POSITION_KEY = '__bodyflowContentHistoryPosition'

let nextHistoryPosition = 0

const navigationGuards = new Set<NavigationGuard>()

export function contentNavigationBlocked(input: {
  dirty: boolean
  coverBusy: boolean
  pendingCoverResolution: boolean
}): boolean {
  return input.dirty || input.coverBusy || input.pendingCoverResolution
}

export function registerContentNavigationGuard(guard: NavigationGuard): () => void {
  navigationGuards.add(guard)
  return () => navigationGuards.delete(guard)
}

export function attemptContentNavigation(
  navigate: () => void,
  confirm: ConfirmNavigation = () => window.confirm(UNSAVED_CHANGES_WARNING),
): boolean {
  if ([...navigationGuards].some((guard) => guard()) && !confirm()) return false
  navigate()
  return true
}

export function stampContentHistoryPosition(
  state: unknown,
  position: number,
): Record<string, unknown> {
  if (typeof state === 'object' && state !== null && !Array.isArray(state)) {
    return { ...(state as Record<string, unknown>), [HISTORY_POSITION_KEY]: position }
  }
  return { [HISTORY_POSITION_KEY]: position }
}

export function createContentHistoryNavigationController({
  currentPosition,
  confirm,
  restore,
  positionForPop,
}: {
  currentPosition: number
  confirm: ConfirmNavigation
  restore: (delta: number) => void
  positionForPop?: () => number | null
}): { handlePop(state: unknown): void } {
  let current = currentPosition
  let restoringPosition: number | null = null

  return {
    handlePop(state) {
      const next = positionForPop?.() ?? contentHistoryPosition(state)
      if (restoringPosition !== null && next === restoringPosition) {
        restoringPosition = null
        return
      }
      if (next === current) return
      if (confirm()) {
        if (next !== null) current = next
        return
      }

      // Without an entry index or marker, the browser does not expose a safe direction to undo.
      if (next === null) return
      const delta = current - next
      if (delta === 0) return
      restoringPosition = current
      restore(delta)
    },
  }
}

export function useContentNavigationGuard(blocked: boolean): void {
  useEffect(() => registerContentNavigationGuard(() => blocked), [blocked])

  useEffect(() => {
    if (!blocked) return

    const markerPosition = reserveContentHistoryPosition(window.history.state)
    const navigationPosition = browserNavigationEntryIndex()
    const currentPosition = navigationPosition ?? markerPosition
    window.history.replaceState(
      stampContentHistoryPosition(window.history.state, currentPosition),
      '',
      window.location.href,
    )
    const historyController = createContentHistoryNavigationController({
      currentPosition,
      confirm: () => attemptContentNavigation(() => undefined),
      restore: (delta) => window.history.go(delta),
      ...(navigationPosition !== null
        ? { positionForPop: () => browserNavigationEntryIndex() }
        : {}),
    })
    const handleBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault()
      event.returnValue = ''
    }
    const handleDocumentClick = (event: MouseEvent) => {
      if (
        event.defaultPrevented ||
        event.button !== 0 ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey
      ) {
        return
      }
      const target = event.target instanceof Element ? event.target.closest('a[href]') : null
      if (!(target instanceof HTMLAnchorElement) || target.target === '_blank' || target.download) {
        return
      }
      const destination = new URL(target.href, window.location.href)
      if (
        destination.origin !== window.location.origin ||
        destination.href === window.location.href
      ) {
        return
      }
      if (!attemptContentNavigation(() => undefined)) {
        event.preventDefault()
        event.stopPropagation()
      }
    }
    const handlePopState = (event: PopStateEvent) => {
      historyController.handlePop(event.state)
    }

    window.addEventListener('beforeunload', handleBeforeUnload)
    window.addEventListener('popstate', handlePopState)
    document.addEventListener('click', handleDocumentClick, true)
    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload)
      window.removeEventListener('popstate', handlePopState)
      document.removeEventListener('click', handleDocumentClick, true)
    }
  }, [blocked])
}

function contentHistoryPosition(state: unknown): number | null {
  if (typeof state !== 'object' || state === null || Array.isArray(state)) return null
  const position = (state as Record<string, unknown>)[HISTORY_POSITION_KEY]
  return typeof position === 'number' && Number.isSafeInteger(position) ? position : null
}

function reserveContentHistoryPosition(state: unknown): number {
  const existing = contentHistoryPosition(state)
  if (existing !== null) {
    nextHistoryPosition = Math.max(nextHistoryPosition, existing)
    return existing
  }
  nextHistoryPosition += 1
  return nextHistoryPosition
}

function browserNavigationEntryIndex(): number | null {
  const navigation = (
    window as unknown as {
      navigation?: { currentEntry?: { index?: unknown } }
    }
  ).navigation
  const index = navigation?.currentEntry?.index
  return typeof index === 'number' && Number.isSafeInteger(index) ? index : null
}
