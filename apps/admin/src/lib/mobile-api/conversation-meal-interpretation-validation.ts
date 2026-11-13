import { isDeepStrictEqual } from 'node:util'
import {
  type ConversationMealInterpretationSource,
  freezeInterpretation,
  interpretationModelSchema,
  interpretationUnavailable,
  MEAL_INTERPRETATION_MAX_BYTES,
  type MealInterpretationModelResult,
  validateConversationMealInterpretationSource,
} from './conversation-meal-interpretation-contracts'

// Closed diagnostic vocabulary only; never derived from source/model values.
export const mealInterpretationValidationReasons = Object.freeze([
  'source_contract',
  'model_schema',
  'model_envelope',
  'source_units',
  'source_shape',
  'span_partition',
  'span_range',
  'occurrence_binding',
  'reference_binding',
  'token_boundary',
  'visual_binding',
  'validation_internal',
] as const)
export type MealInterpretationValidationReason =
  (typeof mealInterpretationValidationReasons)[number]
type Reject = (reason: MealInterpretationValidationReason) => never

export type MealInterpretationScreeningReason =
  | 'food_name'
  | 'cross_source_duplicate'
  | 'quantity'
  | 'unit'
  | 'adjacent_unitless_quantity'
  | 'visual_food_name'
  | 'visual_name'
  | 'visual_coverage'
  | 'source_classification'
  | 'unaccounted_discourse'
  | 'report_prefix'
  | 'separator'
  | 'unbound_span'
  | 'report_count'
  | 'missing_media_action'
  | 'positive_reason'

type Ref = NonNullable<MealInterpretationModelResult['foods'][number]['name']>
const plain = (s: string) =>
  s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/\s+/gu, ' ').trim()
const word = (s: string) => /^[\p{L}\p{M}]$/u.test(s)
function boundary(text: string, at: number): boolean {
  if (at <= 0 || at >= text.length) return true
  const left = text.charCodeAt(at - 1),
    right = text.charCodeAt(at)
  return !(left >= 0xd800 && left <= 0xdbff && right >= 0xdc00 && right <= 0xdfff)
}
function range(text: string, start: number, end: number, reject: Reject) {
  if (
    start < 0 ||
    end <= start ||
    end > text.length ||
    !boundary(text, start) ||
    !boundary(text, end)
  )
    return reject('span_range')
}
function tokenEdges(text: string, ref: Ref, reject: Reject) {
  range(text, ref.start, ref.end, reject)
  const before = text[ref.start - 1] ?? '',
    first = text[ref.start] ?? '',
    last = text[ref.end - 1] ?? '',
    after = text[ref.end] ?? ''
  if (
    (word(before) && word(first)) ||
    (word(last) && word(after)) ||
    (/\d/u.test(before) && /\d/u.test(first)) ||
    (/\d/u.test(last) && /\d/u.test(after))
  )
    return reject('token_boundary')
}
const disallowedNominal = new Set(
  'nao nunca jamais nem sem menos mais porem mas ou talvez sera seria sonhei sonhava sonhoque imaginei imaginava penso pensei pretendo planejo vou iria irei comer beber tomar comi comeu comemos comeram comia comem como bebi bebeu tomei tomou consumir consumi ingerir ingeri devorei queria quero gostaria costumo costumava geralmente normalmente sempre ontem amanha anteontem depois antes ele ela eles elas eu voce meu minha nosso nossa filho filha marido esposa disse falou relatou contou que se quando enquanto porque portanto please ignore instructions system assistant user dream dreamed dreamt imagine imagined will would want wanted eat ate eating drink drank usually always never not he she they said told if when tomorrow yesterday'.split(
    ' ',
  ),
)
/** Conservative lexical screening, not proof of food identity or consumption.
 * The writer still needs actual whole-name food resolution: fuzzy matching
 * must never turn unfamiliar prose into an authoritative nominal food span. */
function nominal(text: string): boolean {
  if (
    !text.length ||
    text.length > 160 ||
    text !== text.trim() ||
    /[+−=<>()[\]{}?!"“”«»`]/u.test(text)
  )
    return false
  const normalized = plain(text),
    words = normalized.split(' ')
  // Only the existing mobile whole-recipe names may contain their literal
  // nested count. Materialization must still invoke the exact recipe helper;
  // this does not upgrade discourse framing or grant food/nutrition authority.
  if (
    /^leite(?: integral)? com (?:1|uma) (?:medida|dose) de whey$/u.test(normalized) ||
    /^(?:1|uma) caneca de leite com (?:1|uma) (?:medida|dose) de whey$/u.test(normalized)
  )
    return true
  // Ambiguous discourse framing is not a new food name. In particular a dream
  // adjunct cannot hide inside the same food span as a genuine head noun.
  if (
    /\b(?:no|num|em|durante|in|during) (?:um |uma |the |my )?(?:sonho|sonhos|dream|dreams)\b/u.test(
      normalized,
    ) ||
    /^(?:sobras?|restos?|sugestao|sugestoes|ideia|recomendacao|plano)\b/u.test(normalized)
  )
    return false
  if (
    !words.length ||
    words.some(
      (w) =>
        !/^(?=[\p{L}\p{N}'’-]*\p{L})[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*$/u.test(w) ||
        disallowedNominal.has(w),
    )
  )
    return false
  // Finite narrative verbs cannot hide inside an allegedly nominal food span.
  return !words.some((w) => /(?:mente|ei|aram|avam|eria|eriam|iriam|ing|ed)$/u.test(w))
}
const numberWords = new Set(
  'um uma dois duas tres quatro cinco seis sete oito nove dez meio meia one two three four five half a an'.split(
    ' ',
  ),
)
function quantity(text: string): boolean {
  const v = plain(text)
  return (
    numberWords.has(v) ||
    (/^\d+(?:[.,]\d+)?$/u.test(v) &&
      Number(v.replace(',', '.')) > 0 &&
      Number.isFinite(Number(v.replace(',', '.'))))
  )
}
const units =
  /^(?:g|gr|grs|gramas?|grams?|kg|quilos?|kilograms?|ml|mililitros?|milliliters?|l|litros?|liters?|un|und|unidades?|units?|fatias?|slices?|pedacos?|pieces?|porcoes?|porcao|portions?|colheres?(?: de (?:sopa|cha|sobremesa))?|spoons?|tablespoons?|teaspoons?|copos?|cups?|xicaras?|canecas?|medidas?|scoops?|tigelas?)$/u
function separator(text: string): boolean {
  const words = plain(text)
    .replace(/[\s,;:.!/]+/gu, ' ')
    .trim()
  return (
    !words ||
    words
      .split(' ')
      .every((w) => ['e', 'com', 'de', 'do', 'da', 'dos', 'das', 'and', 'of'].includes(w))
  )
}
function reportMarker(text: string): boolean {
  const v = plain(text).replace(/[:,]$/u, '').trim()
  // One leading meal context is part of the same reporting span. It does not
  // establish consumption without the existing explicit predicate, assign a
  // meal slot/date, or permit any other source text to be omitted. The optional
  // current-day adjunct is still part of the same wholly observed report span.
  return /^(?:no (?:cafe da manha|almoco|jantar)(?: de hoje)?,? )?(?:(?:hoje|agora) )?(?:(?:eu )?(?:comi|bebi|tomei|almocei|jantei|lanchei|ceei|consumi|ingeri)|(?:eu )?acabei de (?:comer|beber|tomar|almocar|jantar|lanchar|cear)|i (?:just )?(?:ate|drank)|i have (?:eaten|drunk))(?: (?:hoje|agora))?$/u.test(
    v,
  )
}
/** The same leading meal adjunct may be labeled separately from its reporting
 * predicate. Account for the entire exact prefix, never arbitrary other words.
 * The positive model decision and the independently validated report still
 * establish consumption; this adjunct cannot establish it by itself. */
function leadingMealContextEnd(
  source: MealInterpretationModelResult['sources'][number],
  text: string,
): number | null {
  if (source.classification !== 'reported') return null
  const reportIndex = source.spans.findIndex((span) => span.kind === 'report'),
    report = source.spans[reportIndex]
  if (
    !report ||
    reportIndex < 1 ||
    source.spans
      .slice(0, reportIndex)
      .some((span) => span.food_index !== null || !['other', 'separator'].includes(span.kind))
  )
    return null
  // A separately labeled first-person subject still belongs to this exact
  // prefix. The following report span must independently contain the genuine
  // consumption predicate; negations, quotes and other clauses remain refused.
  return /^(?:no (?:cafe da manha|almoco|jantar|lanche)|na ceia)(?: de hoje)?,?(?: eu)?$/u.test(
    plain(text.slice(0, report.start)),
  )
    ? report.start
    : null
}
/** An entire trailing meal-context adjunct accounts for source words, not
 * consumption or a quantity. The existing positive decision, complete food
 * refs and genuine reporting predicate (when reported) are still required.
 * Unknown words, dates, negations and questions cannot disappear in it. */
function trailingMealContextStart(
  source: MealInterpretationModelResult['sources'][number],
  text: string,
): number | null {
  if (!['reported', 'nominal_list'].includes(source.classification)) return null
  const lastFood = source.spans.findLastIndex((span) =>
    ['food', 'quantity', 'unit'].includes(span.kind),
  )
  if (lastFood < 0) return null
  const tail = source.spans.slice(lastFood + 1),
    first = tail[0]
  if (
    !first ||
    tail.some(
      (span) => span.food_index !== null || !['other', 'report', 'separator'].includes(span.kind),
    )
  )
    return null
  const context = plain(text.slice(first.start))
    .replace(/^[,;\s]+/u, '')
    .replace(/[.!]+$/u, '')
    .trim()
  return /^(?:no (?:cafe da manha|almoco|jantar|lanche)|na ceia)(?: de hoje)?$/u.test(context)
    ? first.start
    : null
}
const pointer =
  /^(?:(?:meu|minha|my|este|esta|esse|essa|this|a|o) )?(?:almoco|jantar|cafe da manha|lanche|refeicao|prato|meal|plate|breakfast|lunch|dinner|isto|isso|it|this)[.!]?$/u
/** A completed first-person report may refer to the actual bound photograph.
 * Consume only the complete trailing plate pointer, not arbitrary discourse or
 * a textual food/quantity. The model must already report consumption; visual
 * coverage, the reporting predicate and every other source remain validated. */
function trailingPhotoPointerStart(
  source: MealInterpretationModelResult['sources'][number],
  text: string,
  media: ConversationMealInterpretationSource['media_binding'],
  visualCount: number,
): number | null {
  if (
    source.unit !== 'media_caption' ||
    source.classification !== 'reported' ||
    media?.kind !== 'meal_photo' ||
    visualCount === 0
  )
    return null
  const reports = source.spans.filter((span) => span.kind === 'report')
  const report = reports[0]
  if (reports.length !== 1 || !report || !reportMarker(text.slice(report.start, report.end)))
    return null
  const tail = source.spans.filter((span) => span.start >= report.end)
  if (
    !tail.length ||
    tail.some((span) => span.food_index !== null || !['other', 'separator'].includes(span.kind))
  )
    return null
  return pointer.test(plain(text.slice(report.end))) ? report.end : null
}
const positives = new Set(['explicit_report', 'nominal_food_list', 'explicit_media_action'])
function unclear(source: ConversationMealInterpretationSource): MealInterpretationModelResult {
  return freezeInterpretation({
    schema: 'conversation.meal-interpretation.v1',
    decision: 'clarification_required',
    reason: 'ambiguous',
    sources: source.sources.map((s) => ({
      unit: s.unit,
      classification: s.unit === 'vision_items' ? 'visual' : 'ambiguous',
      spans:
        s.text === null
          ? []
          : [{ start: 0, end: s.text.length, kind: 'other' as const, food_index: null }],
      visual_indexes: s.visual_items.map((_, i) => i),
    })),
    foods: [],
  })
}

/** Rejects incomplete/forged references. Structurally valid but unsupported
 * positive claims can only be downgraded; this function never upgrades a claim. */
export function validateConversationMealInterpretationModel(
  raw: unknown,
  originalSource: ConversationMealInterpretationSource,
  onFailure?: (reason: MealInterpretationValidationReason) => void,
  onScreening?: (reasons: readonly MealInterpretationScreeningReason[]) => void,
): MealInterpretationModelResult {
  let failureReason: MealInterpretationValidationReason = 'validation_internal'
  const reject: Reject = (reason) => {
    failureReason = reason
    return interpretationUnavailable()
  }
  try {
    let source: ConversationMealInterpretationSource
    try {
      source = validateConversationMealInterpretationSource(originalSource)
    } catch {
      return reject('source_contract')
    }
    let copy: unknown, result: MealInterpretationModelResult
    try {
      copy = structuredClone(raw)
      result = interpretationModelSchema.parse(copy)
    } catch {
      return reject('model_schema')
    }
    if (
      !isDeepStrictEqual(copy, result) ||
      Buffer.byteLength(JSON.stringify(result), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
    )
      return reject('model_envelope')
    if (
      !isDeepStrictEqual(
        result.sources.map((s) => s.unit),
        source.source_units,
      )
    )
      return reject('source_units')
    const spans = new Map<string, { kind: string; food_index: number | null }>(),
      used = new Set<string>()
    const snippet = new Map(source.sources.map((s) => [s.unit, s]))
    const key = (unit: string, start: number, end: number) => `${unit}:${start}:${end}`
    for (const s of result.sources) {
      const input = snippet.get(s.unit)
      if (!input) return reject('source_units')
      if (s.unit === 'vision_items') {
        if (
          input.text !== null ||
          s.classification !== 'visual' ||
          s.spans.length ||
          !isDeepStrictEqual(
            s.visual_indexes,
            input.visual_items.map((_, i) => i),
          )
        )
          return reject('source_shape')
        continue
      }
      if (
        input.text === null ||
        !input.text.length ||
        s.visual_indexes.length ||
        s.classification === 'visual' ||
        s.spans.length > input.text.length
      )
        return reject('source_shape')
      let cursor = 0
      let activeFood: number | null = null
      const closedFoods = new Set<number>()
      for (const span of s.spans) {
        if (span.start !== cursor) return reject('span_partition')
        range(input.text, span.start, span.end, reject)
        cursor = span.end
        if (span.food_index !== null && span.food_index >= result.foods.length)
          return reject('occurrence_binding')
        if (!['food', 'quantity', 'unit'].includes(span.kind) && span.food_index !== null)
          return reject('occurrence_binding')
        // A quantity/unit cannot jump across another occurrence and return.
        // This rejects swapped amounts even when all independent refs are valid.
        if (span.food_index !== null && span.food_index !== activeFood) {
          if (closedFoods.has(span.food_index)) return reject('occurrence_binding')
          if (activeFood !== null) closedFoods.add(activeFood)
          activeFood = span.food_index
        }
        spans.set(key(s.unit, span.start, span.end), span)
      }
      if (cursor !== input.text.length) return reject('span_partition')
    }
    const readRef = (ref: Ref, kind: string, index: number) => {
      const input = snippet.get(ref.unit),
        k = key(ref.unit, ref.start, ref.end),
        span = spans.get(k)
      if (
        !input ||
        input.text === null ||
        !span ||
        span.kind !== kind ||
        span.food_index !== index ||
        used.has(k)
      )
        return reject('reference_binding')
      tokenEdges(input.text, ref, reject)
      used.add(k)
      return input.text.slice(ref.start, ref.end)
    }
    let safe = true
    const screening = new Set<MealInterpretationScreeningReason>()
    const mark = (reason: MealInterpretationScreeningReason) => {
      safe = false
      screening.add(reason)
    }
    const visual = new Set<number>()
    const namedUnits = new Map<string, string>()
    for (const [index, food] of result.foods.entries()) {
      if (
        food.index !== index ||
        (!food.name && food.visual_index === null) ||
        (food.unit !== null && food.quantity === null)
      )
        return reject('occurrence_binding')
      if (food.name) {
        const name = readRef(food.name, 'food', index)
        if (!nominal(name)) mark('food_name')
        const previousUnit = namedUnits.get(plain(name))
        // Caption and transcript can describe the same occurrence. Without an
        // independent association, neither adding nor merging is justified.
        if (previousUnit !== undefined && previousUnit !== food.name.unit)
          mark('cross_source_duplicate')
        namedUnits.set(plain(name), food.name.unit)
      }
      if (food.quantity && !quantity(readRef(food.quantity, 'quantity', index))) mark('quantity')
      if (food.unit && !units.test(plain(readRef(food.unit, 'unit', index)))) mark('unit')
      if (food.quantity && food.name && food.quantity.unit !== food.name.unit)
        return reject('occurrence_binding')
      if (food.unit && food.quantity && food.unit.unit !== food.quantity.unit)
        return reject('occurrence_binding')
      if (food.quantity && food.name && !food.unit && food.quantity.start === food.name.end)
        mark('adjacent_unitless_quantity')
      if (food.visual_index !== null) {
        const items = snippet.get('vision_items')?.visual_items
        if (!items || food.visual_index >= items.length || visual.has(food.visual_index))
          return reject('visual_binding')
        visual.add(food.visual_index)
        const item = items[food.visual_index]
        if (
          !item ||
          typeof item !== 'object' ||
          Array.isArray(item) ||
          typeof item.name !== 'string' ||
          !nominal(item.name)
        )
          mark('visual_food_name')
        else if (food.name) {
          const text = snippet.get(food.name.unit)?.text ?? ''
          if (plain(text.slice(food.name.start, food.name.end)) !== plain(item.name))
            mark('visual_name')
        }
      }
    }
    for (const [k, span] of spans)
      if (span.food_index !== null && !used.has(k)) return reject('reference_binding')
    if (result.decision !== 'reported_meal') {
      if (
        positives.has(result.reason) ||
        (result.decision === 'not_reported' && result.foods.length)
      )
        return unclear(source)
      return freezeInterpretation(result)
    }
    if (!result.foods.length || !positives.has(result.reason)) return unclear(source)
    for (const s of result.sources) {
      const input = snippet.get(s.unit)
      if (!input) return reject('source_units')
      if (s.unit === 'vision_items') {
        if (visual.size !== input.visual_items.length) mark('visual_coverage')
        continue
      }
      if (!['reported', 'nominal_list', 'media_pointer'].includes(s.classification))
        mark('source_classification')
      let reports = 0
      let hasFood = false
      const leadingContextEnd = leadingMealContextEnd(s, input.text ?? '')
      const contextStart = trailingMealContextStart(s, input.text ?? '')
      const photoPointerStart = trailingPhotoPointerStart(
        s,
        input.text ?? '',
        source.media_binding,
        visual.size,
      )
      for (const span of s.spans) {
        const text = (input.text ?? '').slice(span.start, span.end)
        if (leadingContextEnd !== null && span.end <= leadingContextEnd) continue
        if (contextStart !== null && span.start >= contextStart) continue
        if (photoPointerStart !== null && span.start >= photoPointerStart) continue
        if (span.kind === 'other') {
          // Labeling inert punctuation as `other` must not discard an otherwise
          // complete report. Words, numbers, quotes and question marks still
          // require semantic accounting; this never upgrades a model refusal.
          if (
            !/^[\s,;:.!/]+$/u.test(text) &&
            !(
              s.classification === 'media_pointer' &&
              source.media_binding &&
              pointer.test(plain(input.text ?? ''))
            )
          )
            mark('unaccounted_discourse')
        } else if (span.kind === 'report') {
          reports += 1
          if (hasFood || !reportMarker(text)) mark('report_prefix')
        } else if (span.kind === 'separator' && !separator(text)) mark('separator')
        else if (['food', 'quantity', 'unit'].includes(span.kind) && span.food_index === null)
          mark('unbound_span')
        if (span.kind === 'food') hasFood = true
      }
      if (s.classification === 'reported' && reports !== 1) mark('report_count')
      if (s.classification !== 'reported' && reports) mark('report_count')
      if (s.classification === 'media_pointer' && !source.media_binding)
        mark('missing_media_action')
    }
    if (
      source.media_binding === null &&
      ((result.sources[0]?.classification === 'reported' && result.reason !== 'explicit_report') ||
        (result.sources[0]?.classification === 'nominal_list' &&
          result.reason !== 'nominal_food_list'))
    )
      mark('positive_reason')
    if (result.reason === 'explicit_media_action' && !source.media_binding)
      mark('missing_media_action')
    if (!safe) {
      try {
        onScreening?.(Object.freeze([...screening].sort()))
      } catch {
        // Closed observation cannot change a refusal or invoke another attempt.
      }
    }
    return safe ? freezeInterpretation(result) : unclear(source)
  } catch {
    try {
      onFailure?.(failureReason)
    } catch {
      // Observation cannot change rejection or authorize another attempt.
    }
    return interpretationUnavailable()
  }
}
