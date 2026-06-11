/**
 * Detector de intent de ADIÇÃO (Luciana 2026-06-10).
 *
 * Bug observado: Luciana registrou 1 fatia de bolo de milho (lanche), depois
 * mandou outra foto. Sistema perguntou "mesma fatia ou segunda?", ela disse
 * "Segunda fatia". LLM corretamente chamou registra_refeicao com replace=false
 * (queria SOMAR). MAS a defesa anti-erro `objectiveCorrectionEvidence` detectou
 * 100% overlap de food_name (bolo→bolo) em <30min e auto-aplicou replace=true,
 * apagando o 1º bolo. Resultado: 2 fatias comidas, 1 registrada.
 *
 * Este detector roda ANTES da auto-aplicação de replace=true e CANCELA quando
 * detecta intent CLARO de adição nas mensagens recentes do paciente.
 *
 * Gatilhos de adição:
 *  - "segundo/segunda pedaço/fatia/copo/etc"
 *  - "outro/outra X" (com X = mesmo alimento)
 *  - "mais um/uma"
 *  - "+ 1", "+1"
 *  - "comi mais"
 *  - "tem mais"
 *  - "acrescent" (acrescenta, acrescentar)
 *  - "dobr" (dobrei, dobrar)
 *  - "repet" (repeti)
 *  - "também comi"
 *  - "outro igual"
 */

const ADDITION_TRIGGERS = new RegExp(
  [
    String.raw`\bsegund[oa]\s+(pedaço|fatia|copo|porção|porcao|colher|prato|unidade|x[ií]cara|xicara|taça|taca|garrafa|lata|bola|p[ãa]ozinho|p[ãa]o|biscoito|barr[ai])\b`,
    String.raw`\boutr[oa]\s+(pedaço|fatia|copo|porção|porcao|colher|prato|unidade|x[ií]cara|xicara|taça|taca|garrafa|lata|bola|p[ãa]ozinho|p[ãa]o|biscoito|barr[ai])\b`,
    String.raw`\boutr[oa]\s+igual\b`,
    String.raw`\bmais\s+(um|uma|dois|duas|tr[êe]s|quatro|cinco)\b`,
    String.raw`(\+\s*1|\+1)`,
    String.raw`\bcomi\s+mais\b`,
    String.raw`\btem\s+mais\b`,
    String.raw`\bacrescent`,
    String.raw`\b(dobr[ei]|dobrei|dobrou|dobramos)\b`,
    String.raw`\brepeti(u|ram|mos)?\b`,
    String.raw`\brepete\b`,
    String.raw`\btamb[ée]m\s+comi\b`,
    String.raw`\btamb[ée]m\s+tomei\b`,
    String.raw`\bagora\s+(comi|tomei|peguei)\s+(outr[oa]|mais)\b`,
    String.raw`\bvou\s+(comer|tomar)\s+mais\s+(um|uma)\b`,
  ].join('|'),
  'i',
)

/**
 * Verifica se há intent de adição no texto. Retorna o gatilho que casou
 * (pra log) ou null.
 */
export function detectAdditionIntent(text: string): string | null {
  if (!text || text.trim().length === 0) return null
  const m = text.match(ADDITION_TRIGGERS)
  return m ? m[0] : null
}

/**
 * Roda detector em uma janela de mensagens recentes (texto agregado).
 * Retorna o gatilho ou null.
 */
export function detectAdditionInRecentMessages(
  recentMessages: Array<{ role: string; content: string }>,
  windowCount = 4,
): string | null {
  const userMsgs = recentMessages.filter((m) => m.role === 'user').slice(-windowCount)
  for (const m of userMsgs) {
    const hit = detectAdditionIntent(m.content)
    if (hit) return hit
  }
  return null
}
