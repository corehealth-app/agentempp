/**
 * Invariants of the everyday-name list. They hold for EVERY entry, so an item
 * added later cannot bring back the side effects of the withdrawn catalog
 * aliases (a composed name priced as its fat or powder, a preparation chosen
 * for the patient) or break the edit round trip of the app.
 */
import { describe, expect, it } from 'vitest'
import {
  EVERYDAY_FOOD_DEFAULTS,
  everydayFoodDefault,
  normalizeEverydayFoodName,
} from './everyday-food-defaults.js'

const COMPOSED_NAME = / com | e |\+/
// A default never decides how the food was prepared: that is the patient's
// answer (product decision of 2026-09-28).
const PREPARATION_WORDS = [
  'cru',
  'crua',
  'cozido',
  'cozida',
  'frito',
  'frita',
  'grelhado',
  'grelhada',
  'assado',
  'assada',
  'refogado',
  'refogada',
  'mexido',
  'mexida',
  'empanado',
  'empanada',
]

describe('everyday food defaults — the list', () => {
  it('holds exactly the two items implemented on 2026-10-04 (confirmation pending)', () => {
    expect(
      EVERYDAY_FOOD_DEFAULTS.map((entry) => ({
        said: [...entry.said],
        shown_as: entry.shown_as,
        catalog_name: entry.catalog_name,
        source_ref: entry.source_ref,
        per_100g: entry.per_100g,
        status: entry.status,
      })),
    ).toEqual([
      {
        said: ['leite', 'leite integral'],
        shown_as: 'leite integral',
        catalog_name: 'Milk, whole, 3.25% milkfat, with added vitamin D',
        source_ref: 'FDC:171265',
        per_100g: { kcal: 61, protein_g: 3.15, carbs_g: 4.8, fat_g: 3.25 },
        status: 'confirmation_pending',
      },
      {
        said: ['whey', 'whey protein em po'],
        shown_as: 'whey protein em pó',
        catalog_name: 'Beverages, Protein powder whey based',
        source_ref: 'FDC:173180',
        per_100g: { kcal: 352, protein_g: 78.13, carbs_g: 6.25, fat_g: 1.56 },
        status: 'confirmation_pending',
      },
    ])
  })

  it('never presents the list as a decision of the client while it is pending', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      expect(entry.stated_on.trim(), entry.shown_as).not.toBe('')
      expect(['confirmation_pending', 'confirmed'], entry.shown_as).toContain(entry.status)
      if (entry.status === 'confirmation_pending') {
        expect(entry.stated_on, entry.shown_as).toContain(
          'a lista de itens não foi confirmada pelo cliente',
        )
      }
    }
    expect(EVERYDAY_FOOD_DEFAULTS[0]?.stated_on).toBe(
      '06/01/2026 (manual 4.2), 18/05/2026 e 01/06/2026 — regra geral de assumir em vez de perguntar; a lista de itens não foi confirmada pelo cliente',
    )
  })

  it('every said name is a single, already normalised food name', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      expect(entry.said.length, entry.shown_as).toBeGreaterThan(0)
      for (const name of entry.said) {
        expect(normalizeEverydayFoodName(name), name).toBe(name)
        expect(COMPOSED_NAME.test(` ${name} `), name).toBe(false)
      }
    }
  })

  it('no said or shown name carries a preparation', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      for (const name of [...entry.said, entry.shown_as]) {
        const words = normalizeEverydayFoodName(name).split(' ')
        for (const word of PREPARATION_WORDS) expect(words, name).not.toContain(word)
      }
    }
  })

  it('the shown name only adds words to what the patient said', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      const shown = normalizeEverydayFoodName(entry.shown_as)
      for (const name of entry.said) {
        expect(shown === name || shown.startsWith(`${name} `), `${name} → ${shown}`).toBe(true)
      }
    }
  })

  // The app sends the shown name back when the patient edits another item of
  // the proposal; it must resolve to the same entry.
  it('the shown name is itself a said name of the same entry', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      expect(entry.said, entry.shown_as).toContain(normalizeEverydayFoodName(entry.shown_as))
      expect(everydayFoodDefault(entry.shown_as)).toBe(entry)
    }
  })

  it('no name belongs to two entries', () => {
    const names = EVERYDAY_FOOD_DEFAULTS.flatMap((entry) => [...entry.said])
    expect(new Set(names).size).toBe(names.length)
  })

  it('every entry names a catalog row and its values are coherent with their own energy', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      expect(entry.catalog_name.trim(), entry.shown_as).not.toBe('')
      expect(entry.source_ref, entry.shown_as).toMatch(/^(FDC|TACO4):\d+$/)
      const { kcal, protein_g, carbs_g, fat_g } = entry.per_100g
      for (const value of [kcal, protein_g, carbs_g, fat_g]) {
        expect(Number.isFinite(value) && value >= 0, entry.shown_as).toBe(true)
      }
      // 4/4/9: a typo in one of the four copied values shows up here.
      const fromMacros = protein_g * 4 + carbs_g * 4 + fat_g * 9
      expect(Math.abs(fromMacros - kcal) / kcal, entry.shown_as).toBeLessThan(0.1)
    }
  })
})

describe('everyday food defaults — the lookup is whole-name equality', () => {
  // The revert switch: an empty list answers for no name.
  it('answers nothing when the list is empty', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      for (const name of [...entry.said, entry.shown_as]) {
        expect(everydayFoodDefault(name), name).toBe(entry)
        expect(everydayFoodDefault(name, []), name).toBeNull()
      }
    }
  })

  it('finds the name whatever the case, the accents and the spacing', () => {
    for (const name of ['leite', 'Leite', ' leite ', 'LEITE  INTEGRAL', 'leite integral']) {
      expect(everydayFoodDefault(name)?.shown_as, name).toBe('leite integral')
    }
    for (const name of [
      'whey',
      'Whey',
      'whey protein em pó',
      'Whey Protein em Po',
      'whey  protein em pó ',
    ]) {
      expect(everydayFoodDefault(name)?.shown_as, name).toBe('whey protein em pó')
    }
  })

  it('does not answer for a name that merely contains, starts or ends with a said name', () => {
    for (const name of [
      '',
      ' ',
      'leites',
      'leite de coco',
      'leite de cabra',
      'leite de soja',
      'leite de vaca',
      'leite desnatado',
      'leite semidesnatado',
      'leite condensado',
      'leite em pó',
      'leite integral em pó',
      'leite integral zero lactose',
      'leite com whey',
      'leite e whey',
      'leite + whey',
      'whey com leite',
      'café com leite',
      'pão com leite',
      'doce de leite',
      'copo de leite',
      '1 copo de leite',
      'leite no jantar',
      'whey protein',
      'whey isolado',
      'whey protein isolado',
      'shake de whey',
      'barra de whey',
      'iogurte whey',
      'scoop de whey',
      'whey no jantar',
      'salada com azeite',
      'azeite',
      'ovo',
      'arroz branco',
    ]) {
      expect(everydayFoodDefault(name), JSON.stringify(name)).toBeNull()
    }
  })
})
