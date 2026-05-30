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
}

export interface FakeWriteResult {
  isFake: boolean
  kind: 'registration' | 'correction' | null
}

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
}: FakeWriteInput): FakeWriteResult {
  if (registrationToolCalled) return { isFake: false, kind: null }

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
  if (!hasFoodSignature && !hasWorkoutSignature) return { isFake: false, kind: null }

  if (CORRECTION_CLAIM.test(content)) return { isFake: true, kind: 'correction' }
  if (REGISTRATION_CLAIM.test(content) || MEAL_CARD.test(content))
    return { isFake: true, kind: 'registration' }
  return { isFake: false, kind: null }
}
