'use client'

import type { ContentDraftInput } from '@mpp/core'
import { FilePlus2, Loader2, Save, Send } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
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
import {
  createContentDraftAction,
  saveContentDraftAction,
  submitContentVersionAction,
} from '../actions'
import { type ContentLocale, selectLocaleVersions } from '../presenter'
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

export function ContentEditor({
  publication,
  role,
  initialError,
}: {
  publication: ContentPublicationDetail
  role: AdminRole
  initialError?: string
}) {
  const [activeLocale, setActiveLocale] = useState<ContentLocale>('pt-BR')
  const activeSelection = selectLocaleVersions(publication.versions, activeLocale)

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
      <Tabs value={activeLocale} onValueChange={(value) => setActiveLocale(value as ContentLocale)}>
        <TabsList className="grid h-10 w-full max-w-sm grid-cols-2 rounded-lg">
          <TabsTrigger value="pt-BR">Portugues · pt-BR</TabsTrigger>
          <TabsTrigger value="en-US">Ingles · en-US</TabsTrigger>
        </TabsList>
        {(['pt-BR', 'en-US'] as const).map((locale) => {
          const selection = selectLocaleVersions(publication.versions, locale)
          return (
            <TabsContent key={locale} value={locale} className="mt-4">
              <LocaleEditor
                key={selection.latest?.versionId ?? `missing-${locale}`}
                publicationId={publication.publicationId}
                locale={locale}
                version={selection.latest}
                previousPublished={selection.previousPublished}
                role={role}
                archived={Boolean(publication.archivedAt)}
              />
            </TabsContent>
          )
        })}
      </Tabs>
      <WorkflowControls
        role={role}
        publicationId={publication.publicationId}
        archivedAt={publication.archivedAt}
        version={activeSelection.latest}
      />
    </div>
  )
}

function LocaleEditor({
  publicationId,
  locale,
  version,
  previousPublished,
  role,
  archived,
}: {
  publicationId: string
  locale: ContentLocale
  version: Version | null
  previousPublished: Version | null
  role: AdminRole
  archived: boolean
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
        {role === 'content_editor' && !archived && (
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
            v{version.version} · atualizado {formatDate(version.updatedAt)}
          </span>
        </div>
        {role === 'content_editor' && version.state !== 'draft' && !archived && (
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
          {formatDate(
            previousPublished.publishedAt ??
              previousPublished.publishAt ??
              previousPublished.updatedAt,
          )}
        </div>
      )}
      <ActionMessage message={message} />
      <DraftForm version={version} canEdit={canEdit} role={role} />
    </div>
  )
}

function DraftForm({
  version,
  canEdit,
  role,
}: {
  version: Version
  canEdit: boolean
  role: AdminRole
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
  const [expectedUpdatedAt, setExpectedUpdatedAt] = useState(version.updatedAt)
  const [pending, setPending] = useState<'save' | 'submit' | null>(null)
  const [message, setMessage] = useState<{ tone: 'error' | 'success'; text: string } | null>(null)

  function draft(): ContentDraftInput {
    return {
      locale: version.locale,
      category,
      title,
      excerpt,
      bodyMarkdown,
      tags: normalizeTags(tagInput),
      featuredToday,
      coverAssetId,
      targeting,
    }
  }

  async function persist(andSubmit: boolean) {
    setPending(andSubmit ? 'submit' : 'save')
    setMessage(null)
    const saveResult = await saveContentDraftAction({
      versionId: version.versionId,
      expectedUpdatedAt,
      draft: draft(),
    })
    if (!saveResult.ok) {
      setPending(null)
      setMessage({ tone: 'error', text: saveResult.error })
      return
    }
    const saved = saveResult.data as { updatedAt: string }
    setExpectedUpdatedAt(saved.updatedAt)
    setTagInput(normalizeTags(tagInput).join(', '))
    if (andSubmit) {
      const submitResult = await submitContentVersionAction({
        versionId: version.versionId,
        expectedUpdatedAt: saved.updatedAt,
      })
      if (!submitResult.ok) {
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
                onBlur={() => canEdit && setTagInput(normalizeTags(tagInput).join(', '))}
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
            onAssetChange={setCoverAssetId}
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

          {canEdit && role === 'content_editor' && (
            <div className="flex flex-wrap justify-end gap-2 border-t border-border pt-4">
              <Button
                variant="outline"
                disabled={pending !== null}
                onClick={() => void persist(false)}
              >
                {pending === 'save' ? <Loader2 className="animate-spin" /> : <Save />}Salvar
                rascunho
              </Button>
              <Button disabled={pending !== null} onClick={() => void persist(true)}>
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

function normalizeTags(value: string): string[] {
  return [
    ...new Set(
      value
        .split(/[,\n]/)
        .map((tag) =>
          tag
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .trim()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, ''),
        )
        .filter(Boolean),
    ),
  ]
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(
    new Date(value),
  )
}
