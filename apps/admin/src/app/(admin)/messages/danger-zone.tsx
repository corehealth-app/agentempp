'use client'

import { Loader2, RotateCcw, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { deleteUserAction, resetUserConversationAction } from './actions'

/**
 * Ações destrutivas: resetar conversa (mantém user) ou excluir paciente.
 * Ambas exigem confirmação textual ("RESETAR" / "EXCLUIR").
 */
export function DangerZone({
  userId,
  userName,
  userWpp,
  layout = 'compact',
}: {
  userId: string
  userName: string | null
  userWpp: string
  layout?: 'compact' | 'full'
}) {
  return (
    <div
      className={
        layout === 'compact'
          ? 'flex flex-wrap gap-1.5'
          : 'flex flex-col gap-2'
      }
    >
      <ResetDialog userId={userId} userName={userName} userWpp={userWpp} layout={layout} />
      <DeleteDialog userId={userId} userName={userName} userWpp={userWpp} layout={layout} />
    </div>
  )
}

function ResetDialog({
  userId,
  userName,
  userWpp,
  layout,
}: {
  userId: string
  userName: string | null
  userWpp: string
  layout: 'compact' | 'full'
}) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [confirm, setConfirm] = useState('')
  const [pending, startTransition] = useTransition()

  function execute() {
    if (confirm.trim().toUpperCase() !== 'RESETAR') return
    startTransition(async () => {
      const r = await resetUserConversationAction(userId)
      if (r.error) {
        toast.error(r.error)
      } else {
        toast.success(`Conversa de ${userName ?? userWpp} resetada — pronto pra começar do zero`)
        setOpen(false)
        setConfirm('')
        router.push('/messages')
      }
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="outline"
          size={layout === 'compact' ? 'sm' : 'default'}
          className="text-amber-700 border-amber-500/30 hover:bg-amber-500/10"
        >
          <RotateCcw className="h-3.5 w-3.5 mr-1.5" />
          Resetar conversa
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Resetar conversa de {userName ?? userWpp}?</DialogTitle>
          <DialogDescription>
            Apaga TODAS as mensagens, refeições, treinos, progresso, snapshots, embeddings.
            Mantém o paciente cadastrado mas zera o onboarding (nome, perfil clínico, badges).
            <br />
            <strong>Útil pra testar o fluxo do zero sem precisar criar paciente novo.</strong>
            <br />
            <br />
            Digite <code className="font-mono bg-muted px-1.5 py-0.5 rounded">RESETAR</code> pra
            confirmar:
          </DialogDescription>
        </DialogHeader>
        <Input
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          placeholder="RESETAR"
          className="font-mono"
          autoFocus
        />
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>
            Cancelar
          </Button>
          <Button
            onClick={execute}
            disabled={pending || confirm.trim().toUpperCase() !== 'RESETAR'}
            className="bg-amber-600 hover:bg-amber-700 text-white"
          >
            {pending && <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />}
            Resetar conversa
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function DeleteDialog({
  userId,
  userName,
  userWpp,
  layout,
}: {
  userId: string
  userName: string | null
  userWpp: string
  layout: 'compact' | 'full'
}) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [confirm, setConfirm] = useState('')
  const [pending, startTransition] = useTransition()

  function execute() {
    if (confirm.trim().toUpperCase() !== 'EXCLUIR') return
    startTransition(async () => {
      const r = await deleteUserAction(userId)
      if (r.error) {
        toast.error(r.error)
      } else {
        toast.success(`${userName ?? userWpp} excluído permanentemente`)
        setOpen(false)
        setConfirm('')
        router.push('/users')
      }
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="outline"
          size={layout === 'compact' ? 'sm' : 'default'}
          className="text-rose-700 border-rose-500/30 hover:bg-rose-500/10"
        >
          <Trash2 className="h-3.5 w-3.5 mr-1.5" />
          Excluir
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Excluir {userName ?? userWpp} permanentemente?</DialogTitle>
          <DialogDescription>
            Isso é <strong>irreversível</strong>. Apaga o paciente + todas as mensagens, tools,
            refeições, treinos, snapshots, progresso, assinaturas Stripe locais e qualquer dado
            associado. Cascade total via FK.
            <br />
            <br />
            Quando essa pessoa mandar nova msg pelo WhatsApp, vai ser tratado como paciente novo
            (1ª interação, onboarding do zero).
            <br />
            <br />
            Digite <code className="font-mono bg-muted px-1.5 py-0.5 rounded">EXCLUIR</code> pra
            confirmar:
          </DialogDescription>
        </DialogHeader>
        <Input
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          placeholder="EXCLUIR"
          className="font-mono"
          autoFocus
        />
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>
            Cancelar
          </Button>
          <Button
            onClick={execute}
            disabled={pending || confirm.trim().toUpperCase() !== 'EXCLUIR'}
            className="bg-rose-600 hover:bg-rose-700 text-white"
          >
            {pending && <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />}
            Excluir permanentemente
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
