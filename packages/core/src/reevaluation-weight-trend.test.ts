import { describe, expect, it } from 'vitest'
import { evaluateReevaluationWeightHistory } from './reevaluation-weight-trend.js'

const date = '2026-10-28'
const asOf = '2026-10-28T23:59:59.999999Z'
let sequence = 0
function day(offset: number) {
  return new Date(Date.UTC(2026, 9, 28 + offset)).toISOString().slice(0, 10)
}
function entry(offset: number, weightHundredths: number, hour = '12', micro = '000000') {
  sequence++
  return {
    id: `aaaaaaaa-aaaa-4aaa-8aaa-${String(sequence).padStart(12, '0')}`,
    localDate: day(offset),
    measuredAt: `${day(offset)}T${hour}:00:00.${micro}Z`,
    weightHundredths,
  }
}
function weeks(values: number[]) {
  return values.flatMap((w, i) => [
    entry(-27 + i * 7, w),
    entry(-25 + i * 7, w),
    entry(-21 + i * 7, w),
  ])
}
const run = (measurements: unknown[]) =>
  evaluateReevaluationWeightHistory({ date, asOf, measurements })
describe('n4/n16/n19 exact individual weight windows', () => {
  it.each([
    [8039, 'stable', false],
    [8040, 'rising', false],
    [8080, 'rising', false],
    [8081, 'rising', true],
  ])('80kg -> %s hundredths classifies %s without rounding averages', (current, direction, aboveOnePercent) => {
    const value = run(weeks([8000, 8000, 8000, current as number]))
    expect(value.fortnight).toMatchObject({ status: 'known', direction, aboveOnePercent })
  })
  it.each([
    [7960, 'falling'],
    [7961, 'stable'],
    [8000, 'stable'],
  ])('fall boundary %s -> %s', (w, direction) => {
    expect(run(weeks([8000, 8000, 8000, w as number])).fortnight).toMatchObject({
      status: 'known',
      direction,
    })
  })
  it.each([
    [8040, false],
    [8041, true],
    [8000, false],
  ])('gain above0.5%% %s -> %s', (current, aboveHalfPercent) => {
    expect(run(weeks([8000, 8000, 8000, current as number])).fortnight).toMatchObject({
      status: 'known',
      aboveHalfPercent,
    })
  })
  it('unequal counts use sums multiplied by denominators, not totals', () => {
    const measurements = [
      entry(-13, 8000),
      entry(-11, 8000),
      entry(-7, 8000),
      entry(-6, 8040),
      entry(-5, 8040),
      entry(-4, 8040),
      entry(-2, 8040),
      entry(0, 8040),
    ]
    expect(run(measurements).fortnight).toMatchObject({
      status: 'known',
      direction: 'rising',
      aboveHalfPercent: false,
    })
  })
  it('three measurements of one day are one sample, never three days', () => {
    const value = run([
      entry(-8, 8000, '09'),
      entry(-8, 8000, '10'),
      entry(-8, 8000, '11'),
      entry(-5, 8040),
      entry(-3, 8040),
      entry(-1, 8040),
    ])
    expect(value.fortnight).toMatchObject({
      status: 'unknown',
      reason: 'insufficient_days',
      missingWeeks: [1],
    })
    expect(value.weeks[2]?.days).toBe(1)
  })
  it('uses latest measurement per local day, including microseconds, independent of input order', () => {
    const values = weeks([8000, 8000, 8000, 8040])
    values.push(entry(-6, 7000, '12', '000001'))
    const early = entry(-6, 9000, '11', '000000')
    values.push(early)
    const one = run(values)
    const two = run([...values].reverse())
    expect(one).toEqual(two)
    expect(one.weeks[3]?.sumHundredths).toBe(String(7000 + 8040 + 8040))
  })
  it('exact retries and different IDs at the same instant do not add days', () => {
    const values = weeks([8000, 8000, 8000, 8040])
    const last = values.at(-1)
    if (!last) throw new Error('Missing synthetic last measurement')
    const replay = run([
      ...values,
      { ...last },
      { ...last, id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' },
    ])
    expect(replay).toEqual(run(values))
  })
  it.each(['same_id', 'same_instant'])('conflicting %s evidence is unknown, not stable', (mode) => {
    const values = weeks([8000, 8000, 8000, 8040])
    const last = values.at(-1)
    if (!last) throw new Error('Missing synthetic last measurement')
    values.push({
      ...last,
      weightHundredths: 8050,
      ...(mode === 'same_instant' ? { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' } : {}),
    })
    expect(run(values).fortnight).toMatchObject({
      status: 'unknown',
      reason: 'conflicting_measurements',
    })
    expect(run(values).fourWeeks).toMatchObject({
      status: 'unknown',
      reason: 'conflicting_measurements',
    })
  })
  it('excludes out-of-window, future local dates and future instants', () => {
    const values = weeks([8000, 8000, 8000, 8040])
    const before = run(values)
    expect(
      run([
        ...values,
        entry(-28, 3000),
        entry(1, 30000),
        { ...entry(0, 3000), measuredAt: '2026-10-29T00:00:00.000000Z' },
      ]),
    ).toEqual(before)
  })
  it('includes both endpoints D-13,D-7,D-6,D and does not borrow days between weeks', () => {
    const values = [
      entry(-13, 8000),
      entry(-10, 8000),
      entry(-7, 8000),
      entry(-6, 8040),
      entry(-3, 8040),
      entry(0, 8040),
    ]
    expect(run(values).fortnight).toMatchObject({ status: 'known', direction: 'rising' })
  })
  it.each([
    [[8000, 8040, 8020, 8040], true],
    [[8000, 7970, 8000, 8020], false],
  ])('four-week stability checks all operative pairs %#', (weights, stable) => {
    expect(run(weeks(weights as number[])).fourWeeks).toMatchObject({ status: 'known', stable })
  })
  it('four weeks require3days in each; good recent weeks do not prove older stability', () => {
    const value = run(weeks([8000, 8000, 8000, 8040]).slice(6))
    expect(value.fourWeeks).toMatchObject({
      status: 'unknown',
      reason: 'insufficient_days',
      missingWeeks: [1, 2],
    })
    expect(value.fortnight.status).toBe('known')
  })
  it('does not mutate canonical entries or invent missing weeks', () => {
    const values = weeks([8000, 8000, 8000, 8040])
    const before = structuredClone(values)
    run(values)
    expect(values).toEqual(before)
    expect(run([]).fortnight).toMatchObject({ status: 'unknown', missingWeeks: [1, 2] })
  })
  it.each([
    { weightHundredths: 80.5 },
    { weightHundredths: NaN },
    { weightHundredths: 0 },
    { localDate: '2026-02-30' },
    { measuredAt: '2026-10-25T12:00:00Z' },
    { id: 'not-a-proof' },
  ])('rejects malformed canonical evidence %#', (patch) => {
    expect(() => run([{ ...entry(-1, 8000), ...patch }])).toThrow()
  })
})
