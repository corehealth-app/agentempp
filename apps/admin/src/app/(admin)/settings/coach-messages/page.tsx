import {
  coachMessageChannelSchema,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
} from '@mpp/core'
import { LockKeyhole } from 'lucide-react'
import { PageHeader } from '@/components/page-header'
import { CONTENT_ADMIN_ROLES, hasAdminRole, isAdminRole } from '@/lib/admin-rbac'
import type {
  CoachCatalogEntry,
  CoachCatalogFilters,
  CoachContentPackSummary,
  CoachPackStatus,
  CoachUsageSummary,
} from '@/lib/coach-messages/admin-service'
import { createClient } from '@/lib/supabase/server'
import {
  getCoachUsageSummaryAction,
  listCoachCatalogAction,
  listCoachContentPacksAction,
} from './actions'
import type { CoachCatalogFilterState } from './catalog-presenter'
import { CatalogTable } from './catalog-table'
import { PackControls } from './pack-controls'
import { UsageSummary } from './usage-summary'

export const dynamic = 'force-dynamic'

const PACK_STATUSES = ['draft', 'scheduled', 'active', 'archived'] as const

type SearchParams = Promise<Record<string, string | string[] | undefined>>

export default async function CoachMessagesPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams
  const admin = await loadAdmin()

  if (!admin || !hasAdminRole(admin.role, CONTENT_ADMIN_ROLES)) {
    return (
      <div className="space-y-4">
        <PageHeader
          breadcrumbs={[{ label: 'Configuração' }, { label: 'Mensagens do coach' }]}
          title="Mensagens do coach"
        />
        <section className="content-card flex min-h-64 flex-col items-center justify-center px-6 text-center">
          <LockKeyhole className="h-6 w-6 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">Acesso editorial necessário</p>
          <p className="mt-1 max-w-md text-xs text-muted-foreground">
            Este módulo está disponível para content editor e master admin.
          </p>
        </section>
      </div>
    )
  }

  const packsResult = await listCoachContentPacksAction()
  if (!packsResult.ok) return <PageFailure message={packsResult.error} />

  const packs = packsResult.data as CoachContentPackSummary[]
  if (packs.length === 0) {
    return <PageFailure message="Nenhum pack de mensagens foi encontrado" />
  }

  const filters = parseFilters(params)
  if (filters.status && !packs.some((pack) => pack.status === filters.status)) {
    filters.status = undefined
  }
  const packsForStatus = filters.status
    ? packs.filter((pack) => pack.status === filters.status)
    : packs
  const selectedPack =
    packsForStatus.find((pack) => pack.id === filters.pack) ??
    packsForStatus.find((pack) => pack.status === 'active') ??
    packsForStatus[0]

  if (!selectedPack) {
    return <PageFailure message="Nenhum pack corresponde ao status selecionado" />
  }

  filters.pack = selectedPack.id
  const catalogFilters: CoachCatalogFilters = {
    packId: selectedPack.id,
    ...(filters.personality ? { personality: filters.personality } : {}),
    ...(filters.context ? { context: filters.context } : {}),
    ...(filters.channel ? { channel: filters.channel } : {}),
    ...(filters.locale ? { locale: filters.locale } : {}),
  }

  const [catalogResult, usageResult] = await Promise.all([
    listCoachCatalogAction(catalogFilters),
    getCoachUsageSummaryAction(),
  ])
  if (!catalogResult.ok) return <PageFailure message={catalogResult.error} />

  const entries = catalogResult.data as CoachCatalogEntry[]
  const usage = usageResult.ok ? (usageResult.data as CoachUsageSummary) : null
  const renderKey = [
    selectedPack.id,
    filters.personality,
    filters.context,
    filters.channel,
    filters.locale,
  ].join(':')

  return (
    <div className="space-y-4">
      <PageHeader
        compact
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Mensagens do coach' }]}
        title="Mensagens do coach"
        description={`${entries.length.toLocaleString('pt-BR')} rendições no recorte atual`}
      />

      {usage ? (
        <UsageSummary summary={usage} />
      ) : (
        <div className="border-l-2 border-amber-500 bg-amber-500/5 px-4 py-3 text-sm text-foreground">
          Não foi possível carregar os contadores de uso.
        </div>
      )}

      <PackControls pack={selectedPack} role={admin.role} />
      <CatalogTable
        key={renderKey}
        packs={packs}
        selectedPack={selectedPack}
        entries={entries}
        filters={filters}
        role={admin.role}
      />
    </div>
  )
}

async function loadAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return null

  const authenticatedRoleReader = supabase as unknown as {
    from(table: 'admin_users'): {
      select(columns: 'id, role'): {
        eq(
          column: 'id',
          value: string,
        ): {
          maybeSingle(): Promise<{
            data: { id: string; role: string } | null
            error: { message: string } | null
          }>
        }
      }
    }
  }
  const { data } = await authenticatedRoleReader
    .from('admin_users')
    .select('id, role')
    .eq('id', user.id)
    .maybeSingle()
  if (!data || !isAdminRole(data.role)) return null
  return { id: data.id, role: data.role }
}

function scalar(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value
}

function parseFilters(params: Awaited<SearchParams>): CoachCatalogFilterState & {
  status?: CoachPackStatus
  personality?: CoachCatalogFilters['personality']
  context?: CoachCatalogFilters['context']
  channel?: CoachCatalogFilters['channel']
  locale?: CoachCatalogFilters['locale']
} {
  const rawStatus = scalar(params.status)
  const status = PACK_STATUSES.find((candidate) => candidate === rawStatus)
  const personality = coachPersonalitySchema.safeParse(scalar(params.personality))
  const context = coachMessageContextSchema.safeParse(scalar(params.context))
  const channel = coachMessageChannelSchema.safeParse(scalar(params.channel))
  const locale = coachMessageLocaleSchema.safeParse(scalar(params.locale))
  return {
    pack: scalar(params.pack),
    status,
    personality: personality.success ? personality.data : undefined,
    context: context.success ? context.data : undefined,
    channel: channel.success ? channel.data : undefined,
    locale: locale.success ? locale.data : undefined,
  }
}

function PageFailure({ message }: { message: string }) {
  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Mensagens do coach' }]}
        title="Mensagens do coach"
      />
      <section className="content-card px-5 py-8 text-center">
        <p className="text-sm font-medium text-destructive">{message}</p>
      </section>
    </div>
  )
}
