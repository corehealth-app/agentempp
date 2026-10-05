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
import { Switch } from '@/components/ui/switch'
import { ChevronDown, ChevronRight, Save } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateAgentConfig } from './actions'
import {
  type AgentToolOptions,
  allowedToolsForSave,
  allToolNames,
  initialAllowAll,
  initialToolSelection,
  missingFlowTools,
  unknownToolNames,
} from './tool-options'

interface Props {
  id: string
  stage: string
  model: string
  temperature: number
  top_p: number | null
  frequency_penalty: number
  presence_penalty: number
  maxTokens: number
  waitSeconds: number
  maxToolIterations: number
  bufferDebounceMs: number
  llmTimeoutMs: number
  visionTimeoutMs: number
  sttTimeoutMs: number
  allowedTools: string[] | null
  heliconeCache: boolean
  streaming: boolean
  modelOptions: string[]
  /** Lista de tools do registro do motor, montada na página (servidor). */
  toolOptions: AgentToolOptions
}

export function AgentConfigForm(props: Props) {
  const [model, setModel] = useState(props.model)
  const [customModel, setCustomModel] = useState('')
  const [temperature, setTemperature] = useState(props.temperature)
  const [topP, setTopP] = useState<number | null>(props.top_p)
  const [freqPenalty, setFreqPenalty] = useState(props.frequency_penalty)
  const [presPenalty, setPresPenalty] = useState(props.presence_penalty)
  const [maxTokens, setMaxTokens] = useState(props.maxTokens)
  const [waitSeconds, setWaitSeconds] = useState(props.waitSeconds)
  const [maxIter, setMaxIter] = useState(props.maxToolIterations)
  const [debounce, setDebounce] = useState(props.bufferDebounceMs)
  const [llmTimeout, setLlmTimeout] = useState(props.llmTimeoutMs)
  const [visionTimeout, setVisionTimeout] = useState(props.visionTimeoutMs)
  const [sttTimeout, setSttTimeout] = useState(props.sttTimeoutMs)
  // "Todas" para o motor é null OU lista vazia: os dois abrem com o botão ligado.
  const [allowAll, setAllowAll] = useState(() => initialAllowAll(props.allowedTools))
  // Estágio salvo como "todas": a lista explícita abre com TODAS marcadas, para
  // que desligar "Permitir todas" nunca tire uma tool do Flow sem a pessoa
  // desmarcar (ver tool-options.ts).
  const [allowedTools, setAllowedTools] = useState<string[]>(() =>
    initialToolSelection(props.toolOptions, props.allowedTools),
  )
  const [heliconeCache, setHeliconeCache] = useState(props.heliconeCache)
  const [streaming, setStreaming] = useState(props.streaming)

  const [openAdvanced, setOpenAdvanced] = useState(false)
  const [openTools, setOpenTools] = useState(false)
  const [pending, startTransition] = useTransition()

  function onSave() {
    startTransition(async () => {
      const result = await updateAgentConfig({
        id: props.id,
        model: customModel || model,
        temperature,
        top_p: topP,
        frequency_penalty: freqPenalty,
        presence_penalty: presPenalty,
        max_tokens: maxTokens,
        wait_seconds: waitSeconds,
        max_tool_iterations: maxIter,
        buffer_debounce_ms: debounce,
        llm_timeout_ms: llmTimeout,
        vision_timeout_ms: visionTimeout,
        stt_timeout_ms: sttTimeout,
        allowed_tools: allowedToolsForSave({ allowAll, selected: allowedTools }),
        helicone_cache: heliconeCache,
        streaming,
      })
      if (result.error) toast.error(result.error)
      else {
        toast.success('Configuração atualizada')
        setCustomModel('')
      }
    })
  }

  const knownModels = [...new Set([...props.modelOptions, props.model])]

  const totalTools = allToolNames(props.toolOptions).length
  const unknownTools = unknownToolNames(props.toolOptions, props.allowedTools)
  const flowMissing = missingFlowTools(props.toolOptions, { allowAll, selected: allowedTools })

  function toggleTool(name: string, checked: boolean) {
    setAllowedTools((current) =>
      checked ? [...new Set([...current, name])] : current.filter((x) => x !== name),
    )
  }

  function toolGroup(title: string, hint: string, names: string[]) {
    if (names.length === 0) return null
    return (
      <div className="space-y-1.5">
        <div className="flex items-baseline gap-2">
          <span className="text-[10px] font-mono uppercase tracking-widest text-foreground">
            {title}
          </span>
          <span className="text-[10px] text-muted-foreground">{hint}</span>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
          {names.map((t) => (
            <label
              key={t}
              className="flex items-center gap-2 p-2 rounded glass-subtle cursor-pointer hover:bg-muted/40"
            >
              <input
                type="checkbox"
                checked={allowedTools.includes(t)}
                onChange={(e) => toggleTool(t, e.target.checked)}
                disabled={pending}
              />
              <code className="text-[11px] font-mono">{t}</code>
            </label>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Modelo + sampling básico */}
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
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

        <FieldNumber
          label={`Temperature (${temperature.toFixed(2)})`}
          help="0 = determinístico, 2 = caótico. Recom: 0.4-0.7"
          value={temperature}
          onChange={(v) => v !== undefined && setTemperature(v)}
          min={0}
          max={2}
          step={0.1}
          disabled={pending}
        />

        <FieldNumber
          label="Max tokens"
          help="Tamanho máx da resposta"
          value={maxTokens}
          onChange={(v) => v !== undefined && setMaxTokens(v)}
          min={256}
          max={32000}
          step={256}
          disabled={pending}
        />
      </div>

      {/* Tools */}
      <div className="border-t border-border pt-4">
        <button
          type="button"
          onClick={() => setOpenTools((v) => !v)}
          className="w-full flex items-center justify-between text-sm font-medium text-foreground hover:text-foreground/80"
        >
          <span className="flex items-center gap-2">
            {openTools ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            Tools permitidas
            <span className="text-[10px] font-mono text-muted-foreground">
              ({allowAll ? 'todas' : `${allowedTools.length}/${totalTools}`})
            </span>
          </span>
        </button>

        {openTools && (
          <div className="mt-3 space-y-3">
            <div className="flex items-center gap-2">
              <Switch checked={allowAll} onCheckedChange={setAllowAll} disabled={pending} />
              <Label className="cursor-pointer">Permitir todas as tools (NULL)</Label>
            </div>

            {!allowAll && (
              <div className="space-y-4">
                {toolGroup(
                  'Flow',
                  'o que o Flow pode usar no app (consultas e sugestões de plano)',
                  props.toolOptions.flow,
                )}
                {toolGroup(
                  'legado (WhatsApp)',
                  'só rodam no canal de WhatsApp, encerrado — sem efeito no Flow',
                  props.toolOptions.legacy,
                )}
                {toolGroup(
                  'fora do registro',
                  'nomes salvos que o motor não conhece mais',
                  unknownTools,
                )}
                {flowMissing.length > 0 && (
                  <p className="text-xs text-amber-700 bg-amber-500/10 rounded px-3 py-2">
                    Com esta lista o Flow fica, neste estágio, sem:{' '}
                    <code className="font-mono">{flowMissing.join(', ')}</code>.
                  </p>
                )}
                {allowedTools.length === 0 && (
                  <p className="text-xs text-muted-foreground">
                    Lista vazia vale como “todas” para o motor.
                  </p>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Avançado */}
      <div className="border-t border-border pt-4">
        <button
          type="button"
          onClick={() => setOpenAdvanced((v) => !v)}
          className="w-full flex items-center justify-between text-sm font-medium text-foreground hover:text-foreground/80"
        >
          <span className="flex items-center gap-2">
            {openAdvanced ? (
              <ChevronDown className="h-4 w-4" />
            ) : (
              <ChevronRight className="h-4 w-4" />
            )}
            Avançado
            <span className="text-[10px] font-mono text-muted-foreground">
              top_p · penalties · timeouts · debounce · iterações · cache
            </span>
          </span>
        </button>

        {openAdvanced && (
          <div className="mt-3 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            <p className="text-[11px] text-muted-foreground md:col-span-2 lg:col-span-3">
              Para o Flow têm efeito o modelo, a temperatura, o máximo de tokens e as tools. O
              número de iterações do Flow tem teto de 2 no código; os demais campos abaixo não são
              lidos pelo Flow.
            </p>
            <FieldNumber
              label={`top_p (${topP ?? 'auto'})`}
              help="Nucleus sampling. Vazio = não envia."
              value={topP}
              onChange={(v) => setTopP(v === undefined ? null : v)}
              min={0}
              max={1}
              step={0.05}
              nullable
              disabled={pending}
            />
            <FieldNumber
              label={`Frequency penalty (${freqPenalty})`}
              help="-2 a 2. Penaliza repetição."
              value={freqPenalty}
              onChange={(v) => v !== undefined && setFreqPenalty(v)}
              min={-2}
              max={2}
              step={0.1}
              disabled={pending}
            />
            <FieldNumber
              label={`Presence penalty (${presPenalty})`}
              help="-2 a 2. Estimula tópicos novos."
              value={presPenalty}
              onChange={(v) => v !== undefined && setPresPenalty(v)}
              min={-2}
              max={2}
              step={0.1}
              disabled={pending}
            />
            <FieldNumber
              label="Wait seconds"
              help="Pensamento antes de responder"
              value={waitSeconds}
              onChange={(v) => v !== undefined && setWaitSeconds(v)}
              min={0}
              max={60}
              disabled={pending}
            />
            <FieldNumber
              label="Max tool iterations"
              help="Loops de tool calling permitidos"
              value={maxIter}
              onChange={(v) => v !== undefined && setMaxIter(v)}
              min={1}
              max={20}
              disabled={pending}
            />
            <FieldNumber
              label="Buffer debounce (ms)"
              help="Janela de empilhamento de msgs"
              value={debounce}
              onChange={(v) => v !== undefined && setDebounce(v)}
              min={500}
              max={60000}
              step={500}
              disabled={pending}
            />
            <FieldNumber
              label="LLM timeout (ms)"
              help="Por chamada individual"
              value={llmTimeout}
              onChange={(v) => v !== undefined && setLlmTimeout(v)}
              min={5000}
              max={300000}
              step={1000}
              disabled={pending}
            />
            <FieldNumber
              label="Vision timeout (ms)"
              value={visionTimeout}
              onChange={(v) => v !== undefined && setVisionTimeout(v)}
              min={5000}
              max={180000}
              step={1000}
              disabled={pending}
            />
            <FieldNumber
              label="STT timeout (ms)"
              value={sttTimeout}
              onChange={(v) => v !== undefined && setSttTimeout(v)}
              min={3000}
              max={120000}
              step={1000}
              disabled={pending}
            />
            <div className="flex items-center gap-3 p-2 glass-subtle md:col-span-1">
              <Switch
                checked={heliconeCache}
                onCheckedChange={setHeliconeCache}
                disabled={pending}
              />
              <div>
                <Label className="cursor-pointer">Helicone cache</Label>
                <p className="text-[10px] text-muted-foreground">
                  Reusa respostas idênticas (economiza)
                </p>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 glass-subtle">
              <Switch checked={streaming} onCheckedChange={setStreaming} disabled={pending} />
              <div>
                <Label className="cursor-pointer">Streaming</Label>
                <p className="text-[10px] text-muted-foreground">Token-a-token (futuro)</p>
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between border-t border-border pt-4">
        <p className="text-[10px] font-mono text-muted-foreground">
          Mudanças geram entrada em audit_log + agent_configs_versions
        </p>
        <Button onClick={onSave} disabled={pending}>
          <Save className="h-4 w-4 mr-1" />
          Salvar
        </Button>
      </div>
    </div>
  )
}

function FieldNumber({
  label,
  help,
  value,
  onChange,
  min,
  max,
  step = 1,
  nullable = false,
  disabled,
}: {
  label: string
  help?: string
  value: number | null
  onChange: (v: number | undefined) => void
  min?: number
  max?: number
  step?: number
  nullable?: boolean
  disabled?: boolean
}) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <Input
        type="number"
        min={min}
        max={max}
        step={step}
        value={value ?? ''}
        placeholder={nullable ? 'auto / vazio' : undefined}
        onChange={(e) => {
          const v = e.target.value
          onChange(v === '' ? undefined : Number(v))
        }}
        disabled={disabled}
      />
      {help && <p className="text-[10px] text-muted-foreground">{help}</p>}
    </div>
  )
}
