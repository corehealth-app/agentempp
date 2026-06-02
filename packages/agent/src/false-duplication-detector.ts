/**
 * Detector de falso positivo de "mensagem duplicada" (Roberto 2026-06-02).
 *
 * O LLM tem tendência a interpretar lista com múltiplos itens (ex:
 * "fiz 45 min de musculação e 19 min de bicicleta") como duplicação e
 * acusar o paciente. Caso real Paulo 30/05 + Luciana 31/05 + Roberto 02/06.
 *
 * Agent_rule sozinha não impediu — Claude segue acusando. Esta defesa é em
 * CÓDIGO: detecta padrão "veio duplicad / lista duplicad / msg duplicad" no
 * output + verifica se o texto do paciente é literalmente repetido. Se NÃO
 * for repetição literal, é falso positivo → pipeline força retry.
 */

const FALSE_DUP_PATTERN =
  /\b(veio|lista|mensagem|m[s]?g|parece|t[áa]\s+vindo)\s+duplicad/i

/**
 * Verifica se a msg do paciente tem REPETIÇÃO LITERAL (mesma string 2x,
 * ou linha idêntica aparecendo >1x). Heurística simples mas conservadora —
 * só retorna true em caso CLARO de duplicação, pra evitar falso negativo.
 */
export function isLiterallyDuplicated(text: string): boolean {
  if (!text || text.length < 10) return false
  const norm = text.toLowerCase().replace(/\s+/g, ' ').trim()

  // Caso 1: msg é a mesma SEQUÊNCIA DE PALAVRAS repetida 2x
  // (ex: "comi um pao integral comi um pao integral")
  const words = norm.split(' ')
  if (words.length >= 4 && words.length % 2 === 0) {
    const half = words.length / 2
    const firstHalf = words.slice(0, half).join(' ')
    const secondHalf = words.slice(half).join(' ')
    if (firstHalf === secondHalf) return true
  }

  // Caso 2: alguma linha (>5 chars) aparece >1x
  const lines = text
    .split(/\n+/)
    .map((l) => l.trim().toLowerCase().replace(/\s+/g, ' '))
    .filter((l) => l.length > 5)
  const seen = new Set<string>()
  for (const l of lines) {
    if (seen.has(l)) return true
    seen.add(l)
  }
  return false
}

/**
 * Detecta acusação espúria de duplicação. Retorna true quando o LLM acusou
 * mas o texto do paciente NÃO tem repetição literal.
 */
export function detectFalseDuplicationClaim(
  outputContent: string,
  patientText: string | null | undefined,
): boolean {
  if (!outputContent || !patientText) return false
  if (!FALSE_DUP_PATTERN.test(outputContent)) return false
  return !isLiterallyDuplicated(patientText)
}
