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
  let best: { food_name: string; weight: number } | null = null
  for (const it of items) {
    // Peso: kcal + bonus por densidade proteica + bonus por densidade gorda
    const proteinDensity = it.kcal > 0 ? (it.protein_g * 4) / it.kcal : 0
    const fatDensity = it.kcal > 0 ? (it.fat_g * 9) / it.kcal : 0
    const weight = it.kcal + proteinDensity * 50 + fatDensity * 30
    if (!best || weight > best.weight) {
      best = { food_name: it.food_name, weight }
    }
  }
  return best
}

/**
 * Normaliza nome pra match em `food_canonical_name`.
 */
function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  const { data: rows } = await sp
    .from('food_education_phrases')
    .select('id, phrase, tags, usage_count, last_used_at')
    .eq('active', true)
    .eq('language', language)
    .ilike('food_canonical_name', canonicalName)
    .order('last_used_at', { ascending: true, nullsFirst: true })
    .limit(50)

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

  const pool = filtered.length > 0 ? filtered : candidates

  // Sorteio determinístico: pega a primeira do pool (já ordenada por
  // last_used_at ASC NULLS FIRST → menos usada vem primeiro).
  const picked = pool[0]
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

  return {
    phrase: picked.phrase,
    food_canonical_name: canonicalName,
    phrase_id: picked.id,
    reason: 'selected',
  }
}
