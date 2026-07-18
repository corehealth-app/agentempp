/**
 * Pipeline de processamento de refeição.
 *
 * Recebe lista de itens (nome + quantidade) → faz match na food_db (TACO) →
 * calcula macros determinísticamente.
 *
 * ADR-006: cálculos saem da TACO, não do LLM.
 */
import type { ServiceClient } from '@mpp/db'
import { classifyNutritionContext, isAggregateNutritionText } from './nutrition-context.js'
import { hasImpossibleKcalDensity } from './nutrition-invariants.js'

export interface MealItemInput {
  food_name: string
  quantity_g: number
  /**
   * Nutrition already resolved and displayed in a server-created pending.
   * This field is intentionally absent from the public tool schema: only the
   * deterministic confirmation handler may provide it.
   */
  approved_nutrition?: {
    source?: MealNutritionSource
    food_db_id?: number | null
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }
  /**
   * Kcal informado EXPLICITAMENTE pelo paciente no texto ("rap 10 : 70 calorias").
   * Quando presente e ≥ 0, OVERRIDE o kcal do TACO/histórico/estimativa.
   * Os macros P/C/F são re-escalonados proporcionalmente à kcal original (mantém
   * o RATIO da fonte — TACO ou estimateMacros).
   *
   * Bug Luciana 2026-06-16: paciente repetiu "rap 10 : 70 calorias" 4× e o
   * sistema gravou wrap 140 kcal todas as vezes porque o pipeline ignorava o
   * número de kcal do texto e usava só o lookup do food_db.
   */
  user_kcal?: number
}

const KCAL_VALUE_RE = /(\d{1,3}(?:\.\d{3})+|\d+(?:[.,]\d+)?)\s*(?:k?cal(?:orias?)?)\b/gi

function parseLocalizedNutritionNumber(raw: string): number {
  if (/^\d{1,3}(?:\.\d{3})+$/.test(raw)) return Number(raw.replace(/\./g, ''))
  return Number(raw.replace(',', '.'))
}

function stripLeadingFormatting(text: string): string {
  return normalizeFoodText(text).replace(/^[^a-z0-9]+/, '')
}

function isAggregateNutritionLine(line: string): boolean {
  return isAggregateNutritionText(line)
}

function parseExplicitMealTotal(patientText: string): number | null {
  for (const line of patientText.split(/\r?\n/)) {
    const normalized = stripLeadingFormatting(line)
    if (!/^total(?:\s+da\s+refeicao)?\s*:/i.test(normalized)) continue
    KCAL_VALUE_RE.lastIndex = 0
    const raw = KCAL_VALUE_RE.exec(line)?.[1]
    if (!raw) return null
    const value = parseLocalizedNutritionNumber(raw)
    return Number.isFinite(value) && value >= 0 ? value : null
  }
  return null
}

/**
 * Parse de "X cal/kcal/calorias" no texto do paciente, associando a um item.
 *
 * Estratégia (heurística simples conforme spec):
 *   1. Tokeniza o texto por separadores fortes (vírgula, dois-pontos, "e",
 *      "+", quebra de linha) — cada trecho representa "um item + opcionais".
 *   2. Em cada trecho com kcal, associa ao item mais próximo ANTES do número.
 *      Só usa um item posterior quando nenhum alimento foi citado antes. Se
 *      nenhum item bate, associa ao item mencionado no trecho anterior.
 *   3. Retorna Map de food_name → kcal (último valor vence se múltiplas
 *      menções; conservador).
 *
 * Pura — sem I/O. Testável.
 */
export function parseUserKcalOverrides(
  patientText: string | null | undefined,
  items: Array<{ food_name: string }>,
): Map<string, number> {
  const out = new Map<string, number>()
  if (!patientText || items.length === 0) return out
  const nutritionContext = classifyNutritionContext(patientText)
  const assertionText = nutritionContext.patientAssertions
  if (!assertionText) return out
  const normalize = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
  const negatesKcalClaim = (segmentNorm: string) =>
    /\b(?:nao|n)\s+(?:tem|e|eh|sao|possui|bate|chega)\b/.test(segmentNorm) ||
    /\berrad[oa]s?\b/.test(segmentNorm)
  // Regex: número (inteiro ou decimal com . ou ,) + kcal/cal/calorias/caloria.
  // Aceita "70 kcal", "70kcal", "70 calorias", "70cal", "70,5 kcal".
  // NÃO aceita "g/grama/gramas" pra não casar com peso — pega só energia.
  const KCAL_RE = KCAL_VALUE_RE
  // Trechos: split por ',', ':', ';', '|', '\n', '+', " e " (com espaços).
  // ATENÇÃO ao decimal "70,5" — vírgula entre dígitos NÃO é separador.
  // Lookbehind/ahead: split em [,:;|\n+] SÓ quando não está entre dígitos.
  // ` e ` (com espaços ao redor) é separador linguístico.
  // Normaliza nomes dos itens uma vez
  const normItems = items.map((it) => ({ raw: it.food_name, norm: normalize(it.food_name) }))
  // Totais e linhas do card são agregados da refeição/dia, não kcal de um
  // alimento. Removê-los antes do split também evita que "Total:" vire dois
  // segmentos e o número seja herdado pelo último item visto.
  const itemOnlyText = assertionText
    .split(/\r?\n/)
    .filter((line) => !isAggregateNutritionLine(line))
    .join('\n')
  // Primeiro separa blocos de card (`|`, quebra de linha, `+`) para que seja
  // possível descartar `Total:`/`Restam:` inteiros antes de tratar `:` como
  // separador de um item legítimo (`wrap: 70 kcal`).
  const segments = itemOnlyText
    .split(/(?<!\d)[|\n+](?!\d)/)
    .filter((part) => !isAggregateNutritionLine(part))
    .flatMap((part) => part.split(/(?<!\d)[:,;](?!\d)|(?<!\d),(?!\d)|(?:\s+e\s+)/i))
  // Default lastSeenItem: se só há UM item na refeição, ele é o alvo presumido
  // de qualquer kcal mencionada no texto (cobre caso "rap 10 : 70 cal" onde o
  // paciente escreveu "rap" mas LLM normalizou pra "wrap" no food_name).
  let lastSeenItem: string | null = items.length === 1 ? (items[0]?.food_name ?? null) : null

  // HARDENING (review HIGH KCAL-MULTI-ITEM 2026-06-16): primeiro passo — coletar
  // segmentos com kcal mas SEM item identificado por nome. Vou alinhar esses
  // por ordem com os items que ainda não receberam override (caso "rap 10 :
  // 70 cal e suco" com items=[wrap, suco] — segmento#1 tem kcal sem nome
  // batendo, segmento#2 cita 'suco' sem kcal; alinhamento por ordem dá
  // wrap=70, suco sem override).
  type SegInfo = { seg: string; segNorm: string; lastKcal: number | null; bestItem: string | null }
  const segInfos: SegInfo[] = []

  for (const segRaw of segments) {
    const seg = segRaw.trim()
    if (!seg) continue
    if (isAggregateNutritionLine(seg)) continue
    const segNorm = normalize(seg)
    const mentions: Array<{ item: string; pos: number; length: number }> = []
    const addMentions = (item: string, needle: string) => {
      if (!needle) return
      let from = 0
      while (from < segNorm.length) {
        const pos = segNorm.indexOf(needle, from)
        if (pos < 0) break
        mentions.push({ item, pos, length: needle.length })
        from = pos + Math.max(needle.length, 1)
      }
    }
    for (const ni of normItems) {
      if (!ni.norm) continue
      addMentions(ni.raw, ni.norm)
      const firstWord = ni.norm.split(/\s+/)[0]
      if (firstWord && firstWord.length >= 3) {
        addMentions(ni.raw, firstWord)
      }
    }
    let lastKcal: number | null = null
    let lastKcalPos = -1
    KCAL_RE.lastIndex = 0
    if (!negatesKcalClaim(segNorm)) {
      while (true) {
        const match = KCAL_RE.exec(seg)
        if (!match) break
        const raw = match[1]
        if (!raw) continue
        const n = parseLocalizedNutritionNumber(raw)
        if (Number.isFinite(n) && n >= 0) {
          lastKcal = n
          lastKcalPos = match.index
        }
      }
    }
    const byNearestBefore = [...mentions]
      .filter((mention) => mention.pos < lastKcalPos)
      .sort((left, right) => right.pos - left.pos || right.length - left.length)
    const byNearestAfter = [...mentions]
      .filter((mention) => mention.pos >= lastKcalPos)
      .sort((left, right) => left.pos - right.pos || right.length - left.length)
    const byLastMention = [...mentions].sort(
      (left, right) => right.pos - left.pos || right.length - left.length,
    )
    const bestItem =
      lastKcalPos >= 0
        ? (byNearestBefore[0]?.item ?? byNearestAfter[0]?.item ?? null)
        : (byLastMention[0]?.item ?? null)
    segInfos.push({ seg, segNorm, lastKcal, bestItem })
  }

  // Passo 1: aplica os overrides com bestItem definido.
  for (const info of segInfos) {
    if (info.bestItem) lastSeenItem = info.bestItem
    if (info.lastKcal == null) continue
    const target = info.bestItem ?? lastSeenItem
    if (target) out.set(target, info.lastKcal)
  }

  // Passo 2: alinhamento por ORDEM — segmentos com kcal mas sem item identificado
  // ficam órfãos. Quando há exatamente N segmentos-órfãos e ≤N items sem override
  // ainda, alinhar por posição na lista. Cobre "rap 10 : 70 cal e suco" com
  // items=[wrap, suco]: segmento#1 (kcal=70, bestItem=null) alinha com wrap
  // (1º item sem override); segmento#2 (kcal=null) ignora.
  const orphanSegsWithKcal = segInfos.filter((s) => s.lastKcal != null && s.bestItem === null)
  const itemsWithoutOverride = items.filter((it) => !out.has(it.food_name))
  if (
    orphanSegsWithKcal.length > 0 &&
    itemsWithoutOverride.length > 0 &&
    orphanSegsWithKcal.length <= itemsWithoutOverride.length
  ) {
    for (let i = 0; i < orphanSegsWithKcal.length; i++) {
      const seg = orphanSegsWithKcal[i]
      const item = itemsWithoutOverride[i]
      if (seg && item && seg.lastKcal != null && !out.has(item.food_name)) {
        out.set(item.food_name, seg.lastKcal)
      }
    }
  }

  const explicitTotal = parseExplicitMealTotal(assertionText)
  if (explicitTotal != null && items.length > 1 && out.size === items.length) {
    const itemSum = [...out.values()].reduce((sum, value) => sum + value, 0)
    const tolerance = Math.max(2, explicitTotal * 0.02)
    if (Math.abs(itemSum - explicitTotal) > tolerance) return new Map()
  }

  return out
}

const EXPLICIT_KCAL_PATTERN = /\d+(?:[.,]\d+)?\s*(?:k?cal(?:orias?)?)\b/i
const SHORT_CONFIRMATION_PATTERN =
  /^(?:sim(?:\s+isso)?|isso(?:\s+mesmo)?|e\s+isso|corret[oa]|confirmo?|pode|ok|certo|exato)[.!?\s]*$/i

const FOOD_MENTION_QUALIFIERS = new Set([
  'com',
  'sem',
  'de',
  'da',
  'do',
  'das',
  'dos',
  'cozido',
  'cozida',
  'grelhado',
  'grelhada',
  'assado',
  'assada',
  'frito',
  'frita',
  'integral',
  'branco',
  'branca',
  'derretido',
  'derretida',
  'fatiado',
  'fatiada',
  'cru',
  'crua',
])

export function mentionsFoodItem(text: string, foodName: string): boolean {
  const normalizeMention = (value: string) =>
    normalizeFoodText(value)
      .replace(/[^a-z0-9]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  const normalizedText = normalizeMention(text)
  const textTokens = new Set(normalizedText.split(/\s+/).filter(Boolean))
  const normalizedFood = normalizeMention(foodName)
  if (!normalizedText || !normalizedFood) return false
  if (` ${normalizedText} `.includes(` ${normalizedFood} `)) return true
  return normalizedFood
    .split(/\s+/)
    .filter((token) => token.length >= 3 && !FOOD_MENTION_QUALIFIERS.has(token))
    .some((token) => textTokens.has(token))
}

function mentionsCurrentFood(text: string, items: Array<{ food_name: string }>): boolean {
  return items.some((item) => mentionsFoodItem(text, item.food_name))
}

/**
 * Variante contextual: kcal explícita vale no turno atual. A mensagem anterior
 * só é consultada quando a atual é uma confirmação curta e menciona um dos
 * itens atuais. Isso preserva "80 kcal" + "sim isso" sem herdar números de
 * refeições antigas que ainda estejam no histórico da conversa.
 */
export function parseUserKcalOverridesFromMessages(
  patientTexts: Array<string | null | undefined>,
  items: Array<{ food_name: string }>,
): Map<string, number> {
  const texts = patientTexts
    .filter((text): text is string => typeof text === 'string' && text.trim().length > 0)
    .map((text) => text.trim())
  const currentText = texts.at(-1)
  if (!currentText) return new Map()

  const currentOverrides = parseUserKcalOverrides(currentText, items)
  if (currentOverrides.size > 0) return currentOverrides
  if (!SHORT_CONFIRMATION_PATTERN.test(normalizeFoodText(currentText))) return new Map()

  const previousText = texts.at(-2)
  if (
    !previousText ||
    !EXPLICIT_KCAL_PATTERN.test(previousText) ||
    !mentionsCurrentFood(previousText, items)
  ) {
    return new Map()
  }
  return parseUserKcalOverrides(previousText, items)
}

export type MealNutritionSource =
  | 'taco'
  | 'canonical_exact'
  | 'canonical_fuzzy'
  | 'canonical_composite'
  | 'canonical_composite_partial'
  | 'rule_based'
  | 'user_correction'
  | 'history'
  | 'user_kcal'
  | 'product_label'
  | 'pending_approved'
  | 'llm_estimate'
  | 'no_match'
  | 'composite_rejected'
  | 'category_mismatch'
  | 'protein_mismatch'

export interface MealItemMatched {
  food_name: string
  matched_taco_name: string
  matched_taco_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  similarity: number
  source: MealNutritionSource
  /** Quantidade em UNIDADE NATURAL pra exibir ao paciente (ex: "2 unidades", "250 ml"). */
  display_qty?: number
  /** Unidade natural pra exibição: 'g' (default), 'ml', 'unidade', 'unidades', 'pão', 'pães'. */
  display_unit?: string
}

/**
 * Decide unidade natural pra exibição baseado no nome do alimento.
 * Backend mantém gramas como unidade interna; isso é só pra UX.
 *
 * Regras:
 *   - Ovos → unidades (50g por ovo médio)
 *   - Líquidos (leite, suco, café, chocolate quente, vitamina, etc) → ml (1g ≈ 1ml)
 *   - Pão francês → unidades quando múltiplo de 50g
 *   - Outros → g
 */
export function naturalUnit(
  foodName: string,
  qtyG: number,
): { display_qty: number; display_unit: string } {
  const lower = foodName.toLowerCase()
  // Ovos: 1 ovo médio ≈ 50g
  if (/\bovo\b|\bovos\b|omelete/.test(lower)) {
    const units = Math.round(qtyG / 50)
    if (units >= 1) {
      return { display_qty: units, display_unit: units === 1 ? 'unidade' : 'unidades' }
    }
  }
  // SÓLIDOS/PÓS de marcas que costumam parecer líquido pelo nome.
  // Caso real Roberto 2026-05-15: "leite em pó" exibido como ml porque o regex
  // de líquidos abaixo casa em \bleite\b. Esta guarda EARLY força "g" pra:
  //   - leite em pó / em pó integral
  //   - café solúvel / café instantâneo
  //   - whey protein em pó / whey em pó
  //   - achocolatado em pó
  //   - chá em folhas / em flocos / granulado
  // OBS: regex usa substring sem \b porque JS \b não trata acentos (é, ó) como
  // word chars — \bp[óo]\b NÃO match "pó" no fim de string. Substring é seguro
  // aqui pois esses termos são únicos em nomes de alimentos.
  if (/em\s+p[óo]|sol[úu]vel|instant[âa]ne[oa]|em\s+flocos|em\s+folhas|granulad[oa]/i.test(lower)) {
    return { display_qty: qtyG, display_unit: 'g' }
  }
  // Chocolate em barra/bombom é sólido. A palavra "leite" em "chocolate ao
  // leite" não o transforma em bebida; apenas preparos explicitamente líquidos
  // seguem para ml.
  if (
    /chocolate/.test(lower) &&
    !/chocolate\s+quente|leite\s+com\s+chocolate|bebida|shake|smoothie|achocolatad/.test(lower)
  ) {
    return { display_qty: qtyG, display_unit: 'g' }
  }
  // Líquidos: leite, suco, café, chocolate quente, achocolatado, vitamina, smoothie,
  // chá, cerveja, vinho, refrigerante, água, whey, capuccino
  if (
    /\bleite\b|\bsuco\b|\bcaf[ée]\b|chocolate\s+quente|cappuc|capuc|achocolatad|vitamina|smoothie|\bch[áa]\b|cerveja|vinho|refri|coca|\b[áa]gua\b|whey|caipirinha|cachaça|whisky|gin|champ/.test(
      lower,
    )
  ) {
    return { display_qty: qtyG, display_unit: 'ml' }
  }
  // Pão francês: 1 pão ≈ 50g
  if (/p[ãa]o\s*franc/.test(lower) && qtyG >= 50 && qtyG % 50 === 0) {
    const units = qtyG / 50
    return { display_qty: units, display_unit: units === 1 ? 'pão' : 'pães' }
  }
  // Pão de queijo: 1 unidade ≈ 30g
  if (/p[ãa]o\s+de\s+queijo/.test(lower) && qtyG >= 30 && qtyG % 30 === 0) {
    const units = qtyG / 30
    return { display_qty: units, display_unit: units === 1 ? 'pão de queijo' : 'pães de queijo' }
  }
  // Fatias (queijo, presunto, mortadela, peito de peru): se "fatiado" ou "fatia(s)" no nome
  if (/fatiad|\bfatia/.test(lower) && qtyG >= 15 && qtyG % 15 === 0) {
    const units = qtyG / 15 // ~15g por fatia média
    return { display_qty: units, display_unit: units === 1 ? 'fatia' : 'fatias' }
  }
  // Banana média ≈ 100g; maçã ≈ 150g — só converte se múltiplo limpo
  if (/\bbanana\b/.test(lower) && qtyG >= 100 && qtyG % 100 === 0) {
    const units = qtyG / 100
    return { display_qty: units, display_unit: units === 1 ? 'banana' : 'bananas' }
  }
  if (/\bma[çc][ãa]\b/.test(lower) && qtyG >= 150 && qtyG % 150 === 0) {
    const units = qtyG / 150
    return { display_qty: units, display_unit: units === 1 ? 'maçã' : 'maçãs' }
  }
  return { display_qty: qtyG, display_unit: 'g' }
}

/**
 * Estimativa de macros por categoria quando search_food_trgm não acha.
 * Roberto pediu: em vez de zerar, supor por porções médias.
 *
 * Categorias por keyword (em ordem de prioridade):
 *   - fruta_doce | fruta_neutra
 *   - vegetal_folhoso | vegetal_geral
 *   - carne | peixe | embutido
 *   - laticineo | queijo
 *   - carbo (massa, batata, mandioca, arroz)
 *   - molho (lipid-heavy)
 *   - oleaginosa
 *   - doce / sobremesa
 *   - prato (fallback genérico)
 */
export function estimateMacros(foodName: string): {
  category: string
  kcal: number // por 100g
  protein: number
  carbs: number
  fat: number
  fiber: number
} {
  const n = foodName.toLowerCase()
  // Frutas (doces vs neutras)
  if (
    /\buvas?\b|manga|abacaxi|melancia|melão|mam[ãa]o|pera|maçã|banana|laranja|tangerina|kiwi|morango|cereja|pêssego|figo|caqui|jabuticaba|goiaba|fruta/.test(
      n,
    )
  ) {
    return { category: 'fruta', kcal: 55, protein: 0.8, carbs: 14, fat: 0.3, fiber: 1.5 }
  }
  // Vegetais folhosos
  if (/alface|rúcula|agrião|espinafre|acelga|couve|repolho|chicória|radicchio|escarola/.test(n)) {
    return { category: 'vegetal_folhoso', kcal: 18, protein: 1.5, carbs: 3, fat: 0.3, fiber: 1.8 }
  }
  // Vegetais cozidos / em geral
  if (
    /br[óo]colis|couve-flor|abobrinha|berinjela|pepino|tomate|cenoura|beterraba|chuchu|vagem|ervilha|milho|aspargo|palmito/.test(
      n,
    )
  ) {
    return { category: 'vegetal', kcal: 35, protein: 2, carbs: 7, fat: 0.3, fiber: 2 }
  }
  // Empanados / fritos calóricos (Roberto 2026-06-05): tem que vir ANTES de
  // peixe/carne/frango pq esses preparos brasileiros agregam farinha+óleo na
  // fritura. Bug observado: "frango à milanesa" caía em categoria 'frango'
  // (165 kcal/100g) quando o real é ~280. Cobre milanesa, empanado, parmegiana,
  // à passarinho, schnitzel, nuggets, escalope, e variantes com "frito".
  // \b não funciona com 'à' (não é \w em ASCII). Uso (^|\s|[^\w]) como
  // boundary que tolera acento. "passarinho" pode vir como "à passarinho" ou
  // "a passarinho".
  if (
    /(?:^|\s)(milanesa|empanad[oa]s?|parmegiana|parmigiana|schnitzel|nuggets?|escalope|cordon\s*bleu)(?:\s|$|,|\.)/.test(
      n,
    ) ||
    /(?:^|\s)[àa]\s+passarinho(?:\s|$)/.test(n) ||
    /\b(frito|fritos?)\b.*(frango|peixe|carne|bife|peru|cordeiro|porco|costela)/.test(n) ||
    /(frango|peixe|carne|bife|peru|cordeiro|porco|costela).*\b(frito|fritos?)\b/.test(n)
  ) {
    // Carne empanada/frita: gordura mais alta. Frango/peixe: gordura menor.
    if (/peixe|atum|salmão|tilápia|merluza|sardinha|bacalhau/.test(n)) {
      return { category: 'empanado_peixe', kcal: 220, protein: 18, carbs: 13, fat: 11, fiber: 0.5 }
    }
    if (/carne|bife|picanha|patinho|porco|costela|cordeiro/.test(n)) {
      return { category: 'empanado_carne', kcal: 300, protein: 22, carbs: 12, fat: 17, fiber: 0.5 }
    }
    // default empanado (frango/peru)
    return { category: 'empanado_frango', kcal: 280, protein: 23, carbs: 11, fat: 16, fiber: 0.5 }
  }
  // Embutidos / frios processados
  if (
    /salame|presunto|mortadela|peito\s+de\s+peru|peru|peito\s+de\s+frango\s+defumado|salsicha|kani|kani\s+kama|sushi/.test(
      n,
    )
  ) {
    return { category: 'embutido', kcal: 180, protein: 18, carbs: 2, fat: 11, fiber: 0 }
  }
  // Peixe
  if (
    /peixe|atum|salmão|tilápia|merluza|sardinha|bacalhau|camarão|sush|robalo|namorado|cação/.test(n)
  ) {
    return { category: 'peixe', kcal: 130, protein: 22, carbs: 0, fat: 4, fiber: 0 }
  }
  // Carne vermelha
  if (
    /carne|bife|picanha|alcatra|file mignon|filé mignon|costela|patinho|coxão|maminha|fraldinha|cordeiro/.test(
      n,
    )
  ) {
    return { category: 'carne', kcal: 200, protein: 26, carbs: 0, fat: 11, fiber: 0 }
  }
  // Frango / aves
  if (/frango|coxa|asa|sobrecoxa|peito\s+de\s+frango|peru/.test(n)) {
    return { category: 'frango', kcal: 165, protein: 28, carbs: 0, fat: 5, fiber: 0 }
  }
  // Chocolate sólido precisa ser classificado antes de laticínios. Em
  // "chocolate ao leite", leite descreve a variedade do doce, não a forma.
  if (
    /chocolate/.test(n) &&
    !/chocolate\s+quente|leite\s+com\s+chocolate|bebida|shake|smoothie|achocolatad/.test(n)
  ) {
    return { category: 'doce', kcal: 260, protein: 3, carbs: 45, fat: 8, fiber: 1 }
  }
  // Laticínios líquidos / leites
  if (/iogurte|kefir|coalhada|leite/.test(n)) {
    return { category: 'laticineo', kcal: 65, protein: 4, carbs: 5, fat: 3, fiber: 0 }
  }
  // Queijos
  if (
    /queijo|cream\s+cheese|requeij[ãa]o|ricota|cottage|burrata|mussarela|provolone|parmes[ãa]o|gorgonzola/.test(
      n,
    )
  ) {
    return { category: 'queijo', kcal: 290, protein: 20, carbs: 3, fat: 22, fiber: 0 }
  }
  // Massas / carbos
  if (/macarr[ãa]o|massa|espaguete|talharim|penne|nhoque|lasanha|ravioli|tortelini/.test(n)) {
    return { category: 'massa', kcal: 130, protein: 5, carbs: 25, fat: 1.5, fiber: 1 }
  }
  if (/arroz|risoto|pa[ée]lla/.test(n)) {
    return { category: 'arroz', kcal: 130, protein: 2.5, carbs: 28, fat: 0.3, fiber: 0.5 }
  }
  if (/batata|mandioca|aipim|inhame|cará|baroa|tubércul/.test(n)) {
    return { category: 'tubérculo', kcal: 90, protein: 1.5, carbs: 21, fat: 0.1, fiber: 1.5 }
  }
  // Pão / panificação
  if (/p[ãa]o|biscoito|bolacha|torrada|crepioca|tapioca|panqueca|crepe|wrap/.test(n)) {
    return { category: 'panificação', kcal: 270, protein: 8, carbs: 50, fat: 4, fiber: 2 }
  }
  // Molhos / condimentos calóricos
  if (/molho\s+de\s+salada|molho\s+ranch|maionese|mostarda\s+e\s+mel|c[ée]sar|tarta/.test(n)) {
    return { category: 'molho_calórico', kcal: 380, protein: 1, carbs: 6, fat: 38, fiber: 0 }
  }
  if (/molho/.test(n)) {
    return { category: 'molho', kcal: 80, protein: 2, carbs: 8, fat: 4, fiber: 0.5 }
  }
  // Doces / sobremesas
  if (/sorvete|chocolate|brigadeiro|pudim|torta|bolo|doce|geleia|mel|açúcar/.test(n)) {
    return { category: 'doce', kcal: 260, protein: 3, carbs: 45, fat: 8, fiber: 1 }
  }
  // Oleaginosas
  if (/castanha|amêndoa|noz|amendoim|pistache|avelã|macadâmia|granola/.test(n)) {
    return { category: 'oleaginosa', kcal: 580, protein: 18, carbs: 20, fat: 50, fiber: 8 }
  }
  // Bebidas zero — refrigerantes/bebidas com qualificador zero/diet/light
  // (coca zero, coca-cola zero, guaraná zero, refri diet, soda light, etc.).
  // Bug Luciana 2026-05-25: regex antigo só pegava "refri zero" literal.
  if (
    /[áa]gua|ch[áa]\b|caf[ée]\s+preto|adoçant/.test(n) ||
    (/\b(zero|diet|light|sem a[çc][uú]car|sem calorias?)\b/.test(n) &&
      /\b(refri|refrigerante|coca|cola|guaran[áa]|soda|gaseosa|soft\s*drink|t[ôo]nica|energ[ée]tico)\b/.test(
        n,
      ))
  ) {
    return { category: 'bebida_zero', kcal: 1, protein: 0, carbs: 0, fat: 0, fiber: 0 }
  }
  // Fallback genérico — prato preparado
  return { category: 'prato_genérico', kcal: 150, protein: 7, carbs: 18, fat: 5, fiber: 1 }
}

function normalizeFoodText(s: string): string {
  return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim()
}

function productCodeIdentifiers(foodName: string): string[] {
  const normalized = normalizeFoodText(foodName)
  const tokens = normalized
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
  const identifiers = tokens.filter((token) => /[a-z]/.test(token) && /\d/.test(token))
  if (/\brap\s+10\b/.test(normalized)) identifiers.push('rap10')
  return [...new Set(identifiers)]
}

function hasProductCodeIdentifier(foodName: string): boolean {
  return productCodeIdentifiers(foodName).length > 0
}

const SIMPLE_FRESH_FRUIT_ALIASES = new Map<string, string>([
  ['abacaxi', 'abacaxi'],
  ['abacaxis', 'abacaxi'],
  ['banana', 'banana'],
  ['bananas', 'banana'],
  ['caqui', 'caqui'],
  ['caquis', 'caqui'],
  ['figo', 'figo'],
  ['figos', 'figo'],
  ['goiaba', 'goiaba'],
  ['goiabas', 'goiaba'],
  ['jabuticaba', 'jabuticaba'],
  ['jabuticabas', 'jabuticaba'],
  ['kiwi', 'kiwi'],
  ['kiwis', 'kiwi'],
  ['laranja', 'laranja'],
  ['laranjas', 'laranja'],
  ['maca', 'maca'],
  ['macas', 'maca'],
  ['mamao', 'mamao'],
  ['mamoes', 'mamao'],
  ['manga', 'manga'],
  ['mangas', 'manga'],
  ['melao', 'melao'],
  ['meloes', 'melao'],
  ['melancia', 'melancia'],
  ['melancias', 'melancia'],
  ['morango', 'morango'],
  ['morangos', 'morango'],
  ['pera', 'pera'],
  ['peras', 'pera'],
  ['pessego', 'pessego'],
  ['pessegos', 'pessego'],
  ['tangerina', 'tangerina'],
  ['tangerinas', 'tangerina'],
  ['uva', 'uva'],
  ['uvas', 'uva'],
])

const SIMPLE_FRESH_FRUIT_MODIFIERS = new Set([
  'branca',
  'brancas',
  'casca',
  'cascas',
  'com',
  'cru',
  'crua',
  'cruas',
  'crus',
  'da',
  'das',
  'de',
  'do',
  'dos',
  'fresca',
  'frescas',
  'fuji',
  'gala',
  'italiana',
  'italianas',
  'nanica',
  'nanicas',
  'prata',
  'pratas',
  'preta',
  'pretas',
  'roxa',
  'roxas',
  'semente',
  'sementes',
  'sem',
  'unidade',
  'unidades',
  'verde',
  'verdes',
  'vermelha',
  'vermelhas',
])

const DERIVED_FRUIT_PATTERN =
  /\b(?:bolo|compota|desidratad[oa]s?|doce|geleia|goiabada|iogurte|passas?|polpa|sorvete|suco|torta)\b/

function simpleFreshFruitKey(foodName: string): string | null {
  const normalized = normalizeFoodText(foodName)
  if (!normalized || DERIVED_FRUIT_PATTERN.test(normalized)) return null
  const tokens = normalized
    .replace(/[^a-z\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
  const fruitKeys = tokens
    .map((token) => SIMPLE_FRESH_FRUIT_ALIASES.get(token))
    .filter((token): token is string => token != null)
  if (fruitKeys.length !== 1) return null
  if (
    tokens.some(
      (token) => !SIMPLE_FRESH_FRUIT_ALIASES.has(token) && !SIMPLE_FRESH_FRUIT_MODIFIERS.has(token),
    )
  ) {
    return null
  }
  return fruitKeys[0] ?? null
}

function isSimpleFreshFruitName(foodName: string): boolean {
  return simpleFreshFruitKey(foodName) != null
}

function isSweetDerivedFruitMismatch(
  foodName: string,
  matchedName: string | null | undefined,
  matchCategory: string | null | undefined,
): boolean {
  if (!isSimpleFreshFruitName(foodName)) return false
  const matched = normalizeFoodText(matchedName ?? '')
  if (!matched) return false
  const fruitKey = simpleFreshFruitKey(foodName)
  if (fruitKey != null && simpleFreshFruitKey(matched) === fruitKey) return false
  return (matchCategory ?? '').toLowerCase().includes('doce') || DERIVED_FRUIT_PATTERN.test(matched)
}

function isImplausibleFreshFruitHistory(
  foodName: string,
  kcalPer100g: number,
  carbsPer100g: number,
  fatPer100g: number,
): boolean {
  if (!isSimpleFreshFruitName(foodName)) return false
  return kcalPer100g >= 120 || carbsPer100g > 40 || fatPer100g > 8
}

type SkinState = 'skinless' | 'skin_on' | 'unspecified'

type PreparationState =
  | 'fried'
  | 'air_fried'
  | 'grilled'
  | 'roasted'
  | 'cooked'
  | 'sauteed'
  | 'raw'
  | 'unspecified'

type PhysicalFormState = 'powdered' | 'liquid' | 'unspecified'
type MilkFatState = 'skim' | 'semi_skim' | 'whole' | 'unspecified'

function inferSkinState(foodName: string): SkinState {
  const n = normalizeFoodText(foodName)
  if (
    /\bsem\s+(?:a\s+)?pele\b|\bpele\s+(?:retirada|removida)\b|\b(?:retirada|removida)\s+(?:a\s+)?pele\b/.test(
      n,
    )
  ) {
    return 'skinless'
  }
  if (/\bcom\s+(?:a\s+)?pele\b/.test(n)) return 'skin_on'
  return 'unspecified'
}

function hasSkinModifierConflict(currentFoodName: string, historicalFoodName: string): boolean {
  const current = inferSkinState(currentFoodName)
  const historical = inferSkinState(historicalFoodName)
  if (current === 'unspecified' && historical === 'unspecified') return false
  return current !== historical
}

function inferPreparationState(foodName: string): PreparationState {
  const n = normalizeFoodText(foodName)
  if (/\bair\s*fryer\b|\bairfryer\b|\bfritadeira\s+sem\s+oleo\b/.test(n)) {
    return 'air_fried'
  }
  if (
    /\bfrit[oa]s?\b|\bempanad[oa]s?\b|\bmilanesa\b|\bparmegiana\b|\bparmigiana\b|\bpassarinho\b|\bnuggets?\b|\bschnitzel\b|\bcordon\s+bleu\b/.test(
      n,
    )
  ) {
    return 'fried'
  }
  if (/\bgrelhad[oa]s?\b|\bchapa\b/.test(n)) return 'grilled'
  if (/\bassad[oa]s?\b|\bforno\b/.test(n)) return 'roasted'
  if (/\bcozid[oa]s?\b|\bfervid[oa]s?\b|\bpoche\b/.test(n)) return 'cooked'
  if (/\brefogad[oa]s?\b|\bsaltead[oa]s?\b/.test(n)) return 'sauteed'
  if (/\bcru[as]?\b|\bin\s+natura\b/.test(n)) return 'raw'
  return 'unspecified'
}

function hasPreparationModifierConflict(currentFoodName: string, matchedFoodName: string): boolean {
  const current = inferPreparationState(currentFoodName)
  if (current === 'unspecified') return false
  return current !== inferPreparationState(matchedFoodName)
}

function inferPhysicalFormState(foodName: string): PhysicalFormState {
  const n = normalizeFoodText(foodName)
  if (/\bem\s+po\b|\bpowder(?:ed)?\b|\bsoluvel\b|\binstantaneo\b/.test(n)) {
    return 'powdered'
  }
  if (/\bleite\b|\bsuco\b|\bcafe\b|\bbebida\b|\bshake\b|\bsmoothie\b/.test(n)) {
    return 'liquid'
  }
  return 'unspecified'
}

function inferMilkFatState(foodName: string): MilkFatState {
  const n = normalizeFoodText(foodName)
  if (/\bsemi\s*desnatad[oa]s?\b|\bsemi\s*skim(?:med)?\b/.test(n)) return 'semi_skim'
  if (/\bdesnatad[oa]s?\b|\bskim(?:med)?\b/.test(n)) return 'skim'
  if (/\bintegral\b|\bwhole\b/.test(n)) return 'whole'
  return 'unspecified'
}

function hasPhysicalFormConflict(currentFoodName: string, matchedFoodName: string): boolean {
  const current = inferPhysicalFormState(currentFoodName)
  const matched = inferPhysicalFormState(matchedFoodName)
  return current !== 'unspecified' && matched !== 'unspecified' && current !== matched
}

function hasMilkFatConflict(currentFoodName: string, matchedFoodName: string): boolean {
  const dairyPattern = /\b(leite|iogurte|queijo|lacte[oa]|kefir|kumis|koumiss|skyr|whey)\b/
  if (
    !dairyPattern.test(normalizeFoodText(currentFoodName)) &&
    !dairyPattern.test(normalizeFoodText(matchedFoodName))
  ) {
    return false
  }
  const current = inferMilkFatState(currentFoodName)
  const matched = inferMilkFatState(matchedFoodName)
  if (current === 'unspecified' && matched === 'unspecified') return false
  return current !== matched
}

type FermentedDairySubtype = 'kumis' | 'greek' | 'kefir' | 'skyr' | 'unspecified'

function inferFermentedDairySubtype(foodName: string): FermentedDairySubtype {
  const n = normalizeFoodText(foodName)
  if (/\b(kumis|koumiss|kumys)\b/.test(n)) return 'kumis'
  if (/\b(grego|greek)\b/.test(n)) return 'greek'
  if (/\bkefir\b/.test(n)) return 'kefir'
  if (/\bskyr\b/.test(n)) return 'skyr'
  return 'unspecified'
}

function hasFermentedDairySubtypeConflict(
  currentFoodName: string,
  matchedFoodName: string,
): boolean {
  const current = inferFermentedDairySubtype(currentFoodName)
  const matched = inferFermentedDairySubtype(matchedFoodName)
  if (current === 'unspecified' && matched === 'unspecified') return false
  return current !== matched
}

function hasNutritionModifierConflict(currentFoodName: string, matchedFoodName: string): boolean {
  return (
    hasSkinModifierConflict(currentFoodName, matchedFoodName) ||
    hasPreparationModifierConflict(currentFoodName, matchedFoodName) ||
    hasPhysicalFormConflict(currentFoodName, matchedFoodName) ||
    hasMilkFatConflict(currentFoodName, matchedFoodName) ||
    hasFermentedDairySubtypeConflict(currentFoodName, matchedFoodName)
  )
}

const PROTEIN_FOOD_PATTERN =
  /\b(frango|sobrecoxa|coxa|asa|peito|carne|bife|porco|lombo|bisteca|peixe|atum|salmao|tilapia|peru|cordeiro|costela|ovo|hamburguer)\b/

export function requiresVisualPreparationConfirmation(foodName: string): boolean {
  const normalized = normalizeFoodText(foodName)
  if (!PROTEIN_FOOD_PATTERN.test(normalized)) return false
  return (
    inferPreparationState(foodName) !== 'unspecified' || inferSkinState(foodName) !== 'unspecified'
  )
}

export interface MealCalcResult {
  items: MealItemMatched[]
  totals: {
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
    fiber_g: number
  }
  /** Warnings DEPRECATED. Use user_warnings ou audit_warnings. Mantido pra
   * compatibilidade — concatena os dois. */
  warnings: string[]
  /** Warnings que DEVEM ser mostradas ao paciente (precisa de ação dele):
   *  - composite rejeitado (paciente separa items)
   *  - match suspeito (paciente confirma)
   *  - sanity violations (densidade calórica, proteína esperada)
   * Estes vão na resposta do agente. */
  user_warnings: string[]
  /** Warnings APENAS pra audit interno (paciente NÃO precisa saber):
   *  - auto-split bem-sucedido
   *  - reuso de histórico
   *  - estimativa por categoria silenciosa
   * Estes vão pra product_events mas não pro paciente. */
  audit_warnings: string[]
}

/**
 * Extrai o "âncora" do nome do alimento — palavra-chave do ingrediente principal,
 * removendo qualifiers de preparo/tipo. Usado pra rejeitar match catastrófico
 * onde o trigram dominou a similaridade por uma palavra de preparo.
 *
 * Exemplo: "arroz refogado" → âncora="arroz". Match "espinafre refogado" não
 * contém "arroz" → rejeita match, cai pra estimativa por categoria.
 *
 * Reportado por Roberto em 2026-05-12: "arroz refogado" matchou com
 * "espinafre refogado" (39 kcal/100g) → 47 kcal pra 120g de arroz = absurdo.
 */
const PREPARATION_QUALIFIERS = new Set([
  'refogado',
  'refogada',
  'cozido',
  'cozida',
  'frito',
  'frita',
  'assado',
  'assada',
  'grelhado',
  'grelhada',
  'cru',
  'crua',
  'natural',
  'temperado',
  'temperada',
  'recheado',
  'recheada',
  'gratinado',
  'gratinada',
  'mexido',
  'mexida',
  'desfiado',
  'desfiada',
  'moído',
  'moida',
  'moído',
  'moída',
  'picado',
  'picada',
  'fatiado',
  'fatiada',
  'ralado',
  'ralada',
  'branco',
  'branca',
  'integral',
  'doce',
  'salgado',
  'salgada',
  'light',
  'diet',
  'zero',
  'magro',
  'magra',
  'gordo',
  'gorda',
  'com',
  'sem',
  'ao',
  'no',
  'na',
  'de',
  'do',
  'da',
  'dos',
  'das',
  'e',
  'em',
  'pra',
  'para',
  'tipo',
  'estilo',
  'mix',
])

export function extractAnchor(foodName: string): string | null {
  const fruitKey = simpleFreshFruitKey(foodName)
  if (fruitKey) return fruitKey
  const tokens = foodName
    .toLowerCase()
    .replace(/[^a-záéíóúâêôãõçü\s]/gi, ' ')
    .split(/\s+/)
    .filter((t) => t.length >= 3 && !PREPARATION_QUALIFIERS.has(t))
  // Prioriza o token mais longo (geralmente o ingrediente principal).
  // Empate: pega o primeiro (ordem de menção do paciente).
  if (tokens.length === 0) return null
  tokens.sort((a, b) => b.length - a.length)
  return tokens[0] ? normalizeFoodText(tokens[0]) : null
}

const TRUSTED_HISTORY_SOURCES = ['canonical_exact', 'canonical_fuzzy', 'user_kcal'] as const

function isTrustedHistorySource(source: string | null | undefined): boolean {
  return (TRUSTED_HISTORY_SOURCES as readonly string[]).includes(source ?? '')
}

function hasVerifiedFoodReference(
  reference:
    | { is_verified?: boolean | null }
    | Array<{ is_verified?: boolean | null }>
    | null
    | undefined,
): boolean {
  const row = Array.isArray(reference) ? reference[0] : reference
  return row?.is_verified === true
}

function canonicalSource(
  requestedName: string,
  canonicalName: string | null,
): 'canonical_exact' | 'canonical_fuzzy' {
  return normalizeFoodText(requestedName) === normalizeFoodText(canonicalName ?? '')
    ? 'canonical_exact'
    : 'canonical_fuzzy'
}

/**
 * Detecta bebida ZERO/diet/light (caloria desprezível) — Bug Luciana 2026-05-25.
 *
 * Caso real: paciente disse "a coca é zero", o agente respondeu "tem caloria
 * zerada" mas GRAVOU "coca-cola zero" com 136,5 kcal — o valor da coca NORMAL.
 * Causa: a food_db tem "coca-cola" (~42 kcal/100g) mas NÃO tem o alias zero, e o
 * "zero" é tratado como qualifier de preparo (PREPARATION_QUALIFIERS), então o
 * trigram casa a coca cheia e o qualificador "zero" é simplesmente descartado.
 *
 * Aqui forçamos macros ~0 ANTES do match quando o nome tem qualificador de
 * zero-caloria E é claramente uma bebida/refrigerante. Suco, leite, água de
 * coco e a coca NORMAL não casam (sem qualificador zero) e seguem o fluxo normal.
 */
const ZERO_CAL_QUALIFIER = /\b(zero|diet|light|sem a[çc][uú]car|sem calorias?)\b/i
const DRINK_KEYWORD =
  /\b(refri|refrigerante|coca|cola|guaran[áa]|soda|gaseosa|soft\s*drink|tônica|t[ôo]nica|energ[ée]tico)\b/i

export function isZeroCalDrink(foodName: string, matchCategory?: string | null): boolean {
  const n = foodName.toLowerCase()
  if (!ZERO_CAL_QUALIFIER.test(n)) return false
  // É bebida pelo nome OU pela categoria do match no food_db (ex.: "bebidas").
  const cat = (matchCategory ?? '').toLowerCase()
  return DRINK_KEYWORD.test(n) || cat === 'bebidas' || cat === 'bebida'
}

function nutritionSourceError(error: unknown, fallback: string): Error {
  if (
    typeof error === 'object' &&
    error !== null &&
    'message' in error &&
    typeof error.message === 'string'
  ) {
    return new Error(error.message)
  }
  return new Error(fallback)
}

/**
 * Match fuzzy via pg_trgm.
 * Threshold de 0.3 (ajustável). Acima disso confiamos no match.
 */
async function matchFood(
  supabase: ServiceClient,
  name: string,
  country: string = 'BR',
): Promise<{
  id: number | null
  name_pt: string | null
  category: string | null
  similarity: number
  kcal_per_100g: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
  fiber_g: number | null
}> {
  // Pede uma janela maior de candidatos pra fazer tie-break determinístico em código.
  // Com o catálogo oficial completo, top-5 pode ser ocupado por descrições muito
  // parecidas do mesmo país e esconder a alternativa exata do país do paciente.
  // (Roberto+Luciana
  // 2026-06-03: alface crespa retornava 6 kcal numa chamada e 4 noutra; milho 34 vs 14
  // — postgres não garante ordem estável em ORDER BY similarity DESC quando há
  // empate, e LIMIT 1 expõe a flutuação. Fix: pega top-N, ordena por
  // (similarity DESC, id ASC) em JS — mesma chamada, mesmo retorno, sempre).
  const { data, error } = await (
    supabase as unknown as {
      rpc: (n: string, p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
    }
  ).rpc('search_food_trgm', {
    search_term: name.toLowerCase(),
    min_similarity: 0.2,
    max_results: 20,
    p_country: country,
  })

  const empty = {
    id: null,
    name_pt: null,
    category: null,
    similarity: 0,
    kcal_per_100g: null,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    fiber_g: null,
  }

  type Row = {
    id: number | null
    name_pt: string | null
    category: string | null
    similarity: number | null
    kcal_per_100g: number | string | null
    protein_g: number | string | null
    carbs_g: number | string | null
    fat_g: number | string | null
    fiber_g: number | string | null
    country_code?: string | null
  }
  const rows = (data ?? []) as Row[]
  if (error) throw nutritionSourceError(error, 'canonical food search failed')
  if (rows.length === 0) return empty

  // Ingredientes simples não podem herdar os macros de um prato composto só
  // porque ambos compartilham o ingrediente principal. Caso real: "calabresa
  // fatiada" empatou no trigram com "pizza de calabresa" e "linguiça
  // calabresa"; o desempate por menor id escolheu a pizza.
  const dishMarkers = [
    'pizza',
    'pastel',
    'torta',
    'lasanha',
    'sanduiche',
    'hamburguer',
    'risoto',
    'sopa',
    'omelete',
    'panqueca',
    'empada',
    'esfiha',
    'quiche',
  ]
  const requestedName = normalizeFoodText(name)
  const compatibleRows = rows.filter((row) => {
    if (normalizeFoodText(row.category ?? '') !== 'pratos') return true
    const candidateName = normalizeFoodText(row.name_pt ?? '')
    return !dishMarkers.some(
      (marker) => candidateName.includes(marker) && !requestedName.includes(marker),
    )
  })
  if (compatibleRows.length === 0) return empty

  // O trigram pode ranquear um derivado acima do alimento simples ("goiaba"
  // -> "goiaba, doce, cascão" antes de "goiaba, crua"). Se o conjunto contém
  // uma fruta fresca compatível, descarte os doces antes do desempate. Quando
  // só há derivados, preserve o melhor candidato para o guard posterior gerar
  // o aviso explícito e cair no fallback de fruta.
  let candidateRows = compatibleRows
  if (hasProductCodeIdentifier(name)) {
    const identifiers = productCodeIdentifiers(name)
    const sameCountryRows = candidateRows.filter((row) => {
      if (row.country_code?.toUpperCase() !== country.toUpperCase()) return false
      const candidateTokens = normalizeFoodText(row.name_pt ?? '')
        .replace(/[^a-z0-9\s]/g, ' ')
        .split(/\s+/)
        .filter(Boolean)
      return identifiers.every((identifier) => candidateTokens.includes(identifier))
    })
    // Um código comercial não é portável entre países: "rap10" no Brasil
    // não pode herdar automaticamente o rótulo do produto Mission dos EUA.
    if (sameCountryRows.length === 0) return empty
    candidateRows = sameCountryRows
  }
  if (isSimpleFreshFruitName(name)) {
    const freshRows = candidateRows.filter(
      (row) => !isSweetDerivedFruitMismatch(name, row.name_pt, row.category),
    )
    if (freshRows.length > 0) candidateRows = freshRows
  }

  // A mesma regra vale para preparo e composição: se há uma alternativa
  // compatível no top-N, não escolha primeiro a versão frita/com pele/integral
  // errada para só depois rejeitá-la.
  const modifierCompatibleRows = candidateRows.filter(
    (row) => row.name_pt == null || !hasNutritionModifierConflict(name, row.name_pt),
  )
  if (modifierCompatibleRows.length > 0) candidateRows = modifierCompatibleRows

  // Tie-break determinístico: similarity DESC, país do paciente, id ASC.
  // Empate de similarity (até 0.001 de diferença, abaixo do ruído de cast
  // real→float) deve preservar a preferência da RPC por país. Reordenar só
  // por id fazia uma linha BR mais antiga vencer a US para pacientes nos EUA.
  const sorted = [...candidateRows].sort((a, b) => {
    const simA = a.similarity ?? 0
    const simB = b.similarity ?? 0
    if (Math.abs(simA - simB) > 0.001) return simB - simA
    const requestedCountry = country.toUpperCase()
    const countryRankA = a.country_code?.toUpperCase() === requestedCountry ? 0 : 1
    const countryRankB = b.country_code?.toUpperCase() === requestedCountry ? 0 : 1
    if (countryRankA !== countryRankB) return countryRankA - countryRankB
    const idA = a.id ?? Number.MAX_SAFE_INTEGER
    const idB = b.id ?? Number.MAX_SAFE_INTEGER
    return idA - idB
  })

  const top = sorted[0]
  if (!top) return empty
  return {
    id: top.id ?? null,
    name_pt: top.name_pt ?? null,
    category: top.category ?? null,
    similarity: top.similarity ?? 0,
    kcal_per_100g: top.kcal_per_100g != null ? Number(top.kcal_per_100g) : null,
    protein_g: top.protein_g != null ? Number(top.protein_g) : null,
    carbs_g: top.carbs_g != null ? Number(top.carbs_g) : null,
    fat_g: top.fat_g != null ? Number(top.fat_g) : null,
    fiber_g: top.fiber_g != null ? Number(top.fiber_g) : null,
  }
}

/**
 * Calcula macros para uma lista de itens.
 * Cada item identificado vai para a food_db. Itens sem match recebem
 * estimativa zero e o warning é registrado.
 */
/**
 * Procura uma correção de alimento APRENDIDA pra esse paciente.
 * Roberto pediu (2026-05-14): quando o paciente corrige a identidade de um
 * alimento ("batata" → "mandioca"), o sistema aprende e reaplica.
 *
 * Precedência: ESTE lookup roda ANTES de tudo (histórico, trigram, estimativa).
 *
 * Comportamento por status:
 *   - 'active' (confirmed_count >= 2): aplica silencioso — remapeia o nome.
 *   - 'learning' (confirmed_count = 1): aplica MAS marca needs_confirmation=true,
 *     pra o agente confirmar com o paciente ("registrei mandioca — você corrigiu
 *     isso antes; se hoje for batata mesmo, me avisa").
 *   - 'retired': ignorado (filtrado na query).
 *
 * Janela: só correções com last_seen nos últimos 30 dias (mesma janela do
 * lookupUserHistory — correção velha de comida que a pessoa não come mais
 * não deve valer pra sempre).
 *
 * Retorna `null` se não há correção aplicável.
 */
export async function lookupFoodCorrection(
  supabase: ServiceClient,
  userId: string,
  foodName: string,
): Promise<{
  corrected_to: string
  custom_macros: {
    kcal_per_100g: number
    protein_g: number
    carbs_g: number
    fat_g: number
  } | null
  needs_confirmation: boolean
  /** True quando correção tem confirmed_count >= 3 (paciente já confirmou
   * múltiplas vezes — aplicar silenciosamente sem warning audível). */
  is_well_established: boolean
} | null> {
  const normalize = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
  const target = normalize(foodName)
  if (!target) return null
  const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  // biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const supaTyped = supabase as any
  // Busca por said_name OU corrected_to. Bug Amanda 2026-05-16: ela corrigiu
  // "iogurte de pêssego" → "iogurte de pêssego whey" com custom_macros, depois
  // o LLM passou items.food_name="iogurte de pêssego whey" (= corrected_to).
  // Lookup com .eq('said_name', target) NÃO achava → cai em estimate genérico
  // → custom_macros 49 kcal/100g + 5.9g P/100g NÃO aplicado → registrou 0.68g P
  // em vez de 5g P. Usar .or() pra cobrir os 2 casos: LLM passou nome original
  // OU passou nome já corrigido. Ordena por last_seen DESC pra pegar o mais
  // recente em caso de múltiplas correções convergentes.
  const { data, error } = await supaTyped
    .from('user_food_corrections')
    .select(
      'said_name, corrected_to, custom_kcal_per_100g, custom_protein_g, custom_carbs_g, custom_fat_g, status, confirmed_count',
    )
    .eq('user_id', userId)
    .or(`said_name.eq.${target},corrected_to.eq.${target}`)
    .neq('status', 'retired')
    .gte('last_seen', lookback)
    .order('last_seen', { ascending: false })
    .limit(1)
  if (error) throw nutritionSourceError(error, 'food correction lookup failed')
  const row = (data ?? [])[0] as
    | {
        said_name: string
        corrected_to: string
        custom_kcal_per_100g: number | string | null
        custom_protein_g: number | string | null
        custom_carbs_g: number | string | null
        custom_fat_g: number | string | null
        status: string
        confirmed_count: number
      }
    | undefined
  if (!row) return null
  const hasCustom = row.custom_kcal_per_100g != null
  return {
    corrected_to: row.corrected_to,
    custom_macros: hasCustom
      ? {
          kcal_per_100g: Number(row.custom_kcal_per_100g),
          protein_g: Number(row.custom_protein_g ?? 0),
          carbs_g: Number(row.custom_carbs_g ?? 0),
          fat_g: Number(row.custom_fat_g ?? 0),
        }
      : null,
    needs_confirmation: row.status === 'learning',
    is_well_established: row.status === 'active' && (row.confirmed_count ?? 0) >= 3,
  }
}

/**
 * Procura o mesmo alimento no histórico do paciente nos últimos 30d.
 * Roberto pediu (2026-05-13): "consegue pegar os alimentos q se repetem
 * pra vir nas refeições seguintes qd ele identificar algo semelhante?
 * Pq tipo, todo dia eu tomo leite com whey de manhã e todo dia ele coloca
 * achocolatado ou chocolate quente".
 *
 * Estratégia: o próprio `meal_logs` é a memória do paciente. Se ele
 * confirmou X = Y macros num dia (após correção, replace=true substitui
 * os logs antigos), nos dias seguintes esse log vira fonte de verdade.
 *
 * Filtros importantes:
 *   - source em fontes explicitamente confiáveis (sem estimativa por categoria)
 *   - kcal > 0 (exclui logs sanity-rejected)
 *   - últimas 30d
 *   - case/acento-insensitive (normalize)
 *
 * Retorna `null` se não acha hit confiável.
 */
export async function lookupUserHistory(
  supabase: ServiceClient,
  userId: string,
  foodName: string,
): Promise<{
  food_db_id: number
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  matched_log_id: string
  matched_food_name: string
} | null> {
  const normalize = normalizeFoodText
  const target = normalize(foodName)
  const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  // biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const supaTyped = supabase as any
  const { data, error } = await supaTyped
    .from('meal_logs')
    .select(
      'id, food_name, food_db_id, quantity_g, kcal, protein_g, carbs_g, fat_g, source, food_db:food_db_id(is_verified)',
    )
    .eq('user_id', userId)
    .in('source', [...TRUSTED_HISTORY_SOURCES])
    .gt('kcal', 0)
    .gte('created_at', lookback)
    .order('created_at', { ascending: false })
    .limit(50)
  if (error) throw nutritionSourceError(error, 'personal food history lookup failed')
  const rows = (data ?? []) as Array<{
    id: string
    food_name: string
    food_db_id: number | null
    quantity_g: number
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
    source: string | null
    food_db: { is_verified?: boolean | null } | Array<{ is_verified?: boolean | null }> | null
  }>
  const compatibleRows = rows.filter(
    (r) =>
      isTrustedHistorySource(r.source) &&
      hasVerifiedFoodReference(r.food_db) &&
      !hasNutritionModifierConflict(foodName, r.food_name),
  )
  // Histórico pessoal só é seguro para o mesmo nome normalizado. Similaridade
  // textual não comprova equivalência nutricional: "sorvete" e "sorvete de
  // iogurte", ou "frango ao molho" e "frango ao molho cremoso", podem ter
  // densidades muito diferentes. Variações e aliases ficam a cargo do food_db
  // canônico e das correções explícitas do paciente.
  const exact = compatibleRows.find(
    (r) => normalize(r.food_name) === target && Number.isInteger(r.food_db_id),
  )
  if (!exact || exact.quantity_g <= 0) return null
  const factor100 = 100 / Number(exact.quantity_g)
  const kcalPer100g = +(Number(exact.kcal) * factor100).toFixed(2)
  const carbsPer100g = +(Number(exact.carbs_g) * factor100).toFixed(2)
  const fatPer100g = +(Number(exact.fat_g) * factor100).toFixed(2)
  if (isImplausibleFreshFruitHistory(foodName, kcalPer100g, carbsPer100g, fatPer100g)) {
    return null
  }
  return {
    food_db_id: exact.food_db_id as number,
    kcal_per_100g: kcalPer100g,
    protein_g: +(Number(exact.protein_g) * factor100).toFixed(2),
    carbs_g: carbsPer100g,
    fat_g: fatPer100g,
    fiber_g: 0,
    matched_log_id: exact.id,
    matched_food_name: exact.food_name,
  }
}

export async function calcMealMacros(
  supabase: ServiceClient,
  items: MealItemInput[],
  country: string = 'BR',
  /** ID do paciente — habilita reuso de alimentos do histórico do user. */
  userIdHint?: string,
): Promise<MealCalcResult> {
  const matched: MealItemMatched[] = []
  const userWarnings: string[] = []
  const auditWarnings: string[] = []
  const warnings = userWarnings // alias pra compat com pushes existentes que não classificou
  const totals = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 }

  for (let it of items) {
    // ── PRIORIDADE -4: PROPOSTA JÁ APROVADA PELO PACIENTE ──────────────────
    // O pending é a fronteira de aprovação. Reconsultar TACO/histórico no tap
    // pode gravar números diferentes dos que acabaram de ser mostrados.
    const approved = it.approved_nutrition
    const approvedValuesValid =
      approved != null &&
      [approved.kcal, approved.protein_g, approved.carbs_g, approved.fat_g].every(
        (value) => Number.isFinite(value) && value >= 0,
      )
    const approvedHasImpossibleDensity =
      approved != null &&
      approvedValuesValid &&
      it.quantity_g > 0 &&
      hasImpossibleKcalDensity(approved.kcal, it.quantity_g)
    if (approved && approvedHasImpossibleDensity) {
      const kcalDensity = approved.kcal / it.quantity_g
      auditWarnings.push(
        `"${it.food_name}" ignorou nutrição do pending com densidade fisicamente impossível (${approved.kcal} kcal em ${it.quantity_g}g; ${kcalDensity.toFixed(1)} kcal/g).`,
      )
      userWarnings.push(
        `Os valores aprovados para "${it.food_name}" parecem incompatíveis com a quantidade, então recalculei pela referência nutricional do alimento.`,
      )
      if (userIdHint) {
        await supabase.from('product_events').insert({
          user_id: userIdHint,
          event: 'meal_calc.approved_nutrition_rejected',
          properties: {
            food_name: it.food_name,
            quantity_g: it.quantity_g,
            approved_kcal: approved.kcal,
            kcal_per_g: +kcalDensity.toFixed(2),
            reason: 'physically_impossible_density',
          },
        })
      }
      it = { ...it, approved_nutrition: undefined, user_kcal: undefined }
    }
    if (approved && it.quantity_g > 0 && approvedValuesValid && !approvedHasImpossibleDensity) {
      const approvedSource = approved.source ?? 'pending_approved'
      const nat = naturalUnit(it.food_name, it.quantity_g)
      const kcal = +approved.kcal.toFixed(1)
      const protein = +approved.protein_g.toFixed(2)
      const carbs = +approved.carbs_g.toFixed(2)
      const fat = +approved.fat_g.toFixed(2)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: `[pending aprovado: ${approvedSource}]`,
        matched_taco_id: approved.food_db_id ?? null,
        quantity_g: it.quantity_g,
        kcal,
        protein_g: protein,
        carbs_g: carbs,
        fat_g: fat,
        fiber_g: 0,
        similarity: 1,
        source: approvedSource,
        display_qty: nat.display_qty,
        display_unit: nat.display_unit,
      })
      totals.kcal += kcal
      totals.protein_g += protein
      totals.carbs_g += carbs
      totals.fat_g += fat
      auditWarnings.push(`"${it.food_name}" persistiu a nutrição aprovada no pending.`)
      continue
    }
    // ── PRIORIDADE -3: KCAL EXPLÍCITO DO PACIENTE (Bug Luciana 2026-06-16) ──
    // Quando o paciente disse "rap 10 : 70 calorias", o número de kcal é fonte
    // de verdade — override total do TACO/histórico/estimativa. P/C/F usam o
    // perfil canônico exato quando existe; caso contrário, usam a categoria
    // implícita, sempre re-escalonados pro novo total de kcal.
    //
    // Caso real: Luciana mandou "rap 10 : 70 calorias" 4× e o sistema gravou
    // wrap 140 kcal todas as vezes porque ignorava o número no texto. Aqui
    // o agente registra exatamente o que o paciente disse — sem segunda chance
    // do trigram dominar.
    if (it.user_kcal != null && it.user_kcal >= 0 && it.quantity_g > 0) {
      const kcalDensity = it.user_kcal / it.quantity_g
      if (hasImpossibleKcalDensity(it.user_kcal, it.quantity_g)) {
        auditWarnings.push(
          `"${it.food_name}" ignorou kcal explícita com densidade fisicamente impossível (${it.user_kcal} kcal em ${it.quantity_g}g; ${kcalDensity.toFixed(1)} kcal/g).`,
        )
        userWarnings.push(
          `O valor de ${it.user_kcal} kcal para ${it.quantity_g}g de "${it.food_name}" parece incompatível com a quantidade, então usei a referência nutricional do alimento.`,
        )
        if (userIdHint) {
          await supabase.from('product_events').insert({
            user_id: userIdHint,
            event: 'meal_calc.user_kcal_rejected',
            properties: {
              food_name: it.food_name,
              quantity_g: it.quantity_g,
              user_kcal: it.user_kcal,
              kcal_per_g: +kcalDensity.toFixed(2),
              reason: 'physically_impossible_density',
            },
          })
        }
        it = { ...it, user_kcal: undefined }
      }
    }
    if (it.user_kcal != null && it.user_kcal >= 0 && it.quantity_g > 0) {
      const canonical = await matchFood(supabase, it.food_name, country)
      const hasExactCanonicalBaseline =
        canonical.id != null &&
        canonical.kcal_per_100g != null &&
        canonical.kcal_per_100g > 0 &&
        normalizeFoodText(canonical.name_pt ?? '') === normalizeFoodText(it.food_name)
      const est = estimateMacros(it.food_name)
      const baselineKcalPer100g = hasExactCanonicalBaseline
        ? (canonical.kcal_per_100g ?? est.kcal)
        : est.kcal
      const baselineProteinPer100g = hasExactCanonicalBaseline
        ? (canonical.protein_g ?? 0)
        : est.protein
      const baselineCarbsPer100g = hasExactCanonicalBaseline ? (canonical.carbs_g ?? 0) : est.carbs
      const baselineFatPer100g = hasExactCanonicalBaseline ? (canonical.fat_g ?? 0) : est.fat
      const baselineFiberPer100g = hasExactCanonicalBaseline ? (canonical.fiber_g ?? 0) : est.fiber
      const baselineKcal = (baselineKcalPer100g * it.quantity_g) / 100
      // Ratio P/C/F do baseline (por unidade de kcal). Se baseline for 0 (raro),
      // grava kcal e P/C/F=0 — paciente forçou o valor exato.
      const ratio = baselineKcal > 0 ? it.user_kcal / baselineKcal : 0
      const scaledProt = +(((baselineProteinPer100g * it.quantity_g) / 100) * ratio).toFixed(2)
      const scaledCarb = +(((baselineCarbsPer100g * it.quantity_g) / 100) * ratio).toFixed(2)
      const scaledFat = +(((baselineFatPer100g * it.quantity_g) / 100) * ratio).toFixed(2)
      const scaledFib = +(((baselineFiberPer100g * it.quantity_g) / 100) * ratio).toFixed(2)
      const overrideKcal = +it.user_kcal.toFixed(1)
      const natU = naturalUnit(it.food_name, it.quantity_g)
      const baselineLabel = hasExactCanonicalBaseline
        ? `item canônico "${canonical.name_pt}"`
        : `categoria "${est.category}"`
      auditWarnings.push(
        `"${it.food_name}" usou kcal informado pelo paciente (${overrideKcal} kcal; baseline ${baselineLabel} ~${baselineKcal.toFixed(0)} kcal). P/C/F re-escalonados.`,
      )
      matched.push({
        food_name: it.food_name,
        matched_taco_name: `[kcal informado pelo paciente] ${canonical.name_pt ?? est.category}`,
        matched_taco_id: hasExactCanonicalBaseline ? canonical.id : null,
        quantity_g: it.quantity_g,
        kcal: overrideKcal,
        protein_g: scaledProt,
        carbs_g: scaledCarb,
        fat_g: scaledFat,
        fiber_g: scaledFib,
        similarity: 1.0,
        source: 'user_kcal',
        display_qty: natU.display_qty,
        display_unit: natU.display_unit,
      })
      totals.kcal += overrideKcal
      totals.protein_g += scaledProt
      totals.carbs_g += scaledCarb
      totals.fat_g += scaledFat
      totals.fiber_g += scaledFib
      continue
    }
    // ── PRIORIDADE -2: BEBIDA ZERO/DIET/LIGHT (Bug Luciana 2026-05-25) ──────
    // Roda ANTES de tudo. Se o nome já deixa claro que é refrigerante/bebida
    // zero ("coca zero", "guaraná diet", "refri light"), força macros ~0 e NÃO
    // deixa o trigram casar a versão cheia (coca-cola normal ~42 kcal/100g) e
    // gravar caloria que o paciente nem ingeriu. Detecção por categoria do
    // food_db ("bebidas") fica no fluxo de match abaixo, pra casos sem keyword.
    if (isZeroCalDrink(it.food_name)) {
      const natZero = naturalUnit(it.food_name, it.quantity_g)
      auditWarnings.push(
        `"${it.food_name}" tratado como bebida zero-caloria (forçado ~0 kcal — qualificador zero/diet/light + bebida).`,
      )
      matched.push({
        food_name: it.food_name,
        matched_taco_name: '[bebida zero]',
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        fiber_g: 0,
        similarity: 1.0,
        source: 'rule_based',
        display_qty: natZero.display_qty,
        display_unit: natZero.display_unit,
      })
      continue
    }
    // ── PRIORIDADE -1: MAPA DE CORREÇÕES DO PACIENTE (Roberto 2026-05-14) ───
    // Roda ANTES de tudo. Se o paciente já corrigiu esse alimento ("batata" →
    // "mandioca"), remapeia o nome aqui. Precedência: correção > histórico >
    // trigram > estimativa.
    //   - custom_macros presente → usa direto (alimento específico do paciente).
    //   - sem custom_macros → só remapeia o nome; o resto do pipeline (histórico
    //     /trigram) resolve os macros pro nome corrigido.
    //   - needs_confirmation (status=learning, 1ª correção) → aplica MAS adiciona
    //     user_warning pro agente confirmar com o paciente.
    if (userIdHint) {
      const corr = await lookupFoodCorrection(supabase, userIdHint, it.food_name)
      // 2026-06-09: status='learning' (confirmed_count=1) NÃO APLICA mais
      // silencioso. Bug observado Amanda+Paulo: 1 correção pontual virou regra
      // eterna ("ovo cozido"→"ovo frito" forçou ovo frito mesmo Amanda dizendo
      // cozido 3× depois). Agora só 'active' (count≥2) aplica. 'learning' fica
      // só pra audit/observabilidade — paciente precisa repetir mesma correção
      // antes de virar regra automática.
      if (corr && corr.needs_confirmation) {
        auditWarnings.push(
          `"${it.food_name}" tem correção pendente "${corr.corrected_to}" (status=learning, count=1) — NÃO aplicada automaticamente, paciente precisa repetir pra virar active.`,
        )
      }
      if (corr && !corr.needs_confirmation) {
        if (corr.custom_macros) {
          const f = it.quantity_g / 100
          const kcal = +(corr.custom_macros.kcal_per_100g * f).toFixed(1)
          const protein = +(corr.custom_macros.protein_g * f).toFixed(2)
          const carbs = +(corr.custom_macros.carbs_g * f).toFixed(2)
          const fat = +(corr.custom_macros.fat_g * f).toFixed(2)
          const nat = naturalUnit(corr.corrected_to, it.quantity_g)
          matched.push({
            food_name: corr.corrected_to,
            matched_taco_name: `[correção do paciente] ${it.food_name} → ${corr.corrected_to}`,
            matched_taco_id: null,
            quantity_g: it.quantity_g,
            kcal,
            protein_g: protein,
            carbs_g: carbs,
            fat_g: fat,
            fiber_g: 0,
            similarity: 1.0,
            source: 'user_correction',
            display_qty: nat.display_qty,
            display_unit: nat.display_unit,
          })
          totals.kcal += kcal
          totals.protein_g += protein
          totals.carbs_g += carbs
          totals.fat_g += fat
          // Caso Roberto 2026-05-19: correção "chocolate quente → leite com whey"
          // está active com confirmed_count=4 mas LLM continuava dizendo "Heads
          // up: identifiquei leite com whey pelo seu histórico" toda manhã. O
          // auditWarning ficava no result da tool e o LLM (Sonnet 4.6) achava
          // que era pra mencionar. Solução: SILENCIAR auditWarning quando
          // correção é well_established (active + confirmed>=3) — paciente já
          // sabe, não precisa de aviso repetido.
          if (!corr.is_well_established) {
            auditWarnings.push(
              `"${it.food_name}" remapeado pra "${corr.corrected_to}" via correção aprendida do paciente (macro customizado).`,
            )
          }
          if (corr.needs_confirmation) {
            userWarnings.push(
              `Registrei "${corr.corrected_to}" porque você corrigiu isso antes. Se hoje for "${it.food_name}" mesmo, é só me avisar.`,
            )
          }
          continue
        }
        // Sem macro customizado: só remapeia o nome e deixa o resto do pipeline
        // resolver os macros do nome corrigido.
        if (!corr.is_well_established) {
          auditWarnings.push(
            `"${it.food_name}" remapeado pra "${corr.corrected_to}" via correção aprendida do paciente.`,
          )
        }
        if (corr.needs_confirmation) {
          userWarnings.push(
            `Registrei "${corr.corrected_to}" porque você corrigiu isso antes. Se hoje for "${it.food_name}" mesmo, é só me avisar.`,
          )
        }
        it = { ...it, food_name: corr.corrected_to }
      }
    }

    // Um item canônico EXATO é mais confiável que um valor herdado do
    // histórico. Isso impede que um override antigo contaminado (por exemplo,
    // arroz de 70 kcal) seja reciclado indefinidamente. Matches apenas fuzzy
    // ainda podem se beneficiar do histórico pessoal compatível.
    const prefetchedMatch = await matchFood(supabase, it.food_name, country)
    const hasExactCanonicalMatch =
      prefetchedMatch.id != null &&
      prefetchedMatch.kcal_per_100g != null &&
      normalizeFoodText(prefetchedMatch.name_pt ?? '') === normalizeFoodText(it.food_name)

    // ── PRIORIDADE 0: HISTÓRICO DO PACIENTE (Roberto 2026-05-13) ────────────
    // Antes do trigram, checa se o paciente já registrou esse alimento antes.
    // Se sim, usa esses macros — evita "leite com whey" virar achocolatado
    // toda vez. Após correção via replace=true, o log atualizado vira a memória.
    if (userIdHint && !hasExactCanonicalMatch) {
      const hist = await lookupUserHistory(supabase, userIdHint, it.food_name)
      if (hist) {
        const f = it.quantity_g / 100
        const kcal = +(hist.kcal_per_100g * f).toFixed(1)
        const protein = +(hist.protein_g * f).toFixed(2)
        const carbs = +(hist.carbs_g * f).toFixed(2)
        const fat = +(hist.fat_g * f).toFixed(2)
        const nat = naturalUnit(it.food_name, it.quantity_g)
        matched.push({
          food_name: it.food_name,
          matched_taco_name: `[histórico] ${hist.matched_food_name}`,
          matched_taco_id: hist.food_db_id,
          quantity_g: it.quantity_g,
          kcal,
          protein_g: protein,
          carbs_g: carbs,
          fat_g: fat,
          fiber_g: 0,
          similarity: 1.0,
          source: 'history',
          display_qty: nat.display_qty,
          display_unit: nat.display_unit,
        })
        totals.kcal += kcal
        totals.protein_g += protein
        totals.carbs_g += carbs
        totals.fat_g += fat
        auditWarnings.push(
          `"${it.food_name}" reusado do histórico do paciente (registro anterior: "${hist.matched_food_name}").`,
        )
        continue
      }
    }
    // ───────────────────────────────────────────────────────────────────────
    // Sanity 1: nome composto ("ovo com azeite", "leite com whey", "arroz e feijão").
    // Antes: rejeitava direto e zerava. Agora: tenta auto-split, busca cada parte
    // separadamente, divide a quantidade proporcionalmente. Se TODAS as partes
    // matcham bem, agrega os macros. Senão rejeita com warning.
    //
    // PRECEDÊNCIA: se o nome COMPLETO bate exato no food_db (ex: "leite com whey"
    // tem alias próprio com sim>=0.85), usa o match direto e PULA auto-split.
    // Sem isso, "leite com whey" (alias 95 kcal/100g) era zerado porque "whey"
    // sozinho tem sim=0.38 < 0.45 e o composite-reject preempta o match perfeito.
    const isComposite =
      / com | e | \+ |\bcom\s+|^com\s+/i.test(` ${it.food_name} `) &&
      it.food_name.split(/\s+/).length >= 3
    if (isComposite) {
      const directMatch = prefetchedMatch
      if (
        directMatch.id != null &&
        directMatch.kcal_per_100g != null &&
        directMatch.similarity >= 0.85
      ) {
        // Match completo bom — segue pelo caminho não-composite (queda abaixo)
      } else {
        const parts = it.food_name
          .split(/ com | e | \+ /i)
          .map((s) => s.trim())
          .filter((s) => s.length >= 2)
        // Dividir qty igual entre as partes
        const partQty = it.quantity_g / parts.length
        const partMatches: Array<{ name: string; m: Awaited<ReturnType<typeof matchFood>> }> = []
        for (const p of parts) {
          let pm = await matchFood(supabase, p, country)
          // FALLBACK (Erika+Amanda 2026-05-15/16): se match da parte completa
          // ficou baixo, tenta a ÚLTIMA palavra "substantiva" (ignorando
          // preposições de/do/da/com). Ex: "lasanha de abóbora" → tenta "abóbora"
          // que é entry específica do food_db. Exige sim>=0.55 pra evitar falso
          // match (mais conservador que match composto inicial).
          if (pm.similarity < 0.45 || pm.kcal_per_100g == null) {
            const words = p
              .split(/\s+/)
              .filter((w) => w.length >= 3 && !/^(de|do|da|dos|das|com|e|ou|na|no|à|ao)$/i.test(w))
            for (const w of [...words].reverse()) {
              const m2 = await matchFood(supabase, w, country)
              if (m2.similarity >= 0.55 && m2.kcal_per_100g != null) {
                pm = m2
                break
              }
            }
          }
          partMatches.push({ name: p, m: pm })
        }
        // Conta partes BOAS (sim>=0.45 + kcal valido). Estratégia em camadas:
        //  - 100% boas: agrega tudo (caminho original)
        //  - parcial: agrega só as boas com warning ao paciente
        //  - threshold de parcial:
        //      2-3 partes: >=50% (>=1 ou 2 boas)
        //      4-5 partes: >=2 boas (40-50%)
        //      6+ partes: >=33% (composto super complexo aceita mais perda)
        const goodMatches = partMatches.filter(
          (pm) => pm.m.similarity >= 0.45 && pm.m.kcal_per_100g != null,
        )
        const allGood = goodMatches.length === partMatches.length
        const minGoodForPartial =
          partMatches.length >= 6
            ? Math.ceil(partMatches.length / 3)
            : partMatches.length >= 4
              ? 2
              : Math.ceil(partMatches.length / 2)
        const someGood = !allGood && goodMatches.length >= minGoodForPartial
        if (allGood) {
          // Adiciona cada parte como item separado, com nome composto preservado em matched_taco_name
          let totalKcal = 0,
            totalProt = 0,
            totalCarbs = 0,
            totalFat = 0,
            totalFib = 0
          for (const pm of partMatches) {
            const f = partQty / 100
            const kcal = +((pm.m.kcal_per_100g ?? 0) * f).toFixed(1)
            const prot = +((pm.m.protein_g ?? 0) * f).toFixed(2)
            const carb = +((pm.m.carbs_g ?? 0) * f).toFixed(2)
            const fat = +((pm.m.fat_g ?? 0) * f).toFixed(2)
            const fib = +((pm.m.fiber_g ?? 0) * f).toFixed(2)
            totalKcal += kcal
            totalProt += prot
            totalCarbs += carb
            totalFat += fat
            totalFib += fib
          }
          const natComp = naturalUnit(it.food_name, it.quantity_g)
          matched.push({
            food_name: it.food_name,
            matched_taco_name: partMatches.map((pm) => pm.m.name_pt).join(' + '),
            matched_taco_id: null,
            quantity_g: it.quantity_g,
            kcal: +totalKcal.toFixed(1),
            protein_g: +totalProt.toFixed(2),
            carbs_g: +totalCarbs.toFixed(2),
            fat_g: +totalFat.toFixed(2),
            fiber_g: +totalFib.toFixed(2),
            similarity: Math.min(...partMatches.map((pm) => pm.m.similarity)),
            source: 'canonical_composite',
            display_qty: natComp.display_qty,
            display_unit: natComp.display_unit,
          })
          totals.kcal += totalKcal
          totals.protein_g += totalProt
          totals.carbs_g += totalCarbs
          totals.fat_g += totalFat
          totals.fiber_g += totalFib
          auditWarnings.push(
            `"${it.food_name}" auto-dividido em ${partMatches.map((pm) => pm.m.name_pt).join(' + ')} (qty ${partQty.toFixed(0)}g cada).`,
          )
          continue
        }
        // Algumas partes OK (mas não todas) — agrega só as boas com warning.
        // Casos reais (sessão 2026-05-19): "lasanha de abóbora com queijo"
        // (Erika 16/05), "muffin de banana com castanhas" (Amanda 16/05).
        // Em vez de zerar TUDO, usa as partes que matcharam (proporcional
        // a partes boas) e avisa o paciente do que faltou.
        if (someGood) {
          const partQtyGood = it.quantity_g / goodMatches.length
          let totalKcal = 0,
            totalProt = 0,
            totalCarbs = 0,
            totalFat = 0,
            totalFib = 0
          for (const pm of goodMatches) {
            const f = partQtyGood / 100
            totalKcal += (pm.m.kcal_per_100g ?? 0) * f
            totalProt += (pm.m.protein_g ?? 0) * f
            totalCarbs += (pm.m.carbs_g ?? 0) * f
            totalFat += (pm.m.fat_g ?? 0) * f
            totalFib += (pm.m.fiber_g ?? 0) * f
          }
          const missing = partMatches.filter((pm) => !goodMatches.includes(pm)).map((pm) => pm.name)
          const natComp = naturalUnit(it.food_name, it.quantity_g)
          matched.push({
            food_name: it.food_name,
            matched_taco_name: goodMatches.map((pm) => pm.m.name_pt).join(' + ') + ' (parcial)',
            matched_taco_id: null,
            quantity_g: it.quantity_g,
            kcal: +totalKcal.toFixed(1),
            protein_g: +totalProt.toFixed(2),
            carbs_g: +totalCarbs.toFixed(2),
            fat_g: +totalFat.toFixed(2),
            fiber_g: +totalFib.toFixed(2),
            similarity: Math.min(...goodMatches.map((pm) => pm.m.similarity)),
            source: 'canonical_composite_partial',
            display_qty: natComp.display_qty,
            display_unit: natComp.display_unit,
          })
          totals.kcal += totalKcal
          totals.protein_g += totalProt
          totals.carbs_g += totalCarbs
          totals.fat_g += totalFat
          totals.fiber_g += totalFib
          warnings.push(
            `Calculei "${it.food_name}" usando só [${goodMatches.map((g) => g.m.name_pt).join(', ')}] — não identifiquei ${missing.length > 1 ? 'as partes' : 'a parte'} ${missing.map((p) => `"${p}"`).join(' e ')}. Se faltou algo importante, me corrija com o nome certo dessa parte e a quantidade.`,
          )
          continue
        }
        // Nenhuma ou pouquíssimas partes OK — rejeição (composite_rejected).
        warnings.push(
          `Não consegui identificar "${it.food_name}" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: "leite 250ml" e "whey 30g"). Não foi possível calcular as calorias desse item ainda.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: '',
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: 0,
          source: 'composite_rejected',
        })
        continue
      } // fecha else (auto-split)
      // Se chegou aqui, directMatch é bom — cai pro fluxo de match direto abaixo
    }

    const m = prefetchedMatch
    const factor = it.quantity_g / 100

    // Anchor check: o ingrediente principal da query precisa aparecer no
    // nome do match. Bloqueia bug "arroz refogado" → "espinafre refogado".
    // Se a âncora não aparece, força fallback pra estimativa por categoria.
    const anchor = extractAnchor(it.food_name)
    const matchedNameLower = normalizeFoodText(m.name_pt ?? '')
    const anchorMatches = anchor == null || matchedNameLower.includes(anchor)
    const fruitSweetMismatch = isSweetDerivedFruitMismatch(it.food_name, m.name_pt, m.category)
    const nutritionModifierMismatch =
      m.name_pt != null && hasNutritionModifierConflict(it.food_name, m.name_pt)

    // Threshold dinâmico por tamanho da query:
    // - Queries curtas (1-2 palavras, ≤15 chars) tendem a ter similarity baixa
    //   contra entries longos no DB (ex: "whey" vs "whey protein" = 0.38).
    //   Threshold mais permissivo evita fallback prematuro pra estimateMacros.
    // - Queries longas (>15 chars / 3+ palavras) usam threshold mais rigoroso
    //   pra evitar matches catastróficos (ex: "ovos cozidos com fio de azeite"
    //   matchando azeite por causa do trigram parcial).
    const queryWords = it.food_name.trim().split(/\s+/).length
    const queryLen = it.food_name.trim().length
    const isShortQuery = queryWords <= 2 || queryLen <= 15
    const requestedFruitKey = simpleFreshFruitKey(it.food_name)
    const matchedFruitKey = simpleFreshFruitKey(m.name_pt ?? '')
    const sameFreshFruit = requestedFruitKey != null && requestedFruitKey === matchedFruitKey
    const matchThreshold = sameFreshFruit ? 0.2 : isShortQuery ? 0.3 : 0.45
    if (
      m.id != null &&
      m.kcal_per_100g != null &&
      m.similarity >= matchThreshold &&
      anchorMatches &&
      !fruitSweetMismatch &&
      !nutritionModifierMismatch
    ) {
      // Camada 2 do guard de bebida zero (Bug Luciana 2026-05-25): nome sem
      // keyword de bebida ("zero" + nome genérico) mas que casou um item de
      // categoria "bebidas" no food_db. Aqui usamos a CATEGORIA do match pra
      // forçar ~0 antes de aceitar a caloria cheia do alimento-base.
      if (isZeroCalDrink(it.food_name, m.category)) {
        const natZ = naturalUnit(it.food_name, it.quantity_g)
        auditWarnings.push(
          `"${it.food_name}" tratado como bebida zero-caloria via categoria do match "${m.category}" (forçado ~0 kcal em vez de ${(m.kcal_per_100g * factor).toFixed(1)}).`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '[bebida zero]',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'rule_based',
          display_qty: natZ.display_qty,
          display_unit: natZ.display_unit,
        })
        continue
      }

      const kcal = +(m.kcal_per_100g * factor).toFixed(1)
      const protein = +((m.protein_g ?? 0) * factor).toFixed(2)
      const carbs = +((m.carbs_g ?? 0) * factor).toFixed(2)
      const fat = +((m.fat_g ?? 0) * factor).toFixed(2)
      const fiber = +((m.fiber_g ?? 0) * factor).toFixed(2)

      // Sanity 2: densidade calórica catastrófica. Alimento >5 kcal/g só faz
      // sentido pra gorduras/oleaginosas/embutidos densos / queijos gordos.
      //
      // Detecção PRINCIPAL via category do food_db (mais robusto que regex).
      // Categorias que justificam >5 kcal/g naturalmente:
      //   - gorduras (óleos, azeite, manteiga)
      //   - oleaginosas / sementes (castanhas, nozes, chia, linhaça)
      //   - doces (chocolates densos)
      // Pra carnes / laticínios / outros, ainda usa regex backup pra cobrir
      // casos específicos (bacon, parmesão, etc) que NÃO têm categoria dedicada.
      //
      // Histórico: regex sozinho falhava em bacon (carnes), parmesão (lacteos)
      // etc. Categoria + regex juntos cobrem todos casos legítimos.
      const kcalPerG = (m.kcal_per_100g ?? 0) / 100
      const lowerName = it.food_name.toLowerCase()
      const matchCat = normalizeFoodText(m.category ?? '')
      const categoryAllowsHighKcal = [
        'gorduras',
        'oleaginosas',
        'sementes',
        'doces',
        // Categorias oficiais do USDA SR Legacy. Sem estas equivalências,
        // azeites, manteigas, castanhas e chocolates em inglês eram encontrados
        // corretamente e depois descartados pelo sanity check em português.
        'fats and oils',
        'nut and seed products',
        'sweets',
        'snacks',
        'baked products',
        'dairy and egg products',
        'sausages and luncheon meats',
      ].includes(matchCat)
      const isFatLike =
        categoryAllowsHighKcal ||
        /azeite|[óo]leo|manteiga|margarina|maionese|gordura|nozes|castanha|am[êe]ndoa|amendoim|pasta de amendoim|nutella|tahini|abacate|coco|chia|linha[çc]a|gergelim|girassol|abóbora|bacon|toucinho|torresmo|salame|chouri[çc]o|sal[áa]mi|pepperoni|mortadela|paio|presunto parma|copa|linguiça|chocolate|brigadeiro|beijinho|trufa|queijo parmes[ãa]o|parmes[ãa]o|gorgonzola|brie|camembert|provolone|gruy[èe]re|requeij[ãa]o cremoso|cream cheese|catupiry|nata|creme de leite|leite de coco|granola/.test(
          lowerName,
        )
      if (kcalPerG > 5 && !isFatLike) {
        warnings.push(
          `Não tenho certeza sobre "${it.food_name}" — o valor calórico encontrado parece alto demais pro que o paciente descreveu. Peça pra ele confirmar ou detalhar melhor o alimento. Não calculei as calorias desse item ainda.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'category_mismatch',
        })
        continue
      }

      // Sanity 3: alimento c/ proteína esperada (carnes, peixes, ovos, embutidos,
      // laticínios proteicos) não pode ter protein_g=0. Match errado se sim.
      const expectsProtein =
        /\bovo|\bfrango|\bcarne|\bpeixe|\bwhey|\batum|\bfil[ée]|\bpicanha|\bbife|\bsalm[ãa]o|\btil[áa]pia|\bsalsicha|\blingu[ií]ça|\bbacon|\bpresunto|\bsalame|\bmortadela|\bperu|\bpernil|\bhamb[uú]rguer|\bnugget|\bisca|\bpat[ée]|\bmussarela|\bricota|\bcoalho|\bsardinha|\bcamar[ãa]o|\bcord[ãa]o\s+azul|\bcordeiro|\bcostela/.test(
          lowerName,
        )
      if (expectsProtein && (m.protein_g ?? 0) < 5) {
        warnings.push(
          `Não tenho certeza sobre "${it.food_name}" — esperava um alimento rico em proteína mas o valor encontrado não bate. Peça pro paciente confirmar ou detalhar. Não calculei as calorias desse item ainda.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'protein_mismatch',
        })
        continue
      }

      // Sanity 4 — DENSIDADE CALÓRICA BAIXA DEMAIS (Roberto 2026-06-05):
      // espelho do sanity 2 mas pro lado oposto. Bug observado: "frango à
      // milanesa" matchou (sim<threshold mas anchor passou) algo com 165 kcal/100g.
      // Real é ~280. Resultado: paciente registra menos kcal que ingeriu.
      //
      // Categoria implícita pelo nome → mínimo esperado de kcal/100g. Se match
      // veio abaixo do piso, REJEITA e cai no fallback (estimateMacros) que
      // tem categorias defensivas (empanado_frango=280, etc).
      const minKcalRules: Array<{ pattern: RegExp; minKcal: number; label: string }> = [
        {
          // Empanados/fritos brasileiros — piso 200 kcal/100g
          pattern:
            /(milanesa|empanad[oa]s?|parmegiana|parmigiana|(?:^|\s)[àa]\s+passarinho|schnitzel|nuggets?|escalope|cordon\s*bleu)/,
          minKcal: 200,
          label: 'empanado/frito',
        },
        {
          // Gorduras puras — piso 500 (óleo/azeite/manteiga ~870-900)
          pattern: /^(azeite|óleo de \w+|manteiga|margarina|banha)$/,
          minKcal: 500,
          label: 'gordura pura',
        },
      ]
      const subRule = minKcalRules.find((r) => r.pattern.test(lowerName))
      if (subRule && (m.kcal_per_100g ?? 0) < subRule.minKcal) {
        auditWarnings.push(
          `"${it.food_name}" rejeitou match em "${m.name_pt}" (${m.kcal_per_100g} kcal/100g) — abaixo do piso ${subRule.minKcal} pra categoria "${subRule.label}". Caindo em fallback estimateMacros.`,
        )
        const est = estimateMacros(it.food_name)
        const estKcal = +((est.kcal * it.quantity_g) / 100).toFixed(1)
        const estProt = +((est.protein * it.quantity_g) / 100).toFixed(2)
        const estCarbs = +((est.carbs * it.quantity_g) / 100).toFixed(2)
        const estFat = +((est.fat * it.quantity_g) / 100).toFixed(2)
        const estFiber = +((est.fiber * it.quantity_g) / 100).toFixed(2)
        const natR = naturalUnit(it.food_name, it.quantity_g)
        matched.push({
          food_name: it.food_name,
          matched_taco_name: `[estimativa ${est.category}]`,
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: estKcal,
          protein_g: estProt,
          carbs_g: estCarbs,
          fat_g: estFat,
          fiber_g: estFiber,
          similarity: 0,
          source: 'llm_estimate',
          display_qty: natR.display_qty,
          display_unit: natR.display_unit,
        })
        totals.kcal += estKcal
        totals.protein_g += estProt
        totals.carbs_g += estCarbs
        totals.fat_g += estFat
        totals.fiber_g += estFiber
        continue
      }

      const nat = naturalUnit(it.food_name, it.quantity_g)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: m.name_pt ?? '',
        matched_taco_id: m.id,
        quantity_g: it.quantity_g,
        kcal,
        protein_g: protein,
        carbs_g: carbs,
        fat_g: fat,
        fiber_g: fiber,
        similarity: m.similarity,
        source: canonicalSource(it.food_name, m.name_pt),
        display_qty: nat.display_qty,
        display_unit: nat.display_unit,
      })

      totals.kcal += kcal
      totals.protein_g += protein
      totals.carbs_g += carbs
      totals.fat_g += fat
      totals.fiber_g += fiber

      if (m.similarity < 0.5) {
        auditWarnings.push(
          `Match com baixa confiança: "${it.food_name}" → "${m.name_pt}" (sim=${m.similarity.toFixed(2)})`,
        )
      }
    } else {
      // Loga rejeição por anchor mismatch pra rastreabilidade no /audit
      if (
        m.id != null &&
        m.kcal_per_100g != null &&
        m.similarity >= matchThreshold &&
        (!anchorMatches || fruitSweetMismatch || nutritionModifierMismatch)
      ) {
        if (nutritionModifierMismatch) {
          auditWarnings.push(
            `"${it.food_name}" rejeitou match em "${m.name_pt}" (sim=${m.similarity.toFixed(2)}) — preparo incompatível.`,
          )
        } else if (fruitSweetMismatch) {
          auditWarnings.push(
            `"${it.food_name}" rejeitou match em "${m.name_pt}" (sim=${m.similarity.toFixed(2)}) — fruta fresca simples não deve casar com doce derivado.`,
          )
        } else {
          auditWarnings.push(
            `"${it.food_name}" rejeitou match em "${m.name_pt}" (sim=${m.similarity.toFixed(2)}) — âncora "${anchor}" não aparece no nome.`,
          )
        }
      }
      // ────────────────────────────────────────────────────────────────────
      // FALLBACK 1: reusa do histórico do paciente (Roberto pediu: "pode já
      // colocar pra ele usar alimentos já informados ou identificados nas
      // próximas refeições").
      //
      // Fix Q3 Roberto 2026-06-03: antes pegava só o último meal_log e aplicava
      // ratio direto — chamadas consecutivas podiam pegar logs diferentes, e
      // kcal variava entre propostas do MESMO turno (caso Luciana 02/06:
      // alface crespa 6→4 kcal, milho 34→14 kcal). Agora calcula MEDIANA de
      // kcal/100g (e dos macros) sobre todos os logs do paciente do mesmo
      // food_name nos últimos 30d. Mediana é resistente a outliers + estável
      // entre chamadas (mesmos logs entram → mesmo resultado sai).
      // ────────────────────────────────────────────────────────────────────
      const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      // biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
      const supaTyped = supabase as any
      const { data: prior, error: priorError } = await supaTyped
        .from('meal_logs')
        .select(
          'food_name, food_db_id, quantity_g, kcal, protein_g, carbs_g, fat_g, source, user_id, food_db:food_db_id(is_verified)',
        )
        .eq('user_id', userIdHint ?? '_no_user_')
        .ilike('food_name', it.food_name)
        .gte('created_at', lookback)
        .in('source', [...TRUSTED_HISTORY_SOURCES])
        .order('created_at', { ascending: false })
        .limit(20)
      if (priorError) {
        throw nutritionSourceError(priorError, 'median food history lookup failed')
      }
      if (prior && prior.length > 0) {
        const compatiblePrior = (
          prior as Array<{
            food_name: string
            food_db_id: number | null
            quantity_g: number
            kcal: number
            protein_g: number
            carbs_g: number
            fat_g: number
            source: string | null
            food_db:
              | { is_verified?: boolean | null }
              | Array<{ is_verified?: boolean | null }>
              | null
          }>
        ).filter(
          (p) =>
            isTrustedHistorySource(p.source) &&
            Number.isInteger(p.food_db_id) &&
            hasVerifiedFoodReference(p.food_db) &&
            normalizeFoodText(p.food_name) === normalizeFoodText(it.food_name) &&
            !hasNutritionModifierConflict(it.food_name, p.food_name),
        )
        if (compatiblePrior.length !== prior.length) {
          auditWarnings.push(
            `"${it.food_name}" ignorou ${prior.length - compatiblePrior.length} registro(s) do histórico por fonte não confiável ou diferença de preparo/composição.`,
          )
        }
        // Normaliza tudo pra per-100g (kcal/100g, P/100g, C/100g, G/100g),
        // descarta linhas com quantity_g ≤ 0 (lixo).
        const canonicalIds = new Set(compatiblePrior.map((p) => p.food_db_id as number))
        if (canonicalIds.size > 1) {
          auditWarnings.push(
            `"${it.food_name}" ignorou histórico associado a referências canônicas divergentes.`,
          )
        }
        const historyFoodDbId =
          canonicalIds.size === 1 ? (canonicalIds.values().next().value ?? null) : null
        const per100g = (historyFoodDbId == null ? [] : compatiblePrior)
          .filter((p) => Number(p.quantity_g) > 0)
          .map((p) => {
            const q = Number(p.quantity_g)
            return {
              kcal: (Number(p.kcal) / q) * 100,
              protein_g: (Number(p.protein_g) / q) * 100,
              carbs_g: (Number(p.carbs_g) / q) * 100,
              fat_g: (Number(p.fat_g) / q) * 100,
            }
          })
        if (per100g.length > 0) {
          const median = (arr: number[]): number => {
            const sorted = [...arr].sort((a, b) => a - b)
            const mid = Math.floor(sorted.length / 2)
            return sorted.length % 2 === 0 ? (sorted[mid - 1]! + sorted[mid]!) / 2 : sorted[mid]!
          }
          const medKcal100 = median(per100g.map((p) => p.kcal))
          const medProt100 = median(per100g.map((p) => p.protein_g))
          const medCarb100 = median(per100g.map((p) => p.carbs_g))
          const medFat100 = median(per100g.map((p) => p.fat_g))
          if (isImplausibleFreshFruitHistory(it.food_name, medKcal100, medCarb100, medFat100)) {
            auditWarnings.push(
              `"${it.food_name}" ignorou histórico implausível para fruta fresca (${medKcal100.toFixed(0)} kcal/100g).`,
            )
          } else {
            const q = it.quantity_g
            const reKcal = +((medKcal100 * q) / 100).toFixed(1)
            const reProt = +((medProt100 * q) / 100).toFixed(2)
            const reCarb = +((medCarb100 * q) / 100).toFixed(2)
            const reFat = +((medFat100 * q) / 100).toFixed(2)
            auditWarnings.push(
              `"${it.food_name}" reusado de ${per100g.length} registros (mediana: ${medKcal100.toFixed(0)} kcal/100g → ${reKcal} kcal pra ${q}g).`,
            )
            // Loga pra auditoria (Roberto 2026-06-03): rastreabilidade de
            // quando reuso de histórico foi usado em vez de TACO.
            await supaTyped.from('product_events').insert({
              user_id: userIdHint ?? null,
              event: 'meal_calc.history_reused',
              properties: {
                food_name: it.food_name,
                source_log_count: per100g.length,
                kcal_per_100g_median: +medKcal100.toFixed(1),
                quantity_g: q,
                kcal_result: reKcal,
              },
            })
            const natRe = naturalUnit(it.food_name, it.quantity_g)
            matched.push({
              food_name: it.food_name,
              matched_taco_name: '[reuso histórico]',
              matched_taco_id: historyFoodDbId,
              quantity_g: it.quantity_g,
              kcal: reKcal,
              protein_g: reProt,
              carbs_g: reCarb,
              fat_g: reFat,
              fiber_g: 0,
              similarity: 1.0,
              source: 'history',
              display_qty: natRe.display_qty,
              display_unit: natRe.display_unit,
            })
            totals.kcal += reKcal
            totals.protein_g += reProt
            totals.carbs_g += reCarb
            totals.fat_g += reFat
            continue
          }
        }
      }
      // ────────────────────────────────────────────────────────────────────
      // Produto/SKU com código sem referência exata no país: não invente uma
      // densidade por categoria. O rótulo é a única fonte segura e a proposta
      // fica bloqueada em zero até o paciente fornecê-lo.
      if (hasProductCodeIdentifier(it.food_name)) {
        userWarnings.push(
          `Não encontrei uma referência verificada para "${it.food_name}" neste país. Envie uma foto legível do rótulo para eu usar as calorias e os macros corretos.`,
        )
        auditWarnings.push(
          `"${it.food_name}" não recebeu estimativa porque contém um código comercial sem referência verificada no país do paciente.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: '',
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: 0,
          source: 'no_match',
        })
        continue
      }

      // ────────────────────────────────────────────────────────────────────
      // FALLBACK 2: sem reuso — ESTIMA por categoria (em vez de zerar).
      // ────────────────────────────────────────────────────────────────────
      const est = estimateMacros(it.food_name)
      const factor = it.quantity_g / 100
      const eKcal = +(est.kcal * factor).toFixed(1)
      const eProt = +(est.protein * factor).toFixed(2)
      const eCarb = +(est.carbs * factor).toFixed(2)
      const eFat = +(est.fat * factor).toFixed(2)
      const eFib = +(est.fiber * factor).toFixed(2)
      auditWarnings.push(
        `"${it.food_name}" sem match exato — estimando por categoria "${est.category}" (~${est.kcal} kcal/100g).`,
      )
      const natEst = naturalUnit(it.food_name, it.quantity_g)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: `[estimativa ${est.category}]`,
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: eKcal,
        protein_g: eProt,
        carbs_g: eCarb,
        fat_g: eFat,
        fiber_g: eFib,
        similarity: 0,
        source: 'llm_estimate',
        display_qty: natEst.display_qty,
        display_unit: natEst.display_unit,
      })
      totals.kcal += eKcal
      totals.protein_g += eProt
      totals.carbs_g += eCarb
      totals.fat_g += eFat
      totals.fiber_g += eFib
    }
  }

  return {
    items: matched,
    totals: roundTotals(totals),
    warnings: [...userWarnings, ...auditWarnings], // compat
    user_warnings: userWarnings,
    audit_warnings: auditWarnings,
  }
}

function roundTotals(t: {
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
}) {
  return {
    kcal: +t.kcal.toFixed(1),
    protein_g: +t.protein_g.toFixed(1),
    carbs_g: +t.carbs_g.toFixed(1),
    fat_g: +t.fat_g.toFixed(1),
    fiber_g: +t.fiber_g.toFixed(1),
  }
}
