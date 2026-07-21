'use client'

import { Eye, Pencil, SearchX } from 'lucide-react'
import { usePathname, useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
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
import type { AdminRole } from '@/lib/admin-rbac'
import type { CoachCatalogEntry, CoachContentPackSummary } from '@/lib/coach-messages/admin-service'
import {
  type CoachCatalogFilterState,
  groupCatalogEntries,
  packControlAvailability,
  serializeCoachCatalogFilters,
} from './catalog-presenter'
import { TemplateEditor } from './template-editor'

const PAGE_SIZE = 36

const PERSONALITY_OPTIONS = [
  ['balanced', 'Balanceada interna'],
  ['focus', 'Focus'],
  ['impulse', 'Impulse'],
  ['zen', 'Zen'],
] as const

const CONTEXT_OPTIONS = [
  ['onboarding', 'Onboarding'],
  ['meal_pending', 'Refeição pendente'],
  ['registration_confirmed', 'Registro confirmado'],
  ['error_corrected', 'Erro corrigido'],
  ['hydration', 'Hidratação'],
  ['supplement', 'Suplemento'],
  ['medication', 'Medicação'],
  ['workout', 'Treino'],
  ['progress', 'Progresso'],
  ['day_incomplete', 'Dia incompleto'],
  ['reevaluation', 'Reavaliação'],
  ['reengagement', 'Reengajamento'],
  ['trial', 'Trial'],
  ['paywall', 'Paywall'],
  ['return_after_abandonment', 'Retorno'],
] as const

const CHANNEL_OPTIONS = [
  ['in_app', 'No app'],
  ['push', 'Push'],
  ['email', 'Email'],
] as const

const LOCALE_OPTIONS = [
  ['pt-BR', 'Português'],
  ['en-US', 'Inglês'],
] as const

const STATUS_OPTIONS = [
  ['draft', 'Rascunho'],
  ['scheduled', 'Agendado'],
  ['active', 'Ativo'],
  ['archived', 'Arquivado'],
] as const

const PERSONALITY_LABELS = Object.fromEntries(PERSONALITY_OPTIONS) as Record<string, string>
const CONTEXT_LABELS = Object.fromEntries(CONTEXT_OPTIONS) as Record<string, string>
const CHANNEL_LABELS = Object.fromEntries(CHANNEL_OPTIONS) as Record<string, string>

export function CatalogTable({
  packs,
  selectedPack,
  entries,
  filters,
  role,
}: {
  packs: CoachContentPackSummary[]
  selectedPack: CoachContentPackSummary
  entries: CoachCatalogEntry[]
  filters: CoachCatalogFilterState
  role: AdminRole
}) {
  const router = useRouter()
  const pathname = usePathname()
  const [selectedEntry, setSelectedEntry] = useState<CoachCatalogEntry | null>(null)
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE)
  const groups = useMemo(() => groupCatalogEntries(entries), [entries])
  const visibleGroups = groups.slice(0, visibleCount)
  const availability = packControlAvailability(selectedPack.status, role)
  const packsForStatus = filters.status
    ? packs.filter((pack) => pack.status === filters.status)
    : packs

  function setFilter(key: keyof CoachCatalogFilterState, value: string) {
    const next = { ...filters, [key]: value === 'all' ? undefined : value }
    if (key === 'status') next.pack = undefined
    const query = serializeCoachCatalogFilters(next)
    router.push(query ? `${pathname}?${query}` : pathname, { scroll: false })
  }

  return (
    <TooltipProvider>
      <section className="content-card" aria-label="Filtros do catálogo">
        <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-6">
          <FilterSelect
            label="Status"
            value={filters.status ?? 'all'}
            options={STATUS_OPTIONS}
            onChange={(value) => setFilter('status', value)}
          />
          <FilterSelect
            label="Pack"
            value={selectedPack.id}
            options={packsForStatus.map((pack) => [pack.id, pack.label] as const)}
            onChange={(value) => setFilter('pack', value)}
          />
          <FilterSelect
            label="Personalidade"
            value={filters.personality ?? 'all'}
            options={PERSONALITY_OPTIONS}
            onChange={(value) => setFilter('personality', value)}
          />
          <FilterSelect
            label="Contexto"
            value={filters.context ?? 'all'}
            options={CONTEXT_OPTIONS}
            onChange={(value) => setFilter('context', value)}
          />
          <FilterSelect
            label="Canal"
            value={filters.channel ?? 'all'}
            options={CHANNEL_OPTIONS}
            onChange={(value) => setFilter('channel', value)}
          />
          <FilterSelect
            label="Idioma"
            value={filters.locale ?? 'all'}
            options={LOCALE_OPTIONS}
            onChange={(value) => setFilter('locale', value)}
          />
        </div>
      </section>

      {groups.length === 0 ? (
        <section className="content-card flex min-h-56 flex-col items-center justify-center px-6 text-center">
          <SearchX className="h-6 w-6 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">Nenhuma mensagem encontrada</p>
          <p className="mt-1 text-xs text-muted-foreground">Revise os filtros selecionados.</p>
        </section>
      ) : (
        <>
          <section
            className="content-card hidden overflow-hidden lg:block"
            aria-label="Mensagens do coach"
          >
            <Table className="table-fixed">
              <TableHeader>
                <TableRow className="bg-muted/30 hover:bg-muted/30">
                  <TableHead className="w-52 px-4 font-mono text-[10px] uppercase tracking-widest">
                    Grupo
                  </TableHead>
                  <TableHead className="font-mono text-[10px] uppercase tracking-widest">
                    Variante 1
                  </TableHead>
                  <TableHead className="font-mono text-[10px] uppercase tracking-widest">
                    Variante 2
                  </TableHead>
                  <TableHead className="font-mono text-[10px] uppercase tracking-widest">
                    Variante 3
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {visibleGroups.map((group) => (
                  <TableRow key={group.key} className="align-top">
                    <TableCell className="px-4 py-3 align-top">
                      <GroupIdentity group={group} />
                    </TableCell>
                    {[1, 2, 3].map((variant) => {
                      const entry = group.variants.find(
                        (candidate) => candidate.variant === variant,
                      )
                      return (
                        <TableCell key={variant} className="min-w-0 py-3 align-top">
                          {entry ? (
                            <VariantCopy
                              entry={entry}
                              canEdit={availability.canEdit}
                              onOpen={() => setSelectedEntry(entry)}
                            />
                          ) : (
                            <Badge variant="outline" className="text-amber-700 dark:text-amber-400">
                              Ausente
                            </Badge>
                          )}
                        </TableCell>
                      )
                    })}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </section>

          <section
            className="content-card divide-y divide-border lg:hidden"
            aria-label="Mensagens do coach"
          >
            {visibleGroups.map((group) => (
              <div key={group.key} className="px-4 py-4">
                <GroupIdentity group={group} />
                <div className="mt-3 divide-y divide-border/60 border-y border-border/60">
                  {[1, 2, 3].map((variant) => {
                    const entry = group.variants.find((candidate) => candidate.variant === variant)
                    return (
                      <div key={variant} className="py-3">
                        <p className="mb-2 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
                          Variante {variant}
                        </p>
                        {entry ? (
                          <VariantCopy
                            entry={entry}
                            canEdit={availability.canEdit}
                            onOpen={() => setSelectedEntry(entry)}
                          />
                        ) : (
                          <Badge variant="outline" className="text-amber-700 dark:text-amber-400">
                            Ausente
                          </Badge>
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>
            ))}
          </section>

          {visibleCount < groups.length && (
            <div className="flex justify-center">
              <Button
                variant="outline"
                onClick={() => setVisibleCount((current) => current + PAGE_SIZE)}
              >
                Carregar mais
              </Button>
            </div>
          )}
        </>
      )}

      {selectedEntry && (
        <TemplateEditor
          entry={selectedEntry}
          canEdit={availability.canEdit}
          canAssist={availability.canAssist}
          onCloseAction={() => setSelectedEntry(null)}
        />
      )}
    </TooltipProvider>
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
      <p className="mb-1 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
        {label}
      </p>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {label !== 'Pack' && <SelectItem value="all">Todos</SelectItem>}
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

function GroupIdentity({ group }: { group: ReturnType<typeof groupCatalogEntries>[number] }) {
  return (
    <div className="min-w-0">
      <p className="truncate text-sm font-medium">
        {PERSONALITY_LABELS[group.personality] ?? group.personality}
      </p>
      <p className="mt-0.5 break-words text-xs text-muted-foreground">
        {CONTEXT_LABELS[group.context] ?? group.context}
      </p>
      <div className="mt-2 flex flex-wrap gap-1.5">
        <Badge variant="outline" className="font-mono text-[10px]">
          {CHANNEL_LABELS[group.channel] ?? group.channel}
        </Badge>
        <Badge variant="secondary" className="font-mono text-[10px]">
          {group.locale}
        </Badge>
      </div>
    </div>
  )
}

function VariantCopy({
  entry,
  canEdit,
  onOpen,
}: {
  entry: CoachCatalogEntry
  canEdit: boolean
  onOpen: () => void
}) {
  const Icon = canEdit ? Pencil : Eye
  const actionLabel = canEdit ? 'Editar variante' : 'Inspecionar variante'
  return (
    <div className="flex min-w-0 items-start gap-2">
      <div className="min-w-0 flex-1">
        {entry.title && <p className="truncate text-xs font-semibold">{entry.title}</p>}
        {entry.subject && <p className="truncate text-xs font-medium">{entry.subject}</p>}
        <p className="line-clamp-3 break-words text-xs leading-relaxed text-muted-foreground">
          {entry.body}
        </p>
        <p className="mt-2 font-mono text-[9px] text-muted-foreground">
          v{entry.version} · {entry.provenance}
        </p>
      </div>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            size="icon"
            variant="ghost"
            className="h-8 w-8 shrink-0"
            aria-label={actionLabel}
            onClick={onOpen}
          >
            <Icon className="h-3.5 w-3.5" />
          </Button>
        </TooltipTrigger>
        <TooltipContent>{actionLabel}</TooltipContent>
      </Tooltip>
    </div>
  )
}
