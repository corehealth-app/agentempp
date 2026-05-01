import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { formatDateTime, formatUSD } from '@/lib/utils'
import Link from 'next/link'
import { Bot, ExternalLink, User as UserIcon } from 'lucide-react'

export default async function MessagesPage() {
  const svc = createServiceClient()
  const { data: messages } = await svc
    .from('messages')
    .select(
      'id, user_id, direction, content, content_type, agent_stage, model_used, prompt_tokens, completion_tokens, cost_usd, latency_ms, created_at',
    )
    .order('created_at', { ascending: false })
    .limit(100)

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Visão geral' }, { label: 'Mensagens' }]}
        title="Mensagens"
        description="Últimas 100 mensagens trocadas (entradas e saídas do agente)."
      />

      <ContentCard>
        {!messages || messages.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4">Sem mensagens ainda.</p>
        ) : (
          <ul className="space-y-3">
            {messages.map((m) => (
              <li
                key={m.id}
                className="glass-subtle p-3.5 hover:bg-muted/40 transition-colors"
              >
                {/* Header */}
                <div className="flex items-center justify-between gap-3 flex-wrap mb-2">
                  <div className="flex items-center gap-2">
                    <div
                      className={`shrink-0 h-6 w-6 rounded-md flex items-center justify-center ${
                        m.direction === 'in'
                          ? 'bg-ink-900 text-cream-100'
                          : 'bg-moss-700 text-cream-100'
                      }`}
                    >
                      {m.direction === 'in' ? (
                        <UserIcon className="h-3 w-3" />
                      ) : (
                        <Bot className="h-3 w-3" />
                      )}
                    </div>
                    <span className="text-[10px] uppercase tracking-widest font-mono text-muted-foreground">
                      {m.direction === 'in' ? 'usuário' : 'agente'}
                    </span>
                    {m.agent_stage && (
                      <span className="text-[10px] font-mono uppercase tracking-widest bg-moss-100 text-moss-700 px-1.5 py-0.5 rounded">
                        {m.agent_stage.replace('_', ' ')}
                      </span>
                    )}
                    {m.content_type !== 'text' && (
                      <span className="text-[10px] font-mono uppercase tracking-widest bg-cream-300 text-foreground/80 px-1.5 py-0.5 rounded">
                        {m.content_type}
                      </span>
                    )}
                    <Link
                      href={`/users/${m.user_id}`}
                      className="text-[10px] font-mono text-muted-foreground hover:text-foreground inline-flex items-center gap-0.5 underline-offset-2 hover:underline"
                    >
                      user
                      <ExternalLink className="h-2.5 w-2.5" />
                    </Link>
                  </div>
                  <div className="text-[10px] font-mono text-muted-foreground tabular-nums flex items-center gap-2">
                    {m.prompt_tokens != null && (
                      <span>
                        {m.prompt_tokens}+{m.completion_tokens} tok
                      </span>
                    )}
                    {m.cost_usd != null && <span>{formatUSD(Number(m.cost_usd), 5)}</span>}
                    {m.latency_ms != null && <span>{m.latency_ms}ms</span>}
                    <span>{formatDateTime(m.created_at)}</span>
                  </div>
                </div>

                {/* Content */}
                <div className="text-sm text-foreground whitespace-pre-wrap pl-8">
                  {m.content ?? <span className="italic text-muted-foreground">(mídia)</span>}
                </div>

                {m.model_used && (
                  <code className="text-[10px] font-mono text-muted-foreground mt-1.5 inline-block pl-8">
                    {m.model_used}
                  </code>
                )}
              </li>
            ))}
          </ul>
        )}
      </ContentCard>
    </div>
  )
}
