import { z } from 'zod'
import { socialUUID } from '../mobile-api/journey-social-contracts'
import {
  deriveOperatorContext,
  type OperatorContext,
  sameOperatorContext,
} from './action-contracts'

export type ModerationBrowserSession = { access_token: string; user: { id: string } } | null
export interface ModerationSessionGate {
  readonly snapshot: 'checking' | 'valid' | 'invalid'
  handle(session: ModerationBrowserSession): void
  subscribe(listener: () => void): () => void
  close(): void
}
export function createModerationSessionGate(
  context: OperatorContext,
  hash: (value: string) => Promise<string>,
): ModerationSessionGate {
  let phase: ModerationSessionGate['snapshot'] = 'checking'
  let candidate: { actor: string; login: string } | null = null
  let disposed = false,
    generation = 0
  const listeners = new Set<() => void>()
  const emit = () => {
    for (const listener of [...listeners]) listener()
  }
  function retire() {
    if (phase === 'invalid') return
    generation++
    phase = 'invalid'
    emit()
  }
  return {
    get snapshot() {
      return phase
    },
    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    handle(session) {
      if (disposed || phase === 'invalid') return
      const current = sessionReference(session)
      if (!current) {
        retire()
        return
      }
      if (candidate) {
        if (candidate.actor !== current.actor || candidate.login !== current.login) retire()
        return
      }
      candidate = current
      const run = ++generation
      void matchesModerationSession(context, session, hash).then((matches) => {
        if (disposed || run !== generation || phase === 'invalid') return
        if (!matches) retire()
        else {
          phase = 'valid'
          emit()
        }
      })
    },
    close() {
      if (!disposed) {
        retire()
        disposed = true
        listeners.clear()
      }
    },
  }
}

function sessionReference(session: ModerationBrowserSession) {
  try {
    if (!session || session.access_token.length > 16384) return null
    const pieces = session.access_token.split('.'),
      part = pieces[1]
    if (pieces.length !== 3 || pieces.some((x) => !/^[\w-]+$/u.test(x)) || !part) return null
    const bytes = Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/')), (c) =>
      c.charCodeAt(0),
    )
    const claims = z
      .object({ sub: socialUUID, session_id: socialUUID })
      .passthrough()
      .parse(JSON.parse(new TextDecoder().decode(bytes)))
    if (claims.sub !== session.user.id.toLowerCase()) return null
    return { actor: claims.sub, login: claims.session_id }
  } catch {
    return null
  }
}

/** Session events can only invalidate the UI. They never authorize an action. */
export async function matchesModerationSession(
  context: OperatorContext,
  session: ModerationBrowserSession,
  hash: (value: string) => Promise<string>,
): Promise<boolean> {
  try {
    const reference = sessionReference(session)
    if (!reference) return false
    return sameOperatorContext(
      context,
      await deriveOperatorContext(reference, context.origin, hash),
    )
  } catch {
    return false
  }
}
