/**
 * Vision via Gemini 2.0 Flash (OpenRouter).
 *
 * Pipeline preferencial para análise de fotos de refeição:
 * recebe imagem + prompt → retorna JSON com itens identificados.
 */
import OpenAI from 'openai'

export interface VisionConfig {
  apiKey: string
  baseURL?: string
  model?: string // default 'google/gemini-2.0-flash-001'
  heliconeApiKey?: string
}

export interface VisionMealAnalysis {
  items: Array<{
    name: string
    quantity_g_estimate: number
    confidence: number
    notes?: string
  }>
  meal_context?: string
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

const MEAL_SYSTEM_PROMPT = `Você é um nutricionista experiente analisando uma foto de refeição brasileira.

Sua tarefa: identificar cada alimento visível, estimar a quantidade em gramas, e indicar sua confiança.

Regras:
1. Use nomes em português brasileiro, próximos aos da Tabela Brasileira de Composição de Alimentos (TACO)
2. Quantidades em gramas (números inteiros). Para líquidos, use ml (mas marque como tal).
3. Confiança 0.0-1.0 — seja honesto. Se a foto está ruim ou item ambíguo, baixe a confiança.
4. Inclua TODOS os itens visíveis, mesmo pequenos (manteiga no pão, fio de azeite na salada, etc.).
5. Para porções típicas brasileiras: 1 concha de arroz ≈ 100g, 1 concha de feijão ≈ 100g, 1 filé médio ≈ 120g.

Retorne APENAS JSON com este formato exato:
{
  "items": [
    {"name": "arroz branco cozido", "quantity_g_estimate": 150, "confidence": 0.9},
    {"name": "feijão carioca cozido", "quantity_g_estimate": 100, "confidence": 0.85}
  ],
  "meal_context": "almoço caseiro tradicional"
}`

export class GeminiVision {
  private client: OpenAI
  private model: string

  constructor(cfg: VisionConfig) {
    const headers: Record<string, string> = {
      'HTTP-Referer': 'https://github.com/corehealth-app/agentempp',
      'X-Title': 'Agente MPP',
    }
    if (cfg.heliconeApiKey) {
      headers['Helicone-Auth'] = `Bearer ${cfg.heliconeApiKey}`
    }

    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL: cfg.baseURL ?? 'https://openrouter.ai/api/v1',
      defaultHeaders: headers,
    })
    this.model = cfg.model ?? 'google/gemini-2.0-flash-001'
  }

  async analyzeMeal(imageUrl: string, userMessage?: string): Promise<VisionMealAnalysis> {
    const start = Date.now()

    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0.2,
      max_tokens: 2048,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: MEAL_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: imageUrl } },
            {
              type: 'text',
              text: userMessage
                ? `Mensagem do usuário junto com a foto: "${userMessage}"\n\nIdentifique os alimentos.`
                : 'Identifique os alimentos visíveis nesta refeição.',
            },
          ],
        },
      ],
    })

    const choice = completion.choices[0]
    if (!choice?.message?.content) {
      throw new Error('Vision retornou conteúdo vazio')
    }
    const raw = choice.message.content

    let parsed: { items?: VisionMealAnalysis['items']; meal_context?: string } = {}
    try {
      parsed = JSON.parse(raw)
    } catch {
      throw new Error(`Vision retornou JSON inválido: ${raw.slice(0, 200)}`)
    }

    return {
      items: parsed.items ?? [],
      meal_context: parsed.meal_context,
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }
}
