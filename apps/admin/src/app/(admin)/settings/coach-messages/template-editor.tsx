'use client'

import { Eye, History, LoaderCircle, Save, Sparkles } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import type {
  CoachCatalogEntry,
  CoachTemplateVersionSummary,
} from '@/lib/coach-messages/admin-service'
import {
  listCoachTemplateVersionsAction,
  previewCoachDraftAction,
  requestCoachAssistedRewriteAction,
  reviseCoachDraftAction,
} from './actions'
import { describePreviewState, type PreviewState } from './catalog-presenter'

type RenderedPreview = { title: string | null; subject: string | null; body: string }

export function TemplateEditor({
  entry,
  canEdit,
  canAssist,
  onCloseAction,
}: {
  entry: CoachCatalogEntry
  canEdit: boolean
  canAssist: boolean
  onCloseAction: () => void
}) {
  const router = useRouter()
  const [activeTab, setActiveTab] = useState('edit')
  const [title, setTitle] = useState(entry.title ?? '')
  const [subject, setSubject] = useState(entry.subject ?? '')
  const [body, setBody] = useState(entry.body)
  const [error, setError] = useState<string | null>(null)
  const [previewState, setPreviewState] = useState<PreviewState>('idle')
  const [preview, setPreview] = useState<RenderedPreview | null>(null)
  const [versions, setVersions] = useState<CoachTemplateVersionSummary[] | null>(null)
  const [selectedVersionId, setSelectedVersionId] = useState<string>('')
  const [savePending, startSave] = useTransition()
  const [previewPending, startPreview] = useTransition()
  const [historyPending, startHistory] = useTransition()
  const [assistPending, startAssist] = useTransition()

  const currentCopy = {
    title: entry.channel === 'push' ? title.trim() || null : null,
    subject: entry.channel === 'email' ? subject.trim() || null : null,
    body: body.trim(),
  }
  const selectedVersion = versions?.find((version) => version.id === selectedVersionId) ?? null
  const previewDescription = describePreviewState(previewState)

  function loadHistory() {
    if (versions !== null || historyPending) return
    startHistory(async () => {
      const result = await listCoachTemplateVersionsAction({ templateId: entry.templateId })
      if (!result.ok) {
        setError(result.error)
        return
      }
      const loaded = result.data as CoachTemplateVersionSummary[]
      setVersions(loaded)
      setSelectedVersionId(
        loaded.find((version) => version.id !== entry.templateVersionId)?.id ?? '',
      )
    })
  }

  function changeTab(value: string) {
    setActiveTab(value)
    setError(null)
    if (value === 'versions') loadHistory()
  }

  function generatePreview() {
    setError(null)
    setPreviewState('loading')
    startPreview(async () => {
      const result = await previewCoachDraftAction({
        packId: entry.packId,
        templateId: entry.templateId,
        expectedTemplateVersionId: entry.templateVersionId,
        ...currentCopy,
      })
      if (!result.ok) {
        setPreviewState('error')
        setError(result.error)
        return
      }
      setPreview(result.data as RenderedPreview)
      setPreviewState('ready')
      setActiveTab('preview')
    })
  }

  function saveRevision() {
    if (!currentCopy.body) {
      setError('O corpo da mensagem é obrigatório')
      return
    }
    setError(null)
    startSave(async () => {
      const result = await reviseCoachDraftAction({
        packId: entry.packId,
        templateId: entry.templateId,
        expectedTemplateVersionId: entry.templateVersionId,
        ...currentCopy,
      })
      if (!result.ok) {
        setError(result.error)
        return
      }
      router.refresh()
      onCloseAction()
    })
  }

  function requestAssistedRewrite() {
    setError(null)
    startAssist(async () => {
      const result = await requestCoachAssistedRewriteAction({
        packId: entry.packId,
        personality: entry.personality,
        context: entry.context,
        locale: entry.locale,
      })
      if (!result.ok) {
        setError(result.error)
        return
      }
      router.refresh()
      onCloseAction()
    })
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onCloseAction()}>
      <DialogContent className="max-h-[92vh] max-w-4xl overflow-y-auto">
        <DialogHeader>
          <div className="flex flex-wrap items-center gap-2 pr-8">
            <DialogTitle>Variante {entry.variant}</DialogTitle>
            <Badge variant="outline">{entry.channel}</Badge>
            <Badge variant="secondary">{entry.locale}</Badge>
          </div>
          <DialogDescription className="font-mono text-xs">
            {entry.personality} / {entry.context} / v{entry.version}
          </DialogDescription>
        </DialogHeader>

        <Tabs value={activeTab} onValueChange={changeTab}>
          <TabsList className="grid w-full grid-cols-3 sm:w-auto">
            <TabsTrigger value="edit">Conteúdo</TabsTrigger>
            <TabsTrigger value="preview">Prévia</TabsTrigger>
            <TabsTrigger value="versions">Versões</TabsTrigger>
          </TabsList>

          <TabsContent value="edit" className="space-y-4 pt-2">
            <div className="flex flex-wrap items-center gap-1.5">
              {entry.allowedVariables.map((variable) => (
                <Badge key={variable} variant="outline" className="font-mono text-[10px]">
                  {'{{'}
                  {variable}
                  {'}}'}
                </Badge>
              ))}
            </div>

            {entry.channel === 'push' && (
              <div>
                <Label htmlFor="coach-template-title">Título do push</Label>
                <Input
                  id="coach-template-title"
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                  maxLength={60}
                  disabled={!canEdit}
                  className="mt-1"
                />
                <p className="mt-1 text-right font-mono text-[10px] text-muted-foreground">
                  {title.length}/60
                </p>
              </div>
            )}

            {entry.channel === 'email' && (
              <div>
                <Label htmlFor="coach-template-subject">Assunto do email</Label>
                <Input
                  id="coach-template-subject"
                  value={subject}
                  onChange={(event) => setSubject(event.target.value)}
                  maxLength={120}
                  disabled={!canEdit}
                  className="mt-1"
                />
                <p className="mt-1 text-right font-mono text-[10px] text-muted-foreground">
                  {subject.length}/120
                </p>
              </div>
            )}

            <div>
              <Label htmlFor="coach-template-body">Corpo</Label>
              <Textarea
                id="coach-template-body"
                value={body}
                onChange={(event) => setBody(event.target.value)}
                maxLength={4000}
                disabled={!canEdit}
                className="mt-1 min-h-40 resize-y leading-relaxed"
              />
              <p className="mt-1 text-right font-mono text-[10px] text-muted-foreground">
                {body.length}/4000
              </p>
            </div>
          </TabsContent>

          <TabsContent value="preview" className="pt-2">
            <div className="flex items-center justify-between border-b border-border pb-3">
              <div className="flex items-center gap-2">
                <Eye className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-medium">Valores sintéticos</span>
              </div>
              <Badge variant="outline">{previewDescription.label}</Badge>
            </div>
            {preview ? (
              <PreviewCopy copy={preview} />
            ) : (
              <div className="flex min-h-48 items-center justify-center text-sm text-muted-foreground">
                {previewPending ? 'Gerando prévia' : 'Nenhuma prévia gerada'}
              </div>
            )}
          </TabsContent>

          <TabsContent value="versions" className="pt-2">
            <div className="flex flex-col gap-3 border-b border-border pb-3 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <p className="text-sm font-medium">Comparação de versões</p>
                <p className="text-xs text-muted-foreground">Versão atual e revisão selecionada</p>
              </div>
              {versions && versions.length > 0 && (
                <Select value={selectedVersionId} onValueChange={setSelectedVersionId}>
                  <SelectTrigger className="w-full font-mono sm:w-52">
                    <SelectValue placeholder="Escolha uma versão" />
                  </SelectTrigger>
                  <SelectContent>
                    {versions.map((version) => (
                      <SelectItem key={version.id} value={version.id}>
                        v{version.version} · {version.provenance}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            {historyPending ? (
              <div className="flex min-h-48 items-center justify-center text-muted-foreground">
                <LoaderCircle className="h-5 w-5 animate-spin" />
              </div>
            ) : selectedVersion ? (
              <div className="grid divide-y divide-border lg:grid-cols-2 lg:divide-x lg:divide-y-0">
                <VersionCopy label={`Atual · v${entry.version}`} copy={entry} />
                <VersionCopy
                  label={`Comparada · v${selectedVersion.version}`}
                  copy={selectedVersion}
                />
              </div>
            ) : (
              <div className="flex min-h-48 items-center justify-center text-sm text-muted-foreground">
                Nenhuma versão anterior disponível
              </div>
            )}
          </TabsContent>
        </Tabs>

        {error && (
          <div
            className="border-l-2 border-destructive bg-destructive/5 px-3 py-2 text-sm text-destructive"
            aria-live="polite"
          >
            {error}
          </div>
        )}

        <DialogFooter className="gap-2 sm:justify-between">
          <Button
            variant="outline"
            disabled={!canAssist || assistPending || savePending}
            onClick={requestAssistedRewrite}
            className="active:scale-[0.98]"
          >
            {assistPending ? <LoaderCircle className="animate-spin" /> : <Sparkles />}
            Sugerir grupo
          </Button>
          <div className="flex flex-col-reverse gap-2 sm:flex-row">
            <Button variant="ghost" onClick={onCloseAction}>
              Fechar
            </Button>
            <Button
              variant="outline"
              disabled={previewPending || savePending}
              onClick={generatePreview}
              className="active:scale-[0.98]"
            >
              {previewPending ? <LoaderCircle className="animate-spin" /> : <Eye />}
              Gerar prévia
            </Button>
            <Button
              disabled={!canEdit || savePending || previewPending || !body.trim()}
              onClick={saveRevision}
              className="active:scale-[0.98]"
            >
              {savePending ? <LoaderCircle className="animate-spin" /> : <Save />}
              Salvar revisão
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function PreviewCopy({ copy }: { copy: RenderedPreview }) {
  return (
    <div className="space-y-3 py-4">
      {copy.title && <p className="font-display text-base font-medium">{copy.title}</p>}
      {copy.subject && <p className="text-sm font-medium">{copy.subject}</p>}
      <p className="whitespace-pre-wrap text-sm leading-relaxed text-foreground">{copy.body}</p>
    </div>
  )
}

function VersionCopy({
  label,
  copy,
}: {
  label: string
  copy: Pick<CoachTemplateVersionSummary, 'title' | 'subject' | 'body'>
}) {
  return (
    <div className="min-w-0 p-4">
      <p className="mb-3 flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
        <History className="h-3.5 w-3.5" />
        {label}
      </p>
      {copy.title && <p className="mb-2 text-sm font-medium">{copy.title}</p>}
      {copy.subject && <p className="mb-2 text-sm font-medium">{copy.subject}</p>}
      <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{copy.body}</p>
    </div>
  )
}
