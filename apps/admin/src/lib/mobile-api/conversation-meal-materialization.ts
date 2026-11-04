/** Private source-bound materialization. No model call, old intent/parser gate,
 * calculation, clinical authority, receipt, proof, analytics or domain write. */
import { isDeepStrictEqual } from 'node:util'
import {
  consumedFoodDefault,
  draftFromVisionItems,
  everydayFoodDefault,
  labelCandidateId,
  type MealCalcResult,
  type MealDraftCandidate,
  type MealDraftRawItem,
  mobileMilkWheyPortions,
  mobileMilkWheyTotalPortions,
  resolveDraftItem,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import {
  buildConversationMealInterpretationSource,
  type ConversationMealInterpretation,
  freezeInterpretation,
  type MealInterpretationModelResult,
  type MealInterpretationUnit,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import { createBoundConversationMealCorrectionReader } from './conversation-meal-personal-correction'
import type { CapturedConversationMealSource } from './conversation-meal-source'
import { MobileApiError } from './http'
import type { MealDraft } from './meal-draft-service'
import {
  type MobileQuantityDisplay,
  mobileDraftQuantity,
  mobileHouseholdTextItem,
} from './mobile-quantity-display'
import { isRecognizedPreparedDish } from './prepared-dish-estimate'

type Ref = NonNullable<MealInterpretationModelResult['foods'][number]['name']>
type Candidate = MealDraftCandidate & { quantity_display?: MobileQuantityDisplay }
type Rule =
  | 'literal'
  | 'mobile_household'
  | 'milk_whey_cup'
  | 'milk_whey_total'
  | 'prepared_dish'
  | 'visual'
export interface ConversationMealSourceGroup {
  readonly group_index: number
  readonly interpretation_food_indexes: readonly number[]
  readonly input_indexes: readonly number[]
  readonly rule: Rule
  readonly source_positions: readonly {
    food_index: number
    unit: MealInterpretationUnit
    name: Ref | null
    quantity: Ref | null
    unit_ref: Ref | null
    visual_index: number | null
  }[]
}
export interface MaterializedConversationMeal {
  readonly status: 'materialized'
  readonly schema: 'conversation.meal-materialization.v1'
  readonly input_hash: string
  readonly source_hash: string
  readonly attempt_id: string
  readonly inputs: readonly {
    input_index: number
    calculation_input: { food_name: string; quantity_g: number }
    candidate: Candidate
    source_group_index: number
  }[]
  readonly source_groups: readonly ConversationMealSourceGroup[]
  /** Review hint only. No approved_nutrition or implicit label consent. */
  readonly nutrition_label: MealDraft['nutrition_label']
}
export type ConversationMealMaterialization =
  | MaterializedConversationMeal
  | {
      readonly status: 'clarification_required'
      readonly reason:
        | 'interpretation_not_positive'
        | 'unqualified_whole_name'
        | 'personal_correction_unproven'
        | 'missing_quantity'
        | 'unsupported_quantity'
        | 'low_confidence'
        | 'ambiguous_source_group'
        | 'conflicting_user_sources'
        | 'unsupported_compound_association'
        | 'item_limit'
      readonly food_indexes: readonly number[]
    }
export interface ConversationMealCalculationSource {
  readonly input_indexes: readonly number[]
  readonly source_group_indexes: readonly number[]
  readonly quantity_basis: Exclude<MealDraftCandidate['quantity_basis'], 'missing'>
  readonly confidence: number | null
  readonly candidate_id?: string
  readonly quantity_display?: MobileQuantityDisplay
}
const normalized = (s: string) =>
  s.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '').replace(/\s+/gu, ' ').trim()
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_materialization_unavailable',
    'Meal materialization is unavailable',
  )
}
function record(v: unknown): Record<string, unknown> | null {
  return v !== null && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : null
}
function clarify(
  reason: Extract<ConversationMealMaterialization, { status: 'clarification_required' }>['reason'],
  indexes: number[],
): ConversationMealMaterialization {
  return freezeInterpretation({ status: 'clarification_required', reason, food_indexes: indexes })
}
const finite = z.number().finite()
const catalogRow = z
  .object({
    id: z.number().int().positive().max(2147483647),
    name_pt: z.string().min(1).max(250),
    category: z.string().nullable(),
    similarity: finite.min(0).max(1),
    kcal_per_100g: finite.nonnegative(),
    protein_g: finite.nonnegative(),
    carbs_g: finite.nonnegative(),
    fat_g: finite.nonnegative(),
    fiber_g: finite.nonnegative().nullable(),
    country_code: z.string().nullable(),
  })
  .strict()
const countWords: Record<string, number> = {
  um: 1,
  uma: 1,
  dois: 2,
  duas: 2,
  tres: 3,
  quatro: 4,
  cinco: 5,
  seis: 6,
  sete: 7,
  oito: 8,
  nove: 9,
  dez: 10,
  meio: 0.5,
  meia: 0.5,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  half: 0.5,
  a: 1,
  an: 1,
}
function amount(raw: string): number | null {
  const s = normalized(raw),
    n = countWords[s] ?? (/^\d+(?:[.,]\d+)?$/u.test(s) ? Number(s.replace(',', '.')) : NaN)
  return Number.isFinite(n) && n > 0 ? n : null
}
function mass(unit: string): number | null {
  if (/^(?:g|gr|grs|gramas?|grams?)$/u.test(unit)) return 1
  if (/^(?:kg|quilos?|kilograms?)$/u.test(unit)) return 1000
  return null
}
function canonicalUnit(unit: string): string | null {
  if (/^(?:ml|mililitros?|milliliters?)$/u.test(unit)) return 'ml'
  if (/^(?:l|litros?|liters?)$/u.test(unit)) return 'l'
  if (/^(?:un|und|unidades?|units?)$/u.test(unit)) return 'unidade'
  if (/^(?:fatias?|slices?)$/u.test(unit)) return 'fatia'
  if (/^(?:medidas?|scoops?|doses?)$/u.test(unit)) return 'medida'
  if (/^canecas?$/u.test(unit)) return 'caneca'
  return null
}
function freshCandidate(
  raw: MealDraftRawItem,
  index: number,
  basis?: 'portion_reference',
): Candidate | null {
  const candidate = resolveDraftItem(raw, index)
  // Never accept cleanName truncation/removal as whole-name qualification.
  if (!candidate || normalized(candidate.name) !== normalized(raw.name)) return null
  const converted = mobileDraftQuantity(candidate)
  return basis
    ? {
        ...converted,
        quantity_basis: basis,
        needs_review: true,
        review_reason: 'estimated_quantity',
      }
    : converted
}
function metadataLabel(raw: unknown, candidates: Candidate[]): MealDraft['nutrition_label'] {
  const label = record(raw)
  if (!label) return null
  const number = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null)
  const values = (v: unknown) => {
    const r = record(v)
    return r
      ? {
          kcal: number(r.kcal),
          protein_g: number(r.protein_g),
          carbs_g: number(r.carbs_g),
          fat_g: number(r.fat_g),
        }
      : null
  }
  const product =
    typeof label.product_name === 'string' &&
    label.product_name.trim() &&
    label.product_name.length <= 160
      ? label.product_name.trim()
      : null
  const confidence = number(label.confidence)
  return {
    product_name: product,
    serving_size_g: number(label.serving_size_g),
    per_serving: values(label.per_serving),
    per_100g: values(label.per_100g),
    confidence: confidence !== null && confidence <= 1 ? confidence : null,
    applies_to_candidate_id: labelCandidateId(candidates, product),
  }
}

export async function materializeConversationMealInterpretation(
  db: ServiceClient,
  command: BoundConversationMealCommand,
  captured: CapturedConversationMealSource,
  originalInterpretation: ConversationMealInterpretation,
  options: { confidenceThreshold: number },
): Promise<ConversationMealMaterialization> {
  try {
    // Pin every input and callback before the first catalog await. The capture
    // may contain functions, so only its data context is detached by builder.
    const rpc = db.rpc.bind(db)
    const source = buildConversationMealInterpretationSource(command, captured)
    const context = structuredClone(captured.context),
      owner = record(context.owner)
    if (
      !owner ||
      owner.country_confirmed !== true ||
      typeof owner.country !== 'string' ||
      !/^[A-Z]{2}$/u.test(owner.country)
    )
      unavailable()
    const country = owner.country
    const threshold = z
      .object({ confidenceThreshold: z.number().finite().min(0).max(1) })
      .strict()
      .parse(structuredClone(options)).confidenceThreshold
    const interpretation = parseConversationMealInterpretation(originalInterpretation, {
      ownerId: source.owner_id,
      commandId: source.command_id,
      attemptId: originalInterpretation.attempt_id,
      inputHash: source.input_hash,
      sourceHash: source.source_hash,
    })
    const model = {
      schema: interpretation.schema,
      decision: interpretation.decision,
      reason: interpretation.reason,
      sources: interpretation.sources,
      foods: interpretation.foods,
    }
    const visualIndexes = interpretation.foods.flatMap((food) =>
      food.visual_index === null ? [] : [food.visual_index],
    )
    const visualCount =
      source.sources.find((unit) => unit.unit === 'vision_items')?.visual_items.length ?? 0
    if (
      interpretation.decision === 'reported_meal' &&
      (visualIndexes.length !== visualCount || new Set(visualIndexes).size !== visualCount)
    )
      unavailable()
    const validated = validateConversationMealInterpretationModel(model, source)
    if (validated.decision !== 'reported_meal' || interpretation.decision !== 'reported_meal')
      return clarify(
        'interpretation_not_positive',
        interpretation.foods.map((f) => f.index),
      )
    if (!isDeepStrictEqual(model, validated)) unavailable()
    const byUnit = new Map(source.sources.map((s) => [s.unit, s]))
    const read = (ref: Ref | null): string | null =>
      ref ? (byUnit.get(ref.unit)?.text?.slice(ref.start, ref.end) ?? unavailable()) : null
    if (
      captured.sourceReader.ownerId !== source.owner_id ||
      captured.sourceReader.asOf !== source.captured_at
    )
      unavailable()
    const corrections = createBoundConversationMealCorrectionReader(db, {
      ownerId: source.owner_id,
      asOf: source.captured_at,
    })
    const correctionCache = new Map<string, Awaited<ReturnType<typeof corrections>>>()
    const correctionFor = async (name: string) => {
      const previous = correctionCache.get(name)
      if (previous !== undefined) return previous
      const value = await corrections(name)
      correctionCache.set(name, value)
      return value
    }
    const wholeQualified = new Map<string, boolean>()
    const qualifyWhole = async (name: string): Promise<boolean> => {
      const whole = normalized(name)
      if (!whole || name.length > 250) return false
      const previous = wholeQualified.get(whole)
      if (previous !== undefined) return previous
      if (
        consumedFoodDefault(name, country) ||
        everydayFoodDefault(name) ||
        isRecognizedPreparedDish(name)
      ) {
        return true
      }
      const result = await rpc('search_food_trgm', {
        search_term: whole,
        min_similarity: 0.9,
        max_results: 5,
        p_country: country,
      })
      if (!result || result.error) unavailable()
      const raw = structuredClone(result.data),
        rows = z.array(catalogRow).max(5).parse(raw)
      if (!isDeepStrictEqual(raw, rows)) unavailable()
      const found = rows.some((row) => normalized(row.name_pt) === whole)
      wholeQualified.set(whole, found)
      return found
    }
    type Qualification =
      | 'qualified'
      | 'unqualified_whole_name'
      | 'personal_correction_unproven'
      | 'ambiguous_source_group'
    const qualified = new Map<string, Qualification>()
    const qualify = async (name: string): Promise<Qualification> => {
      // Use the actual unchanged input spelling the calculator will receive.
      const candidate = freshCandidate({ name }, 0)
      if (!candidate) return 'ambiguous_source_group'
      const key = candidate.name,
        previous = qualified.get(key)
      if (previous !== undefined) return previous
      const correction = await correctionFor(key)
      let answer: Qualification
      if (correction.status === 'active')
        answer =
          correction.customNutrition || (await qualifyWhole(correction.row.corrected_to))
            ? 'qualified'
            : 'personal_correction_unproven'
      else if (correction.status === 'unproven') answer = 'personal_correction_unproven'
      else if (correction.status === 'learning')
        answer = (await qualifyWhole(name)) ? 'qualified' : 'personal_correction_unproven'
      else answer = (await qualifyWhole(name)) ? 'qualified' : 'unqualified_whole_name'
      qualified.set(key, answer)
      return answer
    }
    const inputs: MaterializedConversationMeal['inputs'][number][] = [],
      groups: ConversationMealSourceGroup[] = []
    for (const food of interpretation.foods) {
      const name = read(food.name),
        quantityText = read(food.quantity),
        unitText = read(food.unit)
      const positions: ConversationMealSourceGroup['source_positions'] = [
        {
          food_index: food.index,
          unit:
            food.name?.unit ??
            (food.visual_index !== null ? 'vision_items' : (food.quantity?.unit ?? unavailable())),
          name: food.name,
          quantity: food.quantity,
          unit_ref: food.unit,
          visual_index: food.visual_index,
        },
      ]
      const candidates: Candidate[] = []
      let rule: Rule = 'literal'
      if (food.visual_index !== null) {
        const raw = byUnit.get('vision_items')?.visual_items[food.visual_index],
          v = record(raw)
        if (!v || typeof v.name !== 'string' || v.name.length > 160)
          return clarify('ambiguous_source_group', [food.index])
        if (
          typeof v.confidence !== 'number' ||
          !Number.isFinite(v.confidence) ||
          v.confidence < 0 ||
          v.confidence > 1
        )
          return clarify('low_confidence', [food.index])
        const mapped = draftFromVisionItems([raw], threshold),
          visual = mapped[0]
        const literal = v.name.replace(/^\s*\d{1,2}\s*x\s+/iu, '').trim()
        if (mapped.length !== 1 || !visual || normalized(literal) !== normalized(visual.name))
          return clarify('ambiguous_source_group', [food.index])
        if (name !== null && normalized(name) !== normalized(literal))
          return clarify('conflicting_user_sources', [food.index])
        // Text mass overriding a visual mass needs explicit user association;
        // never silently choose a caption quantity or multiply a 2x estimate.
        if (quantityText !== null || unitText !== null)
          return clarify('ambiguous_source_group', [food.index])
        const qualification = await qualify(visual.name)
        if (qualification !== 'qualified') return clarify(qualification, [food.index])
        const indexed = freshCandidate({ name: visual.name }, inputs.length)
        if (!indexed) return clarify('ambiguous_source_group', [food.index])
        candidates.push({
          ...visual,
          candidate_id: indexed.candidate_id,
          ...(indexed.quantity_display ? { quantity_display: indexed.quantity_display } : {}),
        })
        rule = 'visual'
      } else {
        if (name === null) unavailable()
        const n = quantityText === null ? null : amount(quantityText),
          u = unitText === null ? null : normalized(unitText)
        if (quantityText !== null && n === null)
          return clarify('unsupported_quantity', [food.index])
        // Exact whole recipes are the ONLY added descriptors/expansion. The
        // source was already positively interpreted with complete framing.
        const cup = /^(?:1|uma) caneca de leite com (?:1|uma) (?:medida|dose) de whey$/u.test(
          normalized(name),
        )
          ? mobileMilkWheyPortions(name)
          : null
        const factor = u === null ? null : mass(u)
        const total =
          n !== null && factor !== null
            ? mobileMilkWheyTotalPortions(name, { quantity_g: n * factor })
            : null
        const compactName = /^leite(?: integral)? com (?:1|uma) (?:medida|dose) de whey$/u.test(
          normalized(name),
        )
        if (cup || compactName) {
          const original = freshCandidate({ name }, inputs.length)
          if (!original) return clarify('ambiguous_source_group', [food.index])
          const correction = await correctionFor(original.name)
          if (correction.status === 'unproven')
            return clarify('personal_correction_unproven', [food.index])
          if (correction.status === 'active') {
            const qualification = await qualify(name)
            if (qualification !== 'qualified') return clarify(qualification, [food.index])
            // An approved whole-food correction precedes recipe expansion.
            // Preserve a stated whole mass; never invent one from ingredients
            // after the correction has changed the food's identity.
            if (n === null || factor === null)
              return clarify('unsupported_compound_association', [food.index])
            const corrected = freshCandidate({ name, grams_stated: n * factor }, inputs.length)
            if (!corrected) return clarify('ambiguous_source_group', [food.index])
            candidates.push(corrected)
          }
        }
        if (!candidates.length) {
          if (compactName && !total)
            return clarify('unsupported_compound_association', [food.index])
          else if (cup || total) {
            if (cup && (quantityText !== null || unitText !== null))
              return clarify('unsupported_compound_association', [food.index])
            const parts = cup ?? total ?? unavailable()
            if (inputs.length + parts.length > 30) return clarify('item_limit', [food.index])
            for (const [offset, part] of parts.entries()) {
              const qualification = await qualify(part.food_name)
              if (qualification !== 'qualified') return clarify(qualification, [food.index])
              const candidate = freshCandidate(
                { name: part.food_name, grams_stated: part.quantity_g },
                inputs.length + offset,
                'portion_reference',
              )
              if (!candidate) unavailable()
              candidates.push(candidate)
            }
            rule = cup ? 'milk_whey_cup' : 'milk_whey_total'
          } else {
            const qualification = await qualify(name)
            if (qualification !== 'qualified') return clarify(qualification, [food.index])
            let raw: MealDraftRawItem = { name },
              reference = false
            if (n !== null) {
              if (factor !== null) raw = { name, grams_stated: n * factor }
              else {
                const unit = u === null ? null : canonicalUnit(u)
                if (u !== null && unit === null)
                  return clarify('unsupported_quantity', [food.index])
                if (unit === 'caneca' || unit === 'medida') {
                  // Reuse only the already qualified exact food plus its fully
                  // associated original quantity/unit; this is conversion, not
                  // a parser reinterpreting or discarding meal discourse.
                  const household = mobileHouseholdTextItem(`${n} ${unit} de ${name}`)
                  if (!household) return clarify('unsupported_quantity', [food.index])
                  raw = household
                  reference = true
                  rule = 'mobile_household'
                } else raw = { name, count: n, unit }
              }
            }
            const candidate = freshCandidate(
              raw,
              inputs.length,
              reference ? 'portion_reference' : undefined,
            )
            if (!candidate) return clarify('ambiguous_source_group', [food.index])
            candidates.push(candidate)
            if (isRecognizedPreparedDish(name)) rule = 'prepared_dish'
          }
        }
      }
      if (inputs.length + candidates.length > 30) return clarify('item_limit', [food.index])
      const indexes: number[] = []
      for (const candidate of candidates) {
        if (candidate.quantity_g === null)
          return clarify(
            quantityText === null || rule === 'visual'
              ? 'missing_quantity'
              : 'unsupported_quantity',
            [food.index],
          )
        if (
          !Number.isFinite(candidate.quantity_g) ||
          candidate.quantity_g <= 0 ||
          candidate.quantity_g > 9999
        )
          return clarify('unsupported_quantity', [food.index])
        if (candidate.review_reason === 'low_confidence')
          return clarify('low_confidence', [food.index])
        const index = inputs.length
        indexes.push(index)
        inputs.push({
          input_index: index,
          calculation_input: { food_name: candidate.name, quantity_g: candidate.quantity_g },
          candidate,
          source_group_index: groups.length,
        })
      }
      groups.push({
        group_index: groups.length,
        interpretation_food_indexes: [food.index],
        input_indexes: indexes,
        rule,
        source_positions: positions,
      })
    }
    if (!inputs.length) return clarify('missing_quantity', [])
    const media = record(context.media),
      processing = record(media?.processing_result)
    return freezeInterpretation({
      status: 'materialized',
      schema: 'conversation.meal-materialization.v1',
      input_hash: source.input_hash,
      source_hash: source.source_hash,
      attempt_id: interpretation.attempt_id,
      inputs,
      source_groups: groups,
      nutrition_label: metadataLabel(
        processing?.nutrition_label,
        inputs.map((i) => i.candidate),
      ),
    })
  } catch {
    return unavailable()
  }
}

/** Compose output→expanded input→source group; never zip calculator lines
 * with model foods. Called on the private materializer result, not HTTP JSON. */
export function mapConversationMealCalculationSources(
  materialization: MaterializedConversationMeal,
  calculation: MealCalcResult,
): readonly ConversationMealCalculationSource[] {
  try {
    const material = structuredClone(materialization),
      calc = structuredClone(calculation)
    const inputs = material.inputs
    if (
      !inputs.length ||
      inputs.length > 30 ||
      !Array.isArray(calc.items) ||
      !calc.items.length ||
      calc.items.length > 30 ||
      inputs.some((input, i) => input.input_index !== i)
    )
      unavailable()
    const indexes =
      calc.input_indexes ??
      (calc.items.length === inputs.length ? inputs.map((_, i) => [i]) : unavailable())
    const flattened = indexes.flat()
    if (
      indexes.length !== calc.items.length ||
      indexes.some((group) => !Array.isArray(group) || !group.length) ||
      flattened.length !== inputs.length ||
      new Set(flattened).size !== inputs.length ||
      flattened.some((i) => !Number.isInteger(i) || i < 0 || i >= inputs.length)
    )
      unavailable()
    return freezeInterpretation(
      indexes.map((group) => {
        const sources = group.map((index) => inputs[index] ?? unavailable())
        const bases = sources.map((input) => input.candidate.quantity_basis)
        if (bases.includes('missing')) unavailable()
        const basis = bases.includes('visual_estimate')
          ? ('visual_estimate' as const)
          : bases.includes('portion_reference')
            ? ('portion_reference' as const)
            : ('stated' as const)
        const confidences = sources.map((input) => input.candidate.confidence)
        const confidence = confidences.every(
          (c): c is number => typeof c === 'number' && Number.isFinite(c) && c >= 0 && c <= 1,
        )
          ? Math.min(...confidences)
          : null
        const groups = [...new Set(sources.map((input) => input.source_group_index))]
        if (
          groups.some(
            (index) =>
              !material.source_groups[index] ||
              sources.some(
                (input) =>
                  input.source_group_index === index &&
                  !material.source_groups[index]?.input_indexes.includes(input.input_index),
              ),
          )
        )
          unavailable()
        const sole = sources.length === 1 ? sources[0]?.candidate : undefined
        return {
          input_indexes: group,
          source_group_indexes: groups,
          quantity_basis: basis,
          confidence,
          ...(sole
            ? {
                candidate_id: sole.candidate_id,
                ...(sole.quantity_display ? { quantity_display: sole.quantity_display } : {}),
              }
            : {}),
        }
      }),
    )
  } catch {
    return unavailable()
  }
}
