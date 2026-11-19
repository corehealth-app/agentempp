'use client'
import { useCallback, useEffect, useRef, useState } from 'react'
import type {
  ModerationActionPort,
  OperatorContext,
} from '@/lib/journey-moderation/action-contracts'
import { browserModerationHash } from '@/lib/journey-moderation/pending-store'
import {
  createModerationSessionGate,
  type ModerationSessionGate,
} from '@/lib/journey-moderation/session-watch'
import { createClient } from '@/lib/supabase/client'
import { ModerationPanel } from './panel'

export function ConnectedModerationPanel({
  initial,
  action,
}: {
  initial: { context: OperatorContext }
  action: ModerationActionPort
}) {
  const { origin, owner, login } = initial.context
  const key = `${origin}|${owner}|${login}`
  const [admission, setAdmission] = useState<{
    key: string
    phase: ModerationSessionGate['snapshot']
  }>({ key, phase: 'checking' })
  const invalidators = useRef(new Set<() => void>())
  const watchSession = useCallback((close: () => void) => {
    invalidators.current.add(close)
    return () => {
      invalidators.current.delete(close)
    }
  }, [])
  useEffect(() => {
    const gate = createModerationSessionGate({ origin, owner, login }, browserModerationHash)
    setAdmission({ key, phase: 'checking' })
    const stop = gate.subscribe(() => {
      if (gate.snapshot === 'invalid') for (const close of [...invalidators.current]) close()
      setAdmission({ key, phase: gate.snapshot })
    })
    const client = createClient()
    const { data } = client.auth.onAuthStateChange((_event, session) => gate.handle(session))
    return () => {
      stop()
      gate.close()
      data.subscription.unsubscribe()
      for (const close of [...invalidators.current]) close()
      invalidators.current.clear()
    }
  }, [origin, owner, login, key])
  if (admission.key !== key || admission.phase === 'checking')
    return <p role="status">Conferindo a sessão operacional…</p>
  if (admission.phase === 'invalid')
    return (
      <div className="glass-card p-6" role="alert">
        <p>A sessão mudou. Reabra esta página para continuar.</p>
        <a className="mt-3 inline-block underline" href="/journey-moderation">
          Reabrir moderação
        </a>
      </div>
    )
  return <ModerationPanel initial={initial} action={action} watchSession={watchSession} />
}
