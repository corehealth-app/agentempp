import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import type { ModerationActionPort } from '@/lib/journey-moderation/action-contracts'
import { moderationActionResult } from '@/lib/journey-moderation/action-contracts'
import {
  createModerationPanelModel,
  type ModerationPanelModel,
  type ModerationPanelState,
} from '@/lib/journey-moderation/panel-model'
import { createBrowserModerationStore } from '@/lib/journey-moderation/pending-store'

const reasons = {
  nickname: 'Apelido inadequado',
  harassment: 'Assédio',
  spam: 'Spam',
  other: 'Outro motivo',
}
const stamp = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
/** Internal client component: the connected boundary owns Auth invalidation. */
export function ModerationPanel({
  initial,
  action,
  watchSession,
}: {
  initial: unknown
  action: ModerationActionPort
  watchSession: (close: () => void) => () => void
}) {
  const [state, setState] = useState<Readonly<ModerationPanelState> | null>(null)
  const [lookup, setLookup] = useState('')
  const model = useRef<ModerationPanelModel | null>(null)
  useEffect(() => {
    const boot = moderationActionResult.parse(initial)
    if (!boot.ok || boot.type !== 'queue') return
    let current: ModerationPanelModel
    try {
      current = createModerationPanelModel(
        boot,
        action,
        createBrowserModerationStore(boot.context),
        () => crypto.randomUUID(),
      )
    } catch {
      setState({
        ready: false,
        closed: true,
        busy: false,
        queue: null,
        profile: null,
        pending: null,
        error: 'Não foi possível abrir o armazenamento seguro desta página.',
        notice: null,
      })
      return
    }
    model.current = current
    setState(current.snapshot)
    const unsubscribe = current.subscribe(() => setState(current.snapshot))
    const stopWatching = watchSession(() => {
      setLookup('')
      current.close()
    })
    const onStorage = (event: StorageEvent) => {
      if (event.storageArea === window.localStorage) void current.syncPending()
    }
    window.addEventListener('storage', onStorage)
    void current.initialize()
    return () => {
      stopWatching()
      window.removeEventListener('storage', onStorage)
      unsubscribe()
      current.close()
      if (model.current === current) model.current = null
    }
  }, [initial, action, watchSession])
  const disabled = !state?.ready || state.busy || state.closed
  const writingDisabled = disabled || state.pending !== null
  if (!state) return <p role="status">Conferindo sessão e pendências…</p>
  if (state.closed)
    return (
      <div role="alert" className="glass-card p-6">
        <p>{state.error}</p>
        <a href="/journey-moderation" className="mt-3 inline-block underline">
          Reabrir moderação
        </a>
      </div>
    )
  return (
    <div className="space-y-6" aria-busy={state.busy}>
      {state.error ? (
        <p role="alert" className="rounded-lg border border-destructive/40 bg-destructive/10 p-4">
          {state.error}
        </p>
      ) : null}
      {state.notice ? (
        <p role="status" className="rounded-lg border border-primary/40 bg-primary/10 p-4">
          {state.notice}
        </p>
      ) : null}
      {state.pending ? (
        <section
          aria-labelledby="moderation-pending"
          className="glass-card border border-amber-500/40 p-5 space-y-3"
        >
          <h2 id="moderation-pending" className="text-lg font-semibold">
            Há uma operação pendente
          </h2>
          <p className="text-sm text-muted-foreground">
            A resposta ainda precisa ser conferida. Abrir esta tela não reenvia a ação. Verificar
            consulta o resultado ou cancela um envio que ainda não foi aplicado.
          </p>
          <p className="text-sm">
            {state.pending.request.kind === 'profile'
              ? 'Alteração de moderação do perfil'
              : 'Encerramento de denúncia'}
            {state.pending.context.login !== model.current?.context.login
              ? ' · sessão anterior'
              : ''}
          </p>
          <Button
            type="button"
            disabled={state.busy}
            onClick={() => {
              void model.current?.recover()
            }}
          >
            Verificar resultado ou cancelar envio
          </Button>
        </section>
      ) : null}
      <section aria-labelledby="moderation-profile" className="glass-card p-5 space-y-4">
        <h2 id="moderation-profile" className="text-lg font-semibold">
          Consultar participante
        </h2>
        <p className="text-sm text-muted-foreground">
          Use o identificador público para consultar ou restaurar um perfil, inclusive após encerrar
          uma denúncia. Restaurar não reinscreve quem retirou a participação.
        </p>
        <form
          className="flex flex-col gap-3 sm:flex-row sm:items-end"
          onSubmit={(event) => {
            event.preventDefault()
            void model.current?.selectMember(lookup.trim().toLowerCase())
          }}
        >
          <div className="flex-1">
            <label htmlFor="moderation-member" className="block text-sm font-medium mb-1">
              Identificador público
            </label>
            <input
              id="moderation-member"
              value={lookup}
              onChange={(event) => setLookup(event.target.value)}
              required
              maxLength={36}
              pattern="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
              autoComplete="off"
              spellCheck={false}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>
          <Button type="submit" variant="outline" disabled={disabled}>
            Consultar perfil
          </Button>
        </form>
        {state.profile ? (
          <div className="rounded-lg border border-border p-4 space-y-3">
            <p className="font-medium">{state.profile.nickname ?? 'Participação retirada'}</p>
            <p className="text-sm">
              Perfil {state.profile.moderation === 'active' ? 'liberado' : 'suspenso'} ·{' '}
              {state.profile.opted_in ? 'participação autorizada' : 'sem participação autorizada'}
            </p>
            <p className="text-xs text-muted-foreground break-all">
              Identificador público: {state.profile.member_id}
            </p>
            <p className="text-sm text-muted-foreground">
              Esta ação altera somente a moderação do perfil. Ela não encerra denúncias nem muda
              metas ou pontos.
            </p>
            <Button
              type="button"
              variant={state.profile.moderation === 'active' ? 'destructive' : 'outline'}
              disabled={writingDisabled}
              onClick={() => {
                void model.current?.moderate(
                  state.profile?.moderation === 'active' ? 'suspend' : 'restore',
                )
              }}
            >
              {state.profile.moderation === 'active' ? 'Suspender perfil' : 'Restaurar perfil'}
            </Button>
          </div>
        ) : null}
      </section>
      <section aria-labelledby="moderation-queue" className="glass-card p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="moderation-queue" className="text-lg font-semibold">
            Denúncias pendentes
          </h2>
          <Button
            type="button"
            variant="outline"
            disabled={state.busy}
            onClick={() => {
              void model.current?.refresh()
            }}
          >
            Atualizar fila
          </Button>
        </div>
        <p className="text-sm text-muted-foreground">
          Encerrar uma denúncia e suspender um perfil são decisões separadas. A lista mostra apenas
          o motivo e o perfil público denunciado.
        </p>
        {state.queue?.entries.length === 0 ? (
          <p>Nenhuma denúncia pendente nesta consulta.</p>
        ) : null}
        <ul className="space-y-4">
          {state.queue?.entries.map((entry) => (
            <li key={entry.report_id} className="rounded-lg border border-border p-4 space-y-3">
              <div className="flex flex-wrap justify-between gap-2">
                <h3 className="font-medium">{entry.nickname ?? 'Participação retirada'}</h3>
                <time dateTime={entry.created_at} className="text-xs text-muted-foreground">
                  {stamp.format(new Date(entry.created_at))}
                </time>
              </div>
              <p className="text-sm">
                {reasons[entry.reason]} · perfil{' '}
                {entry.moderation === 'active' ? 'liberado' : 'suspenso'}
              </p>
              <p className="text-xs text-muted-foreground break-all">
                Identificador público: {entry.member_id}
              </p>
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant="outline"
                  disabled={disabled}
                  onClick={() => {
                    setLookup(entry.member_id)
                    void model.current?.selectMember(entry.member_id)
                  }}
                >
                  Consultar este perfil
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  disabled={writingDisabled}
                  onClick={() => {
                    void model.current?.resolveReport(entry.report_id, 'resolved')
                  }}
                >
                  Encerrar como resolvida
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  disabled={writingDisabled}
                  onClick={() => {
                    void model.current?.resolveReport(entry.report_id, 'dismissed')
                  }}
                >
                  Arquivar sem ação
                </Button>
              </div>
            </li>
          ))}
        </ul>
        {state.queue?.next_cursor ? (
          <Button
            type="button"
            variant="outline"
            disabled={state.busy}
            onClick={() => {
              void model.current?.nextPage()
            }}
          >
            Carregar mais denúncias
          </Button>
        ) : null}
      </section>
    </div>
  )
}
