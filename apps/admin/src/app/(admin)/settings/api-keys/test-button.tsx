'use client'
import { Button } from '@/components/ui/button'
import { testCredential } from './actions'
import { CheckCircle2, Loader2, XCircle } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'

export function TestCredentialButton({ service }: { service: string }) {
  const [pending, startTransition] = useTransition()
  const [last, setLast] = useState<'ok' | 'fail' | null>(null)

  function onTest() {
    startTransition(async () => {
      const r = await testCredential(service)
      if (r.error) {
        toast.error(`Teste falhou: ${r.error}`)
        setLast('fail')
        return
      }
      if (r.result === 'ok') {
        toast.success(`${service} OK`)
        setLast('ok')
      } else {
        toast.error(`${service}: ${r.result}`)
        setLast('fail')
      }
    })
  }

  return (
    <Button variant="outline" size="sm" onClick={onTest} disabled={pending}>
      {pending ? (
        <Loader2 className="h-3 w-3 animate-spin mr-1" />
      ) : last === 'ok' ? (
        <CheckCircle2 className="h-3 w-3 mr-1 text-green-500" />
      ) : last === 'fail' ? (
        <XCircle className="h-3 w-3 mr-1 text-red-500" />
      ) : null}
      Testar
    </Button>
  )
}
