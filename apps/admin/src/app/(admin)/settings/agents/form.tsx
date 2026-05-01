'use client'
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
import { Save } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateAgentConfig } from './actions'

interface Props {
  id: string
  stage: string
  model: string
  temperature: number
  maxTokens: number
  waitSeconds: number
  modelOptions: string[]
}

export function AgentConfigForm(props: Props) {
  const [model, setModel] = useState(props.model)
  const [customModel, setCustomModel] = useState('')
  const [temperature, setTemperature] = useState(props.temperature)
  const [maxTokens, setMaxTokens] = useState(props.maxTokens)
  const [waitSeconds, setWaitSeconds] = useState(props.waitSeconds)
  const [pending, startTransition] = useTransition()

  const dirty =
    model !== props.model ||
    temperature !== props.temperature ||
    maxTokens !== props.maxTokens ||
    waitSeconds !== props.waitSeconds ||
    !!customModel

  function onSave() {
    startTransition(async () => {
      const result = await updateAgentConfig({
        id: props.id,
        model: customModel || model,
        temperature,
        max_tokens: maxTokens,
        wait_seconds: waitSeconds,
      })
      if (result.error) toast.error(result.error)
      else {
        toast.success('Configuração atualizada')
        setCustomModel('')
      }
    })
  }

  const knownModels = [...new Set([...props.modelOptions, props.model])]

  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
      <div className="space-y-1.5 lg:col-span-2">
        <Label>Modelo</Label>
        <Select value={model} onValueChange={setModel} disabled={pending}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {knownModels.map((m) => (
              <SelectItem key={m} value={m}>
                {m}
              </SelectItem>
            ))}
            <SelectItem value="__custom__">… outro (digite abaixo)</SelectItem>
          </SelectContent>
        </Select>
        {model === '__custom__' && (
          <Input
            placeholder="ex: provider/model-id"
            value={customModel}
            onChange={(e) => setCustomModel(e.target.value)}
            className="mt-1"
          />
        )}
      </div>

      <div className="space-y-1.5">
        <Label>Temperature ({temperature.toFixed(2)})</Label>
        <Input
          type="number"
          step="0.1"
          min="0"
          max="2"
          value={temperature}
          onChange={(e) => setTemperature(Number.parseFloat(e.target.value))}
          disabled={pending}
        />
      </div>

      <div className="space-y-1.5">
        <Label>Max tokens</Label>
        <Input
          type="number"
          min="256"
          max="32000"
          step="256"
          value={maxTokens}
          onChange={(e) => setMaxTokens(Number.parseInt(e.target.value, 10))}
          disabled={pending}
        />
      </div>

      <div className="space-y-1.5">
        <Label>Wait seconds (buffer)</Label>
        <Input
          type="number"
          min="0"
          max="60"
          value={waitSeconds}
          onChange={(e) => setWaitSeconds(Number.parseInt(e.target.value, 10))}
          disabled={pending}
        />
      </div>

      <div className="lg:col-span-3 flex items-end">
        <Button onClick={onSave} disabled={!dirty || pending}>
          <Save className="h-4 w-4 mr-1" />
          Salvar
        </Button>
      </div>
    </div>
  )
}
