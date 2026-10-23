import { genericPreparedDishMacros, type MealCalcResult, type MealItemInput } from '@mpp/agent'

type PreparedDishInput = MealItemInput & { use_nutrition_label?: boolean }

function normalized(value: string): string {
  return value.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim()
}

/** Positive whole-phrase grammar for the reported prepared dish. Unknown
 * ingredients, brands, negations and different preparations are not admitted. */
function isRecognizedPreparedDish(value: string): boolean {
  const parts = normalized(value).split(/ (?:com|e|\+) /)
  if (parts.length < 2 || !/^carne (?:desfiada|cozida)$/.test(parts[0] ?? '')) return false
  const complements = parts.slice(1)
  if (complements.some(part => !/^(?:molho(?: de tomate)?|milho(?: cozido)?)$/.test(part))) return false
  const ingredients = complements.map(part => part.startsWith('molho') ? 'molho' : 'milho')
  return new Set(ingredients).size === ingredients.length
}

function rejectionWarning(food: string): string {
  return `Não consegui identificar "${food}" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: "leite 250ml" e "whey 30g"). Não foi possível calcular as calorias desse item ainda.`
}

/** App-only opt-in approved23Oct: a recognized prepared dish may use the
 * existing generic reference. This does not change the shared engine routing,
 * identify a recipe, split its weight, or accept an unknown composition. */
export function applyMobilePreparedDishEstimate(
  calculation: MealCalcResult,
  inputs: readonly PreparedDishInput[],
  origin: string | null,
  locale: string | null | undefined,
): MealCalcResult {
  if (origin !== 'mobile_app') return calculation
  const indexes = calculation.input_indexes ?? calculation.items.map((_, index) => [index])
  const flattened = indexes.flat()
  // Do not guess the association if a calculator ever changes its line shape.
  if (indexes.length !== calculation.items.length || indexes.some(group => !group.length)
    || flattened.length !== inputs.length || new Set(flattened).size !== inputs.length
    || flattened.some(index => !Number.isInteger(index) || index < 0 || index >= inputs.length)) return calculation

  const totals = { ...calculation.totals }
  const userWarnings = [...calculation.user_warnings]
  let changed = false
  const items = calculation.items.map((item, index) => {
    const group = indexes[index]!
    const input = group.length === 1 ? inputs[group[0]!] : undefined
    if (item.source !== 'composite_rejected' || !input
      || input.user_kcal !== undefined || input.use_nutrition_label || input.approved_nutrition
      || item.preparation_options?.length || item.quantity_g !== input.quantity_g
      || !Number.isFinite(input.quantity_g) || input.quantity_g <= 0 || input.quantity_g > 9999
      || normalized(item.food_name) !== normalized(input.food_name)
      || !isRecognizedPreparedDish(input.food_name)
      || [item.kcal, item.protein_g, item.carbs_g, item.fat_g, item.fiber_g].some(value => value !== 0)) return item
    const warningIndex = userWarnings.indexOf(rejectionWarning(item.food_name))
    // Keep any changed engine warning intact rather than leaving a contradictory
    // refusal alongside an estimate. Only the exact known occurrence is removed.
    if (warningIndex < 0) return item
    userWarnings.splice(warningIndex, 1)
    const reference = genericPreparedDishMacros()
    const factor = input.quantity_g / 100
    const nutrition = {
      kcal: +(reference.kcal * factor).toFixed(1),
      protein_g: +(reference.protein * factor).toFixed(2),
      carbs_g: +(reference.carbs * factor).toFixed(2),
      fat_g: +(reference.fat * factor).toFixed(2),
      fiber_g: +(reference.fiber * factor).toFixed(2),
    }
    for (const key of ['kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g'] as const) totals[key] += nutrition[key]
    userWarnings.push(locale?.startsWith('en')
      ? `I estimated "${item.food_name}" from its total weight using a generic reference for a prepared dish. The nutrition values are approximate and can be edited before confirming.`
      : `Estimei "${item.food_name}" a partir do peso total, usando uma referência genérica de prato preparado. Os valores nutricionais são aproximados e podem ser corrigidos antes de confirmar.`)
    changed = true
    return { ...item, ...nutrition, matched_taco_name: `[estimativa ${reference.category}]`,
      matched_taco_id: null, similarity: 0, source: 'llm_estimate' as const }
  })
  if (!changed) return calculation
  for (const key of ['kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g'] as const) totals[key] = +totals[key].toFixed(1)
  const auditWarnings = [...calculation.audit_warnings]
  return { ...calculation, items, totals, user_warnings: userWarnings,
    audit_warnings: auditWarnings, warnings: [...userWarnings, ...auditWarnings] }
}
