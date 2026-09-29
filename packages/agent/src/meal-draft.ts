/**
 * Candidatos de refeição para revisão no app (C1 da beta funcional).
 *
 * Texto livre, transcrição de áudio ou resultado do Vision viram CANDIDATOS:
 * nome + quantidade com a base explícita. Nenhuma caloria é calculada aqui e
 * nenhuma grama é inventada: o que não foi dito, visto ou coberto por uma
 * porção de referência já existente fica `missing` e o paciente informa.
 */
import { createHash } from 'node:crypto'

export type MealDraftQuantityBasis = 'stated' | 'visual_estimate' | 'portion_reference' | 'missing'

export type MealDraftReviewReason =
  | 'low_confidence'
  | 'estimated_quantity'
  | 'missing_quantity'
  | 'ambiguous'

export interface MealDraftCandidate {
  candidate_id: string
  name: string
  quantity_g: number | null
  quantity_basis: MealDraftQuantityBasis
  count: number | null
  unit_label: string | null
  confidence: number | null
  needs_review: boolean
  review_reason: MealDraftReviewReason | null
}

/** Item bruto antes da resolução de quantidade (parser ou extrator). */
export interface MealDraftRawItem {
  name: string
  count?: number | null
  unit?: string | null
  grams_stated?: number | null
  /** O trecho não pôde ser lido com segurança; o paciente confere o nome. */
  ambiguous?: boolean
}

export const MEAL_DRAFT_MAX_ITEMS = 30
export const MEAL_DRAFT_MAX_TEXT_LENGTH = 2000
const MAX_QUANTITY_G = 9999
const MAX_NAME_LENGTH = 160

function normalize(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

function round1(value: number): number {
  return Math.round(value * 10) / 10
}

/**
 * Pesos unitários de referência. São EXATAMENTE os números que `naturalUnit`
 * já usa para exibir unidades (ovo 50 g, pão francês 50 g, pão de queijo 30 g,
 * fatia 15 g, banana 100 g, maçã 150 g); nenhum valor novo.
 */
const UNIT_FOOD_REFERENCES: Array<{ pattern: RegExp; grams: number }> = [
  { pattern: /\bovos?\b/, grams: 50 },
  { pattern: /\bpao frances\b|\bpaes franceses\b|\bpaozinho\b/, grams: 50 },
  { pattern: /\bpao de queijo\b|\bpaes de queijo\b/, grams: 30 },
  { pattern: /\bbananas?\b/, grams: 100 },
  { pattern: /\bmacas?\b/, grams: 150 },
]
const SLICE_GRAMS = 15
const SLICE_UNIT = /^fatias?$/
const PIECE_UNIT = /^(unidades?|un|und)$/

/** Gramas de UMA unidade do alimento, ou null quando não há referência. */
export function portionReferenceGrams(foodName: string, unit: string | null): number | null {
  const food = normalize(foodName)
  const normalizedUnit = unit == null ? null : normalize(unit)
  if (normalizedUnit != null && SLICE_UNIT.test(normalizedUnit)) return SLICE_GRAMS
  if (normalizedUnit != null && !PIECE_UNIT.test(normalizedUnit)) return null
  // "ovo de codorna", "ovo de páscoa" etc. não são o ovo de 50 g.
  if (/\bovos? de\b/.test(food) && !/\bovos? de galinha\b/.test(food)) return null
  return UNIT_FOOD_REFERENCES.find((rule) => rule.pattern.test(food))?.grams ?? null
}

// Mesmo critério de líquido que `naturalUnit` usa para exibir ml (1 ml ≈ 1 g).
const LIQUID_FOOD =
  /\bleite\b|\bsuco\b|\bcafe\b|chocolate quente|cappuc|capuc|achocolatad|vitamina|smoothie|\bcha\b|cerveja|vinho|refri|coca|\bagua\b|whey|caipirinha|cachaca|whisky|gin|champ/
const POWDER_FOOD = /em po|soluvel|instantane|em flocos|em folhas|granulad/

function isLiquidFood(foodName: string): boolean {
  const food = normalize(foodName)
  return LIQUID_FOOD.test(food) && !POWDER_FOOD.test(food)
}

function candidateId(index: number, name: string): string {
  const digest = createHash('sha256').update(`${index}:${normalize(name)}`).digest('hex')
  return `c${index + 1}-${digest.slice(0, 8)}`
}

function cleanName(value: string): string {
  return value
    .replace(/\s+/g, ' ')
    .replace(/^[\s\-–:,.;]+|[\s\-–:,.;]+$/g, '')
    .replace(/^(de|do|da|dos|das|of)\s+/i, '')
    .trim()
    .slice(0, MAX_NAME_LENGTH)
}

function validGrams(value: number | null | undefined): number | null {
  if (value == null || !Number.isFinite(value) || value <= 0 || value > MAX_QUANTITY_G) return null
  return value
}

/** Resolve a quantidade de um item bruto sem inventar gramas. */
export function resolveDraftItem(raw: MealDraftRawItem, index: number): MealDraftCandidate | null {
  const name = cleanName(raw.name)
  if (!name) return null
  const stated = validGrams(raw.grams_stated)
  const unit = raw.unit ? normalize(raw.unit) : null
  // Contagem de unidades até 100; volume (ml) até 5000.
  const countLimit = unit === 'ml' ? 5000 : unit === 'l' || unit === 'litro' ? 5 : 100
  const count =
    raw.count != null && Number.isFinite(raw.count) && raw.count > 0 && raw.count <= countLimit
      ? raw.count
      : null
  const base = { candidate_id: candidateId(index, name), name, confidence: null }

  if (stated != null) {
    return {
      ...base,
      quantity_g: stated,
      quantity_basis: 'stated',
      count,
      unit_label: count != null ? (unit ?? 'unidade') : null,
      needs_review: false,
      review_reason: null,
    }
  }

  if (count != null) {
    const millilitres = unit === 'ml' ? count : unit === 'l' || unit === 'litro' ? count * 1000 : null
    if (millilitres != null) {
      const grams = isLiquidFood(name) ? validGrams(millilitres) : null
      return {
        ...base,
        quantity_g: grams,
        quantity_basis: grams != null ? 'portion_reference' : 'missing',
        count: millilitres,
        unit_label: 'ml',
        needs_review: true,
        review_reason: grams != null ? 'estimated_quantity' : 'missing_quantity',
      }
    }
    const perUnit = portionReferenceGrams(name, unit)
    const grams = perUnit != null ? validGrams(round1(perUnit * count)) : null
    return {
      ...base,
      quantity_g: grams,
      quantity_basis: grams != null ? 'portion_reference' : 'missing',
      count,
      unit_label: unit ?? 'unidade',
      needs_review: true,
      review_reason: grams != null ? 'estimated_quantity' : 'missing_quantity',
    }
  }

  return {
    ...base,
    quantity_g: null,
    quantity_basis: 'missing',
    count: null,
    unit_label: null,
    needs_review: true,
    review_reason: raw.ambiguous ? 'ambiguous' : 'missing_quantity',
  }
}

const NUMBER = String.raw`\d+(?:[.,]\d+)?`
const GRAMS = new RegExp(
  String.raw`(${NUMBER})\s*(kg|quilos?|g|gr|grs|gramas?|grams?)(?![\p{L}\d])`,
  'iu',
)
const COUNT_WORDS: Record<string, number> = {
  meio: 0.5,
  meia: 0.5,
  um: 1,
  uma: 1,
  dois: 2,
  duas: 2,
  tres: 3,
  quatro: 4,
  cinco: 5,
  seis: 6,
  sete: 7,
  oito: 8,
  nove: 9,
  dez: 10,
}
const LEAD_IN_WORDS = new Set([
  'comi',
  'tomei',
  'bebi',
  'almocei',
  'jantei',
  'lanchei',
  'consumi',
  'ingeri',
  'mais',
  'tambem',
  'depois',
  'hoje',
  'e',
  'com',
])
const COUNT_UNIT = /^(ml|l|litros?|unidades?|un|und|fatias?)$/
const NUMBER_WITH_UNIT = new RegExp(String.raw`^(${NUMBER})(ml|l|un|und)$`)

function parseNumber(text: string): number | null {
  const word = COUNT_WORDS[normalize(text)]
  if (word != null) return word
  if (!/^\d+(?:[.,]\d+)?$/.test(text)) return null
  const value = Number(text.replace(',', '.'))
  return Number.isFinite(value) ? value : null
}

/** Quebra o texto em trechos de um alimento, sem cortar decimais ("86,5 g"). */
export function splitMealText(text: string): string[] {
  return text
    .split(/\r?\n|;|(?<!\d),|,(?!\d)|\s+e\s+(?=\S)/u)
    .map((segment) => segment.trim())
    .filter(Boolean)
}

// Spoken/written introduction before a quantity (audit 2026-09-29: "No almoço
// eu comi 150 gramas de arroz"): only meal/time words, then an eating verb.
const EATING_VERBS = new Set(['comi', 'tomei', 'bebi', 'almocei', 'jantei', 'lanchei', 'consumi', 'ingeri'])
const INTRO_WORDS = new Set([
  'no', 'na', 'nos', 'nas', 'o', 'a', 'em', 'de', 'do', 'da', 'pelo', 'pela', 'eu', 'e', 'hoje', 'ontem', 'agora',
  'depois', 'mais', 'tambem', 'cafe', 'manha', 'almoco', 'jantar', 'janta', 'lanche', 'ceia', 'tarde', 'noite',
])

function withoutLeadIn(prefix: string): string {
  const words = prefix.trim().split(/\s+/).filter(Boolean)
  const plain = words.map((word) => normalize(word).replace(/[^a-z]/g, ''))
  let verb = -1
  for (let i = plain.length - 1; i >= 0; i -= 1) {
    if (EATING_VERBS.has(plain[i] ?? '')) {
      verb = i
      break
    }
  }
  if (verb < 0 || !plain.slice(0, verb).every((word) => INTRO_WORDS.has(word))) return prefix
  return words.slice(verb + 1).join(' ')
}

/** "alimento + gramas" (mesmas regras do parser do app): declarado, exato. */
export function parseStatedGrams(segment: string): MealDraftRawItem | null {
  const match = GRAMS.exec(segment)
  if (!match) return null
  const value = parseNumber(match[1] ?? '')
  if (value == null) return null
  const kilograms = /^(kg|quilos?)$/i.test(match[2] ?? '')
  const grams = validGrams(kilograms ? value * 1000 : value)
  const name = cleanName(
    `${withoutLeadIn(segment.slice(0, match.index))} ${segment.slice(match.index + match[0].length)}`,
  )
  if (grams == null || !name) return null
  return { name, grams_stated: grams }
}

/** "2 ovos", "1 fatia de queijo", "250 ml de leite", "três bananas", "banana". */
export function parseCountedSegment(segment: string): MealDraftRawItem | null {
  // Palavra a palavra: número e unidade são lidos sem acento, o nome do
  // alimento fica como o paciente escreveu.
  const allWords = segment.trim().split(/\s+/).filter(Boolean)
  // "comi 2 ovos", "tomei um café": o que vem antes da quantidade e é só
  // introdução sai; qualquer outra palavra ali deixa o trecho ambíguo.
  let lead = 0
  while (lead < allWords.length - 1 && LEAD_IN_WORDS.has(normalize(allWords[lead] ?? ''))) {
    lead += 1
  }
  const words = allWords.slice(lead)
  const first = normalize(words[0] ?? '')
  const glued = NUMBER_WITH_UNIT.exec(first)
  const count = glued ? parseNumber(glued[1] ?? '') : parseNumber(first)
  if (count != null && words.length > 1) {
    let next = 1
    let unit: string | null = glued ? (glued[2] ?? null) : null
    if (unit == null && COUNT_UNIT.test(normalize(words[next] ?? ''))) {
      unit = normalize(words[next] ?? '')
      next += 1
    }
    const name = cleanName(words.slice(next).join(' '))
    if (name && !/\d/.test(name)) return { name, count, unit }
  }
  const name = cleanName(words.join(' '))
  if (!name) return null
  // Número no meio do trecho sem leitura segura: o paciente vê o trecho como
  // escreveu e corrige; nada é descartado em silêncio nem adivinhado.
  if (/\d/.test(name)) return { name, ambiguous: true }
  return { name }
}

export interface MealTextDraft {
  items: MealDraftCandidate[]
  /** Trechos que o parser determinístico não reconheceu como "alimento + gramas". */
  unrecognized: string[]
}

/** Passo 1: só o que foi dito com gramas. O resto fica para o passo 2. */
export function draftFromStatedText(text: string): { raw: MealDraftRawItem[]; rest: string[] } {
  const raw: MealDraftRawItem[] = []
  const rest: string[] = []
  for (const segment of splitMealText(text)) {
    const stated = parseStatedGrams(segment)
    if (stated) raw.push(stated)
    else rest.push(segment)
  }
  return { raw, rest }
}

function appearsIn(text: string, value: number, unitPattern: string): boolean {
  const normalized = normalize(text)
  const forms = [String(value), String(value).replace('.', ',')]
  return forms.some((form) =>
    new RegExp(String.raw`(?<![\d.,])${form.replace('.', String.raw`\.`)}\s*${unitPattern}`, 'u').test(
      normalized,
    ),
  )
}

/**
 * Saída de um extrator (LLM) é dado não confiável: gramas e contagens só valem
 * se estiverem no texto do paciente; nome precisa ter ao menos uma palavra do
 * texto. O que não passar perde a quantidade ou é descartado.
 */
export function sanitizeExtractedItems(
  sourceText: string,
  extracted: unknown,
): MealDraftRawItem[] {
  if (!Array.isArray(extracted)) return []
  const source = normalize(sourceText)
  const result: MealDraftRawItem[] = []
  for (const value of extracted.slice(0, MEAL_DRAFT_MAX_ITEMS)) {
    if (typeof value !== 'object' || value === null) continue
    const item = value as Record<string, unknown>
    const name = typeof item.name === 'string' ? cleanName(item.name) : ''
    if (!name) continue
    const words = normalize(name)
      .split(' ')
      .filter((word) => word.length >= 3)
    if (!words.some((word) => source.includes(word.slice(0, Math.max(3, word.length - 2))))) {
      continue
    }
    const grams =
      typeof item.grams_stated === 'number' &&
      validGrams(item.grams_stated) != null &&
      (appearsIn(sourceText, item.grams_stated, String.raw`(g|gr|grs|gramas?|grams?)(?![a-z\d])`) ||
        appearsIn(sourceText, item.grams_stated / 1000, String.raw`(kg|quilos?)(?![a-z\d])`))
        ? item.grams_stated
        : null
    const countValue = typeof item.count === 'number' ? item.count : null
    const countWord = Object.entries(COUNT_WORDS).find(([, number]) => number === countValue)?.[0]
    const count =
      countValue != null &&
      (appearsIn(sourceText, countValue, '') ||
        (countWord != null && new RegExp(String.raw`\b${countWord}\b`, 'u').test(source)) ||
        (countValue === 0.5 && /\bmei[oa]\b/u.test(source)) ||
        (countValue === 1 && /\bum(a)?\b/u.test(source)))
        ? countValue
        : null
    const unit = typeof item.unit === 'string' && item.unit.trim() ? item.unit.trim() : null
    result.push({ name, count, unit: count != null ? unit : null, grams_stated: grams })
  }
  return result
}

export function buildDraftCandidates(raw: MealDraftRawItem[]): MealDraftCandidate[] {
  return raw
    .slice(0, MEAL_DRAFT_MAX_ITEMS)
    .map((item, index) => resolveDraftItem(item, index))
    .filter((item): item is MealDraftCandidate => item !== null)
}

export interface VisionMealItemLike {
  name?: unknown
  quantity_g_estimate?: unknown
  confidence?: unknown
}

/**
 * Foto: o Vision já identificou; aqui só se mapeia. Estimativa visual nunca
 * vira dado exato, quantidade ilegível (0) fica `missing`, e confiança abaixo
 * do limiar pede revisão. "2x ovo frito" mostra a contagem; as gramas
 * continuam as do Vision.
 */
export function draftFromVisionItems(
  items: unknown,
  confidenceThreshold: number,
): MealDraftCandidate[] {
  if (!Array.isArray(items)) return []
  const candidates: MealDraftCandidate[] = []
  for (const value of items.slice(0, MEAL_DRAFT_MAX_ITEMS)) {
    if (typeof value !== 'object' || value === null) continue
    const item = value as VisionMealItemLike
    const rawName = typeof item.name === 'string' ? item.name : ''
    const repeated = /^\s*(\d{1,2})\s*x\s+(.+)$/i.exec(rawName)
    const name = cleanName(repeated ? (repeated[2] ?? '') : rawName)
    if (!name) continue
    const grams = validGrams(typeof item.quantity_g_estimate === 'number' ? item.quantity_g_estimate : null)
    const confidence =
      typeof item.confidence === 'number' && Number.isFinite(item.confidence)
        ? Math.min(1, Math.max(0, item.confidence))
        : null
    const lowConfidence = confidence == null || confidence < confidenceThreshold
    candidates.push({
      candidate_id: candidateId(candidates.length, name),
      name,
      quantity_g: grams,
      quantity_basis: grams != null ? 'visual_estimate' : 'missing',
      count: repeated ? Number(repeated[1]) : null,
      unit_label: repeated ? 'unidade' : null,
      confidence,
      needs_review: true,
      review_reason:
        grams == null ? 'missing_quantity' : lowConfidence ? 'low_confidence' : 'estimated_quantity',
    })
  }
  return candidates
}

/**
 * O rótulo só vem associado quando a associação é inequívoca: um único
 * candidato, ou exatamente um candidato cujo nome compartilha palavra com o
 * produto do rótulo. Caso contrário o paciente associa explicitamente.
 */
export function labelCandidateId(
  candidates: MealDraftCandidate[],
  productName: string | null,
): string | null {
  if (candidates.length === 1) return candidates[0]?.candidate_id ?? null
  if (!productName) return null
  const productWords = normalize(productName)
    .split(' ')
    .filter((word) => word.length >= 4)
  const matching = candidates.filter((candidate) => {
    const name = normalize(candidate.name)
    return productWords.some((word) => name.includes(word))
  })
  return matching.length === 1 ? (matching[0]?.candidate_id ?? null) : null
}
