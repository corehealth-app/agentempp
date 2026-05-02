'use client'

import { Loader2, RotateCcw, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useTransition } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  deleteUserAction,
  resetUserConversationAction,
} from '../../messages/actions'

/**
 * Versão simplificada da DangerZone pro /users/[id] — usa window.prompt
 * em vez de Radix Dialog (que estava causando server-side render error
 * quando renderizado por RSC). Mesma funcionalidade.
 */
export function DangerButtons({
  userId,
  userName,
  userWpp,
}: {
  userId: string
  userName: string | null
  userWpp: string
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const label = userName ?? userWpp

  function reset() {
    const ans = prompt(
      `Resetar conversa de ${label}?\n\n` +
        'Apaga TODAS mensagens, refeições, treinos, snapshots, progresso, embeddings.\n' +
        'Mantém o paciente cadastrado mas zera onboarding (nome, perfil, badges).\n' +
        'Mantém subscriptions Stripe ativas.\n\n' +
        'Digite RESETAR pra confirmar:',
    )
    if (ans?.trim().toUpperCase() !== 'RESETAR') return
    startTransition(async () => {
      const r = await resetUserConversationAction(userId)
      if (r.error) toast.error(r.error)
      else {
        toast.success(`Conversa de ${label} resetada — pronto pra começar do zero`)
        router.push('/messages')
      }
    })
  }

  function del() {
    const ans = prompt(
      `EXCLUIR ${label} permanentemente?\n\n` +
        'Apaga o paciente + todas mensagens + tools + refeições + treinos + snapshots +\n' +
        'progresso + assinaturas + qualquer dado associado. CASCADE TOTAL.\n\n' +
        'Quando essa pessoa mandar nova msg pelo WhatsApp, vai ser tratado como novo.\n\n' +
        'Digite EXCLUIR pra confirmar:',
    )
    if (ans?.trim().toUpperCase() !== 'EXCLUIR') return
    startTransition(async () => {
      const r = await deleteUserAction(userId)
      if (r.error) toast.error(r.error)
      else {
        toast.success(`${label} excluído permanentemente`)
        router.push('/users')
      }
    })
  }

  return (
    <div className="flex flex-wrap gap-2">
      <Button
        variant="outline"
        onClick={reset}
        disabled={pending}
        className="text-amber-700 border-amber-500/30 hover:bg-amber-500/10"
      >
        {pending ? (
          <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
        ) : (
          <RotateCcw className="h-4 w-4 mr-1.5" />
        )}
        Resetar conversa
      </Button>
      <Button
        variant="outline"
        onClick={del}
        disabled={pending}
        className="text-rose-700 border-rose-500/30 hover:bg-rose-500/10"
      >
        {pending ? (
          <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
        ) : (
          <Trash2 className="h-4 w-4 mr-1.5" />
        )}
        Excluir paciente
      </Button>
    </div>
  )
}
