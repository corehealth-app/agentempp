/**
 * Detector determinístico de `consumed_date` — audit 06-18 (gap descoberto
 * pelo Discovery D do audit retroativo).
 *
 * Sinal: em 434 chamadas de `registra_refeicao` desde 2026-05-25 (commit
 * be4c13e que adicionou o campo), `consumed_date` foi passado ZERO vezes.
 * Roberto/Paulo/Erika têm mensagens claras ("isso foi ontem", "jantar de
 * ontem", "comi ontem à noite") mas o LLM nunca injetou o campo — refeição
 * cai sempre no dia atual, distorcendo o snapshot de ontem.
 *
 * Causa provável: a description do tool fala genericamente sobre
 * `consumed_date` mas o LLM (Sonnet/Haiku) consistentemente ignora. Detector
 * determinístico pré-LLM resolve sem depender de prompt obediência.
 *
 * Estratégia: regex de marcadores temporais em PT-BR. Quando detecta,
 * calcula a data alvo a partir do `now` no timezone do paciente.
 *
 * Patterns suportados (não exaustivo, mas cobre 90%+ dos casos vistos):
 *  - "ontem", "ontem à noite", "ontem de manhã"
 *  - "anteontem", "antes de ontem"
 *  - "de ontem" / "do dia de ontem"
 *  - "isso foi ontem", "jantar de ontem"
 *
 * NÃO detecta:
 *  - "ontem fiz X" sem mencionar refeição (ambíguo)
 *  - timestamps explícitos ("dia 15") — fica pra próxima fase
 *  - "essa manhã" / "hoje" — retorna null (hoje é default)
 */

export interface ConsumedDateDetection {
  /** Data inferida no timezone do paciente, YYYY-MM-DD. */
  consumed_date: string
  /** Quantos dias antes de hoje. 1 = ontem, 2 = anteontem. */
  days_ago: number
  /** Trecho do texto que disparou a detecção (pra audit). */
  matched_phrase: string
}

// Patterns FORTES — ancoram em refeição/ingestão explícita.
const YESTERDAY_STRONG_PATTERNS = [
  /\bontem\s+(?:de|à|a)\s+(?:noite|tarde|manhã|manha)\b/i,
  /\b(?:isso|essa|esse)\s+foi\s+ontem\b/i,
  /^foi\s+ontem\b/i,
  /^ontem[.!?]*$/i,
  /\b(?:jantar|almoço|almoco|café|cafe|lanche|ceia)\s+de\s+ontem\b/i,
  /\bcomi\s+(?:isso\s+)?ontem\b/i,
  /\bontem\s+à\s+noite\b/i,
  /\bdo\s+dia\s+(?:de\s+)?ontem\b/i,
]

// Lexemas de comida/ingestão pra validar o catch-all "ontem".
// Review CDD-1: catch-all isolado pegava "Bom dia, hoje vai ser melhor que
// ontem" / "ontem treinei pesado" / "dormi mal ontem" — sem contexto
// alimentar. Agora exige co-ocorrência (janela ~30 chars antes/depois).
const FOOD_LEXEMES =
  /\b(comi|comer|comemos|comeu|jantar|jantei|jantou|jantamos|almoço|almoco|almocei|almocou|almoçamos|café\s+da\s+manhã|cafe\s+da\s+manha|cafe|café|lanche|lanchei|lanchou|ceia|ceei|tomei|bebi|engoli|devorei|comida|refeição|refeicao|prato|alimentação|alimentacao)\b/i

// Pattern catch-all SÓ se houver co-ocorrência de lexema alimentar.
const YESTERDAY_CATCHALL = /\bontem\b/i

// Lexemas de NEGAÇÃO / SKIP — review CDD-2: "não comi ontem", "pulei almoço
// ontem", "esqueci de comer ontem" matchavam patterns FORTES e gravariam
// refeição inexistente em ontem. Pre-check rejeita esses casos.
// NOTA: "esqueci" sozinho é ambíguo ("esqueci de MANDAR o almoço" é
// logística, não skip). Tratamos separadamente abaixo.
const NEGATION_LEXEMES = /\b(n[ãa]o|nem|sem|pulei|pulou|pulamos|jejuei|jejum)\b/i
// "Esqueci de COMER/JANTAR/etc" = skip real. "Esqueci de MANDAR/AVISAR/
// REGISTRAR" = logística (paciente comeu mas não reportou).
const FORGOT_TO_EAT =
  /\besqueci\s+(?:de\s+)?(?:com[ie]r|jantar|almoçar|almocar|tomar|lanchar|cear|engolir)\b/i

const DAY_BEFORE_YESTERDAY_PATTERNS = [
  /\banteontem\b/i,
  /\bantes\s+de\s+ontem\b/i,
  /\bhá\s+2\s+dias\b/i,
  /\bdois\s+dias\s+atrás\b/i,
]

/**
 * Verifica se há negação numa janela de N caracteres ANTES do match.
 * Cobre "não comi ontem", "ontem não jantei", "pulei o almoço ontem".
 */
function hasNegationContext(text: string, matchIndex: number): boolean {
  // Janela: até 40 chars antes + a sentença depois até o próximo ponto
  const start = Math.max(0, matchIndex - 40)
  const before = text.slice(start, matchIndex)
  // Janela depois (cobre "ontem não jantei"): 30 chars
  const after = text.slice(matchIndex, Math.min(text.length, matchIndex + 30))
  if (NEGATION_LEXEMES.test(before) || NEGATION_LEXEMES.test(after)) return true
  // "Esqueci de COMER/JANTAR" também é skip; "esqueci de MANDAR/AVISAR" não.
  const window = text.slice(start, Math.min(text.length, matchIndex + 30))
  if (FORGOT_TO_EAT.test(window)) return true
  return false
}

/**
 * Verifica se há lexema alimentar próximo do match (janela ~50 chars
 * total). Pra ativar o catch-all "ontem" só em contexto de comida.
 */
function hasFoodContext(text: string, matchIndex: number): boolean {
  const start = Math.max(0, matchIndex - 50)
  const end = Math.min(text.length, matchIndex + 50)
  const window = text.slice(start, end)
  return FOOD_LEXEMES.test(window)
}

/**
 * Detecta marcador temporal explícito no texto do paciente e retorna a
 * data inferida no timezone dele (default America/Sao_Paulo).
 *
 * Prioridade: anteontem > ontem (mais específico vence). NÃO matcha "hoje"
 * (default da tool) nem datas futuras (paciente não registra refeição
 * futura).
 */
export function detectConsumedDate(
  patientText: string | null | undefined,
  timezone: string = 'America/Sao_Paulo',
  now: Date = new Date(),
): ConsumedDateDetection | null {
  if (!patientText) return null
  // recentUserMessages são unidos com uma quebra de linha. Cada segmento
  // precisa manter seu próprio contexto: "caminhada de ontem" não pode
  // emprestar "almoço" da mensagem seguinte e mudar a data da refeição.
  const messageSegments = patientText
    .split(/\r?\n+/)
    .map((segment) => segment.trim())
    .filter(Boolean)

  // Anteontem primeiro (mais específico). Pre-check de negação se matchar.
  for (const pat of DAY_BEFORE_YESTERDAY_PATTERNS) {
    for (const segment of messageSegments) {
      const m = segment.match(pat)
      if (m && m.index != null) {
        if (hasNegationContext(segment, m.index)) continue
        return {
          consumed_date: getLocalDateMinusDays(timezone, 2, now),
          days_ago: 2,
          matched_phrase: m[0],
        }
      }
    }
  }

  // Ontem — patterns FORTES primeiro (review CDD-1: catch-all isolado
  // pegava conversa não-alimentar). Patterns fortes já ancoram em
  // refeição/ingestão; ainda assim aplica pre-check de negação
  // (review CDD-2: "almoço de ontem não rolou" não deve disparar).
  for (const pat of YESTERDAY_STRONG_PATTERNS) {
    for (const segment of messageSegments) {
      const m = segment.match(pat)
      if (m && m.index != null) {
        if (hasNegationContext(segment, m.index)) continue
        return {
          consumed_date: getLocalDateMinusDays(timezone, 1, now),
          days_ago: 1,
          matched_phrase: m[0],
        }
      }
    }
  }

  // Catch-all "ontem" — só ativa se há contexto alimentar próximo E sem
  // negação na janela. Pega "comi feijão ontem" mas NÃO "ontem treinei
  // pesado" ou "Bom dia, hoje vai ser melhor que ontem".
  for (const segment of messageSegments) {
    const catchAll = segment.match(YESTERDAY_CATCHALL)
    if (catchAll && catchAll.index != null) {
      if (!hasNegationContext(segment, catchAll.index) && hasFoodContext(segment, catchAll.index)) {
        return {
          consumed_date: getLocalDateMinusDays(timezone, 1, now),
          days_ago: 1,
          matched_phrase: catchAll[0],
        }
      }
    }
  }

  return null
}

/**
 * Retorna a data local do paciente N dias atrás, em YYYY-MM-DD. Replica
 * o helper de timezone-utils localmente pra evitar dependência circular
 * (este módulo é importado por tools.ts).
 */
function getLocalDateMinusDays(timezone: string, days: number, now: Date): string {
  // Intl.DateTimeFormat parts é correto em qualquer TZ
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  const parts = fmt.formatToParts(now)
  const map: Record<string, string> = {}
  for (const p of parts) map[p.type] = p.value
  const todayLocal = new Date(
    `${map.year}-${map.month}-${map.day}T12:00:00Z`, // meio-dia evita DST edges
  )
  todayLocal.setUTCDate(todayLocal.getUTCDate() - days)
  return todayLocal.toISOString().slice(0, 10)
}
