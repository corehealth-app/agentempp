import type { MealType } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { type FlowMealGapFacts, selectFlowMealGap } from './flow-meal-gap-policy.js'

const now = Date.parse('2026-11-26T21:00:00Z')
const meals: MealType[] = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia']
const facts: FlowMealGapFacts = {
  now,
  localHour: 18,
  optedIn: true,
  daytimeEnabled: true,
  dayClosed: false,
  patternReliable: true,
  expected: new Set(meals),
  registered: new Set(['cafe', 'almoco']),
  skipped: new Set(),
  personalEndHours: {},
  dayProteinGrams: 30,
  dayProteinTargetGrams: 100,
  lastMealLoggedAt: now - 4 * 3600000,
  lastIntakeAt: null,
  intakeProcessing: false,
  dailyLimit: 8,
  priorNotices: [],
}

describe('mobile meal gap reminder policy', () => {
  it('picks a missing meal whose normal window ended and skips future meals', () => {
    expect(selectFlowMealGap(facts)).toEqual({ mode: 'daytime', meal: 'lanche' })
    expect(
      selectFlowMealGap({ ...facts, registered: new Set(['cafe', 'almoco', 'lanche']) }),
    ).toBeNull()
    expect(selectFlowMealGap({ ...facts, skipped: new Set(['lanche']) })).toBeNull()
  })

  it('honors a later personal window for that meal', () => {
    expect(selectFlowMealGap({ ...facts, personalEndHours: { lanche: 18 } })).toBeNull()
    expect(
      selectFlowMealGap({ ...facts, localHour: 19, personalEndHours: { lanche: 18 } }),
    ).toEqual({ mode: 'daytime', meal: 'lanche' })
  })

  it('asks once before close, without depending on the optional daytime nudges', () => {
    const evening: FlowMealGapFacts = {
      ...facts,
      daytimeEnabled: false,
      localHour: 21,
      registered: new Set(['cafe', 'almoco', 'lanche']),
    }
    expect(selectFlowMealGap(evening)).toEqual({ mode: 'before_close', meal: 'jantar' })
    expect(
      selectFlowMealGap({
        ...evening,
        priorNotices: [{ mode: 'before_close', meal: 'lanche', at: now - 3600000 }],
      }),
    ).toBeNull()
    expect(selectFlowMealGap({ ...evening, personalEndHours: { jantar: 22 } })).toBeNull()
    expect(
      selectFlowMealGap({
        ...evening,
        localHour: 23,
        registered: new Set(['cafe', 'almoco', 'lanche', 'jantar']),
      }),
    ).toBeNull()
  })

  it.each([
    { optedIn: false },
    { daytimeEnabled: false },
    { dayClosed: true },
    { patternReliable: false },
    { intakeProcessing: true },
    { dailyLimit: 0 },
    { localHour: 20 },
    { lastIntakeAt: now - 3599000 },
    { dayProteinGrams: 60 },
    { dayProteinTargetGrams: null },
    { lastMealLoggedAt: now - 14399000 },
  ] satisfies Partial<FlowMealGapFacts>[])('suppresses daytime push for %o', (change) => {
    expect(selectFlowMealGap({ ...facts, ...change })).toBeNull()
  })

  it('enforces the cooldown, total limit and two daytime nudges per day', () => {
    expect(
      selectFlowMealGap({
        ...facts,
        priorNotices: [{ mode: 'daytime', meal: 'cafe', at: now - 3 * 3600000 }],
      }),
    ).toBeNull()
    expect(
      selectFlowMealGap({
        ...facts,
        dailyLimit: 1,
        priorNotices: [{ mode: 'daytime', meal: 'cafe', at: now - 5 * 3600000 }],
      }),
    ).toBeNull()
    expect(
      selectFlowMealGap({
        ...facts,
        priorNotices: [
          { mode: 'daytime', meal: 'cafe', at: now - 10 * 3600000 },
          { mode: 'daytime', meal: 'almoco', at: now - 5 * 3600000 },
        ],
      }),
    ).toBeNull()
  })
})
