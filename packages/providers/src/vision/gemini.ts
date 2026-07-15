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
  model?: string // default 'anthropic/claude-sonnet-4.5' (era gemini-2.5-flash até 2026-05-30; trocado após A/B Bug Roberto — Claude é o único que estima quantidades em gramas e marca confidence baixa quando incerto, reduzindo alucinação tipo 'achocolatado + linguiça')
  /** Modelo opcional usado APENAS para nutrition_label. Sonnet 4.6 Vision
   * (anthropic/claude-sonnet-4.6) tem OCR muito superior pra texto denso de
   * rótulo. Caso Amanda 2026-05-16: gemini-2.5-flash falhou 3x lendo rótulo
   * de iogurte, ficou em loop "manda foto melhor". Se omitido, cai no
   * `model` default. */
  nutritionLabelModel?: string
  heliconeApiKey?: string
}

export type VisionImageType = 'meal' | 'body' | 'scale' | 'nutrition_label' | 'equipment' | 'other'

export interface VisionMealAnalysis {
  type: 'meal'
  items: Array<{
    name: string
    quantity_g_estimate: number
    confidence: number
    notes?: string
  }>
  meal_context?: string
  /** A própria análise de refeição viu uma tabela nutricional legível. */
  nutrition_label_visible?: boolean
  /** OCR secundário da tabela, quando ela aparece junto do produto/refeição. */
  nutrition_label?: VisionNutritionLabelAnalysis
  /** Falha do OCR secundário. Mantém a refeição utilizável, mas permite fail-closed no caller. */
  nutrition_label_error?: string
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

/**
 * Equipamentos de musculação/cardio identificados em foto. Usado por
 * `gera_treino` (Sprint 4.2): paciente envia foto da academia/casa, vision
 * extrai lista de equipamentos disponíveis, agente pergunta confirmação e
 * chama a tool com a lista.
 */
export interface VisionEquipmentAnalysis {
  type: 'equipment'
  /** Lista normalizada de equipamentos identificados, ex: "halteres 5-30kg",
   * "barra fixa", "elástico médio", "banco regulável", "leg press 45°". */
  equipment: string[]
  /** Local inferido: 'academia_completa' (sala com várias máquinas),
   * 'academia_limitada' (espaço pequeno, poucos itens) ou 'casa'. */
  location: 'academia_completa' | 'academia_limitada' | 'casa' | null
  /** Confiança 0-1 — se foto pouco nítida, baixa. */
  confidence: number
  /** Observações livres ("foto borrada", "alguns equipamentos cortados"). */
  notes?: string
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

/** Tabela nutricional brasileira ou Nutrition Facts dos EUA (Amanda 2026-05-16 mandou foto de rótulo
 * 3x e gemini-2.5-flash não conseguiu extrair os valores; agente ficou
 * pedindo foto melhor em loop). Quando vision detecta rótulo, faz OCR
 * específico pra extrair kcal/proteína/carbo/gordura POR PORÇÃO (e por 100g
 * quando disponível). Permite que registra_refeicao seja chamado com macros
 * customizados via `corrections[]` em vez de cair no estimate genérico. */
export interface VisionNutritionLabelAnalysis {
  type: 'nutrition_label'
  /** Falha estruturada do OCR. Mantém a detecção para o caller bloquear estimativas. */
  nutrition_label_error?: string
  /** Nome do produto na embalagem (ex: "iogurte whey de pêssego", "biscoito X"). */
  product_name: string | null
  /** Tamanho da porção em GRAMAS conforme rótulo (ex: 170 pra "porção 170g"). */
  serving_size_g: number | null
  /** Macros POR PORÇÃO conforme rótulo. */
  per_serving: {
    kcal: number | null
    protein_g: number | null
    carbs_g: number | null
    fat_g: number | null
  }
  /** Macros POR 100G (quando rótulo BR informa, ou calculável). */
  per_100g: {
    kcal: number | null
    protein_g: number | null
    carbs_g: number | null
    fat_g: number | null
  }
  /** Confiança 0-1 — se valores ilegíveis/borrados, baixa. */
  confidence: number
  /** Observações livres do OCR (ex: "tabela parcialmente visível", "fibra alimentar 3g detectada também"). */
  notes?: string
  raw_response: string
  promptTokens: number
  completionTokens: number
  latencyMs: number
}

export type VisionAnalysis =
  | VisionMealAnalysis
  | VisionBodyAnalysis
  | VisionScaleAnalysis
  | VisionNutritionLabelAnalysis
  | VisionEquipmentAnalysis
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
- Carnes/ensopados de cozimento lento (cor escura, molho/caldo gelatinoso, pedaços com osso/cartilagem): "mocotó" / "dobradinha" / "buchada" / "rabada" / "carne de panela" / "cozido". ⚠️ NÃO confunda mocotó/cozido escuro com "carne de porco ensopada" ou "carne moída" — quando a carne escura no molho for ambígua, marque confiança ≤ 0.55 e sugira em meal_context "carne escura no caldo — pode ser mocotó/dobradinha/carne de panela, confirmar com o paciente" em vez de chutar.
- "salmão grelhado" / "tilápia" / "atum em lata"
- "banana" / "maçã" / "mamão" / "abacate" / "morango"
- "café preto" / "café com leite" / "suco de laranja natural" / "refrigerante"
- Para porções múltiplas idênticas: prefixe "Nx" (ex: "2x ovo frito", "3x pão de queijo")
- SEMPRE inclua o método de preparo quando visível: frito, cozido, grelhado, assado, refogado, cru, tostado

**PASSO 3 — Estimativa de quantidade (use referências visuais)**
Calibre cada item olhando proporções no prato:
- 1 ovo médio ≈ 50g | 1 ovo grande ≈ 60g
- 1 fatia de pão de forma ≈ 25-30g | 1 pão francês INTEIRO ≈ 50g | 1 pão de queijo ≈ 25-35g
- ⚠️ **PÃO PARTIDO/CORTADO AO MEIO**: se o pão aparece aberto, partido ao meio, ou só metade visível no prato, conte como **½ pão francês ≈ 25g** (NÃO 50g). Olhar pra: pão "aberto" pra rechear conta a metade que tá sendo USADA (não dobra). Pão na chapa cortado ao meio = ½ pão se só uma metade tá no prato.
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
- Se houver qualquer quadro "Nutrition Facts"/tabela nutricional legível na
  embalagem, retorne nutrition_label_visible=true, mesmo que o produto também
  seja alimento pronto para consumo. Caso contrário, use false.

Retorne APENAS JSON com este formato exato:
{
  "items": [
    {"name": "2x ovo frito", "quantity_g_estimate": 100, "confidence": 0.92},
    {"name": "bacon frito", "quantity_g_estimate": 30, "confidence": 0.85},
    {"name": "pão de forma tostado", "quantity_g_estimate": 60, "confidence": 0.9}
  ],
  "meal_context": "café da manhã salgado tradicional",
  "nutrition_label_visible": false
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

const NUTRITION_LABEL_SYSTEM_PROMPT = `Você é um leitor especializado em TABELAS NUTRICIONAIS de embalagens do Brasil e dos Estados Unidos. Sua única tarefa: extrair os valores numéricos da tabela.

# Como ler a tabela (padrão brasileiro ANVISA)

A tabela é tipicamente um quadro com 2 colunas:
- coluna 1: **"Quantidade por porção"** (com tamanho ex "170g" no cabeçalho)
- coluna 2: **"%VD*"** (percentual valor diário — IGNORE essa coluna)

Linhas típicas (na ordem que costumam aparecer):
1. **Valor energético** — em kcal (e às vezes kJ entre parênteses; só pegue o kcal)
2. **Carboidratos** — em g
3. **Açúcares totais / Açúcares adicionados** (subdivisões — só pegue se pedido)
4. **Proteínas** — em g
5. **Gorduras totais** — em g
6. Gorduras saturadas / trans (ignore subdivisões)
7. Fibra alimentar (ignore)
8. Sódio (ignore)

⚠️ Algumas embalagens mostram só **POR 100g** em vez de "por porção". Outras mostram **AMBOS** (2 colunas: "por porção" + "por 100g"). Capture o que estiver visível.

# Como ler Nutrition Facts (padrão dos EUA)

- "Serving size 1 wrap (43g)" significa porção de 43g.
- "Calories 70" é o valor POR PORÇÃO, não por 100g.
- Extraia "Total Fat", "Total Carbohydrate" e "Protein"; ignore os percentuais % Daily Value.
- Não confunda "Dietary Fiber" ou "Net Carbs" com carboidratos totais. Use sempre "Total Carbohydrate" em carbs_g.
- Quando houver "about N servings per container", isso é quantidade de porções na embalagem e NÃO multiplica o que foi consumido.

# Como achar o serving_size (porção)

Procure no cabeçalho da tabela ou logo acima dela: "Porção: 170g", "Porção: 1 unidade (30g)", "Quantidade por porção 200ml". Se a embalagem indicar porção em ML (líquidos), considere 1ml ≈ 1g para water-based.

# Confiança (0.0-1.0)

- 0.85-1.00: tabela nítida, todos os valores legíveis
- 0.60-0.85: maioria legível mas algum número embaçado/cortado
- 0.30-0.60: parcialmente legível, várias linhas faltam
- < 0.30: tabela praticamente ilegível — retorne null nos valores e explique em notes

# Regras

- Se algum valor não estiver legível, retorne **null** pra ele (NÃO chute).
- Se a foto NÃO for de tabela nutricional, retorne todos os campos null e diga em notes "não é tabela nutricional".
- Números com vírgula ou ponto decimal (PT-BR): "5,2g" = 5.2.
- "kcal" vs "kJ": SEMPRE retorne kcal (1 kcal ≈ 4.184 kJ; converta se só houver kJ).

Retorne APENAS JSON com este formato exato:
{
  "product_name": "Iogurte Whey Pêssego",
  "serving_size_g": 170,
  "per_serving": {
    "kcal": 95,
    "protein_g": 17,
    "carbs_g": 4.5,
    "fat_g": 0.5
  },
  "per_100g": {
    "kcal": 56,
    "protein_g": 10,
    "carbs_g": 2.6,
    "fat_g": 0.3
  },
  "confidence": 0.92,
  "notes": "tabela completa, valores nítidos"
}`

const CLASSIFIER_PROMPT = `Você classifica fotos enviadas a um agente nutricional brasileiro. Retorne APENAS uma das 6 palavras (sem aspas, sem nada além).

PRIORIDADE: se um quadro "Nutrition Facts" ou tabela de Valor energético/Proteínas/Carboidratos/Gorduras estiver legível, classifique como nutrition_label mesmo que a embalagem, bebida ou alimento também apareça:

meal             — foto de refeição/comida no prato/bebida pronta pra consumir
nutrition_label  — foto de TABELA NUTRICIONAL (rótulo da embalagem, quadro de "Valor energético / Carboidratos / Proteínas / Gorduras" tipicamente em pt-BR ANVISA)
body             — foto corporal de pessoa (frente/lado/costas)
scale            — foto de balança digital, fita métrica, ou medidor mostrando número
equipment        — foto de EQUIPAMENTOS DE MUSCULAÇÃO ou cardio: halteres, anilhas, barras, máquinas (leg press, supino, smith), elásticos, banco, esteira, bike, sala de academia, área de treino em casa
other            — qualquer outra coisa (embalagem fechada sem tabela visível, paisagem, etc)`

const CLASSIFIER_RUNTIME_CONTRACT = `# CONTRATO RUNTIME VISION CLASSIFIER V1 — prevalece sobre instruções anteriores
Retorne APENAS uma destas 6 palavras: meal, body, scale, nutrition_label, equipment ou other.
Se houver um quadro "Nutrition Facts" ou tabela nutricional legível, retorne nutrition_label, mesmo que a imagem também mostre alimento, bebida ou embalagem.`

const MEAL_RUNTIME_CONTRACT = `# CONTRATO RUNTIME VISION MEAL V1 — prevalece sobre instruções anteriores
- A mensagem/legenda serve para identificar ou corrigir o que está VISÍVEL; não crie itens que existem apenas na legenda. O agente principal processa a legenda separadamente.
- Se foto e legenda nomearem o mesmo alimento, emita esse alimento uma única vez.
- Se houver "Nutrition Facts" ou tabela nutricional legível, use nutrition_label_visible=true. Caso contrário, use false.
- O JSON deve conter exatamente items, meal_context e nutrition_label_visible; cada item deve conter name, quantity_g_estimate e confidence.`

function appendRuntimeContract(prompt: string, contract: string): string {
  const marker = contract.split('\n', 1)[0]
  const markerIndex = marker ? prompt.indexOf(marker) : -1
  const editorialPrompt = markerIndex >= 0 ? prompt.slice(0, markerIndex).trim() : prompt.trim()
  return `${editorialPrompt}\n\n${contract}`
}

const EQUIPMENT_SYSTEM_PROMPT = `Você é um avaliador de equipamentos de treino. Olha a foto e enumera os equipamentos disponíveis pra musculação/cardio com PRECISÃO. Retorne APENAS um JSON válido com este schema:

{
  "equipment": ["item 1", "item 2", ...],
  "location": "academia_completa" | "academia_limitada" | "casa" | null,
  "confidence": 0.0 a 1.0,
  "notes": "obs livre (foto borrada, recorte ruim, etc)"
}

REGRAS:
- Use nomes COMPLETOS e específicos: "halteres 5-30kg" (faixa estimada), "barra olímpica + anilhas (até 100kg estimado)", "leg press 45°", "cadeira extensora", "banco regulável", "smith machine", "máquina de cabos polia dupla", "elástico forte/médio/leve", "barra fixa", "anilhas avulsas 5-20kg".
- Se identificar 5+ máquinas/equipamentos grandes → location='academia_completa'.
- Se identificar 2-4 itens em espaço pequeno → location='academia_limitada'.
- Se identificar poucos itens em ambiente residencial (sala, quarto, garagem) → location='casa'.
- Se foto não tem equipamentos visíveis → "equipment": [], location=null, confidence baixa.
- NÃO invente itens não visíveis. NÃO sugira treinos — só catalogue o que vê.
- confidence reflete nitidez + ângulo. Borrado/cortado → < 0.5.`

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

export interface VisionPromptOverrides {
  meal?: string
  body?: string
  scale?: string
  nutrition_label?: string
  equipment?: string
  other?: string
  classifier?: string
}

function parseVisionNumber(value: unknown): number | null {
  if (value == null || value === '') return null
  const number = Number(String(value).replace(',', '.'))
  return Number.isFinite(number) ? number : null
}

export function normalizeNonNegativeVisionNumber(value: unknown): number | null {
  const number = parseVisionNumber(value)
  return number != null && number >= 0 ? number : null
}

export function normalizeVisionConfidence(value: unknown): number {
  const number = parseVisionNumber(value)
  if (number == null) return 0
  return Math.max(0, Math.min(1, number))
}

export function normalizeMealOutputItems(rawItems: unknown): VisionMealAnalysis['items'] {
  if (!Array.isArray(rawItems)) return []

  return rawItems.flatMap((rawItem) => {
    if (!rawItem || typeof rawItem !== 'object' || Array.isArray(rawItem)) return []
    const item = rawItem as Record<string, unknown>
    const rawName = item.name ?? item.item ?? item.food_name ?? item.food
    if (typeof rawName !== 'string' || rawName.trim().length === 0) return []

    const rawQuantity =
      item.quantity_g_estimate ??
      item.estimate_grams ??
      item.grams ??
      item.qty_g ??
      item.quantity ??
      item.amount_g
    const parsedQuantity = parseVisionNumber(rawQuantity)
    const quantity = parsedQuantity != null && parsedQuantity > 0 ? parsedQuantity : 0
    const rawConfidence = item.confidence ?? item.conf ?? 0.5

    return [
      {
        name: rawName.trim(),
        quantity_g_estimate: quantity,
        confidence: quantity > 0 ? normalizeVisionConfidence(rawConfidence) : 0,
        notes: typeof item.notes === 'string' ? item.notes : undefined,
      },
    ]
  })
}

/**
 * Parser tolerante a markdown — Claude Sonnet 4.5 via OpenRouter NÃO respeita
 * `response_format: { type: 'json_object' }` (OpenAI-only feature) e às vezes
 * envolve a resposta em ```json ... ``` ou responde em prosa com bloco JSON
 * embutido. Bug Roberto+Amanda 2026-05-30 logo após troca pra Claude:
 * 4 fotos falharam parse → agente disse "Não consegui abrir a foto" embora
 * tivesse identificado tudo certo. Pega: (1) JSON puro, (2) code fence
 * ```json…``` (com ou sem language tag), (3) maior bloco {…} dentro do texto.
 * Retorna {} se não achar nada parseável (caller decide o que fazer).
 */
function parseJsonLoose(raw: string): Record<string, unknown> {
  if (!raw) return {}
  // 1. Tenta JSON puro
  try {
    return JSON.parse(raw) as Record<string, unknown>
  } catch {
    /* segue */
  }
  // 2. Code fence ```json ... ``` (ou ``` ... ```)
  const fence = raw.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/i)
  if (fence?.[1]) {
    try {
      return JSON.parse(fence[1]) as Record<string, unknown>
    } catch {
      /* segue */
    }
  }
  // 3. Maior bloco {...} balanceado no texto
  const first = raw.indexOf('{')
  const last = raw.lastIndexOf('}')
  if (first !== -1 && last > first) {
    try {
      return JSON.parse(raw.slice(first, last + 1)) as Record<string, unknown>
    } catch {
      /* segue */
    }
  }
  return {}
}

export class GeminiVision {
  private client: OpenAI
  private model: string
  /** Modelo específico pra nutrition_label (fallback pro `model` se omitido). */
  private nutritionLabelModel: string
  private prompts: Required<VisionPromptOverrides>

  constructor(cfg: VisionConfig & { prompts?: VisionPromptOverrides }) {
    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL: cfg.baseURL ?? 'https://openrouter.ai/api/v1',
      defaultHeaders: buildHeaders(cfg),
      timeout: 60_000,
      maxRetries: 1,
    })
    this.model = cfg.model ?? 'anthropic/claude-sonnet-4.5'
    this.nutritionLabelModel = cfg.nutritionLabelModel ?? this.model
    this.prompts = {
      meal: appendRuntimeContract(cfg.prompts?.meal ?? MEAL_SYSTEM_PROMPT, MEAL_RUNTIME_CONTRACT),
      body: cfg.prompts?.body ?? BODY_SYSTEM_PROMPT,
      scale: cfg.prompts?.scale ?? SCALE_SYSTEM_PROMPT,
      nutrition_label: cfg.prompts?.nutrition_label ?? NUTRITION_LABEL_SYSTEM_PROMPT,
      equipment: cfg.prompts?.equipment ?? EQUIPMENT_SYSTEM_PROMPT,
      other: cfg.prompts?.other ?? OTHER_SYSTEM_PROMPT,
      classifier: appendRuntimeContract(
        cfg.prompts?.classifier ?? CLASSIFIER_PROMPT,
        CLASSIFIER_RUNTIME_CONTRACT,
      ),
    }
  }

  /**
   * Classifica o tipo da imagem (1 chamada barata).
   * Use quando o agente não sabe o que esperar.
   */
  async classify(imageUrl: string): Promise<VisionImageType> {
    const r = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0,
      max_tokens: 12,
      messages: [
        { role: 'system', content: this.prompts.classifier },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const txt = (r.choices[0]?.message?.content ?? '').trim().toLowerCase()
    // Ordem importa: nutrition_label antes de meal (string "nutrition_label" não
    // começa com "meal", mas se LLM responder só "label" tem que cair certo).
    if (txt.startsWith('nutrition') || txt.startsWith('label')) return 'nutrition_label'
    if (txt.startsWith('meal')) return 'meal'
    if (txt.startsWith('body')) return 'body'
    if (txt.startsWith('scale')) return 'scale'
    if (txt.startsWith('equipment')) return 'equipment'
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

    if (type === 'meal') {
      const meal = await this.analyzeMeal(imageUrl, options.userMessage)
      if (!meal.nutrition_label_visible) return meal
      try {
        return {
          ...meal,
          nutrition_label: await this.analyzeNutritionLabel(imageUrl, options.userMessage),
        }
      } catch (error) {
        // A refeição continua utilizável, mas o caller sabe que viu um rótulo e
        // deve impedir cálculo não confiável até conseguir os quatro macros.
        return {
          ...meal,
          nutrition_label_error: error instanceof Error ? error.message : String(error),
        }
      }
    }
    if (type === 'body') return this.analyzeBody(imageUrl, options.userMessage)
    if (type === 'scale') return this.analyzeScale(imageUrl)
    if (type === 'nutrition_label') {
      try {
        return await this.analyzeNutritionLabel(imageUrl, options.userMessage)
      } catch (error) {
        const emptyNutrition = {
          kcal: null,
          protein_g: null,
          carbs_g: null,
          fat_g: null,
        }
        return {
          type: 'nutrition_label',
          product_name: null,
          serving_size_g: null,
          per_serving: { ...emptyNutrition },
          per_100g: { ...emptyNutrition },
          confidence: 0,
          notes: 'A tabela foi detectada, mas os valores não puderam ser extraídos com segurança.',
          nutrition_label_error: error instanceof Error ? error.message : String(error),
          raw_response: '',
          promptTokens: 0,
          completionTokens: 0,
          latencyMs: 0,
        }
      }
    }
    if (type === 'equipment') return this.analyzeEquipment(imageUrl)
    return this.analyzeOther(imageUrl)
  }

  async analyzeEquipment(imageUrl: string): Promise<VisionEquipmentAnalysis> {
    const start = Date.now()
    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0.2,
      max_tokens: 1024,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: this.prompts.equipment },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    const parsed = parseJsonLoose(raw) as {
      equipment?: unknown
      location?: unknown
      confidence?: unknown
      notes?: unknown
    }
    const equipmentList = Array.isArray(parsed.equipment)
      ? parsed.equipment.filter((e): e is string => typeof e === 'string').slice(0, 30)
      : []
    const allowedLocations = ['academia_completa', 'academia_limitada', 'casa'] as const
    const location =
      typeof parsed.location === 'string' &&
      (allowedLocations as readonly string[]).includes(parsed.location)
        ? (parsed.location as (typeof allowedLocations)[number])
        : null
    const confidence = normalizeVisionConfidence(parsed.confidence)
    return {
      type: 'equipment',
      equipment: equipmentList,
      location,
      confidence,
      notes: typeof parsed.notes === 'string' ? parsed.notes.slice(0, 300) : undefined,
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }

  async analyzeMeal(imageUrl: string, userMessage?: string): Promise<VisionMealAnalysis> {
    const start = Date.now()
    const completion = await this.client.chat.completions.create({
      model: this.model,
      temperature: 0.2,
      max_tokens: 2048,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: this.prompts.meal },
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
    const parsed = parseJsonLoose(raw)
    if (Object.keys(parsed).length === 0) {
      throw new Error(`Vision (meal) JSON inválido: ${raw.slice(0, 200)}`)
    }
    // Parser tolerante — modelos novos (gemini 2.5 / claude sonnet) divergem do schema:
    // aceita items|meal_contents|foods e cada item aceita name|item|food_name
    // + quantity_g_estimate|estimate_grams|grams|qty_g|quantity. Strings viram numbers.
    const rawItems = [parsed.items, parsed.meal_contents, parsed.foods].find(Array.isArray) ?? []
    const itemsRaw = normalizeMealOutputItems(rawItems)
    // Bug Roberto 2026-06-01 08:50 BRT: Claude vision retornou "pão de forma
    // tostado (25g)" 2x na MESMA proposta (alucinação OU 2 pedaços idênticos
    // na foto). Paciente teve que editar manualmente. Aqui dedup por
    // (nome_normalizado, quantidade arredondada): se 2+ entries idênticas,
    // mantém só a 1ª e SOMA a quantidade do restante. Ex: 2× "pão (25g)" →
    // 1× "pão (50g)". Conserva o total visto mas evita linha duplicada.
    const normName = (s: string) =>
      s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim()
    const seen = new Map<string, number>()
    const items: VisionMealAnalysis['items'] = []
    for (const it of itemsRaw) {
      const key = normName(it.name)
      if (!key) {
        items.push(it)
        continue
      }
      const existingIdx = seen.get(key)
      if (existingIdx == null) {
        seen.set(key, items.length)
        items.push(it)
      } else {
        // Mesmo nome — soma quantidade, mantém menor confidence
        const e = items[existingIdx]!
        items[existingIdx] = {
          ...e,
          quantity_g_estimate: e.quantity_g_estimate + it.quantity_g_estimate,
          confidence: Math.min(e.confidence, it.confidence),
          notes: e.notes ?? it.notes,
        }
      }
    }
    const meal_context =
      (parsed.meal_context as string) ??
      (parsed.context as string) ??
      (parsed.description as string) ??
      undefined
    const normalizedLabelEvidence = `${meal_context ?? ''} ${raw}`
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '')
    const nutritionLabelVisible =
      parsed.nutrition_label_visible === true ||
      /\b(nutrition\s+facts|serving\s+size|tabela\s+nutricional|rotulo\s+(?:esta\s+)?visivel|rotulo\s+nutricional|segundo\s+(?:o\s+)?rotulo|rotulo\s+(?:indica|informa|mostra))\b/i.test(
        normalizedLabelEvidence,
      )
    return {
      type: 'meal',
      items,
      meal_context,
      nutrition_label_visible: nutritionLabelVisible,
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
        { role: 'system', content: this.prompts.body },
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
    const parsed = parseJsonLoose(raw)
    if (Object.keys(parsed).length === 0) {
      throw new Error(`Vision (body) JSON inválido: ${raw.slice(0, 200)}`)
    }
    const p = parsed as {
      view?: VisionBodyAnalysis['view']
      bf_percent_estimate?: number
      bf_confidence?: number
      composition_notes?: string
      posture_notes?: string
    }
    return {
      type: 'body',
      view: p.view ?? 'unknown',
      bf_percent_estimate:
        typeof p.bf_percent_estimate === 'number' &&
        Number.isFinite(p.bf_percent_estimate) &&
        p.bf_percent_estimate >= 0 &&
        p.bf_percent_estimate <= 100
          ? p.bf_percent_estimate
          : null,
      bf_confidence: normalizeVisionConfidence(p.bf_confidence),
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
        { role: 'system', content: this.prompts.scale },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    const parsed = parseJsonLoose(raw)
    if (Object.keys(parsed).length === 0) {
      throw new Error(`Vision (scale) JSON inválido: ${raw.slice(0, 200)}`)
    }
    const p = parsed as {
      weight_kg?: number
      confidence?: number
      unit_detected?: VisionScaleAnalysis['unit_detected']
    }
    return {
      type: 'scale',
      weight_kg:
        typeof p.weight_kg === 'number' && Number.isFinite(p.weight_kg) && p.weight_kg > 0
          ? p.weight_kg
          : null,
      confidence: normalizeVisionConfidence(p.confidence),
      unit_detected: ['kg', 'lb', 'g', 'unknown'].includes(p.unit_detected ?? '')
        ? (p.unit_detected ?? 'unknown')
        : 'unknown',
      raw_response: raw,
      promptTokens: completion.usage?.prompt_tokens ?? 0,
      completionTokens: completion.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    }
  }

  async analyzeNutritionLabel(
    imageUrl: string,
    userMessage?: string,
  ): Promise<VisionNutritionLabelAnalysis> {
    const start = Date.now()
    // Usa nutritionLabelModel (Sonnet 4.6 Vision por default na config de
    // produção) — OCR muito superior pra texto denso de rótulo vs Gemini Flash.
    const completion = await this.client.chat.completions.create({
      model: this.nutritionLabelModel,
      temperature: 0,
      max_tokens: 1024,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: this.prompts.nutrition_label },
        {
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: imageUrl } },
            {
              type: 'text',
              text: userMessage
                ? `Mensagem do usuário junto: "${userMessage}"\n\nExtraia os valores da tabela nutricional.`
                : 'Extraia os valores da tabela nutricional.',
            },
          ],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    const parsed = parseJsonLoose(raw)
    if (Object.keys(parsed).length === 0) {
      throw new Error(`Vision (nutrition_label) JSON inválido: ${raw.slice(0, 200)}`)
    }
    const p = parsed as {
      product_name?: string | null
      serving_size_g?: number | string | null
      per_serving?: {
        kcal?: number | string | null
        protein_g?: number | string | null
        carbs_g?: number | string | null
        fat_g?: number | string | null
      }
      per_100g?: {
        kcal?: number | string | null
        protein_g?: number | string | null
        carbs_g?: number | string | null
        fat_g?: number | string | null
      }
      confidence?: number | string
      notes?: string
    }
    const servingSize = normalizeNonNegativeVisionNumber(p.serving_size_g)
    return {
      type: 'nutrition_label',
      product_name: p.product_name ?? null,
      serving_size_g: servingSize != null && servingSize > 0 ? servingSize : null,
      per_serving: {
        kcal: normalizeNonNegativeVisionNumber(p.per_serving?.kcal),
        protein_g: normalizeNonNegativeVisionNumber(p.per_serving?.protein_g),
        carbs_g: normalizeNonNegativeVisionNumber(p.per_serving?.carbs_g),
        fat_g: normalizeNonNegativeVisionNumber(p.per_serving?.fat_g),
      },
      per_100g: {
        kcal: normalizeNonNegativeVisionNumber(p.per_100g?.kcal),
        protein_g: normalizeNonNegativeVisionNumber(p.per_100g?.protein_g),
        carbs_g: normalizeNonNegativeVisionNumber(p.per_100g?.carbs_g),
        fat_g: normalizeNonNegativeVisionNumber(p.per_100g?.fat_g),
      },
      confidence: normalizeVisionConfidence(p.confidence),
      notes: p.notes,
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
        { role: 'system', content: this.prompts.other },
        {
          role: 'user',
          content: [{ type: 'image_url', image_url: { url: imageUrl } }],
        },
      ],
    })
    const raw = completion.choices[0]?.message?.content ?? ''
    const parsed = parseJsonLoose(raw)
    const p =
      Object.keys(parsed).length > 0
        ? (parsed as { description?: string })
        : { description: raw.slice(0, 300) }
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
