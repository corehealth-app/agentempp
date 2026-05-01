'use client'
import { Loader2, Wand2 } from 'lucide-react'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'

interface Result {
  lookup_key: string
  product_id: string
  price_id: string
  created: boolean
}

export function SetupProductsButton({ enabled }: { enabled: boolean }) {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ ok: boolean; results?: Result[]; error?: string } | null>(
    null,
  )

  async function run() {
    setLoading(true)
    setResult(null)
    try {
      const r = await fetch('/api/stripe/setup-products', { method: 'POST' })
      const data = await r.json()
      setResult(data)
      if (data.ok) router.refresh()
    } catch (e) {
      setResult({ ok: false, error: e instanceof Error ? e.message : String(e) })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-3">
      <Button onClick={run} disabled={!enabled || loading} variant="default">
        {loading ? (
          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
        ) : (
          <Wand2 className="mr-2 h-4 w-4" />
        )}
        {loading ? 'Sincronizando...' : 'Sincronizar produtos no Stripe'}
      </Button>

      {!enabled && (
        <p className="text-xs text-rose-500">
          Adicione <code className="font-mono">stripe.secret_key</code> antes de rodar.
        </p>
      )}

      {result?.ok && result.results && (
        <div className="glass-subtle p-3 space-y-1.5">
          <div className="text-xs font-mono uppercase tracking-widest text-moss-600">
            ✓ {result.results.length} produto(s) sincronizado(s)
          </div>
          <ul className="text-xs space-y-1 font-mono">
            {result.results.map((r) => (
              <li key={r.lookup_key} className="flex items-center gap-2">
                <span
                  className={
                    r.created
                      ? 'px-1.5 py-0.5 bg-moss-500 text-cream-100 rounded text-[10px]'
                      : 'px-1.5 py-0.5 bg-muted-foreground/20 text-foreground/70 rounded text-[10px]'
                  }
                >
                  {r.created ? 'CRIADO' : 'EXISTIA'}
                </span>
                <span className="text-foreground">{r.lookup_key}</span>
                <span className="text-muted-foreground/70">→</span>
                <span className="text-muted-foreground/70">{r.price_id}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {result?.ok === false && result.error && (
        <div className="glass-subtle p-3 border-l-2 border-rose-500/50">
          <div className="text-xs font-mono uppercase tracking-widest text-rose-500 mb-1">
            ✗ Falha
          </div>
          <code className="text-xs whitespace-pre-wrap break-words">{result.error}</code>
        </div>
      )}
    </div>
  )
}
