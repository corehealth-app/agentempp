'use client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import { ArrowRight, Check } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [loading, setLoading] = useState(false)
  const [sent, setSent] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
    })
    setLoading(false)
    if (error) {
      toast.error(error.message)
      return
    }
    setSent(true)
    toast.success('Link de acesso enviado')
  }

  return (
    <div className="min-h-screen flex">
      {/* === Left: brand panel === */}
      <aside className="hidden lg:flex lg:w-1/2 bg-ink-900 text-cream-100 relative overflow-hidden">
        {/* dot grid background */}
        <div
          className="absolute inset-0 opacity-[0.04]"
          style={{
            backgroundImage:
              'radial-gradient(circle at 1px 1px, currentColor 1px, transparent 0)',
            backgroundSize: '24px 24px',
          }}
          aria-hidden
        />

        {/* moss accent */}
        <div className="absolute -bottom-40 -right-40 w-[600px] h-[600px] rounded-full bg-moss-700/20 blur-3xl" aria-hidden />

        <div className="relative z-10 flex flex-col justify-between w-full p-12">
          {/* Header */}
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-sm bg-cream-100 text-ink-900 flex items-center justify-center font-display text-xl font-medium">
              M
            </div>
            <div className="flex flex-col leading-tight">
              <span className="font-display text-lg tracking-tight">Agente MPP</span>
              <span className="text-[10px] tracking-widest uppercase text-cream-100/50 font-mono">
                CoreHealth · Painel
              </span>
            </div>
          </div>

          {/* Quote / value prop */}
          <div className="space-y-8 max-w-md">
            <div className="chapter-num text-cream-100/40">— Método Muscular Power Plant</div>
            <blockquote className="font-display text-3xl leading-tight text-balance">
              Não é dieta.
              <br />
              <span className="italic text-moss-300">É método.</span>
            </blockquote>
            <p className="text-cream-100/60 text-sm leading-relaxed max-w-sm">
              Coach nutricional via WhatsApp. Cálculo determinístico via TACO,
              gamificação por blocos de 7&thinsp;700&nbsp;kcal, voz custom do
              Dr.&nbsp;Roberto&nbsp;Menescal.
            </p>
          </div>

          {/* Footer */}
          <div className="grid grid-cols-3 gap-6 text-xs font-mono text-cream-100/40 uppercase tracking-widest">
            <div>
              <div className="text-cream-100/80 num text-base mb-1">88</div>
              regras de comportamento
            </div>
            <div>
              <div className="text-cream-100/80 num text-base mb-1">06</div>
              sub-agentes
            </div>
            <div>
              <div className="text-cream-100/80 num text-base mb-1">7700</div>
              kcal · 1 bloco
            </div>
          </div>
        </div>
      </aside>

      {/* === Right: form === */}
      <main className="flex-1 flex items-center justify-center px-6 py-12 bg-cream-100 paper">
        <div className="w-full max-w-md space-y-10 animate-fade-up">
          {/* Mobile logo */}
          <div className="lg:hidden flex items-center gap-3 mb-8">
            <div className="h-9 w-9 rounded-sm bg-ink-900 text-cream-100 flex items-center justify-center font-display text-lg font-medium">
              M
            </div>
            <div className="flex flex-col leading-tight">
              <span className="font-display text-base tracking-tight">Agente MPP</span>
              <span className="text-[10px] tracking-widest uppercase text-ink-500 font-mono">
                CoreHealth
              </span>
            </div>
          </div>

          {/* Header */}
          <div className="space-y-3">
            <div className="section-eyebrow">Painel administrativo</div>
            <h1 className="display text-5xl text-ink-900">
              {sent ? 'Verifique seu email' : 'Entrar'}
            </h1>
            <p className="text-ink-500 text-pretty">
              {sent
                ? 'Enviamos um link de acesso. Pode demorar alguns segundos.'
                : 'Receba um link mágico no seu email. Sem senhas.'}
            </p>
          </div>

          {sent ? (
            <div className="space-y-4">
              <div className="flex items-start gap-3 p-4 border border-moss-200 bg-moss-50 rounded">
                <Check className="h-5 w-5 text-moss-600 shrink-0 mt-0.5" />
                <div className="text-sm">
                  <div className="font-medium text-ink-900">Link enviado</div>
                  <div className="text-ink-600 mt-0.5 font-mono text-xs">{email}</div>
                </div>
              </div>
              <button
                onClick={() => {
                  setSent(false)
                  setEmail('')
                }}
                className="text-sm text-ink-500 hover:text-ink-900 underline underline-offset-4 focus-ring rounded px-1 -mx-1"
              >
                Usar outro email
              </button>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-5">
              <div className="space-y-2">
                <label htmlFor="email" className="section-eyebrow">
                  Email autorizado
                </label>
                <Input
                  id="email"
                  type="email"
                  placeholder="seu@corehealth.com"
                  required
                  autoFocus
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="h-12 font-mono text-sm bg-cream-50 border-ink-300 focus:border-ink-900"
                />
              </div>
              <Button
                type="submit"
                className="w-full h-12 bg-ink-900 hover:bg-ink-800 text-cream-100 group rounded-sm font-medium tracking-tight"
                disabled={loading}
              >
                {loading ? (
                  'Enviando…'
                ) : (
                  <>
                    Receber link de acesso
                    <ArrowRight className="h-4 w-4 ml-2 transition-transform group-hover:translate-x-0.5" />
                  </>
                )}
              </Button>
              <p className="text-xs text-ink-500 leading-relaxed pt-2">
                Apenas emails cadastrados em <code className="font-mono text-[11px] text-ink-700 bg-cream-200 px-1.5 py-0.5 rounded">admin_users</code> têm acesso ao painel. Pacientes conversam direto pelo WhatsApp.
              </p>
            </form>
          )}

          {/* Footer note */}
          <div className="hairline pt-6 flex items-center justify-between text-[10px] font-mono uppercase tracking-widest text-ink-500">
            <span>v1.0 · MMXXVI</span>
            <span>—</span>
            <span>CoreHealth</span>
          </div>
        </div>
      </main>
    </div>
  )
}
