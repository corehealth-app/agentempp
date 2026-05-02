'use client'

import { AlertTriangle, RefreshCw } from 'lucide-react'
import Link from 'next/link'
import { useEffect } from 'react'
import { Button } from '@/components/ui/button'

/**
 * Error boundary local pra /users/[id]. Quando algum fetch falha ou
 * o render quebra, mostra fallback amigável em vez do screen branco.
 */
export default function UserDetailError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('UserDetailError', error)
  }, [error])

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] p-6 text-center">
      <div className="glass-card p-8 max-w-lg space-y-4">
        <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
        <h1 className="font-display text-2xl tracking-tight">Não foi possível carregar este paciente</h1>
        <p className="text-sm text-muted-foreground">
          Houve um erro ao buscar ou renderizar os dados. Pode ser um estado
          inconsistente após reset/exclusão recente, ou uma query que retornou
          algo inesperado.
        </p>
        {error.digest && (
          <code className="block text-[10px] font-mono text-muted-foreground/70 break-all">
            digest: {error.digest}
          </code>
        )}
        {error.message && (
          <code className="block text-xs font-mono bg-muted px-2 py-1 rounded text-foreground/80 break-all max-h-32 overflow-y-auto">
            {error.message}
          </code>
        )}
        <div className="flex gap-2 justify-center pt-2">
          <Button variant="outline" onClick={reset}>
            <RefreshCw className="h-4 w-4 mr-1.5" />
            Tentar novamente
          </Button>
          <Button asChild>
            <Link href="/users">Voltar pra lista</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}
