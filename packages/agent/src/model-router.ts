/**
 * Router de modelo por turn (Fase 6 do plano de redução de custo — 2026-06-04).
 *
 * Hoje 100% dos turnos conversacionais rodam em Sonnet 4.6 ($3/M in, $15/M out).
 * Muitos casos NÃO precisam dessa potência:
 *   - "ok", "valeu", "obrigado" (saudação/agradecimento isolado)
 *   - "quanto kcal hoje?" (resposta vem do snapshot, não precisa raciocínio)
 *   - "bom dia" (resposta curta, sem decisão de tool)
 *
 * Heurística conservadora: detecta intents SEGURAS pra Haiku 4.5 ($1/M in, $5/M out).
 * Em caso de dúvida → mantém Sonnet (default). Foto/áudio NUNCA rotear pra Haiku.
 *
 * Feature flag: `router.haiku_enabled` em global_config (default false). Liga
 * gradual pra observar comportamento antes de ativar pra todos.
 */

const HAIKU_MODEL = 'anthropic/claude-4.5-haiku-20251001'

/**
 * Palavras-chave que indicam REGISTRO DE COMIDA OU TREINO — exigem Sonnet
 * (precisa identificar itens, chamar tool, lidar com correções).
 */
const FOOD_WORKOUT_KEYWORDS = new RegExp(
  [
    // Refeições
    'caf[ée]', 'almoço', 'jantar', 'lanche', 'ceia', 'merenda', 'desjejum',
    // Verbos de ação
    'comi', 'bebi', 'tomei', 'almoc[ei]', 'jante[i]', 'lanche[i]',
    'inger', 'devor', 'mast', 'engoli', 'provei',
    // Alimentos comuns
    'whey', 'leite', 'p[ãa]o', 'frango', 'carne', 'fruta', 'salada',
    'arroz', 'feijão', 'feijao', 'ovo', 'queijo', 'iogurte', 'banana',
    'maç[ãa]', 'manga', 'abac', 'massa', 'macarr', 'risoto', 'sopa',
    'sand[uú]', 'pizza', 'hamb', 'tapioca', 'crep', 'panqu', 'biscoito',
    // Treino
    'treino', 'musculaç', 'corrida', 'caminhada', 'bicicleta', 'cardio',
    'aerob', 'exerc[ií]', 'academia', 'pernas?', 'peito', 'costas', 'ombro',
    'spinning', 'nataç', 'yoga', 'pilates', 'crossfit', 'hiit',
    // Unidades de quantidade (sinal forte de descrição de refeição)
    '\\d+\\s*(g|ml|kg|l|gramas?|colher|fatia|pedaço|unidade|prato|copo|xícara|xicara|porção|porcao)',
    // Foto referência
    'foto', 'imagem', 'mandei', 'enviei',
  ].join('|'),
  'i',
)

/**
 * Saudações/agradecimentos curtos isolados — resposta simples, Haiku basta.
 */
const TRIVIAL_GREETING = new RegExp(
  '^\\s*(ok|okay|valeu|obrigad[oa]|brigad[oa]|t[áa]|tá|tudo certo|certo|bele|beleza|' +
    'legal|show|massa|tranquilo|saquei|entendi|claro|fechou|pode crer|bacana|joia|' +
    'top|👍|🙏|❤️|👏|✅|sim|n[ãa]o)\\s*[!\\.]?\\s*$',
  'i',
)

const GREETING_OPENER = new RegExp(
  '^\\s*(bom dia|boa tarde|boa noite|oi|ol[áa]|hey|hi|hello|e a[íi])\\s*[!?\\.]?\\s*$',
  'i',
)

/**
 * Perguntas de status onde resposta vem direto do snapshot/progress —
 * raciocínio é apenas formatar números. Haiku basta.
 */
const STATUS_QUESTION = new RegExp(
  '\\b(quant[oa]s?|qual|onde|como)\\s+(\\w+\\s+){0,2}' +
    '(' +
    'kcal|caloria|cal|grama|gr|kg|prote|carbo|fat|d[ée]ficit|bloco|consumi|' +
    'restam?|sobrou|falta|meta|saldo|consum|comi hoje|gastei' +
    ')',
  'i',
)

export interface ModelRoutingContext {
  /** Texto da mensagem do paciente (pode estar vazio se for mídia). */
  text: string | null | undefined
  /** Tipo do conteúdo recebido. Foto/áudio NUNCA Haiku. */
  contentType: 'text' | 'audio' | 'image' | 'interactive' | null | undefined
  /** Estágio do agente. coleta_dados (onboarding) sempre Sonnet. */
  stage: string | null | undefined
  /** Tipo da última msg INBOUND do paciente. Se foto pendente → Sonnet pra
   * lidar com proposta. */
  lastInboundContentType: 'text' | 'audio' | 'image' | null | undefined
  /** True se paciente sumiu >7d — reentrada precisa Sonnet pra warm restart. */
  isReentry: boolean
  /** True se há pending_registration aberta — pode haver correção em texto. */
  hasOpenPending?: boolean
}

export interface ModelRoutingResult {
  /** Modelo escolhido. */
  model: string
  /** Se mudou do default. */
  changed: boolean
  /** Motivo do roteamento (pra log). */
  reason: string
}

/**
 * Decide o modelo pra UM turn. Default mantém o `defaultModel` (Sonnet).
 * Só troca pra Haiku quando heurística é CONFIDENTE de que é caso seguro.
 *
 * Critérios pra MANTER Sonnet (defensivos):
 *  - content_type = image/audio (mídia precisa Sonnet 4.5/4.6)
 *  - stage = coleta_dados (onboarding decisões críticas)
 *  - isReentry (sumiu >7d, contexto frio)
 *  - hasOpenPending (correção de pending pode estar vindo)
 *  - texto contém keyword de comida/treino
 *  - texto longo (>120 chars) — provavelmente requisição complexa
 *
 * Critérios pra TROCAR pra Haiku:
 *  - saudação isolada (oi, bom dia)
 *  - agradecimento/confirmação curta (ok, valeu)
 *  - pergunta de status (quanto kcal, qual meu bloco)
 */
export function routeModel(
  defaultModel: string,
  haikuEnabled: boolean,
  ctx: ModelRoutingContext,
): ModelRoutingResult {
  // Feature flag off → sempre default
  if (!haikuEnabled) {
    return { model: defaultModel, changed: false, reason: 'flag_off' }
  }

  const text = (ctx.text ?? '').trim()

  // Mídia atual → Sonnet
  if (ctx.contentType === 'image' || ctx.contentType === 'audio') {
    return { model: defaultModel, changed: false, reason: 'media_input' }
  }

  // Última msg inbound foi mídia → provavelmente segue contexto da foto
  if (ctx.lastInboundContentType === 'image' || ctx.lastInboundContentType === 'audio') {
    return { model: defaultModel, changed: false, reason: 'recent_media_context' }
  }

  // Onboarding (coleta_dados) → Sonnet (decisões críticas)
  if (ctx.stage === 'coleta_dados') {
    return { model: defaultModel, changed: false, reason: 'stage_onboarding' }
  }

  // Reentrada (>7d sem msg) → Sonnet
  if (ctx.isReentry) {
    return { model: defaultModel, changed: false, reason: 'reentry' }
  }

  // Pending aberto → Sonnet (pode estar vindo correção)
  if (ctx.hasOpenPending) {
    return { model: defaultModel, changed: false, reason: 'open_pending' }
  }

  // Texto vazio → Sonnet (sem dado pra heurística)
  if (text.length === 0) {
    return { model: defaultModel, changed: false, reason: 'empty_text' }
  }

  // Texto longo → provavelmente complexo, Sonnet
  if (text.length > 120) {
    return { model: defaultModel, changed: false, reason: 'long_text' }
  }

  // Texto menciona comida/treino → Sonnet (registro de refeição/exercício)
  if (FOOD_WORKOUT_KEYWORDS.test(text)) {
    return { model: defaultModel, changed: false, reason: 'food_workout_keyword' }
  }

  // Agora critérios POSITIVOS pra Haiku
  if (TRIVIAL_GREETING.test(text)) {
    return { model: HAIKU_MODEL, changed: true, reason: 'trivial_greeting' }
  }
  if (GREETING_OPENER.test(text)) {
    return { model: HAIKU_MODEL, changed: true, reason: 'greeting_opener' }
  }
  if (STATUS_QUESTION.test(text)) {
    return { model: HAIKU_MODEL, changed: true, reason: 'status_question' }
  }

  // Default — não tem critério positivo pra Haiku, mantém Sonnet
  return { model: defaultModel, changed: false, reason: 'no_haiku_match' }
}
