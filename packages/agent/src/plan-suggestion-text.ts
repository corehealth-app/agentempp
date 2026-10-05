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
  error?: unknown
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
 * True when the turn's tool calls are plan-suggestion tools only and each one
 * succeeded and returned its text. The answer of such a turn is fully known
 * (ensureSuggestionShown): the stored suggestion between the fixed opening
 * and closing, with nothing left for the model to write. A refused or failed
 * call, any other tool, or a suggestion without text (the model then says
 * only that it is ready) is not such a turn.
 */
export function isPurePlanSuggestionTurn(toolCalls: readonly ToolCallRecord[]): boolean {
  if (toolCalls.length === 0) return false
  return toolCalls.every((call) => {
    if (!DRAFT_TOOLS.has(call.name) || call.error !== undefined) return false
    const result = call.result as { success?: unknown; sugestao?: unknown } | null | undefined
    return result?.success === true && typeof result.sugestao === 'string' && result.sugestao !== ''
  })
}

/**
 * Every word a message may be made of and still be read as ONE request for a
 * plan (isSingleRequestMessage). Words are compared after
 * singleRequestTokens: lowercase, accents removed.
 *
 * The list is closed on purpose. The direct path answers with the stored
 * suggestion alone, so a second request or a question in the same message
 * gets no answer at all. A rule that looked for marks of a second request
 * (a "?", a second sentence, "e me diga") missed every wording it had not
 * foreseen: a comma, the question first, "tb quero saber", English (second
 * review 2026-10-04). Here the unknown goes the other way: a word that is
 * not in this list — "quanto", "falta", "proteína", "também", "joelho",
 * "tell", any typo or abbreviation — sends the turn to the second model
 * call, as before the direct path existed. Correct first, cheap second.
 *
 * "e" is NOT in the list: it is the word that joins two requests ("Monte uma
 * dieta e um plano pra academia", "…para hoje e outro para amanhã", "1 e 2";
 * third review 2026-10-04). The price is known: a courtesy pair ("por favor
 * e obrigado") takes the second call. "mais", "também" and "tb" were never
 * in it.
 *
 * Adding a word widens the one-call path: add it only if no question or
 * second request can be written with the words already here plus that one.
 * The list itself does not meet that bar in one known class: a yes/no
 * question or a resend request typed without "?" ("Dá pra fazer o treino de
 * hoje em casa", "pode treino hoje", "me passa o treino de hoje") is made
 * only of these words. It is declared, not fixed (RC PERF-C16).
 */
export const SINGLE_REQUEST_VOCABULARY: ReadonlySet<string> = new Set([
  // Request verbs.
  ...['monte', 'monta', 'montar', 'sugira', 'sugere', 'sugerir', 'crie', 'cria', 'criar'],
  ...['faca', 'faz', 'fazer', 'gere', 'gera', 'gerar', 'prepare', 'quero', 'queria', 'preciso'],
  ...['pode', 'poderia', 'consegue', 'me', 'da', 'passa', 'manda'],
  // Plan nouns.
  ...['sugestao', 'cardapio', 'dieta', 'menu', 'plano', 'alimentar', 'alimentacao', 'refeicoes'],
  ...['treino', 'treinos', 'exercicios'],
  // Qualifiers.
  ...['completo', 'completa', 'novo', 'nova', 'simples', 'rapido', 'outro', 'outra'],
  // Time and place (a number is accepted apart, see countsDaysOrTimes).
  ...['hoje', 'amanha', 'agora', 'semana', 'dia', 'dias', 'vezes', 'por', 'na', 'em'],
  ...['casa', 'academia'],
  // Articles, prepositions and pronouns.
  ...['um', 'uma', 'o', 'a', 'os', 'as', 'de', 'do', 'para', 'pra', 'pro'],
  ...['meu', 'minha', 'mim'],
  // Courtesy ("por favor" is "por" above plus "favor").
  ...['oi', 'ola', 'bom', 'boa', 'tarde', 'noite', 'favor', 'pf', 'pfv'],
  ...['obrigado', 'obrigada', 'valeu', 'flow'],
])

/**
 * Replies that are one request although they name no plan, listed whole (the
 * words of singleRequestTokens joined by one space). A reply that takes its
 * meaning from the Flow's previous line is otherwise never a single request
 * (see isSingleRequestMessage).
 *
 * "Pode ser equilibrado no geral." is the patient's answer to the Flow's
 * question about the workout focus in the device turn of 09-30, one of the
 * two turns the one-call path was measured on. It is kept as this one phrase
 * and not as words of the list: with "ser", "no" and "geral" in the list,
 * "Pode ser" and "o treino de hoje pode ser em casa" were single requests
 * too. After a Flow line that offered two things the phrase still ends on
 * the first suggestion (RC PERF-C10).
 */
export const SINGLE_REQUEST_EXACT_REPLIES: ReadonlySet<string> = new Set([
  'pode ser equilibrado no geral',
])

/** Plan nouns that name a menu, and those that name a workout. */
const DIET_NOUNS: ReadonlySet<string> = new Set([
  'cardapio',
  'dieta',
  'menu',
  'alimentar',
  'alimentacao',
  'refeicoes',
])
const WORKOUT_NOUNS: ReadonlySet<string> = new Set(['treino', 'treinos', 'exercicios'])
/**
 * "academia" stands for the workout plan in "um plano pra academia" and
 * "dieta e academia": next to a menu noun it is a second plan (third review
 * 2026-10-04: "Monte uma dieta e um plano pra academia" ended on the menu
 * alone). It is not a request by itself: "na academia" is a place, and a
 * message needs a noun of WORKOUT_NOUNS or DIET_NOUNS to be one.
 */
const TRAINING_NOUNS: ReadonlySet<string> = new Set([...WORKOUT_NOUNS, 'academia'])

/** The nouns that can head a request: the two kinds and the generic ones. */
const REQUEST_NOUNS: ReadonlySet<string> = new Set([
  ...DIET_NOUNS,
  ...WORKOUT_NOUNS,
  'plano',
  'sugestao',
])
/**
 * What may stand between two nouns of ONE request ("sugestão de cardápio",
 * "plano de treino", "um plano novo de dieta", "cardápio da minha dieta").
 * Anything else between them makes two requests ("um cardápio pra hoje
 * cardápio pra amanhã", "um cardápio um plano").
 */
const NOUN_GROUP_LINKS: ReadonlySet<string> = new Set([
  ...['de', 'do', 'da', 'para', 'pra', 'pro', 'meu', 'minha'],
  ...['completo', 'completa', 'novo', 'nova', 'simples', 'rapido'],
])
/**
 * Words that announce a noun. Standing for one instead ("outro para amanhã",
 * "o de amanhã", "os 2", "um pra casa") they are a second request, or a
 * reference to the Flow's previous line.
 */
const DETERMINERS: ReadonlySet<string> = new Set([
  ...['um', 'uma', 'o', 'a', 'os', 'as', 'outro', 'outra'],
])
/** What may stand between a determiner and its noun ("um novo treino", "o meu cardápio"). */
const DETERMINER_FILLERS: ReadonlySet<string> = new Set([
  ...['meu', 'minha', 'novo', 'nova', 'outro', 'outra', 'simples', 'rapido'],
  ...['completo', 'completa'],
])
/** The nouns a determiner may announce: a plan, a time or a place. */
const DETERMINED_NOUNS: ReadonlySet<string> = new Set([
  ...REQUEST_NOUNS,
  ...['academia', 'casa', 'dia', 'dias', 'semana'],
])
/**
 * Greetings and thanks that may stand in a clause of their own next to the
 * request ("Oi, …", "Bom dia!\n…", "…, por favor.", "… Valeu!!").
 */
const COURTESY_PHRASES: readonly (readonly string[])[] = [
  ['bom', 'dia'],
  ['boa', 'tarde'],
  ['boa', 'noite'],
  ['por', 'favor'],
  ...['oi', 'ola', 'pf', 'pfv', 'obrigado', 'obrigada', 'valeu', 'flow'].map((word) => [word]),
]

/** Lowercase, accents removed: the form the lists above are written in. */
function foldCase(message: string): string {
  return message
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
}

/**
 * The words of a message: lowercase, accents removed, and everything that is
 * not a letter or a digit (punctuation, emoji) read as a space.
 */
function singleRequestTokens(message: string): string[] {
  return foldCase(message)
    .split(/[^\p{L}\p{N}]+/u)
    .filter((token) => token !== '')
}

/**
 * The clauses of a message, each as its words: the message is cut at every
 * character that is not a letter, a digit, a space or a tab — a comma, a
 * full stop, a line break, a dash, a bracket, an emoji. A clause with no
 * word is dropped.
 */
function singleRequestClauses(message: string): string[][] {
  return foldCase(message)
    .split(/[^\p{L}\p{N} \t]+/u)
    .map((clause) => clause.split(/[ \t]+/).filter((token) => token !== ''))
    .filter((clause) => clause.length > 0)
}

/** True when the clause is greetings and thanks only (COURTESY_PHRASES). */
function isCourtesyClause(clause: readonly string[]): boolean {
  let index = 0
  while (index < clause.length) {
    const phrase = COURTESY_PHRASES.find((words) =>
      words.every((word, offset) => clause[index + offset] === word),
    )
    if (!phrase) return false
    index += phrase.length
  }
  return true
}

/**
 * True when every determiner of the clause announces a noun: the next word,
 * past the fillers, is one of DETERMINED_NOUNS.
 */
function determinersAnnounceNouns(clause: readonly string[]): boolean {
  return clause.every((token, index) => {
    if (!DETERMINERS.has(token)) return true
    let next = index + 1
    while (next < clause.length && DETERMINER_FILLERS.has(clause[next] as string)) next += 1
    return next < clause.length && DETERMINED_NOUNS.has(clause[next] as string)
  })
}

/**
 * True when every number of the clause counts days or times ("3 dias", "3
 * vezes por semana"). Any other number is a condition on the plan ("um
 * cardápio de 1500", "dieta de 2000 por dia") or a reference to a numbered
 * offer ("o 1"), and the model answers.
 */
function countsDaysOrTimes(clause: readonly string[]): boolean {
  return clause.every(
    (token, index) =>
      !/^\d+$/.test(token) || ['dia', 'dias', 'vezes'].includes(clause[index + 1] ?? ''),
  )
}

/**
 * True when the request nouns of the clause are one group: between the first
 * and the last of them there are only request nouns and NOUN_GROUP_LINKS.
 */
function isOneNounGroup(clause: readonly string[]): boolean {
  const nouns = clause.flatMap((token, index) => (REQUEST_NOUNS.has(token) ? [index] : []))
  const first = nouns[0]
  const last = nouns[nouns.length - 1]
  if (first === undefined || last === undefined) return false
  return clause
    .slice(first, last + 1)
    .every((token) => REQUEST_NOUNS.has(token) || NOUN_GROUP_LINKS.has(token))
}

/**
 * True when the patient's message is known to be a single request for a
 * plan. Only such a message may be answered with the stored suggestion
 * alone: a message that asks for the plan AND for something else ("Monte uma
 * sugestão de cardápio para amanhã. E quanto falta de proteína hoje?") had
 * its second question dropped without a word when the turn looked only at
 * the tools (review 2026-10-04).
 *
 * The message has no question mark and ALL of this holds:
 *  (a) every word is in SINGLE_REQUEST_VOCABULARY or is a number that
 *      counts days or times ("3 dias", "3 vezes");
 *  (b) it names exactly one plan: a menu or a workout, never both
 *      ("academia" next to a menu noun is the workout), in one noun group,
 *      for one day ("hoje" and "amanhã" together are two);
 *  (c) it is one clause: punctuation may only set greetings and thanks
 *      apart ("Oi, …", "…, por favor."), and no "e" joins two requests (the
 *      word is not in the list);
 *  (d) it names its plan itself, with a noun of DIET_NOUNS or WORKOUT_NOUNS,
 *      and every determiner announces a noun. A reply that takes its meaning
 *      from the Flow's previous line — "Quero", "pode", "Pode ser", "manda",
 *      "quero os 2", "1 e 2", "outro" — may be accepting an offer of two
 *      things: it is not a single request (third review 2026-10-04). The one
 *      exception is listed whole in SINGLE_REQUEST_EXACT_REPLIES.
 *
 * The rule reads words, not meaning, and errs to the second model call: a
 * request phrased as a question ("Pode montar um cardápio?"), one in English
 * and one with any word outside the list all keep that call, as does a
 * message with no word at all. What it still does not tell apart is in RC
 * PERF-C10 (docs/mobile/flow-performance.md).
 */
export function isSingleRequestMessage(patientText: string | null | undefined): boolean {
  const message = patientText ?? ''
  // The fullwidth mark is what some keyboards type.
  if (/[?？]/.test(message)) return false
  const tokens = singleRequestTokens(message)
  if (tokens.length === 0) return false
  if (SINGLE_REQUEST_EXACT_REPLIES.has(tokens.join(' '))) return true
  // (a)
  if (!tokens.every((token) => SINGLE_REQUEST_VOCABULARY.has(token) || /^\d+$/.test(token))) {
    return false
  }
  // (c)
  const requests = singleRequestClauses(message).filter((clause) => !isCourtesyClause(clause))
  if (requests.length !== 1) return false
  const request = requests[0] as string[]
  if (!countsDaysOrTimes(request)) return false
  // (d)
  const diet = request.some((token) => DIET_NOUNS.has(token))
  const workout = request.some((token) => WORKOUT_NOUNS.has(token))
  if (!diet && !workout) return false
  if (!determinersAnnounceNouns(request)) return false
  // (b)
  if (diet && request.some((token) => TRAINING_NOUNS.has(token))) return false
  if (request.includes('hoje') && request.includes('amanha')) return false
  return isOneNounGroup(request)
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
