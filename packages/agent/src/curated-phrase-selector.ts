/**
 * Seletor determinístico de frases educativas curadas (Roberto 2026-06-11).
 *
 * Roberto vai criar até 50 variações de frases por alimento (planilha
 * manual). Este seletor consulta `food_education_phrases`, identifica o
 * alimento "âncora" da refeição (maior peso nutricional), filtra por tags
 * do estado do paciente (déficit alto, proteína baixa, recomp, etc),
 * sorteia 1 evitando repetição em N dias E retorna.
 *
 * Se não há frase pro alimento (planilha incompleta) → retorna null e o
 * caller cai pro Haiku edu-comment como hoje.
 *
 * Custo: ZERO (sem LLM). Substitui ~$8-12/mês de Haiku quando planilha
 * cobrir os top-30 alimentos do meal_logs.
 */
import type { ServiceClient } from '@mpp/db'

export interface PhraseSelectorInput {
  /** Items da refeição registrada. */
  items: Array<{
    food_name: string
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  /** ID do paciente — pra evitar repetição via usage_count + last_used_at. */
  userId: string
  /** Estado do paciente (pra filtrar por tag). */
  state?: {
    protocol?: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
    protein_pct?: number // 0-100, % da meta diária
    kcal_pct?: number // 0-100
    deficit_block_pct?: number // 0-100
  }
  /** Idioma. */
  language?: string
  /** Tipo da refeição em que a frase será renderizada (Nível 1 defensivo —
   * bug I3 2026-06-14: frase "Whey de manhã…" caiu em jantar do Roberto).
   * Quando presente, o selector descarta frases cujo TEXTO contém palavras
   * temporais incompatíveis com esse slot (ex: "manhã" em jantar/ceia,
   * "antes de dormir" em café/almoço). Quando ausente, o filtro é no-op
   * (degradação graciosa). */
  mealKind?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro' | 'treino'
  /** Embeddings provider pra cascade semântica (opcional). Quando ausente,
   * selector só usa .eq() exato — degradação graciosa. Quando presente e
   * .eq() retorna vazio, faz similarity search via pgvector. */
  embeddings?: { embed(text: string): Promise<number[]> }
}

export interface PhraseSelectorResult {
  /** Frase selecionada ou null se não há cobertura. */
  phrase: string | null
  /** Nome canônico do alimento que disparou. */
  food_canonical_name: string | null
  /** ID da frase (pra incrementar usage_count). */
  phrase_id: string | null
  /** Motivo da seleção/falha. */
  reason: string
  /** Tamanho do pool retornado da fonte de frases. */
  candidate_count?: number
  /** Tamanho do pool após filtros de tag e compatibilidade temporal. */
  compatible_count?: number
  /** Quantas frases elegíveis estavam no cooldown do paciente. */
  cooldown_count?: number
  /** True quando a frase escolhida veio do subconjunto fora do cooldown. */
  selected_after_cooldown?: boolean
}

/**
 * Identifica o alimento "âncora" da refeição — maior protagonismo.
 * Critério: maior kcal × proteína_relevância. Proteína > carb > gordura
 * (preferência MPP).
 */
export function pickAnchorFood(
  items: PhraseSelectorInput['items'],
): { food_name: string; weight: number } | null {
  if (!items || items.length === 0) return null
  // Filtra items com kcal=0 (água, chá puro, temperos) — não merecem ser
  // anchor (não há frase educativa relevante). Se TODOS são 0kcal, retorna
  // null (caller cai pro fallback Haiku ou skip).
  const scorable = items.filter((it) => it.kcal > 0)
  if (scorable.length === 0) return null
  let best: { food_name: string; weight: number } | null = null
  for (const it of scorable) {
    // Peso: kcal + bonus por densidade proteica + bonus por densidade gorda
    const proteinDensity = (it.protein_g * 4) / it.kcal
    const fatDensity = (it.fat_g * 9) / it.kcal
    const weight = it.kcal + proteinDensity * 50 + fatDensity * 30
    if (!best || weight > best.weight) {
      best = { food_name: it.food_name, weight }
    }
  }
  return best
}

/**
 * Normaliza nome pra match em `food_canonical_name`. Lowercase + remove
 * diacríticos (acentos) + colapsa espaços. Usa \p{Diacritic} (unicode
 * property) — mais robusto que `[̀-ͯ]` literal que pode falhar dependendo
 * da fonte do arquivo.
 */
function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * Variantes do nome pra busca tolerante (plural ↔ singular comum em PT-BR).
 * Selector tenta cada variante até achar match. Resolve 'ovo' ↔ 'ovos',
 * 'banana' ↔ 'bananas', 'castanha' ↔ 'castanhas', 'azeite' ↔ 'azeites'.
 * Não tenta lematização semântica (ovo→ovinhos: false-positives).
 */
function generateLookupVariants(canonicalName: string): string[] {
  const variants = new Set<string>()
  variants.add(canonicalName)
  // Plural: adicionar 's' se não termina em 's'
  if (!canonicalName.endsWith('s')) variants.add(canonicalName + 's')
  // Singular: tirar 's' final se termina em 's' (mas só pra palavras >= 4 chars
  // pra evitar 'arroz' → 'arro')
  if (canonicalName.endsWith('s') && canonicalName.length >= 5) {
    variants.add(canonicalName.slice(0, -1))
  }
  // Plural -ão → -ões (limão → limões)
  if (canonicalName.endsWith('ao')) variants.add(canonicalName.slice(0, -2) + 'oes')
  if (canonicalName.endsWith('oes')) variants.add(canonicalName.slice(0, -3) + 'ao')
  return [...variants]
}

/**
 * Nível 1 defensivo (bug I3 2026-06-14): detecta incompatibilidade temporal
 * entre o TEXTO da frase curada e o slot (meal_type) em que ela seria
 * renderizada. Ex.: frase "Whey de manhã…" não pode cair em jantar do
 * paciente — quebra o tom e parece bug de relógio.
 *
 * Estratégia: regex em palavras-âncora temporais explícitas. Conservador
 * (só rejeita combinações claramente erradas). NÃO usa NLP nem LLM.
 *
 * Slot → palavras temporais ACEITAS (frase OK se mencionar) e BLOQUEADAS
 * (frase REJEITADA se mencionar):
 *   cafe / lanche_da_manha → 'manhã', 'cedo', 'logo cedo', 'café da manhã'
 *     OK. 'noite', 'jantar', 'antes de dormir', 'ceia' BLOQUEIA.
 *   almoco → 'almoço' OK. 'manhã', 'café da manhã', 'antes de dormir',
 *     'ceia', 'noite' BLOQUEIA.
 *   lanche (genérico/tarde) → 'tarde', 'lanche' OK. 'manhã', 'cedo',
 *     'antes de dormir', 'ceia' BLOQUEIA.
 *   jantar → 'jantar', 'noite' OK. 'manhã', 'cedo', 'café da manhã'
 *     BLOQUEIA.
 *   ceia → 'ceia', 'antes de dormir', 'noite' OK. 'manhã', 'cedo',
 *     'café da manhã', 'almoço' BLOQUEIA.
 *   outro / treino / undefined → sem filtro (passa).
 *
 * Frases que mencionam MÚLTIPLAS refeições ("almoço, jantar, e até em
 * vitaminas verdes no café da manhã") são tratadas como universais —
 * citam ≥3 slots, descrevem versatilidade. Não bloqueiam.
 */
export function isTemporallyCompatible(
  phrase: string,
  mealKind?: PhraseSelectorInput['mealKind'],
): { ok: true } | { ok: false; reason: string } {
  if (!mealKind || mealKind === 'outro' || mealKind === 'treino') return { ok: true }
  // Normaliza phrase pra match case-insensitive. Mantém acentos pra preservar
  // semântica "manhã"≠"manha" (a 2ª é gíria) — apenas baixa caixa.
  const p = phrase.toLowerCase()
  // BOUNDARY PT-BR: \b do JS não trata 'ã', 'é', 'ç' como word chars, então
  // 'manhã' tem \b ANTES de 'ã' (falha o match). Usamos boundary manual:
  // (?:^|[^a-zà-úãõçâêôîû]) — começo de string OU char não-alfa-PT-BR.
  // Lookbehind seria mais limpo mas Node 14+ suporta — usamos non-capturing
  // group e padrão de início/fim. Trabalhamos com a string em lowercase.
  const W = '[^a-zà-úãõçâêôîû]' // char NÃO-alfabético PT-BR (delimitador)
  const B = `(?:^|${W})` // boundary à esquerda
  const E = `(?=${W}|$)` // boundary à direita (lookahead)
  const has = (needle: RegExp): boolean => needle.test(p)
  const reCafeManha = new RegExp(`${B}caf[eé] da manh[ãa]${E}`, 'i')
  const reManha = new RegExp(`${B}manh[ãa]${E}`, 'i')
  const reCedo = new RegExp(`${B}(logo )?cedo${E}`, 'i')
  const reAlmoco = new RegExp(`${B}almo[çc]o${E}`, 'i')
  const reTarde = new RegExp(`${B}(?:[àa]|na|da) tarde${E}`, 'i')
  const reJantar = new RegExp(`${B}jantar${E}`, 'i')
  const reNoite = new RegExp(`${B}(?:[àa]|na|da|de) noite${E}`, 'i')
  const reAntesDormir = new RegExp(`${B}antes de dormir${E}`, 'i')
  const reCeia = new RegExp(`${B}ceia${E}`, 'i')

  // Conta quantos slots distintos a frase referencia. Se >=3, é uma frase
  // "versátil" que descreve flexibilidade entre refeições — não bloqueia.
  const slotsMentioned =
    (reCafeManha.test(p) || reManha.test(p) || reCedo.test(p) ? 1 : 0) +
    (reAlmoco.test(p) ? 1 : 0) +
    (reTarde.test(p) ? 1 : 0) +
    (reJantar.test(p) || reNoite.test(p) ? 1 : 0) +
    (reAntesDormir.test(p) || reCeia.test(p) ? 1 : 0)
  if (slotsMentioned >= 3) return { ok: true }

  // Regras de bloqueio por slot.
  switch (mealKind) {
    case 'cafe': {
      if (has(reJantar)) return { ok: false, reason: 'phrase_mentions_jantar_in_cafe' }
      if (has(reAntesDormir)) return { ok: false, reason: 'phrase_mentions_antes_dormir_in_cafe' }
      if (has(reCeia)) return { ok: false, reason: 'phrase_mentions_ceia_in_cafe' }
      if (has(reNoite)) return { ok: false, reason: 'phrase_mentions_noite_in_cafe' }
      // "almoço" sozinho em frase de café também é estranho ("X é ideal pro almoço")
      if (has(reAlmoco) && !has(reCafeManha) && !has(reManha) && !has(reCedo))
        return { ok: false, reason: 'phrase_mentions_almoco_only_in_cafe' }
      return { ok: true }
    }
    case 'almoco': {
      if (has(reCafeManha)) return { ok: false, reason: 'phrase_mentions_cafe_in_almoco' }
      if (has(reAntesDormir))
        return { ok: false, reason: 'phrase_mentions_antes_dormir_in_almoco' }
      if (has(reCeia)) return { ok: false, reason: 'phrase_mentions_ceia_in_almoco' }
      // "manhã" / "cedo" isolados em frase de almoço são incompatíveis
      if ((has(reManha) || has(reCedo)) && !has(reAlmoco) && !has(reJantar))
        return { ok: false, reason: 'phrase_mentions_manha_only_in_almoco' }
      return { ok: true }
    }
    case 'lanche': {
      // Lanche é o slot mais genérico em PT-BR (manhã ou tarde). Bloqueia só
      // os extremos noturnos.
      if (has(reAntesDormir))
        return { ok: false, reason: 'phrase_mentions_antes_dormir_in_lanche' }
      if (has(reCeia)) return { ok: false, reason: 'phrase_mentions_ceia_in_lanche' }
      if (has(reJantar) && !has(reTarde) && !has(reManha))
        return { ok: false, reason: 'phrase_mentions_jantar_only_in_lanche' }
      return { ok: true }
    }
    case 'jantar': {
      if (has(reCafeManha)) return { ok: false, reason: 'phrase_mentions_cafe_in_jantar' }
      // "manhã" / "cedo" isolados em frase de jantar = bug I3 exato (Whey de manhã)
      if ((has(reManha) || has(reCedo)) && !has(reJantar) && !has(reNoite))
        return { ok: false, reason: 'phrase_mentions_manha_only_in_jantar' }
      // "almoço" sozinho em jantar também é estranho
      if (has(reAlmoco) && !has(reJantar) && !has(reNoite))
        return { ok: false, reason: 'phrase_mentions_almoco_only_in_jantar' }
      return { ok: true }
    }
    case 'ceia': {
      if (has(reCafeManha)) return { ok: false, reason: 'phrase_mentions_cafe_in_ceia' }
      if (has(reAlmoco) && !has(reCeia) && !has(reAntesDormir))
        return { ok: false, reason: 'phrase_mentions_almoco_only_in_ceia' }
      if ((has(reManha) || has(reCedo)) && !has(reCeia) && !has(reAntesDormir))
        return { ok: false, reason: 'phrase_mentions_manha_only_in_ceia' }
      return { ok: true }
    }
    default:
      return { ok: true }
  }
}

/**
 * Tags do estado pra filtrar frases. Cada frase pode ter tags em jsonb
 * tipo { protein_low: true, deficit_high: true, recomp: true }. Sem tags
 * → frase universal.
 */
export function inferTags(state?: PhraseSelectorInput['state']): string[] {
  const tags: string[] = []
  if (!state) return tags
  if (state.protocol === 'recomposicao') tags.push('recomp')
  if (state.protocol === 'ganho_massa') tags.push('ganho_massa')
  if (state.protocol === 'manutencao') tags.push('manutencao')
  if (state.protein_pct != null && state.protein_pct < 50) tags.push('protein_low')
  if (state.protein_pct != null && state.protein_pct >= 80) tags.push('protein_high')
  if (state.kcal_pct != null && state.kcal_pct >= 80) tags.push('kcal_high')
  if (state.deficit_block_pct != null && state.deficit_block_pct >= 90)
    tags.push('block_near_close')
  return tags
}

/**
 * Seletor principal. Roda a query, filtra por tags, sorteia evitando
 * repetição recente, incrementa usage_count.
 */
export async function selectCuratedPhrase(
  supabase: ServiceClient,
  input: PhraseSelectorInput,
): Promise<PhraseSelectorResult> {
  const anchor = pickAnchorFood(input.items)
  if (!anchor) {
    return { phrase: null, food_canonical_name: null, phrase_id: null, reason: 'no_anchor' }
  }
  // Defesa: shape inválido (food_name undefined). O bug histórico era a tool
  // retornar items com chave `name` e o cast TS mascarar isso; quando o
  // adapter no caller falha (ou rota nova esquece), anchor.food_name vira
  // undefined e normalize lançava TypeError engolido pelo catch silencioso.
  if (!anchor.food_name || typeof anchor.food_name !== 'string') {
    return {
      phrase: null,
      food_canonical_name: null,
      phrase_id: null,
      reason: 'invalid_anchor_shape',
    }
  }
  const canonicalName = normalize(anchor.food_name)
  const language = input.language ?? 'pt-BR'
  // Cascade lookup (HIGH/Eduardo escolha estrutural):
  //   1) .eq() exato com variantes plural/singular (fast path, 0 custo)
  //   2) Se vazio, similarity via embedding (resolve "aveia em flocos" → "aveia")
  // Audit empírico pós-deploy mostrou que meal_logs em prod usa nomes
  // compostos ("X em flocos", "Y zero açúcar", "Z desnatado") enquanto
  // Roberto entregou nomes-base. .eq() pegava 0 hits. Embeddings semânticos
  // (text-embedding-3-large 1024d) distinguem polaridade (desnatado vs
  // condensado têm distance significativa).
  const lookupVariants = generateLookupVariants(canonicalName)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const sp = supabase as any
  let { data: rows } = await sp
    .from('food_education_phrases')
    .select('id, phrase, tags, usage_count, last_used_at')
    .eq('active', true)
    .eq('language', language)
    .in('food_canonical_name', lookupVariants)
    .order('last_used_at', { ascending: true, nullsFirst: true })
    .limit(50)

  // Cascade 2: se .eq() vazio, busca semântica via RPC.
  let matchedViaEmbedding = false
  let embeddingSimilarity: number | null = null
  if ((!rows || rows.length === 0) && input.embeddings) {
    try {
      const queryVec = await input.embeddings.embed(canonicalName)
      // Threshold 0.80 calibrado empiricamente (audit Paulo's foods):
      //  - 0.85 perdia 'aveia em flocos'→'aveia' (sim=0.844)
      //  - 0.70 incluía 'leite desnatado'→'leite condensado' (polaridade errada!)
      //  - 0.80 = sweet spot: pega variações de nome ('X picado',
      //    'Y em flocos', 'Z zero açúcar') sem pegar substituições
      //    semânticas que confundem polaridade ('grelhado' vs 'frito').
      const { data: vecRows } = await sp.rpc('match_food_phrases', {
        query_embedding: queryVec,
        match_threshold: 0.8,
        match_count: 50,
        match_language: language,
      })
      if (vecRows && vecRows.length > 0) {
        rows = vecRows
        matchedViaEmbedding = true
        embeddingSimilarity = (vecRows[0] as { similarity?: number })?.similarity ?? null
      }
    } catch (err) {
      // Embedding falhou (timeout, sem credencial) — cai pro fallback Haiku
      // eslint-disable-next-line no-console
      console.warn('[curated-phrase] embedding cascade failed:', err)
    }
  }

  const candidates = ((rows ?? []) as Array<{
    id: string
    phrase: string
    tags: Record<string, unknown> | null
    usage_count: number
    last_used_at: string | null
  }>)
  const candidateCount = candidates.length

  if (candidates.length === 0) {
    return {
      phrase: null,
      food_canonical_name: canonicalName,
      phrase_id: null,
      reason: 'no_phrases_for_food',
      candidate_count: candidateCount,
      compatible_count: 0,
      cooldown_count: 0,
    }
  }

  // Filtra por tags do estado. Frases SEM tags são universais (sempre OK).
  // Frases COM tags só passam se PELO MENOS UMA tag bate com o estado.
  const stateTags = new Set(inferTags(input.state))
  const filtered = candidates.filter((c) => {
    if (!c.tags || Object.keys(c.tags).length === 0) return true // universal
    return Object.keys(c.tags).some((k) => stateTags.has(k))
  })

  let pool = filtered.length > 0 ? filtered : candidates

  // Nível 1 defensivo (bug I3 2026-06-14): descarta frases cujo TEXTO menciona
  // refeição/horário incompatível com o slot atual. Ex.: "Whey de manhã…" em
  // jantar do Roberto. Se TODAS forem incompatíveis, retorna null
  // (no_temporally_compatible_phrase) — caller cai pro Haiku, melhor do que
  // mandar frase quebrada.
  if (input.mealKind) {
    const compatible = pool.filter((c) => isTemporallyCompatible(c.phrase, input.mealKind).ok)
    if (compatible.length === 0) {
      return {
        phrase: null,
        food_canonical_name: canonicalName,
        phrase_id: null,
        reason: 'no_temporally_compatible_phrase',
        candidate_count: candidateCount,
        compatible_count: 0,
        cooldown_count: 0,
      }
    }
    pool = compatible
  }
  const compatibleCount = pool.length

  // Cooldown por (user, phrase): filtra frases que esse user viu nas
  // últimas 7 dias. Resolve repetição literal pra mesmo paciente em refeições
  // consecutivas (review high #3). Regra forte: se existe alternativa fora
  // do cooldown, nunca repete a recente. Se a leitura do cooldown falhar,
  // retorna null e o caller cai pro Haiku em vez de repetir silenciosamente.
  let cooldownCount = 0
  let selectedAfterCooldown = false
  let allRecentFallback = false
  if (input.userId) {
    const cooldownSince = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
    const phraseIds = pool.map((c) => c.id)
    const { data: recent, error: cooldownError } = await sp
      .from('user_phrase_cooldown')
      .select('phrase_id')
      .eq('user_id', input.userId)
      .eq('phrase_table', 'food')
      .gte('last_seen_at', cooldownSince)
      .in('phrase_id', phraseIds)
    if (cooldownError) {
      return {
        phrase: null,
        food_canonical_name: canonicalName,
        phrase_id: null,
        reason: 'cooldown_lookup_failed',
        candidate_count: candidateCount,
        compatible_count: compatibleCount,
        cooldown_count: 0,
      }
    }
    const seenIds = new Set((recent ?? []).map((r: { phrase_id: string }) => r.phrase_id))
    cooldownCount = seenIds.size
    const notRecent = pool.filter((c) => !seenIds.has(c.id))
    if (notRecent.length > 0) {
      selectedAfterCooldown = seenIds.size > 0 && notRecent.length < pool.length
      pool = notRecent
    } else if (seenIds.size > 0) {
      // Se TODAS foram vistas <7d, usa pool original (melhor repetir do que
      // mandar fallback Haiku — paciente pode até notar a repetição mas o
      // tom continua certo), mas marca o reason explicitamente.
      allRecentFallback = true
    }
  }

  pool = [...pool].sort((a, b) => {
    const aTime = a.last_used_at ? Date.parse(a.last_used_at) : 0
    const bTime = b.last_used_at ? Date.parse(b.last_used_at) : 0
    if (aTime !== bTime) return aTime - bTime
    return (a.usage_count ?? 0) - (b.usage_count ?? 0)
  })

  // Sorteio determinístico entre top-3 — retries inngest cachean step.run
  // por SAÍDA, mas qualquer throw após selectCuratedPhrase força re-execução.
  // Math.random pegaria frase diferente no retry, criando órfãos no cooldown
  // (review medium). Hash baseado em (userId + canonicalName + date) garante
  // mesma frase no retry. Date em YYYY-MM-DD pra rotação diária natural.
  const today = new Date().toISOString().slice(0, 10)
  const seedStr = `${input.userId ?? 'anon'}|${canonicalName}|${today}`
  let seed = 0
  for (let i = 0; i < seedStr.length; i++) seed = (seed * 31 + seedStr.charCodeAt(i)) & 0xffffffff
  const idx = Math.abs(seed) % Math.min(pool.length, 3)
  const picked = pool[idx]
  if (!picked) {
    return {
      phrase: null,
      food_canonical_name: canonicalName,
      phrase_id: null,
      reason: 'no_match_after_filter',
      candidate_count: candidateCount,
      compatible_count: compatibleCount,
      cooldown_count: cooldownCount,
    }
  }

  // Marca como usada (incrementa usage_count + atualiza last_used_at)
  await sp
    .from('food_education_phrases')
    .update({
      usage_count: picked.usage_count + 1,
      last_used_at: new Date().toISOString(),
    })
    .eq('id', picked.id)

  // Upsert cooldown pra esse user×phrase. Idempotente via ON CONFLICT.
  if (input.userId) {
    await sp.from('user_phrase_cooldown').upsert(
      {
        user_id: input.userId,
        phrase_table: 'food',
        phrase_id: picked.id,
        last_seen_at: new Date().toISOString(),
      },
      { onConflict: 'user_id,phrase_table,phrase_id' },
    )
  }

  // Substitui placeholder {alimento} pelo nome do anchor. Quando o
  // placeholder está no INÍCIO da frase, capitaliza a primeira letra
  // (food_name vem em lowercase do meal_pipeline; sem capitalizar saía
  // "chocolate é uma escolha…" — review #4 medium). Demais ocorrências
  // mantêm o caso original (lowercase) pra fluir gramaticalmente.
  // Usa função no replacement (não string) pra evitar interpretação de
  // $1, $&, $` etc se food_name contém esses caracteres.
  const capFirst = (s: string) => (s.length === 0 ? s : s.charAt(0).toUpperCase() + s.slice(1))
  const foodLower = anchor.food_name.toLowerCase()
  let finalPhrase = picked.phrase
  // Substitui {alimento} no início (com possível espaço/pontuação antes) —
  // capitaliza. Cobre: "{alimento}…", "— {alimento}…", "\"{alimento}…",
  // "({alimento})…", "* {alimento}…", "1. {alimento}…", etc.
  finalPhrase = finalPhrase.replace(
    /^[\s\-—–"'`(\[*•·>#\d.)]*\{alimento\}/i,
    (match) => match.replace(/\{alimento\}/i, capFirst(anchor.food_name)),
  )
  // Restante: lowercase consistente
  finalPhrase = finalPhrase.replace(/\{alimento\}/gi, () => foodLower)

  // reason inclui o caminho do match pra audit: 'selected' (exact) ou
  // 'selected_embedding:0.84' (cascade semântica)
  const reasonStr = allRecentFallback
    ? 'selected_all_recent'
    : selectedAfterCooldown
      ? matchedViaEmbedding
        ? `selected_after_cooldown_embedding:${embeddingSimilarity?.toFixed(2) ?? '?'}`
        : 'selected_after_cooldown'
      : matchedViaEmbedding
        ? `selected_embedding:${embeddingSimilarity?.toFixed(2) ?? '?'}`
        : 'selected'

  return {
    phrase: finalPhrase,
    food_canonical_name: canonicalName,
    phrase_id: picked.id,
    reason: reasonStr,
    candidate_count: candidateCount,
    compatible_count: compatibleCount,
    cooldown_count: cooldownCount,
    selected_after_cooldown: selectedAfterCooldown,
  }
}
