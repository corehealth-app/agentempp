import { describe, expect, it } from 'vitest'
import { prepareClinicalDayClose } from './clinical-day-close-calculation'
import original from './testing/clinical-day-close-wire.json'

const scope = {
  userId: original.user_id,
  from: original.request.from,
  date: original.request.date as string | null,
  timezone: original.request.timezone,
}
const wire = () => structuredClone(original)
function required<T>(value: T | null | undefined): T {
  if (value == null) throw new Error('Fixture value missing')
  return value
}
function early(value: ReturnType<typeof wire>) {
  value.observed_at = '2026-10-26T03:40:00.000001Z'
  value.facts.current.observed_at = value.observed_at
  value.facts.current.safety.observed_at = value.observed_at
  value.facts.calendar.late = false
  return value
}
function held(value: ReturnType<typeof wire>, code = 'professional_diet') {
  Object.assign(value.facts.current.health_state, {
    safety_revision: '1',
    hold_active: true,
    hide_protein: code === 'professional_diet',
    declared_no_plan: code === 'pregnant_or_breastfeeding',
    last_declared_at: '2026-10-20T12:00:00.000001Z',
    items: [{ code, declared_at: '2026-10-20T12:00:00.000001Z' }],
  })
  Object.assign(value.facts.current.safety, {
    hold_active: true,
    hide_protein: true,
    no_plan: code === 'pregnant_or_breastfeeding',
  })
  return value
}
function effect(value: unknown) {
  const result = prepareClinicalDayClose(value, scope)
  if (result.kind !== 'apply' || result.effect.kind !== 'close')
    throw new Error('Expected close effect')
  return result.effect
}

describe('real pure core calculation from whole-close SQL facts', () => {
  it('preserves the historical targets before dawn instead of recalculating them with today inputs', () => {
    const e = effect(early(wire()))
    expect(e.fields.calories_target).toBe(2000)
    expect(e.fields.protein_target).toBe(130)
  })
  it('closes records and XP but preserves the block when the historical deficit is unproven', () => {
    const value = wire()
    Object.assign(value.facts.snapshot, { current_protocol: 'recomposicao' })
    Object.assign(value.facts.target_authority, { applied_target: null })
    Object.assign(value.facts, {
      progress: {
        xp_total: 90,
        level: 1,
        current_streak: 0,
        longest_streak: 0,
        blocks_completed: 1,
        deficit_block: 400,
        badges_earned: [],
        last_active_date: null,
      },
    })
    const e = effect(value)
    expect(e.fields.current_protocol).toBe('recomposicao')
    expect(e.fields.xp_earned).toBe(15)
    expect(e.blockCredit).toBe(0)
    expect(e.progress).toMatchObject({ xpTotal: 105, blocksCompleted: 1, deficitBlock: 400 })
  })
  it('preserves a recorded gain phase even while today profile is recomposition', () => {
    const value = wire()
    Object.assign(value.facts.snapshot, { current_protocol: 'ganho_massa' })
    Object.assign(value.facts.target_authority, { applied_target: null })
    const e = effect(value)
    expect(e.fields.current_protocol).toBe('ganho_massa')
    expect(e.blockCredit).toBe(0)
  })
  it('uses yesterday recomposition deficit400 even when today phase is maintenance', () => {
    const value = wire()
    Object.assign(value.facts.profile, { current_protocol: 'manutencao', deficit_level: null })
    Object.assign(value.facts.current.phase_origin, { phase: 'manutencao' })
    Object.assign(value.facts.target_authority.phase_origin, { phase: 'manutencao' })
    Object.assign(value.facts.target_authority.applied_target, { deficit_level: 400 })
    const e = effect(value)
    expect(e.fields.current_protocol).toBe('recomposicao')
    expect(e.fields.calories_target).toBe(2000)
    expect(e.blockCredit).toBe(800)
  })
  it('keeps the actual protein target after a protein-only correction without losing calorie authority', () => {
    const value = wire()
    Object.assign(value.facts.snapshot, { protein_target: 125 })
    const e = effect(value)
    expect(e.fields.protein_target).toBe(125)
    expect(e.blockCredit).toBe(900)
  })
  it('keeps known historical credit and the existing protein XP rule under an assigned HOLD', () => {
    const e = effect(held(wire()))
    expect(e.blockCredit).toBe(900)
    expect(e.fields.xp_earned).toBe(15)
  })
  it('does not assign today phase or deficit to a history row with no recorded phase', () => {
    const value = wire()
    Object.assign(value.facts.snapshot, { current_protocol: null })
    Object.assign(value.facts.target_authority, { applied_target: null })
    const e = effect(value)
    expect(e.fields.current_protocol).toBeNull()
    expect(e.blockCredit).toBe(0)
  })
  it.each([
    ['user_id', 'b3b01000-0000-4000-8000-000000009999'],
    ['signup_generation', 'b3b01000-0000-4000-8000-000000009999'],
    ['signup_epoch', 'b3b01000-0000-4000-8000-000000009999'],
    ['snapshot_id', 'b3b01000-0000-4000-8000-000000009999'],
    ['date', '2026-10-24'],
    ['phase', 'manutencao'],
    ['calories_target', 2001],
    ['recorded_at', '2026-10-26T03:00:00.000000Z'],
    ['deficit_level', 500.5],
  ])('rejects an unbound or later historical calorie origin %s', (key, value) => {
    const packet = wire()
    Object.assign(packet.facts.target_authority.applied_target, { [key]: value })
    expect(() => effect(packet)).toThrow()
  })
  it('retains stored late targets and applies the actual net credit formula, rather than the synthetic SQL payload', () => {
    const e = effect(wire())
    expect(e.fields).toMatchObject({
      calories_consumed: 1600,
      calories_target: 2000,
      protein_g: 100,
      protein_target: 130,
      xp_earned: 15,
    })
    expect(e.dailyBalance).toBe(-400)
    expect(e.blockCredit).toBe(900)
    expect(e.progress).toMatchObject({ xpTotal: 15, deficitBlock: 900, lastActiveDate: scope.date })
  })
  it('uses raw protein for XP and rounds dayFields independently', () => {
    const value = wire()
    required(value.facts.day_meals[0]).protein_g = 99.96
    const e = effect(value)
    expect(e.fields.protein_g).toBe(100)
    expect(e.fields.xp_earned).toBe(10)
  })
  it('applies the raw under-registration boundary before the rounded generated balance', () => {
    const value = wire()
    required(value.facts.day_meals[0]).kcal = 999.9
    const e = effect(value)
    expect(e.fields.calories_consumed).toBe(1000)
    expect(e.dailyBalance).toBe(-1000)
    expect(e.blockCredit).toBe(500)
    expect(e.telemetry).toContainEqual({
      event: 'bloco7700.skipped_subregistro',
      properties: {
        date: scope.date,
        day_status: 'complete',
        calories_consumed: 1000,
        calories_target: 2000,
        pct: 50,
      },
    })
  })
  it('shares the learned meal pattern for reminder gaps and explicit skips', () => {
    const value = wire()
    for (let n = 1; n <= 4; n++) {
      const id = `b3b01000-0000-4000-8000-${String(3500 + n).padStart(12, '0')}`
      value.facts.pattern_snapshots.push({ id, date: `2026-10-${25 - n}` })
      value.facts.pattern_meals.push({ id, snapshot_id: id, meal_type: 'almoco' })
    }
    for (const snapshot of value.facts.pattern_snapshots)
      value.facts.pattern_meals.push({
        id: snapshot.id,
        snapshot_id: snapshot.id,
        meal_type: 'cafe',
      })
    Object.assign(value.facts.snapshot, { gap_reminder_sent_at: '2026-10-25T20:00:00Z' })
    const incomplete = effect(value)
    expect(incomplete.dayStatus).toBe('incomplete_no_response')
    expect(incomplete.blockCredit).toBe(0)
    Object.assign(value.facts, {
      skip_events: [
        {
          id: 'b3b01000-0000-4000-8000-000000003599',
          occurred_at: '2026-10-25T20:00:00Z',
          properties: { local_date: scope.date, meal_type: 'cafe' },
        },
      ],
    })
    const skipped = effect(value)
    expect(skipped.dayStatus).toBe('user_skipped')
    expect(skipped.gap).toEqual([])
    expect(skipped.blockCredit).toBe(900)
  })
  it('does not use a changed current formula configuration to rewrite historical targets', () => {
    const value = early(wire())
    value.facts.current.calculation_config.push({
      key: 'calc.recomp_bmr_multiplier',
      value: 1.8,
      updated_at: value.observed_at,
    })
    const e = effect(value)
    expect(e.fields.calories_target).toBe(2000)
    expect(e.fields.protein_target).toBe(130)
    expect(e.progress.lastActiveDate).toBe('2026-10-25')
  })
  it('preserves an absent historical target independently of the stored protein field', () => {
    const value = wire()
    Object.assign(value.facts.snapshot, { calories_target: null })
    Object.assign(value.facts.target_authority, { applied_target: null })
    const e = effect(value)
    expect(e.fields.calories_target).toBeNull()
    expect(e.fields.protein_target).toBe(130)
  })
  it('preserves absent targets and existing XP under HOLD while unknown historical deficit preserves the block', () => {
    const value = held(early(wire()))
    Object.assign(value.facts.snapshot, { calories_target: null, protein_target: null })
    Object.assign(value.facts.target_authority, { applied_target: null })
    const e = effect(value)
    expect(e.fields.calories_target).toBeNull()
    expect(e.fields.protein_target).toBeNull()
    expect(e.fields.xp_earned).toBe(15)
    expect(e.blockCredit).toBe(0)
    expect(e.progress.deficitBlock).toBe(0)
  })
  it('does not authorize a fresh target from unproven reported body fat', () => {
    const value = early(wire())
    Object.assign(value.facts.profile, { body_fat_percent: 24 })
    Object.assign(value.facts.current.body, { body_fat_percent: 24 })
    Object.assign(value.facts.snapshot, { calories_target: null })
    Object.assign(value.facts.target_authority, { applied_target: null })
    expect(effect(value).fields.calories_target).toBeNull()
  })
  it('keeps a no-plan account recordable, preserving its block and stored fields independently', () => {
    const value = held(wire(), 'pregnant_or_breastfeeding')
    Object.assign(value.facts.profile, { current_protocol: null })
    const origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: value.facts.current.signup_generation,
      signupEpoch: value.facts.current.epoch,
      completedAt: value.facts.profile.onboarding_completed_at,
    }
    Object.assign(value.facts.current, { phase_origin: origin })
    Object.assign(value.facts.target_authority, { phase_origin: origin })
    Object.assign(value.facts, {
      progress: {
        xp_total: 90,
        level: 1,
        current_streak: 0,
        longest_streak: 0,
        blocks_completed: 1,
        deficit_block: 400,
        badges_earned: [],
        last_active_date: null,
      },
    })
    const e = effect(value)
    expect(e.fields.current_protocol).toBe('recomposicao')
    expect(e.fields.calories_target).toBe(2000)
    expect(e.blockCredit).toBe(0)
    expect(e.progress.blocksCompleted).toBe(1)
    expect(e.progress.deficitBlock).toBe(400)
    expect(e.fields.xp_earned).toBe(15)
  })
  it('reads fresh XP overrides and counts food rows rather than distinct meal categories', () => {
    const value = wire()
    value.facts.day_meals.push({
      ...required(value.facts.day_meals[0]),
      id: 'b3b01000-0000-4000-8000-000000003499',
    })
    Object.assign(
      required(value.facts.current.calculation_config.find((row) => row.key === 'calc.xp_rules')),
      {
        value: {
          base: 10,
          training_bonus: 5,
          protein_bonus: 5,
          protein_threshold_g: 100,
          meal_xp: 2,
          protein_meta_xp: 7,
        },
      },
    )
    expect(effect(value).fields.xp_earned).toBe(11)
  })
  it('returns typed no-effect skips before numeric calculation when the SQL disposition is not ready', () => {
    const value = wire()
    value.facts.disposition = 'earlier_date_changed'
    expect(prepareClinicalDayClose(value, scope)).toMatchObject({
      kind: 'skip',
      result: { closed: false, skipReason: 'earlier_date_changed' },
    })
  })
  it.each([
    (v: ReturnType<typeof wire>) => {
      v.user_id = 'b3b01000-0000-4000-8000-000000009999'
    },
    (v: ReturnType<typeof wire>) => {
      v.facts.calendar.today = '2026-10-27'
    },
    (v: ReturnType<typeof wire>) => {
      v.facts.snapshot.date = '2026-10-24'
    },
    (v: ReturnType<typeof wire>) => {
      v.facts.current.body.weight_kg = 99
    },
    (v: ReturnType<typeof wire>) => {
      required(v.facts.day_meals[0]).user_id = 'b3b01000-0000-4000-8000-000000009999'
    },
    (v: ReturnType<typeof wire>) => {
      required(v.facts.pattern_meals[0]).snapshot_id = 'b3b01000-0000-4000-8000-000000009999'
    },
    (v: ReturnType<typeof wire>) => {
      v.facts.calendar.current_day_end = '2026-10-26T00:00:00.000000Z'
    },
  ])('refuses inconsistent identity, date, membership or current profile binding', (patch) => {
    const value = wire()
    patch(value)
    expect(() => effect(value)).toThrow()
  })
})
