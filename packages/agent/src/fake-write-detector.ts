/**
 * Detector de "escrita fantasma": o LLM AFIRMA ter registrado/corrigido uma
 * refeição (ou treino) e exibe um card, mas NÃO chamou a tool de gravação no
 * turno — então nada foi salvo no banco.
 *
 * Casos reais:
 *  - Registro-fake (Luciana 2026-05-20): "Almoço registrado. … 521 kcal" sem
 *    chamar registra_refeicao → refeição fantasma, snapshot com déficit fake.
 *  - Correção-fake (Roberto 2026-05-21): "Corrigido. Feijão 180g…" sem chamar
 *    registra_refeicao(replace=true) → banco fica com a refeição velha; o card
 *    (canônico, vindo do banco) some com a correção.
 *
 * O card NUNCA é alucinado (o FIX C no pipeline reescreve o card com dados
 * frescos do banco). A falha é a montante: a tool não roda. Este detector é a
 * base do guard que força a tool a ser chamada.
 */

// "salv*" incluído (Paulo 2026-05-22): o agente usa MUITO "Café/Almoço/Jantar
// salvo" — era o buraco que mais perdia refeição (guard não pegava sem a tool).
const REGISTRATION_CLAIM =
  /\b(registr(?:ei|ado|ada|ados|adas)|anot(?:ei|ado|ada)|salv(?:o|a|os|as|ei|amos)|adicion(?:ei|ado|ada)\s+ao)\b/i

// Sem \b no FIM: "substituí" termina em vogal acentuada (não-ASCII), e \b
// ASCII falha entre "í" e espaço (ambos não-\w). Mesmo gotcha do correction-detector.
// Card de refeição itemizado (Roberto 2026-05-22 14:02): o agente às vezes mostra
// "**Almoço:** • item… **Total refeição: X**" SEM dizer "registrado/salvo" — é uma
// afirmação IMPLÍCITA de registro. "Total refeição" não aparece no card de balanço
// (que usa 🔥 Consumido), só no card de registro de refeição.
const MEAL_CARD = /total\s+(?:da\s+)?refei[çc][ãa]o/i

const CORRECTION_CLAIM =
  /\b(?:corrig(?:i|ido|ida|idos|idas)|corre[çc][ãa]o|substitu(?:í|i|ído|ido|ída|ida)|re-?registr(?:ei|ado|ada)|troquei|atualiz(?:ei|ado|ada))/i

// Skip explícito (Roberto 2026-06-16): paciente confirma que NÃO comeu uma
// refeição. Tool correta é `marca_refeicao_pulada`, NÃO `registra_refeicao`.
// Sem este detector dedicado, "Pulei o almoço, anotado." cai na regex
// REGISTRATION_CLAIM via "anotado" → retry força registra_refeicao →
// LLM inventa refeição vazia ou refaz uma anterior. Bug caso Roberto
// 2026-06-15 23:06 BRT: "Pulei" → Haiku "Anotado: jantar pulado" → fake_write
// detectou registration → Haiku no retry copiou items do LANCHE anterior
// e propôs registrar como pending fantasma.
const SKIP_CLAIM =
  /\b(?:pul(?:ei|ado|ada)|n[ãa]o\s+com(?:i|ia)|n[ãa]o\s+(?:almoc(?:ei|ava)|jantei|cafei|lanchei|ceei)|fiquei\s+sem\s+(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)|passei\s+direto|estou\s+em\s+jejum|t[ôo]\s+em\s+jejum|sem\s+(?:almo[çc]ar|jantar|caf[ée])\s+hoje)\b/i

// ABANDONO total — paciente NÃO está pulando UMA refeição, está reportando
// o dia inteiro sem comer. Não disparar skip-fake-write (caso clínico, não
// caso de tool). Daily-closer trata via incomplete_no_response.
const ABANDONMENT_CLAIM =
  /\bn[ãa]o\s+com(?:i|ia)\s+nada\s+(?:hoje|o\s+dia)|n[ãa]o\s+com(?:i|ia)\s+o\s+dia\s+(?:inteiro|todo)|jejum\s+(?:total|do\s+dia)|nada\s+(?:hoje|o\s+dia\s+inteiro)\b/i

// CONTEXTOS NEGATIVOS — paciente disse algo que CASA SKIP_CLAIM mas o
// contexto é claramente social/clínico, não skip de refeição. Bloqueia
// false positives (review CRITICAL 2026-06-16):
//  - "passei direto pra cama / pra casa / pro quarto"
//  - "passei direto pelo restaurante e comi em casa"
//  - "estou em jejum intermitente até 12h"
//  - "não comi banana" (negação de ITEM específico, não da refeição)
const SKIP_NEGATIVE_CONTEXT =
  /\bpassei\s+direto\s+(?:pra|para|pro|para\s+o|pelo|pelo[s]?|por|em)\s+\w+|jejum\s+intermitente|j(?:i|í)\s+intermitente|n[ãa]o\s+com(?:i|ia)\s+(?:o\s+|a\s+|um[a]?\s+)?[a-zà-ú]+\s*(?:hoje|agora|ontem)?\s*(?:,|\.|$)/i

// SKIP ACKNOWLEDGMENT no CONTENT do LLM — sinaliza que o LLM "anotou" o
// skip mas pode não ter chamado a tool. Combina com registration claim
// (anotado/salvo/registrado) — qualquer um basta.
const SKIP_ACK_CLAIM =
  /\b(?:pul(?:ado|ada|ados|adas)|sem\s+(?:registro|comer|refei[çc][ãa]o)|fica\s+(?:sem|em\s+branco)\s+(?:o\s+)?(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)|marquei?\s+(?:o\s+)?(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)\s+(?:como\s+)?pulad)/i

// Extrai meal_type literal do texto do paciente. Ordem importa pouco
// (regexes independentes), mas mantemos café→almoço→lanche→jantar→ceia
// pra estabilidade.
// BOUNDARY PT-BR: `\b` do JS não trata 'ã/é/ç' como word chars — então
// "Café da manhã" tem `\b` ANTES de 'ã' (sem match no final). Usamos
// boundary custom: começo/fim de string OU char não-alfa-PT-BR.
const MEAL_KEYWORDS: Array<
  [RegExp, 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia']
> = [
  [/(?:^|[^a-zà-úãõçâêôîû])(?:caf[ée](?:\s+da\s+manh[ãa])?)(?=$|[^a-zà-úãõçâêôîû])/i, 'cafe'],
  [/(?:^|[^a-zà-úãõçâêôîû])almo[çc](?:o|ar|ei)(?=$|[^a-zà-úãõçâêôîû])/i, 'almoco'],
  [/(?:^|[^a-zà-úãõçâêôîû])lanch(?:e|ei|ar)(?=$|[^a-zà-úãõçâêôîû])/i, 'lanche'],
  [/(?:^|[^a-zà-úãõçâêôîû])jant(?:ar|ei|ou)(?=$|[^a-zà-úãõçâêôîû])/i, 'jantar'],
  [/(?:^|[^a-zà-úãõçâêôîû])ceia(?=$|[^a-zà-úãõçâêôîû])/i, 'ceia'],
]

/**
 * Infere meal_type pra skip a partir do texto do paciente. Se o paciente
 * mencionou explicitamente ("pulei o almoço"), usa isso; senão usa o hint
 * (geralmente o gap_reminder mais recente ou inferência por hora local).
 */
export function inferMealFromSkipText(
  text: string,
  hint?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia',
): 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | null {
  for (const [re, meal] of MEAL_KEYWORDS) {
    if (re.test(text)) return meal
  }
  return hint ?? null
}

export interface FakeWriteInput {
  /** Texto final que o LLM produziu pro paciente. */
  content: string
  /** Texto do paciente (último input). Necessário pra detectar skip claim.
   *  Quando ausente, o branch de skip nunca dispara (zero regressão). */
  patientText?: string
  /** registra_refeicao OU registra_treino foi chamada com sucesso no turno. */
  registrationToolCalled: boolean
  /** gera_dieta OU gera_treino foi chamada com sucesso no turno. */
  prescriptionToolCalled?: boolean
  /** marca_refeicao_pulada foi chamada com sucesso no turno. */
  skipToolCalled?: boolean
  /** Fallback de meal_type quando texto do paciente não cita (vem do gap
   *  reminder do dia ou inferência por hora local — pipeline preenche). */
  mealTypeHint?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'
}

export interface FakeWriteResult {
  isFake: boolean
  kind: 'registration' | 'correction' | 'diet_fake' | 'training_fake' | 'skip' | null
  /** Quando kind='skip', meal_type sugerido pro retry msg. Pode ser null
   *  quando o paciente disse "pulei" sem especificar e não há hint. */
  inferredMealType?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | null
}

// Card de DIETA inventado (Sprint 4.1 review 2026-06-12): LLM apresenta
// "Café da manhã: ... Almoço: ... Lista de compras: ..." sem chamar
// `gera_dieta`. Paciente vai pra cozinha seguir uma dieta que ninguém
// salvou e cujos macros não foram validados. Critério: ≥2 "headers de
// refeição" (Café/Almoço/Lanche/Jantar) seguido de itens E uma seção
// "Lista de compras" no mesmo turno.
const DIET_REFEICAO_HEADER =
  /\b(?:caf[ée]\s+da\s+manh[ãa]|almo[çc]o|lanche\s+(?:da\s+)?(?:manh[ãa]|tarde)|jantar|ceia)\s*:/gi
const DIET_SHOPPING =
  /\b(?:lista\s+de\s+compras|compras\s+da\s+semana|mercado|hortifruti)\s*[:\n]/i
const DIET_TOTAL =
  /\b(?:total\s+(?:di[áa]rio|do\s+dia)|kcal\s+totais|prote[ií]na\s+total)\b/i

// Plano de TREINO inventado: LLM apresenta "Treino A: ... Treino B: ..."
// ou "Segunda: ... Quarta: ..." com exercícios+séries+reps sem chamar
// `gera_treino`. Paciente segue um plano não salvo, cron diário nunca
// dispara, e regenerar bloqueia 24h pelo rate-limit.
const TRAINING_DAY_HEADER =
  /\b(?:treino\s+[ABCabc]|segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo|dia\s+\d)\s*:/gi
const TRAINING_EXERCISE_LINE =
  /(?:^|\n)\s*[•\-*]?\s*[^\n]{4,40}\s+\d+\s*[x×]\s*\d+/g

// Assinatura de TREINO (Paulo 2026-05-28): bug real do detector que só pegava
// REFEIÇÃO. Caso: "Registrei as duas caminhadas de 60 minutos cada..." sem
// chamar registra_treino. Texto tinha "registrei" + "minutos" + "caminhadas"
// mas zero kcal/🔥/💪/📊 → guard antigo retornava isFake=false → fantasma
// passava. Confirmado: workout_logs vazio, tools_audit não tem registra_treino.
const WORKOUT_SIGNATURE =
  /\b\d+\s*(min|minutos?|hora|horas?|h)\b.*\b(caminhada|musculaç[ãa]o|treino|corrida|bike|bicicleta|nataç[ãa]o|alongamento|yoga|pilates|exerc[íi]cio|peso|for[çc]a|cross\w*)\b|\b(caminhada|musculaç[ãa]o|treino|corrida|bike|bicicleta|nataç[ãa]o|exerc[íi]cio).*\b\d+\s*(min|hora)/i

// Bug Roberto 2026-05-29 21:41: LLM IMITOU o formato exato do
// composePendingProposal pra almoço — "Vi isso nas suas fotos (Almoço):" +
// lista de itens + "Confirma?" — mas SEM chamar registra_refeicao. Como o
// pipeline interception só dispara quando a tool foi chamada, NÃO houve
// pending criado nem interactive payload com botões. Paciente recebeu uma
// proposta-fantasma sem botões; quando respondeu por texto, agente perdeu o
// contexto e autocorrigiu pra jantar. Este padrão complementa as assinaturas
// de kcal/workout: detecta a IMITAÇÃO de proposta de botão sem tool.
const FAKE_PROPOSAL =
  /\bvi\s+isso\s+na\s+sua\s+(?:foto|áudio|audio)|\bvi\s+isso\s+nas\s+suas\s+fotos\b|\bentendi\s+do\s+áudio\b|\bentendi\s+do\s+audio\b/i
const PROPOSAL_QUESTION = /\bconfirma\??\s*$|\bregistro\?\s*$/i

/**
 * Retorna isFake=true quando o texto afirma registro/correção + tem assinatura
 * de card (kcal/🔥💪📊 pra refeição OU duração+tipo pra treino) MAS nenhuma
 * tool de gravação rodou no turno. Correção tem prioridade no `kind` (decide
 * a mensagem de retry: replace=true).
 */
export function detectFakeWrite({
  content,
  patientText,
  registrationToolCalled,
  prescriptionToolCalled,
  skipToolCalled,
  mealTypeHint,
}: FakeWriteInput): FakeWriteResult {
  if (registrationToolCalled) return { isFake: false, kind: null }

  // Bug Roberto 2026-06-15: paciente diz "Pulei", LLM responde "Anotado:
  // jantar pulado" SEM chamar marca_refeicao_pulada. Antes do fix, esse texto
  // caía na regex REGISTRATION_CLAIM (via "anotado") e o retry forçava
  // registra_refeicao — Haiku obediente copiava items do histórico e criava
  // pending fantasma. Solução: detectar SKIP_CLAIM no texto do paciente
  // ANTES das regras de registration/correction, e quando marca_refeicao_pulada
  // NÃO foi chamada, flagrar kind='skip' (retry message dirigido pra skip
  // tool, não pra registra_refeicao).
  //
  // HARDENING (review CRITICAL 2026-06-16): SKIP_CLAIM sozinho gera false
  // positives massivos ("passei direto pra cama", "não comi banana",
  // "jejum intermitente"). Pré-condições obrigatórias agora:
  //  (a) NÃO casa SKIP_NEGATIVE_CONTEXT (filtra "passei direto pra X",
  //      "jejum intermitente", "não comi <item>")
  //  (b) NÃO casa ABANDONMENT (clínico, não tool)
  //  (c) CONTENT do LLM precisa parecer fake-acknowledgment de skip:
  //      SKIP_ACK_CLAIM OU REGISTRATION_CLAIM (que é o caso real do bug
  //      Roberto: "Anotado: jantar pulado").
  // Sem (c), o LLM provavelmente respondeu coisa normal/conversational
  // (e.g. "Boa noite!" pra "passei direto pra cama") e não há fake-write.
  if (patientText && !skipToolCalled) {
    const isAbandonment = ABANDONMENT_CLAIM.test(patientText)
    const hasNegativeContext = SKIP_NEGATIVE_CONTEXT.test(patientText)
    const hasSkipClaim = SKIP_CLAIM.test(patientText)
    if (!isAbandonment && !hasNegativeContext && hasSkipClaim) {
      // Pré-condição (c): LLM tem que ter "anotado" o skip — senão é
      // conversa normal e não há fake-write.
      const llmAcknowledgedSkip =
        SKIP_ACK_CLAIM.test(content) || REGISTRATION_CLAIM.test(content)
      if (llmAcknowledgedSkip) {
        const inferredMealType = inferMealFromSkipText(patientText, mealTypeHint)
        return { isFake: true, kind: 'skip', inferredMealType }
      }
    }
  }

  // --- Detectores de prescrição-fantasma (rodam ANTES das regras antigas
  // porque cardápio inventado tem aparência profissional, paciente segue
  // sem questionar). Só dispara se gera_dieta/gera_treino NÃO foram chamadas.
  if (!prescriptionToolCalled) {
    // DIET FAKE: ≥2 headers de refeição + (lista de compras OU total diário).
    // Os 2 sinais juntos diferenciam cardápio inventado de uma simples
    // explicação ("almoço: arroz + frango" em uma linha não dispara).
    const dietHeaders = content.match(DIET_REFEICAO_HEADER) ?? []
    const hasDietContext = DIET_SHOPPING.test(content) || DIET_TOTAL.test(content)
    if (dietHeaders.length >= 2 && hasDietContext) {
      return { isFake: true, kind: 'diet_fake' }
    }

    // TRAINING FAKE: ≥1 header de dia/treino + ≥3 linhas de exercício no
    // formato "Nome NxR". Apenas explicar "vou treinar segunda" não dispara.
    const trainingHeaders = content.match(TRAINING_DAY_HEADER) ?? []
    const exerciseLines = content.match(TRAINING_EXERCISE_LINE) ?? []
    if (trainingHeaders.length >= 1 && exerciseLines.length >= 3) {
      return { isFake: true, kind: 'training_fake' }
    }
  }

  // Proposta-fake (Roberto 2026-05-29): LLM imita "Vi isso na sua foto …
  // Confirma?" sem chamar tool. Não tem kcal/workout signature mas é claro
  // que o LLM achou que tava propondo um botão → força retry pra ele chamar
  // registra_refeicao e o pipeline criar o pending com botões de verdade.
  if (FAKE_PROPOSAL.test(content) && PROPOSAL_QUESTION.test(content.trim())) {
    return { isFake: true, kind: 'registration' }
  }

  const hasFoodSignature = /\bkcal\b/i.test(content) || /🔥|💪|📊/.test(content)
  const hasWorkoutSignature = WORKOUT_SIGNATURE.test(content)

  // Proposta-fake genérica (Roberto 2026-05-30 13:47): LLM disse "Entendido!
  // Então incluo também o ovo... • leite com whey 190 kcal... Total: 568 kcal
  // ... Confirma?" — tem kcal + bullets + "Confirma?" no fim, MAS sem verbo de
  // claim ("incluo" não bate REGISTRATION_CLAIM, "vi isso" não bate
  // FAKE_PROPOSAL). Critério mais amplo: refeição-signature + ≥2 bullets de
  // itens + termina com "Confirma?" → é proposta de botão sem tool. Retry.
  if (hasFoodSignature && PROPOSAL_QUESTION.test(content.trim())) {
    const bulletCount = (content.match(/(?:^|\n)\s*[•\-*]\s/g) ?? []).length
    if (bulletCount >= 2) {
      return { isFake: true, kind: 'registration' }
    }
  }

  // Proposta-fake SEM kcal (Roberto 2026-05-30 14:24): variante que escapou a
  // regra acima — LLM mandou "Então o almoço fica assim: • risoto (200g) •
  // queijo ralado (30g) ... Confirma?" SEM kcal e SEM emojis (só quantidades
  // em g/ml/unidade). Paciente teve que digitar "Confirma" pra forçar tool.
  // Critério: ≥2 bullets COM quantidade em (g)/(ml)/(unidade) + "Confirma?"
  // no fim → mesma intenção de proposta de botão, kind=registration.
  if (PROPOSAL_QUESTION.test(content.trim())) {
    const bulletLines = content.match(/(?:^|\n)\s*[•\-*]\s+[^\n]+/g) ?? []
    const QTY_IN_BULLET = /\(\s*\d+(?:[.,]\d+)?\s*(?:g|ml|kg|l|unidades?|fatia|p[ãa]o)\b/i
    const bulletsWithQty = bulletLines.filter((l) => QTY_IN_BULLET.test(l))
    if (bulletsWithQty.length >= 2) {
      return { isFake: true, kind: 'registration' }
    }
  }

  // Rascunho com kcal inventada (Roberto 2026-06-03 15:41): LLM mandou
  // "Entendi isso pro seu almoço: • alface crespa (40g) — 6 kcal • alface roxa
  // (20g) — 3 kcal ... Tem proteína nessa refeição?" — kcal em ≥2 bullets de
  // itens MAS termina com pergunta legítima (não "Confirma?") → escapa as
  // regras acima. Resultado: kcal inventada exibida ao paciente; quando a
  // tool roda na segunda passada, os números são diferentes e parece bug de
  // consistência. Critério: ≥2 bullets do formato "• <nome> (<qty>) — <X> kcal"
  // e nenhuma tool de registro chamada → força retry pro LLM chamar
  // registra_refeicao ANTES de mostrar kcal.
  const KCAL_BULLET = /(?:^|\n)\s*[•\-*]\s+[^\n]+\(\s*\d+(?:[.,]\d+)?\s*(?:g|ml|kg|l|unidades?|fatia|p[ãa]o)[^\n]*?\d+(?:[.,]\d+)?\s*kcal/i
  const kcalBullets = content.match(new RegExp(KCAL_BULLET.source, 'gi')) ?? []
  if (kcalBullets.length >= 2) {
    return { isFake: true, kind: 'registration' }
  }
  if (!hasFoodSignature && !hasWorkoutSignature) return { isFake: false, kind: null }

  if (CORRECTION_CLAIM.test(content)) return { isFake: true, kind: 'correction' }
  if (REGISTRATION_CLAIM.test(content) || MEAL_CARD.test(content))
    return { isFake: true, kind: 'registration' }
  return { isFake: false, kind: null }
}
