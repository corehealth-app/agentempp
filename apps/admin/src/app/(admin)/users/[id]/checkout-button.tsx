'use client'
import { CreditCard, ExternalLink, Loader2 } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'

export function CheckoutButton({ userId }: { userId: string }) {
  const [loading, setLoading] = useState<string | null>(null)
  const [url, setUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function generate(lookupKey: string) {
    setLoading(lookupKey)
    setError(null)
    setUrl(null)
    try {
      const r = await fetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user_id: userId, lookup_key: lookupKey }),
      })
      const data = await r.json()
      if (data.ok && data.url) {
        setUrl(data.url)
      } else {
        setError(data.error ?? 'erro desconhecido')
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoading(null)
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="outline"
          onClick={() => generate('mpp_mensal_v1')}
          disabled={!!loading}
        >
          {loading === 'mpp_mensal_v1' ? (
            <Loader2 className="mr-1.5 h-3 w-3 animate-spin" />
          ) : (
            <CreditCard className="mr-1.5 h-3 w-3" />
          )}
          Checkout Mensal (R$ 197)
        </Button>
        <Button
          size="sm"
          variant="default"
          onClick={() => generate('mpp_anual_v1')}
          disabled={!!loading}
        >
          {loading === 'mpp_anual_v1' ? (
            <Loader2 className="mr-1.5 h-3 w-3 animate-spin" />
          ) : (
            <CreditCard className="mr-1.5 h-3 w-3" />
          )}
          Checkout Anual (R$ 1.164)
        </Button>
      </div>

      {url && (
        <div className="glass-subtle p-3 space-y-2">
          <div className="text-[10px] font-mono uppercase tracking-widest text-moss-600">
            ✓ Checkout criado — link válido por 24h
          </div>
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs font-mono break-all underline text-foreground hover:text-moss-600 inline-flex items-start gap-1"
          >
            {url}
            <ExternalLink className="h-3 w-3 shrink-0 mt-0.5" />
          </a>
          <button
            onClick={() => navigator.clipboard.writeText(url)}
            className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground hover:text-foreground"
          >
            Copiar link →
          </button>
        </div>
      )}

      {error && (
        <div className="glass-subtle p-3 border-l-2 border-rose-500/50">
          <code className="text-xs text-rose-500">{error}</code>
        </div>
      )}
    </div>
  )
}
