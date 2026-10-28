import { describe, expect, it } from 'vitest'
import {
  evaluateClinicalFirstPhase,
  projectClinicalFirstPhase,
} from './clinical-first-phase-calculation'
import wire from './testing/clinical-full-wire.json'

const owner = wire.context.user_id
function sample() {
  const raw = structuredClone(wire.context)
  Object.assign(raw, { review_kind: 'FIRST_PHASE', cycle_id: null })
  Object.assign(raw.facts.profile, {
    current_protocol: null,
    deficit_level: null,
    body_fat_percent: 18,
    body_fat_measured_at: null,
    weight_kg: 80,
    height_cm: 180,
    birth_date: '1990-01-01',
    hunger_level: 'moderada',
    activity_level: 'moderado',
    training_frequency: 4,
  })
  Object.assign(raw.facts, {
    day: null,
    first_phase: { effective_date: raw.facts.calculation_date },
    safety: { ...raw.facts.safety, hold_active: false, items: [] },
  })
  Object.assign(raw.facts.protocol_authority, {
    phase_origin: {
      kind: 'confirmed_no_plan',
      signupGeneration: raw.facts.anchor.signup_generation,
      signupEpoch: raw.facts.anchor.signup_epoch,
      completedAt: raw.facts.profile.onboarding_completed_at,
    },
    episode: null,
    signup_origin: null,
    target_origin: null,
    confirmed_calorie_decision: null,
    body_fat_origin: null,
    signup_body_fat_origin: null,
    body_fat_candidate: null,
  })
  return raw
}
describe('explicit later first phase (private dormant calculation)', () => {
  it('offers current eligible choices without pretending this is a signup or assigning a phase', () => {
    const raw = sample(),
      before = structuredClone(raw)
    const projected = projectClinicalFirstPhase(raw, owner)
    expect(projected).toMatchObject({ availability: 'available', missing: [], date: '2026-10-26' })
    expect(projected.options).toEqual([
      { phase: 'recomposicao', status: 'available', reasons: [] },
      { phase: 'ganho_massa', status: 'available', reasons: [] },
      { phase: 'manutencao', status: 'available', reasons: [] },
    ])
    expect(raw).toEqual(before)
    expect(raw.facts.profile.current_protocol).toBeNull()
  })
  it('above the composition cut offers only a recomposition candidate, still requiring confirmation', () => {
    const raw = sample()
    raw.facts.profile.body_fat_percent = 24
    expect(projectClinicalFirstPhase(raw, owner).options.map((v) => [v.phase, v.status])).toEqual([
      ['recomposicao', 'available'],
      ['ganho_massa', 'blocked'],
      ['manutencao', 'not_offered'],
    ])
    expect(() => evaluateClinicalFirstPhase(raw, owner, { phase: 'manutencao' })).toThrow(
      'First phase choice unavailable',
    )
    expect(raw.facts.profile.current_protocol).toBeNull()
  })
  it('uses current age and excludes the typed BF from the real calorie formula', () => {
    const raw = sample(),
      before = structuredClone(raw)
    const result = evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' })
    expect(result.package).toMatchObject({
      version: 1,
      phase: 'recomposicao',
      deficitLevel: 500,
      effectiveDate: '2026-10-26',
      targets: {
        beforeKcal: null,
        beforeProtein: null,
        afterKcal: 1600,
        afterProtein: 120,
        formulaAfterKcal: 1600,
      },
      formulaBodyFat: { origin: 'report', percent: null },
      episode: { difficultyCount: 0, ledgerSteps: null, schedule: null, maintenanceSince: null },
    })
    expect(raw).toEqual(before)
    expect(Object.isFrozen(result.package.targets)).toBe(true)
  })
  it.each([
    ['muita', 400, 1700],
    ['moderada', 500, 1600],
    ['pouca', 600, 1500],
  ])('binds the approved entry hunger %s to its explicit deficit', (hunger, deficit, calories) => {
    const raw = sample()
    Object.assign(raw.facts.profile, { hunger_level: hunger })
    expect(evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' }).package).toMatchObject(
      {
        deficitLevel: deficit,
        targets: { afterKcal: calories },
      },
    )
  })
  it('maintenance starts R only with an actually applicable current-day candidate', () => {
    const raw = sample()
    const value = evaluateClinicalFirstPhase(raw, owner, { phase: 'manutencao' })
    expect(value.package).toMatchObject({
      phase: 'manutencao',
      deficitLevel: null,
      targets: { afterKcal: 2713, afterProtein: 144 },
      episode: { ledgerSteps: [], maintenanceSince: '2026-10-26' },
    })
  })
  it('keeps a closed day intact and leaves R pending until the next real application', () => {
    const raw = sample()
    Object.assign(raw.facts, {
      day: {
        user_id: owner,
        date: '2026-10-26',
        calories_target: 1900,
        protein_target: 120,
        day_closed: true,
      },
      first_phase: { effective_date: '2026-10-27' },
    })
    const before = structuredClone(raw)
    expect(evaluateClinicalFirstPhase(raw, owner, { phase: 'manutencao' }).package).toMatchObject({
      effectiveDate: '2026-10-27',
      targets: { beforeKcal: 1900, beforeProtein: 120, afterKcal: 2713 },
      episode: { maintenanceSince: null },
    })
    expect(raw).toEqual(before)
  })
  it('uses BMI for the no-BF cut and never waives the independent gain BMI criterion', () => {
    const raw = sample()
    Object.assign(raw.facts.profile, { height_cm: 160, weight_kg: 64, body_fat_percent: null })
    expect(
      projectClinicalFirstPhase(raw, owner).options.find((v) => v.phase === 'manutencao')?.status,
    ).toBe('not_offered')
    Object.assign(raw.facts.profile, { body_fat_percent: 18 })
    const p = projectClinicalFirstPhase(raw, owner)
    expect(p.options.find((v) => v.phase === 'manutencao')?.status).toBe('available')
    expect(p.options.find((v) => v.phase === 'ganho_massa')).toMatchObject({
      status: 'blocked',
      reasons: ['gain_composition'],
    })
  })
  it.each([
    { weight_kg: 50 },
    { body_fat_percent: 10 },
    { birth_date: '2009-01-01' },
  ])('current safety wins before offering any first phase: %j', (patch) => {
    const raw = sample()
    Object.assign(raw.facts.profile, patch)
    expect(projectClinicalFirstPhase(raw, owner)).toMatchObject({
      availability: 'blocked',
      options: [],
    })
    expect(() => evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' })).toThrow(
      'First phase choice unavailable',
    )
  })
  it('a later declared risk blocks instead of treating the historical no-plan clear as permission', () => {
    const raw = sample()
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    expect(projectClinicalFirstPhase(raw, owner)).toMatchObject({
      availability: 'blocked',
      options: [],
    })
  })
  it('reports missing routine fields rather than inventing the entry deficit or protein branch', () => {
    const raw = sample()
    Object.assign(raw.facts.profile, { hunger_level: null })
    expect(projectClinicalFirstPhase(raw, owner)).toMatchObject({
      availability: 'incomplete',
      missing: ['hunger_level'],
      options: [],
    })
  })
  it('preserves incomplete physical data as a blocked projection with usable field names', () => {
    const raw = sample()
    Object.assign(raw.facts.profile, { birth_date: null })
    expect(projectClinicalFirstPhase(raw, owner)).toMatchObject({
      availability: 'blocked',
      missing: ['birth_date'],
      options: [],
    })
  })
  it('requires the official non-recomposition protein table', () => {
    const raw = sample()
    raw.facts.calculation_config = raw.facts.calculation_config.filter(
      (r) => r.key !== 'calc.protein_factors',
    )
    expect(() => evaluateClinicalFirstPhase(raw, owner, { phase: 'manutencao' })).toThrow(
      'First phase calculation unavailable',
    )
    expect(
      evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' }).package.targets
        .afterProtein,
    ).toBe(120)
  })
  it('uses a real bound signup photo source instead of relabelling a report', () => {
    const raw = sample()
    const proof = {
      user_id: owner,
      signup_generation: raw.facts.anchor.signup_generation,
      signup_epoch: raw.facts.anchor.signup_epoch,
      receipt_version: 1,
      onboarding_completed_at: raw.facts.profile.onboarding_completed_at,
      method: 'arithmetic_mean_v1',
      confirmed_body_fat_percent: 18,
      fingerprint: 'b'.repeat(64),
      decided_at: raw.observed_at,
    }
    Object.assign(raw.facts.protocol_authority, { signup_body_fat_origin: proof })
    expect(evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' }).package).toMatchObject(
      {
        formulaBodyFat: { origin: 'signup', percent: 18 },
        targets: { afterKcal: 1644 },
      },
    )
    Object.assign(proof, { signup_epoch: 'b3b01000-0000-4000-8000-000000009999' })
    expect(() => evaluateClinicalFirstPhase(raw, owner, { phase: 'recomposicao' })).toThrow(
      'Invalid first phase context',
    )
  })
  it.each([
    (r: ReturnType<typeof sample>) =>
      Object.assign(r, { user_id: 'b3b01000-0000-4000-8000-000000009999' }),
    (r: ReturnType<typeof sample>) => Object.assign(r, { review_kind: 'APPLICATION' }),
    (r: ReturnType<typeof sample>) =>
      Object.assign(r.facts.protocol_authority, { phase_origin: { kind: 'legacy_unassigned' } }),
    (r: ReturnType<typeof sample>) =>
      Object.assign(r.facts.profile, { current_protocol: 'manutencao' }),
    (r: ReturnType<typeof sample>) =>
      Object.assign(r.facts.protocol_authority, { signup_origin: {} }),
    (r: ReturnType<typeof sample>) =>
      Object.assign(r.facts, { first_phase: { effective_date: '2026-10-27' } }),
  ])('rejects wrong source, owner, phase, scope or civil application date', (mutate) => {
    const raw = sample()
    mutate(raw)
    expect(() => projectClinicalFirstPhase(raw, owner)).toThrow('Invalid first phase context')
  })
  it('has no client numerical override or automatic write intent', () => {
    expect(() =>
      evaluateClinicalFirstPhase(sample(), owner, { phase: 'recomposicao', calories: 1 }),
    ).toThrow()
  })
})
