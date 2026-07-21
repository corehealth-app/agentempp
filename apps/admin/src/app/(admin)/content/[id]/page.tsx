import { ArrowLeft, LockKeyhole } from 'lucide-react'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { Button } from '@/components/ui/button'
import { CONTENT_MODULE_ROLES, hasAdminRole, isAdminRole } from '@/lib/admin-rbac'
import type { ContentPublicationDetail } from '@/lib/content/admin-service'
import { createClient } from '@/lib/supabase/server'
import { getContentPublicationAction } from '../actions'
import { ContentEditor } from './editor'

export const dynamic = 'force-dynamic'

type Params = Promise<{ id: string }>
type SearchParams = Promise<Record<string, string | string[] | undefined>>

export default async function ContentDetailPage({
  params,
  searchParams,
}: {
  params: Params
  searchParams: SearchParams
}) {
  const admin = await loadAdmin()
  if (!admin || !hasAdminRole(admin.role, CONTENT_MODULE_ROLES)) return <AccessDenied />
  const { id } = await params
  const result = await getContentPublicationAction({ publicationId: id })
  if (!result.ok) return <PageFailure message={result.error} />
  const publication = result.data as ContentPublicationDetail | null
  if (!publication) notFound()
  const query = await searchParams
  const initialError = scalar(query.error)?.slice(0, 160)

  return (
    <div className="space-y-4">
      <PageHeader
        compact
        breadcrumbs={[{ label: 'Publicacoes', href: '/content' }, { label: publication.slug }]}
        title={publication.slug}
        description={`Criada por ${publication.createdBy.name ?? publication.createdBy.id.slice(0, 8)} · ${publication.versions.length} versoes`}
        actions={
          <Button asChild size="sm" variant="outline">
            <Link href="/content">
              <ArrowLeft />
              Voltar
            </Link>
          </Button>
        }
      />
      <ContentEditor publication={publication} role={admin.role} initialError={initialError} />
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
        ): { maybeSingle(): Promise<{ data: { id: string; role: string } | null; error: unknown }> }
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

function AccessDenied() {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={[{ label: 'Publicacoes' }]} title="Publicacoes" />
      <section className="content-card flex min-h-64 flex-col items-center justify-center px-6 text-center">
        <LockKeyhole className="h-6 w-6 text-muted-foreground" />
        <p className="mt-3 text-sm font-medium">Acesso editorial necessario</p>
      </section>
    </div>
  )
}

function PageFailure({ message }: { message: string }) {
  return (
    <div className="space-y-4">
      <PageHeader breadcrumbs={[{ label: 'Publicacoes', href: '/content' }]} title="Publicacao" />
      <section className="content-card px-5 py-8 text-center">
        <p className="text-sm font-medium text-destructive">{message}</p>
      </section>
    </div>
  )
}
