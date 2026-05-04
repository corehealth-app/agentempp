'use client'

import { Loader2, Pencil, Play, Power, X } from 'lucide-react'
import { useOptimistic, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  runCronNowAction,
  toggleCronAction,
  updateCronScheduleAction,
} from './actions'

export function CronControls({
  jobname,
  schedule,
  active,
}: {
  jobname: string
  schedule: string
  active: boolean
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(schedule)

  // Optimistic: botão muda instantaneamente, server roda em background.
  // Se der erro, useOptimistic reverte automaticamente no próximo render.
  const [optimisticActive, setOptimisticActive] = useOptimistic(active)

  function toggle() {
    const next = !optimisticActive
    startTransition(async () => {
      setOptimisticActive(next)
      const r = await toggleCronAction(jobname, next)
      if (r.error) {
        toast.error(r.error)
        // optimistic auto-reverte porque transição não persistiu o valor
      } else {
        toast.success(next ? `${jobname} ativado` : `${jobname} desativado`)
      }
      router.refresh()
    })
  }

  function saveSchedule() {
    if (draft.trim() === schedule) {
      setEditing(false)
      return
    }
    startTransition(async () => {
      const r = await updateCronScheduleAction(jobname, draft)
      if (r.error) {
        toast.error(r.error)
      } else {
        toast.success(`Schedule atualizado pra "${draft.trim()}"`)
        setEditing(false)
        router.refresh()
      }
    })
  }

  function runNow() {
    if (
      !confirm(
        `Disparar "${jobname}" agora?\n\nIsso executa o command do cron imediatamente, fora do schedule.`,
      )
    )
      return
    startTransition(async () => {
      const r = await runCronNowAction(jobname)
      if (r.error) toast.error(r.error)
      else toast.success(`${jobname} executado — aguarde efeitos`)
      router.refresh()
    })
  }

  return (
    <div className="flex items-center gap-1.5 flex-wrap mt-2">
      {editing ? (
        <>
          <Input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="ex: 0 9 * * *"
            className="h-7 w-44 text-xs font-mono"
            autoFocus
            onKeyDown={(e) => e.key === 'Enter' && saveSchedule()}
            disabled={pending}
          />
          <Button
            size="sm"
            onClick={saveSchedule}
            disabled={pending || !draft.trim()}
            className="h-7 text-xs"
          >
            {pending && <Loader2 className="h-3 w-3 mr-1 animate-spin" />}
            Salvar
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              setEditing(false)
              setDraft(schedule)
            }}
            disabled={pending}
            className="h-7 text-xs"
          >
            <X className="h-3 w-3" />
          </Button>
        </>
      ) : (
        <>
          <Button
            size="sm"
            variant="outline"
            onClick={() => setEditing(true)}
            disabled={pending}
            className="h-7 text-xs"
          >
            <Pencil className="h-3 w-3 mr-1" />
            Editar
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={toggle}
            disabled={pending}
            className={`h-7 text-xs ${optimisticActive ? 'text-rose-700 hover:bg-rose-500/10' : 'text-moss-700 hover:bg-moss-500/10'}`}
          >
            <Power className="h-3 w-3 mr-1" />
            {optimisticActive ? 'Desativar' : 'Ativar'}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={runNow}
            disabled={pending}
            className="h-7 text-xs text-amber-700 hover:bg-amber-500/10"
          >
            <Play className="h-3 w-3 mr-1" />
            Rodar agora
          </Button>
        </>
      )}
    </div>
  )
}
