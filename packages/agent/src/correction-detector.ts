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
  /\bcorrigir\b/i, // "Favor corrigir" (Luciana 2026-05-15) — infinitivo
  /\bcorrigid[oa]\b/i, // "já foi corrigido" etc
  /\bcorre[çc][ãa]o\b/i,
  // Linguagem de REMOÇÃO de item — implica correção (paciente quer tirar item):
  /\btira\s+(?:o|a|os|as)?\s*\w+/i, // "tira o bacon"
  /\bsem\s+(?:o|a|os|as)\s+\w+/i, // "sem o bacon"
  /\bnão\s+(?:tem|tinha|teve)\s+\w+/i, // "não tem bacon"
  /\besquec[ea]\s+(?:o|a|os|as)?\s*\w+/i, // "esquece o queijo"
  /\bremov[ea]r?\s+(?:o|a|os|as)?\s*\w+/i, // "remove o pão"
  /\bdelet[ae]r?\s+/i, // "deleta", "deletar"
  /\bapag[ae]r?\s+/i, // "apaga o item"
  /\bexcluir?\s+/i, // "exclui isso"
  /\bretir[ae]r?\s+/i, // "retira o bacon"
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
  // Formas naturais de correção que a Amanda usou (2026-05-15) e o detector falhou:
  /\b[ée]\s+\w+(?:\s+\w+)?,?\s+n[ãa]o\b/i, // "é cuscuz, não farofa" / "é X não Y"
  /\bn[ãa]o\s+[ée]\s+\w+/i, // "não é X"
  /\bapenas\s+\d+\b/i, // "Apenas 1 unidade nessa foto"
  /\bs[óo]\s+\d+\s*(?:unidade|fatia|colher|pedaço|p[ãa]o)/i, // "só 1 unidade"
  /\bno\s+lugar\s+(?:do|da|de)\b/i, // "no lugar do açúcar"
  /\bo\s+\w+\s+[ée]\s+\w+\b/i, // "o pão é francês" (afirmação corretiva)
  // RESET MASSA — paciente quer descartar/recomeçar refeições do dia
  // (Luciana 2026-05-12: "Preciso resetar o dia todo hoje" + "favor
  // desconsiderar" — 8 replace_blocked porque detector verbal não pegava)
  /\bdesconsider(?:a|e|ar|ando)\b/i,
  /\bresete?(?:a|ar|i|e)?\b/i,
  /\brecome[çc][ae]r?\b/i,
  /\brefaz(?:er|emos)?\b/i,
  /\bcome[çc]ar\s+(?:de\s+)?novo\b/i,
  /\bdescart[ae]r?\b/i,
  /\bjog(?:a|ar)\s+fora\b/i,
  /\bapag(?:a|ar|ou)\s+(?:tudo|todas?|essas?|aqueles?|aquilo)\b/i,
  /\bzer(?:a|ar|ado)\s+(?:o\s+)?dia\b/i,
  /\bignor[ae]r?\s+(?:essas?|aqueles?|aquilo)\b/i,
  /\best[áa]\s+errado\b/i, // "está errado" — afirma erro
  /\best[áa]o?\s+errad[oa]s?\b/i, // "estão errados"
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
  // Removal language
  /\bno\s+\w+\s*(?:in|on|inside)/i, // "no bacon in"
  /\btake\s+(?:out|off)\s+/i, // "take out the bacon"
  /\bwithout\s+(?:the|any)?\s*\w+/i, // "without bacon"
  /\bskip\s+(?:the)?\s*\w+/i, // "skip the bacon"
  /\bthere'?s\s+no\s+\w+/i, // "there's no bacon"
  /\bisn'?t\s+\w+/i, // "isn't bacon"
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
  // Removal language ES
  /\bsin\s+(?:el|la|los|las)?\s*\w+/i, // "sin el bacon"
  /\bno\s+(?:hay|tiene)\s+\w+/i, // "no hay bacon"
  /\bsac[ae]r?\s+(?:el|la)?\s*\w+/i, // "saca el bacon"
  /\belimina[r]?\s+/i, // "elimina"
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
