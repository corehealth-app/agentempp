import Link from 'next/link'
import { Suspense } from 'react'
import { Award, CreditCard, TrendingUp } from 'lucide-react'
import { PageHeader } from '@/components/page-header'
import { ConquistasView } from './views/conquistas-view'
import { FunilView } from './views/funil-view'
import { ReceitaView } from './views/receita-view'

export const dynamic = 'force-dynamic'

type Tab = 'conquistas' | 'funil' | 'receita'

const TABS: Array<{ key: Tab; label: string; icon: React.ComponentType<{ className?: string }>; description: string }> = [
  { key: 'receita', label: 'Receita', icon: CreditCard, description: 'MRR, churn, assinaturas Stripe' },
  { key: 'conquistas', label: 'Conquistas', icon: Award, description: 'XP, streaks, badges, blocos' },
  { key: 'funil', label: 'Funil & Cohorts', icon: TrendingUp, description: 'Ativação semanal' },
]

export default async function CrescimentoPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>
}) {
  const params = await searchParams
  const tab: Tab = (TABS.find((t) => t.key === params.tab)?.key ?? 'receita') as Tab
  const activeMeta = TABS.find((t) => t.key === tab)!

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Crescimento' }, { label: activeMeta.label }]}
        title="Crescimento"
        description={activeMeta.description}
      />

      {/* Tabs nav */}
      <div className="flex flex-wrap gap-1 border-b border-border">
        {TABS.map((t) => {
          const Icon = t.icon
          const active = t.key === tab
          return (
            <Link
              key={t.key}
              href={t.key === 'receita' ? '/crescimento' : `/crescimento?tab=${t.key}`}
              className={`inline-flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
                active
                  ? 'border-moss-700 text-moss-700'
                  : 'border-transparent text-muted-foreground hover:text-foreground hover:border-border'
              }`}
            >
              <Icon className="h-3.5 w-3.5" />
              {t.label}
            </Link>
          )
        })}
      </div>

      {/* Tab content (Suspense por tab pra streaming) */}
      <Suspense fallback={<TabSkeleton />} key={tab}>
        {tab === 'receita' && <ReceitaView />}
        {tab === 'conquistas' && <ConquistasView />}
        {tab === 'funil' && <FunilView />}
      </Suspense>
    </div>
  )
}

function TabSkeleton() {
  return (
    <div className="space-y-3">
      <div className="grid gap-3 md:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="content-card p-4 space-y-2">
            <div className="h-3 w-20 rounded bg-muted animate-pulse" />
            <div className="h-7 w-16 rounded bg-muted/70 animate-pulse" />
          </div>
        ))}
      </div>
      <div className="content-card p-5 space-y-2">
        <div className="h-4 w-48 rounded bg-muted animate-pulse" />
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="h-3 rounded bg-muted/50 animate-pulse" style={{ width: `${60 + i * 7}%` }} />
        ))}
      </div>
    </div>
  )
}
