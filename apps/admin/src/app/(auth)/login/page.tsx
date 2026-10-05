'use client'
import { BrandSymbol } from '@/components/brand-symbol'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import { ArrowRight, Check, Lock, Mail } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { toast } from 'sonner'

type Mode = 'password' | 'magic'

export default function LoginPage() {
  const router = useRouter()
  const [mode, setMode] = useState<Mode>('password')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [sent, setSent] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    const supabase = createClient()

    if (mode === 'password') {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      setLoading(false)
      if (error) {
        toast.error(error.message)
        return
      }
      toast.success('Entrando…')
      router.push('/dashboard')
      router.refresh()
    } else {
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
  }

  return (
    <div className="min-h-screen flex">
      {/* === Left: brand panel (fundo de marca do app, #003B3B) === */}
      <aside className="hidden lg:flex lg:w-1/2 bg-[#003B3B] text-cream-100 relative overflow-hidden">
        <div
          className="absolute inset-0 opacity-[0.04]"
          style={{
            backgroundImage:
              'radial-gradient(circle at 1px 1px, currentColor 1px, transparent 0)',
            backgroundSize: '24px 24px',
          }}
          aria-hidden
        />
        <div
          className="absolute -bottom-40 -right-40 w-[600px] h-[600px] rounded-full bg-primary/40 blur-3xl"
          aria-hidden
        />

        <div className="relative z-10 flex flex-col justify-between w-full p-12">
          <div className="flex items-center gap-3">
            <BrandSymbol variant="negative" size={40} className="h-10 w-10 shrink-0" />
            <div className="flex flex-col leading-tight">
              <span className="font-display text-lg tracking-tight">Performe AI</span>
              <span className="text-[10px] tracking-widest uppercase text-cream-100/50 font-mono">
                Painel
              </span>
            </div>
          </div>

          <div className="space-y-6 max-w-md">
            <p className="font-display text-4xl leading-tight text-balance">Melhor a cada dia.</p>
            <p className="font-display text-xl leading-snug text-cream-100/80">
              Flow, seu guia em cada etapa.
            </p>
            <p className="text-cream-100/60 text-sm leading-relaxed max-w-sm">
              Painel da equipe: conteúdo da Biblioteca, regras do Flow, cálculos e contas do app.
            </p>
          </div>

          {/* Mantém a composição em três faixas (marca · mensagem · respiro). */}
          <div aria-hidden />
        </div>
      </aside>

      {/* === Right: form === */}
      <main className="flex-1 flex items-center justify-center px-6 py-12 bg-cream-100 paper">
        <div className="w-full max-w-md space-y-10 animate-fade-up">
          {/* Mobile logo */}
          <div className="lg:hidden flex items-center gap-3 mb-8">
            <BrandSymbol variant="light" size={36} className="h-9 w-9 shrink-0" />
            <div className="flex flex-col leading-tight">
              <span className="font-display text-base tracking-tight">Performe AI</span>
              <span className="text-[10px] tracking-widest uppercase text-ink-500 font-mono">
                Painel
              </span>
            </div>
          </div>

          <div className="space-y-3">
            <div className="section-eyebrow">Painel administrativo</div>
            <h1 className="text-display-xl text-ink-900">
              {sent ? 'Verifique seu email' : 'Entrar'}
            </h1>
            <p className="text-ink-500 text-pretty">
              {sent
                ? 'Enviamos um link de acesso. Pode demorar alguns segundos.'
                : mode === 'password'
                  ? 'Entre com email e senha cadastrada.'
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
                Voltar
              </button>
            </div>
          ) : (
            <>
              {/* Tabs */}
              <div className="flex gap-1 p-1 bg-cream-200 rounded-sm w-fit">
                <button
                  type="button"
                  onClick={() => setMode('password')}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-sm text-xs font-mono uppercase tracking-wider transition ${
                    mode === 'password'
                      ? 'bg-cream-50 text-ink-900 shadow-sm'
                      : 'text-ink-500 hover:text-ink-900'
                  }`}
                >
                  <Lock className="h-3 w-3" />
                  Senha
                </button>
                <button
                  type="button"
                  onClick={() => setMode('magic')}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-sm text-xs font-mono uppercase tracking-wider transition ${
                    mode === 'magic'
                      ? 'bg-cream-50 text-ink-900 shadow-sm'
                      : 'text-ink-500 hover:text-ink-900'
                  }`}
                >
                  <Mail className="h-3 w-3" />
                  Magic Link
                </button>
              </div>

              <form onSubmit={handleSubmit} className="space-y-5">
                <div className="space-y-2">
                  <label htmlFor="email" className="section-eyebrow">
                    Email autorizado
                  </label>
                  <Input
                    id="email"
                    type="email"
                    placeholder="voce@exemplo.com"
                    required
                    autoFocus
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="h-12 font-mono text-sm bg-cream-50 border-ink-300 focus:border-ink-900"
                  />
                </div>

                {mode === 'password' && (
                  <div className="space-y-2 animate-fade-in">
                    <label htmlFor="password" className="section-eyebrow">
                      Senha
                    </label>
                    <Input
                      id="password"
                      type="password"
                      placeholder="••••••••"
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      className="h-12 font-mono text-sm bg-cream-50 border-ink-300 focus:border-ink-900"
                    />
                  </div>
                )}

                <Button
                  type="submit"
                  className="w-full h-12 bg-ink-900 hover:bg-ink-800 text-cream-100 group rounded-sm font-medium tracking-tight"
                  disabled={loading}
                >
                  {loading
                    ? 'Aguarde…'
                    : mode === 'password'
                      ? (
                          <>
                            Entrar
                            <ArrowRight className="h-4 w-4 ml-2 transition-transform group-hover:translate-x-0.5" />
                          </>
                        )
                      : (
                          <>
                            Receber link de acesso
                            <ArrowRight className="h-4 w-4 ml-2 transition-transform group-hover:translate-x-0.5" />
                          </>
                        )}
                </Button>

                <p className="text-xs text-ink-500 leading-relaxed pt-2">
                  Apenas e-mails cadastrados como administradores têm acesso ao painel.
                </p>
              </form>
            </>
          )}

          <div className="hairline pt-6 flex items-center justify-between text-[10px] font-mono uppercase tracking-widest text-ink-500">
            <span>v1.0 · MMXXVI</span>
            <span>—</span>
            <span>Performe AI</span>
          </div>
        </div>
      </main>
    </div>
  )
}
