'use client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Save, Trash2 } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { useRouter } from 'next/navigation'
import { saveRule, deleteRule } from './actions'

interface Props {
  id: string
  topic: string
  tipo: string
  content: string
  status: string
  displayOrder: number
}

const TIPOS = [
  { value: 'regras_gerais', label: 'Regras Gerais' },
  { value: 'coleta_dados', label: 'Coleta de Dados' },
  { value: 'recomposicao', label: 'Recomposição' },
  { value: 'ganho_massa', label: 'Ganho de Massa' },
  { value: 'manutencao', label: 'Manutenção' },
]

const STATUSES = [
  { value: 'draft', label: 'Rascunho' },
  { value: 'testing', label: 'Em teste' },
  { value: 'active', label: 'Ativo' },
  { value: 'archived', label: 'Arquivado' },
]

export function RuleEditor(props: Props) {
  const router = useRouter()
  const [topic, setTopic] = useState(props.topic)
  const [tipo, setTipo] = useState(props.tipo)
  const [content, setContent] = useState(props.content)
  const [status, setStatus] = useState(props.status)
  const [displayOrder, setDisplayOrder] = useState(props.displayOrder)
  const [reason, setReason] = useState('')
  const [pending, startTransition] = useTransition()

  const dirty =
    topic !== props.topic ||
    tipo !== props.tipo ||
    content !== props.content ||
    status !== props.status ||
    displayOrder !== props.displayOrder

  const tokenEstimate = Math.ceil(content.length / 4)

  function onSave() {
    startTransition(async () => {
      const result = await saveRule({
        id: props.id,
        topic,
        tipo,
        content,
        status,
        display_order: displayOrder,
        change_reason: reason || null,
      })
      if (result.error) toast.error(result.error)
      else {
        toast.success('Regra atualizada')
        setReason('')
        router.refresh()
      }
    })
  }

  function onDelete() {
    if (!confirm(`Apagar regra "${props.topic}"? Versões antigas permanecem em histórico.`)) return
    startTransition(async () => {
      const result = await deleteRule(props.id)
      if (result.error) toast.error(result.error)
      else {
        toast.success('Apagado')
        router.push('/prompts')
      }
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Editor</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-1.5 md:col-span-2">
            <Label>Tópico</Label>
            <Input value={topic} onChange={(e) => setTopic(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Tipo</Label>
            <Select value={tipo} onValueChange={setTipo}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TIPOS.map((t) => (
                  <SelectItem key={t.value} value={t.value}>
                    {t.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {STATUSES.map((s) => (
                  <SelectItem key={s.value} value={s.value}>
                    {s.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Ordem de exibição</Label>
            <Input
              type="number"
              value={displayOrder}
              onChange={(e) => setDisplayOrder(Number.parseInt(e.target.value, 10) || 0)}
            />
          </div>
        </div>

        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label>Conteúdo (markdown)</Label>
            <span className="text-xs text-muted-foreground">
              {content.length} chars · ~{tokenEstimate} tokens
            </span>
          </div>
          <Textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={20}
            className="font-mono text-sm"
          />
        </div>

        <div className="space-y-1.5">
          <Label>Motivo da mudança (opcional, vai pro audit log)</Label>
          <Input
            placeholder="ex: ajuste de tom após feedback do Dr. Roberto"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
        </div>

        <div className="flex justify-between pt-2 border-t">
          <Button variant="outline" onClick={onDelete} disabled={pending}>
            <Trash2 className="h-4 w-4 mr-1" />
            Apagar
          </Button>
          <Button onClick={onSave} disabled={!dirty || pending}>
            <Save className="h-4 w-4 mr-1" />
            Salvar nova versão
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
