/**
 * Detector de "modo EXPRESS" — Roberto 2026-05-28 (Fase B botões #4).
 *
 * Decide se um registro de refeição pode pular o botão e ir direto pra
 * gravação, OU se precisa propor + aguardar tap. Default conservador: na
 * dúvida, vai pra botão (proteção contra gravação errada).
 *
 * Critério (DEC-1 do plano em /root/.claude/plans/botoes-whatsapp.md):
 *   - foto/áudio = NUNCA express (estimativa visual/transcrição = sempre incerto)
 *   - texto com palavra de incerteza ("uns 100g", "mais ou menos", "talvez") = não express
 *   - texto SEM gramatura/unidade explícita pra cada item = não express
 *   - tudo bate = express
 *
 * Pura — sem I/O, sem dependência de supabase/LLM. Testável.
 */

const UNCERTAINTY_MARKERS =
  /\b(uns?|umas?|mais\s+ou\s+menos|talvez|acho\s+que|por\s+a[íi]|aproximadamente|cerca\s+de|sei\s+l[áa]|chuto|chutei|n[ãa]o\s+sei\s+bem|mais\/menos|nao\s+tenho\s+certeza)\b/i

// Quantidades explícitas: contagem genérica de NÚMEROS no texto. Cobre tanto
// "100g"/"200ml" (com unidade) quanto "2 ovos"/"3 pães" (número + nome do
// alimento). Heurística aproximada — sobra rara (false positive) leva a
// gravar direto algo que devia ir pra botão; o lado conservador (botão) é
// preferido na dúvida e está garantido pelos outros checks.
const QUANTITY_MARKERS_GLOBAL = /\b\d+(?:[.,]\d+)?/g

export interface ExpressInput {
  contentType: 'text' | 'image' | 'audio'
  patientText: string
  items: Array<{ food_name: string; quantity_g?: number | null }>
}

export interface ExpressResult {
  eligible: boolean
  reason: string
  qty_markers_found?: number
  items_count?: number
}

// Duração explícita no texto: "30 min", "30 minutos", "1 h", "1 hora".
const DURATION_REGEX = /\b\d+\s*(min|minuto|hora|h\b)/i

export interface WorkoutExpressInput {
  contentType: 'text' | 'image' | 'audio'
  patientText: string
  workoutType?: string | null
  durationMin?: number | null
}

/**
 * Detector de express pra TREINO (Fase D botões #4).
 * Texto claro com duração explícita ("30 min de caminhada") = express.
 * Foto/áudio/vago = botão.
 */
export function isWorkoutExpressEligible(input: WorkoutExpressInput): ExpressResult {
  if (input.contentType !== 'text') {
    return { eligible: false, reason: `content_type_${input.contentType}` }
  }
  if (!input.patientText || input.patientText.trim().length === 0) {
    return { eligible: false, reason: 'empty_text' }
  }
  if (UNCERTAINTY_MARKERS.test(input.patientText)) {
    return { eligible: false, reason: 'uncertainty_marker' }
  }
  if (!input.workoutType) {
    return { eligible: false, reason: 'no_workout_type' }
  }
  if (!input.durationMin || input.durationMin <= 0) {
    return { eligible: false, reason: 'no_duration' }
  }
  if (!DURATION_REGEX.test(input.patientText)) {
    return { eligible: false, reason: 'no_explicit_duration_in_text' }
  }
  return { eligible: true, reason: 'ok' }
}

export function isMealExpressEligible(input: ExpressInput): ExpressResult {
  if (input.contentType !== 'text') {
    return { eligible: false, reason: `content_type_${input.contentType}` }
  }
  if (!input.patientText || input.patientText.trim().length === 0) {
    return { eligible: false, reason: 'empty_text' }
  }
  if (UNCERTAINTY_MARKERS.test(input.patientText)) {
    return { eligible: false, reason: 'uncertainty_marker' }
  }
  if (input.items.length === 0) {
    return { eligible: false, reason: 'no_items' }
  }
  const qtyMatches = input.patientText.match(QUANTITY_MARKERS_GLOBAL) ?? []
  const qtyCount = qtyMatches.length
  if (qtyCount < input.items.length) {
    return {
      eligible: false,
      reason: 'qty_count_mismatch',
      qty_markers_found: qtyCount,
      items_count: input.items.length,
    }
  }
  return {
    eligible: true,
    reason: 'ok',
    qty_markers_found: qtyCount,
    items_count: input.items.length,
  }
}
