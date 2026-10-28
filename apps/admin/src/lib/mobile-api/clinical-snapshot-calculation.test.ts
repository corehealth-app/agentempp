import { calcBMR, computeDailyTargetsOnCivilDate, DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { calculateClinicalSnapshotTargets } from './clinical-snapshot-calculation'

const owner = 'b3b01000-0000-4000-8000-000000001900'
const generation = 'b3b01000-0000-4000-8000-000000001901'
const epoch = 'b3b01000-0000-4000-8000-000000001902'
const cycle = 'b3b01000-0000-4000-8000-000000001903'
const at = '2026-10-25T12:00:00.123456Z'
const table = {
  muita: 1.6,
  moderada: 1.8,
  pouca: 1.8,
  training_low: 1.7,
  optimal_mid_training: 1.9,
  optimal_high_training: 2,
}
function proteinForm() {
  return {
    version: 1,
    phase: 'manutencao',
    kind: 'EARLY_FULL',
    activityPurpose: 'normal',
    preference: null,
    answers: {
      weightKg: null,
      strengthSessions: 5,
      hunger: 'muita',
      adherence: null,
      energy: null,
      strengthProgression: null,
      fatPerception: null,
      difficultToMaintain: null,
      activity: null,
      healthCheck: { kind: 'none' },
      professionalConversationConfirmed: null,
    },
  }
}
function snapshot() {
  return {
    version: 1,
    user_id: owner,
    review_kind: 'APPLICATION',
    cycle_id: null,
    observed_at: at,
    valid_until: '2026-10-26T03:00:00.000000Z',
    context_hash: 'a'.repeat(64),
    facts: {
      owner: { id: owner, status: 'active', locale: 'pt-BR', timezone: 'America/Sao_Paulo' },
      anchor: {
        signup_generation: generation,
        signup_epoch: epoch,
        authority: {
          kind: 'signup_receipt',
          generation,
          epoch,
          completed_at: '2026-10-01T03:00:00.000000Z',
          timezone_at_signup: 'America/Sao_Paulo',
        },
      },
      calculation_date: '2026-10-25',
      profile: {
        user_id: owner,
        sex: 'masculino',
        birth_date: '1982-11-01',
        height_cm: 180,
        weight_kg: 81,
        body_fat_percent: null as number | null,
        body_fat_measured_at: null as string | null,
        onboarding_completed: true,
        onboarding_completed_at: '2026-10-01T03:00:00.000000Z',
        current_protocol: 'recomposicao',
        deficit_level: 500,
        activity_level: 'leve',
        training_frequency: 4,
        hunger_level: 'moderada',
        water_intake: null,
        goal_type: 'BF',
        goal_value: 10,
      },
      day: null as null | {
        user_id: string
        date: string
        calories_target: number
        protein_target: number
        day_closed: boolean
      },
      calculation_config: [
        { key: 'calc.protein_factors', value: table as unknown, updated_at: at },
      ],
      protocol_authority: {
        body_fat_origin: null as unknown,
        signup_body_fat_origin: null as unknown,
        body_fat_candidate: null as unknown,
      },
      safety: { user_id: owner, hold_active: false, items: [] },
    },
  }
}
function signupProof(s: ReturnType<typeof snapshot>) {
  s.facts.profile.body_fat_percent = 24
  s.facts.protocol_authority.signup_body_fat_origin = {
    user_id: owner,
    signup_generation: generation,
    signup_epoch: epoch,
    receipt_version: 1,
    onboarding_completed_at: s.facts.profile.onboarding_completed_at,
    method: 'arithmetic_mean_v1',
    confirmed_body_fat_percent: 24,
    fingerprint: 'b'.repeat(64),
    decided_at: at,
  }
}

describe('server clinical snapshot calculations (dormant)', () => {
  it('admits a genuine assigned signup for its first APPLICATION without inventing a FULL or old formula proof', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 24
    const origin = {
      user_id: owner,
      signup_generation: generation,
      signup_epoch: epoch,
      episode_id: cycle,
      phase: 'recomposicao',
      started_at: s.facts.profile.onboarding_completed_at,
      start_date: '2026-10-01',
      timezone_at_entry: 'America/Sao_Paulo',
      start_weight_kg: 81,
      start_height_cm: 180,
      start_body_fat_percent: 24,
      start_training_frequency: 4,
      start_activity_level: 'leve',
      deficit_level: 500,
      maintenance_since: null,
      captured_at: s.facts.profile.onboarding_completed_at,
      rule_version: 'clinical-v1',
    }
    const raw = {
      ...s,
      facts: {
        ...s.facts,
        protocol_authority: {
          ...s.facts.protocol_authority,
          phase_origin: { kind: 'assigned' },
          episode: null,
          signup_origin: origin,
        },
      },
    }
    const first = calculateClinicalSnapshotTargets(raw, owner)
    expect(first.automaticCalculationReady).toBe(true)
    expect(first.formulaBodyFatPercent).toBeNull()
    expect(first.bodyFat.kind).toBe('manual_report')
    for (const [field, value] of [
      ['user_id', cycle],
      ['signup_generation', cycle],
      ['signup_epoch', cycle],
      ['started_at', '2026-10-02T03:00:00.000000Z'],
      ['phase', 'manutencao'],
      ['deficit_level', 400],
      ['captured_at', '2026-10-27T00:00:00.000000Z'],
    ] as const) {
      const wrong = structuredClone(raw)
      Object.assign(wrong.facts.protocol_authority.signup_origin, { [field]: value })
      expect(() => calculateClinicalSnapshotTargets(wrong, owner)).toThrow(
        'Invalid clinical calculation context',
      )
    }
    const stored = {
      ...raw,
      facts: {
        ...raw.facts,
        day: {
          user_id: owner,
          date: '2026-10-25',
          calories_target: 1099,
          protein_target: 120,
          day_closed: false,
        },
      },
    }
    expect(calculateClinicalSnapshotTargets(stored, owner).automaticCalculationReady).toBe(false)
    expect(calculateClinicalSnapshotTargets(stored, owner).legacyTarget.action).toBe('preserve')
  })
  it('does not run a target formula for a captured confirmed no-plan origin, even after clear', () => {
    const s = snapshot()
    const raw = {
      ...s,
      facts: {
        ...s.facts,
        profile: { ...s.facts.profile, current_protocol: null, deficit_level: null },
        protocol_authority: {
          ...s.facts.protocol_authority,
          phase_origin: {
            kind: 'confirmed_no_plan',
            signupGeneration: generation,
            signupEpoch: epoch,
            completedAt: s.facts.profile.onboarding_completed_at,
          },
        },
      },
    }
    expect(() => calculateClinicalSnapshotTargets(raw, owner)).toThrow(
      'Invalid clinical calculation context',
    )
  })
  it('keeps legacy unassigned phase distinct from genuine no-plan', () => {
    const s = snapshot()
    const raw = {
      ...s,
      facts: {
        ...s.facts,
        profile: { ...s.facts.profile, current_protocol: null, deficit_level: null },
        protocol_authority: {
          ...s.facts.protocol_authority,
          phase_origin: { kind: 'legacy_unassigned' },
        },
      },
    }
    expect(calculateClinicalSnapshotTargets(raw, owner).formulaKcal).toBe(
      calculateClinicalSnapshotTargets(
        { ...raw, facts: { ...raw.facts, protocol_authority: s.facts.protocol_authority } },
        owner,
      ).formulaKcal,
    )
  })
  it('uses the real shared formula and the captured civil birthday, never the host date', () => {
    const s = snapshot()
    const result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.formulaKcal).toBe(1570)
    expect(result.proteinTarget).toBe(121.5)
    expect(result.bmr).toBe(calcBMR({ sex: 'masculino', weightKg: 81, heightCm: 180, age: 43 }))
    expect(result.formulaKcal).toBe(
      computeDailyTargetsOnCivilDate(
        {
          ...s.facts.profile,
          sex: 'masculino',
          activity_level: 'leve',
          current_protocol: 'recomposicao',
          deficit_level: 500,
          hunger_level: 'moderada',
          goal_type: 'BF',
          water_intake: null,
        },
        { ...DEFAULT_CALC_CONFIG, protein_factors: table },
        '2026-10-25',
      ).calories_target,
    )
  })
  it.each([
    12, 22, 45,
  ])('excludes the unproven %s%% report from BMR but retains it for guards', (bf) => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = bf
    const result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.formulaKcal).toBe(1570)
    expect(result.bodyFat.kind).toBe('manual_report')
    expect(result.safety.bodyFatPercent).toBe(bf)
    expect(result.formulaBodyFatPercent).toBeNull()
  })
  it('accepts only bound numeric signup photo proof; no baseline label establishes provenance', () => {
    const s = snapshot()
    signupProof(s)
    expect(calculateClinicalSnapshotTargets(s, owner).formulaBodyFatPercent).toBe(24)
    s.facts.protocol_authority.signup_body_fat_origin = null
    Object.assign(s.facts.protocol_authority, { signup_origin: { start_body_fat_percent: 24 } })
    // Signup is now consumed as entry authority, so a baseline label alone
    // must fail validation rather than being mistaken for a genuine receipt.
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow(
      'Invalid clinical calculation context',
    )
  })
  it.each([
    'user_id',
    'signup_generation',
    'signup_epoch',
    'onboarding_completed_at',
  ])('rejects a mismatched signup proof %s', (key) => {
    const s = snapshot()
    signupProof(s)
    const proof = s.facts.protocol_authority.signup_body_fat_origin as Record<string, unknown>
    proof[key] = key === 'onboarding_completed_at' ? '2026-10-02T03:00:00.000000Z' : cycle
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow(
      'Invalid clinical calculation context',
    )
  })
  it('binds recurring numeric proof to the current profile instant and generation', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 24
    s.facts.profile.body_fat_measured_at = at
    s.facts.protocol_authority.body_fat_origin = {
      user_id: owner,
      signup_generation: generation,
      signup_epoch: epoch,
      mean_percent: 24,
      confirmed_at: at,
      source_hash: 'c'.repeat(64),
    }
    expect(calculateClinicalSnapshotTargets(s, owner).bodyFat.origin).toBe('recurring')
    s.facts.profile.body_fat_measured_at = '2026-10-25T12:00:00.123457Z'
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow(
      'Invalid clinical calculation context',
    )
  })
  it('uses only the SQL-bound future mean for a REGULAR proposal, not a free client number', () => {
    const s = snapshot()
    Object.assign(s, { review_kind: 'REGULAR', cycle_id: cycle })
    s.facts.protocol_authority.body_fat_candidate = {
      version: 1,
      availability: 'available',
      user_id: owner,
      signup_generation: generation,
      signup_epoch: epoch,
      cycle_id: cycle,
      mean_percent: 24,
      mean_hundredths: 2400,
      source_hash: 'd'.repeat(64),
    }
    const choice = { bodyFatCandidate: { sourceHash: 'd'.repeat(64), meanHundredths: 2400 } }
    const result = calculateClinicalSnapshotTargets(s, owner, choice)
    expect(result.formulaBodyFatPercent).toBe(24)
    expect(result.bodyFat.origin).toBe('regular_candidate')
    expect(result.requiresBodyFatConfirmation).toBe(true)
    expect(() =>
      calculateClinicalSnapshotTargets(s, owner, {
        bodyFatCandidate: { ...choice.bodyFatCandidate, meanHundredths: 2300 },
      }),
    ).toThrow()
    expect(() => calculateClinicalSnapshotTargets(s, owner, { formulaKcal: 900 })).toThrow()
  })
  it.each([
    ['muita', 5, 129.6],
    ['moderada', 2, 137.7],
    ['pouca', 5, 162],
    ['pouca', 4, 153.9],
    ['moderada', 4, 145.8],
    [null, 4, 145.8],
  ])('uses captured n11 table for %s and %s sessions', (hunger, sessions, protein) => {
    const s = snapshot()
    Object.assign(s.facts.profile, {
      current_protocol: 'manutencao',
      deficit_level: null,
      hunger_level: hunger,
      training_frequency: sessions,
    })
    expect(calculateClinicalSnapshotTargets(s, owner).proteinTarget).toBe(protein)
  })
  it('does not silently use unaccepted hunger/frequency answers to calculate the approved target', () => {
    const s = snapshot()
    Object.assign(s, { review_kind: 'EARLY_FULL' })
    Object.assign(s.facts.profile, { current_protocol: 'manutencao', deficit_level: null })
    expect(calculateClinicalSnapshotTargets(s, owner, { form: proteinForm() }).proteinTarget).toBe(
      145.8,
    )
  })
  it('can explicitly project candidate protein inputs without confusing them with approval', () => {
    const s = snapshot()
    Object.assign(s, { review_kind: 'EARLY_FULL' })
    Object.assign(s.facts.profile, { current_protocol: 'manutencao', deficit_level: null })
    expect(
      calculateClinicalSnapshotTargets(s, owner, {
        form: proteinForm(),
        proteinInputSource: 'answers',
      }).proteinTarget,
    ).toBe(129.6)
  })
  it('does not pretend that the 1.5 code fallback proves the approved cascade', () => {
    const s = snapshot()
    s.facts.calculation_config = []
    Object.assign(s.facts.profile, { current_protocol: 'manutencao', deficit_level: null })
    const result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.proteinAuthority).toBe('unverified_table')
    expect(result.proteinTarget).toBeNull()
    expect(result.automaticCalculationReady).toBe(false)
    s.facts.profile.current_protocol = 'recomposicao'
    s.facts.profile.deficit_level = 500
    expect(calculateClinicalSnapshotTargets(s, owner).proteinTarget).toBe(121.5)
  })
  it('reads whole config rows without cache, coercion or a partial object merge', () => {
    const s = snapshot()
    s.facts.calculation_config.push({
      key: 'calc.activity_factors',
      value: { leve: 2 },
      updated_at: at,
    })
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow()
    s.facts.calculation_config.pop()
    s.facts.calculation_config.push({
      key: 'calc.recomp_bmr_multiplier',
      value: '1.2',
      updated_at: at,
    })
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow()
  })
  it('preserves the existing fixed-protein compatibility switch and invalid-value fallback', () => {
    const s = snapshot()
    s.facts.calculation_config.push({
      key: 'calc.recomp_protein_g_per_kg',
      value: 0,
      updated_at: at,
    })
    expect(calculateClinicalSnapshotTargets(s, owner).proteinTarget).toBe(145.8)
    const override = s.facts.calculation_config.at(-1)
    if (!override) throw new Error('Fixture override missing')
    override.value = 'bad'
    expect(calculateClinicalSnapshotTargets(s, owner).proteinTarget).toBe(121.5)
  })
  it('preserves an unknown old source until a new confirmed assessment, without a correction offer', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 45
    s.facts.day = {
      user_id: owner,
      date: '2026-10-25',
      calories_target: 1099,
      protein_target: 121.5,
      day_closed: false,
    }
    let result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.storedTargets?.calories_target).toBe(1099)
    expect(result.legacyTarget.action).toBe('preserve')
    expect(result.legacyTarget.candidateKcal).toBeNull()
    expect(result.automaticCalculationReady).toBe(false)
    s.facts.day.calories_target = 1792
    result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.legacyTarget.action).toBe('preserve')
    expect(result.legacyTarget.candidateKcal).toBeNull()
  })
  it('distinguishes a new applied clinical target from an old unknown source after a typed report', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 45
    const raw = {
      ...s,
      facts: {
        ...s.facts,
        day: {
          id: cycle,
          user_id: owner,
          date: '2026-10-25',
          calories_target: 1564,
          protein_target: 121.5,
          current_protocol: 'recomposicao',
          day_closed: false,
        },
        protocol_authority: {
          ...s.facts.protocol_authority,
          target_origin: {
            version: 1,
            source: 'clinical_full_v1',
            target_component: 'calories',
            origin_id: generation,
            user_id: owner,
            signup_generation: generation,
            signup_epoch: epoch,
            snapshot_id: cycle,
            date: '2026-10-25',
            phase: 'recomposicao',
            calories_target: 1564,
            protein_target: 121.5,
            formula_target: 1564,
            review_id: epoch,
            context_hash: 'd'.repeat(64),
            recorded_at: at,
          },
        },
      },
    }
    const result = calculateClinicalSnapshotTargets(raw, owner)
    expect(result.formulaBodyFatPercent).toBeNull()
    expect(result.bodyFat.kind).toBe('manual_report')
    expect(result.legacyTarget.origin).toBe('not_applicable')
    expect(result.automaticCalculationReady).toBe(true)
    // Every consumed binding must agree. A source for another snapshot,
    // owner, admission, epoch, day or target cannot lift the legacy fence.
    for (const [key, value] of [
      ['user_id', cycle],
      ['signup_generation', cycle],
      ['signup_epoch', cycle],
      ['snapshot_id', epoch],
      ['date', '2026-10-24'],
      ['phase', 'manutencao'],
      ['calories_target', 1565],
      ['recorded_at', '2026-10-27T00:00:00.000000Z'],
    ] as const) {
      const wrong = structuredClone(raw)
      Object.assign(wrong.facts.protocol_authority.target_origin, { [key]: value })
      expect(() => calculateClinicalSnapshotTargets(wrong, owner)).toThrow(
        'Invalid clinical calculation context',
      )
    }
    const proteinChanged = structuredClone(raw)
    proteinChanged.facts.day.protein_target = 125
    expect(calculateClinicalSnapshotTargets(proteinChanged, owner).automaticCalculationReady).toBe(
      true,
    )
    expect(
      calculateClinicalSnapshotTargets(proteinChanged, owner).storedTargets?.protein_target,
    ).toBe(125)
  })
  it('does not offer a new automatic target under a low-fat guard or a HOLD', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 10
    expect(calculateClinicalSnapshotTargets(s, owner).automaticCalculationReady).toBe(false)
    s.facts.profile.body_fat_percent = null
    Object.assign(s.facts.safety, { hold_active: true, items: [{ code: 'professional_diet' }] })
    const result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.automaticCalculationReady).toBe(false)
    expect(result.visibility.protein).toBe(true)
  })
  it('uses a genuine confirmed calculation prospectively, never to relabel an existing unknown target', () => {
    const s = snapshot()
    s.facts.profile.body_fat_percent = 45
    const decision = {
      version: 1,
      source: 'confirmed_full_calculation_v1',
      user_id: owner,
      signup_generation: generation,
      signup_epoch: epoch,
      review_id: cycle,
      source_episode_event_id: generation,
      phase: 'recomposicao',
      decision_date: '2026-10-24',
      valid_from_date: '2026-10-24',
      decided_at: '2026-10-24T12:00:00.000000Z',
      decision_kind: 'calculated',
      command_hash: 'e'.repeat(64),
      context_hash: 'd'.repeat(64),
      calories_target: 1564,
      formula_target: 1564,
    }
    const raw = {
      ...s,
      facts: {
        ...s.facts,
        protocol_authority: {
          ...s.facts.protocol_authority,
          confirmed_calorie_decision: decision,
          episode: {
            user_id: owner,
            signup_generation: generation,
            signup_epoch: epoch,
            event_id: generation,
            review_id: cycle,
          },
        },
      },
    }
    expect(calculateClinicalSnapshotTargets(raw, owner).automaticCalculationReady).toBe(true)
    expect(calculateClinicalSnapshotTargets(raw, owner).formulaBodyFatPercent).toBeNull()
    const existing = {
      ...raw,
      facts: {
        ...raw.facts,
        day: {
          user_id: owner,
          date: '2026-10-25',
          calories_target: 1099,
          protein_target: 121.5,
          day_closed: false,
        },
      },
    }
    const preserved = calculateClinicalSnapshotTargets(existing, owner)
    expect(preserved.automaticCalculationReady).toBe(false)
    expect(preserved.legacyTarget.action).toBe('preserve')
    expect(preserved.legacyTarget.candidateKcal).toBeNull()
    for (const [field, value] of [
      ['user_id', cycle],
      ['signup_generation', cycle],
      ['signup_epoch', cycle],
      ['phase', 'manutencao'],
      ['valid_from_date', '2026-10-26'],
      ['review_id', epoch],
      ['source_episode_event_id', cycle],
      ['decided_at', '2026-10-26T12:00:00.000000Z'],
    ] as const) {
      const invalid = structuredClone(raw)
      Object.assign(invalid.facts.protocol_authority.confirmed_calorie_decision, { [field]: value })
      expect(() => calculateClinicalSnapshotTargets(invalid, owner)).toThrow(
        'Invalid clinical calculation context',
      )
    }
  })
  it('allows only a new FULL assessment proposal to supersede an unknown source, retaining every safety guard', () => {
    const s = snapshot()
    s.review_kind = 'EARLY_FULL'
    s.facts.profile.body_fat_percent = 45
    s.facts.day = {
      user_id: owner,
      date: '2026-10-25',
      calories_target: 1099,
      protein_target: 121.5,
      day_closed: false,
    }
    const form = { ...proteinForm(), phase: 'recomposicao' }
    const projection = { form, assessmentProposal: true }
    const result = calculateClinicalSnapshotTargets(s, owner, projection)
    expect(result.automaticCalculationReady).toBe(true)
    expect(result.assessmentProposal).toBe(true)
    expect(result.formulaBodyFatPercent).toBeNull()
    expect(result.legacyTarget).toEqual({
      origin: 'unproven',
      action: 'preserve',
      beforeKcal: 1099,
      candidateKcal: null,
    })
    expect(s.facts.day.calories_target).toBe(1099)
    expect(calculateClinicalSnapshotTargets(s, owner).automaticCalculationReady).toBe(false)
    Object.assign(s.facts.safety, { hold_active: true, items: [{ code: 'professional_diet' }] })
    expect(calculateClinicalSnapshotTargets(s, owner, projection).automaticCalculationReady).toBe(
      false,
    )
    Object.assign(s.facts.safety, { hold_active: false, items: [] })
    s.facts.profile.body_fat_percent = 10
    expect(calculateClinicalSnapshotTargets(s, owner, projection).automaticCalculationReady).toBe(
      false,
    )
    expect(() => calculateClinicalSnapshotTargets(s, owner, { assessmentProposal: true })).toThrow(
      'Invalid clinical calculation context',
    )
    s.review_kind = 'ROUTINE_REVIEW'
    expect(() =>
      calculateClinicalSnapshotTargets(s, owner, {
        ...projection,
        form: { ...form, kind: 'ROUTINE_REVIEW' },
      }),
    ).toThrow('Invalid clinical calculation context')
  })
  it.each([
    'sex',
    'birth_date',
    'height_cm',
    'weight_kg',
    'activity_level',
  ])('does not invent missing %s', (field) => {
    const s = snapshot()
    Object.assign(s.facts.profile, { [field]: null })
    const result = calculateClinicalSnapshotTargets(s, owner)
    expect(result.formulaKcal).toBeNull()
    expect(result.proteinTarget).toBeNull()
    expect(result.automaticCalculationReady).toBe(false)
  })
  it('returns exact server bindings without rounding the clinical instants', () => {
    const s = snapshot()
    expect(calculateClinicalSnapshotTargets(s, owner).authority).toEqual({
      userId: owner,
      signupGeneration: generation,
      signupEpoch: epoch,
      contextHash: 'a'.repeat(64),
      kind: 'APPLICATION',
      cycleId: null,
      date: '2026-10-25',
      observedAt: at,
      validUntil: s.valid_until,
    })
  })
  it('refuses a noncanonical candidate weight before SQL stores it', () => {
    const s = snapshot()
    s.review_kind = 'EARLY_FULL'
    expect(() =>
      calculateClinicalSnapshotTargets(s, owner, {
        form: {
          version: 1,
          kind: 'EARLY_FULL',
          phase: 'recomposicao',
          activityPurpose: 'normal',
          answers: { weightKg: 81.555 },
          preference: null,
        },
      }),
    ).toThrow('Invalid clinical calculation context')
  })
  it('keeps input and default config unchanged across independent calculations', () => {
    const s = snapshot()
    const saved = structuredClone(s)
    const defaults = structuredClone(DEFAULT_CALC_CONFIG)
    calculateClinicalSnapshotTargets(s, owner).config.activity_factors.leve = 10
    expect(calculateClinicalSnapshotTargets(s, owner).config.activity_factors.leve).toBe(1.375)
    expect(s).toEqual(saved)
    expect(DEFAULT_CALC_CONFIG).toEqual(defaults)
  })
  it('refuses another owner and a mismatched day without echoing patient data', () => {
    const s = snapshot()
    expect(() => calculateClinicalSnapshotTargets(s, cycle)).toThrow(
      'Invalid clinical calculation context',
    )
    s.facts.day = {
      user_id: cycle,
      date: '2026-10-25',
      calories_target: 1500,
      protein_target: 120,
      day_closed: false,
    }
    expect(() => calculateClinicalSnapshotTargets(s, owner)).toThrow(
      'Invalid clinical calculation context',
    )
  })
})
