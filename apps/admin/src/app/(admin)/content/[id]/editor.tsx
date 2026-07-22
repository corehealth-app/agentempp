'use client'

import type { ContentDraftInput } from '@mpp/core'
import { FilePlus2, Loader2, RefreshCw, Save, Send } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useCallback, useEffect, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import type { AdminRole } from '@/lib/admin-rbac'
import type { ContentPublicationDetail } from '@/lib/content/admin-service'
import { contentNavigationBlocked, useContentNavigationGuard } from '@/lib/content/navigation-guard'
import {
  createContentDraftAction,
  getContentPublicationAction,
  saveContentDraftAction,
  submitContentVersionAction,
} from '../actions'
import {
  type ConfirmedDraftCover,
  type ConfirmedDraftCoverEvent,
  confirmedCoverAssetForLocale,
  coverPublicationLocked,
  type PendingCoverResolution,
  transitionConfirmedDraftCover,
} from '../cover-flow'
import {
  buildDraftSavePayload,
  type ContentLocale,
  canCreateContentDraft,
  createDraftEditBaseline,
  type DraftSaveState,
  formatOperationalDate,
  isDraftDirty,
  localeSwitchDecision,
  markDraftSaveStale,
  normalizeDraftTags,
  recoverDraftSaveState,
  selectLocaleVersions,
  selectWorkflowContentVersion,
} from '../presenter'
import { CoverUploader } from './cover-uploader'
import { MarkdownPreview } from './markdown-preview'
import { WorkflowControls } from './workflow-controls'

type Version = ContentPublicationDetail['versions'][number]
type Targeting = Version['targeting']

const CATEGORY_OPTIONS: Array<[ContentDraftInput['category'], string]> = [
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
]

const PROTOCOL_OPTIONS = [
  ['recomposicao', 'Recomposicao'],
  ['ganho_massa', 'Ganho de massa'],
  ['manutencao', 'Manutencao'],
] as const
const PLAN_OPTIONS = [
  ['trial', 'Trial'],
  ['mensal', 'Mensal'],
  ['anual', 'Anual'],
] as const
const PERSONALITY_OPTIONS = [
  ['focus', 'Focus'],
  ['impulse', 'Impulse'],
  ['zen', 'Zen'],
] as const

const STATUS_LABELS: Record<Version['state'], string> = {
  draft: 'Rascunho',
  in_review: 'Em revisao',
  approved: 'Aprovado',
  rejected: 'Rejeitado',
}

const UNSAVED_CHANGES_WARNING = 'Existem alteracoes nao salvas. Deseja descarta-las e continuar?'

export function ContentEditor({
  publication,
  role,
  initialError,
  now,
}: {
  publication: ContentPublicationDetail
  role: AdminRole
  initialError?: string
  now: string
}) {
  const [activeLocale, setActiveLocale] = useState<ContentLocale>('pt-BR')
  const [pendingCoverResolution, setPendingCoverResolution] =
    useState<PendingCoverResolution | null>(null)
  const [confirmedDraftCover, setConfirmedDraftCover] = useState<ConfirmedDraftCover | null>(null)
  const [coverBusy, setCoverBusy] = useState(false)
  const [dirtyLocales, setDirtyLocales] = useState<Record<ContentLocale, boolean>>({
    'pt-BR': false,
    'en-US': false,
  })
  const coverLocked = coverPublicationLocked(pendingCoverResolution, coverBusy, confirmedDraftCover)
  const hasUnsavedChanges = contentNavigationBlocked({
    dirty: confirmedDraftCover !== null || dirtyLocales['pt-BR'] || dirtyLocales['en-US'],
    coverBusy,
    pendingCoverResolution: pendingCoverResolution !== null,
  })
  const activeWorkflowVersion = selectWorkflowContentVersion(
    publication.versions,
    activeLocale,
    role,
    publication.archivedAt,
  )
  useContentNavigationGuard(hasUnsavedChanges)

  const updateLocaleDirty = useCallback((locale: ContentLocale, dirty: boolean) => {
    setDirtyLocales((current) =>
      current[locale] === dirty ? current : { ...current, [locale]: dirty },
    )
  }, [])

  function updateConfirmedDraftCover(event: ConfirmedDraftCoverEvent) {
    setConfirmedDraftCover((current) => transitionConfirmedDraftCover(current, event))
  }

  function changeLocale(nextLocale: ContentLocale) {
    const decision = localeSwitchDecision(
      activeLocale,
      nextLocale,
      dirtyLocales[activeLocale],
      coverLocked,
    )
    if (decision === 'stay') return
    if (decision === 'confirm_discard' && !window.confirm(UNSAVED_CHANGES_WARNING)) return
    updateLocaleDirty(activeLocale, false)
    setActiveLocale(nextLocale)
  }

  return (
    <div className="space-y-4">
      {initialError && (
        <p
          role="alert"
          className="border-l-2 border-destructive bg-destructive/5 px-3 py-2 text-sm text-destructive"
        >
          {initialError}
        </p>
      )}
      <Tabs value={activeLocale} onValueChange={(value) => changeLocale(value as ContentLocale)}>
        <TabsList className="grid h-10 w-full max-w-sm grid-cols-2 rounded-lg">
          <TabsTrigger value="pt-BR" disabled={coverLocked}>
            Portugues · pt-BR
          </TabsTrigger>
          <TabsTrigger value="en-US" disabled={coverLocked}>
            Ingles · en-US
          </TabsTrigger>
        </TabsList>
        {(['pt-BR', 'en-US'] as const).map((locale) => {
          const selection = selectLocaleVersions(publication.versions, locale, now)
          return (
            <TabsContent key={locale} value={locale} className="mt-4">
              <LocaleEditor
                key={selection.latest?.versionId ?? `missing-${locale}`}
                publicationId={publication.publicationId}
                locale={locale}
                version={selection.latest}
                canCreateDraft={canCreateContentDraft(
                  publication.versions,
                  locale,
                  publication.archivedAt,
                )}
                previousPublished={selection.previousPublished}
                futureScheduled={selection.futureScheduled}
                role={role}
                archived={Boolean(publication.archivedAt)}
                pendingCoverResolution={pendingCoverResolution}
                confirmedDraftCover={confirmedDraftCover}
                coverBusy={coverBusy}
                coverLocked={coverLocked}
                onPendingCoverResolutionChange={setPendingCoverResolution}
                onConfirmedDraftCoverEvent={updateConfirmedDraftCover}
                onCoverBusyChange={setCoverBusy}
                onDirtyChange={updateLocaleDirty}
              />
            </TabsContent>
          )
        })}
      </Tabs>
      <WorkflowControls
        role={role}
        publicationId={publication.publicationId}
        archivedAt={publication.archivedAt}
        version={activeWorkflowVersion}
      />
    </div>
  )
}

function LocaleEditor({
  publicationId,
  locale,
  version,
  canCreateDraft,
  previousPublished,
  futureScheduled,
  role,
  archived,
  pendingCoverResolution,
  confirmedDraftCover,
  coverBusy,
  coverLocked,
  onPendingCoverResolutionChange,
  onConfirmedDraftCoverEvent,
  onCoverBusyChange,
  onDirtyChange,
}: {
  publicationId: string
  locale: ContentLocale
  version: Version | null
  canCreateDraft: boolean
  previousPublished: Version | null
  futureScheduled: Version | null
  role: AdminRole
  archived: boolean
  pendingCoverResolution: PendingCoverResolution | null
  confirmedDraftCover: ConfirmedDraftCover | null
  coverBusy: boolean
  coverLocked: boolean
  onPendingCoverResolutionChange: (pending: PendingCoverResolution | null) => void
  onConfirmedDraftCoverEvent: (event: ConfirmedDraftCoverEvent) => void
  onCoverBusyChange: (busy: boolean) => void
  onDirtyChange: (locale: ContentLocale, dirty: boolean) => void
}) {
  const router = useRouter()
  const [creating, setCreating] = useState(false)
  const [message, setMessage] = useState<{ tone: 'error' | 'success'; text: string } | null>(null)

  async function createDraft() {
    setCreating(true)
    setMessage(null)
    const result = await createContentDraftAction({
      publicationId,
      locale,
      ...(version ? { sourceVersionId: version.versionId } : {}),
    })
    setCreating(false)
    if (!result.ok) {
      setMessage({ tone: 'error', text: result.error })
      return
    }
    setMessage({ tone: 'success', text: 'Rascunho criado.' })
    router.refresh()
  }

  if (!version) {
    return (
      <section className="flex min-h-64 flex-col items-center justify-center border-y border-border px-5 text-center">
        <p className="text-sm font-medium">Nenhuma versao em {locale}</p>
        {role === 'content_editor' && canCreateDraft && (
          <Button className="mt-4" size="sm" onClick={() => void createDraft()} disabled={creating}>
            {creating ? <Loader2 className="animate-spin" /> : <FilePlus2 />}
            Criar rascunho
          </Button>
        )}
        <ActionMessage message={message} />
      </section>
    )
  }

  const canEdit = role === 'content_editor' && version.state === 'draft' && !archived

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3 border-y border-border py-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">{STATUS_LABELS[version.state]}</Badge>
          <span className="font-mono text-[10px] text-muted-foreground">
            v{version.version} · atualizado {formatOperationalDate(version.updatedAt)}
          </span>
        </div>
        {role === 'content_editor' && canCreateDraft && (
          <Button
            size="sm"
            variant="outline"
            onClick={() => void createDraft()}
            disabled={creating}
          >
            {creating ? <Loader2 className="animate-spin" /> : <FilePlus2 />}
            Novo rascunho
          </Button>
        )}
      </div>
      {previousPublished && (
        <div className="border-l-2 border-emerald-600 bg-emerald-500/5 px-3 py-2 text-xs">
          <span className="font-medium">Versao publicada preservada:</span> v
          {previousPublished.version} · {previousPublished.title ?? locale} ·{' '}
          {formatOperationalDate(previousPublished.publishAt ?? previousPublished.updatedAt)}
        </div>
      )}
      {futureScheduled && (
        <div className="border-l-2 border-amber-500 bg-amber-500/5 px-3 py-2 text-xs text-amber-900 dark:text-amber-200">
          <span className="font-medium">Versao agendada:</span> v{futureScheduled.version} ·{' '}
          {futureScheduled.title ?? locale} · efetiva em{' '}
          {formatOperationalDate(futureScheduled.publishAt ?? futureScheduled.updatedAt)}
        </div>
      )}
      <ActionMessage message={message} />
      <VersionMetadata version={version} />
      <DraftForm
        publicationId={publicationId}
        version={version}
        canEdit={canEdit}
        role={role}
        pendingCoverResolution={pendingCoverResolution}
        confirmedDraftCover={confirmedDraftCover}
        coverBusy={coverBusy}
        coverLocked={coverLocked}
        onPendingCoverResolutionChange={onPendingCoverResolutionChange}
        onConfirmedDraftCoverEvent={onConfirmedDraftCoverEvent}
        onCoverBusyChange={onCoverBusyChange}
        onDirtyChange={onDirtyChange}
      />
    </div>
  )
}

function DraftForm({
  publicationId,
  version,
  canEdit,
  role,
  pendingCoverResolution,
  confirmedDraftCover,
  coverBusy,
  coverLocked,
  onPendingCoverResolutionChange,
  onConfirmedDraftCoverEvent,
  onCoverBusyChange,
  onDirtyChange,
}: {
  publicationId: string
  version: Version
  canEdit: boolean
  role: AdminRole
  pendingCoverResolution: PendingCoverResolution | null
  confirmedDraftCover: ConfirmedDraftCover | null
  coverBusy: boolean
  coverLocked: boolean
  onPendingCoverResolutionChange: (pending: PendingCoverResolution | null) => void
  onConfirmedDraftCoverEvent: (event: ConfirmedDraftCoverEvent) => void
  onCoverBusyChange: (busy: boolean) => void
  onDirtyChange: (locale: ContentLocale, dirty: boolean) => void
}) {
  const router = useRouter()
  const [title, setTitle] = useState(version.title ?? '')
  const [excerpt, setExcerpt] = useState(version.excerpt ?? '')
  const [category, setCategory] = useState<ContentDraftInput['category']>(
    version.category ?? 'nutrition',
  )
  const [tagInput, setTagInput] = useState(version.tags.join(', '))
  const [featuredToday, setFeaturedToday] = useState(version.featuredToday)
  const [targeting, setTargeting] = useState<Targeting>(version.targeting)
  const [bodyMarkdown, setBodyMarkdown] = useState(version.bodyMarkdown ?? '')
  const [coverAssetId, setCoverAssetId] = useState<string | null>(version.cover?.assetId ?? null)
  const [editBaseline, setEditBaseline] = useState(() => createDraftEditBaseline(version))
  const [saveState, setSaveState] = useState<DraftSaveState>({
    versionId: version.versionId,
    expectedUpdatedAt: version.updatedAt,
    stale: false,
    confirmedCover: confirmedDraftCover,
  })
  const [pending, setPending] = useState<'save' | 'submit' | 'recover' | null>(null)
  const [message, setMessage] = useState<{ tone: 'error' | 'success'; text: string } | null>(null)

  function currentDraft(): ContentDraftInput {
    const confirmedAssetId = confirmedCoverAssetForLocale(confirmedDraftCover, version.locale)
    return {
      locale: version.locale,
      category,
      title,
      excerpt,
      bodyMarkdown,
      tags: normalizeDraftTags(tagInput),
      featuredToday,
      coverAssetId: confirmedAssetId ?? coverAssetId,
      targeting,
    }
  }

  const dirty = isDraftDirty(editBaseline, currentDraft(), canEdit)
  useEffect(() => {
    onDirtyChange(version.locale, dirty)
    return () => onDirtyChange(version.locale, false)
  }, [dirty, onDirtyChange, version.locale])

  async function persist(andSubmit: boolean) {
    if (coverBusy || pendingCoverResolution || saveState.stale) return
    const attemptState = { ...saveState, confirmedCover: confirmedDraftCover }
    const payload = buildDraftSavePayload(attemptState, currentDraft())
    if (!payload) return
    setPending(andSubmit ? 'submit' : 'save')
    setMessage(null)
    const saveResult = await saveContentDraftAction(payload)
    if (!saveResult.ok) {
      onConfirmedDraftCoverEvent({ type: 'save', locale: version.locale, succeeded: false })
      if (saveResult.code === 'stale') setSaveState(markDraftSaveStale(attemptState))
      setPending(null)
      setMessage({ tone: 'error', text: saveResult.error })
      return
    }
    const saved = saveResult.data as { updatedAt: string }
    const savedState: DraftSaveState = {
      ...attemptState,
      expectedUpdatedAt: saved.updatedAt,
      stale: false,
      confirmedCover: null,
    }
    onConfirmedDraftCoverEvent({ type: 'save', locale: version.locale, succeeded: true })
    setSaveState(savedState)
    setEditBaseline({ versionId: version.versionId, draft: payload.draft })
    onDirtyChange(version.locale, false)
    setTagInput(normalizeDraftTags(tagInput).join(', '))
    if (andSubmit) {
      const submitResult = await submitContentVersionAction({
        versionId: version.versionId,
        expectedUpdatedAt: saved.updatedAt,
      })
      if (!submitResult.ok) {
        if (submitResult.code === 'stale') setSaveState(markDraftSaveStale(savedState))
        setPending(null)
        setMessage({ tone: 'error', text: submitResult.error })
        return
      }
    }
    setPending(null)
    setMessage({
      tone: 'success',
      text: andSubmit ? 'Versao enviada para revisao.' : 'Rascunho salvo.',
    })
    router.refresh()
  }

  async function recoverBaseline() {
    if (!saveState.stale || pending !== null) return
    setPending('recover')
    setMessage(null)
    const result = await getContentPublicationAction({ publicationId })
    if (!result.ok) {
      setPending(null)
      setMessage({
        tone: 'error',
        text: `Não foi possível atualizar a baseline. ${result.error}`,
      })
      return
    }
    const currentPublication = result.data as ContentPublicationDetail | null
    const recovery = currentPublication
      ? recoverDraftSaveState(saveState, currentPublication.versions)
      : { recovered: false as const, state: saveState }
    if (!recovery.recovered) {
      setPending(null)
      setMessage({
        tone: 'error',
        text: 'A versão não está mais disponível como rascunho. Suas edições e a capa foram preservadas.',
      })
      return
    }
    const recoveredDraft = recovery.baseline.draft
    setTitle(recoveredDraft.title)
    setExcerpt(recoveredDraft.excerpt)
    setCategory(recoveredDraft.category)
    setTagInput(recoveredDraft.tags.join(', '))
    setFeaturedToday(recoveredDraft.featuredToday)
    setTargeting(recoveredDraft.targeting)
    setBodyMarkdown(recoveredDraft.bodyMarkdown)
    setCoverAssetId(recoveredDraft.coverAssetId)
    setEditBaseline(recovery.baseline)
    setSaveState(recovery.state)
    setPending(null)
    setMessage({
      tone: 'success',
      text: recovery.state.confirmedCover
        ? 'A versão atual foi carregada e as edições locais foram descartadas. A capa enviada permanece pendente de salvar.'
        : 'A versão atual foi carregada e as edições locais foram descartadas.',
    })
  }

  function toggleTarget(key: keyof Targeting, value: string) {
    setTargeting((current) => {
      const values = current[key] as string[]
      const next = values.includes(value)
        ? values.filter((candidate) => candidate !== value)
        : [...values, value]
      return { ...current, [key]: next } as Targeting
    })
  }

  return (
    <section className="content-card overflow-hidden">
      <div className="grid min-w-0 gap-0 xl:grid-cols-2 xl:divide-x xl:divide-border">
        <div className="min-w-0 space-y-5 p-4 sm:p-5">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Titulo" htmlFor={`title-${version.versionId}`} className="sm:col-span-2">
              <Input
                id={`title-${version.versionId}`}
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                disabled={!canEdit}
                minLength={3}
                maxLength={120}
              />
            </Field>
            <Field label="Categoria" htmlFor={`category-${version.versionId}`}>
              <Select
                value={category}
                onValueChange={(value) => setCategory(value as ContentDraftInput['category'])}
                disabled={!canEdit}
              >
                <SelectTrigger id={`category-${version.versionId}`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CATEGORY_OPTIONS.map(([value, label]) => (
                    <SelectItem key={value} value={value}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <div className="flex min-h-16 items-end pb-1">
              <div className="flex items-center gap-2">
                <Switch
                  id={`featured-${version.versionId}`}
                  checked={featuredToday}
                  onCheckedChange={setFeaturedToday}
                  disabled={!canEdit}
                />
                <Label htmlFor={`featured-${version.versionId}`}>Destaque de hoje</Label>
              </div>
            </div>
            <Field
              label="Resumo"
              htmlFor={`excerpt-${version.versionId}`}
              className="sm:col-span-2"
            >
              <Textarea
                id={`excerpt-${version.versionId}`}
                value={excerpt}
                onChange={(event) => setExcerpt(event.target.value)}
                disabled={!canEdit}
                minLength={20}
                maxLength={280}
                className="min-h-24 resize-y"
              />
            </Field>
            <Field label="Tags" htmlFor={`tags-${version.versionId}`} className="sm:col-span-2">
              <Input
                id={`tags-${version.versionId}`}
                value={tagInput}
                onChange={(event) => setTagInput(event.target.value)}
                onBlur={() => canEdit && setTagInput(normalizeDraftTags(tagInput).join(', '))}
                disabled={!canEdit}
                placeholder="habitos, alimentacao-consciente"
              />
            </Field>
          </div>

          <div className="grid gap-4 sm:grid-cols-3">
            <TargetGroup
              label="Protocolos"
              values={targeting.protocols}
              options={PROTOCOL_OPTIONS}
              disabled={!canEdit}
              onToggle={(value) => toggleTarget('protocols', value)}
            />
            <TargetGroup
              label="Planos"
              values={targeting.plans}
              options={PLAN_OPTIONS}
              disabled={!canEdit}
              onToggle={(value) => toggleTarget('plans', value)}
            />
            <TargetGroup
              label="Personalidades"
              values={targeting.personalities}
              options={PERSONALITY_OPTIONS}
              disabled={!canEdit}
              onToggle={(value) => toggleTarget('personalities', value)}
            />
          </div>

          <CoverUploader
            cover={version.cover}
            disabled={!canEdit}
            publicationLocked={coverLocked}
            pendingResolution={pendingCoverResolution}
            locale={version.locale}
            confirmedDraftCover={confirmedDraftCover}
            draftPending={pending !== null}
            onAssetChange={setCoverAssetId}
            onPendingResolutionChange={onPendingCoverResolutionChange}
            onConfirmedDraftCoverEvent={onConfirmedDraftCoverEvent}
            onBusyChange={onCoverBusyChange}
          />

          <Field label="Markdown" htmlFor={`body-${version.versionId}`}>
            <Textarea
              id={`body-${version.versionId}`}
              value={bodyMarkdown}
              onChange={(event) => setBodyMarkdown(event.target.value)}
              disabled={!canEdit}
              className="min-h-[360px] resize-y font-mono text-xs leading-relaxed"
              spellCheck
            />
          </Field>

          {canEdit && saveState.stale && (
            <div
              role="alert"
              className="flex flex-wrap items-center justify-between gap-3 border-l-2 border-amber-500 bg-amber-500/5 px-3 py-3"
            >
              <p className="max-w-2xl text-xs text-amber-900 dark:text-amber-200">
                Conflito detectado. As edições e a capa foram preservadas; atualize somente a
                baseline antes de uma nova tentativa.
              </p>
              <Button
                size="sm"
                variant="outline"
                disabled={pending !== null}
                onClick={() => void recoverBaseline()}
              >
                {pending === 'recover' ? <Loader2 className="animate-spin" /> : <RefreshCw />}
                Atualizar baseline
              </Button>
            </div>
          )}

          {canEdit && role === 'content_editor' && (
            <div className="flex flex-wrap justify-end gap-2 border-t border-border pt-4">
              <Button
                variant="outline"
                disabled={
                  pending !== null ||
                  coverBusy ||
                  pendingCoverResolution !== null ||
                  saveState.stale
                }
                onClick={() => void persist(false)}
              >
                {pending === 'save' ? <Loader2 className="animate-spin" /> : <Save />}Salvar
                rascunho
              </Button>
              <Button
                disabled={
                  pending !== null ||
                  coverBusy ||
                  pendingCoverResolution !== null ||
                  saveState.stale
                }
                onClick={() => void persist(true)}
              >
                {pending === 'submit' ? <Loader2 className="animate-spin" /> : <Send />}Enviar para
                revisao
              </Button>
            </div>
          )}
          <ActionMessage message={message} />
          {!canEdit && (
            <p className="text-xs text-muted-foreground">Visualizacao somente leitura.</p>
          )}
        </div>

        <div className="min-w-0 bg-muted/10 p-4 sm:p-5">
          <p className="mb-2 font-mono text-[10px] uppercase text-muted-foreground">Previa</p>
          <MarkdownPreview markdown={bodyMarkdown} />
        </div>
      </div>
    </section>
  )
}

function Field({
  label,
  htmlFor,
  className,
  children,
}: {
  label: string
  htmlFor: string
  className?: string
  children: React.ReactNode
}) {
  return (
    <div className={`min-w-0 space-y-2 ${className ?? ''}`}>
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
    </div>
  )
}

function TargetGroup({
  label,
  values,
  options,
  disabled,
  onToggle,
}: {
  label: string
  values: readonly string[]
  options: readonly (readonly [string, string])[]
  disabled: boolean
  onToggle: (value: string) => void
}) {
  return (
    <fieldset className="min-w-0 space-y-2">
      <legend className="text-sm font-medium">{label}</legend>
      {options.map(([value, optionLabel]) => (
        <label key={value} className="flex min-h-8 items-center gap-2 text-xs">
          <input
            type="checkbox"
            checked={values.includes(value)}
            disabled={disabled}
            onChange={() => onToggle(value)}
            className="h-4 w-4 shrink-0 accent-primary"
          />
          <span className="break-words">{optionLabel}</span>
        </label>
      ))}
    </fieldset>
  )
}

function ActionMessage({
  message,
}: {
  message: { tone: 'error' | 'success'; text: string } | null
}) {
  return (
    <div className="min-h-5" aria-live="polite">
      {message && (
        <p
          className={`text-xs ${message.tone === 'error' ? 'text-destructive' : 'text-emerald-700 dark:text-emerald-400'}`}
        >
          {message.text}
        </p>
      )}
    </div>
  )
}

function VersionMetadata({ version }: { version: Version }) {
  const metadata = [
    ['Autor', identityLabel(version.author)],
    ['Revisor', identityLabel(version.reviewer)],
    ['Publicador', identityLabel(version.publisher)],
    ['Enviada para revisao', timestampLabel(version.submittedAt)],
    ['Revisada', timestampLabel(version.reviewedAt)],
    ['Comando de publicacao', timestampLabel(version.publishedAt)],
    ['Publicacao efetiva', timestampLabel(version.publishAt)],
    ['Tempo de leitura', version.readingTimeMinutes ? `${version.readingTimeMinutes} min` : '-'],
    ['Hash do conteudo', version.bodyHash ? `${version.bodyHash.slice(0, 12)}...` : '-'],
  ] as const

  return (
    <section className="border-y border-border py-3" aria-label="Metadados editoriais">
      <p className="mb-3 font-mono text-[10px] uppercase text-muted-foreground">
        Metadados editoriais
      </p>
      <dl className="grid min-w-0 gap-x-5 gap-y-3 sm:grid-cols-2 xl:grid-cols-3">
        {metadata.map(([label, value]) => (
          <div key={label} className="min-w-0">
            <dt className="font-mono text-[9px] uppercase text-muted-foreground">{label}</dt>
            <dd className="mt-0.5 break-words text-xs">{value}</dd>
          </div>
        ))}
        {version.rejectionReason && (
          <div className="min-w-0 sm:col-span-2 xl:col-span-3">
            <dt className="font-mono text-[9px] uppercase text-muted-foreground">
              Motivo da rejeicao
            </dt>
            <dd className="mt-0.5 whitespace-pre-wrap break-words text-xs">
              {version.rejectionReason}
            </dd>
          </div>
        )}
      </dl>
    </section>
  )
}

function identityLabel(identity: Version['author'] | null): string {
  if (!identity) return '-'
  const label = identity.name?.trim() || identity.role
  return `${label} · ${shortId(identity.id)}`
}

function timestampLabel(value: string | null): string {
  return value ? formatOperationalDate(value) : '-'
}

function shortId(value: string): string {
  return `${value.slice(0, 8)}...`
}
