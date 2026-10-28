import { describe, expect, it } from 'vitest'
import { evaluateReevaluationProteinInputs } from './reevaluation-protein-inputs.js'

const table = {
  muita: 1.6,
  moderada: 1.8,
  pouca: 1.8,
  training_low: 1.7,
  optimal_mid_training: 1.9,
  optimal_high_training: 2,
}
const safety = {
  date: '2026-10-25',
  birthDate: '1990-01-01',
  heightCm: 180,
  weightKg: 80,
  bodyFatPercent: 18,
  hold: { active: false, items: [] },
}
const base = {
  phase: 'manutencao',
  profileHunger: 'moderada',
  profileSessions: 4,
  answeredHunger: 'muita',
  answeredSessions: 5,
  confirmedPrincipal: null,
  proteinFactors: table,
  recompProteinFactor: 1.5,
  safety,
}

describe('n11 — audit answers are not permission to move protein inputs', () => {
  it('declining a changed hunger branch preserves both original profile inputs', () => {
    const result = evaluateReevaluationProteinInputs(base)
    expect(result.status).toBe('confirmation_required')
    expect(result.beforeBranch).toBe('moderada')
    expect(result.candidateBranch).toBe('muita')
    expect(result.profile).toEqual({ hunger: 'moderada', sessions: 4 })
    expect(result.candidate).toEqual({ hunger: 'muita', sessions: 5 })
  })
  it.each([
    'activity',
    'phase',
  ] as const)('explicit %s package acceptance saves the declared inputs', (confirmedPrincipal) => {
    const result = evaluateReevaluationProteinInputs({ ...base, confirmedPrincipal })
    expect(result.status).toBe('confirmed')
    expect(result.profile).toEqual({ hunger: 'muita', sessions: 5 })
  })
  it('frequency crossing the low-training branch requires an accepted package', () => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      answeredHunger: null,
      answeredSessions: 2,
    })
    expect(result.status).toBe('confirmation_required')
    expect(result.profile).toEqual({ hunger: 'moderada', sessions: 4 })
    expect(result.candidateBranch).toBe('training_low')
  })
  it('same branch may save structured answers without an extra confirmation', () => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      answeredHunger: 'pouca',
      answeredSessions: 3,
    })
    expect(result.status).toBe('same_branch')
    expect(result.profile).toEqual({ hunger: 'pouca', sessions: 3 })
  })
  it('NULL hunger is calculation fallback only, never an invented saved Moderada', () => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      profileHunger: null,
      answeredHunger: null,
      answeredSessions: 5,
    })
    expect(result.status).toBe('same_branch')
    expect(result.profile).toEqual({ hunger: null, sessions: 5 })
  })
  it('no weight input exists: a new measured weight cannot masquerade as a changed branch', () => {
    expect(() => evaluateReevaluationProteinInputs({ ...base, weightKg: 84 })).toThrow()
  })
  it.each([
    null,
    {},
    { ...table, muita: 1.5 },
    { ...table, muita: '1.6' },
  ])('an unproven table cannot authorize a different branch (%j)', (proteinFactors) => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      confirmedPrincipal: 'activity',
      proteinFactors,
    })
    expect(result.status).toBe('unverified_table')
    expect(result.profile).toEqual({ hunger: 'moderada', sessions: 4 })
  })
  it('fixed recomposition is independent of hunger/frequency and of the cascade row', () => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      phase: 'recomposicao',
      proteinFactors: null,
    })
    expect(result.status).toBe('same_branch')
    expect(result.profile).toEqual({ hunger: 'muita', sessions: 5 })
    expect(result.beforeBranch).toBe('fixed_recomposition')
  })
  it.each([
    null,
    0,
  ])('recomposition fixed-factor off (%s) uses the actual cascade', (recompProteinFactor) => {
    expect(
      evaluateReevaluationProteinInputs({ ...base, phase: 'recomposicao', recompProteinFactor })
        .status,
    ).toBe('confirmation_required')
  })
  it.each([
    { ...safety, weightKg: 45 },
    { ...safety, bodyFatPercent: 10 },
    { ...safety, birthDate: '2012-01-01' },
    { ...safety, hold: { active: true, items: ['professional_diet'] } },
  ])('safety preserves inputs even when an activity/phase package was accepted (%j)', (safety) => {
    const result = evaluateReevaluationProteinInputs({
      ...base,
      safety,
      confirmedPrincipal: 'activity',
    })
    expect(result.status).toBe('safety')
    expect(result.profile).toEqual({ hunger: 'moderada', sessions: 4 })
  })
  it('missing answers preserve both original values', () => {
    expect(
      evaluateReevaluationProteinInputs({ ...base, answeredHunger: null, answeredSessions: null })
        .profile,
    ).toEqual({ hunger: 'moderada', sessions: 4 })
  })
})
