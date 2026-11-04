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
function range(text: string, start: number, end: number) {
  if (
    start < 0 ||
    end <= start ||
    end > text.length ||
    !boundary(text, start) ||
    !boundary(text, end)
  )
    return interpretationUnavailable()
}
function tokenEdges(text: string, ref: Ref) {
  range(text, ref.start, ref.end)
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
    return interpretationUnavailable()
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
  return /^(?:(?:hoje|agora) )?(?:(?:eu )?(?:comi|bebi|tomei|almocei|jantei|lanchei|ceei|consumi|ingeri)|(?:eu )?acabei de (?:comer|beber|tomar)|i (?:just )?(?:ate|drank)|i have (?:eaten|drunk))(?: (?:hoje|agora))?$/u.test(
    v,
  )
}
const pointer =
  /^(?:(?:meu|minha|my|este|esta|esse|essa|this|a|o) )?(?:almoco|jantar|cafe da manha|lanche|refeicao|prato|meal|plate|breakfast|lunch|dinner|isto|isso|it|this)[.!]?$/u
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
): MealInterpretationModelResult {
  try {
    const source = validateConversationMealInterpretationSource(originalSource)
    const copy = structuredClone(raw),
      result = interpretationModelSchema.parse(copy)
    if (
      !isDeepStrictEqual(copy, result) ||
      Buffer.byteLength(JSON.stringify(result), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES ||
      !isDeepStrictEqual(
        result.sources.map((s) => s.unit),
        source.source_units,
      )
    )
      return interpretationUnavailable()
    const spans = new Map<string, { kind: string; food_index: number | null }>(),
      used = new Set<string>()
    const snippet = new Map(source.sources.map((s) => [s.unit, s]))
    const key = (unit: string, start: number, end: number) => `${unit}:${start}:${end}`
    for (const s of result.sources) {
      const input = snippet.get(s.unit)
      if (!input) return interpretationUnavailable()
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
          return interpretationUnavailable()
        continue
      }
      if (
        input.text === null ||
        !input.text.length ||
        s.visual_indexes.length ||
        s.classification === 'visual' ||
        s.spans.length > input.text.length
      )
        return interpretationUnavailable()
      let cursor = 0
      let activeFood: number | null = null
      const closedFoods = new Set<number>()
      for (const span of s.spans) {
        if (span.start !== cursor) return interpretationUnavailable()
        range(input.text, span.start, span.end)
        cursor = span.end
        if (span.food_index !== null && span.food_index >= result.foods.length)
          return interpretationUnavailable()
        if (!['food', 'quantity', 'unit'].includes(span.kind) && span.food_index !== null)
          return interpretationUnavailable()
        // A quantity/unit cannot jump across another occurrence and return.
        // This rejects swapped amounts even when all independent refs are valid.
        if (span.food_index !== null && span.food_index !== activeFood) {
          if (closedFoods.has(span.food_index)) return interpretationUnavailable()
          if (activeFood !== null) closedFoods.add(activeFood)
          activeFood = span.food_index
        }
        spans.set(key(s.unit, span.start, span.end), span)
      }
      if (cursor !== input.text.length) return interpretationUnavailable()
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
        return interpretationUnavailable()
      tokenEdges(input.text, ref)
      used.add(k)
      return input.text.slice(ref.start, ref.end)
    }
    let safe = true
    const visual = new Set<number>()
    const namedUnits = new Map<string, string>()
    for (const [index, food] of result.foods.entries()) {
      if (
        food.index !== index ||
        (!food.name && food.visual_index === null) ||
        (food.unit !== null && food.quantity === null)
      )
        return interpretationUnavailable()
      if (food.name) {
        const name = readRef(food.name, 'food', index)
        if (!nominal(name)) safe = false
        const previousUnit = namedUnits.get(plain(name))
        // Caption and transcript can describe the same occurrence. Without an
        // independent association, neither adding nor merging is justified.
        if (previousUnit !== undefined && previousUnit !== food.name.unit) safe = false
        namedUnits.set(plain(name), food.name.unit)
      }
      if (food.quantity && !quantity(readRef(food.quantity, 'quantity', index))) safe = false
      if (food.unit && !units.test(plain(readRef(food.unit, 'unit', index)))) safe = false
      if (food.quantity && food.name && food.quantity.unit !== food.name.unit)
        return interpretationUnavailable()
      if (food.unit && food.quantity && food.unit.unit !== food.quantity.unit)
        return interpretationUnavailable()
      if (food.quantity && food.name && !food.unit && food.quantity.start === food.name.end)
        safe = false
      if (food.visual_index !== null) {
        const items = snippet.get('vision_items')?.visual_items
        if (!items || food.visual_index >= items.length || visual.has(food.visual_index))
          return interpretationUnavailable()
        visual.add(food.visual_index)
        const item = items[food.visual_index]
        if (
          !item ||
          typeof item !== 'object' ||
          Array.isArray(item) ||
          typeof item.name !== 'string' ||
          !nominal(item.name)
        )
          safe = false
        else if (food.name) {
          const text = snippet.get(food.name.unit)?.text ?? ''
          if (plain(text.slice(food.name.start, food.name.end)) !== plain(item.name)) safe = false
        }
      }
    }
    for (const [k, span] of spans)
      if (span.food_index !== null && !used.has(k)) return interpretationUnavailable()
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
      if (!input) return interpretationUnavailable()
      if (s.unit === 'vision_items') {
        if (visual.size !== input.visual_items.length) safe = false
        continue
      }
      if (!['reported', 'nominal_list', 'media_pointer'].includes(s.classification)) safe = false
      let reports = 0
      let hasFood = false
      for (const span of s.spans) {
        const text = (input.text ?? '').slice(span.start, span.end)
        if (span.kind === 'other') {
          if (
            !(
              s.classification === 'media_pointer' &&
              source.media_binding &&
              pointer.test(plain(input.text ?? ''))
            )
          )
            safe = false
        } else if (span.kind === 'report') {
          reports += 1
          if (hasFood || !reportMarker(text)) safe = false
        } else if (span.kind === 'separator' && !separator(text)) safe = false
        else if (['food', 'quantity', 'unit'].includes(span.kind) && span.food_index === null)
          safe = false
        if (span.kind === 'food') hasFood = true
      }
      if (s.classification === 'reported' && reports !== 1) safe = false
      if (s.classification !== 'reported' && reports) safe = false
      if (s.classification === 'media_pointer' && !source.media_binding) safe = false
    }
    if (
      source.media_binding === null &&
      ((result.sources[0]?.classification === 'reported' && result.reason !== 'explicit_report') ||
        (result.sources[0]?.classification === 'nominal_list' &&
          result.reason !== 'nominal_food_list'))
    )
      safe = false
    if (result.reason === 'explicit_media_action' && !source.media_binding) safe = false
    return safe ? freezeInterpretation(result) : unclear(source)
  } catch {
    return interpretationUnavailable()
  }
}
