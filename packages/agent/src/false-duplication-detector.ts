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

// Padrões de "acusação de duplicação" — LLM aprende sinônimos novos quase toda
// semana, por isso o regex precisa cobrir variações:
//   - "veio duplicad" / "veio em duplicidade"
//   - "lista duplicad" / "mensagem duplicad"
//   - "repetiu (os mesmos|esses) (itens|alimentos)" + "duas vezes / 2 vezes"
//   - "veio em duas (mensagens|msgs)" / "duas vezes" / "2 vezes"
//   - "duas porções (de cada)" / "2 porções"
//   - "(lista|mensagem) veio igual" / "veio igual das duas vezes" (Roberto 03/06)
//   - "(as duas|2) (mensagens|listas) (vieram|chegaram) iguais"
const FALSE_DUP_PATTERN = new RegExp(
  [
    String.raw`\b(veio|lista|mensagem|m[s]?g|parece|t[áa]\s+vindo)\s+duplicad`,
    String.raw`\brepetiu\s+(os\s+)?(mesmos|esses|os)?\s*(itens|alimentos)`,
    String.raw`\b(veio|chegou|t[áa]\s+vindo)\s+em\s+(duas|2)\s+(mensagens|msgs|vezes)`,
    String.raw`\b(duas|2)\s+por[çc][õo]es\s+(de\s+cada|iguais|iguais\?|mesmo)`,
    String.raw`\bvoc[êe]\s+mandou\s+(os\s+)?(mesmos|esses)\s+itens\s+(duas|2)\s+vezes`,
    String.raw`\b(lista|mensagem|m[s]?g)\s+(veio|chegou|t[áa]\s+vindo)\s+igual\b`,
    String.raw`\b(veio|chegou)\s+igual\s+(das|nas)?\s*(duas|2)?\s*(vezes|mensagens|msgs)`,
    String.raw`\b(as\s+)?(duas|2)\s+(mensagens|msgs|listas)\s+(vieram|chegaram|s[ãa]o|est[ãa]o)\s+iguais`,
  ].join('|'),
  'i',
)

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
