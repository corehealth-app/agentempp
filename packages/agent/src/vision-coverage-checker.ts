/**
 * vision-coverage-checker — telemetria de cobertura de fotos (audit 06-25 Bug B).
 *
 * Caso real Roberto 2026-06-25 13:08: 2 fotos do almoço (prato + salada) =
 * 2 product_events `vision.analyzed` com mesmo `provider_message_id`. LLM
 * fez pergunta intermediária ("que carne era?"), turno seguinte só
 * reconstruiu o prato (4 itens) — salada (5 itens, ~245 kcal) sumiu
 * silenciosamente.
 *
 * Este helper detecta a perda: antes do tool_call de registra_refeicao
 * gravar, carrega TODAS as visions recentes (30min), agrupa por pmid e
 * computa overlap entre items dos visions e items[] do tool_call. Se
 * overlap < threshold, emite `pipeline.vision_coverage_warning` com detalhe
 * pra audit identificar o problema e Camada A do fix bloquear futuro.
 *
 * Versão 1: SÓ telemetria — não gateia o gravação. Calibra threshold com
 * dado de prod antes de virar bloqueio (golden tests cobertos primeiro).
 */

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type SupabaseClient = any

export interface VisionItem {
  name: string
  quantity_g_estimate?: number
  confidence?: number
}

export interface RecentVision {
  provider_message_id: string | null
  items: VisionItem[]
  occurred_at: string
}

export interface CoverageReport {
  vision_items_count: number
  tool_items_count: number
  overlap_count: number
  overlap_ratio: number
  missing_from_tool_call: string[]
  pmids_checked: string[]
  visions_count: number
}

const stripAccents = (s: string) =>
  s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').trim()

/**
 * Carrega TODAS visions dos últimos N minutos pro user, agrupadas por
 * provider_message_id (1 entry por foto). Filtra type=meal.
 */
export async function loadRecentVisionAnalyzed(
  supabase: SupabaseClient,
  userId: string,
  sinceMinutes = 30,
): Promise<RecentVision[]> {
  const sinceIso = new Date(Date.now() - sinceMinutes * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('product_events')
    .select('properties, occurred_at')
    .eq('user_id', userId)
    .eq('event', 'vision.analyzed')
    .gte('occurred_at', sinceIso)
    .order('occurred_at', { ascending: false })
    .limit(20)
  if (error) return []
  const rows = (data ?? []) as Array<{
    properties: {
      type?: string
      provider_message_id?: string | null
      meal_items?: VisionItem[] | null
    }
    occurred_at: string
  }>
  return rows
    .filter((r) => r.properties.type === 'meal')
    .filter((r) => Array.isArray(r.properties.meal_items) && r.properties.meal_items.length > 0)
    .map((r) => ({
      provider_message_id: r.properties.provider_message_id ?? null,
      items: r.properties.meal_items ?? [],
      occurred_at: r.occurred_at,
    }))
}

/**
 * Computa cobertura entre items detectados pelas visions vs items que a
 * tool_call vai registrar. overlap_ratio = (items vision presentes no
 * tool_call) / (items vision totais). Threshold sugerido pra warning: <0.7.
 *
 * Normaliza nomes (lower + sem acentos + trim) antes de comparar.
 * Considera apenas visions que ainda não viraram meal_log (gate fora deste
 * helper — quem chama deve filtrar primeiro).
 */
export function checkCoverage(
  visions: RecentVision[],
  toolCallItems: Array<{ food_name: string }>,
): CoverageReport {
  const toolSet = new Set(toolCallItems.map((i) => stripAccents(i.food_name)))
  const visionSet = new Set<string>()
  const pmidsChecked: string[] = []
  for (const v of visions) {
    if (v.provider_message_id) pmidsChecked.push(v.provider_message_id)
    for (const it of v.items) visionSet.add(stripAccents(it.name))
  }
  let overlap = 0
  const missing: string[] = []
  for (const v of visionSet) {
    if (toolSet.has(v)) overlap++
    else missing.push(v)
  }
  const overlapRatio = visionSet.size > 0 ? overlap / visionSet.size : 1
  return {
    vision_items_count: visionSet.size,
    tool_items_count: toolSet.size,
    overlap_count: overlap,
    overlap_ratio: overlapRatio,
    missing_from_tool_call: missing,
    pmids_checked: pmidsChecked,
    visions_count: visions.length,
  }
}

/**
 * Helper de telemetria — chamado antes do tool.execute(registra_refeicao).
 * Se overlap < threshold (default 0.7) E há ≥2 visions OU visões com
 * mais de N items detectados, emite product_event pra audit pegar.
 * NÃO gateia gravação — só observa por enquanto.
 */
/**
 * Threshold padrão de cobertura — vira warning se overlap < threshold E há
 * ≥3 items vision pendentes. Audit 06-26 sprint pendentes: env var
 * `VISION_COVERAGE_THRESHOLD` (0-1) permite calibrar entre deploys.
 *
 * Review LOW 06-26: leitura on-call (não module-load const) — em Vercel
 * serverless cada cold start lê o env atual, mas warm instances podem
 * cachear. Function call garante leitura por chamada. Em prática, mudar
 * VISION_COVERAGE_THRESHOLD ainda exige redeploy no Vercel (env vars são
 * snapshot do deploy), mas o código fica preparado pra ambientes com
 * env mutável (Dev/CI).
 */
function getThreshold(): number {
  const env = process.env.VISION_COVERAGE_THRESHOLD
  if (!env) return 0.7
  const n = Number.parseFloat(env)
  if (Number.isNaN(n) || n < 0 || n > 1) return 0.7
  return n
}

export async function reportVisionCoverageIfLow(
  supabase: SupabaseClient,
  userId: string,
  toolCallItems: Array<{ food_name: string }>,
  threshold = getThreshold(),
): Promise<CoverageReport | null> {
  const visions = await loadRecentVisionAnalyzed(supabase, userId, 30)
  if (visions.length === 0) return null

  // Review HIGH 5 (audit 06-25): filtra visions já consumidas em meal_logs
  // recentes antes de checar cobertura. Sem isso, visions de turnos antigos
  // (já registrados) ficam acumulando warnings falsos. Critério: vision tem
  // pmid → buscar meal_log com mesmo pmid. Se existe, considera consumida.
  const sinceIso = new Date(Date.now() - 30 * 60 * 1000).toISOString()
  const { data: recentMeals } = await supabase
    .from('meal_logs')
    .select('raw_provider_message_id')
    .eq('user_id', userId)
    .gte('created_at', sinceIso)
  const consumedPmids = new Set<string>(
    ((recentMeals ?? []) as Array<{ raw_provider_message_id?: string | null }>)
      .map((r) => r.raw_provider_message_id ?? null)
      .filter((p): p is string => typeof p === 'string' && p.length > 0),
  )
  const pendingVisions = visions.filter((v) => {
    if (!v.provider_message_id) return true
    return !consumedPmids.has(v.provider_message_id)
  })
  if (pendingVisions.length === 0) return null

  const report = checkCoverage(pendingVisions, toolCallItems)
  // Só alerta quando há visões reais E gap (>=3 items vision E ratio < threshold).
  if (report.vision_items_count >= 3 && report.overlap_ratio < threshold) {
    try {
      await supabase.from('product_events').insert({
        user_id: userId,
        event: 'pipeline.vision_coverage_warning',
        properties: {
          ...report,
          threshold,
        },
      })
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn('[vision-coverage] event insert failed (non-fatal):', e)
    }
  }
  return report
}
