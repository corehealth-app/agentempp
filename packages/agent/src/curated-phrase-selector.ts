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

  if (candidates.length === 0) {
    return {
      phrase: null,
      food_canonical_name: canonicalName,
      phrase_id: null,
      reason: 'no_phrases_for_food',
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

  // Cooldown por (user, phrase): filtra frases que esse user viu nas
  // últimas 7 dias. Resolve repetição literal pra mesmo paciente em
  // refeições consecutivas (review high #3). Só aplica se userId presente.
  if (input.userId) {
    const cooldownSince = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
    const phraseIds = pool.map((c) => c.id)
    const { data: recent } = await sp
      .from('user_phrase_cooldown')
      .select('phrase_id')
      .eq('user_id', input.userId)
      .eq('phrase_table', 'food')
      .gte('last_seen_at', cooldownSince)
      .in('phrase_id', phraseIds)
    const seenIds = new Set((recent ?? []).map((r: { phrase_id: string }) => r.phrase_id))
    const notRecent = pool.filter((c) => !seenIds.has(c.id))
    // Se TODAS foram vistas <7d, usa pool original (melhor repetir do que
    // mandar fallback Haiku — paciente pode até notar a repetição mas o
    // tom continua certo).
    if (notRecent.length > 0) pool = notRecent
  }

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
  const reasonStr = matchedViaEmbedding
    ? `selected_embedding:${embeddingSimilarity?.toFixed(2) ?? '?'}`
    : 'selected'

  return {
    phrase: finalPhrase,
    food_canonical_name: canonicalName,
    phrase_id: picked.id,
    reason: reasonStr,
  }
}
