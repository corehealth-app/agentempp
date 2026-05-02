'use client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Activity, Bot, DollarSign, RotateCcw, Send, User, Wrench, Zap } from 'lucide-react'
import Link from 'next/link'
import { useEffect, useMemo, useRef, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { resetPlaygroundUser, runPlayground } from './actions'

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

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [turns])

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
    })
  }

  async function reset() {
    if (!confirm(`Apagar usuário ${wpp} e iniciar nova conversa?`)) return
    const r = await resetPlaygroundUser(wpp)
    if (r.error) toast.error(r.error)
    else {
      toast.success('Conversa resetada')
      setTurns([])
    }
  }

  // Métricas acumuladas
  const stats = useMemo(() => {
    const meta = turns.filter((t) => t.meta).map((t) => t.meta!)
    const totalTokens = meta.reduce((s, m) => s + m.tokens.in + m.tokens.out, 0)
    const totalCost = meta.reduce((s, m) => s + (m.cost_usd ?? 0), 0)
    const avgLatency =
      meta.length > 0 ? Math.round(meta.reduce((s, m) => s + m.latency_ms, 0) / meta.length) : 0
    const lastStage = meta.at(-1)?.stage ?? null
    const lastModel = meta.at(-1)?.model ?? null
    const tools = meta.flatMap((m) => m.tools)
    return { totalTokens, totalCost, avgLatency, lastStage, lastModel, tools }
  }, [turns])

  return (
    <div className="grid gap-3 lg:grid-cols-[1fr_280px]">
      {/* === Coluna principal: chat === */}
      <div className="border border-border bg-cream-50 rounded-sm overflow-hidden">
        {/* Header */}
        <div className="border-b border-border bg-cream-100 px-5 py-3 flex items-center gap-3">
        <div className="flex-1 flex items-center gap-3">
          <span className="section-eyebrow">Número simulado</span>
          <Input
            value={wpp}
            onChange={(e) => setWpp(e.target.value)}
            className="h-8 max-w-[200px] font-mono text-xs bg-cream-50 border-border"
          />
        </div>
        <Button
          size="sm"
          variant="ghost"
          onClick={reset}
          className="text-ink-500 hover:text-ink-900 hover:bg-cream-200 rounded-sm"
        >
          <RotateCcw className="h-3.5 w-3.5 mr-1.5" />
          Resetar
        </Button>
      </div>

      {/* Conversation */}
      <div ref={scrollRef} className="h-[520px] overflow-y-auto px-5 py-6 space-y-6">
        {turns.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-center max-w-md mx-auto">
            <div className="font-mono text-[10px] uppercase tracking-widest text-ink-400 mb-3">
              Pronto para conversar
            </div>
            <h3 className="font-display text-2xl text-ink-900 tracking-tight mb-2">
              Comece uma conversa
            </h3>
            <p className="text-sm text-ink-500">
              Cada mensagem aqui passa pela mesma pipeline que o WhatsApp usaria — incluindo
              regras, tools e cálculo TACO.
            </p>
            <div className="mt-6 flex flex-wrap gap-2 justify-center">
              {[
                'Oi, meu nome é Eduardo',
                'almocei 150g de arroz e 120g de frango',
                'como estou indo?',
              ].map((suggestion) => (
                <button
                  key={suggestion}
                  onClick={() => setInput(suggestion)}
                  className="text-xs px-3 py-1.5 rounded-sm border border-border bg-cream-50 hover:bg-cream-200 transition-colors"
                >
                  {suggestion}
                </button>
              ))}
            </div>
          </div>
        ) : (
          turns.map((t, i) => (
            <div
              key={i}
              className={`flex gap-3 ${t.role === 'user' ? 'flex-row-reverse' : ''} animate-fade-up`}
            >
              <div
                className={`shrink-0 h-7 w-7 rounded-sm flex items-center justify-center ${
                  t.role === 'user'
                    ? 'bg-ink-900 text-cream-100'
                    : 'bg-moss-700 text-cream-100'
                }`}
              >
                {t.role === 'user' ? (
                  <User className="h-3.5 w-3.5" />
                ) : (
                  <Bot className="h-3.5 w-3.5" />
                )}
              </div>
              <div className={`max-w-[78%] ${t.role === 'user' ? 'text-right' : ''}`}>
                <div className="text-[10px] uppercase tracking-widest font-mono text-ink-500 mb-1">
                  {t.role === 'user' ? 'Você' : `Agente · ${t.meta?.stage ?? ''}`}
                </div>
                <div
                  className={`text-sm whitespace-pre-wrap rounded-sm px-4 py-3 ${
                    t.role === 'user'
                      ? 'bg-ink-900 text-cream-100'
                      : 'bg-cream-100 border border-border text-ink-900'
                  }`}
                >
                  {t.content}
                </div>
                {t.meta && (
                  <div className="mt-1.5 flex items-center gap-3 text-[10px] font-mono text-ink-500 flex-wrap">
                    <span>
                      <span className="num">{t.meta.tokens.in + t.meta.tokens.out}</span> tok
                    </span>
                    <span>·</span>
                    <span>
                      $<span className="num">{t.meta.cost_usd?.toFixed(5) ?? '?'}</span>
                    </span>
                    <span>·</span>
                    <span>
                      <span className="num">{t.meta.latency_ms}</span>ms
                    </span>
                    {t.meta.tools.length > 0 && (
                      <>
                        <span>·</span>
                        {t.meta.tools.map((tool) => (
                          <code
                            key={tool.name}
                            className={`text-[10px] px-1.5 py-0.5 rounded ${
                              tool.success
                                ? 'bg-moss-100 text-moss-700'
                                : 'bg-red-100 text-red-700'
                            }`}
                          >
                            {tool.name}
                          </code>
                        ))}
                      </>
                    )}
                  </div>
                )}
              </div>
            </div>
          ))
        )}
        {pending && (
          <div className="flex gap-3 animate-fade-in">
            <div className="shrink-0 h-7 w-7 rounded-sm bg-moss-700 text-cream-100 flex items-center justify-center">
              <Bot className="h-3.5 w-3.5" />
            </div>
            <div className="bg-cream-100 border border-border rounded-sm px-4 py-3 text-sm text-ink-500 italic">
              <span className="inline-flex gap-1">
                <span className="h-1 w-1 rounded-full bg-ink-500 animate-pulse" />
                <span className="h-1 w-1 rounded-full bg-ink-500 animate-pulse [animation-delay:0.2s]" />
                <span className="h-1 w-1 rounded-full bg-ink-500 animate-pulse [animation-delay:0.4s]" />
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Input */}
      <div className="border-t border-border bg-cream-100 p-3">
        <div className="flex gap-2 items-end">
          <textarea
            rows={2}
            value={input}
            placeholder="Mensagem (Enter para enviar)"
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                send()
              }
            }}
            disabled={pending}
            className="flex-1 resize-none bg-cream-50 border border-border rounded-sm px-3 py-2 text-sm placeholder:text-ink-400 focus:outline-none focus:border-ink-900"
          />
          <Button
            onClick={send}
            disabled={pending || !input.trim()}
            className="h-[60px] w-[60px] shrink-0 bg-ink-900 hover:bg-ink-800 text-cream-100 rounded-sm"
          >
            <Send className="h-4 w-4" />
          </Button>
        </div>
        </div>
      </div>

      {/* === Sidebar: métricas + config ativa === */}
      <div className="space-y-3">
        <div className="content-card p-4 space-y-3">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Métricas da sessão
          </div>
          <Stat
            icon={Activity}
            label="Tokens totais"
            value={stats.totalTokens.toLocaleString('pt-BR')}
          />
          <Stat icon={DollarSign} label="Custo total" value={`$${stats.totalCost.toFixed(5)}`} />
          <Stat icon={Zap} label="Latência média" value={`${stats.avgLatency} ms`} />
          <Stat icon={Wrench} label="Tool calls" value={stats.tools.length.toString()} />
        </div>

        <div className="content-card p-4 space-y-2">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Estado atual
          </div>
          <div className="space-y-1.5 text-xs">
            <Row label="Stage">
              {stats.lastStage ? (
                <code className="font-mono text-foreground">{stats.lastStage}</code>
              ) : (
                <span className="text-muted-foreground">aguardando</span>
              )}
            </Row>
            <Row label="Modelo">
              {stats.lastModel ? (
                <code className="font-mono text-foreground text-[11px]">{stats.lastModel}</code>
              ) : (
                <span className="text-muted-foreground">aguardando</span>
              )}
            </Row>
            <Row label="Turnos">{turns.length}</Row>
          </div>
          <Link
            href="/settings/agents"
            className="block mt-3 text-[11px] text-moss-700 hover:underline"
          >
            Editar configuração →
          </Link>
        </div>

        <div className="content-card p-4 space-y-2">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Tools usadas
          </div>
          {stats.tools.length === 0 ? (
            <p className="text-xs text-muted-foreground italic">nenhuma ainda</p>
          ) : (
            <ul className="space-y-1">
              {Object.entries(
                stats.tools.reduce<Record<string, { ok: number; fail: number }>>((acc, t) => {
                  acc[t.name] ??= { ok: 0, fail: 0 }
                  if (t.success) acc[t.name]!.ok++
                  else acc[t.name]!.fail++
                  return acc
                }, {}),
              ).map(([name, c]) => (
                <li key={name} className="flex items-center justify-between text-[11px]">
                  <code className="font-mono">{name}</code>
                  <span className="font-mono">
                    {c.ok > 0 && <span className="text-moss-600">{c.ok}✓</span>}
                    {c.fail > 0 && <span className="text-rose-500 ml-1">{c.fail}✗</span>}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <Link
            href="/audit"
            className="block mt-2 text-[11px] text-moss-700 hover:underline"
          >
            Auditoria detalhada →
          </Link>
        </div>
      </div>
    </div>
  )
}

function Stat({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: string
}) {
  return (
    <div className="flex items-center justify-between gap-2 text-xs">
      <span className="flex items-center gap-2 text-muted-foreground">
        <Icon className="h-3.5 w-3.5" />
        {label}
      </span>
      <span className="font-mono tabular-nums text-foreground">{value}</span>
    </div>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="text-muted-foreground">{label}</span>
      <span>{children}</span>
    </div>
  )
}
