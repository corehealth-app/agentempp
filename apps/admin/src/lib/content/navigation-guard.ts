'use client'

import { useEffect } from 'react'

const UNSAVED_CHANGES_WARNING = 'Existem alteracoes nao salvas. Deseja descarta-las e continuar?'

type NavigationGuard = () => boolean
type ConfirmNavigation = () => boolean

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

export function useContentNavigationGuard(blocked: boolean): void {
  useEffect(() => registerContentNavigationGuard(() => blocked), [blocked])

  useEffect(() => {
    if (!blocked) return

    let restoringHistory = false
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
    const handlePopState = () => {
      if (restoringHistory) {
        restoringHistory = false
        return
      }
      if (!attemptContentNavigation(() => undefined)) {
        restoringHistory = true
        window.history.forward()
      }
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
