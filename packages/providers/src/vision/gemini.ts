/**
 * Vision via Gemini 2.0 Flash (OpenRouter), multi-prompt.
 *
 * Suporta 4 tipos de análise (autodetectados ou via hint do agente):
 *   - meal:  foto de refeição → JSON com itens/quantidade/confiança
 *   - body:  foto corporal (frente/lado/costas) → estimativa de BF%
 *            + composição visual
 *   - scale: foto de balança/medidor → leitura de número (kg)
 *   - other: qualquer outra → descrição livre em pt-BR
 *
 * Cada análise tem prompt próprio. O classificador é uma chamada LLM
 * curta que prediz o tipo. Se o agente já souber o tipo (ex: stage =
 * onboarding pedindo foto corporal), passar `hint` evita a classificação.
 */
import OpenAI from 'openai'

export interface VisionConfig {
  apiKey: string
  baseURL?: string
  model?: string // default 'google/gemini-2.0-flash-001'
  heliconeApiKey?: string
}

export type VisionImageType = 'meal' | 'body' | 'scale' | 'other'

export interface VisionMealAnalysis {
  type: 'meal'
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

export interface VisionBodyAnalysis {
  type: 'body'
  /** view ângulo: 'front' | 'side' | 'back' | 'unknown' */
  view: 'front' | 'side' | 'back' | 'unknown'
  bf_percent_estimate: number | null
  bf_confidence: number
  composition_notes: string
  posture_notes?: string
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

export interface VisionScaleAnalysis {
  type: 'scale'
  weight_kg: number | null
  confidence: number
  unit_detected: 'kg' | 'lb' | 'g' | 'unknown'
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

export interface VisionOtherAnalysis {
  type: 'other'
  description: string
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

export type VisionAnalysis =
  | VisionMealAnalysis
  | VisionBodyAnalysis
  | VisionScaleAnalysis
  | VisionOtherAnalysis

const MEAL_SYSTEM_PROMPT = `Você é um nutricionista brasileiro experiente analisando uma foto de refeição. Sua acurácia é crítica — o paciente toma decisão de protocolo a partir desses dados.

# Processo (faça mentalmente, em ordem)

**PASSO 1 — Identificação visual exaustiva**
Liste TUDO que vê no prato/cena, incluindo: alimentos principais, acompanhamentos, molhos visíveis, óleos/manteiga/queijo derretido, bebidas, suplementos. Não pule itens pequenos.

**PASSO 2 — Nomenclatura (escolha PT-BR popular do dia-a-dia)**
Sempre prefira o nome que um brasileiro usaria conversando, NÃO termo técnico/científico:
- "ovo frito" / "ovo mexido" / "ovo cozido" / "omelete" (✗ "ovo de galinha mexido", ✗ "scrambled egg")
- "bacon frito" / "bacon" (✗ "bacon cooked")
- "peito de frango grelhado" / "coxa assada" / "frango xadrez" (✗ "ave doméstica")
- "pão francês" / "pão de forma" / "pão de forma tostado" / "pão integral" / "pão de queijo" / "tapioca"
- "queijo minas" / "queijo branco" / "mussarela" / "queijo coalho" / "ricota" / "requeijão"
- "alface americana" / "alface crespa" / "tomate" / "pepino" / "cenoura ralada"
- "arroz branco cozido" / "arroz integral" / "feijão preto cozido" / "feijão carioca" / "farofa"
- "batata cozida" / "batata frita" / "batata doce cozida" / "purê de batata" / "mandioca cozida"
- "carne moída" / "patinho grelhado" / "picanha" / "filé mignon"
- "salmão grelhado" / "tilápia" / "atum em lata"
- "banana" / "maçã" / "mamão" / "abacate" / "morango"
- "café preto" / "café com leite" / "suco de laranja natural" / "refrigerante"
- Para porções múltiplas idênticas: prefixe "Nx" (ex: "2x ovo frito", "3x pão de queijo")
- SEMPRE inclua o método de preparo quando visível: frito, cozido, grelhado, assado, refogado, cru, tostado

**PASSO 3 — Estimativa de quantidade (use referências visuais)**
Calibre cada item olhando proporções no prato:
- 1 ovo médio ≈ 50g | 1 ovo grande ≈ 60g
- 1 fatia de pão de forma ≈ 25-30g | 1 pão francês ≈ 50g | 1 pão de queijo ≈ 25-35g
- 1 fatia de bacon ≈ 10-15g | 1 fatia de presunto ≈ 15g
- 1 fatia de queijo (sanduíche) ≈ 20g | cubo de queijo coalho ≈ 30g
- 1 concha de arroz cozido ≈ 100g | 1 colher servir ≈ 50g
- 1 concha de feijão ≈ 100g (com caldo) | só grãos ≈ 60g
- 1 filé tamanho palma da mão ≈ 100-120g | filé pequeno ≈ 80g
- 1 prato raso bem servido ≈ 350-450g total | prato modesto ≈ 250g
- 1 banana média ≈ 100g | 1 maçã média ≈ 150g
- 1 xícara café ≈ 50ml | 1 copo americano ≈ 200ml | 1 lata refri ≈ 350ml
- Salada de folhas ≈ 30-60g (alface é muito leve)
- Molho/azeite visível ≈ 5-15g
- 1 colher sopa óleo/azeite/maionese ≈ 12-15g

**PASSO 4 — Auto-checagem de confiança (0.0-1.0)**
Para CADA item, julgue honestamente:
- 0.85-1.00: alimento claramente identificável, porção bem visível, ângulo bom
- 0.65-0.85: identificação clara mas porção ambígua (oclusão, ângulo) OU porção clara mas alimento parecido com 2 outros (ex: "queijo branco" vs "ricota")
- 0.40-0.65: razoavelmente identificado mas com dúvida significativa (foto borrada, ângulo ruim, prato sobreposto)
- < 0.40: chute — prefira NÃO incluir o item e mencionar em meal_context "vejo algo que pode ser X ou Y, peça pro paciente confirmar"

⚠️ **NUNCA invente confiança alta pra parecer útil.** Confiança baixa é melhor que dado errado — o sistema pergunta ao paciente quando confiança é baixa.

# Regras de saída

- Líquidos: use o mesmo campo \`quantity_g_estimate\` (ml ≈ g pra água/café/leite/suco).
- Se não conseguir identificar absolutamente nada, retorne \`items: []\` e descreva em \`meal_context\`.
- \`meal_context\`: 1 frase curta sobre o tipo de refeição (ex: "café da manhã salgado", "almoço executivo", "lanche da tarde").
- Se a foto NÃO for de comida, retorne items=[] e meal_context com a descrição.

Retorne APENAS JSON com este formato exato:
{
  "items": [
    {"name": "2x ovo frito", "quantity_g_estimate": 100, "confidence": 0.92},
    {"name": "bacon frito", "quantity_g_estimate": 30, "confidence": 0.85},
    {"name": "pão de forma tostado", "quantity_g_estimate": 60, "confidence": 0.9}
  ],
  "meal_context": "café da manhã salgado tradicional"
}`

const BODY_SYSTEM_PROMPT = `Você é um avaliador físico experiente analisando uma foto corporal.

Sua tarefa: estimar percentual de gordura corporal (BF%) e descrever a composição visível.

Regras:
1. Identifique o ângulo da foto: front (frente), side (lado), back (costas) ou unknown.
2. Estime BF% baseado em definição muscular, distribuição de gordura visível, vascularização.
   - 8-12%: extremamente definido, vascularização visível, sem gordura abdominal
   - 13-17%: definido, abdomen visível em partes
   - 18-22%: levemente definido, abdomen pouco visível
   - 23-27%: gordura distribuída, sem definição visível
   - 28-32%: sobrepeso evidente
   - 33%+: obesidade
3. Confiança 0.0-1.0 — fotos com roupa larga, pouca luz ou ângulo ruim → confiança baixa.
4. Composição: descreva em 1-2 frases o que vê (massa muscular, distribuição de gordura, postura).
5. NÃO emita julgamento estético, só descrição técnica.

Se a foto NÃO for corporal (ex: comida, paisagem, pet), retorne bf_percent_estimate=null e composition_notes explicando o que vê.

Retorne APENAS JSON:
{
  "view": "front",
  "bf_percent_estimate": 24,
  "bf_confidence": 0.7,
  "composition_notes": "Massa muscular visível em ombros e braços, gordura abdominal moderada concentrada na região umbilical.",
  "posture_notes": "Leve protração de ombros, possível desequilíbrio postural"
}`

const SCALE_SYSTEM_PROMPT = `Você é um leitor de balanças/medidores. Sua tarefa: extrair o número exibido.

Regras:
1. Procure o número principal (geralmente o maior na tela).
2. Identifique a unidade (kg, lb, g) — se ambíguo, retorne 'unknown'.
3. Confiança 0.0-1.0: foto borrada, display apagado, números cortados → baixa.
4. Se NÃO for uma balança/medidor, retorne weight_kg=null.

Retorne APENAS JSON:
{
  "weight_kg": 87.4,
  "confidence": 0.95,
  "unit_detected": "kg"
}

Se a unidade for libras, converta pra kg (1 lb = 0.4536 kg) e marque unit_detected: "lb".`

const OTHER_SYSTEM_PROMPT = `Você é um descritor visual em pt-BR. Em 2-3 frases, descreva o que vê na foto, focando em informação útil pra um nutricionista (se aplicável: alimentos, embalagens, equipamentos de treino, ambiente).

Retorne APENAS JSON:
{ "description": "..." }`

const CLASSIFIER_PROMPT = `Você classifica fotos enviadas a um agente nutricional brasileiro. Retorne APENAS uma das 4 palavras (sem aspas, sem nada além):

meal  — foto de refeição/comida/bebida/embalagem alimentar
body  — foto corporal de pessoa (frente/lado/costas)
scale — foto de balança digital, fita métrica, ou medidor mostrando número
other — qualquer outra coisa`

function buildHeaders(cfg: VisionConfig): Record<string, string> {
  const headers: Record<string, string> = {
    'HTTP-Referer': 'https://github.com/corehealth-app/agentempp',
    'X-Title': 'Agente MPP',
  }
  if (cfg.heliconeApiKey) {
    headers['Helicone-Auth'] = `Bearer ${cfg.heliconeApiKey}`
  }
  return headers
}

export class GeminiVision {
  private client: OpenAI
  private model: string

  constructor(cfg: VisionConfig) {
    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL: cfg.baseURL ?? 'https://openrouter.ai/api/v1',
      defaultHeaders: buildHeaders(cfg),
      timeout: 60_000,
      maxRetries: 1,
    })
    this.model = cfg.model ?? 'google/gemini-2.5-flash'
  }

  /**
   * Classifica o tipo da imagem (1 chamada barata).
   * Use quando o agente não sabe o que esperar.
   */
  async classify(imageUrl: string): Promise<VisionImageType> {
    const r = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0,
      max_tokens: 8,
      messages: [
        { role: 'system', content: CLASSIFIER_PROMPT },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const txt = (r.choices[0]?.message?.content ?? '').trim().toLowerCase()
    if (txt.startsWith('meal')) return 'meal'
    if (txt.startsWith('body')) return 'body'
    if (txt.startsWith('scale')) return 'scale'
    return 'other'
  }

  /**
   * Analisa uma imagem com o prompt apropriado. Se `hint` for passado,
   * pula o classificador (1 chamada a menos).
   */
  async analyzeImage(
    imageUrl: string,
    options: { hint?: VisionImageType; userMessage?: string } = {},
  ): Promise<VisionAnalysis> {
    const type = options.hint ?? (await this.classify(imageUrl))

    if (type === 'meal') return this.analyzeMeal(imageUrl, options.userMessage)
    if (type === 'body') return this.analyzeBody(imageUrl, options.userMessage)
    if (type === 'scale') return this.analyzeScale(imageUrl)
    return this.analyzeOther(imageUrl)
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
    const raw = completion.choices[0]?.message?.content ?? ''
    let parsed: { items?: VisionMealAnalysis['items']; meal_context?: string } = {}
    try {
      parsed = JSON.parse(raw)
    } catch {
      throw new Error(`Vision (meal) JSON inválido: ${raw.slice(0, 200)}`)
    }
    return {
      type: 'meal',
      items: parsed.items ?? [],
      meal_context: parsed.meal_context,
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }

  async analyzeBody(imageUrl: string, userMessage?: string): Promise<VisionBodyAnalysis> {
    const start = Date.now()
    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0.2,
      max_tokens: 1024,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: BODY_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: imageUrl } },
            {
              type: 'text',
              text: userMessage
                ? `Contexto do usuário: "${userMessage}"`
                : 'Avalie a composição corporal.',
            },
          ],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    let p: {
      view?: VisionBodyAnalysis['view']
      bf_percent_estimate?: number
      bf_confidence?: number
      composition_notes?: string
      posture_notes?: string
    } = {}
    try {
      p = JSON.parse(raw)
    } catch {
      throw new Error(`Vision (body) JSON inválido: ${raw.slice(0, 200)}`)
    }
    return {
      type: 'body',
      view: p.view ?? 'unknown',
      bf_percent_estimate: p.bf_percent_estimate ?? null,
      bf_confidence: p.bf_confidence ?? 0,
      composition_notes: p.composition_notes ?? '',
      posture_notes: p.posture_notes,
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }

  async analyzeScale(imageUrl: string): Promise<VisionScaleAnalysis> {
    const start = Date.now()
    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0,
      max_tokens: 256,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SCALE_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    let p: {
      weight_kg?: number
      confidence?: number
      unit_detected?: VisionScaleAnalysis['unit_detected']
    } = {}
    try {
      p = JSON.parse(raw)
    } catch {
      throw new Error(`Vision (scale) JSON inválido: ${raw.slice(0, 200)}`)
    }
    return {
      type: 'scale',
      weight_kg: p.weight_kg ?? null,
      confidence: p.confidence ?? 0,
      unit_detected: p.unit_detected ?? 'unknown',
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }

  async analyzeOther(imageUrl: string): Promise<VisionOtherAnalysis> {
    const start = Date.now()
    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0.3,
      max_tokens: 256,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: OTHER_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    let p: { description?: string } = {}
    try {
      p = JSON.parse(raw)
    } catch {
      p = { description: raw.slice(0, 300) }
    }
    return {
      type: 'other',
      description: p.description ?? '',
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }
}
