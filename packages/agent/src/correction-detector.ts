/**
 * Detector determinístico de "intenção de correção" em mensagens do paciente.
 *
 * Usado por registra_refeicao pra validar `replace=true`. Sem palavra-chave
 * de correção nas últimas msgs do paciente, replace é REJEITADO silenciosamente
 * — vira INSERT normal. Bug histórico (Roberto): foto de café da manhã foi
 * classificada como correção do jantar de ontem, replace=true sumiu com dado.
 *
 * Cobre PT-BR, EN e ES (idiomas suportados). Match case-insensitive, com
 * boundary de palavra pra evitar falso positivo (ex: "trocar" ≠ "troca").
 */

const CORRECTION_KEYWORDS_PT: RegExp[] = [
  /\bcorrige\b/i,
  /\bcorrij[ao]\b/i,
  /\bcorre[çc][ãa]o\b/i,
  /\bna verdade\b/i,
  /\berrei\b/i,
  /\b(?:errado|errada)\b/i,
  /\btroca\b/i,
  /\btrocar\b/i,
  /\batualiza\b/i,
  /\bajusta\b/i,
  /\bajustar\b/i,
  /\bera\s+\w+(?:\s+\w+)?\s+n[ãa]o\b/i, // "era X não Y"
  /\bn[ãa]o\s+(?:era|foi|é)(?=\s|$)/i, // "não era", "não foi", "não é" — sem \b após é (não-ASCII)
  /\besqueci\b/i,
  /\bsubstitu[ai]\b/i,
  /\bdeleta\b/i,
  /\bremove\b/i,
  /\b[ée]\s+leite\s+com\b/i, // "é leite com whey" (correção do tipo "X é Y")
]

const CORRECTION_KEYWORDS_EN: RegExp[] = [
  /\bcorrect(?:ion)?\b/i,
  /\bactually\b/i,
  /\bmistake\b/i,
  /\bmistakenly\b/i,
  /\bwrong\b/i,
  /\bfix(?:ed)?\b/i,
  /\breplace\b/i,
  /\bupdate\b/i,
  /\bchange\s+(?:to|that)\b/i,
  /\bit'?s\s+\w+\s+not\b/i, // "it's X not Y"
  /\bnot\s+\w+,?\s+(?:but|it'?s)\b/i, // "not X, but Y"
  /\bI\s+meant\b/i,
  /\bsorry\b/i,
  /\bforgot\b/i,
  /\bremove\b/i,
  /\bdelete\b/i,
]

const CORRECTION_KEYWORDS_ES: RegExp[] = [
  /\bcorrige\b/i,
  /\bcorrecci[óo]n\b/i,
  /\ben\s+realidad\b/i,
  /\bme\s+equivoqu[ée](?=\s|$|[.,!?])/i,
  /\bequivocad[oa]\b/i,
  /\bcambia\b/i,
  /\bactualiza\b/i,
  /\bajusta\b/i,
  /\bera\s+\w+\s+no\b/i, // "era X no Y"
  /\bno\s+(?:era|fue|es)\b/i,
  /\bme\s+olvid[ée]\b/i,
  /\bquita\b/i,
  /\bborra\b/i,
]

const ALL_PATTERNS: RegExp[] = [
  ...CORRECTION_KEYWORDS_PT,
  ...CORRECTION_KEYWORDS_EN,
  ...CORRECTION_KEYWORDS_ES,
]

/**
 * Checa se alguma das mensagens recentes do paciente tem palavra de correção.
 * Retorna a palavra detectada (pra log) ou null.
 */
export function detectCorrectionIntent(messages: string[]): string | null {
  for (const msg of messages) {
    if (!msg) continue
    for (const pattern of ALL_PATTERNS) {
      const match = msg.match(pattern)
      if (match) return match[0]
    }
  }
  return null
}
