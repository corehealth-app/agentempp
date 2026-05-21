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

const REGISTRATION_CLAIM =
  /\b(registr(?:ei|ado|ada|ados|adas)|anot(?:ei|ado|ada)|adicion(?:ei|ado|ada)\s+ao)\b/i

// Sem \b no FIM: "substituí" termina em vogal acentuada (não-ASCII), e \b
// ASCII falha entre "í" e espaço (ambos não-\w). Mesmo gotcha do correction-detector.
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

/**
 * Retorna isFake=true quando o texto afirma registro/correção + tem assinatura
 * de card (kcal ou emoji 🔥💪📊) MAS nenhuma tool de gravação rodou no turno.
 * Correção tem prioridade no `kind` (decide a mensagem de retry: replace=true).
 */
export function detectFakeWrite({
  content,
  registrationToolCalled,
}: FakeWriteInput): FakeWriteResult {
  if (registrationToolCalled) return { isFake: false, kind: null }

  const hasFoodSignature = /\bkcal\b/i.test(content) || /🔥|💪|📊/.test(content)
  if (!hasFoodSignature) return { isFake: false, kind: null }

  if (CORRECTION_CLAIM.test(content)) return { isFake: true, kind: 'correction' }
  if (REGISTRATION_CLAIM.test(content)) return { isFake: true, kind: 'registration' }
  return { isFake: false, kind: null }
}
