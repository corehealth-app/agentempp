'use client'

import { Check, Clock, Loader2, MessageSquare } from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useTransition } from 'react'
import { toast } from 'sonner'
import { attentionDismissAction, attentionSnoozeAction } from './actions'

/**
 * Ações inline em cada item de "Quem precisa da sua atenção".
 *
 * - Abrir conversa: link direto pra /messages?user=...
 * - Snooze 24h: esconde por 1 dia (volta automaticamente)
 * - Resolver: esconde permanentemente até nova ocorrência
 *
 * Snooze + dismiss usam attention_dismissals + audit_log automático.
 */
export function AttentionActions({ userId, kind }: { userId: string; kind: string }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()

  function snooze() {
    startTransition(async () => {
      const r = await attentionSnoozeAction(userId, kind, 24)
      if (r.error) toast.error(r.error)
      else {
        toast.success('Adiado por 24h')
        router.refresh()
      }
    })
  }

  function dismiss() {
    if (!confirm('Marcar como resolvido? Item só volta se condição reaparecer.')) return
    startTransition(async () => {
      const r = await attentionDismissAction(userId, kind)
      if (r.error) toast.error(r.error)
      else {
        toast.success('Resolvido')
        router.refresh()
      }
    })
  }

  return (
    <div className="flex items-center gap-1 shrink-0">
      <Link
        href={`/messages?user=${userId}`}
        className="h-7 px-2 inline-flex items-center gap-1 rounded text-[11px] font-mono text-foreground/70 hover:bg-muted hover:text-foreground transition-colors"
        title="Abrir conversa"
      >
        <MessageSquare className="h-3 w-3" />
        Conversa
      </Link>
      <button
        type="button"
        onClick={snooze}
        disabled={pending}
        className="h-7 px-2 inline-flex items-center gap-1 rounded text-[11px] font-mono text-amber-700 hover:bg-amber-500/10 transition-colors disabled:opacity-50"
        title="Esconder por 24h"
      >
        {pending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Clock className="h-3 w-3" />}
        Adiar 24h
      </button>
      <button
        type="button"
        onClick={dismiss}
        disabled={pending}
        className="h-7 px-2 inline-flex items-center gap-1 rounded text-[11px] font-mono text-moss-700 hover:bg-moss-500/10 transition-colors disabled:opacity-50"
        title="Marcar como resolvido"
      >
        <Check className="h-3 w-3" />
        Resolver
      </button>
    </div>
  )
}
