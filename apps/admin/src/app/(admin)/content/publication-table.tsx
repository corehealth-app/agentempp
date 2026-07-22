'use client'

import { ArrowLeft, ArrowRight, Search, SearchX, Star } from 'lucide-react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { type FormEvent, useEffect, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import type { ContentAdminFilters } from '@/lib/content/admin-service'
import { type PublicationListRow, scheduleLabel } from './presenter'
import {
  buildPublicationIdentityOptions,
  type PublicationIdentityOptionSource,
} from './publication-filter-options'

export interface PublicationFilterState
  extends Omit<ContentAdminFilters, 'limit' | 'offset' | 'featuredToday'> {
  featuredToday?: boolean
  text?: string
}

const STATUS_OPTIONS = [
  ['draft', 'Rascunho'],
  ['in_review', 'Em revisao'],
  ['approved', 'Aprovado'],
  ['rejected', 'Rejeitado'],
  ['scheduled', 'Agendado'],
  ['published', 'Publicado'],
  ['archived', 'Arquivado'],
] as const

const CATEGORY_OPTIONS = [
  ['weight_loss', 'Emagrecimento'],
  ['hypertrophy', 'Hipertrofia'],
  ['nutrition', 'Nutricao'],
  ['training', 'Treino'],
  ['neuroscience', 'Neurociencia'],
  ['habit_formation', 'Formacao de habitos'],
  ['cardiovascular_health', 'Saude cardiovascular'],
  ['hydration', 'Hidratacao'],
  ['supplementation', 'Suplementacao'],
  ['sleep', 'Sono'],
  ['using_bodyflow', 'Uso do BodyFlow'],
] as const

const STATUS_LABELS = Object.fromEntries(STATUS_OPTIONS) as Record<string, string>
const CATEGORY_LABELS = Object.fromEntries(CATEGORY_OPTIONS) as Record<string, string>

export function PublicationTable({
  rows,
  filters,
  globalAuthors,
  globalReviewers,
  now,
  page,
  hasPrevious,
  hasNext,
}: {
  rows: PublicationListRow[]
  filters: PublicationFilterState
  globalAuthors: PublicationIdentityOptionSource[]
  globalReviewers: PublicationIdentityOptionSource[]
  now: string
  page: number
  hasPrevious: boolean
  hasNext: boolean
}) {
  const pathname = usePathname()
  const router = useRouter()
  const [text, setText] = useState(filters.text ?? '')

  useEffect(() => {
    setText(filters.text ?? '')
  }, [filters.text])

  const authorOptions = buildPublicationIdentityOptions(
    globalAuthors,
    rows.flatMap((row) => row.versions.map((version) => version.authorId)),
    filters.authorId,
  )
  const reviewerOptions = buildPublicationIdentityOptions(
    globalReviewers,
    rows.flatMap((row) => row.versions.map((version) => version.reviewerId)),
    filters.reviewerId,
  )

  function navigate(next: PublicationFilterState, requestedPage = 1) {
    const params = new URLSearchParams()
    if (next.status) params.set('status', next.status)
    if (next.locale) params.set('locale', next.locale)
    if (next.category) params.set('category', next.category)
    if (next.authorId) params.set('author', next.authorId)
    if (next.reviewerId) params.set('reviewer', next.reviewerId)
    if (next.schedule) params.set('schedule', next.schedule)
    if (next.featuredToday !== undefined) params.set('featured', String(next.featuredToday))
    if (next.text) params.set('text', next.text)
    if (requestedPage > 1) params.set('page', String(requestedPage))
    const query = params.toString()
    router.push(query ? `${pathname}?${query}` : pathname, { scroll: false })
  }

  function setFilter(key: keyof PublicationFilterState, value: string) {
    navigate({ ...filters, [key]: value === 'all' ? undefined : value })
  }

  function submitText(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    navigate({ ...filters, text: text.trim() || undefined })
  }

  return (
    <TooltipProvider>
      <section className="content-card" aria-label="Filtros de publicacoes">
        <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-4">
          <FilterSelect
            label="Status"
            value={filters.status ?? 'all'}
            options={STATUS_OPTIONS}
            onChange={(value) => setFilter('status', value)}
          />
          <FilterSelect
            label="Idioma"
            value={filters.locale ?? 'all'}
            options={[
              ['pt-BR', 'Portugues'],
              ['en-US', 'Ingles'],
            ]}
            onChange={(value) => setFilter('locale', value)}
          />
          <FilterSelect
            label="Categoria"
            value={filters.category ?? 'all'}
            options={CATEGORY_OPTIONS}
            onChange={(value) => setFilter('category', value)}
          />
          <FilterSelect
            label="Autor"
            value={filters.authorId ?? 'all'}
            options={authorOptions}
            onChange={(value) => setFilter('authorId', value)}
          />
          <FilterSelect
            label="Revisor"
            value={filters.reviewerId ?? 'all'}
            options={reviewerOptions}
            onChange={(value) => setFilter('reviewerId', value)}
          />
          <FilterSelect
            label="Agenda"
            value={filters.schedule ?? 'all'}
            options={[
              ['unscheduled', 'Sem agendamento'],
              ['scheduled', 'Agendado'],
              ['published', 'Publicado'],
            ]}
            onChange={(value) => setFilter('schedule', value)}
          />
          <FilterSelect
            label="Destaque"
            value={filters.featuredToday === undefined ? 'all' : String(filters.featuredToday)}
            options={[
              ['true', 'Em destaque'],
              ['false', 'Sem destaque'],
            ]}
            onChange={(value) =>
              navigate({
                ...filters,
                featuredToday: value === 'all' ? undefined : value === 'true',
              })
            }
          />
          <form className="min-w-0" onSubmit={submitText}>
            <p className="mb-1 font-mono text-[10px] uppercase text-muted-foreground">Texto</p>
            <div className="flex min-w-0 gap-2">
              <Input
                value={text}
                onChange={(event) => setText(event.target.value)}
                maxLength={120}
                placeholder="Titulo ou slug"
                className="min-w-0"
              />
              <Button type="submit" size="icon" variant="outline" aria-label="Buscar texto">
                <Search />
              </Button>
            </div>
          </form>
        </div>
      </section>

      {rows.length === 0 ? (
        <section className="flex min-h-56 flex-col items-center justify-center border-y border-border px-6 text-center">
          <SearchX className="h-6 w-6 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">Nenhuma publicacao encontrada</p>
          <p className="mt-1 text-xs text-muted-foreground">Revise os filtros selecionados.</p>
        </section>
      ) : (
        <>
          <section
            className="content-card hidden overflow-x-auto lg:block"
            aria-label="Publicacoes"
          >
            <Table className="min-w-[1120px] table-fixed">
              <TableHeader>
                <TableRow className="bg-muted/30 hover:bg-muted/30">
                  {[
                    'Publicacao',
                    'Status',
                    'Idiomas',
                    'Categoria',
                    'Autor',
                    'Revisor',
                    'Agenda',
                    'Destaque',
                    '',
                  ].map((label) => (
                    <TableHead
                      key={label || 'acao'}
                      className="h-9 px-3 font-mono text-[10px] uppercase text-muted-foreground"
                    >
                      {label}
                    </TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <PublicationDesktopRow key={row.publicationId} row={row} now={now} />
                ))}
              </TableBody>
            </Table>
          </section>

          <section
            className="divide-y divide-border border-y border-border lg:hidden"
            aria-label="Publicacoes"
          >
            {rows.map((row) => (
              <PublicationMobileRow key={row.publicationId} row={row} now={now} />
            ))}
          </section>
        </>
      )}

      <nav className="flex min-h-10 items-center justify-between gap-3" aria-label="Paginacao">
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={!hasPrevious}
          onClick={() => navigate(filters, page - 1)}
        >
          <ArrowLeft />
          Anterior
        </Button>
        <span className="font-mono text-[10px] text-muted-foreground">Pagina {page}</span>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={!hasNext}
          onClick={() => navigate(filters, page + 1)}
        >
          Proxima
          <ArrowRight />
        </Button>
      </nav>
    </TooltipProvider>
  )
}

function PublicationDesktopRow({ row, now }: { row: PublicationListRow; now: string }) {
  const primary =
    row.versions.find((version) => version.versionId === row.primaryVersionId) ??
    row.versions.find((version) => version.effectiveStatus === row.effectiveStatus) ??
    row.versions[0]
  const timing = primary ? scheduleLabel(primary, now) : { label: 'Sem agendamento' }
  return (
    <TableRow>
      <TableCell className="w-56 px-3 py-3">
        <p className="truncate text-sm font-medium">{primary?.title ?? row.slug}</p>
        <p className="mt-0.5 truncate font-mono text-[10px] text-muted-foreground">{row.slug}</p>
      </TableCell>
      <TableCell className="px-3">
        <StatusBadge status={row.effectiveStatus} />
      </TableCell>
      <TableCell className="px-3">
        <LocaleBadges locales={row.locales} />
      </TableCell>
      <TableCell className="truncate px-3 text-xs">
        {primary?.category ? CATEGORY_LABELS[primary.category] : 'Sem categoria'}
      </TableCell>
      <TableCell className="px-3 font-mono text-[10px]">
        {primary ? shortId(primary.authorId) : '-'}
      </TableCell>
      <TableCell className="px-3 font-mono text-[10px]">
        {primary?.reviewerId ? shortId(primary.reviewerId) : '-'}
      </TableCell>
      <TableCell className="px-3 text-[11px] text-muted-foreground">{timing.label}</TableCell>
      <TableCell className="px-3">
        {(
          row.primaryVersionId
            ? primary?.featuredToday
            : row.versions.some((version) => version.featuredToday)
        ) ? (
          <Star className="h-4 w-4 fill-current text-amber-500" aria-label="Em destaque" />
        ) : (
          '-'
        )}
      </TableCell>
      <TableCell className="w-12 px-2">
        <OpenPublication id={row.publicationId} />
      </TableCell>
    </TableRow>
  )
}

function PublicationMobileRow({ row, now }: { row: PublicationListRow; now: string }) {
  const primary =
    row.versions.find((version) => version.versionId === row.primaryVersionId) ??
    row.versions.find((version) => version.effectiveStatus === row.effectiveStatus) ??
    row.versions[0]
  const timing = primary ? scheduleLabel(primary, now).label : 'Sem agendamento'
  return (
    <div className="min-w-0 px-1 py-4 sm:px-2">
      <div className="flex min-w-0 items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="break-words text-sm font-medium">{primary?.title ?? row.slug}</p>
          <p className="mt-0.5 break-all font-mono text-[10px] text-muted-foreground">{row.slug}</p>
        </div>
        <OpenPublication id={row.publicationId} />
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <StatusBadge status={row.effectiveStatus} />
        <LocaleBadges locales={row.locales} />
        {(row.primaryVersionId
          ? primary?.featuredToday
          : row.versions.some((version) => version.featuredToday)) && (
          <Badge variant="outline" className="gap-1 text-[10px]">
            <Star className="h-3 w-3 fill-current" /> Destaque
          </Badge>
        )}
      </div>
      <dl className="mt-3 grid min-w-0 grid-cols-2 gap-x-4 gap-y-2 text-xs">
        <MobileDatum
          label="Categoria"
          value={primary?.category ? CATEGORY_LABELS[primary.category] : 'Sem categoria'}
        />
        <MobileDatum label="Agenda" value={timing} />
        <MobileDatum label="Autor" value={primary ? shortId(primary.authorId) : '-'} />
        <MobileDatum
          label="Revisor"
          value={primary?.reviewerId ? shortId(primary.reviewerId) : '-'}
        />
      </dl>
    </div>
  )
}

function MobileDatum({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <dt className="font-mono text-[9px] uppercase text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 break-words">{value}</dd>
    </div>
  )
}

function FilterSelect({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: readonly (readonly [string, string])[]
  onChange: (value: string) => void
}) {
  return (
    <div className="min-w-0">
      <p className="mb-1 font-mono text-[10px] uppercase text-muted-foreground">{label}</p>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todos</SelectItem>
          {options.map(([optionValue, optionLabel]) => (
            <SelectItem key={optionValue} value={optionValue}>
              {optionLabel}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}

function StatusBadge({ status }: { status: PublicationListRow['effectiveStatus'] }) {
  const variant =
    status === 'rejected' ? 'destructive' : status === 'published' ? 'default' : 'secondary'
  return (
    <Badge variant={variant} className="whitespace-nowrap text-[10px]">
      {STATUS_LABELS[status]}
    </Badge>
  )
}

function LocaleBadges({ locales }: { locales: PublicationListRow['locales'] }) {
  return (
    <div className="flex flex-wrap gap-1">
      {(['pt-BR', 'en-US'] as const).map((locale) => (
        <Badge
          key={locale}
          variant="outline"
          className={`font-mono text-[9px] ${locales.includes(locale) ? '' : 'border-amber-500/50 text-amber-700 dark:text-amber-400'}`}
        >
          {locales.includes(locale) ? locale : `${locale} ausente`}
        </Badge>
      ))}
    </div>
  )
}

function OpenPublication({ id }: { id: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button asChild size="icon" variant="ghost" className="h-8 w-8">
          <Link href={`/content/${id}`} aria-label="Abrir publicacao">
            <ArrowRight />
          </Link>
        </Button>
      </TooltipTrigger>
      <TooltipContent>Abrir publicacao</TooltipContent>
    </Tooltip>
  )
}

function shortId(value: string): string {
  return `${value.slice(0, 8)}...`
}
