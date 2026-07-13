const KCAL_VALUE = /\d{1,3}(?:\.\d{3})+|\d+(?:[.,]\d+)?/
const KCAL_CLAIM = new RegExp(`(?:${KCAL_VALUE.source})\\s*(?:k?cal(?:orias?)?)\\b`, 'i')
const QUANTITY_IN_PARENS =
  /\([^)]*\d+(?:[.,]\d+)?\s*(?:kg|g|ml|litros?|l|unidades?|unid\.?|p(?:ão|ães|ao|aes)|fatias?|colheres?|copos?|xícaras?|xicaras?|bolas?|porções?|porcoes?|scoops?)[^)]*\)/i
const BULLET_PREFIX = /^\s*[•·\-*]\s+/
const AGGREGATE_PREFIX =
  /^(?:total(?:\s+da\s+refeicao)?|consumid[oa]|restam?|restante|saldo|meta|proteina|carboidratos?|gorduras?|exercicio|bloco\s*7700)\s*:/i
const MACRO_ONLY =
  /^\s*\d+(?:[.,]\d+)?\s*g\s*(?:de\s+)?(?:proteinas?|protein|carboidratos?|carbs?|gorduras?|fat|fibras?|fiber)\b/i

function normalizeLine(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .replace(/^[^a-z0-9]+/, '')
}

export function isAggregateNutritionText(text: string): boolean {
  return AGGREGATE_PREFIX.test(normalizeLine(text))
}

function isStructuredNutritionItem(text: string): boolean {
  if (!KCAL_CLAIM.test(text) || !QUANTITY_IN_PARENS.test(text)) return false
  return (
    BULLET_PREFIX.test(text) ||
    /[—–-]\s*\d/.test(text) ||
    /:\s*\d/.test(text) ||
    /\|\s*\d/.test(text)
  )
}

interface NutritionPart {
  raw: string
  kind: 'aggregate' | 'item' | 'macro' | 'other'
}

export interface NutritionContextClassification {
  patientAssertions: string
  hasStructuredSummary: boolean
  removedPartCount: number
}

/**
 * Separates server-generated nutrition cards from free text written by the
 * patient. A card is identified by nutrition rows plus an aggregate, or by at
 * least two formatted item rows. Plain assertions such as "torta 80 kcal" are
 * intentionally preserved.
 */
export function classifyNutritionContext(text: string): NutritionContextClassification {
  const parts: NutritionPart[] = text
    .split(/\r?\n/)
    .flatMap((line) => line.split('|'))
    .map((raw) => {
      const trimmed = raw.trim()
      if (isAggregateNutritionText(trimmed)) return { raw: trimmed, kind: 'aggregate' as const }
      if (isStructuredNutritionItem(trimmed)) return { raw: trimmed, kind: 'item' as const }
      if (MACRO_ONLY.test(normalizeLine(trimmed))) return { raw: trimmed, kind: 'macro' as const }
      return { raw: trimmed, kind: 'other' as const }
    })

  const itemCount = parts.filter((part) => part.kind === 'item').length
  const aggregateCount = parts.filter((part) => part.kind === 'aggregate').length
  const hasStructuredSummary = itemCount >= 2 || (itemCount >= 1 && aggregateCount >= 1)

  let removedPartCount = 0
  const patientAssertions = parts
    .filter((part) => {
      const remove =
        part.kind === 'aggregate' ||
        (hasStructuredSummary && (part.kind === 'item' || part.kind === 'macro'))
      if (remove) removedPartCount += 1
      return !remove && part.raw.length > 0
    })
    .map((part) => part.raw)
    .join('\n')

  return { patientAssertions, hasStructuredSummary, removedPartCount }
}

export function looksLikeStructuredNutritionSummary(text: string): boolean {
  return classifyNutritionContext(text).hasStructuredSummary
}
