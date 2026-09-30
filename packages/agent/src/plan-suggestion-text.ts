/**
 * Texto da sugestão de plano que o Flow mostra no chat.
 *
 * Renderizado a partir do rascunho GRAVADO (o mesmo payload que o paciente
 * revisa no app), nunca da saída bruta do gerador: o chat e a tela "Revisar
 * sugestão" mostram os mesmos exercícios, alimentos e números. Campos que o
 * rascunho não tem (ou que a validação limpou) simplesmente não aparecem;
 * nada é calculado ou completado aqui, exceto a soma do dia das refeições
 * mostradas.
 *
 * Um item que fala de medicamento, dose ou suplemento NUNCA aparece no chat
 * (o Flow não indica nada disso): ele fica só na revisão, onde o app o marca,
 * e o texto diz quantos itens precisam de revisão.
 */
import { classifyHealthProduct } from './plan-draft.js'

// biome-ignore lint/suspicious/noExplicitAny: payload jsonb já validado por plan-draft
type Payload = any

const MEAL_LABELS: Record<string, string> = {
  cafe: 'Café da manhã',
  lanche_manha: 'Lanche da manhã',
  almoco: 'Almoço',
  lanche_tarde: 'Lanche da tarde',
  jantar: 'Jantar',
  ceia: 'Ceia',
}

const WEEKDAYS = ['', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo']

/**
 * Limite do texto (~700 tokens): cabe no max_tokens do Flow junto da abertura
 * e do fecho; o resto fica na revisão.
 */
export const PLAN_SUGGESTION_TEXT_MAX = 2000

export const PLAN_SUGGESTION_TRUNCATED = '(O restante está em "Revisar sugestão".)'

function num(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null
}

function formatNumber(value: number, digits = 1): string {
  return new Intl.NumberFormat('pt-BR', { maximumFractionDigits: digits }).format(value)
}

/** O que o paciente vê na revisão: a medida caseira e, sempre, os gramas. */
function quantityOf(item: Payload): string | null {
  const grams = num(item?.quantity_g)
  const displayQty = num(item?.display_qty)
  const displayUnit = text(item?.display_unit)
  const gramsText = grams !== null ? `${formatNumber(grams, 2)} g` : null
  if (displayQty !== null && displayUnit) {
    const household = `${formatNumber(displayQty, 2)} ${displayUnit}`
    return gramsText ? `${household} (${gramsText})` : household
  }
  return gramsText
}

function isHealthProduct(name: string): boolean {
  return classifyHealthProduct(name, 'item') !== null
}

function withheldNote(count: number): string | null {
  if (count === 0) return null
  return count === 1
    ? '1 item precisa ser conferido em "Revisar sugestão" e não aparece aqui.'
    : `${count} itens precisam ser conferidos em "Revisar sugestão" e não aparecem aqui.`
}

/**
 * Junta os blocos (um por dia ou refeição) sem cortar nenhum no meio. O que
 * não cabe fica na revisão; o rodapé (total, avisos) nunca é cortado.
 */
function assemble(blocks: string[][], footer: string[]): string {
  const footerText = footer.join('\n')
  const budget =
    PLAN_SUGGESTION_TEXT_MAX -
    (footerText ? footerText.length + 2 : 0) -
    (PLAN_SUGGESTION_TRUNCATED.length + 2)
  const shown: string[] = []
  let length = 0
  let truncated = false
  for (const block of blocks) {
    const blockText = block.join('\n')
    const cost = blockText.length + (shown.length > 0 ? 2 : 0)
    if (length + cost > budget) {
      truncated = true
      break
    }
    shown.push(blockText)
    length += cost
  }
  const parts = [...shown]
  if (truncated) parts.push(PLAN_SUGGESTION_TRUNCATED)
  if (footerText) parts.push(footerText)
  return parts.join('\n\n').trim()
}

export function trainingSuggestionText(payload: Payload): string {
  const blocks: string[][] = []
  let withheld = 0
  const days = Array.isArray(payload?.weekly_schedule) ? payload.weekly_schedule : []
  for (const day of days) {
    const block: string[] = []
    const header = [text(day?.day), text(day?.focus)].filter(Boolean).join(' — ')
    const minutes = num(day?.duration_min)
    if (header) block.push(minutes !== null ? `${header} (${formatNumber(minutes)} min)` : header)
    for (const exercise of Array.isArray(day?.exercises) ? day.exercises : []) {
      const name = text(exercise?.name)
      if (!name) continue
      if (isHealthProduct(name)) {
        withheld += 1
        continue
      }
      const sets = num(exercise?.sets)
      const reps = text(exercise?.reps_range)
      const rest = num(exercise?.rest_seconds)
      const volume =
        sets !== null && reps
          ? `${formatNumber(sets)}×${reps}`
          : sets !== null
            ? `${formatNumber(sets)} séries`
            : reps
      const parts = [volume, rest !== null && rest > 0 ? `descanso ${formatNumber(rest)} s` : null]
        .filter(Boolean)
        .join(', ')
      block.push(parts ? `• ${name} — ${parts}` : `• ${name}`)
    }
    if (block.length > 0) blocks.push(block)
  }
  const progression = text(payload?.progression_rule)
  if (progression && !isHealthProduct(progression)) blocks.push([`Progressão: ${progression}`])
  const note = withheldNote(withheld)
  return assemble(blocks, note ? [note] : [])
}

export function nutritionSuggestionText(payload: Payload): string {
  const blocks: string[][] = []
  const footer: string[] = []
  let withheld = 0
  const meals = Array.isArray(payload?.daily_meals) ? payload.daily_meals : []
  // Semanal: o chat mostra o primeiro dia; a semana inteira fica na revisão.
  const days = [
    ...new Set(
      meals.map((meal: Payload) => num(meal?.day_of_week)).filter((d: number | null) => d !== null),
    ),
  ] as number[]
  const firstDay = days.length > 1 ? Math.min(...days) : null
  const shown =
    firstDay === null ? meals : meals.filter((meal: Payload) => num(meal?.day_of_week) === firstDay)
  if (firstDay !== null) {
    blocks.push([`${WEEKDAYS[firstDay] ?? 'Dia 1'} (os outros dias estão em "Revisar sugestão")`])
  }

  let dayKcal = 0
  let dayProtein = 0
  let totalsComplete = shown.length > 0
  for (const meal of shown) {
    const label = MEAL_LABELS[meal?.meal_type] ?? 'Refeição'
    const time = text(meal?.time_suggestion)
    const kcal = num(meal?.total_kcal)
    const protein = num(meal?.total_protein_g)
    const facts = [
      kcal !== null ? `${formatNumber(kcal)} kcal` : null,
      protein !== null ? `${formatNumber(protein)} g de proteína` : null,
    ].filter(Boolean)
    const block = [
      `${label}${time ? ` (${time})` : ''}${facts.length > 0 ? ` — ${facts.join(', ')}` : ''}`,
    ]
    for (const item of Array.isArray(meal?.items) ? meal.items : []) {
      const food = text(item?.food_name)
      if (!food) continue
      if (isHealthProduct(food)) {
        withheld += 1
        continue
      }
      const quantity = quantityOf(item)
      block.push(quantity ? `• ${food}: ${quantity}` : `• ${food}`)
    }
    blocks.push(block)
    if (kcal === null || protein === null) totalsComplete = false
    else {
      dayKcal += kcal
      dayProtein += protein
    }
  }

  // Com item retido, a soma incluiria algo que o chat não mostra: fica na revisão.
  if (totalsComplete && withheld === 0) {
    const metaKcal = num(payload?.meta_kcal)
    const metaProtein = num(payload?.meta_protein_g)
    // Meta 0 é "sem meta" (o gerador grava 0 quando não há meta oficial).
    const meta =
      metaKcal !== null && metaKcal > 0 && metaProtein !== null && metaProtein > 0
        ? ` (meta: ${formatNumber(metaKcal)} kcal, ${formatNumber(metaProtein)} g)`
        : ''
    footer.push(
      `Total do dia: ${formatNumber(dayKcal)} kcal, ${formatNumber(dayProtein)} g de proteína${meta}`,
    )
  }
  const note = withheldNote(withheld)
  if (note) footer.push(note)
  return assemble(blocks, footer)
}

// --- Garantia de que o paciente vê a sugestão -------------------------------

const DRAFT_TOOLS = new Set(['propoe_plano_treino', 'propoe_plano_dieta'])

interface ToolCallRecord {
  name: string
  result?: unknown
}

function squash(value: string): string {
  return value.replace(/\s+/g, ' ').trim()
}

/**
 * As sugestões que as ferramentas de rascunho devolveram com sucesso neste
 * turno (na ordem em que foram criadas).
 */
export function turnSuggestions(
  toolCalls: readonly ToolCallRecord[],
): Array<{ sugestao: string; needsCompletion: boolean }> {
  const out: Array<{ sugestao: string; needsCompletion: boolean }> = []
  for (const call of toolCalls) {
    if (!DRAFT_TOOLS.has(call.name)) continue
    const result = call.result as { success?: unknown; sugestao?: unknown; status?: unknown }
    if (result?.success !== true || typeof result.sugestao !== 'string' || !result.sugestao)
      continue
    if (out.some((entry) => entry.sugestao === result.sugestao)) continue
    out.push({ sugestao: result.sugestao, needsCompletion: result.status === 'needs_completion' })
  }
  return out
}

/**
 * Se o modelo resumiu, parafraseou ou omitiu a sugestão, a resposta passa a
 * ser o texto gravado com uma abertura e um fecho fixos. Assim o chat nunca
 * mostra um plano diferente do rascunho, nem um resumo genérico.
 */
export function ensureSuggestionShown(
  finalText: string,
  toolCalls: readonly ToolCallRecord[],
): { text: string; replaced: boolean } {
  const suggestions = turnSuggestions(toolCalls)
  if (suggestions.length === 0) return { text: finalText, replaced: false }
  const squashed = squash(finalText)
  if (suggestions.every((entry) => squashed.includes(squash(entry.sugestao)))) {
    return { text: finalText, replaced: false }
  }
  const parts = [
    suggestions.length === 1 ? 'Sua sugestão está pronta:' : 'Suas sugestões estão prontas:',
    ...suggestions.map((entry) => entry.sugestao),
  ]
  if (suggestions.some((entry) => entry.needsCompletion)) {
    parts.push('Alguns campos ficaram para você completar na revisão.')
  }
  parts.push(
    'É um rascunho: toque em "Revisar sugestão" para conferir, ajustar e confirmar. Ele só vale depois que você confirmar.',
  )
  return { text: parts.join('\n\n'), replaced: true }
}
