/**
 * Detector de PHANTOM ITEMS (Amanda 2026-06-11).
 *
 * Bug observado: Amanda mandou foto do café com banana no canto. Agente
 * perguntou se banana fazia parte. Amanda respondeu "Não faz parte". Logo
 * em seguida, agente propôs registrar "vinho branco (150 ml) — 225 kcal"
 * para o ALMOÇO. Amanda nunca mencionou vinho. Foto era de café da manhã.
 * O vinho era resíduo de cross-day contamination — Amanda tomou vinho 3
 * dias atrás (08/06), e o LLM Sonnet, processando o histórico, alucinou
 * o item.
 *
 * Defesa: ANTES de aceitar items propostos pelo LLM em registra_refeicao,
 * checar se cada item aparece (fuzzy) nas mensagens recentes do PACIENTE
 * OU em propostas/cards recentes do AGENTE no mesmo turno (vision pode ter
 * identificado da foto sem o paciente dizer explicitamente). Items que
 * NÃO aparecem em LUGAR NENHUM são phantom.
 *
 * Critério de ação: phantom detectado E paciente acabou de DENEGAR algo
 * ("não", "não faz parte", "esqueça", "não é") → bloquear pra retry.
 */

const DENIAL_PATTERN = new RegExp(
  [
    String.raw`\bn[ãa]o\s+faz\s+parte\b`,
    String.raw`\bn[ãa]o\s+[ée]\s+isso\b`,
    String.raw`\bn[ãa]o\s+[ée]\s+esse\b`,
    String.raw`(?:^|\s)esque[çc]a(?=\s|$|[\.!?,;])`,
    String.raw`(?:^|\s)esquece(?=\s|$|[\.!?,;])`,
    String.raw`\bn[ãa]o\s+era\s+isso\b`,
    String.raw`\b(ignor[ae]|ignora|ignore)\b`,
    String.raw`\bsem\s+(isso|esse|essa)\b`,
    String.raw`\bnenhum\s+(deles|disso)\b`,
    // Negação isolada curta (uma palavra ou frase curta)
    String.raw`^\s*n[ãa]o\s*[\.!]?\s*$`,
  ].join('|'),
  'i',
)

function normalize(s: string): string {
  return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
}

/**
 * Verifica se um nome de alimento aparece (fuzzy) em qualquer um dos textos
 * de referência. Match positivo se a palavra principal do alimento (>=4 chars)
 * aparece no texto.
 */
function nameAppearsInTexts(foodName: string, texts: string[]): boolean {
  const n = normalize(foodName)
  // Palavras principais do nome (>= 4 chars cada)
  const words = n.split(/\s+/).filter((w) => w.length >= 4)
  if (words.length === 0) return false
  const corpus = texts.map(normalize).join(' ')
  // Pelo menos UMA palavra principal precisa aparecer no corpus
  return words.some((w) => corpus.includes(w))
}

export interface PhantomCheckInput {
  /** Items que o LLM propôs registrar. */
  proposedItems: Array<{ food_name: string }>
  /** Últimas mensagens do paciente (mais recente por último). */
  recentUserMessages: string[]
  /** Últimos textos do agente no turno (cards, propostas anteriores) —
   * podem conter items identificados via vision sem o paciente ter falado. */
  recentAgentTexts?: string[]
}

export interface PhantomCheckResult {
  /** Items que não aparecem em lugar nenhum (suspeitos). */
  phantomItems: string[]
  /** Última msg do paciente era uma negação? */
  denialDetected: boolean
  /** Gatilho da negação (regex match) ou null. */
  denialTrigger: string | null
  /** Deve bloquear o tool call? (phantom + denial) */
  shouldBlock: boolean
}

/**
 * Checa se há items "fantasma" entre os propostos. Phantom = não aparecem
 * em nenhuma msg recente do paciente nem em proposta/card recente do agente.
 */
export function detectPhantomItems(input: PhantomCheckInput): PhantomCheckResult {
  const userTexts = input.recentUserMessages
  const agentTexts = input.recentAgentTexts ?? []
  const phantomItems: string[] = []
  for (const item of input.proposedItems) {
    const inUser = nameAppearsInTexts(item.food_name, userTexts)
    const inAgent = nameAppearsInTexts(item.food_name, agentTexts)
    if (!inUser && !inAgent) {
      phantomItems.push(item.food_name)
    }
  }
  const lastUserMsg = userTexts[userTexts.length - 1] ?? ''
  const denialMatch = lastUserMsg.match(DENIAL_PATTERN)
  const denialDetected = !!denialMatch
  const denialTrigger = denialMatch ? denialMatch[0] : null
  // Bloqueia QUANDO: tem phantom E denial recente. Sinal claro de alucinação
  // após o paciente ter dito "não" pra algo.
  const shouldBlock = phantomItems.length > 0 && denialDetected
  return {
    phantomItems,
    denialDetected,
    denialTrigger,
    shouldBlock,
  }
}
