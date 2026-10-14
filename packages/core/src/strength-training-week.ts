/**
 * Internal pure Q15 weekly strength facts. Publication requires a durable
 * owner/week winner supplied by the integrator; this module performs no I/O.
 */

export interface StrengthWeekScope {
  readonly ownerKey: string
  /** Exact local civil Monday; not a UTC instant. */
  readonly weekStartDate: string
}

export type StrengthWeekTargetSource = 'accepted_plan' | 'informed_frequency' | 'absent'

/** Internal persisted weekly fact; the integrator must prove durability. */
export interface StrengthWeekTargetRecord extends StrengthWeekScope {
  readonly plannedDays: number | null
  readonly source: StrengthWeekTargetSource
  readonly sourceKey: string | null
}

/** Trusted facts already resolved for this exact week by the future integrator. */
export interface EffectiveStrengthWeekSources extends StrengthWeekScope {
  readonly plan: {
    readonly ownerKey: string
    readonly sourceKey: string
    readonly state: 'accepted' | 'draft' | 'cancelled'
    /** Null falls back to the exact-week informed frequency; zero is a value. */
    readonly daysPerWeek: number | null
  } | null
  readonly informedFrequency: {
    readonly ownerKey: string
    readonly sourceKey: string
    readonly daysPerWeek: number | null
  } | null
}

export interface ResolveStrengthWeekTargetInput {
  readonly scope: StrengthWeekScope
  readonly existingRecord: StrengthWeekTargetRecord | null
  /** Null means no historical proof, not an empty profile and not zero. */
  readonly effectiveSources: EffectiveStrengthWeekSources | null
}

export type StrengthWeekIssue =
  | 'invalid_owner'
  | 'invalid_week'
  | 'invalid_observation_date'
  | 'mixed_owner'
  | 'record_week_mismatch'
  | 'effective_week_mismatch'
  | 'effective_sources_missing'
  | 'invalid_target_record'
  | 'invalid_target_value'
  | 'invalid_source_reference'
  | 'invalid_workout_key'
  | 'invalid_workout_date'
  | 'invalid_workout_state'
  | 'invalid_catalogue_category'
  | 'invalid_stored_answer'
  | 'stored_answer_workout_mismatch'
  | 'conflicting_workout_duplicate'

export type ResolveStrengthWeekTargetResult =
  | {
      readonly status: 'reuse_existing' | 'propose_new'
      readonly record: StrengthWeekTargetRecord
      readonly issues: readonly StrengthWeekIssue[]
    }
  | {
      readonly status: 'unavailable' | 'invalid_input'
      readonly record: null
      readonly issues: readonly StrengthWeekIssue[]
    }

/** Only used when catalogueCategory is null (genuinely unrecognised type). */
export interface PersistedStrengthAnswer {
  readonly ownerKey: string
  readonly workoutKey: string
  readonly answer: 'yes' | 'no'
}

export interface StrengthWeekWorkout {
  readonly ownerKey: string
  readonly workoutKey: string
  readonly localDate: string
  readonly state: 'confirmed' | 'pending' | 'cancelled'
  /** Authoritative category of the confirmed event, not today's active lookup. */
  readonly catalogueCategory: 'musculacao' | 'cardio' | 'esporte' | 'mobilidade' | null
  readonly storedStrengthAnswer: PersistedStrengthAnswer | null
}

export interface SummarizeStrengthTrainingWeekInput {
  readonly scope: StrengthWeekScope & { readonly asOfLocalDate: string }
  readonly persistedTarget: StrengthWeekTargetRecord | null
  readonly workouts: readonly StrengthWeekWorkout[]
}

export interface StrengthTrainingWeekSummary {
  readonly status: 'counted' | 'invalid_input'
  readonly completedStrengthDays: number | null
  readonly plannedDays: number | null
  readonly targetSource: StrengthWeekTargetSource | null
  readonly targetAvailability: 'available' | 'zero' | 'absent' | 'not_frozen' | 'unavailable'
  readonly percentage: number | null
  readonly countedLocalDates: readonly string[]
  /** Internal keys only; no display metric or public API is defined here. */
  readonly otherWorkoutKeys: readonly string[]
  readonly unclassifiedWorkoutKeys: readonly string[]
  readonly issues: readonly StrengthWeekIssue[]
}

/** Pure proposal/reuse only. A proposed record is not durable publication authority. */
export function resolveStrengthWeekTarget(
  input: ResolveStrengthWeekTargetInput,
): ResolveStrengthWeekTargetResult {
  const { scope, existingRecord, effectiveSources } = input
  const weekStart = civilDay(scope.weekStartDate)
  const invalid = (issue: StrengthWeekIssue): ResolveStrengthWeekTargetResult => ({
    status: 'invalid_input',
    record: null,
    issues: [issue],
  })
  if (!nonblank(scope.ownerKey)) return invalid('invalid_owner')
  if (weekStart === null || (weekStart + 3) % 7 !== 0) return invalid('invalid_week')

  // A valid durable winner is authoritative before any later source facts.
  if (existingRecord !== null) {
    const issues = targetRecordIssues(existingRecord, scope)
    if (issues.length > 0) return { status: 'invalid_input', record: null, issues }
    return { status: 'reuse_existing', record: existingRecord, issues: [] }
  }
  if (effectiveSources === null) {
    return { status: 'unavailable', record: null, issues: ['effective_sources_missing'] }
  }

  const issues = new Set<StrengthWeekIssue>()
  collectOwnerIssue(effectiveSources.ownerKey, scope.ownerKey, issues)
  const sourceWeek = civilDay(effectiveSources.weekStartDate)
  if (sourceWeek === null || (sourceWeek + 3) % 7 !== 0) issues.add('invalid_week')
  if (issues.size > 0)
    return { status: 'invalid_input', record: null, issues: sortedIssues(issues) }
  if (effectiveSources.weekStartDate !== scope.weekStartDate) {
    return { status: 'unavailable', record: null, issues: ['effective_week_mismatch'] }
  }

  const { plan, informedFrequency } = effectiveSources
  if (plan !== null) {
    collectSourceIssues(plan, scope.ownerKey, issues)
    if (plan.state !== 'accepted' && plan.state !== 'draft' && plan.state !== 'cancelled') {
      issues.add('invalid_target_record')
    }
  }
  if (informedFrequency !== null) {
    collectSourceIssues(informedFrequency, scope.ownerKey, issues)
  }
  if (issues.size > 0)
    return { status: 'invalid_input', record: null, issues: sortedIssues(issues) }

  let plannedDays: number | null = null
  let source: StrengthWeekTargetSource = 'absent'
  let sourceKey: string | null = null
  if (plan !== null && plan.state === 'accepted' && plan.daysPerWeek !== null) {
    plannedDays = plan.daysPerWeek
    source = 'accepted_plan'
    sourceKey = plan.sourceKey
  } else if (informedFrequency !== null && informedFrequency.daysPerWeek !== null) {
    plannedDays = informedFrequency.daysPerWeek
    source = 'informed_frequency'
    sourceKey = informedFrequency.sourceKey
  }
  return {
    status: 'propose_new',
    record: {
      ownerKey: scope.ownerKey,
      weekStartDate: scope.weekStartDate,
      plannedDays,
      source,
      sourceKey,
    },
    issues: [],
  }
}

/** Pure projection only. Never reads mutable profile/plan or computes energy. */
export function summarizeStrengthTrainingWeek(
  input: SummarizeStrengthTrainingWeekInput,
): StrengthTrainingWeekSummary {
  const { scope, persistedTarget, workouts } = input
  if (!nonblank(scope.ownerKey)) return invalidSummary(['invalid_owner'])
  const weekStart = civilDay(scope.weekStartDate)
  if (weekStart === null || (weekStart + 3) % 7 !== 0) return invalidSummary(['invalid_week'])
  const observedDay = civilDay(scope.asOfLocalDate)
  if (observedDay === null || observedDay < weekStart || observedDay > weekStart + 6) {
    return invalidSummary(['invalid_observation_date'])
  }

  const issues = new Set<StrengthWeekIssue>(
    persistedTarget === null ? [] : targetRecordIssues(persistedTarget, scope),
  )
  const byKey = new Map<string, StrengthWeekWorkout>()
  // Validate the complete projected facts before excluding a date or state.
  // Otherwise a conflicting cancelled copy could silently select a winner.
  for (const event of workouts) {
    collectOwnerIssue(event.ownerKey, scope.ownerKey, issues)
    if (!nonblank(event.workoutKey)) issues.add('invalid_workout_key')
    if (civilDay(event.localDate) === null) issues.add('invalid_workout_date')
    if (event.state !== 'confirmed' && event.state !== 'pending' && event.state !== 'cancelled') {
      issues.add('invalid_workout_state')
    }
    if (
      event.catalogueCategory !== null &&
      event.catalogueCategory !== 'musculacao' &&
      event.catalogueCategory !== 'cardio' &&
      event.catalogueCategory !== 'esporte' &&
      event.catalogueCategory !== 'mobilidade'
    ) {
      issues.add('invalid_catalogue_category')
    }
    const answer = event.storedStrengthAnswer
    if (answer !== null) {
      collectOwnerIssue(answer.ownerKey, scope.ownerKey, issues)
      if (answer.workoutKey !== event.workoutKey) issues.add('stored_answer_workout_mismatch')
      if (answer.answer !== 'yes' && answer.answer !== 'no') issues.add('invalid_stored_answer')
    }
    const previous = byKey.get(event.workoutKey)
    if (previous !== undefined && !sameWorkout(previous, event)) {
      issues.add('conflicting_workout_duplicate')
    } else if (previous === undefined) {
      byKey.set(event.workoutKey, event)
    }
  }
  if (issues.size > 0) return invalidSummary(sortedIssues(issues))

  const countedDates = new Set<string>()
  const otherWorkoutKeys: string[] = []
  const unclassifiedWorkoutKeys: string[] = []
  for (const event of byKey.values()) {
    if (
      event.state !== 'confirmed' ||
      event.localDate < scope.weekStartDate ||
      event.localDate > scope.asOfLocalDate
    ) {
      continue
    }
    if (event.catalogueCategory === 'musculacao') {
      countedDates.add(event.localDate)
    } else if (event.catalogueCategory !== null) {
      otherWorkoutKeys.push(event.workoutKey)
    } else if (event.storedStrengthAnswer?.answer === 'yes') {
      countedDates.add(event.localDate)
    } else if (event.storedStrengthAnswer?.answer === 'no') {
      otherWorkoutKeys.push(event.workoutKey)
    } else {
      unclassifiedWorkoutKeys.push(event.workoutKey)
    }
  }

  const countedLocalDates = [...countedDates].sort()
  const completedStrengthDays = countedLocalDates.length
  const plannedDays = persistedTarget?.plannedDays ?? null
  return {
    status: 'counted',
    completedStrengthDays,
    plannedDays,
    targetSource: persistedTarget?.source ?? null,
    targetAvailability:
      persistedTarget === null
        ? 'not_frozen'
        : persistedTarget.source === 'absent'
          ? 'absent'
          : plannedDays === 0
            ? 'zero'
            : 'available',
    percentage:
      plannedDays !== null && plannedDays > 0
        ? Math.min(100, Math.round((100 * completedStrengthDays) / plannedDays))
        : null,
    countedLocalDates,
    otherWorkoutKeys: otherWorkoutKeys.sort(),
    unclassifiedWorkoutKeys: unclassifiedWorkoutKeys.sort(),
    issues: [],
  }
}

const civilDayMs = 86_400_000

/** Deterministic civil calendar arithmetic; never reads a clock or a timezone. */
function civilDay(value: unknown): number | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) return null
  const timestamp = Date.parse(`${value}T00:00:00.000Z`)
  if (!Number.isFinite(timestamp) || new Date(timestamp).toISOString().slice(0, 10) !== value) {
    return null
  }
  return timestamp / civilDayMs
}

function nonblank(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function validDays(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}

function sortedIssues(issues: ReadonlySet<StrengthWeekIssue>): StrengthWeekIssue[] {
  return [...issues].sort()
}

function collectOwnerIssue(
  ownerKey: unknown,
  expectedOwner: string,
  issues: Set<StrengthWeekIssue>,
): void {
  if (!nonblank(ownerKey)) issues.add('invalid_owner')
  else if (ownerKey !== expectedOwner) issues.add('mixed_owner')
}

function collectSourceIssues(
  source: {
    readonly ownerKey: string
    readonly sourceKey: string
    readonly daysPerWeek: number | null
  },
  expectedOwner: string,
  issues: Set<StrengthWeekIssue>,
): void {
  collectOwnerIssue(source.ownerKey, expectedOwner, issues)
  if (!nonblank(source.sourceKey)) issues.add('invalid_source_reference')
  if (source.daysPerWeek !== null && !validDays(source.daysPerWeek)) {
    issues.add('invalid_target_value')
  }
}

function targetRecordIssues(
  record: StrengthWeekTargetRecord,
  scope: StrengthWeekScope,
): StrengthWeekIssue[] {
  const issues = new Set<StrengthWeekIssue>()
  collectOwnerIssue(record.ownerKey, scope.ownerKey, issues)
  if (record.weekStartDate !== scope.weekStartDate) issues.add('record_week_mismatch')
  if (record.plannedDays !== null && !validDays(record.plannedDays)) {
    issues.add('invalid_target_value')
  }
  if (record.source === 'absent') {
    if (record.plannedDays !== null || record.sourceKey !== null)
      issues.add('invalid_target_record')
  } else if (record.source === 'accepted_plan' || record.source === 'informed_frequency') {
    if (record.plannedDays === null) issues.add('invalid_target_record')
    if (!nonblank(record.sourceKey)) issues.add('invalid_source_reference')
  } else {
    issues.add('invalid_target_record')
  }
  return sortedIssues(issues)
}

function sameWorkout(first: StrengthWeekWorkout, second: StrengthWeekWorkout): boolean {
  const firstAnswer = first.storedStrengthAnswer
  const secondAnswer = second.storedStrengthAnswer
  return (
    first.ownerKey === second.ownerKey &&
    first.workoutKey === second.workoutKey &&
    first.localDate === second.localDate &&
    first.state === second.state &&
    first.catalogueCategory === second.catalogueCategory &&
    (firstAnswer === null
      ? secondAnswer === null
      : secondAnswer !== null &&
        firstAnswer.ownerKey === secondAnswer.ownerKey &&
        firstAnswer.workoutKey === secondAnswer.workoutKey &&
        firstAnswer.answer === secondAnswer.answer)
  )
}

function invalidSummary(issues: readonly StrengthWeekIssue[]): StrengthTrainingWeekSummary {
  return {
    status: 'invalid_input',
    completedStrengthDays: null,
    plannedDays: null,
    targetSource: null,
    targetAvailability: 'unavailable',
    percentage: null,
    countedLocalDates: [],
    otherWorkoutKeys: [],
    unclassifiedWorkoutKeys: [],
    issues,
  }
}
