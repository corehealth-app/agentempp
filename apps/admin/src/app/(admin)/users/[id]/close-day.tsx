'use client'
import { Button } from '@/components/ui/button'
import { Lock } from 'lucide-react'
import { useTransition } from 'react'
import { toast } from 'sonner'
import { useRouter } from 'next/navigation'
import { closeDay } from './actions'

export function CloseDayButton({ userId, date }: { userId: string; date: string }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()

  function onClose() {
    startTransition(async () => {
      const r = await closeDay(userId, date)
      if (r.error) toast.error(r.error)
      else {
        toast.success(
          `Dia fechado: streak=${r.result?.streak} XP=${r.result?.xp_total} blocks=${r.result?.blocks_completed}`,
        )
        router.refresh()
      }
    })
  }

  return (
    <Button size="sm" variant="outline" onClick={onClose} disabled={pending}>
      <Lock className="h-3 w-3 mr-1" />
      Fechar dia
    </Button>
  )
}
