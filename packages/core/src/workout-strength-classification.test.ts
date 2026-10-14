/**
 * C59a3a pure classification test-first contract, before a runtime candidate.
 * Fixtures stand in for a future validated backend complete observation.
 * A JS object/type/complete flag is NOT read authority or full-set CAS proof.
 * No DB, catalogue producer, operation binding, lifecycle, projection, kcal,
 * consumer, WhatsApp or activation is exercised. Missing module is NOT RED.
 */
import { describe, expect, it } from 'vitest'
import {
  classifyConfirmedWorkoutType,
  type WorkoutCatalogueRead,
  type WorkoutCatalogueRow,
  type WorkoutClassification,
} from './workout-strength-classification.js'

const OBSERVATION = {
  observedAt: '2026-10-14T20:40:01.000009Z',
  matcherVersion: 'active_slug_then_unique_canonical_display_v1' as const,
  observationKey: 'synthetic-complete-catalogue-observation-1',
}
const STRENGTH: WorkoutCatalogueRow = {
  id: 'c59a3000-0000-4000-8000-000000000001',
  slug: 'musculacao',
  displayName: 'Musculação',
  category: 'musculacao',
  isActive: true,
  updatedAtLiteral: '2026-10-14T20:39:16.000001+00:00',
}
const SWIMMING: WorkoutCatalogueRow = {
  id: 'c59a3000-0000-4000-8000-000000000002',
  slug: 'natacao',
  displayName: 'Natação',
  category: 'cardio',
  isActive: true,
  updatedAtLiteral: '2026-10-14T20:39:16.000002+00:00',
}
const JACKS: WorkoutCatalogueRow = {
  id: 'c59a3000-0000-4000-8000-000000000003',
  slug: 'jumping_jacks',
  displayName: 'Polichinelos',
  category: 'cardio',
  isActive: true,
  updatedAtLiteral: '2026-10-14T20:39:16.000003+00:00',
}
const OTHER: WorkoutCatalogueRow = {
  id: 'c59a3000-0000-4000-8000-000000000004',
  slug: 'outro',
  displayName: 'Atividade genérica',
  category: 'cardio',
  isActive: true,
  updatedAtLiteral: '2026-10-14T20:39:16.000004+00:00',
}
function complete(
  activeRows: readonly WorkoutCatalogueRow[] = [STRENGTH, SWIMMING, JACKS, OTHER],
): Extract<WorkoutCatalogueRead, { status: 'complete' }> {
  return { status: 'complete', observation: OBSERVATION, activeRows }
}
function matched(
  catalogue: WorkoutCatalogueRow,
  method: 'active_slug' | 'unique_active_display' = 'active_slug',
): WorkoutClassification {
  return { status: 'matched', observation: OBSERVATION, method, catalogue }
}
function unrecognized(
  reason: 'no_active_match' | 'ambiguous_active_name' | 'generic_outro',
): WorkoutClassification {
  return { status: 'unrecognized', observation: OBSERVATION, reason }
}
/** Deliberately malformed data at the typed boundary, never a production cast. */
function classifyInvalidFixture(read: unknown, rawType = 'musculacao'): WorkoutClassification {
  return classifyConfirmedWorkoutType(rawType, read as WorkoutCatalogueRead)
}

describe('classifyConfirmedWorkoutType: literal current matcher on complete input', () => {
  it('copies the actual confirmed catalogue strength category and all stored literals', () => {
    expect(classifyConfirmedWorkoutType('musculacao', complete())).toStrictEqual(matched(STRENGTH))
  })

  it.each([
    ['Natação', SWIMMING],
    ['Natac\u0327a\u0303o', SWIMMING],
    ['NATAÇÃO', SWIMMING],
    ['\u00a0\t Natação \n\u2003', SWIMMING],
    ['na\u1ab0tacao', SWIMMING],
  ] as const)('retains literal NFD/Unicode Diacritic/case/trim parity for %s', (rawType, expected) => {
    expect(classifyConfirmedWorkoutType(rawType, complete())).toStrictEqual(matched(expected))
  })

  it.each([
    'jumping jacks',
    'jumping--jacks',
    'jumping___jacks',
    'jumping _--\t jacks',
  ])('collapses exactly the existing whitespace/underscore/ASCII-hyphen runs: %s', (rawType) => {
    expect(classifyConfirmedWorkoutType(rawType, complete())).toStrictEqual(matched(JACKS))
  })

  it('uses only a unique normalized active display when no active slug matches', () => {
    expect(classifyConfirmedWorkoutType('  POLICHÍNELOS ', complete())).toStrictEqual(
      matched(JACKS, 'unique_active_display'),
    )
  })

  it('normalizes the display name with the same separator rule', () => {
    const byName: WorkoutCatalogueRow = {
      ...STRENGTH,
      slug: 'peito_triceps',
      displayName: 'Peito - e__tríceps',
    }
    expect(classifyConfirmedWorkoutType('PEITO_e--TRICEPS', complete([byName]))).toStrictEqual(
      matched(byName, 'unique_active_display'),
    )
  })

  it.each([
    [SWIMMING, { ...JACKS, displayName: 'Natação' }],
    [{ ...JACKS, displayName: 'Natação' }, SWIMMING],
  ])('prioritizes exact active slug over competing normalized displays %#', (first, second) => {
    expect(classifyConfirmedWorkoutType('Natação', complete([first, second]))).toStrictEqual(
      matched(SWIMMING),
    )
  })

  it.each([
    'musculacao',
    'cardio',
    'esporte',
    'mobilidade',
  ] as const)('copies real category %s instead of inferring it from raw text or kcal', (category) => {
    const actualRow: WorkoutCatalogueRow = { ...STRENGTH, category }
    expect(classifyConfirmedWorkoutType('musculacao', complete([actualRow]))).toStrictEqual(
      matched(actualRow),
    )
  })

  it.each([
    ['natacaoo', 'no_active_match'],
    ['natação livre', 'no_active_match'],
    ['swimming', 'no_active_match'],
    ['treino de força', 'no_active_match'],
    ['polichinelo', 'no_active_match'],
    ['jumping–jacks', 'no_active_match'],
    ['na\u034ftacao', 'no_active_match'],
  ] as const)('does not add fuzzy/synonym/LLM/punctuation/general-Mark rules for %s', (raw, reason) => {
    expect(classifyConfirmedWorkoutType(raw, complete())).toStrictEqual(unrecognized(reason))
  })

  it('does not canonicalize the stored slug to manufacture an active-slug match', () => {
    const literalSlug: WorkoutCatalogueRow = {
      ...SWIMMING,
      slug: 'Natação',
      displayName: 'Água',
    }
    expect(classifyConfirmedWorkoutType('Natação', complete([literalSlug]))).toStrictEqual(
      unrecognized('no_active_match'),
    )
  })

  it('uses NFD, not compatibility normalization of ligatures', () => {
    const fitness: WorkoutCatalogueRow = { ...STRENGTH, slug: 'fitness', displayName: 'Fitness' }
    expect(classifyConfirmedWorkoutType('ﬁtness', complete([fitness]))).toStrictEqual(
      unrecognized('no_active_match'),
    )
  })

  it.each([
    [JACKS, { ...SWIMMING, displayName: 'POLICHÍNELOS' }],
    [{ ...SWIMMING, displayName: 'POLICHÍNELOS' }, JACKS],
  ])('does not select one of ambiguous active display matches %#', (first, second) => {
    expect(classifyConfirmedWorkoutType('Polichinelos', complete([first, second]))).toStrictEqual(
      unrecognized('ambiguous_active_name'),
    )
  })

  it('treats a successful complete empty set as no active match', () => {
    expect(classifyConfirmedWorkoutType('Natação', complete([]))).toStrictEqual(
      unrecognized('no_active_match'),
    )
  })

  it('does not invent knowledge of an inactive row omitted from the active observation', () => {
    expect(classifyConfirmedWorkoutType('natacao', complete([STRENGTH]))).toStrictEqual(
      unrecognized('no_active_match'),
    )
  })

  it.each([
    'outro',
    'OUTRO',
    '  Óutro\t',
  ])('keeps the normalized generic literal %s unrecognized despite a non-generic display match', (rawType) => {
    const namedOther: WorkoutCatalogueRow = { ...STRENGTH, displayName: 'Outro' }
    expect(classifyConfirmedWorkoutType(rawType, complete([namedOther]))).toStrictEqual(
      unrecognized('generic_outro'),
    )
  })

  it('never promotes the generic outro row cardio rate into a real category', () => {
    expect(classifyConfirmedWorkoutType('Atividade genérica', complete())).toStrictEqual(
      unrecognized('generic_outro'),
    )
  })

  it('does not need an outro row to recognize the literal as generic', () => {
    expect(classifyConfirmedWorkoutType('outro', complete([]))).toStrictEqual(
      unrecognized('generic_outro'),
    )
  })
})

describe('classification availability and defensive shape validation', () => {
  it.each([
    'catalogue_read_error',
    'catalogue_invalid',
    'catalogue_incomplete',
  ] as const)('keeps %s unavailable even for an otherwise direct slug or generic literal', (reason) => {
    for (const rawType of ['musculacao', 'outro']) {
      expect(
        classifyConfirmedWorkoutType(rawType, { status: 'unavailable', reason }),
      ).toStrictEqual({
        status: 'unavailable',
        reason,
      })
    }
  })

  it.each([
    null,
    undefined,
    [],
    {},
    { status: 'complete' },
    { ...complete(), activeRows: null },
    { ...complete(), activeRows: {} },
    { ...complete(), observation: null },
    { ...complete(), observation: { ...OBSERVATION, matcherVersion: 'fuzzy_v2' } },
    { ...complete(), observation: { ...OBSERVATION, observationKey: null } },
    {
      ...complete(),
      observation: { ...OBSERVATION, observedAt: new Date('2026-10-14T20:40:01Z') },
    },
    complete([{ ...STRENGTH, id: 'not-a-uuid' }]),
    { ...complete(), activeRows: [{ ...STRENGTH, category: 'strength' }] },
    { ...complete(), activeRows: [{ ...STRENGTH, category: null }] },
    { ...complete(), activeRows: [{ ...STRENGTH, slug: null }] },
    { ...complete(), activeRows: [{ ...STRENGTH, displayName: 7 }] },
    { ...complete(), activeRows: [{ ...STRENGTH, isActive: false }] },
    { ...complete(), activeRows: [{ ...STRENGTH, isActive: 'true' }] },
    {
      ...complete(),
      activeRows: [{ ...STRENGTH, updatedAtLiteral: new Date('2026-10-14T20:39:16Z') }],
    },
    complete([STRENGTH, { ...SWIMMING, id: STRENGTH.id }]),
    complete([STRENGTH, { ...SWIMMING, slug: STRENGTH.slug }]),
  ])('does not convert invalid complete observation %# into a match or a question', (read) => {
    for (const rawType of ['musculacao', 'outro']) {
      expect(classifyInvalidFixture(read, rawType)).toStrictEqual({
        status: 'unavailable',
        reason: 'catalogue_invalid',
      })
    }
  })

  it('validates the entire complete set before matching a valid first row', () => {
    const read = {
      ...complete(),
      activeRows: [STRENGTH, { ...SWIMMING, category: 'muscle_from_llm' }],
    }
    expect(classifyInvalidFixture(read)).toStrictEqual({
      status: 'unavailable',
      reason: 'catalogue_invalid',
    })
  })
})

describe('stored literal and input preservation', () => {
  it('preserves microseconds and does not mutate the raw operation text or frozen input', () => {
    const rawType = '  MÚSCULAÇÃO\t'
    const row = Object.freeze({ ...STRENGTH })
    const observation = Object.freeze({ ...OBSERVATION })
    const read = Object.freeze({
      status: 'complete' as const,
      observation,
      activeRows: Object.freeze([row]),
    })
    const before = JSON.stringify(read)
    expect(classifyConfirmedWorkoutType(rawType, read)).toStrictEqual(matched(row))
    expect(rawType).toBe('  MÚSCULAÇÃO\t')
    expect(JSON.stringify(read)).toBe(before)
  })

  it('preserves the selected display, slug, ID and category literally, without canonicalizing stored fields', () => {
    const row: WorkoutCatalogueRow = {
      ...STRENGTH,
      slug: 'row_literal_slug',
      displayName: '  PÉITO--TRÍCEPS  ',
      category: 'esporte',
      updatedAtLiteral: '2026-10-14T20:39:16.123456Z',
    }
    expect(classifyConfirmedWorkoutType('peito_triceps', complete([row]))).toStrictEqual(
      matched(row, 'unique_active_display'),
    )
  })

  it('returns independent classifications for separate observations without changing the earlier result', () => {
    const first = classifyConfirmedWorkoutType('musculacao', complete([STRENGTH]))
    const laterRow: WorkoutCatalogueRow = {
      ...STRENGTH,
      category: 'mobilidade',
      updatedAtLiteral: '2026-10-15T01:02:03.000007Z',
    }
    expect(classifyConfirmedWorkoutType('musculacao', complete([laterRow]))).toStrictEqual(
      matched(laterRow),
    )
    expect(first).toStrictEqual(matched(STRENGTH))
  })
})
