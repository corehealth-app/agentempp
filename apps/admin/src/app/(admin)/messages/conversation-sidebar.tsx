'use client'

import {
  CheckCircle2,
  Edit2,
  Flame,
  Pause,
  Play,
  Tag,
  Trophy,
  X,
} from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { CountryBadge } from '@/components/country-badge'
import {
  pauseUserAction,
  resumeUserAction,
  tagUserAction,
  untagUserAction,
  updateNotesAction,
  updateUserNameAction,
} from './actions'

interface User {
  id: string
  name: string | null
  wpp: string
  tags?: string[] | null
  admin_notes?: string | null
  metadata?: Record<string, unknown> | null
  country?: string | null
  country_confirmed?: boolean | null
}

interface Progress {
  xp_total: number
  level: number
  current_streak: number
  blocks_completed: number
}

interface Profile {
  sex: string | null
  weight_kg: number | null
  height_cm: number | null
  onboarding_completed: boolean
  current_protocol: string | null
}

const SUGGESTED_TAGS = [
  'caso-bom',
  'alucinou',
  'precisa-rule',
  'vip',
  'desistente',
  'engajado',
  'lento',
  'tecnico',
]

export function ConversationSidebar({
  user,
  progress,
  profile,
  totalCost,
  totalMessages,
}: {
  user: User
  progress: Progress | null
  profile: Profile | null
  totalCost: number
  totalMessages: number
}) {
  const [pending, startTransition] = useTransition()
  const [editingName, setEditingName] = useState(false)
  const [name, setName] = useState(user.name ?? '')
  const [notes, setNotes] = useState(user.admin_notes ?? '')
  const [editingNotes, setEditingNotes] = useState(false)
  const [newTag, setNewTag] = useState('')
  const [showTagInput, setShowTagInput] = useState(false)

  const isPaused =
    !!user.metadata?.paused_until &&
    new Date(user.metadata.paused_until as string) > new Date()

  function togglePause() {
    startTransition(async () => {
      if (isPaused) {
        const r = await resumeUserAction(user.id)
        if (r.error) toast.error(r.error)
        else toast.success('Agente retomado')
      } else {
        const days = Number(prompt('Pausar por quantos dias?', '7'))
        if (!days || days < 1 || days > 60) return
        const r = await pauseUserAction(user.id, days)
        if (r.error) toast.error(r.error)
        else toast.success(`Pausado por ${days} dia(s)`)
      }
    })
  }

  function saveName() {
    startTransition(async () => {
      const r = await updateUserNameAction(user.id, name)
      if (r.error) toast.error(r.error)
      else {
        toast.success('Nome atualizado')
        setEditingName(false)
      }
    })
  }

  function saveNotes() {
    startTransition(async () => {
      const r = await updateNotesAction(user.id, notes)
      if (r.error) toast.error(r.error)
      else {
        toast.success('Notas salvas')
        setEditingNotes(false)
      }
    })
  }

  function addTag(t: string) {
    startTransition(async () => {
      const r = await tagUserAction(user.id, t)
      if (r.error) toast.error(r.error)
      else {
        setNewTag('')
        setShowTagInput(false)
      }
    })
  }

  function removeTag(t: string) {
    startTransition(async () => {
      const r = await untagUserAction(user.id, t)
      if (r.error) toast.error(r.error)
    })
  }

  return (
    <div className="space-y-3 overflow-y-auto pr-1 -mr-1">
      {/* Identidade + ações */}
      <div className="content-card p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Paciente
          </div>
          <Button
            size="sm"
            variant={isPaused ? 'default' : 'outline'}
            onClick={togglePause}
            disabled={pending}
            className="h-7 text-xs"
          >
            {isPaused ? (
              <>
                <Play className="h-3 w-3 mr-1" />
                Retomar
              </>
            ) : (
              <>
                <Pause className="h-3 w-3 mr-1" />
                Pausar agente
              </>
            )}
          </Button>
        </div>

        {editingName ? (
          <div className="flex gap-1">
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="h-8 text-sm"
              autoFocus
            />
            <Button size="sm" onClick={saveName} disabled={pending}>
              <CheckCircle2 className="h-3 w-3" />
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setEditingName(false)
                setName(user.name ?? '')
              }}
            >
              <X className="h-3 w-3" />
            </Button>
          </div>
        ) : (
          <div className="flex items-center gap-2 group">
            <span className="font-medium text-foreground">
              {user.name ?? <span className="italic text-muted-foreground">sem nome</span>}
            </span>
            <button
              type="button"
              onClick={() => setEditingName(true)}
              className="opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-foreground transition-opacity"
            >
              <Edit2 className="h-3 w-3" />
            </button>
          </div>
        )}
        <div className="text-[11px] font-mono text-muted-foreground inline-flex items-center gap-2">
          +{user.wpp}
          <CountryBadge
            country={user.country ?? null}
            confirmed={!!user.country_confirmed}
            size="sm"
          />
        </div>
        {isPaused && user.metadata?.paused_until ? (
          <div className="text-[10px] font-mono text-amber-700 bg-amber-500/10 px-2 py-1 rounded">
            💤 pausado até{' '}
            {new Date(user.metadata.paused_until as string).toLocaleDateString('pt-BR')}
          </div>
        ) : null}
      </div>

      {/* Tags */}
      <div className="content-card p-4 space-y-2">
        <div className="flex items-center justify-between">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground inline-flex items-center gap-1.5">
            <Tag className="h-3 w-3" />
            Tags
          </div>
          <button
            type="button"
            onClick={() => setShowTagInput(!showTagInput)}
            className="text-[10px] font-mono text-moss-700 hover:text-moss-900"
          >
            + adicionar
          </button>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {(user.tags ?? []).length === 0 && !showTagInput && (
            <span className="text-[11px] text-muted-foreground italic">sem tags</span>
          )}
          {(user.tags ?? []).map((t) => (
            <span
              key={t}
              className="inline-flex items-center gap-1 text-[10px] uppercase tracking-widest font-mono px-2 py-0.5 rounded-full bg-bronze/10 text-bronze"
            >
              {t}
              <button
                type="button"
                onClick={() => removeTag(t)}
                disabled={pending}
                className="hover:text-rose-500"
              >
                <X className="h-2.5 w-2.5" />
              </button>
            </span>
          ))}
        </div>
        {showTagInput && (
          <div className="space-y-2">
            <div className="flex gap-1">
              <Input
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                placeholder="nova-tag"
                className="h-7 text-xs font-mono"
                onKeyDown={(e) => e.key === 'Enter' && newTag && addTag(newTag)}
              />
              <Button
                size="sm"
                onClick={() => addTag(newTag)}
                disabled={pending || !newTag}
                className="h-7"
              >
                ↵
              </Button>
            </div>
            <div className="flex flex-wrap gap-1">
              {SUGGESTED_TAGS.filter((t) => !(user.tags ?? []).includes(t))
                .slice(0, 6)
                .map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => addTag(t)}
                    disabled={pending}
                    className="text-[10px] font-mono px-1.5 py-0.5 rounded border border-border hover:bg-muted text-muted-foreground"
                  >
                    +{t}
                  </button>
                ))}
            </div>
          </div>
        )}
      </div>

      {/* Notas */}
      <div className="content-card p-4 space-y-2">
        <div className="flex items-center justify-between">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Notas (admin)
          </div>
          {!editingNotes && (
            <button
              type="button"
              onClick={() => setEditingNotes(true)}
              className="text-[10px] font-mono text-moss-700 hover:text-moss-900"
            >
              editar
            </button>
          )}
        </div>
        {editingNotes ? (
          <div className="space-y-2">
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Anotações sobre este paciente..."
              rows={4}
              className="w-full text-xs p-2 rounded border border-border bg-background resize-none"
            />
            <div className="flex gap-1">
              <Button size="sm" onClick={saveNotes} disabled={pending} className="flex-1 h-7">
                Salvar
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  setEditingNotes(false)
                  setNotes(user.admin_notes ?? '')
                }}
                className="h-7"
              >
                Cancelar
              </Button>
            </div>
          </div>
        ) : user.admin_notes ? (
          <p className="text-xs text-foreground/80 whitespace-pre-wrap">{user.admin_notes}</p>
        ) : (
          <p className="text-xs text-muted-foreground italic">sem notas</p>
        )}
      </div>

      {/* Métricas do paciente */}
      <div className="content-card p-4 space-y-2">
        <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
          Métricas
        </div>
        <div className="space-y-1.5 text-xs">
          <Row label="Mensagens">{totalMessages}</Row>
          <Row label="Custo total">${totalCost.toFixed(4)}</Row>
          <Row label="Custo médio/msg">
            ${totalMessages > 0 ? (totalCost / totalMessages).toFixed(5) : '0.00000'}
          </Row>
        </div>
      </div>

      {/* Progresso */}
      {progress && (
        <div className="content-card p-4 space-y-2">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground inline-flex items-center gap-1.5">
            <Trophy className="h-3 w-3" />
            Progresso
          </div>
          <div className="space-y-1.5 text-xs">
            <Row label="Nível">{progress.level}</Row>
            <Row label="XP">{progress.xp_total}</Row>
            <Row label="Streak">
              <span className="inline-flex items-center gap-1">
                <Flame className="h-3 w-3 text-orange-500" />
                {progress.current_streak} dias
              </span>
            </Row>
            <Row label="Blocos">{progress.blocks_completed}</Row>
          </div>
        </div>
      )}

      {/* Perfil */}
      {profile && profile.onboarding_completed && (
        <div className="content-card p-4 space-y-2">
          <div className="text-[10px] font-mono uppercase tracking-widest text-muted-foreground">
            Perfil clínico
          </div>
          <div className="space-y-1.5 text-xs">
            <Row label="Sexo">{profile.sex ?? '?'}</Row>
            <Row label="Peso">{profile.weight_kg ? `${profile.weight_kg} kg` : '?'}</Row>
            <Row label="Altura">{profile.height_cm ? `${profile.height_cm} cm` : '?'}</Row>
            <Row label="Protocolo">{profile.current_protocol ?? '?'}</Row>
          </div>
          <a
            href={`/users/${user.id}`}
            className="block mt-2 text-[10px] text-moss-700 hover:underline"
          >
            ver perfil completo →
          </a>
        </div>
      )}
    </div>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-mono tabular-nums text-foreground">{children}</span>
    </div>
  )
}
