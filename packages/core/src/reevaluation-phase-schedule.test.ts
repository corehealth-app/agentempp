import { describe, expect, it } from 'vitest'
import {
  evaluateConfirmedActivityChange,
  evaluatePhaseSchedule,
  gainExitInvitation,
  planGainExit,
  planRecompositionTransition,
} from './reevaluation-phase-schedule.js'

const safety = {
  date: '2026-10-12',
  birthDate: '1990-01-01',
  heightCm: 180,
  weightKg: 80,
  bodyFatPercent: 18,
  hold: { active: false, items: [] },
}
function activity(overrides: Record<string, unknown> = {}) {
  return {
    phase: 'manutencao',
    safety,
    bmr: 1800,
    activityFactors: {
      sedentario: 1.2,
      leve: 1.375,
      moderado: 1.55,
      alto: 1.725,
      atleta: 1.9,
    },
    surplusMultiplier: 1.05,
    beforeLevel: 'moderado',
    confirmedLevel: 'alto',
    levelConfirmed: true,
    sessions: 4,
    profileSessions: 4,
    gainStartSessions: null,
    ledgerSteps: [-100],
    ...overrides,
  }
}
function planInput(overrides: Record<string, unknown> = {}) {
  return {
    date: '2026-10-12',
    safety,
    currentTargetKcal: 1950,
    maintenanceTargetKcal: 2200,
    activityLevelConfirmed: true,
    ...overrides,
  }
}
function apply(schedule: unknown, date: string, overrides: Record<string, unknown> = {}) {
  return evaluatePhaseSchedule({
    schedule,
    date,
    safety: { ...safety, date },
    currentTargetKcal: 2050,
    maintenanceTargetTodayKcal: 2200,
    ...overrides,
  })
}

describe('n3 confirmed level and frequency', () => {
  it('keeps frequency out of calories and uses the confirmed level plus existing signed net', () => {
    for (const sessions of [0, 2, 4, 7, null]) {
      expect(evaluateConfirmedActivityChange(activity({ sessions }))).toMatchObject({
        status: 'proposed',
        beforeKcal: 2690,
        afterKcal: 3005,
        activityChanged: true,
        sessionsToSave: sessions,
        suppressPhaseCalorieStep: true,
      })
    }
  })
  it('maintains the sedentary floor without silently clearing ledger steps', () => {
    expect(
      evaluateConfirmedActivityChange(
        activity({ beforeLevel: 'leve', confirmedLevel: 'sedentario', ledgerSteps: [-200] }),
      ),
    ).toMatchObject({ beforeKcal: 2275, afterKcal: 2160, ledgerNet: -200 })
  })
  it('uses the gain floor and actual signed net', () => {
    expect(
      evaluateConfirmedActivityChange(
        activity({ phase: 'ganho_massa', gainStartSessions: 4, ledgerSteps: [-200] }),
      ),
    ).toMatchObject({ beforeKcal: 2790, afterKcal: 3105 })
  })
  it.each([
    null,
    2,
    4,
  ])('refuses gain calorie increases with missing or below-baseline sessions %s', (sessions) => {
    expect(
      evaluateConfirmedActivityChange(
        activity({ phase: 'ganho_massa', gainStartSessions: 5, sessions }),
      ),
    ).toMatchObject({
      status: 'blocked',
      reason: 'gain_training_baseline',
      afterKcal: null,
      sessionsToSave: null,
    })
  })
  it('uses the higher profile/start baseline, not just the initial frequency', () => {
    expect(
      evaluateConfirmedActivityChange(
        activity({ phase: 'ganho_massa', gainStartSessions: 3, profileSessions: 6, sessions: 5 }),
      ),
    ).toMatchObject({ status: 'blocked', reason: 'gain_training_baseline' })
  })
  it('allows a gain decrease with fewer sessions and warns below three without a per-session penalty', () => {
    expect(
      evaluateConfirmedActivityChange(
        activity({
          phase: 'ganho_massa',
          beforeLevel: 'alto',
          confirmedLevel: 'leve',
          gainStartSessions: 5,
          sessions: 2,
        }),
      ),
    ).toMatchObject({
      status: 'proposed',
      beforeKcal: 3160,
      afterKcal: 2499,
      lowStrengthNotice: true,
    })
  })
  it('does not save a preselected, unconfirmed level or infer it from exercise context', () => {
    expect(evaluateConfirmedActivityChange(activity({ levelConfirmed: false }))).toMatchObject({
      status: 'missing',
      reason: 'unconfirmed_activity',
      afterKcal: null,
      sessionsToSave: null,
    })
  })
  it('same level keeps calorie steps eligible; sessions can still affect a protein branch', () => {
    expect(
      evaluateConfirmedActivityChange(activity({ confirmedLevel: 'moderado', sessions: 5 })),
    ).toMatchObject({
      activityChanged: false,
      suppressPhaseCalorieStep: false,
      beforeKcal: 2690,
      afterKcal: 2690,
      sessionsToSave: 5,
    })
  })
  it('recomposition does not derive calories from level, and does not suppress n2', () => {
    expect(evaluateConfirmedActivityChange(activity({ phase: 'recomposicao' }))).toMatchObject({
      beforeKcal: null,
      afterKcal: null,
      activityChanged: true,
      suppressPhaseCalorieStep: false,
    })
  })
  it.each([
    { ...safety, bodyFatPercent: 10 },
    { ...safety, weightKg: 50, heightCm: 180 },
    { ...safety, hold: { active: true, items: ['reduced_intake'] } },
    { ...safety, birthDate: '2010-01-01' },
  ])('safety blocks saving both level and sessions', (paused) => {
    expect(evaluateConfirmedActivityChange(activity({ safety: paused }))).toMatchObject({
      status: 'blocked',
      reason: 'safety',
      afterKcal: null,
      sessionsToSave: null,
    })
  })
  it('cannot reuse a ledger whose absolute movements already exceed the episode cap', () => {
    expect(() => evaluateConfirmedActivityChange(activity({ ledgerSteps: [150, -150] }))).toThrow()
  })
})

describe('n5/n18 confirmed weekly schedule arithmetic (no persistence authority)', () => {
  it('dates n5 values from confirmation and reaches R at the actually applied maintenance target', () => {
    const schedule = planRecompositionTransition(planInput())
    expect(schedule).toMatchObject({
      kind: 'recomp_to_maintenance',
      startDate: '2026-10-12',
      plannedEndDate: '2026-10-26',
    })
    expect(apply(schedule, '2026-10-12')).toMatchObject({
      targetKcal: 2050,
      phase: 'manutencao',
      reachedMaintenance: false,
    })
    expect(apply(schedule, '2026-10-18')).toMatchObject({
      targetKcal: 2050,
      reachedMaintenance: false,
    })
    expect(apply(schedule, '2026-10-19')).toMatchObject({
      targetKcal: 2150,
      reachedMaintenance: false,
    })
    expect(apply(schedule, '2026-10-26')).toMatchObject({
      targetKcal: 2200,
      reachedMaintenance: true,
      maintenanceSinceCandidate: '2026-10-26',
    })
  })
  it('does not manufacture a retrospective R when the final step was not actually applied on its planned date', () => {
    const schedule = planRecompositionTransition(planInput())
    expect(apply(schedule, '2026-10-29')).toMatchObject({
      targetKcal: 2200,
      maintenanceSinceCandidate: '2026-10-29',
    })
  })
  it('n5 caps each frozen value at today’s recalculated target but never extends for a higher target', () => {
    const schedule = planRecompositionTransition(planInput())
    expect(apply(schedule, '2026-10-12', { maintenanceTargetTodayKcal: 2000 })).toMatchObject({
      targetKcal: 2000,
      reachedMaintenance: true,
    })
    expect(apply(schedule, '2026-11-30', { maintenanceTargetTodayKcal: 2400 })).toMatchObject({
      targetKcal: 2200,
      reachedMaintenance: false,
      needsNewConfirmation: true,
      maintenanceSinceCandidate: null,
    })
  })
  it('keeps n18 G/M/E frozen, first step on E and gain phase until M is reached', () => {
    const schedule = planGainExit(
      planInput({ currentTargetKcal: 2500, maintenanceTargetKcal: 2350 }),
    )
    expect(schedule.plannedEndDate).toBe('2026-10-19')
    expect(apply(schedule, '2026-10-12', { maintenanceTargetTodayKcal: 2400 })).toMatchObject({
      targetKcal: 2400,
      phase: 'ganho_massa',
      reachedMaintenance: false,
    })
    expect(apply(schedule, '2026-10-19', { maintenanceTargetTodayKcal: 2400 })).toMatchObject({
      targetKcal: 2350,
      phase: 'manutencao',
      reachedMaintenance: true,
      maintenanceSinceCandidate: '2026-10-19',
    })
  })
  it.each([
    2300, 2350,
  ])('G <= M (%s) reaches maintenance on E without a ramp', (currentTargetKcal) => {
    const schedule = planGainExit(planInput({ currentTargetKcal, maintenanceTargetKcal: 2350 }))
    expect(apply(schedule, '2026-10-12')).toMatchObject({
      targetKcal: 2350,
      phase: 'manutencao',
      maintenanceSinceCandidate: '2026-10-12',
    })
  })
  it.each([
    'recomp',
    'gain',
  ])('stops the %s schedule at current target under a guard, never resumes itself', (kind) => {
    const schedule =
      kind === 'recomp'
        ? planRecompositionTransition(planInput())
        : planGainExit(planInput({ currentTargetKcal: 2500, maintenanceTargetKcal: 2350 }))
    const paused = apply(schedule, '2026-10-19', {
      safety: { ...safety, date: '2026-10-19', bodyFatPercent: 10 },
      currentTargetKcal: 2100,
    })
    expect(paused).toMatchObject({
      targetKcal: 2100,
      state: 'suspended',
      reachedMaintenance: false,
      maintenanceSinceCandidate: null,
    })
    expect(
      apply({ ...schedule, state: paused.state }, '2026-10-26', { currentTargetKcal: 2100 }),
    ).toMatchObject({ targetKcal: 2100, state: 'suspended', reason: 'confirmation_required' })
  })
  it('neither starts a schedule with unconfirmed activity nor bypasses an active HOLD', () => {
    expect(() => planGainExit(planInput({ activityLevelConfirmed: false }))).toThrow()
    expect(() =>
      planRecompositionTransition(
        planInput({ safety: { ...safety, hold: { active: true, items: ['reduced_intake'] } } }),
      ),
    ).toThrow()
  })
  it('refuses a malformed or mutable schedule payload', () => {
    const schedule = planRecompositionTransition(planInput())
    expect(() => apply({ ...schedule, plannedEndDate: '2026-10-19' }, '2026-10-12')).toThrow()
    expect(() => apply({ ...schedule, hiddenSteps: [3000] }, '2026-10-12')).toThrow()
    expect(() => apply(schedule, '2026-10-11')).toThrow()
    expect(() =>
      apply(schedule, '2026-10-12', { safety: { ...safety, date: '2026-10-13' } }),
    ).toThrow()
  })
  it('leaves its input unmodified', () => {
    const schedule = planGainExit(
      planInput({ currentTargetKcal: 2500, maintenanceTargetKcal: 2350 }),
    )
    const original = structuredClone(schedule)
    apply(schedule, '2026-10-26')
    expect(schedule).toEqual(original)
  })
})

describe('n18 invitations use completed civil weeks and never end a phase', () => {
  it.each([
    ['2026-11-29', false, false, 7],
    ['2026-11-30', true, false, 8],
    ['2027-01-24', true, false, 15],
    ['2027-01-25', true, true, 16],
  ])('%s has the correct week boundary', (date, offer, reinforce, week) => {
    expect(
      gainExitInvitation({ startDate: '2026-10-12', date, limitActive: false, requested: false }),
    ).toEqual({ offer, reinforce, week })
  })
  it('allows a requested exit under a limit before week eight', () => {
    expect(
      gainExitInvitation({
        startDate: '2026-10-12',
        date: '2026-10-19',
        limitActive: true,
        requested: true,
      }),
    ).toEqual({ offer: true, reinforce: false, week: 2 })
  })
})
