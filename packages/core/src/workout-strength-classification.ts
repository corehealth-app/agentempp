/**
 * Internal pure catalogue decision. Input shape is checked defensively;
 * a JS object/type/status never authenticates completeness or provenance.
 * The future backend observer and transactional full-set CAS must prove it.
 * No I/O, historical binding, energy calculation, barrel or consumer here.
 */
import type { StrengthWeekWorkout } from './strength-training-week.js'

export type WorkoutCatalogueCategory = NonNullable<StrengthWeekWorkout['catalogueCategory']>
export interface WorkoutCatalogueObservation {
  readonly observedAt: string
  readonly matcherVersion: 'active_slug_then_unique_canonical_display_v1'
  readonly observationKey: string
}
export interface WorkoutCatalogueRow {
  readonly id: string
  readonly slug: string
  readonly displayName: string
  readonly category: WorkoutCatalogueCategory
  readonly isActive: true
  /** Exact validated DB literal, never a Date or rounded millisecond value. */
  readonly updatedAtLiteral: string
}
export type WorkoutCatalogueRead =
  | {
      readonly status: 'complete'
      readonly observation: WorkoutCatalogueObservation
      readonly activeRows: readonly WorkoutCatalogueRow[]
    }
  | {
      readonly status: 'unavailable'
      readonly reason: 'catalogue_read_error' | 'catalogue_invalid' | 'catalogue_incomplete'
    }

/** Exact classification union from R2 a4e19 / Root pin1180200. */
export type WorkoutClassification =
  | {
      readonly status: 'matched'
      readonly observation: WorkoutCatalogueObservation
      readonly method: 'active_slug' | 'unique_active_display'
      readonly catalogue: WorkoutCatalogueRow
    }
  | {
      readonly status: 'unrecognized'
      readonly observation: WorkoutCatalogueObservation
      readonly reason: 'no_active_match' | 'ambiguous_active_name' | 'generic_outro'
    }
  | {
      readonly status: 'unavailable'
      readonly reason:
        | 'catalogue_read_error'
        | 'catalogue_invalid'
        | 'catalogue_incomplete'
        | 'legacy_provenance_gap'
    }

/** Matches the existing mobile vocabulary without changing the stored text. */
export function classifyConfirmedWorkoutType(
  rawType: string,
  read: WorkoutCatalogueRead,
): WorkoutClassification {
  if (!isRecord(read)) return invalidCatalogue()
  if (read.status === 'unavailable') {
    if (
      read.reason === 'catalogue_read_error' ||
      read.reason === 'catalogue_invalid' ||
      read.reason === 'catalogue_incomplete'
    ) {
      return { status: 'unavailable', reason: read.reason }
    }
    return invalidCatalogue()
  }
  if (
    read.status !== 'complete' ||
    !validObservation(read.observation) ||
    !Array.isArray(read.activeRows)
  ) {
    return invalidCatalogue()
  }

  const ids = new Set<string>()
  const slugs = new Set<string>()
  for (const row of read.activeRows) {
    if (!validRow(row) || ids.has(row.id) || slugs.has(row.slug)) return invalidCatalogue()
    ids.add(row.id)
    slugs.add(row.slug)
  }

  // Copy only the declared literals. Later input mutation cannot rewrite a decision.
  const observation: WorkoutCatalogueObservation = {
    observedAt: read.observation.observedAt,
    matcherVersion: read.observation.matcherVersion,
    observationKey: read.observation.observationKey,
  }
  const unrecognized = (
    reason: 'no_active_match' | 'ambiguous_active_name' | 'generic_outro',
  ): WorkoutClassification => ({ status: 'unrecognized', observation, reason })

  const canonical = canonicalWorkoutType(rawType)
  if (canonical === 'outro') return unrecognized('generic_outro')

  let selected = read.activeRows.find((row) => row.slug === canonical)
  let method: 'active_slug' | 'unique_active_display' = 'active_slug'
  if (selected === undefined) {
    const named = read.activeRows.filter(
      (row) => canonicalWorkoutType(row.displayName) === canonical,
    )
    if (named.length > 1) return unrecognized('ambiguous_active_name')
    selected = named[0]
    method = 'unique_active_display'
  }
  if (selected === undefined) return unrecognized('no_active_match')
  if (selected.slug === 'outro') return unrecognized('generic_outro')

  return {
    status: 'matched',
    observation,
    method,
    catalogue: {
      id: selected.id,
      slug: selected.slug,
      displayName: selected.displayName,
      category: selected.category,
      isActive: true,
      updatedAtLiteral: selected.updatedAtLiteral,
    },
  }
}

// Keep the literal current registration-service canonicalization and order.
function canonicalWorkoutType(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
    .replace(/[\s_-]+/g, '_')
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function validObservation(value: unknown): value is WorkoutCatalogueObservation {
  return (
    isRecord(value) &&
    typeof value.observedAt === 'string' &&
    typeof value.observationKey === 'string' &&
    value.matcherVersion === 'active_slug_then_unique_canonical_display_v1'
  )
}

function validRow(value: unknown): value is WorkoutCatalogueRow {
  return (
    isRecord(value) &&
    typeof value.id === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(value.id) &&
    typeof value.slug === 'string' &&
    typeof value.displayName === 'string' &&
    (value.category === 'musculacao' ||
      value.category === 'cardio' ||
      value.category === 'esporte' ||
      value.category === 'mobilidade') &&
    value.isActive === true &&
    typeof value.updatedAtLiteral === 'string'
  )
}

function invalidCatalogue(): WorkoutClassification {
  return { status: 'unavailable', reason: 'catalogue_invalid' }
}
