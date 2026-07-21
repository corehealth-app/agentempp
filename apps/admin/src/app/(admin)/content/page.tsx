import { LockKeyhole, Plus } from 'lucide-react'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { Button } from '@/components/ui/button'
import { CONTENT_MODULE_ROLES, hasAdminRole, isAdminRole } from '@/lib/admin-rbac'
import type { ContentAdminFilters, ContentPublicationSummary } from '@/lib/content/admin-service'
import { createClient } from '@/lib/supabase/server'
import { listContentPublicationsAction } from './actions'
import { toPublicationListRow } from './presenter'
import { type PublicationFilterState, PublicationTable } from './publication-table'

export const dynamic = 'force-dynamic'

type SearchParams = Promise<Record<string, string | string[] | undefined>>

const STATUSES = [
  'draft',
  'in_review',
  'approved',
  'rejected',
  'scheduled',
  'published',
  'archived',
] as const
const LOCALES = ['pt-BR', 'en-US'] as const
const CATEGORIES = [
  'weight_loss',
  'hypertrophy',
  'nutrition',
  'training',
  'neuroscience',
  'habit_formation',
  'cardiovascular_health',
  'hydration',
  'supplementation',
  'sleep',
  'using_bodyflow',
] as const
const SCHEDULES = ['unscheduled', 'scheduled', 'published'] as const
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export default async function ContentPage({ searchParams }: { searchParams: SearchParams }) {
  const admin = await loadAdmin()
  if (!admin || !hasAdminRole(admin.role, CONTENT_MODULE_ROLES)) return <AccessDenied />

  const filters = parseFilters(await searchParams)
  const actionFilters: ContentAdminFilters = {
    limit: 100,
    offset: 0,
    ...(filters.status ? { status: filters.status } : {}),
    ...(filters.locale ? { locale: filters.locale } : {}),
    ...(filters.category ? { category: filters.category } : {}),
    ...(filters.authorId ? { authorId: filters.authorId } : {}),
    ...(filters.reviewerId ? { reviewerId: filters.reviewerId } : {}),
    ...(filters.schedule ? { schedule: filters.schedule } : {}),
    ...(filters.featuredToday !== undefined ? { featuredToday: filters.featuredToday } : {}),
  }
  const result = await listContentPublicationsAction(actionFilters)

  if (!result.ok) return <PageFailure message={result.error} />

  const now = new Date().toISOString()
  const summaries = result.data as ContentPublicationSummary[]
  const rows = summaries.map((publication) => toPublicationListRow(publication, now))

  return (
    <div className="space-y-4">
      <PageHeader
        compact
        breadcrumbs={[{ label: 'Publicacoes' }]}
        title="Publicacoes"
        description={`${rows.length.toLocaleString('pt-BR')} itens no recorte atual`}
        actions={
          admin.role === 'content_editor' ? (
            <Button asChild size="sm">
              <Link href="/content/new">
                <Plus />
                Nova publicacao
              </Link>
            </Button>
          ) : undefined
        }
      />
      <PublicationTable rows={rows} filters={filters} now={now} />
    </div>
  )
}

async function loadAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return null

  const reader = supabase as unknown as {
    from(table: 'admin_users'): {
      select(columns: 'id, role'): {
        eq(
          column: 'id',
          value: string,
        ): {
          maybeSingle(): Promise<{
            data: { id: string; role: string } | null
            error: unknown
          }>
        }
      }
    }
  }
  const { data } = await reader
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

function member<T extends string>(values: readonly T[], value: string | undefined): T | undefined {
  return values.find((candidate) => candidate === value)
}

function parseFilters(params: Awaited<SearchParams>): PublicationFilterState {
  const authorId = scalar(params.author)
  const reviewerId = scalar(params.reviewer)
  const featured = scalar(params.featured)
  return {
    status: member(STATUSES, scalar(params.status)),
    locale: member(LOCALES, scalar(params.locale)),
    category: member(CATEGORIES, scalar(params.category)),
    authorId: authorId && UUID_PATTERN.test(authorId) ? authorId : undefined,
    reviewerId: reviewerId && UUID_PATTERN.test(reviewerId) ? reviewerId : undefined,
    schedule: member(SCHEDULES, scalar(params.schedule)),
    featuredToday: featured === 'true' ? true : featured === 'false' ? false : undefined,
    text: scalar(params.text)?.trim().slice(0, 120) || undefined,
  }
}

function AccessDenied() {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={[{ label: 'Publicacoes' }]} title="Publicacoes" />
      <section className="content-card flex min-h-64 flex-col items-center justify-center px-6 text-center">
        <LockKeyhole className="h-6 w-6 text-muted-foreground" />
        <p className="mt-3 text-sm font-medium">Acesso editorial necessario</p>
        <p className="mt-1 max-w-md text-xs text-muted-foreground">
          Este modulo esta disponivel apenas para a equipe editorial.
        </p>
      </section>
    </div>
  )
}

function PageFailure({ message }: { message: string }) {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={[{ label: 'Publicacoes' }]} title="Publicacoes" />
      <section className="content-card px-5 py-8 text-center">
        <p className="text-sm font-medium text-destructive">{message}</p>
      </section>
    </div>
  )
}
