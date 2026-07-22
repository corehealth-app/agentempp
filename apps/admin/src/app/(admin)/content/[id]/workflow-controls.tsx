'use client'

import { Archive, CalendarClock, Check, Loader2, Send, X } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import type { AdminRole } from '@/lib/admin-rbac'
import type { ContentPublicationDetail } from '@/lib/content/admin-service'
import {
  archiveContentPublicationAction,
  publishContentVersionAction,
  reviewContentVersionAction,
} from '../actions'
import {
  canPublishContentVersion,
  canReviewContentVersion,
  contentWorkflowTargetLabel,
  parseUtcDateTimeLocal,
} from '../presenter'

type Version = ContentPublicationDetail['versions'][number]

export function WorkflowControls({
  role,
  publicationId,
  archivedAt,
  version,
}: {
  role: AdminRole
  publicationId: string
  archivedAt: string | null
  version: Version | null
}) {
  const router = useRouter()
  const [pending, setPending] = useState<string | null>(null)
  const [message, setMessage] = useState<{ tone: 'error' | 'success'; text: string } | null>(null)
  const [reason, setReason] = useState('')
  const [scheduleAt, setScheduleAt] = useState('')

  async function review(decision: 'approve' | 'reject') {
    if (!version) return
    const rejectionReason = decision === 'reject' ? reason.trim() : null
    if (decision === 'reject' && (rejectionReason === null || rejectionReason.length < 10)) {
      setMessage({ tone: 'error', text: 'Informe um motivo com pelo menos 10 caracteres.' })
      return
    }
    setPending(decision)
    setMessage(null)
    const result = await reviewContentVersionAction({
      versionId: version.versionId,
      decision,
      rejectionReason,
    })
    setPending(null)
    if (!result.ok) {
      setMessage({ tone: 'error', text: result.error })
      return
    }
    setMessage({
      tone: 'success',
      text: decision === 'approve' ? 'Versao aprovada.' : 'Versao rejeitada.',
    })
    router.refresh()
  }

  async function publish(publishAt: string | null) {
    if (!version) return
    setPending('publish')
    setMessage(null)
    const result = await publishContentVersionAction({ versionId: version.versionId, publishAt })
    setPending(null)
    if (!result.ok) {
      setMessage({ tone: 'error', text: result.error })
      return
    }
    setMessage({
      tone: 'success',
      text: publishAt ? 'Publicacao agendada.' : 'Publicacao liberada.',
    })
    router.refresh()
  }

  async function schedule() {
    const timestamp = parseUtcDateTimeLocal(scheduleAt)
    if (!timestamp) {
      setMessage({ tone: 'error', text: 'Informe uma data e hora validas.' })
      return
    }
    await publish(timestamp)
  }

  async function archivePublication() {
    setPending('archive')
    setMessage(null)
    const result = await archiveContentPublicationAction({ publicationId })
    setPending(null)
    if (!result.ok) {
      setMessage({ tone: 'error', text: result.error })
      return
    }
    setMessage({ tone: 'success', text: 'Publicacao arquivada.' })
    router.refresh()
  }

  const canReview = version ? canReviewContentVersion(role, version.state, archivedAt) : false
  const canPublish = version
    ? canPublishContentVersion(role, version.state, version.publishAt, archivedAt)
    : false
  const canArchive = role === 'master_admin' && !archivedAt
  const targetLabel = version ? contentWorkflowTargetLabel(version) : null
  if (!canReview && !canPublish && !canArchive && !message) return null

  return (
    <section className="border-y border-border py-3" aria-label="Fluxo editorial">
      {targetLabel && (canReview || canPublish) && (
        <p className="mb-2 break-words font-mono text-[10px] text-muted-foreground">
          Alvo do workflow: {targetLabel}
        </p>
      )}
      <div className="flex flex-wrap items-center gap-2">
        {canReview && (
          <>
            <Button size="sm" disabled={pending !== null} onClick={() => void review('approve')}>
              {pending === 'approve' ? <Loader2 className="animate-spin" /> : <Check />}
              Aprovar
            </Button>
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm" variant="destructive" disabled={pending !== null}>
                  <X />
                  Rejeitar
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-md rounded-lg">
                <DialogHeader>
                  <DialogTitle>Rejeitar versao</DialogTitle>
                  <DialogDescription>
                    {targetLabel}. O motivo ficara registrado no fluxo editorial.
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-2">
                  <Label htmlFor="rejection-reason">Motivo</Label>
                  <Textarea
                    id="rejection-reason"
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                    minLength={10}
                    maxLength={1000}
                    className="min-h-28"
                  />
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancelar</Button>
                  </DialogClose>
                  <Button
                    variant="destructive"
                    disabled={pending !== null || reason.trim().length < 10}
                    onClick={() => void review('reject')}
                  >
                    Confirmar rejeicao
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </>
        )}

        {canPublish && (
          <>
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm" disabled={pending !== null}>
                  <Send />
                  Publicar agora
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-md rounded-lg">
                <DialogHeader>
                  <DialogTitle>Publicar agora</DialogTitle>
                  <DialogDescription>
                    {targetLabel}. Esta versao ficara disponivel imediatamente.
                  </DialogDescription>
                </DialogHeader>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancelar</Button>
                  </DialogClose>
                  <Button disabled={pending !== null} onClick={() => void publish(null)}>
                    Confirmar publicacao
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm" variant="outline" disabled={pending !== null}>
                  <CalendarClock />
                  Agendar
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-md rounded-lg">
                <DialogHeader>
                  <DialogTitle>Agendar publicacao</DialogTitle>
                  <DialogDescription>
                    {targetLabel}. Confirme a data e a hora de liberacao no fuso operacional UTC.
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-2">
                  <Label htmlFor="publish-at">Data e hora (UTC)</Label>
                  <Input
                    id="publish-at"
                    type="datetime-local"
                    value={scheduleAt}
                    onChange={(event) => setScheduleAt(event.target.value)}
                  />
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancelar</Button>
                  </DialogClose>
                  <Button
                    disabled={pending !== null || !scheduleAt}
                    onClick={() => void schedule()}
                  >
                    Confirmar agendamento
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </>
        )}

        {canArchive && (
          <Dialog>
            <DialogTrigger asChild>
              <Button size="sm" variant="destructive" disabled={pending !== null}>
                <Archive />
                Arquivar
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-md rounded-lg">
              <DialogHeader>
                <DialogTitle>Arquivar publicacao</DialogTitle>
                <DialogDescription>
                  Todas as versoes desta publicacao deixarao o fluxo ativo.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancelar</Button>
                </DialogClose>
                <Button
                  variant="destructive"
                  disabled={pending !== null}
                  onClick={() => void archivePublication()}
                >
                  Confirmar arquivamento
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        )}
      </div>
      <div className="mt-2 min-h-5" aria-live="polite">
        {message && (
          <p
            className={`text-xs ${message.tone === 'error' ? 'text-destructive' : 'text-emerald-700 dark:text-emerald-400'}`}
          >
            {message.text}
          </p>
        )}
      </div>
    </section>
  )
}
