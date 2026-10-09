import { describe, expect, it } from 'vitest'
import {
  type Budget14dDay,
  type Budget14dDraftPolicy,
  type Budget14dInput,
  calculateDraftBudget14d,
} from './budget-14d.js'

const policy: Budget14dDraftPolicy = {
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
const dates = [
  '2026-09-26',
  '2026-09-27',
  '2026-09-28',
  '2026-09-29',
  '2026-09-30',
  '2026-10-01',
  '2026-10-02',
  '2026-10-03',
  '2026-10-04',
  '2026-10-05',
  '2026-10-06',
  '2026-10-07',
  '2026-10-08',
  '2026-10-09',
] as const
const day = (date: string, changes: Partial<Budget14dDay> = {}): Budget14dDay => ({
  ownerKey: 'qa-a',
  date,
  protocol: 'manutencao',
  closed: true,
  status: 'complete',
  hasRegistration: true,
  consumedKcal: 2600,
  targetKcal: 2600,
  rule: { phaseKey: 'phase-a', targetMatchesRule: true, adjustmentKcal: 0, gainMultiplier: null },
  ...changes,
})
const input = (
  days: readonly Budget14dDay[],
  changes: Partial<Budget14dInput> = {},
): Budget14dInput => ({
  scope: {
    ownerKey: 'qa-a',
    protocol: 'manutencao',
    phaseKey: 'phase-a',
    phaseStartDate: dates[0],
  },
  window: { fromDate: dates[0], throughDate: dates[13] },
  policy,
  days,
  ...changes,
})
const gain = (date: string, changes: Partial<Budget14dDay> = {}) =>
  day(date, {
    protocol: 'ganho_massa',
    consumedKcal: 2900,
    targetKcal: 2900,
    rule: { phaseKey: 'phase-a', targetMatchesRule: true, adjustmentKcal: 0, gainMultiplier: 1.05 },
    ...changes,
  })
const gainScope = {
  ownerKey: 'qa-a',
  protocol: 'ganho_massa',
  phaseKey: 'phase-a',
  phaseStartDate: dates[0],
}

function calculated(value: Budget14dInput) {
  const result = calculateDraftBudget14d(value)
  expect(result.status).toBe('draft_calculated')
  if (result.status !== 'draft_calculated')
    throw new Error(`Expected calculation, got ${result.status}`)
  expect(result.draft).toBe(true)
  expect(result.displayEnabled).toBe(false)
  expect(result.policyApplied).toEqual(policy)
  return result
}
function withheld(value: Budget14dInput, status: string, code?: string) {
  const result = calculateDraftBudget14d(value)
  expect(result.status).toBe(status)
  expect(result.metrics).toBeNull()
  expect(result.version).toBe('c4-draft-v1')
  expect(result.draft).toBe(true)
  expect(result.displayEnabled).toBe(false)
  if (code) expect(result.issues).toContainEqual({ code, date: null })
  return result
}

describe('C4 explicit DRAFT budget, with no consumer', () => {
  it('exact maintenance example: 2600 × 14 = 36400 and six / four, without clamping', () => {
    const result = calculated(
      input(dates.map((date, index) => day(date, { consumedKcal: index < 6 ? 2601 : 2600 }))),
    )
    expect(result.metrics).toEqual({
      consumedTotalKcal: 36406,
      budgetTotalKcal: 36400,
      percentage: (100 * 36406) / 36400,
      daysAboveTarget: 6,
      limit: 4,
    })
    expect(result.coverage).toEqual({
      windowDays: 14,
      phaseDaysInWindow: 14,
      countedDays: 14,
      includedDates: dates,
      denominator: 'included-days',
      calendarComplete: true,
      dataComplete: true,
    })
  })
  it('exact gain example uses historical daily rounding: 2900 / 1.05 → 2762', () => {
    const result = calculated(
      input(
        dates.map((date) => gain(date)),
        { scope: gainScope },
      ),
    )
    expect(result.metrics).toEqual({
      consumedTotalKcal: 40600,
      budgetTotalKcal: 38668,
      percentage: (100 * 40600) / 38668,
      daysAboveTarget: null,
      limit: null,
    })
    expect(result.metrics.percentage).not.toBe(105)
    // Exercise is deliberately absent from the contract; extra loader metadata cannot add it.
    const rows = dates.map((date) => ({ ...gain(date), exerciseKcal: 400 }))
    expect(calculateDraftBudget14d(input(rows, { scope: gainScope }))).toEqual(result)
  })
  it('three registered days mean 7800 / 7800 with explicit 3/14 coverage', () => {
    const result = calculated(input(dates.slice(11).map((date) => day(date))))
    expect(result.metrics.budgetTotalKcal).toBe(7800)
    expect(result.metrics.consumedTotalKcal).toBe(7800)
    expect(result.coverage).toMatchObject({
      countedDays: 3,
      windowDays: 14,
      calendarComplete: false,
    })
  })
  it('uses inclusive calendar limits, ignores future/open days, never extends gaps', () => {
    const rows = [
      day('2026-09-25'),
      day('2026-10-10'),
      day(dates[13], { closed: false }),
      day(dates[0]),
      day(dates[12]),
    ]
    const result = calculated(input(rows))
    expect(result.coverage?.includedDates).toEqual([dates[0], dates[12]])
    expect(result.metrics.budgetTotalKcal).toBe(5200)
    expect(result.excludedDays).toEqual([
      { date: '2026-09-25', code: 'before_window' },
      { date: dates[13], code: 'open' },
      { date: '2026-10-10', code: 'after_window' },
    ])
    expect(calculateDraftBudget14d(input([...rows].reverse()))).toEqual(result)
  })
  it('historical multipliers and adjustments vary by day, never by current profile', () => {
    const variable = dates.map((date, i) => day(date, { targetKcal: i < 7 ? 2600 : 2450 }))
    expect(calculated(input(variable)).metrics.budgetTotalKcal).toBe(35350)
    const adjusted = variable.map((row, i) => ({
      ...row,
      rule: {
        phaseKey: 'phase-a',
        targetMatchesRule: true,
        adjustmentKcal: i < 7 ? 0 : -150,
        gainMultiplier: null,
      },
    }))
    const result = calculated(input(adjusted))
    expect(result.metrics.budgetTotalKcal).toBe(36400)
    expect(result.metrics.daysAboveTarget).toBe(7) // Against 2450, not base 2600.
    const gains = dates.map((date, i) =>
      gain(date, {
        rule: {
          phaseKey: 'phase-a',
          targetMatchesRule: true,
          adjustmentKcal: 0,
          gainMultiplier: i < 7 ? 1.05 : 1.1,
        },
      }),
    )
    expect(calculated(input(gains, { scope: gainScope })).metrics.budgetTotalKcal).toBe(
      7 * 2762 + 7 * 2636,
    )
  })
  it('gain reverses the historical adjustment before dividing and rounding', () => {
    const result = calculated(
      input(
        [
          gain(dates[0], {
            targetKcal: 2750,
            consumedKcal: 2750,
            rule: {
              phaseKey: 'phase-a',
              targetMatchesRule: true,
              adjustmentKcal: -150,
              gainMultiplier: 1.05,
            },
          }),
        ],
        { scope: gainScope },
      ),
    )
    expect(result.metrics).toEqual({
      consumedTotalKcal: 2750,
      budgetTotalKcal: 2762,
      percentage: (100 * 2750) / 2762,
      daysAboveTarget: null,
      limit: null,
    })
  })
  it('phase change excludes prior day; retagged old target without history withholds all metrics', () => {
    const scope = { ...gainScope, phaseStartDate: '2026-10-03' }
    const result = calculateDraftBudget14d(
      input(
        [
          day('2026-10-02'),
          gain('2026-10-03', { targetKcal: 2600, rule: null }),
          gain('2026-10-04'),
        ],
        { scope },
      ),
    )
    expect(result.status).toBe('insufficient_data')
    expect(result.metrics).toBeNull()
    expect(result.issues).toContainEqual({ date: '2026-10-03', code: 'missing_rule' })
    expect(result.coverage?.dataComplete).toBe(false)
    const resolved = calculated(
      input([gain('2026-10-03', { rule: null }), gain('2026-10-04')], {
        scope: { ...scope, phaseStartDate: '2026-10-04' },
      }),
    )
    expect(resolved.metrics.budgetTotalKcal).toBe(2762)
    expect(resolved.coverage?.phaseDaysInWindow).toBe(6)
  })
  it('same protocol in an old phase remains excluded; A → B → A is stateless', () => {
    const a = input([
      day(dates[0], {
        rule: {
          phaseKey: 'old-phase',
          targetMatchesRule: true,
          adjustmentKcal: 0,
          gainMultiplier: null,
        },
      }),
      day(dates[1]),
    ])
    const first = calculated(a)
    expect(first.coverage?.includedDates).toEqual([dates[1]])
    const b = input([day(dates[2], { ownerKey: 'qa-b' })], {
      scope: { ...a.scope, ownerKey: 'qa-b' },
    })
    expect(calculated(b).coverage?.includedDates).toEqual([dates[2]])
    expect(calculateDraftBudget14d(a)).toEqual(first)
    withheld(input([day('2026-09-25', { ownerKey: 'qa-b' })]), 'invalid_input', 'mixed_owner')
  })
  it('explicit quality excludes <50%, incomplete and confirmed skip below half; exactly half counts', () => {
    const result = calculated(
      input([
        day(dates[0], { consumedKcal: 1299 }),
        day(dates[1], { consumedKcal: 1300 }),
        day(dates[2], { status: 'incomplete_no_response' }),
        day(dates[3], { consumedKcal: 1299, status: 'user_skipped' }),
        day(dates[4], { status: 'user_skipped' }),
        day(dates[5], { status: 'pending' }),
        day(dates[6], { hasRegistration: false }),
      ]),
    )
    expect(result.coverage?.includedDates).toEqual([dates[1], dates[4]])
    expect(result.metrics.consumedTotalKcal).toBe(3900)
    expect(result.metrics.budgetTotalKcal).toBe(5200)
  })
  it.each([
    [{ protocol: null }, 'unknown_protocol'],
    [{ protocol: 'other' }, 'unknown_protocol'],
    [{ closed: null }, 'unknown_closed'],
    [{ status: null }, 'unknown_status'],
    [{ status: 'other' }, 'unknown_status'],
    [{ hasRegistration: null }, 'unknown_registration'],
    [{ rule: null }, 'missing_rule'],
    [
      {
        rule: { phaseKey: null, targetMatchesRule: true, adjustmentKcal: 0, gainMultiplier: null },
      },
      'unknown_phase',
    ],
    [
      {
        rule: {
          phaseKey: 'phase-a',
          targetMatchesRule: false,
          adjustmentKcal: 0,
          gainMultiplier: null,
        },
      },
      'target_rule_mismatch',
    ],
    [
      {
        rule: {
          phaseKey: 'phase-a',
          targetMatchesRule: null,
          adjustmentKcal: 0,
          gainMultiplier: null,
        },
      },
      'target_rule_mismatch',
    ],
  ] as const)('ambiguous eligible day %j withholds all figures (%s)', (changes, code) => {
    const result = withheld(input([day(dates[0], changes), day(dates[1])]), 'insufficient_data')
    expect(result.issues).toContainEqual({ date: dates[0], code })
    expect(result.coverage?.dataComplete).toBe(false)
  })
  it.each([
    null,
    0,
    -1,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('invalid target %s is not coerced into a budget', (targetKcal) => {
    const result = withheld(input([day(dates[0], { targetKcal })]), 'insufficient_data')
    expect(result.issues).toContainEqual({ date: dates[0], code: 'invalid_target' })
  })
  it.each([
    null,
    -1,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('invalid consumed %s is not a zero', (consumedKcal) => {
    const result = withheld(input([day(dates[0], { consumedKcal })]), 'insufficient_data')
    expect(result.issues).toContainEqual({ date: dates[0], code: 'invalid_consumed' })
  })
  it.each([
    null,
    0,
    -1,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('gain multiplier %s has no current-profile fallback', (gainMultiplier) => {
    const result = withheld(
      input(
        [
          gain(dates[0], {
            rule: {
              phaseKey: 'phase-a',
              targetMatchesRule: true,
              adjustmentKcal: 0,
              gainMultiplier,
            },
          }),
        ],
        { scope: gainScope },
      ),
      'insufficient_data',
    )
    expect(result.issues).toContainEqual({ date: dates[0], code: 'invalid_multiplier' })
  })
  it.each([
    null,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('historical adjustment %s must be explicit and finite', (adjustmentKcal) => {
    const result = withheld(
      input([
        day(dates[0], {
          rule: {
            phaseKey: 'phase-a',
            targetMatchesRule: true,
            adjustmentKcal,
            gainMultiplier: null,
          },
        }),
      ]),
      'insufficient_data',
    )
    expect(result.issues).toContainEqual({ date: dates[0], code: 'invalid_adjustment' })
  })
  it('nonpositive derived base and overflowing totals withhold figures', () => {
    const zero = withheld(
      input([
        day(dates[0], {
          rule: {
            phaseKey: 'phase-a',
            targetMatchesRule: true,
            adjustmentKcal: 2600,
            gainMultiplier: null,
          },
        }),
      ]),
      'insufficient_data',
    )
    expect(zero.issues).toContainEqual({ date: dates[0], code: 'invalid_reference' })
    withheld(
      input(
        dates.map((date) =>
          day(date, { consumedKcal: Number.MAX_VALUE, targetKcal: Number.MAX_VALUE }),
        ),
      ),
      'insufficient_data',
      'nonfinite_total',
    )
    withheld(
      input([day(dates[0], { consumedKcal: Number.MAX_VALUE, targetKcal: 1 })]),
      'insufficient_data',
      'nonfinite_total',
    )
  })
  it('numeric strings are not implicitly coerced into historical energy or rules', () => {
    const rows = [
      { ...day(dates[0]), targetKcal: '2600' },
      { ...day(dates[0]), consumedKcal: '2600' },
      {
        ...day(dates[0]),
        rule: {
          phaseKey: 'phase-a',
          targetMatchesRule: true,
          adjustmentKcal: '0',
          gainMultiplier: null,
        },
      },
      {
        ...gain(dates[0]),
        rule: {
          phaseKey: 'phase-a',
          targetMatchesRule: true,
          adjustmentKcal: 0,
          gainMultiplier: '1.05',
        },
      },
    ]
    for (const row of rows) {
      withheld(
        input([row as unknown as Budget14dDay], {
          scope: { ...gainScope, protocol: row.protocol },
        }),
        'insufficient_data',
      )
    }
  })
  it('empty or only excluded data is empty, with no zero or invented percentage', () => {
    const result = withheld(input([]), 'empty')
    expect(result.coverage).toMatchObject({
      countedDays: 0,
      calendarComplete: false,
      dataComplete: true,
    })
    withheld(
      input([day(dates[0], { closed: false }), day(dates[1], { protocol: 'recomposicao' })]),
      'empty',
    )
  })
  it.each([
    'recomposicao',
    null,
    'unknown',
  ])('scope %s is not applicable to budget and never reuses 7700', (protocol) => {
    withheld(
      input([], { scope: { ownerKey: 'qa-a', protocol, phaseKey: null, phaseStartDate: null } }),
      'not_applicable',
    )
  })
  it.each([
    false,
    true,
  ])('duplicate owner/date rejects identical or conflicting rows (%s)', (conflicting) => {
    withheld(
      input([day(dates[0]), day(dates[0], { consumedKcal: conflicting ? 2700 : 2600 })]),
      'invalid_input',
      'duplicate_date',
    )
  })
  it.each([
    '2026-02-30',
    '2026-13-01',
    '2026-2-01',
  ])('invalid row date %s rejects even outside the window', (date) => {
    withheld(input([day(date)]), 'invalid_input', 'invalid_day_date')
  })
  it.each([
    { fromDate: '2026-09-25', throughDate: '2026-10-09' },
    { fromDate: '2026-10-09', throughDate: '2026-09-26' },
    { fromDate: '2026-02-30', throughDate: '2026-03-13' },
  ])('window %j must be exactly fourteen valid inclusive dates', (window) => {
    withheld(input([], { window }), 'invalid_input', 'invalid_window')
  })
  it.each([
    null,
    '',
    ' ',
    undefined,
    '2026-02-30',
    '2026-10-10',
  ])('missing or invalid phase start %s fails closed', (phaseStartDate) => {
    withheld(
      input([], { scope: { ...gainScope, phaseStartDate: phaseStartDate ?? null } }),
      'invalid_input',
      'invalid_phase',
    )
  })
  it('phase key and owner must be explicit nonblank identifiers', () => {
    for (const value of [null, '', ' ']) {
      withheld(
        input([], { scope: { ...gainScope, phaseKey: value } }),
        'invalid_input',
        'invalid_phase',
      )
    }
    withheld(
      input([], { scope: { ...gainScope, ownerKey: ' ' } }),
      'invalid_input',
      'invalid_owner',
    )
  })
  it('each policy value must be explicitly supported; no auto-enable or fallback', () => {
    for (const key of Object.keys(policy)) {
      const missing = { ...policy }
      Reflect.deleteProperty(missing, key)
      withheld(input([], { policy: missing }), 'invalid_input', 'invalid_policy')
      withheld(
        input([], { policy: { ...policy, [key]: 'unsupported' } }),
        'invalid_input',
        'invalid_policy',
      )
    }
    for (const value of [undefined, null, {}, { ...policy, displayEnabled: true }]) {
      withheld(input([], { policy: value }), 'invalid_input', 'invalid_policy')
    }
    withheld(
      input([], { policy: { ...policy, extraTolerance: 100 } }),
      'invalid_input',
      'invalid_policy',
    )
  })
  it('identity/date invalidity precedes missing history, regardless of row order', () => {
    const rows = [
      day(dates[0], { rule: null }),
      day('2026-09-25', { ownerKey: 'qa-b' }),
      day(dates[1]),
      day(dates[1]),
    ]
    const result = withheld(input(rows), 'invalid_input')
    expect(result.coverage).toBeNull()
    expect(result.issues).toEqual([
      { date: null, code: 'duplicate_date' },
      { date: null, code: 'mixed_owner' },
    ])
    expect(calculateDraftBudget14d(input([...rows].reverse()))).toEqual(result)
  })
  it('fractional consumption is preserved and fractional excess counts as a DAM', () => {
    const result = calculated(
      input([day(dates[0], { consumedKcal: 2600.25 }), day(dates[1], { consumedKcal: 2600.5 })]),
    )
    expect(result.metrics).toEqual({
      consumedTotalKcal: 5200.75,
      budgetTotalKcal: 5200,
      percentage: (100 * 5200.75) / 5200,
      daysAboveTarget: 2,
      limit: 4,
    })
  })
  it('quality uses the frozen target, while reference rounding never hides fractional excess', () => {
    const historicalRule = {
      phaseKey: 'phase-a',
      targetMatchesRule: true,
      adjustmentKcal: -150,
      gainMultiplier: null,
    }
    const half = calculated(
      input([
        day(dates[0], { consumedKcal: 1225, targetKcal: 2450, rule: historicalRule }),
        day(dates[1], { consumedKcal: 1224.75, targetKcal: 2450, rule: historicalRule }),
      ]),
    )
    expect(half.coverage?.includedDates).toEqual([dates[0]])
    expect(half.metrics.budgetTotalKcal).toBe(2600)
    const fraction = calculated(
      input([day(dates[0], { targetKcal: 2600.5, consumedKcal: 2600.75 })]),
    )
    expect(fraction.metrics.budgetTotalKcal).toBe(2601)
    expect(fraction.metrics.daysAboveTarget).toBe(1)
  })
  it('known exclusions do not require unrelated protocol, status or historical metadata', () => {
    const result = calculated(
      input([
        day(dates[0], { closed: false, protocol: null, rule: null }),
        day(dates[1], { hasRegistration: false, protocol: null, status: null, rule: null }),
        day(dates[2], {
          status: null,
          hasRegistration: null,
          rule: {
            phaseKey: 'old-phase',
            targetMatchesRule: false,
            adjustmentKcal: null,
            gainMultiplier: null,
          },
        }),
        day(dates[3]),
      ]),
    )
    expect(result.coverage?.includedDates).toEqual([dates[3]])
    expect(result.metrics.budgetTotalKcal).toBe(2600)
    expect(result.excludedDays).toEqual([
      { code: 'open', date: dates[0] },
      { code: 'no_registration', date: dates[1] },
      { code: 'different_phase', date: dates[2] },
    ])
  })
  it.each([
    [
      { phaseKey: 'phase-a', targetMatchesRule: false, adjustmentKcal: 0, gainMultiplier: null },
      'target_rule_mismatch',
    ],
    [
      { phaseKey: 'phase-a', targetMatchesRule: null, adjustmentKcal: 0, gainMultiplier: null },
      'target_rule_mismatch',
    ],
    [
      { phaseKey: null, targetMatchesRule: true, adjustmentKcal: 0, gainMultiplier: null },
      'unknown_phase',
    ],
    [null, 'missing_rule'],
  ] as const)('unproven target %j cannot exclude a candidate as below half (%s)', (rule, code) => {
    const result = withheld(
      input([day(dates[0], { targetKcal: 2600, consumedKcal: 1200, rule }), day(dates[1])]),
      'insufficient_data',
    )
    expect(result.issues).toContainEqual({ date: dates[0], code })
    expect(result.excludedDays).not.toContainEqual({ date: dates[0], code: 'below_half' })
    expect(result.coverage).toMatchObject({ countedDays: 1, dataComplete: false })
  })
  it('does not mutate frozen data and sums fractional consumption in date order', () => {
    const rows = [
      day(dates[0], { consumedKcal: 1e16 }),
      day(dates[1], { consumedKcal: 2601 }),
      day(dates[2], { consumedKcal: 2601 }),
    ]
    for (const row of rows) {
      Object.freeze(row.rule)
      Object.freeze(row)
    }
    Object.freeze(rows)
    const original = input(rows)
    Object.freeze(original.scope)
    Object.freeze(original.window)
    Object.freeze(original.policy)
    Object.freeze(original)
    const result = calculated(original)
    expect(result.metrics.consumedTotalKcal).toBe(1e16 + 2601 + 2601)
    expect(calculateDraftBudget14d(input([...rows].reverse()))).toEqual(result)
    expect(rows.map((row) => row.date)).toEqual(dates.slice(0, 3))
  })
})
