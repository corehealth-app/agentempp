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
  /**
   * true = regex JÁ ancora em keyword target ("meta|alvo|dia|por dia").
   * Audit 06-24 review HIGH 1: nesses casos NÃO aplicar minPlausibleTarget,
   * porque o LLM declarou explicitamente "meta de Xg" — claim baixo aqui é
   * alucinação real, não confusão per-meal. Sem essa flag, "meta de 50g de
   * proteína" com target=120 era silenciada (regressão de detecção).
   */
  targetAnchored?: boolean
}> = [
  // "2.500 kcal", "2500 kcal", "meta de 2,500 kcal"
  { field: 'calories_target', re: /(?:meta|alvo|target|goal)\s*(?:hoje|de|é)?\s*(?:é\s*)?\*{0,2}\s*([\d]{3,5}(?:[.,][\d]{3})?)\s*\*{0,2}\s*kcal/gi, group: 1, targetAnchored: true },
  // protein_target só dispara quando o número está claramente no contexto de
  // META DIÁRIA (não per-refeição). 3 padrões:
  //   A) "Proteína: 125 / 178g" — card pós-registro (segundo número = meta)
  //   B) "meta de 178g de proteína" — keyword target ANTES do número
  //   C) "178g de proteína (meta|dia|diária)" — keyword target DEPOIS do número
  // Antes dispara em "Total refeição: 447 kcal | 11g proteína" (per-meal) → false positive.
  // A: card "X/Yg" — segundo número é meta. SEM keyword target — pode confundir
  // com per-meal "consumido/restante". minPlausibleTarget aplica aqui.
  {
    field: 'protein_target',
    re: /prote[íi]na[:\s]*\*{0,2}\s*\d+(?:[.,]\d+)?\s*\*{0,2}\s*g?\s*\/\s*\*{0,2}\s*([\d]{2,4}(?:[.,]\d)?)\s*\*{0,2}\s*g/gi,
    group: 1,
  },
  // B: keyword target ANTES do número
  {
    field: 'protein_target',
    re: /(?:meta|alvo|target|goal|objetiv[oa]|cota)[^\n]{0,40}?(\d{2,4}(?:[.,]\d)?)\s*g[^\n]{0,15}?prote[íi]na/gi,
    group: 1,
    targetAnchored: true,
  },
  // C: keyword target DEPOIS do número
  {
    field: 'protein_target',
    re: /(\d{2,4}(?:[.,]\d)?)\s*g\s*(?:de\s*)?prote[íi]na[^\n]{0,30}?(?:meta|alvo|dia|diár[ia]a|goal|target|por\s+dia)/gi,
    group: 1,
    targetAnchored: true,
  },
  // D) "meta de proteína é Xg" (keyword + proteína ANTES do número)
  {
    field: 'protein_target',
    re: /(?:meta|alvo|target|goal|objetiv[oa]|cota)[^\n]{0,40}?prote[íi]na[^\n]{0,20}?(\d{2,4}(?:[.,]\d)?)\s*g\b/gi,
    group: 1,
    targetAnchored: true,
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
  // Audit 06-24 (Bug B): parser quebrava decimais — "100.1" virava 1001 porque
  // `.replace(/\./g, '')` removia TODO ponto, ignorando contexto. Caso real:
  // "Nova meta: 100.1g de proteína" extraía claimed=1001 vs target=100.1 →
  // falso positivo 6× em 14d. Agora distingue separador de MILHAR (PT-BR,
  // sempre 3 dígitos depois) vs DECIMAL (1-2 dígitos depois).
  const trimmed = s.trim()
  // PT-BR decimal: "100,1" / "1.943,5" — vírgula é SEMPRE decimal
  if (/^\d{1,3}(?:\.\d{3})*,\d+$/.test(trimmed)) {
    return Number(trimmed.replace(/\./g, '').replace(',', '.'))
  }
  if (/^\d+,\d+$/.test(trimmed)) {
    return Number(trimmed.replace(',', '.'))
  }
  // EN decimal: "100.1" / "25.3" — ponto seguido de 1-2 dígitos é decimal
  if (/^\d+\.\d{1,2}$/.test(trimmed)) {
    return Number(trimmed)
  }
  // Milhar PT-BR: "2.500" / "7.700" / "1.943" — ponto seguido de 3 dígitos
  if (/^\d{1,3}(?:\.\d{3})+$/.test(trimmed)) {
    return Number(trimmed.replace(/\./g, ''))
  }
  // Milhar EN com vírgula: "2,500" (raro mas suporta)
  if (/^\d{1,3}(?:,\d{3})+$/.test(trimmed)) {
    return Number(trimmed.replace(/,/g, ''))
  }
  // Inteiro puro
  return Number(trimmed)
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

// Audit 06-24 (Bug B): contexto explícito de PER-REFEIÇÃO antes do número.
// Casos reais que viraram falso positivo:
//  - "Almoço com 40g de proteína" (Luciana 23/06)
//  - "Jantar com 21g de proteína" (Luciana 22/06)
//  - "Jantar com 44,5g de proteína" (Luciana 19/06)
// O número é per-meal, não target diário.
// Review HIGH 2 (audit 06-24 review): `\b` em JS exige transição \w↔\W,
// mas "é" (U+00E9), "ã" (U+00E3), "ç" (U+00E7) são \W. Logo `\bcaf[ée]\b`
// FALHA em "café" (último char "é" é \W, \b não dispara). Trocado por
// lookahead `(?=[\s.,:;!?)\-]|$)` que aceita qualquer separador comum +
// fim de string. "Café com 30g" agora suprime corretamente.
const WORD_END = '(?=[\\s.,:;!?)\\-]|$)'
const PER_MEAL_BEFORE_PATTERNS = [
  new RegExp(`\\b(almo[çc]o|jantar|lanche|caf[ée](?:\\s+da\\s+(?:manh[ãa]|tarde))?|ceia|refei[çc][ãa]o|brunch)${WORD_END}[^.\\n]{0,15}\\bcom\\s*$`, 'i'),
  new RegExp(`\\bno\\s+(almo[çc]o|jantar|lanche|caf[ée](?:\\s+da\\s+(?:manh[ãa]|tarde))?|brunch)${WORD_END}[^.\\n]{0,15}$`, 'i'),
  new RegExp(`\\bna\\s+(ceia|refei[çc][ãa]o)${WORD_END}[^.\\n]{0,15}$`, 'i'),
  /\b(desta|dessa|da)\s+refei[çc][ãa]o\s*$/i,
  /\b(do\s+almo[çc]o|do\s+jantar|do\s+lanche|do\s+caf[ée]|da\s+ceia)\s*$/i,
]

export function validateNumericClaims(
  text: string,
  ctx: NumericContext,
  thresholdPct = 0.1,
): MismatchFinding[] {
  const findings: MismatchFinding[] = []
  for (const { field, re, group, targetAnchored } of PATTERNS) {
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
        // Audit 06-24 (Bug B): skip se o número está num contexto explícito
        // de PER-REFEIÇÃO ("Almoço com 40g", "Jantar com 21g", "no almoço",
        // "da refeição"). Caso real: "Almoço com 40g de proteína" pegava
        // claimed=40 vs target=178 (FALSO POSITIVO 4× em 14d).
        if (PER_MEAL_BEFORE_PATTERNS.some((p) => p.test(before))) continue
        // Audit 06-24 (Bug B): skip por implausibilidade — proteína de UMA
        // refeição quase nunca passa de 50% da meta diária (refeição típica
        // 25-40g, meta 120-200g). Threshold 0.5 evita matchar "almoço com
        // 40g" vs meta 178g. Pra calorias, threshold mais frouxo (0.4) pra
        // não vetar card legítimo que cita meta cheia.
        //
        // Review HIGH 1 (audit 06-24 review): SÓ aplicar quando regex NÃO
        // ancora em keyword target. Quando regex B/C/D casam "meta de Xg de
        // proteína", o LLM declarou explicitamente meta — claim baixo aqui
        // é alucinação real, não confusão per-meal. Sem essa condicional,
        // "meta de 50g" silenciaria mismatch real vs target=120.
        if (!targetAnchored) {
          const minPlausibleTarget = field === 'protein_target' ? real * 0.5 : real * 0.4
          if (claimed > 0 && claimed < minPlausibleTarget) continue
        }
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
 * Reconcilia a afirmação de BALANÇO DE ONTEM da mensagem matinal contra o
 * DÉFICIT REAL vs MANUTENÇÃO (realDailyDeficit = designDeficit − dailyBalance).
 *
 * Por que existe ALÉM de reconcileBalanceProse: aquela valida contra o
 * daily_balance (vs META). A matinal comunica o real vs MANUTENÇÃO — e os dois
 * DISCORDAM de sinal na zona "acima da meta, porém abaixo da manutenção"
 * (Paulo 2026-05-27: daily_balance +119 = excedente vs meta, mas realDef +381 =
 * déficit real vs manutenção). Nessa zona, reconcileBalanceProse NÃO pega a
 * inversão "excedente de 119" — pior, poderia CORROMPER um correto "déficit
 * real de 381" achando que é excedente. Por isso a matinal usa ESTA função.
 *
 *   realDef > tol  → déficit real (emagrece / alimenta o bloco 7700)
 *   realDef < -tol → superávit acima da manutenção (comeu mais do que gastou)
 *
 * Só reescreve quando o SINAL da prosa (déficit ↔ superávit/excedente) diverge
 * do realDef; frase com sinal certo fica intacta (magnitude do LLM preservada).
 */
export function reconcileRealDeficitProse(
  text: string,
  realDef: number | null | undefined,
  opts: { tolerance?: number } = {},
): { text: string; replacements: number } {
  if (!text || realDef == null) return { text, replacements: 0 }
  const tol = opts.tolerance ?? 50
  const realSign: 'deficit' | 'surplus' | 'on_target' =
    realDef > tol ? 'deficit' : realDef < -tol ? 'surplus' : 'on_target'
  if (realSign === 'on_target') return { text, replacements: 0 }

  const mag = Math.abs(Math.round(realDef))
  const replacement =
    realSign === 'deficit'
      ? `déficit real de ${mag} kcal vs manutenção`
      : `superávit de ${mag} kcal acima da manutenção`
  const wordToSign = (w: string): 'deficit' | 'surplus' =>
    /^d[ée]f/i.test(w) ? 'deficit' : 'surplus'

  let replacements = 0
  let out = text

  // Padrão A: "<palavra> (real|leve|...)? de <n> kcal[ real][ vs/acima/abaixo manutenção]?"
  out = out.replace(
    /\b(d[ée]ficit|super[áa]vit|excedente)\b(?:\s+(?:real|leve|pequen[oa]|grande))?\s+de\s+[\d.,]+\s*kcal(?:\s+reais?)?(?:\s+(?:vs\.?\s+manuten[çc][ãa]o|(?:acima|abaixo)\s+da\s+manuten[çc][ãa]o))?/gi,
    (full: string, word: string) => {
      if (wordToSign(word) === realSign) return full
      replacements++
      return /^[A-ZÀ-Ý]/.test(full.trimStart())
        ? replacement.charAt(0).toUpperCase() + replacement.slice(1)
        : replacement
    },
  )

  // Padrão B: "<n> kcal (de <palavra> | acima/abaixo da manutenção)"
  out = out.replace(
    /[\d.,]+\s*kcal\s+(?:de\s+(d[ée]ficit|super[áa]vit|excedente)\b|(acima|abaixo)\s+da\s+manuten[çc][ãa]o)/gi,
    (full: string, word: string | undefined, dir: string | undefined) => {
      const sign: 'deficit' | 'surplus' = word
        ? wordToSign(word)
        : dir && /acima/i.test(dir)
          ? 'surplus'
          : 'deficit'
      if (sign === realSign) return full
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
 * Detecta afirmação PREMATURA de conclusão de bloco (Roberto 2026-05-22 12:31):
 * "bloco 7700 fechado hoje / segundo bloco completo" durante o DIA. O bloco só
 * credita no FECHAMENTO da noite (daily-closer); no meio do dia o déficit está
 * inflado (refeições ainda não feitas). O card mostra o valor real, mas a prosa
 * comemora antes da hora — contradizendo o próprio card.
 *
 * Dispara quando há (afirmação de conclusão de bloco) E (marcador de "agora/hoje/
 * com isso/com o treino") — pra NÃO pegar comemoração legítima de bloco passado
 * ("você fechou seu 1º bloco ontem"). Usado só em turno ao vivo (dia aberto).
 */
const BLOCK_DONE =
  /\bbloco\b[^.\n]{0,25}(fechad[oa]|complet[oa])|(fech|complet)\w+[^.\n]{0,12}\bbloco\b|(primeir|segund|terceir|quart|quint)[oa]\s+bloco\s+(completo|fechado)/i
const NOW_MARKER = /\b(hoje|agora|com\s+isso|com\s+o\s+(exerc|treino)|acab\w+\s+de|já\s+ultrapass)/i

export function detectPrematureBlockCompletion(text: string): boolean {
  if (!text) return false
  // Ignora a linha do card "Bloco 7700: X / 7700" (tem barra, não é afirmação).
  const prose = text.replace(/Bloco\s*7\.?700[^\n]*\/[^\n]*/gi, '')
  return BLOCK_DONE.test(prose) && NOW_MARKER.test(prose)
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
