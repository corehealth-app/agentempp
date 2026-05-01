'use client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Send, Trash2 } from 'lucide-react'
import { useRef, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { runPlayground, resetPlaygroundUser } from './actions'

interface Turn {
  role: 'user' | 'assistant'
  content: string
  meta?: {
    stage: string
    model: string
    tokens: { in: number; out: number }
    cost_usd: number | null
    latency_ms: number
    tools: Array<{ name: string; success: boolean }>
  }
}

export function PlaygroundForm() {
  const [wpp, setWpp] = useState('5511999999999')
  const [input, setInput] = useState('')
  const [turns, setTurns] = useState<Turn[]>([])
  const [pending, startTransition] = useTransition()
  const scrollRef = useRef<HTMLDivElement>(null)

  function send() {
    if (!input.trim() || pending) return
    const text = input.trim()
    setTurns((t) => [...t, { role: 'user', content: text }])
    setInput('')

    startTransition(async () => {
      const r = await runPlayground({ from: wpp, text })
      if (r.error) {
        toast.error(r.error)
        return
      }
      setTurns((t) => [
        ...t,
        {
          role: 'assistant',
          content: r.text ?? '',
          meta: {
            stage: r.stage ?? '?',
            model: r.model ?? '?',
            tokens: { in: r.prompt_tokens ?? 0, out: r.completion_tokens ?? 0 },
            cost_usd: r.cost_usd ?? null,
            latency_ms: r.latency_ms ?? 0,
            tools: r.tools ?? [],
          },
        },
      ])
      setTimeout(() => {
        scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
      }, 100)
    })
  }

  async function reset() {
    if (!confirm(`Apagar usuário ${wpp} e todas as mensagens dele?`)) return
    const r = await resetPlaygroundUser(wpp)
    if (r.error) toast.error(r.error)
    else {
      toast.success('Usuário resetado')
      setTurns([])
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-2 items-end">
        <div className="flex-1 space-y-1.5">
          <Label htmlFor="wpp">Número simulado (E.164 sem +)</Label>
          <Input id="wpp" value={wpp} onChange={(e) => setWpp(e.target.value)} />
        </div>
        <Button variant="outline" onClick={reset}>
          <Trash2 className="h-4 w-4 mr-1" />
          Resetar
        </Button>
      </div>

      <div
        ref={scrollRef}
        className="border rounded-lg bg-muted/30 h-[500px] overflow-y-auto p-4 space-y-3"
      >
        {turns.length === 0 ? (
          <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
            Comece digitando uma mensagem abaixo. O agente responderá usando o stage apropriado.
          </div>
        ) : (
          turns.map((t, i) => (
            <div
              key={i}
              className={`flex ${t.role === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-[80%] rounded-lg p-3 ${
                  t.role === 'user'
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-card border'
                }`}
              >
                <div className="whitespace-pre-wrap text-sm">{t.content}</div>
                {t.meta && (
                  <div className="mt-2 pt-2 border-t border-border/50 text-xs opacity-70 space-y-0.5">
                    <div>
                      stage=<code>{t.meta.stage}</code> · model=
                      <code className="text-[10px]">{t.meta.model}</code>
                    </div>
                    <div>
                      tokens={t.meta.tokens.in}+{t.meta.tokens.out} · ${' '}
                      {t.meta.cost_usd?.toFixed(5) ?? '?'} · {t.meta.latency_ms}ms
                    </div>
                    {t.meta.tools.length > 0 && (
                      <div>
                        tools:{' '}
                        {t.meta.tools.map((tool) => (
                          <code
                            key={tool.name}
                            className={`text-[10px] mr-1 ${tool.success ? '' : 'text-red-500'}`}
                          >
                            {tool.name}
                            {!tool.success && '✗'}
                          </code>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          ))
        )}
        {pending && (
          <div className="flex justify-start">
            <div className="bg-card border rounded-lg p-3 text-sm text-muted-foreground">
              ✏️ pensando…
            </div>
          </div>
        )}
      </div>

      <div className="flex gap-2 items-end">
        <Textarea
          rows={2}
          value={input}
          placeholder="Mensagem (Enter para enviar, Shift+Enter para nova linha)"
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              send()
            }
          }}
          disabled={pending}
          className="resize-none"
        />
        <Button onClick={send} disabled={pending || !input.trim()}>
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </div>
  )
}
