import { ArrowLeft, FilePlus2, LockKeyhole } from 'lucide-react'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { CONTENT_AUTHOR_ROLES, hasAdminRole, isAdminRole } from '@/lib/admin-rbac'
import { createClient } from '@/lib/supabase/server'
import { createContentDraftAction, createContentPublicationAction } from '../actions'

export const dynamic = 'force-dynamic'

type SearchParams = Promise<Record<string, string | string[] | undefined>>

export default async function NewContentPage({ searchParams }: { searchParams: SearchParams }) {
  const admin = await loadAdmin()
  if (!admin || !hasAdminRole(admin.role, CONTENT_AUTHOR_ROLES)) return <AccessDenied />
  const params = await searchParams
  const error = scalar(params.error)?.slice(0, 160)

  async function createPublication(formData: FormData) {
    'use server'
    const slug = String(formData.get('slug') ?? '')
      .trim()
      .toLowerCase()
    const locale = String(formData.get('locale') ?? '')
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length < 3 || slug.length > 120) {
      redirect(
        `/content/new?error=${encodeURIComponent('Use um slug valido entre 3 e 120 caracteres.')}`,
      )
    }
    if (locale !== 'pt-BR' && locale !== 'en-US') {
      redirect(`/content/new?error=${encodeURIComponent('Selecione o idioma inicial.')}`)
    }

    const publicationResult = await createContentPublicationAction({ slug })
    if (!publicationResult.ok) {
      redirect(`/content/new?error=${encodeURIComponent(publicationResult.error)}`)
    }
    const publication = publicationResult.data as { publicationId: string }
    const draftResult = await createContentDraftAction({
      publicationId: publication.publicationId,
      locale,
    })
    if (!draftResult.ok) {
      redirect(
        `/content/${publication.publicationId}?error=${encodeURIComponent(draftResult.error)}`,
      )
    }
    redirect(`/content/${publication.publicationId}`)
  }

  return (
    <div className="space-y-4">
      <PageHeader
        compact
        breadcrumbs={[{ label: 'Publicacoes', href: '/content' }, { label: 'Nova' }]}
        title="Nova publicacao"
        actions={
          <Button asChild size="sm" variant="outline">
            <Link href="/content">
              <ArrowLeft />
              Voltar
            </Link>
          </Button>
        }
      />
      <section className="content-card max-w-2xl">
        <form action={createPublication} className="space-y-5 p-5">
          {error && (
            <p
              role="alert"
              className="border-l-2 border-destructive bg-destructive/5 px-3 py-2 text-sm text-destructive"
            >
              {error}
            </p>
          )}
          <div className="space-y-2">
            <Label htmlFor="slug">Slug estavel</Label>
            <Input
              id="slug"
              name="slug"
              required
              minLength={3}
              maxLength={120}
              pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
              placeholder="alimentacao-consciente"
              autoComplete="off"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="locale">Primeiro idioma</Label>
            <select
              id="locale"
              name="locale"
              defaultValue="pt-BR"
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="pt-BR">Portugues (pt-BR)</option>
              <option value="en-US">Ingles (en-US)</option>
            </select>
          </div>
          <div className="flex justify-end border-t border-border pt-4">
            <Button type="submit">
              <FilePlus2 />
              Criar publicacao
            </Button>
          </div>
        </form>
      </section>
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
      <PageHeader
        breadcrumbs={[{ label: 'Publicacoes', href: '/content' }, { label: 'Nova' }]}
        title="Nova publicacao"
      />
      <section className="content-card flex min-h-64 flex-col items-center justify-center px-6 text-center">
        <LockKeyhole className="h-6 w-6 text-muted-foreground" />
        <p className="mt-3 text-sm font-medium">Apenas autores podem criar publicacoes</p>
      </section>
    </div>
  )
}
