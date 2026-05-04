'use client'

import { Check, Globe, Loader2 } from 'lucide-react'
import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { confirmCountryAction } from './actions'

const COMMON_COUNTRIES = ['BR', 'PT', 'US', 'ES', 'MX', 'AR', 'CL', 'CO', 'GB', 'CA']

/**
 * Botão de confirmação manual de país.
 *
 * Mostra apenas quando country_confirmed=false. Pré-seleciona o country
 * já detectado (do DDI ou guess). Admin pode trocar pra outro ISO antes
 * de confirmar (ex: detected=BR mas paciente é PT que mora aqui).
 */
export function CountryConfirmButton({
  userId,
  detectedCountry,
}: {
  userId: string
  detectedCountry: string | null
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [editing, setEditing] = useState(false)
  const [iso, setIso] = useState((detectedCountry ?? 'BR').toUpperCase())

  function confirm(target: string) {
    startTransition(async () => {
      const r = await confirmCountryAction(userId, target)
      if (r.error) toast.error(r.error)
      else {
        toast.success(`País confirmado: ${target}`)
        setEditing(false)
        router.refresh()
      }
    })
  }

  if (!editing) {
    return (
      <Button
        size="sm"
        variant="outline"
        onClick={() => setEditing(true)}
        disabled={pending}
        className="h-7 text-xs text-amber-700 border-amber-500/30 hover:bg-amber-500/10"
        title="Marcar país como confirmado pelo paciente"
      >
        <Globe className="h-3 w-3 mr-1" />
        Confirmar país
      </Button>
    )
  }

  return (
    <div className="inline-flex items-center gap-1.5 flex-wrap">
      <Input
        value={iso}
        onChange={(e) => setIso(e.target.value.toUpperCase().slice(0, 2))}
        placeholder="BR"
        className="h-7 w-16 text-xs font-mono uppercase"
        maxLength={2}
        autoFocus
        onKeyDown={(e) => e.key === 'Enter' && confirm(iso)}
        disabled={pending}
      />
      <Button
        size="sm"
        onClick={() => confirm(iso)}
        disabled={pending || iso.length !== 2}
        className="h-7 text-xs bg-moss-700 hover:bg-moss-800 text-cream-100"
      >
        {pending ? <Loader2 className="h-3 w-3 mr-1 animate-spin" /> : <Check className="h-3 w-3 mr-1" />}
        Confirmar
      </Button>
      <div className="flex gap-0.5">
        {COMMON_COUNTRIES.slice(0, 5).map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => setIso(c)}
            disabled={pending}
            className={`text-[10px] font-mono px-1.5 py-0.5 rounded border ${
              iso === c
                ? 'border-moss-500 bg-moss-500/10 text-moss-700'
                : 'border-border text-muted-foreground hover:bg-muted'
            }`}
          >
            {c}
          </button>
        ))}
      </div>
      <button
        type="button"
        onClick={() => setEditing(false)}
        disabled={pending}
        className="text-[10px] text-muted-foreground hover:text-foreground underline"
      >
        cancelar
      </button>
    </div>
  )
}
