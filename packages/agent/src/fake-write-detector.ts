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

export interface FakeWriteInput {
  /** Texto final que o LLM produziu pro paciente. */
  content: string
  /** registra_refeicao OU registra_treino foi chamada com sucesso no turno. */
  registrationToolCalled: boolean
  /** gera_dieta OU gera_treino foi chamada com sucesso no turno. */
  prescriptionToolCalled?: boolean
}

export interface FakeWriteResult {
  isFake: boolean
  kind: 'registration' | 'correction' | 'diet_fake' | 'training_fake' | null
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
  registrationToolCalled,
  prescriptionToolCalled,
}: FakeWriteInput): FakeWriteResult {
  if (registrationToolCalled) return { isFake: false, kind: null }

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
