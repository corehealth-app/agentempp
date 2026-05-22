/**
 * Validador de saída: parseia números numa resposta do LLM e compara
 * com valores reais do contexto. Nao BLOQUEIA — apenas audita em
 * product_events ('llm.numeric_mismatch').
 *
 * Defensa em camadas: mesmo com (a) dados pre-injetados, (b) regra
 * inviolavel e (c) tool consulta_metricas, ainda pode haver alucinacao
 * em edge cases. Este validador detecta e loga pra investigacao.
 *
 * Nao corrige automaticamente — autoregeneracao e arriscada (loop) e a
 * correcao ideal depende do contexto (re-prompt? truncar? marcar?).
 *
 * Criterio de divergencia: |claimed - real| / max(|real|, 1) > 0.10
 * (10% de erro relativo) OU diferenca absoluta > 30 pra valores baixos.
 */

import type { Json, ServiceClient } from '@mpp/db'
import { realDailyDeficit } from '@mpp/core'

// Config cache (60s) — controla threshold + on/off via /settings/global
interface ValidatorConfig {
  enabled: boolean
  threshold_pct: number
}
const DEFAULT_CONFIG: ValidatorConfig = { enabled: true, threshold_pct: 0.1 }
let cachedConfig: { config: ValidatorConfig; expiresAt: number } | null = null
const TTL_MS = 60_000

async function loadValidatorConfig(supabase: ServiceClient): Promise<ValidatorConfig> {
  const now = Date.now()
  if (cachedConfig && cachedConfig.expiresAt > now) return cachedConfig.config
  const { data } = (await supabase
    .from('global_config')
    .select('key, value')
    .like('key', 'numeric_validator.%')) as {
    data: Array<{ key: string; value: unknown }> | null
  }
  const merged: ValidatorConfig = { ...DEFAULT_CONFIG }
  for (const row of data ?? []) {
    if (row.key === 'numeric_validator.enabled' && typeof row.value === 'boolean') {
      merged.enabled = row.value
    } else if (row.key === 'numeric_validator.threshold_pct') {
      const n = Number(row.value)
      if (Number.isFinite(n) && n >= 0 && n <= 1) merged.threshold_pct = n
    }
  }
  cachedConfig = { config: merged, expiresAt: now + TTL_MS }
  return merged
}

interface NumericContext {
  calories_target?: number | null
  protein_target?: number | null
  imc?: number | null
  bmr?: number | null
  tdee?: number | null
  age?: number | null
  current_streak?: number | null
  level?: number | null
  calories_consumed_today?: number | null
  /** deficit_block atual do paciente (0-7700). Roberto 2026-05-15 viu o LLM
   * imprimir "Bloco 7700: 0/7700" enquanto DB tinha 2110 — validador não
   * cobria essa linha do card e nada pegou. */
  deficit_block?: number | null
}

interface MismatchFinding {
  field: string
  claimed: number
  real: number
  diff_abs: number
  diff_pct: number
  excerpt: string
}

const PATTERNS: Array<{
  field: keyof NumericContext
  re: RegExp
  /** Index do grupo de captura que tem o numero. */
  group: number
}> = [
  // "2.500 kcal", "2500 kcal", "meta de 2,500 kcal"
  { field: 'calories_target', re: /(?:meta|alvo|target|goal)\s*(?:hoje|de|é)?\s*(?:é\s*)?\*{0,2}\s*([\d]{3,5}(?:[.,][\d]{3})?)\s*\*{0,2}\s*kcal/gi, group: 1 },
  // protein_target só dispara quando o número está claramente no contexto de
  // META DIÁRIA (não per-refeição). 3 padrões:
  //   A) "Proteína: 125 / 178g" — card pós-registro (segundo número = meta)
  //   B) "meta de 178g de proteína" — keyword target ANTES do número
  //   C) "178g de proteína (meta|dia|diária)" — keyword target DEPOIS do número
  // Antes dispara em "Total refeição: 447 kcal | 11g proteína" (per-meal) → false positive.
  {
    field: 'protein_target',
    re: /prote[íi]na[:\s]*\*{0,2}\s*\d+(?:[.,]\d+)?\s*\*{0,2}\s*g?\s*\/\s*\*{0,2}\s*([\d]{2,4}(?:[.,]\d)?)\s*\*{0,2}\s*g/gi,
    group: 1,
  },
  {
    field: 'protein_target',
    re: /(?:meta|alvo|target|goal|objetiv[oa]|cota)[^\n]{0,40}?(\d{2,4}(?:[.,]\d)?)\s*g[^\n]{0,15}?prote[íi]na/gi,
    group: 1,
  },
  {
    field: 'protein_target',
    re: /(\d{2,4}(?:[.,]\d)?)\s*g\s*(?:de\s*)?prote[íi]na[^\n]{0,30}?(?:meta|alvo|dia|diár[ia]a|goal|target|por\s+dia)/gi,
    group: 1,
  },
  // D) "meta de proteína é Xg" (keyword + proteína ANTES do número)
  {
    field: 'protein_target',
    re: /(?:meta|alvo|target|goal|objetiv[oa]|cota)[^\n]{0,40}?prote[íi]na[^\n]{0,20}?(\d{2,4}(?:[.,]\d)?)\s*g\b/gi,
    group: 1,
  },
  // "IMC 25", "IMC de 25.3", "IMC: 25,3"
  { field: 'imc', re: /imc\s*[:=]?\s*(?:de\s*)?(\d{1,2}(?:[.,]\d)?)/gi, group: 1 },
  // "BMR 1973", "BMR de 1.973"
  { field: 'bmr', re: /bmr\s*[:=]?\s*(?:de\s*)?(\d{3,4}(?:[.,]\d{3})?)/gi, group: 1 },
  // "TDEE 3059", "TDEE de 3.059"
  { field: 'tdee', re: /tdee\s*[:=]?\s*(?:de\s*)?(\d{3,4}(?:[.,]\d{3})?)/gi, group: 1 },
  // "46 anos", "tem 46 anos"
  { field: 'age', re: /(\d{2})\s*anos\b/gi, group: 1 },
  // "streak de 5 dias", "5 dias seguidos"
  { field: 'current_streak', re: /streak\s*(?:de|atual)?\s*[:=]?\s*(\d{1,3})/gi, group: 1 },
  // Bloco 7700 — captura o valor ATUAL do bloco (lado esquerdo da fração).
  // Casos:
  //   "📊 Bloco 7700: **2.110 / 7.700 kcal (27%)**"  ← card pós-refeição
  //   "Bloco 7700: 0 / 7.700 kcal (0%)"
  //   "Bloco 7700 em andamento: **2110 kcal de 7700**"  ← formato numericLines
  //   "no bloco 7.700 ele tem 2110 kcal"
  // NÃO casa "7700 kcal" sozinho (target), nem "(27%)" (porcentagem).
  {
    field: 'deficit_block',
    re: /bloco\s*7\.?700\s*(?:em\s*andamento)?[:\s]*\*{0,2}\s*(\d{1,4}(?:[.,]\d{3})?)\s*\*{0,2}\s*(?:\/|de|kcal\s*de)/gi,
    group: 1,
  },
]

function parseNum(s: string): number {
  // "2.500" → 2500 (PT-BR), "2,500" → 2500
  const cleaned = s.replace(/\./g, '').replace(',', '.')
  return Number(cleaned)
}

// Padroes que indicam que o numero eh RESTANTE/FALTANTE/atingido em item,
// nao meta absoluta. Falsos positivos vistos:
//  - "Ainda faltam 32g de proteina pra fechar o dia" (Luciana 16/05)
//  - "Meta de proteina batida com folga - 23g num iogurte" (Luciana 18/05)
// Skip se algum desses padroes aparece nos 40 chars antes do match.
const RESTANTE_BEFORE_PATTERNS = [
  // Restante/faltante (numero eh quanto FALTA bater)
  /\bfalta(?:m|ndo|ram)?\b/i,
  /\bainda\b/i,
  /\brestam?\b/i,
  /\bsobra(?:m)?\b/i,
  /\bpra\s+fechar\b/i,
  /\bpara\s+fechar\b/i,
  /\bpra\s+bater\b/i,
  /\bpara\s+bater\b/i,
  // Meta JA atingida/batida (numero eh quanto FOI alem da meta, nao a meta)
  /\bbatid[oa]\b/i,
  /\batingid[oa]\b/i,
  /\bcumprid[oa]\b/i,
  /\bcom\s+folga\b/i,
  /\bsuperad[oa]\b/i,
  /\bultrapassad[oa]\b/i,
  // Numero descrevendo QUANTIDADE OBTIDA/ENTREGUE em item (nao meta)
  // Casos reais: "whey puxou 23g de proteina" (Paulo 19/05), "ovos
  // entregaram 13g" (Paulo 18/05), "frango garantiu 30g", "leite trouxe 8g"
  /\bpuxo(?:u|aram)\b/i,
  /\btrouxe(?:ram)?\b/i,
  /\bentrego(?:u|aram)\b/i,
  /\bgaranti[ou]\b/i,
  /\boferec[ei](?:u|am)\b/i,
  /\bsoma(?:ram|m)?\b.{0,15}$/i,
  /\bso(?:u|aram)\s+\d/i,
  /\bdeu\b/i,
  /\bderam\b/i,
  // Numero descrevendo QUANTIDADE EM UM ITEM (nao meta)
  // "23g num iogurte", "30g no leite", "15g numa banana"
  /\bnum?\s*$/i,
  /\bnum[ao]\s*$/i,
  /\bno\s*$/i,
  /\bem\s+um(?:a)?\s*$/i,
  /\bcontido\s+em\b/i,
  // Tabela de item ("Iogurte (170g): 10g P") - item antes vem antes do numero
  /\(\d+\s*g\)\s*[:|]\s*\d+\s*kcal\s*\|\s*$/i,
]

export function validateNumericClaims(
  text: string,
  ctx: NumericContext,
  thresholdPct = 0.1,
): MismatchFinding[] {
  const findings: MismatchFinding[] = []
  for (const { field, re, group } of PATTERNS) {
    const real = ctx[field]
    if (real == null) continue
    re.lastIndex = 0
    let match: RegExpExecArray | null
    while ((match = re.exec(text)) !== null) {
      const claimedRaw = match[group]
      if (!claimedRaw) continue
      const claimed = parseNum(claimedRaw)
      if (!Number.isFinite(claimed)) continue

      // Skip se eh RESTANTE/FALTANTE (paciente ve "ainda faltam Xg" e isso
      // nao eh claim sobre meta absoluta). Aplica apenas pra fields com
      // semantica de "restante" (protein_target, calories_target).
      //
      // IMPORTANTE: match.index aponta pro INICIO da regex inteira (ex: "meta"
      // na regex `(meta|...)prote[íi]na(...g)`), nao pro grupo capturado. Pra
      // achar 40 chars antes do NUMERO, calculamos a posicao do grupo.
      if (field === 'protein_target' || field === 'calories_target') {
        const numberPosInMatch = match[0].indexOf(claimedRaw)
        const numberAbsPos = match.index + (numberPosInMatch >= 0 ? numberPosInMatch : 0)
        const before = text.slice(Math.max(0, numberAbsPos - 40), numberAbsPos)
        if (RESTANTE_BEFORE_PATTERNS.some((p) => p.test(before))) continue
      }

      const diff = Math.abs(claimed - real)
      const diffPct = diff / Math.max(Math.abs(real), 1)

      const tolerance =
        field === 'age'
          ? 1
          : field === 'current_streak' || field === 'level'
            ? 2
            : Math.max(real * thresholdPct, 30)
      if (diff <= tolerance) continue

      const excerptStart = Math.max(0, match.index - 40)
      const excerptEnd = Math.min(text.length, match.index + match[0].length + 40)
      findings.push({
        field,
        claimed,
        real,
        diff_abs: +diff.toFixed(2),
        diff_pct: +diffPct.toFixed(3),
        excerpt: text.slice(excerptStart, excerptEnd).trim(),
      })
    }
  }
  return findings
}

/**
 * Sanity semantico: detecta inconsistencia entre PALAVRAS (deficit/excedente)
 * e o sinal real do daily_balance. Caso real Roberto 2026-05-18 20:52: LLM
 * disse "excedente de 92 kcal" quando snapshot tinha daily_balance=-960
 * (deficit). Validator numerico nao pegava (nao tinha "92" como meta no ctx).
 *
 * Convencao MPP:
 *   daily_balance = consumed - target - exercise
 *   - balance < 0: deficit (paciente ainda nao bateu meta, "restam X kcal")
 *   - balance > 0: excedente (passou da meta, "excedente Y kcal")
 *   - balance == 0: na meta exata
 *
 * Palavras-chave a detectar:
 *   - "deficit", "restam X kcal", "abaixo da meta", "ainda pode comer"
 *      -> implica balance < 0 (ou proximo de 0)
 *   - "excedente", "acima da meta", "passou", "estourou", "ultrapassou"
 *      -> implica balance > 0
 */
export interface SentimentMismatch {
  text_says: 'deficit' | 'excedente'
  balance_is: 'deficit' | 'excedente' | 'on_target'
  daily_balance: number
  excerpt: string
}

const DEFICIT_WORDS = /\b(d[ée]ficit|restam?\s+\d|ainda\s+(?:tem|pode|faltam)|abaixo\s+da\s+meta|sobra(?:m)?\s+\d|falta(?:m)?\s+\d)/i
const EXCEDENTE_WORDS = /\b(excedente|acima\s+da\s+meta|passou\s+(?:da|de)\s+meta|estourou|ultrapassou\s+(?:a\s+)?meta|al[ée]m\s+da\s+meta)/i

export function detectSentimentMismatch(
  text: string,
  dailyBalance: number | null | undefined,
): SentimentMismatch | null {
  if (dailyBalance == null) return null
  const hasDeficit = DEFICIT_WORDS.test(text)
  const hasExcedente = EXCEDENTE_WORDS.test(text)
  // Toleancia ±50 kcal (paciente "na meta")
  const balanceIs: 'deficit' | 'excedente' | 'on_target' =
    dailyBalance < -50 ? 'deficit' : dailyBalance > 50 ? 'excedente' : 'on_target'

  // Mismatch 1: texto diz excedente mas balance eh deficit grande
  if (hasExcedente && dailyBalance < -100) {
    const m = text.match(EXCEDENTE_WORDS)
    return {
      text_says: 'excedente',
      balance_is: balanceIs,
      daily_balance: dailyBalance,
      excerpt: m ? text.slice(Math.max(0, (m.index ?? 0) - 30), (m.index ?? 0) + (m[0]?.length ?? 0) + 30) : '',
    }
  }
  // Mismatch 2: texto diz deficit mas balance eh excedente
  if (hasDeficit && !hasExcedente && dailyBalance > 100) {
    const m = text.match(DEFICIT_WORDS)
    return {
      text_says: 'deficit',
      balance_is: balanceIs,
      daily_balance: dailyBalance,
      excerpt: m ? text.slice(Math.max(0, (m.index ?? 0) - 30), (m.index ?? 0) + (m[0]?.length ?? 0) + 30) : '',
    }
  }
  return null
}

/**
 * Reconcilia o RÓTULO e a MAGNITUDE de balanço calórico na PROSA livre com o
 * saldo real do dia. Diferente de detectSentimentMismatch (que só detecta/loga),
 * esta função CORRIGE o texto. Casos reais (Paulo 2026-05-20):
 *   - 17:13 pipeline: prosa "Excedente leve de 130 kcal" (ignorou exercício)
 *     enquanto saldo real era -122 (déficit). Card já dizia "Restam 122" — a
 *     prosa contradizia o próprio card.
 *   - 11:17 engajamento: "fechou com 458 kcal de déficit" quando o balanço de
 *     ontem era +458 (superávit vs meta). Sinal invertido.
 *
 * Convenção (igual à do card): balance = consumido - meta - exercício.
 *   balance < -tol  -> déficit (sob a meta, "restam |balance| kcal")
 *   balance > +tol  -> excedente/superávit (passou da meta)
 *
 * NÃO toca linhas de card (usam "Restam:/Excedente:" com dois-pontos e emoji);
 * só captura prosa no formato "<palavra> de <n> kcal" ou "<n> kcal de <palavra>",
 * e só reescreve quando o rótulo da prosa DIVERGE do sinal real (frases corretas
 * ficam intactas).
 */
export function reconcileBalanceProse(
  text: string,
  dailyBalance: number | null | undefined,
  opts: { tolerance?: number } = {},
): { text: string; replacements: number } {
  if (!text || dailyBalance == null) return { text, replacements: 0 }
  const tol = opts.tolerance ?? 50
  const realSign: 'deficit' | 'excedente' | 'on_target' =
    dailyBalance < -tol ? 'deficit' : dailyBalance > tol ? 'excedente' : 'on_target'
  if (realSign === 'on_target') return { text, replacements: 0 }

  const mag = Math.abs(Math.round(dailyBalance))
  const replacement = realSign === 'deficit' ? `restam ${mag} kcal` : `excedente de ${mag} kcal`
  const wordToSign = (w: string): 'deficit' | 'excedente' =>
    /^d[ée]f/i.test(w) ? 'deficit' : 'excedente'

  let replacements = 0
  let out = text

  // Padrão A: "<palavra> (leve|pequeno|grande)? de <n> kcal"
  out = out.replace(
    /\b(d[ée]ficit|super[áa]vit|excedente)\b(?:\s+(?:leve|pequen[oa]|grande))?\s+de\s+[\d.,]+\s*kcal/gi,
    (full: string, word: string) => {
      if (wordToSign(word) === realSign) return full
      replacements++
      return /^[A-ZÀ-Ý]/.test(full.trimStart())
        ? replacement.charAt(0).toUpperCase() + replacement.slice(1)
        : replacement
    },
  )

  // Padrão B: "<n> kcal de <palavra>"
  out = out.replace(
    /[\d.,]+\s*kcal\s+de\s+(d[ée]ficit|super[áa]vit|excedente)\b/gi,
    (full: string, word: string) => {
      if (wordToSign(word) === realSign) return full
      replacements++
      return replacement
    },
  )

  return { text: out, replacements }
}

/**
 * Detecta o erro do "déficit real" (Roberto 2026-05-21): o LLM, ao narrar um
 * dia COM exercício, calcula "déficit real = exercício − excedente" e ESQUECE
 * que a meta já tem o déficit programado embutido. Ex: excedente 126, exercício
 * 523 → escreveu "déficit real de 397" (523−126), quando o real é 897.
 *
 * O "déficit real do dia" = crédito do bloco = designDeficit − dailyBalance
 * (dailyBalance = consumido − meta − exercício, negativo quando há déficit).
 * Ex: 500 − (−397) = 897. É o mesmo número que o bloco credita no fechamento.
 *
 * Só dispara em afirmação EXPLÍCITA "déficit real ... de N kcal". Frases sem
 * número ("déficit real fica positivo") não acusam. Detecta/loga — não reescreve.
 */
export interface DeficitRealMismatch {
  claimed: number
  correct: number
  excerpt: string
}

export function detectDeficitRealMismatch(
  text: string,
  params: { designDeficit: number; dailyBalance: number },
  opts: { tolerance?: number } = {},
): DeficitRealMismatch | null {
  if (!text) return null
  const tol = opts.tolerance ?? 50
  // "déficit real [do dia] [de] **N kcal**" — N em pt-BR (1.943 / 397).
  const m = text.match(
    /d[ée]ficit\s+real(?:\s+do\s+dia)?\s+(?:de\s+)?\*{0,2}\s*([\d.,]+)\s*kcal/i,
  )
  if (!m || m[1] == null) return null
  const claimed = Number(m[1].replace(/\./g, '').replace(',', '.'))
  if (!Number.isFinite(claimed)) return null
  const correct = Math.max(0, Math.round(realDailyDeficit(params.designDeficit, params.dailyBalance)))
  if (Math.abs(claimed - correct) <= tol) return null
  return {
    claimed,
    correct,
    excerpt: text.slice(Math.max(0, (m.index ?? 0) - 20), (m.index ?? 0) + m[0].length + 10),
  }
}

/**
 * Loga divergencias em product_events. Nao bloqueia. Nao retorna nada.
 */
export async function auditNumericClaims(
  supabase: ServiceClient,
  userId: string,
  text: string,
  ctx: NumericContext,
  metadata: Record<string, Json> = {},
): Promise<void> {
  if (!text) return
  const config = await loadValidatorConfig(supabase)
  if (!config.enabled) return
  const findings = validateNumericClaims(text, ctx, config.threshold_pct)
  if (findings.length === 0) return

  await supabase.from('product_events').insert({
    user_id: userId,
    event: 'llm.numeric_mismatch',
    properties: {
      findings: findings as unknown as Json,
      threshold_pct: config.threshold_pct,
      ...metadata,
    },
  })
}
