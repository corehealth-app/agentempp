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

export interface LLMCallParams {
  model: string
  systemPrompt: string
  messages: ChatCompletionMessageParam[]
  temperature?: number
  maxTokens?: number
  tools?: ChatCompletionTool[]
  /** Forçar uso de tool específica, ou 'auto' (padrão). */
  toolChoice?: 'auto' | 'none' | { type: 'function'; function: { name: string } }
  /** JSON mode (structured output). Se Zod schema futuramente, usar response_format. */
  responseFormat?: { type: 'json_object' }
  /** Metadata para tracking (Helicone properties). */
  metadata?: Record<string, string>
  /** User identifier (Helicone-User-Id). */
  userId?: string
}

export interface LLMResult {
  content: string | null
  toolCalls: Array<{ id: string; name: string; arguments: string }>
  promptTokens: number
  completionTokens: number
  totalTokens: number
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

    const completion = await this.client.chat.completions.create(
      {
        model: p.model,
        messages: [{ role: 'system', content: p.systemPrompt }, ...p.messages],
        temperature: p.temperature ?? 0.4,
        max_tokens: p.maxTokens ?? 8192,
        ...(p.tools ? { tools: p.tools, tool_choice: p.toolChoice ?? 'auto' } : {}),
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
    return {
      content: message.content ?? null,
      toolCalls,
      promptTokens: usage?.prompt_tokens ?? 0,
      completionTokens: usage?.completion_tokens ?? 0,
      totalTokens: usage?.total_tokens ?? 0,
      // OpenRouter retorna custo em `usage.cost` (extensão proprietária) — pode ser undefined
      costUsd: (usage as unknown as { cost?: number })?.cost ?? null,
      model: completion.model,
      finishReason: choice.finish_reason ?? 'unknown',
      latencyMs: Date.now() - start,
    }
  }
}
