import { describe, expect, it } from 'vitest'
import { readClinicalFullContext } from './clinical-full-authority'
import wire from './testing/clinical-full-wire.json'

const owner = wire.after.user_id
const scope = { userId: owner, kind: 'ROUTINE_REVIEW' as const, cycleId: null }
const other = 'b3b01000-0000-4000-8000-000000004151'
function sample() {
  return structuredClone(wire.after)
}
function origin() {
  return {
    user_id: owner,
    signup_generation: wire.after.facts.anchor.signup_generation,
    signup_epoch: wire.after.facts.anchor.signup_epoch,
    episode_id: other,
    phase: 'manutencao',
    started_at: '2026-10-01T03:00:00.000000Z',
    start_date: '2026-10-01',
    timezone_at_entry: 'America/Sao_Paulo',
    start_weight_kg: 80,
    start_height_cm: 180,
    start_body_fat_percent: 23.333333,
    start_training_frequency: 4,
    start_activity_level: 'moderado',
    deficit_level: null,
    maintenance_since: '2026-10-01',
    captured_at: '2026-10-01T03:00:00.000001Z',
    rule_version: 'clinical-v1',
  }
}

describe('private FULL capture authority', () => {
  it.each([
    'user_id',
    'signup_generation',
    'signup_epoch',
    'mean_hundredths',
  ])('refuses substituted available photo proof %s before using it', (field) => {
    const raw = structuredClone(wire.context)
    Object.assign(raw.facts.protocol_authority.body_fat_candidate, {
      [field]: field === 'mean_hundredths' ? 2401 : other,
    })
    expect(() =>
      readClinicalFullContext(raw, {
        userId: owner,
        kind: 'REGULAR',
        cycleId: raw.cycle_id,
      }),
    ).toThrow('Invalid clinical FULL authority')
  })
  it('reads actual SQL capture before and after a FULL without inventing legacy baselines', () => {
    const first = readClinicalFullContext(wire.context, {
      userId: owner,
      kind: 'REGULAR',
      cycleId: wire.context.cycle_id,
    })
    expect(first.facts.protocol_authority.episode).toBeNull()
    const current = readClinicalFullContext(sample(), scope)
    expect(current.facts.protocol_authority.episode).toMatchObject({
      entry_origin: 'legacy_unknown',
      entry_date: null,
      start_weight_kg: null,
      difficulty_count: '0',
      event_no: '1',
      deficit_level: 500,
    })
    expect(current.facts.weight_history[0]?.weight_kg).toBe(84)
    expect(current.facts.protocol_authority.prior_regular_reviews[0]?.form.answers.energy).toBe(
      'boa',
    )
  })
  it('detaches caller data and preserves an effective daily overlay without fabricating a FULL', () => {
    const raw = sample()
    const episode = raw.facts.protocol_authority.episode
    episode.applied_at = raw.observed_at
    const current = readClinicalFullContext(raw, scope)
    episode.deficit_level = 600
    expect(current.facts.protocol_authority.episode?.deficit_level).toBe(500)
    expect(current.facts.protocol_authority.episode?.review_id).toBe(wire.receipt.preview_id)
  })
  it('keeps a legacy unknown deficit nullable but never assigns that state to a proven episode', () => {
    const raw = sample()
    Object.assign(raw.facts.protocol_authority.episode, { deficit_level: null })
    expect(
      readClinicalFullContext(raw, scope).facts.protocol_authority.episode?.deficit_level,
    ).toBeNull()
    Object.assign(raw.facts.protocol_authority.episode, { entry_origin: 'signup' })
    expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
    Object.assign(raw.facts.protocol_authority.episode, { entry_origin: 'confirmed_phase_change' })
    expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
  })
  it('keeps counters above JS precision exact and refuses numeric, overflow and unsafe difficulty', () => {
    const raw = sample()
    raw.facts.protocol_authority.episode.event_no = '9223372036854775807'
    const prior = raw.facts.protocol_authority.prior_regular_reviews[0]
    if (!prior) throw new Error('Missing SQL fixture prior review')
    prior.review_no = '9007199254740993'
    expect(readClinicalFullContext(raw, scope).facts.protocol_authority.episode?.event_no).toBe(
      '9223372036854775807',
    )
    for (const value of [1, '9223372036854775808', '00', '-1']) {
      Object.assign(raw.facts.protocol_authority.episode, { event_no: value })
      expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
    }
    raw.facts.protocol_authority.episode.event_no = '1'
    raw.facts.protocol_authority.episode.difficulty_count = '9007199254740992'
    expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
  })
  it.each([
    'user_id',
    'signup_generation',
    'signup_epoch',
  ])('binds episode %s to captured owner and signup epoch', (field) => {
    const raw = sample()
    Object.assign(raw.facts.protocol_authority.episode, { [field]: other })
    expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
  })
  it('retains unscaled signup BF and a legitimate historical phase without using it as current', () => {
    const raw = sample()
    Object.assign(raw.facts.protocol_authority, { signup_origin: origin() })
    expect(
      readClinicalFullContext(raw, scope).facts.protocol_authority.signup_origin,
    ).toMatchObject({
      phase: 'manutencao',
      start_body_fat_percent: 23.333333,
    })
    Object.assign(raw.facts.protocol_authority, {
      signup_origin: { ...origin(), signup_epoch: other },
    })
    expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
  })
  it('requires observed signup chronology and maintenance R from the actual entry day', () => {
    const raw = sample()
    for (const bad of [
      { ...origin(), captured_at: '2026-09-30T03:00:00.000000Z' },
      { ...origin(), maintenance_since: '2026-10-02' },
      { ...origin(), phase: 'ganho_massa' },
    ]) {
      Object.assign(raw.facts.protocol_authority, { signup_origin: bad })
      expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
    }
  })
  it('matches the ledger absolute budget, not a cancelling signed sum', () => {
    const raw = sample()
    Object.assign(raw.facts.protocol_authority.episode, { ledger_steps: [100, -100] })
    expect(
      readClinicalFullContext(raw, scope).facts.protocol_authority.episode?.ledger_steps,
    ).toEqual([100, -100])
    for (const steps of [[150, -150], [0], [200, 1], [1.1]]) {
      Object.assign(raw.facts.protocol_authority.episode, { ledger_steps: steps })
      expect(() => readClinicalFullContext(raw, scope)).toThrow('Invalid clinical FULL authority')
    }
  })
  it('does not manufacture baselines for legacy episodes or accept missing/unknown authority fields', () => {
    const raw = sample()
    for (const patch of [{ start_weight_kg: 80 }, { unexpected: true }, { event_no: undefined }]) {
      const next = structuredClone(raw)
      Object.assign(next.facts.protocol_authority.episode, patch)
      expect(() => readClinicalFullContext(next, scope)).toThrow('Invalid clinical FULL authority')
    }
  })
  it('accepts future measured weight for core filtering, but refuses cross-owner/epoch and rounded precision', () => {
    const raw = sample()
    const weight = raw.facts.weight_history[0]
    if (!weight) throw new Error('Missing SQL fixture weight')
    const future = `${raw.observed_at.slice(0, 11)}23:59:59.000000Z`
    weight.measured_at = future
    weight.observed_timezone = 'Pacific/Honolulu'
    expect(readClinicalFullContext(raw, scope).facts.weight_history[0]?.measured_at).toBe(future)
    for (const patch of [{ user_id: other }, { authority_epoch: other }, { weight_kg: 84.001 }]) {
      const next = structuredClone(raw)
      const entry = next.facts.weight_history[0]
      if (!entry) throw new Error('Missing SQL fixture weight')
      Object.assign(entry, patch)
      expect(() => readClinicalFullContext(next, scope)).toThrow('Invalid clinical FULL authority')
    }
  })
  it('keeps no-plan explicit after health clear and requires absent clinical origins', () => {
    const raw = sample()
    const noPlanOrigin = {
      kind: 'confirmed_no_plan',
      signupGeneration: raw.facts.anchor.signup_generation,
      signupEpoch: raw.facts.anchor.signup_epoch,
      completedAt: raw.facts.profile.onboarding_completed_at,
    }
    Object.assign(raw, { review_kind: 'EARLY_FULL', cycle_id: other })
    Object.assign(raw.facts.profile, { current_protocol: null, deficit_level: null })
    Object.assign(raw.facts.protocol_authority, {
      phase_origin: noPlanOrigin,
      episode: null,
      signup_origin: null,
    })
    const requested = { userId: owner, kind: 'EARLY_FULL' as const, cycleId: other }
    expect(readClinicalFullContext(raw, requested).facts.profile.current_protocol).toBeNull()
    Object.assign(raw.facts.protocol_authority, { signup_origin: origin() })
    expect(() => readClinicalFullContext(raw, requested)).toThrow('Invalid clinical FULL authority')
  })
  it.each([
    { userId: other, kind: 'ROUTINE_REVIEW', cycleId: null },
    { userId: owner, kind: 'APPLICATION', cycleId: null },
    { userId: owner, kind: 'REGULAR', cycleId: other },
    { userId: owner, kind: 'ROUTINE_REVIEW', cycleId: other },
  ])('refuses scope substitution before any evaluator or writer', (requested) => {
    expect(() => readClinicalFullContext(sample(), requested)).toThrow(
      'Invalid clinical FULL authority',
    )
  })
})
