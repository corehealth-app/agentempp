/**
 * OpenRouter LLM client.
 *
 * Wrapper sobre o SDK `openai` apontando para o endpoint do OpenRouter,
 * preparado para passar por proxy Helicone quando habilitado.
 */
import OpenAI from 'openai'
import type { ChatCompletionMessageParam, ChatCompletionTool } from 'openai/resources/chat/completions'

export interface LLMConfig {
  apiKey: string
  /** Base URL — padrão openrouter.ai. Se HELICONE_API_KEY presente, usa proxy. */
  baseURL?: string
  /** Habilita proxy Helicone (ainda não usado neste momento). */
  heliconeApiKey?: string
  /** Identificador do app reportado ao OpenRouter para analytics. */
  referrer?: string
  appName?: string
}

/** Bloco de system prompt — string simples ou array (pra cache control).
 *
 * Anthropic prompt caching via OpenRouter (2026-05-16): marcar bloco com
 * `cache: 'ephemeral'` salva 90% no custo das leituras subsequentes dentro
 * de 5min. Usado pra parte ESTÁVEL do prompt (regras + persona) que não
 * muda entre turnos do mesmo paciente. Parte VARIÁVEL (contexto do paciente)
 * vai num bloco separado sem cache.
 *
 * Funciona só pra modelos Anthropic (Opus/Sonnet/Haiku 4.x). Em outros
 * providers, OpenRouter ignora o campo. */
export type SystemPromptBlock = string | Array<{ text: string; cache?: 'ephemeral' }>

export interface LLMCallParams {
  model: string
  systemPrompt: SystemPromptBlock
  messages: ChatCompletionMessageParam[]
  temperature?: number
  maxTokens?: number
  tools?: ChatCompletionTool[]
  /** Se true, marca o último tool schema com cache_control — Anthropic cacheia
   * todos os tools anteriores junto. Funciona com tools array estável. */
  cacheTools?: boolean
  /** Forçar uso de tool específica, ou 'auto' (padrão). */
  toolChoice?: 'auto' | 'none' | { type: 'function'; function: { name: string } }
  /** JSON mode (structured output). Se Zod schema futuramente, usar response_format. */
  responseFormat?: { type: 'json_object' }
  /** Metadata para tracking (Helicone properties). */
  metadata?: Record<string, string>
  /** User identifier (Helicone-User-Id). */
  userId?: string
}

/** Detecta se o modelo suporta prompt caching nativo (Anthropic). */
export function modelSupportsPromptCaching(model: string): boolean {
  return /^anthropic\//.test(model)
}

export interface LLMResult {
  content: string | null
  toolCalls: Array<{ id: string; name: string; arguments: string }>
  promptTokens: number
  completionTokens: number
  totalTokens: number
  /** Anthropic prompt caching: tokens GRAVADOS no cache (paga 25% extra na 1ª) */
  cacheCreationInputTokens?: number
  /** Anthropic prompt caching: tokens LIDOS do cache (paga 10% do preço normal) */
  cacheReadInputTokens?: number
  costUsd: number | null
  model: string
  finishReason: string
  latencyMs: number
}

export class OpenRouterLLM {
  private client: OpenAI

  constructor(private cfg: LLMConfig) {
    const baseURL = cfg.baseURL ?? 'https://openrouter.ai/api/v1'
    const headers: Record<string, string> = {
      'HTTP-Referer': cfg.referrer ?? 'https://github.com/corehealth-app/agentempp',
      'X-Title': cfg.appName ?? 'Agente MPP',
    }
    if (cfg.heliconeApiKey) {
      headers['Helicone-Auth'] = `Bearer ${cfg.heliconeApiKey}`
      headers['Helicone-Cache-Enabled'] = 'true'
    }

    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL,
      defaultHeaders: headers,
      // Timeout 90s pra cada LLM call (default OpenAI SDK é 10min, ridículo
      // pra agente síncrono). Pipeline pode fazer 2-3 iterações; 90s × 3 = 270s
      // ainda dentro do maxDuration=300s do Vercel.
      timeout: 90_000,
      maxRetries: 1,
    })
  }

  async complete(p: LLMCallParams): Promise<LLMResult> {
    const start = Date.now()

    const headers: Record<string, string> = {}
    if (p.userId) headers['Helicone-User-Id'] = p.userId
    if (p.metadata) {
      for (const [k, v] of Object.entries(p.metadata)) {
        headers[`Helicone-Property-${k}`] = String(v)
      }
    }

    // System content — string simples ou array de blocos com cache_control.
    // Quando array, cada bloco vira `{type:'text', text, cache_control?}` no
    // formato Anthropic via OpenRouter. OpenRouter encaminha o cache_control
    // pra Anthropic, que cacheia por 5min (ephemeral). Outros providers ignoram.
    let systemMessage: ChatCompletionMessageParam
    if (typeof p.systemPrompt === 'string') {
      systemMessage = { role: 'system', content: p.systemPrompt }
    } else {
      // Array of blocks — OpenAI SDK aceita content como array.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const blocks: any[] = p.systemPrompt.map((b) => ({
        type: 'text',
        text: b.text,
        ...(b.cache === 'ephemeral' ? { cache_control: { type: 'ephemeral' } } : {}),
      }))
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      systemMessage = { role: 'system', content: blocks as any }
    }

    // Tools com cache_control no ÚLTIMO item — Anthropic cacheia tools até esse.
    let toolsToSend = p.tools
    if (p.tools && p.tools.length > 0 && p.cacheTools) {
      toolsToSend = p.tools.map((t, i, arr) => {
        if (i === arr.length - 1) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          return { ...t, cache_control: { type: 'ephemeral' } } as any
        }
        return t
      })
    }

    const completion = await this.client.chat.completions.create(
      {
        model: p.model,
        messages: [systemMessage, ...p.messages],
        temperature: p.temperature ?? 0.4,
        max_tokens: p.maxTokens ?? 8192,
        ...(toolsToSend ? { tools: toolsToSend, tool_choice: p.toolChoice ?? 'auto' } : {}),
        ...(p.responseFormat ? { response_format: p.responseFormat } : {}),
      },
      Object.keys(headers).length ? { headers } : undefined,
    )

    const choice = completion.choices[0]
    if (!choice) throw new Error('OpenRouter returned no choices')

    const message = choice.message
    const toolCalls = (message.tool_calls ?? []).map((tc) => ({
      id: tc.id,
      name: tc.function.name,
      arguments: tc.function.arguments,
    }))

    const usage = completion.usage
    // Anthropic cache fields ficam em usage.prompt_tokens_details no formato
    // OpenAI-compatible. OpenRouter usa nomes ligeiramente diferentes dos da
    // Anthropic direta — testamos múltiplos. Confirmado live (2026-05-16):
    // OpenRouter retorna `cached_tokens` (read) e `cache_write_tokens` (create).
    const usageExt = usage as unknown as {
      cost?: number
      cache_creation_input_tokens?: number
      cache_read_input_tokens?: number
      prompt_tokens_details?: {
        cached_tokens?: number
        cache_creation_tokens?: number
        cache_write_tokens?: number
      }
    } | undefined
    const cacheRead =
      usageExt?.cache_read_input_tokens ?? usageExt?.prompt_tokens_details?.cached_tokens
    const cacheCreate =
      usageExt?.cache_creation_input_tokens ??
      usageExt?.prompt_tokens_details?.cache_creation_tokens ??
      usageExt?.prompt_tokens_details?.cache_write_tokens
    return {
      content: message.content ?? null,
      toolCalls,
      promptTokens: usage?.prompt_tokens ?? 0,
      completionTokens: usage?.completion_tokens ?? 0,
      totalTokens: usage?.total_tokens ?? 0,
      cacheCreationInputTokens: cacheCreate,
      cacheReadInputTokens: cacheRead,
      // OpenRouter retorna custo em `usage.cost` (extensão proprietária) — pode ser undefined
      costUsd: usageExt?.cost ?? null,
      model: completion.model,
      finishReason: choice.finish_reason ?? 'unknown',
      latencyMs: Date.now() - start,
    }
  }
}
