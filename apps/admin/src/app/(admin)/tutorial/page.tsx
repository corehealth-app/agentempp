import Link from 'next/link'
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  Bot,
  Calculator,
  Clock,
  Cpu,
  CreditCard,
  FileText,
  Globe,
  Key,
  MessageSquare,
  RotateCcw,
  Settings,
  Sparkles,
  Trash2,
  UserCog,
  Users,
} from 'lucide-react'
import { ContentCard, PageHeader } from '@/components/page-header'

export default function TutorialPage() {
  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        breadcrumbs={[{ label: 'Tutorial' }]}
        title="O que dá pra mexer"
        description="Mapa completo de tudo que é editável via UI. Mudanças propagam em ≤1min sem deploy de código."
      />

      <ContentCard
        title="Filosofia"
        description="Tudo que afeta comportamento do agente em produção é editável aqui."
      >
        <div className="text-sm text-foreground/80 space-y-2 leading-relaxed">
          <p>
            A plataforma foi construída com a regra: <strong>nenhuma decisão clínica,
            nutricional, gamificação, agendamento ou conversa fica trancada em código</strong>.
            Cada constante mora em <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">global_config</code>,{' '}
            <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">agent_configs</code>,{' '}
            <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">agent_rules</code>{' '}
            ou em tabelas de configuração equivalentes.
          </p>
          <p>
            Os workers (Inngest functions) cacheiam config por 60s — então qualquer ajuste que
            você fizer aqui aparece em produção em ≤1min sem precisar de redeploy. Toda mudança
            grava <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">audit_log</code>{' '}
            automaticamente (quem, quando, o quê, antes/depois).
          </p>
        </div>
      </ContentCard>

      <Section
        title="Operação do dia-a-dia"
        description="Coisas que você toca em cada paciente individualmente."
      >
        <Item
          icon={MessageSquare}
          href="/messages"
          title="Conversas"
          description="Observa thread em tempo real, marca msgs como 'alucinou' / 'ótima resposta', pausa o agente, edita nome/notas/tags do paciente, abre playground com a msg como seed."
          examples={[
            'Click numa msg OUT → Flag → "Alucinação" pra revisar depois',
            'Sidebar direita → "Pausar agente" → 7d (ele para de responder)',
            'Notas (admin) → adiciona contexto interno (paciente não vê)',
          ]}
        />
        <Item
          icon={Users}
          href="/users"
          title="Pacientes"
          description="Lista de todos com filtros. Click abre /users/[id] com perfil completo."
          examples={[
            'Filtra "sem nome" → identifica testes vs onboarding incompleto',
            'Click no paciente → vê BMR, IMC, protocolo, snapshots 14d',
          ]}
        />
        <SubItem
          icon={Globe}
          title="Confirmar país manualmente"
          description="Quando o LLM não chama confirma_pais_residencia mesmo o paciente respondendo. /users/[id] → header tem botão âmbar 'Confirmar país'."
        />
        <SubItem
          icon={CreditCard}
          title="Gerar link de checkout"
          description="/users/[id] → seção Assinatura → botões 'Mensal R$197' / 'Anual R$1.164'. Cria sessão Stripe e devolve URL."
        />
        <SubItem
          icon={RotateCcw}
          title="Resetar conversa"
          description="Mantém o paciente cadastrado mas zera onboarding (mensagens, refeições, treinos, snapshots, progresso, embeddings). Útil pra testar fluxo do zero. Mantém subscription Stripe ativa."
        />
        <SubItem
          icon={Trash2}
          title="Excluir paciente"
          description="CASCADE total: apaga user + tudo relacionado. Próxima msg dele no WhatsApp será tratada como paciente novo."
        />
      </Section>

      <Section
        title="Curadoria do agente"
        description="Como o agente fala, decide, usa tools e qual modelo roda em cada estágio."
      >
        <Item
          icon={FileText}
          href="/prompts"
          title="Regras (88+) e system prompts"
          description="Editor com diff viewer e versionamento. Cada regra tem categoria, prioridade, ativa/inativa. System prompt de cada estágio tem versão própria."
          examples={[
            'Mudar voz/tom → editar regra de persona, publicar',
            'Comparar com versão anterior → diff viewer side-by-side',
            'Despublicar regra problemática → toggle ativa=false',
          ]}
        />
        <Item
          icon={Bot}
          href="/prompts/playground"
          title="Playground"
          description="Testa prompt ad-hoc com seed real de paciente, sem afetar produção. Útil pra calibrar tom antes de salvar."
        />
        <Item
          icon={Cpu}
          href="/settings/agents"
          title="Sub-agentes (modelo/temp/tokens)"
          description="6 estágios: coleta_dados, recomposicao, ganho_massa, manutencao, analista_diario (cron), engajamento (cron). Cada um com modelo (OpenRouter ID), temperatura, max_tokens. Versionado em agent_configs_versions."
          examples={[
            'Engajamento muito conservador → temperatura 0.7 → 0.9',
            'Coleta_dados gastando muito → trocar de Grok pra Haiku',
            'Reverter pra versão anterior → agent_configs_versions',
          ]}
        />
        <Item
          icon={Sparkles}
          href="/evaluations"
          title="Avaliações LLM"
          description="Lista os scores das últimas 50 conversas avaliadas pelo cron LLM-as-judge. Distribuição alta/média/baixa, score médio."
        />
      </Section>

      <Section
        title="Cálculos e parâmetros"
        description="Toda fórmula determinística (BMR, TDEE, IMC, badges, XP) e config runtime."
      >
        <Item
          icon={Calculator}
          href="/settings/calc"
          title="Constantes de cálculo (13)"
          description="BMR Mifflin-St Jeor + Katch-McArdle, fatores de atividade, fatores de proteína, KCAL_BLOCK (7700), limites IMC/BF, training_min, IMC goal steps, BF goal rules, níveis XP, badges, regras XP diário."
          examples={[
            'Mudar bloco de 7700 pra 7000 kcal → afeta gamificação imediata',
            'Adicionar nova badge "Atleta Pro" → editar JSON do calc.badges',
            'Ajustar limite IMC pra recomposição (25 → 27)',
          ]}
        />
        <Item
          icon={Settings}
          href="/settings/global"
          title="Config global (32+ chaves em 9 grupos)"
          description="Tudo que não é por-paciente. Agrupado por prefixo do key:"
          groups={[
            { name: 'rate_limit', count: 2, what: 'Msgs/user/min, custo/user/dia' },
            { name: 'alerts', count: 3, what: 'Thresholds de custo 24h, latência, taxa de erro' },
            { name: 'tts', count: 5, what: 'ElevenLabs stability/similarity/speed/style + rewriter on/off' },
            { name: 'engagement', count: 5, what: 'Wake/bed offsets + fallbacks + slots (thresholds + meal_hints)' },
            { name: 'humanizer', count: 4, what: 'Velocidade de digitação simulada + delays' },
            { name: 'buffer', count: 1, what: 'Debounce do webhook WhatsApp (ms)' },
            { name: 'attention', count: 7, what: 'Thresholds das categorias do "Quem precisa da sua atenção"' },
            { name: 'calc', count: 13, what: '(também aparece em /settings/calc com UI dedicada)' },
            { name: 'country_to_language', count: 1, what: 'Map de país → idioma da persona' },
            { name: 'persona', count: 1, what: 'Variações de persona por país' },
          ]}
        />
      </Section>

      <Section
        title="Crons e automação"
        description="Agendamentos rodando via pg_cron + Inngest workers."
      >
        <Item
          icon={Clock}
          href="/settings/crons"
          title="Cron jobs (12)"
          description="Cada job tem 3 ações inline: Editar (cron expression 5/6 campos), Ativar/Desativar (toggle pg_cron com optimistic UI), Rodar agora (executa o command imediatamente, fora do schedule). Toda mudança vai pro audit_log."
          examples={[
            'engagement-* (5 disparos/dia) — heartbeats, sender escolhe slot por hora local',
            'daily-closer-* (4 horários, cobre múltiplos timezones)',
            'cleanup-processed-messages (4h diário)',
            'wa-quality-check / refresh-mv-kpis-daily',
          ]}
        />
      </Section>

      <Section
        title="Integrações"
        description="Credentials de providers externos."
      >
        <Item
          icon={Key}
          href="/settings/api-keys"
          title="API Keys (8 providers)"
          description="OpenRouter, Groq, ElevenLabs (×2 voices), WhatsApp Cloud API (Meta), Stripe, Inngest, Sentry. Cada um com botão 'Testar' que valida a credencial sem aplicar."
        />
        <Item
          icon={CreditCard}
          href="/settings/stripe"
          title="Stripe — produtos + sync"
          description="Sincroniza produtos do Stripe (lookup_keys mpp_mensal_v1, mpp_anual_v1) com a DB local. Edita preço/nome direto no Stripe Dashboard, vem aqui e clica Sync."
        />
      </Section>

      <Section
        title="Governança e atenção"
        description="O que olhar pra saber se algo precisa intervenção manual."
      >
        <Item
          icon={AlertTriangle}
          href="/dashboard"
          title='"Quem precisa da sua atenção" (top do dashboard)'
          description="Feed automático com 5 categorias: tool error recent (6h), payment failed (7d), onboarding stuck (24h+), silent user (3-14d), block milestone (parabenizar). Cada item tem botões inline:"
          examples={[
            'Conversa → abre thread direto',
            'Adiar 24h → snooze (volta automaticamente)',
            'Resolver → dismiss permanente até nova ocorrência',
            'Thresholds editáveis em /settings/global → attention.*',
          ]}
        />
        <Item
          icon={Activity}
          href="/audit"
          title="Auditoria"
          description="Feed de todas as ações administrativas: quem editou regra, quem reset paciente, quem mudou cron, etc. Filtra por tipo de ação. 200 últimas."
        />
        <Item
          icon={UserCog}
          href="/settings/admins"
          title="Admins"
          description="CRUD de quem tem acesso ao painel. Adiciona email + role. RLS bloqueia tudo fora de admin_users."
        />
      </Section>

      <ContentCard
        title="Atalhos úteis"
        description="Coisas escondidas que economizam tempo."
      >
        <div className="space-y-2 text-sm">
          <ShortcutRow
            shortcut="⌘ K"
            label="Abre command palette"
            description="Busca conversas, abre páginas rápido."
          />
          <ShortcutRow
            shortcut="/"
            label="Foco na busca de conversas"
            description="Em /messages, vai direto pro campo de busca."
          />
          <ShortcutRow
            shortcut="Hover"
            label="Tooltips em badges"
            description='País "BR ✓" mostra "confirmado pelo paciente"; "BR ?" mostra "detectado pelo DDI".'
          />
        </div>
      </ContentCard>

      <ContentCard title="Onde tudo mora">
        <div className="text-sm text-foreground/80 space-y-2 leading-relaxed">
          <p>
            <strong>Frontend (Vercel)</strong>: <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">apps/admin</code>{' '}
            (Next.js 15) + <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">/api/inngest</code> servindo as
            funções workers.
          </p>
          <p>
            <strong>Backend (Supabase)</strong>: Postgres + RLS + pg_cron + 2 Edge Functions
            (webhook-whatsapp, webhook-stripe). Cada migration em{' '}
            <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">supabase/migrations</code>.
          </p>
          <p>
            <strong>Workers (Inngest Cloud)</strong>:{' '}
            <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">packages/inngest-functions</code>{' '}
            — engagement-sender, daily-closer, process-message, buffer-listener,
            wa-quality-check.
          </p>
          <p>
            <strong>Lógica pura testável</strong>:{' '}
            <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">packages/core</code>{' '}
            (BMR, IMC, blocos, XP, badges, protocolo) — 40+ tests cobrindo as fórmulas.
          </p>
        </div>
      </ContentCard>
    </div>
  )
}

// ----------------------------------------------------------------------------
// helpers
// ----------------------------------------------------------------------------

function Section({
  title,
  description,
  children,
}: {
  title: string
  description: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-3">
      <div className="px-1 pt-2">
        <h2 className="font-display text-xl tracking-tight text-foreground">{title}</h2>
        <p className="text-sm text-muted-foreground mt-0.5">{description}</p>
      </div>
      <div className="space-y-2">{children}</div>
    </div>
  )
}

function Item({
  icon: Icon,
  href,
  title,
  description,
  examples,
  groups,
}: {
  icon: React.ComponentType<{ className?: string }>
  href?: string
  title: string
  description: string
  examples?: string[]
  groups?: Array<{ name: string; count: number; what: string }>
}) {
  const inner = (
    <div className="content-card p-4 flex gap-3 hover:bg-muted/30 transition-colors">
      <div className="shrink-0 h-9 w-9 rounded-md bg-moss-700/10 text-moss-700 flex items-center justify-center">
        <Icon className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0 space-y-1.5">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-medium text-foreground">{title}</span>
          {href && (
            <code className="font-mono text-[10px] bg-muted px-1.5 py-0.5 rounded text-muted-foreground">
              {href}
            </code>
          )}
        </div>
        <p className="text-sm text-muted-foreground leading-relaxed">{description}</p>
        {examples && (
          <ul className="text-xs text-foreground/70 space-y-0.5 mt-2">
            {examples.map((e, i) => (
              <li key={i} className="flex gap-2">
                <span className="text-moss-600 shrink-0">▸</span>
                <span>{e}</span>
              </li>
            ))}
          </ul>
        )}
        {groups && (
          <ul className="text-xs space-y-0.5 mt-2">
            {groups.map((g) => (
              <li key={g.name} className="flex gap-2 items-baseline">
                <code className="font-mono text-[11px] text-moss-700 shrink-0 min-w-[110px]">
                  {g.name}.* ({g.count})
                </code>
                <span className="text-muted-foreground">{g.what}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
      {href && (
        <ArrowRight className="h-4 w-4 text-muted-foreground/40 mt-1 shrink-0 self-start" />
      )}
    </div>
  )
  if (href) {
    return (
      <Link href={href} className="block">
        {inner}
      </Link>
    )
  }
  return inner
}

function SubItem({
  icon: Icon,
  title,
  description,
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  description: string
}) {
  return (
    <div className="ml-12 glass-subtle p-3 flex gap-2.5">
      <Icon className="h-3.5 w-3.5 text-muted-foreground shrink-0 mt-0.5" />
      <div>
        <div className="text-sm font-medium text-foreground">{title}</div>
        <p className="text-xs text-muted-foreground mt-0.5 leading-relaxed">{description}</p>
      </div>
    </div>
  )
}

function ShortcutRow({
  shortcut,
  label,
  description,
}: {
  shortcut: string
  label: string
  description: string
}) {
  return (
    <div className="flex items-baseline gap-3 py-1.5">
      <kbd className="shrink-0 inline-flex items-center justify-center min-w-[3rem] h-6 px-2 text-[11px] font-mono font-medium bg-muted border border-border rounded">
        {shortcut}
      </kbd>
      <div className="flex-1">
        <span className="font-medium text-foreground text-sm">{label}</span>
        <span className="text-xs text-muted-foreground ml-2">— {description}</span>
      </div>
    </div>
  )
}
