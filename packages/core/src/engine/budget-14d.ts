/** C4 DRAFT: pure calculation only; no consumer or clinical action is enabled. */
export interface Budget14dDraftPolicy {
  readonly version: 'c4-draft-v1'
  readonly draft: true
  readonly displayEnabled: false
  readonly denominator: 'included-days'
  readonly windowMode: 'rolling-calendar'
  readonly gainBasis: 'expenditure'
  readonly referenceRounding: 'daily-integer'
  readonly damToleranceKcal: 0
  readonly maintenanceLimit: 4
  readonly incompleteDays: 'exclude'
  readonly belowHalfDays: 'exclude'
  readonly confirmedSkippedBelowHalf: 'exclude'
}

export interface Budget14dDay {
  readonly ownerKey: string
  readonly date: string
  readonly protocol: string | null
  readonly closed: boolean | null
  readonly status: string | null
  readonly hasRegistration: boolean | null
  readonly consumedKcal: number | null
  readonly targetKcal: number | null
  readonly rule: {
    readonly phaseKey: string | null
    readonly targetMatchesRule: boolean | null
    readonly adjustmentKcal: number | null
    readonly gainMultiplier: number | null
  } | null
}

export interface Budget14dInput {
  readonly scope: {
    readonly ownerKey: string
    readonly protocol: string | null
    readonly phaseKey: string | null
    readonly phaseStartDate: string | null
  }
  readonly window: { readonly fromDate: string; readonly throughDate: string }
  /** Mandatory explicit DRAFT assumptions; never inferred from a profile. */
  readonly policy: unknown
  readonly days: readonly Budget14dDay[]
}

export interface Budget14dCoverage {
  readonly windowDays: 14
  readonly phaseDaysInWindow: number
  readonly countedDays: number
  readonly includedDates: readonly string[]
  readonly denominator: 'included-days'
  readonly calendarComplete: boolean
  /** False means metrics are withheld, even if some days were usable. */
  readonly dataComplete: boolean
}

export interface Budget14dIssue {
  readonly code: string
  readonly date: string | null
}

export interface Budget14dMetrics {
  readonly consumedTotalKcal: number
  readonly budgetTotalKcal: number
  readonly percentage: number
  readonly daysAboveTarget: number | null
  readonly limit: 4 | null
}

interface Budget14dResultBase {
  readonly version: 'c4-draft-v1'
  readonly draft: true
  readonly displayEnabled: false
  readonly policyApplied: Budget14dDraftPolicy | null
  readonly coverage: Budget14dCoverage | null
  readonly issues: readonly Budget14dIssue[]
  readonly excludedDays: readonly Budget14dIssue[]
}

export type Budget14dResult = Budget14dResultBase &
  (
    | { readonly status: 'draft_calculated'; readonly metrics: Budget14dMetrics }
    | {
        readonly status: 'empty' | 'insufficient_data' | 'invalid_input' | 'not_applicable'
        readonly metrics: null
      }
  )

// These are supported test assumptions, not a product default. A caller must
// supply every value explicitly; no version can activate display or treatment.
const supportedPolicy: Budget14dDraftPolicy = {
  version: 'c4-draft-v1',
  draft: true,
  displayEnabled: false,
  denominator: 'included-days',
  windowMode: 'rolling-calendar',
  gainBasis: 'expenditure',
  referenceRounding: 'daily-integer',
  damToleranceKcal: 0,
  maintenanceLimit: 4,
  incompleteDays: 'exclude',
  belowHalfDays: 'exclude',
  confirmedSkippedBelowHalf: 'exclude',
}
const civilDayMs = 86_400_000
const knownProtocols = ['recomposicao', 'ganho_massa', 'manutencao']

function readPolicy(value: unknown): Budget14dDraftPolicy | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  const record = value as Record<string, unknown>
  const entries = Object.entries(supportedPolicy)
  if (Object.keys(record).length !== entries.length) return null
  if (!entries.every(([key, expected]) => Object.hasOwn(record, key) && record[key] === expected)) {
    return null
  }
  return { ...supportedPolicy }
}

/** Civil dates are provided by the caller; UTC arithmetic avoids DST shifts. */
function civilDate(value: unknown): number | null {
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

function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function sortIssues(issues: readonly Budget14dIssue[]): Budget14dIssue[] {
  return [...issues].sort(
    (a, b) => (a.date ?? '').localeCompare(b.date ?? '') || a.code.localeCompare(b.code),
  )
}

export function calculateDraftBudget14d(input: Budget14dInput): Budget14dResult {
  const policyApplied = readPolicy(input.policy)
  const base: Budget14dResultBase = {
    version: 'c4-draft-v1',
    draft: true,
    displayEnabled: false,
    policyApplied,
    coverage: null,
    issues: [],
    excludedDays: [],
  }
  const invalid = (code: string): Budget14dResult => ({
    ...base,
    status: 'invalid_input',
    metrics: null,
    issues: [{ code, date: null }],
  })
  if (!policyApplied) return invalid('invalid_policy')
  if (!nonblank(input.scope.ownerKey)) return invalid('invalid_owner')
  const protocol = input.scope.protocol
  if (protocol !== 'manutencao' && protocol !== 'ganho_massa') {
    return { ...base, status: 'not_applicable', metrics: null }
  }
  const from = civilDate(input.window.fromDate)
  const through = civilDate(input.window.throughDate)
  if (from === null || through === null || through - from !== 13) return invalid('invalid_window')
  const phaseStart = civilDate(input.scope.phaseStartDate)
  if (!nonblank(input.scope.phaseKey) || phaseStart === null || phaseStart > through) {
    return invalid('invalid_phase')
  }

  // Validate identity and uniqueness even for a row subsequently excluded.
  // Structural invalidity takes precedence over any candidate's missing data.
  const structural = new Set<string>()
  const seenDates = new Set<string>()
  for (const row of input.days) {
    if (row.ownerKey !== input.scope.ownerKey) structural.add('mixed_owner')
    if (civilDate(row.date) === null) structural.add('invalid_day_date')
    if (seenDates.has(row.date)) structural.add('duplicate_date')
    seenDates.add(row.date)
  }
  if (structural.size > 0) {
    return {
      ...base,
      status: 'invalid_input',
      metrics: null,
      issues: sortIssues([...structural].map((code) => ({ code, date: null }))),
    }
  }

  const issues: Budget14dIssue[] = []
  const excludedDays: Budget14dIssue[] = []
  const includedDates: string[] = []
  let consumedTotalKcal = 0
  let budgetTotalKcal = 0
  let daysAboveTarget = 0
  // Date order applies to arithmetic too, not just to the returned dates.
  const rows = [...input.days].sort((a, b) => a.date.localeCompare(b.date))
  for (const row of rows) {
    const exclude = (code: string) => {
      excludedDays.push({ code, date: row.date })
    }
    const missing = (code: string) => {
      issues.push({ code, date: row.date })
    }
    if (row.date < input.window.fromDate) {
      exclude('before_window')
      continue
    }
    if (row.date > input.window.throughDate) {
      exclude('after_window')
      continue
    }
    if (row.date < (input.scope.phaseStartDate ?? '')) {
      exclude('before_phase')
      continue
    }
    // Known exclusions need no unrelated historical data. Only a remaining
    // candidate's ambiguity can invalidate the calculation.
    if (row.closed === false) {
      exclude('open')
      continue
    }
    if (row.hasRegistration === false) {
      exclude('no_registration')
      continue
    }
    if (row.status === 'pending') {
      exclude('pending')
      continue
    }
    if (row.status === 'incomplete_no_response') {
      exclude('incomplete')
      continue
    }
    const rule = row.rule
    if (rule && nonblank(rule.phaseKey) && rule.phaseKey !== input.scope.phaseKey) {
      exclude('different_phase')
      continue
    }
    if (row.protocol === null || !knownProtocols.includes(row.protocol)) {
      missing('unknown_protocol')
      continue
    }
    if (row.protocol !== protocol) {
      exclude('different_protocol')
      continue
    }
    if (row.closed !== true) {
      missing('unknown_closed')
      continue
    }
    if (row.status !== 'complete' && row.status !== 'user_skipped') {
      missing('unknown_status')
      continue
    }
    if (row.hasRegistration !== true) {
      missing('unknown_registration')
      continue
    }
    if (!finite(row.targetKcal) || row.targetKcal <= 0) {
      missing('invalid_target')
      continue
    }
    if (!finite(row.consumedKcal) || row.consumedKcal < 0) {
      missing('invalid_consumed')
      continue
    }
    if (!rule) {
      missing('missing_rule')
      continue
    }
    if (!nonblank(rule.phaseKey)) {
      missing('unknown_phase')
      continue
    }
    if (rule.targetMatchesRule !== true) {
      missing('target_rule_mismatch')
      continue
    }
    // An old/unproven target cannot establish the current phase's quality.
    if (row.consumedKcal < 0.5 * row.targetKcal) {
      exclude('below_half')
      continue
    }
    if (!finite(rule.adjustmentKcal)) {
      missing('invalid_adjustment')
      continue
    }
    if (protocol === 'ganho_massa' && (!finite(rule.gainMultiplier) || rule.gainMultiplier <= 0)) {
      missing('invalid_multiplier')
      continue
    }
    const unroundedBase =
      protocol === 'ganho_massa'
        ? (row.targetKcal - rule.adjustmentKcal) / (rule.gainMultiplier ?? Number.NaN)
        : row.targetKcal - rule.adjustmentKcal
    const reference = Math.round(unroundedBase) + 0
    if (!Number.isFinite(reference) || reference <= 0) {
      missing('invalid_reference')
      continue
    }
    includedDates.push(row.date)
    consumedTotalKcal += row.consumedKcal
    budgetTotalKcal += reference
    if (row.consumedKcal > row.targetKcal) daysAboveTarget += 1
  }
  const coverage: Budget14dCoverage = {
    windowDays: 14,
    phaseDaysInWindow: through - Math.max(from, phaseStart) + 1,
    countedDays: includedDates.length,
    includedDates,
    denominator: 'included-days',
    calendarComplete: includedDates.length === 14,
    dataComplete: issues.length === 0,
  }
  const selected = {
    ...base,
    coverage,
    issues: sortIssues(issues),
    excludedDays: sortIssues(excludedDays),
  }
  if (issues.length > 0) return { ...selected, status: 'insufficient_data', metrics: null }
  if (includedDates.length === 0) return { ...selected, status: 'empty', metrics: null }
  const percentage = (100 * consumedTotalKcal) / budgetTotalKcal
  if (![consumedTotalKcal, budgetTotalKcal, percentage].every(Number.isFinite)) {
    return {
      ...selected,
      coverage: { ...coverage, dataComplete: false },
      status: 'insufficient_data',
      metrics: null,
      issues: [{ code: 'nonfinite_total', date: null }],
    }
  }
  return {
    ...selected,
    status: 'draft_calculated',
    metrics: {
      consumedTotalKcal: consumedTotalKcal + 0,
      budgetTotalKcal,
      percentage: percentage + 0,
      daysAboveTarget: protocol === 'manutencao' ? daysAboveTarget : null,
      limit: protocol === 'manutencao' ? 4 : null,
    },
  }
}
