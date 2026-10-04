/**
 * Everyday food names: the item the system assumes when the patient names a
 * food without saying its type ("leite" is taken as whole cow milk), and the
 * name every screen shows so the assumption is visible and can be edited.
 *
 * WHO SAID WHAT. The client (Dr. Roberto) stated the GENERAL rule, "assume
 * instead of asking": manual item 4.2 pasted on 06/01/2026, repeated on
 * 18/05/2026 and 01/06/2026. He did NOT state this list of items. The list
 * was implemented on 2026-10-04 at Eduardo's request and the client's
 * confirmation is pending. This is not a decision of the client.
 *
 * NO NUMBER IS INVENTED HERE. `per_100g` repeats the verified catalog row
 * named by `catalog_name` / `source_ref`. The calculation reads that row from
 * the catalog and uses it only when its values still equal these; otherwise
 * the item follows the normal calculation, as if this list were empty.
 *
 * ONE LINE PER ENTRY. Two items of the same call that resolve to the same
 * entry ("leite" and "leite integral") come back as ONE line with the summed
 * quantity, computed from the same row (calcMealMacros).
 *
 * REVERT: empty EVERYDAY_FOOD_DEFAULTS (or remove one entry). New items go
 * back to the previous calculation and nothing is added into one line. There
 * is no migration to undo, but the revert does NOT touch what was already
 * recorded: no meal_log is deleted or recalculated. For 30 days (the window
 * of the patient's own history) a patient who recorded an item under the
 * shown name keeps getting it from that record: "leite integral" 200 g still
 * comes back as 122 kcal (source "history"), not as the 224.9 kcal the
 * previous calculation gives a patient without that record. The typed
 * "leite" goes back to coconut milk (332.3 kcal) at once.
 */

export interface EverydayFoodDefault {
  /** Whole item names that trigger the default, already normalised. */
  said: readonly string[]
  /** Name the item is shown and stored with. Must normalise to one of `said`:
   * the app sends the shown name back when the patient edits the proposal. */
  shown_as: string
  /** Exact name of the verified catalog row the values come from. */
  catalog_name: string
  source_ref: string
  /** The values the row had when the entry was written (kcal, g per 100 g). */
  per_100g: { kcal: number; protein_g: number; carbs_g: number; fat_g: number }
  /** What the client said and when (Portuguese, quoted in the docs). */
  stated_on: string
  status: 'confirmation_pending' | 'confirmed'
}

const GENERAL_RULE_ONLY =
  '06/01/2026 (manual 4.2), 18/05/2026 e 01/06/2026 — regra geral de assumir em vez de perguntar; a lista de itens não foi confirmada pelo cliente'

export const EVERYDAY_FOOD_DEFAULTS: readonly EverydayFoodDefault[] = [
  {
    said: ['leite', 'leite integral'],
    shown_as: 'leite integral',
    catalog_name: 'Milk, whole, 3.25% milkfat, with added vitamin D',
    source_ref: 'FDC:171265',
    per_100g: { kcal: 61, protein_g: 3.15, carbs_g: 4.8, fat_g: 3.25 },
    stated_on: GENERAL_RULE_ONLY,
    status: 'confirmation_pending',
  },
  {
    said: ['whey', 'whey protein em po'],
    shown_as: 'whey protein em pó',
    catalog_name: 'Beverages, Protein powder whey based',
    source_ref: 'FDC:173180',
    per_100g: { kcal: 352, protein_g: 78.13, carbs_g: 6.25, fat_g: 1.56 },
    stated_on: GENERAL_RULE_ONLY,
    status: 'confirmation_pending',
  },
]

/** Lower case, no accents, single spaces. */
export function normalizeEverydayFoodName(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * The default for an item, or null. Whole-name equality only: a substring or
 * prefix match would price "leite de coco", "café com leite" or "shake de
 * whey" as plain milk or plain powder.
 */
export function everydayFoodDefault(
  foodName: string,
  defaults: readonly EverydayFoodDefault[] = EVERYDAY_FOOD_DEFAULTS,
): EverydayFoodDefault | null {
  const name = normalizeEverydayFoodName(foodName)
  if (!name) return null
  return defaults.find((entry) => entry.said.includes(name)) ?? null
}
