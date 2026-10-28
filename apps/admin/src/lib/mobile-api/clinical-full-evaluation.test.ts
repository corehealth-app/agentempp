import { describe, expect, it } from 'vitest'
import { evaluateClinicalFull } from './clinical-full-evaluation'
import wire from './testing/clinical-full-wire.json'

const scope = { userId: wire.context.user_id, kind: 'REGULAR', cycleId: wire.context.cycle_id }
const activity = {
  otherExerciseType: null,
  otherExerciseDays: null,
  sessionMinutes: null,
  sessionIntensity: null,
  mostlySitting: null,
  activityLevel: 'moderado',
  activityLevelConfirmed: true,
}
function sample(phase = 'recomposicao') {
  const seed = structuredClone(wire.context)
  const raw = {
    ...seed,
    facts: {
      ...seed.facts,
      protocol_authority: {
        ...seed.facts.protocol_authority,
        episode:
          phase === 'recomposicao'
            ? null
            : structuredClone(wire.after.facts.protocol_authority.episode),
      },
    },
  }
  Object.assign(raw.facts.profile, {
    current_protocol: phase,
    deficit_level: phase === 'recomposicao' ? 500 : null,
  })
  Object.assign(raw, { observed_at: wire.after.observed_at })
  if (phase !== 'recomposicao')
    Object.assign(raw.facts.protocol_authority, {
      episode: {
        ...wire.after.facts.protocol_authority.episode,
        phase,
        deficit_level: null,
        entry_origin: 'confirmed_phase_change',
        entry_date: '2026-09-01',
        start_weight_kg: 80,
        start_height_cm: 180,
        start_body_fat_percent: 15,
        start_training_frequency: 4,
        ledger_steps: [],
        difficulty_count: null,
        maintenance_since: phase === 'manutencao' ? '2026-09-01' : null,
      },
    })
  return raw
}
function provenEpisode(raw: ReturnType<typeof sample>) {
  const value = raw.facts.protocol_authority.episode
  if (!value) throw new Error('SQL-shaped fixture requires an episode')
  return value
}
function form(phase = 'recomposicao') {
  const form = structuredClone(wire.receipt.form)
  form.phase = phase
  Object.assign(form.answers, {
    difficultToMaintain: phase === 'manutencao' ? 'nao' : null,
    strengthProgression: phase === 'ganho_massa' ? 'piorou_ou_travou' : null,
    fatPerception: phase === 'ganho_massa' ? 'nao_percebi' : null,
  })
  return form
}
function command(phase = 'recomposicao', choice: object = { kind: 'keep' }) {
  return {
    form: form(phase),
    choice,
    measureConfirmed: false,
    bodyFat: structuredClone(wire.receipt.intent.bodyFat),
  }
}
function lowerFat(raw: ReturnType<typeof sample>, input: ReturnType<typeof command>, percent = 18) {
  raw.facts.protocol_authority.body_fat_candidate.mean_percent = percent
  raw.facts.protocol_authority.body_fat_candidate.mean_hundredths = percent * 100
  input.bodyFat.meanHundredths = percent * 100
}
function episode(raw: ReturnType<typeof sample>, patch: object) {
  Object.assign(raw.facts.protocol_authority, {
    episode: {
      ...wire.after.facts.protocol_authority.episode,
      applied_at: raw.observed_at,
      ...patch,
    },
  })
}
function weights(raw: ReturnType<typeof sample>, allWeeks = true) {
  const offsets = allWeeks
    ? [-27, -24, -21, -20, -17, -14, -13, -10, -7, -6, -3, 0]
    : [-13, -10, -7, -6, -3, 0]
  const today = new Date(`${raw.facts.calculation_date}T00:00:00.000Z`).getTime()
  Object.assign(raw.facts, {
    weight_history: offsets.map((offset, index) => {
      const date = new Date(today + offset * 86400000).toISOString().slice(0, 10)
      return {
        id: `b3b01000-0000-4000-8000-${String(5000 + index).padStart(12, '0')}`,
        user_id: scope.userId,
        weight_kg: 80,
        measured_at: `${date}T12:00:00.000000Z`,
        received_at: `${date}T12:00:00.000000Z`,
        instant_source: 'recorded',
        observed_timezone: 'America/Sao_Paulo',
        local_date: date,
        authority_epoch: raw.facts.anchor.signup_epoch,
      }
    }),
  })
}
describe('actual server-owned all-phase FULL evaluation', () => {
  it('distinguishes computed formula and protein from calories preserved by an unknown ledger', () => {
    const raw = sample('manutencao'),
      input = command('manutencao')
    Object.assign(provenEpisode(raw), {
      entry_origin: 'legacy_unknown',
      entry_date: null,
      start_weight_kg: null,
      start_height_cm: null,
      start_body_fat_percent: null,
      start_training_frequency: null,
      ledger_steps: null,
      maintenance_since: null,
    })
    const p = evaluateClinicalFull(raw, scope, input).package.proposal
    expect(p.targets.formulaAfterKcal).not.toBeNull()
    expect(p.targets.afterKcal).toBe(p.targets.beforeKcal)
    expect(p.episode.ledgerSteps).toBeNull()
  })
  it('preserves an unknown legacy deficit and its targets under HOLD without manufacturing 500', () => {
    const raw = sample(),
      input = command()
    Object.assign(raw.facts.profile, { deficit_level: null })
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    const evaluated = evaluateClinicalFull(raw, scope, input)
    expect(evaluated.package.proposal.profile.deficit_level).toBeNull()
    expect(evaluated.package.proposal.targets).toMatchObject({
      beforeKcal: 1700,
      afterKcal: 1700,
      formulaAfterKcal: null,
    })
    expect(evaluated.package.proposal.episode.difficultyCount).toBeNull()
    for (const choice of [
      { kind: 'activity' },
      { kind: 'phase_calorie_step' },
      { kind: 'phase', phase: 'manutencao' },
    ])
      expect(() => evaluateClinicalFull(raw, scope, { ...input, choice })).toThrow(
        'Review choice unavailable',
      )
  })
  it('preserves a protected target, then proposes a fresh EARLY assessment without claiming old BF formula provenance', () => {
    const raw = sample(),
      input = command()
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    expect(
      evaluateClinicalFull(raw, scope, input).package.proposal.targets.formulaAfterKcal,
    ).toBeNull()
    Object.assign(raw.facts.safety, { hold_active: false, items: [] })
    Object.assign(raw, { review_kind: 'EARLY_FULL' })
    Object.assign(input.form, { kind: 'EARLY_FULL' })
    Object.assign(input, { bodyFat: null })
    const proposed = evaluateClinicalFull(raw, { ...scope, kind: 'EARLY_FULL' }, input).package
      .proposal.targets
    expect(proposed.beforeKcal).toBe(1700)
    expect(proposed.formulaAfterKcal).not.toBeNull()
    expect(proposed.afterKcal).toBe(proposed.formulaAfterKcal)
    expect(raw.facts.day.calories_target).toBe(1700)
  })
  it('does not count or reset n2 during EARLY_FULL even when answers differ', () => {
    const raw = sample(),
      input = command()
    episode(raw, { difficulty_count: '4' })
    Object.assign(raw, { review_kind: 'EARLY_FULL' })
    Object.assign(input.form, { kind: 'EARLY_FULL' })
    Object.assign(input, { bodyFat: null })
    input.form.answers.hunger = 'pouca'
    expect(
      evaluateClinicalFull(raw, { ...scope, kind: 'EARLY_FULL' }, input).package.proposal.episode
        .difficultyCount,
    ).toBe(4)
  })
  it('uses confirmed activity and signed ledger rather than session count for calories', () => {
    const raw = sample('manutencao'),
      input = command('manutencao', { kind: 'activity' })
    Object.assign(provenEpisode(raw), { ledger_steps: [-100] })
    Object.assign(input.form.answers, {
      weightKg: 80,
      activity: { ...activity, activityLevel: 'alto' },
    })
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'activity',
      profile: { activity_level: 'alto' },
      targets: { afterKcal: 2804, formulaAfterKcal: 2904 },
      episode: { ledgerSteps: [-100] },
    })
  })
  it('refuses gain activity increases below the higher current/start strength baseline', () => {
    const raw = sample('ganho_massa'),
      input = command('ganho_massa', { kind: 'activity' })
    lowerFat(raw, input, 15)
    Object.assign(raw.facts.profile, { training_frequency: 5 })
    Object.assign(input.form.answers, {
      weightKg: 80,
      strengthSessions: 4,
      activity: { ...activity, activityLevel: 'alto' },
    })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
    input.form.answers.strengthSessions = 5
    expect(
      evaluateClinicalFull(raw, scope, input).package.proposal.profile.training_frequency,
    ).toBe(5)
  })
  it('applies only frozen schedule values when kept and never resumes a paused plan', () => {
    const raw = sample('manutencao'),
      input = command('manutencao')
    const schedule = {
      version: 1,
      kind: 'recomp_to_maintenance',
      state: 'running',
      startDate: '2026-10-01',
      startTargetKcal: 1700,
      maintenanceTargetKcal: 2600,
      plannedEndDate: '2026-11-26',
    }
    Object.assign(provenEpisode(raw), { schedule, maintenance_since: null })
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'keep',
      targets: { afterKcal: 2100 },
      episode: { maintenanceSince: null, schedule: { state: 'running' } },
    })
    schedule.state = 'suspended'
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'keep',
      targets: { afterKcal: 1700 },
      episode: { maintenanceSince: null, schedule: { state: 'suspended' } },
    })
  })
  it('requires daily suspension authority before a guarded ROUTINE with a running schedule', () => {
    const raw = sample('manutencao'),
      input = command('manutencao')
    const schedule = {
      version: 1,
      kind: 'recomp_to_maintenance',
      state: 'running',
      startDate: '2026-10-01',
      startTargetKcal: 1700,
      maintenanceTargetKcal: 2600,
      plannedEndDate: '2026-11-26',
    }
    Object.assign(raw, { review_kind: 'ROUTINE_REVIEW', cycle_id: null })
    Object.assign(provenEpisode(raw), { schedule, maintenance_since: null })
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    Object.assign(input.form, { kind: 'ROUTINE_REVIEW' })
    Object.assign(input, { bodyFat: null })
    Object.assign(input.form.answers, {
      weightKg: null,
      healthCheck: null,
      energy: null,
      adherence: null,
      difficultToMaintain: null,
    })
    const expected = { ...scope, kind: 'ROUTINE_REVIEW', cycleId: null }
    expect(() => evaluateClinicalFull(raw, expected, input)).toThrow('Review choice unavailable')
    schedule.state = 'suspended'
    expect(evaluateClinicalFull(raw, expected, input).package.proposal).toMatchObject({
      principal: 'keep',
      targets: { afterKcal: 1700, afterProtein: 120 },
      episode: { schedule: { state: 'suspended' } },
    })
  })
  it('runs the maintenance calorie rule using real-shaped individual samples and a proven ledger', () => {
    const raw = sample('manutencao'),
      input = command('manutencao', { kind: 'phase_calorie_step' })
    weights(raw, false)
    Object.assign(input.form.answers, { weightKg: 80, hunger: 'muita', energy: 'baixa' })
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      principal: 'maintenance_step',
      profile: { hunger_level: 'moderada' },
      targets: { afterKcal: 2709, formulaAfterKcal: 2609, afterProtein: 144 },
      episode: { ledgerSteps: [100] },
    })
    Object.assign(raw.facts.protocol_authority, {
      routine_reviews_since_regular: [
        {
          review_id: wire.receipt.preview_id,
          principal: 'activity',
          base_before: '2026-10-01',
          date: '2026-10-20',
          review_no: '1',
          activity_level_changed: true,
        },
      ],
    })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
  })
  it('never creates a maintenance/gain ledger from an unknown legacy episode', () => {
    const raw = sample('manutencao'),
      input = command('manutencao', { kind: 'phase_calorie_step' })
    Object.assign(raw.facts.protocol_authority, { episode: null })
    weights(raw, false)
    Object.assign(input.form.answers, { weightKg: 80, hunger: 'muita', energy: 'baixa' })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
  })
  it('enforces the four-week gate before maintenance can become gain', () => {
    const raw = sample('manutencao'),
      input = command('manutencao', { kind: 'phase', phase: 'ganho_massa' })
    lowerFat(raw, input)
    Object.assign(input.form.answers, { weightKg: 80, hunger: 'pouca', activity })
    Object.assign(raw.facts.protocol_authority, {
      prior_regular_reviews: [
        {
          ...wire.after.facts.protocol_authority.prior_regular_reviews[0],
          date: '2026-10-12',
        },
      ],
    })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
    weights(raw)
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      principal: 'phase_gain',
      profile: { current_protocol: 'ganho_massa', hunger_level: 'pouca' },
      targets: { afterKcal: 2908, afterProtein: 152 },
      episode: { ledgerSteps: [], maintenanceSince: null },
    })
  })
  it('requires the separate measure confirmation for the above-cut maintenance suggestion', () => {
    const raw = sample('manutencao'),
      input = command('manutencao', { kind: 'phase', phase: 'recomposicao' })
    Object.assign(input.form.answers, { weightKg: 80, activity })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
    input.measureConfirmed = true
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'phase_recomposition',
      profile: { deficit_level: 500 },
      targets: { afterKcal: 1520, afterProtein: 120 },
    })
  })
  it('runs gain n16 only with preserved strength/known limits and an absolute ledger budget', () => {
    const raw = sample('ganho_massa'),
      input = command('ganho_massa', { kind: 'phase_calorie_step' })
    lowerFat(raw, input, 15)
    weights(raw, false)
    Object.assign(input.form.answers, { weightKg: 80, hunger: 'muita', energy: 'baixa' })
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'gain_step',
      targets: { afterKcal: 3143, formulaAfterKcal: 2993 },
      episode: { ledgerSteps: [150] },
    })
    input.form.answers.strengthSessions = 2
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
  })
  it('applies the first frozen gain-exit step and resets ledger only on actual phase change', () => {
    const raw = sample('ganho_massa'),
      input = command('ganho_massa', { kind: 'phase', phase: 'manutencao' })
    lowerFat(raw, input, 15)
    Object.assign(input.form.answers, { activity })
    raw.facts.day.calories_target = 3200
    const running = evaluateClinicalFull(raw, scope, input)
    expect(running.package.proposal).toMatchObject({
      principal: 'gain_exit',
      profile: { current_protocol: 'ganho_massa' },
      targets: { afterKcal: 3100, formulaAfterKcal: 2964 },
      episode: {
        schedule: { kind: 'gain_exit', maintenanceTargetKcal: 2964 },
        maintenanceSince: null,
      },
    })
    raw.facts.day.calories_target = 2500
    Object.assign(provenEpisode(raw), { ledger_steps: [-100] })
    const completed = evaluateClinicalFull(raw, scope, input)
    expect(completed.package.proposal).toMatchObject({
      profile: { current_protocol: 'manutencao' },
      targets: { afterKcal: 2964 },
      episode: {
        ledgerSteps: [],
        difficultyCount: 0,
        maintenanceSince: raw.facts.calculation_date,
      },
    })
    raw.facts.day.day_closed = true
    expect(
      evaluateClinicalFull(raw, scope, input).package.proposal.episode.maintenanceSince,
    ).toBeNull()
  })
  it('supports the narrowly confirmed SAFETY exit without clearing the captured HOLD', () => {
    const raw = sample(),
      input = command('recomposicao', { kind: 'neutral_exit' })
    Object.assign(raw, { review_kind: 'SAFETY', cycle_id: null })
    Object.assign(raw.facts.profile, { body_fat_percent: null })
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    Object.assign(input, { bodyFat: null })
    Object.assign(input.form, { kind: 'SAFETY' })
    Object.assign(input.form.answers, {
      weightKg: null,
      hunger: null,
      adherence: null,
      energy: null,
      healthCheck: null,
      activity,
    })
    const expected = { ...scope, kind: 'SAFETY', cycleId: null }
    expect(evaluateClinicalFull(raw, expected, input).package.proposal).toMatchObject({
      principal: 'neutral_exit',
      clearHold: false,
      profile: { current_protocol: 'manutencao' },
      targets: { afterKcal: 2713, afterProtein: 144 },
      episode: { ledgerSteps: [], schedule: null },
    })
    Object.assign(raw.facts.profile, { weight_kg: 50 })
    expect(() => evaluateClinicalFull(raw, expected, input)).toThrow('Review choice unavailable')
  })
  it('keeps health-only FULL targets and episode null after an approved clear', () => {
    const raw = sample(),
      input = command()
    const origin = {
      kind: 'confirmed_no_plan',
      completedAt: raw.facts.profile.onboarding_completed_at,
      signupEpoch: raw.facts.anchor.signup_epoch,
      signupGeneration: raw.facts.anchor.signup_generation,
    }
    Object.assign(raw.facts.profile, { current_protocol: null, deficit_level: null })
    Object.assign(raw.facts.protocol_authority, { phase_origin: origin })
    Object.assign(input.form, { phase: null, noPlanOrigin: origin })
    for (const key of Object.keys(input.form.answers))
      Object.assign(input.form.answers, { [key]: null })
    Object.assign(input.form.answers, {
      weightKg: 84,
      healthCheck: { kind: 'none' },
      professionalConversationConfirmed: true,
    })
    Object.assign(raw.facts.safety, {
      hold_active: true,
      items: [{ code: 'pregnant_or_breastfeeding' }],
    })
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      clearHold: true,
      profile: { current_protocol: null },
      targets: { afterKcal: null, afterProtein: null },
      episode: { ledgerSteps: null, schedule: null },
    })
  })
  it('computes real recomposition targets from confirmed photos and weight, not a submitted effect', () => {
    const value = evaluateClinicalFull(sample(), scope, command())
    expect(value.package.proposal).toMatchObject({
      principal: 'keep',
      profile: { current_protocol: 'recomposicao', deficit_level: 500 },
      targets: {
        beforeKcal: 1700,
        beforeProtein: 120,
        afterKcal: 1599,
        afterProtein: 126,
        formulaAfterKcal: 1599,
      },
    })
    expect(value.package.proposal.episode.difficultyCount).toBe(0)
    expect(value.package.proposal.episode.ledgerSteps).toBeNull()
  })
  it('normalizes refused n21 preference out of both the prepared form and calculation', () => {
    const input = command()
    Object.assign(input.form, {
      preference: { action: 'change', value: { kind: 'body_fat', percent: 8 } },
    })
    const value = evaluateClinicalFull(sample(), scope, input)
    expect(value.package.form.preference).toBeNull()
    expect(value.command.form.preference).toBeNull()
    expect(value.command.choice).toEqual({ kind: 'keep' })
    expect(value.preference.status).toBe('refused')
    expect(value.package.proposal.targets.afterKcal).toBe(1599)
  })
  it('records answers without changing protected inputs or targets under a captured HOLD', () => {
    const raw = sample(),
      input = command()
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    input.form.answers.hunger = 'muita'
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      clearHold: false,
      profile: { hunger_level: 'moderada', training_frequency: 4 },
      targets: { afterKcal: 1700, afterProtein: 120 },
    })
    expect(value.package.form.answers.hunger).toBe('muita')
  })
  it('uses effective post-clear safety only with the exact professional declaration, preserving source', () => {
    const raw = sample(),
      input = command()
    Object.assign(raw.facts.safety, { hold_active: true, items: [{ code: 'reduced_intake' }] })
    Object.assign(input.form.answers, { professionalConversationConfirmed: true })
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal.clearHold).toBe(true)
    expect(value.package.proposal.targets.afterKcal).toBe(1599)
    expect(raw.facts.safety.hold_active).toBe(true)
    input.form.answers.weightKg = 50
    const guarded = evaluateClinicalFull(raw, scope, input)
    expect(guarded.package.proposal.clearHold).toBe(true)
    expect(guarded.package.proposal.targets.afterKcal).toBe(1700)
  })
  it('requires declaring new health risks before capturing and preparing the FULL', () => {
    const input = command()
    Object.assign(input.form.answers, { healthCheck: { kind: 'risks', items: ['reduced_intake'] } })
    expect(() => evaluateClinicalFull(sample(), scope, input)).toThrow('Clinical context changed')
  })
  it('retains unknown legacy difficulty until current answers actually establish a reset', () => {
    const input = command()
    input.form.answers.hunger = 'muita'
    expect(
      evaluateClinicalFull(sample(), scope, input).package.proposal.episode.difficultyCount,
    ).toBeNull()
    expect(() =>
      evaluateClinicalFull(sample(), scope, { ...input, choice: { kind: 'phase_calorie_step' } }),
    ).toThrow('Review choice unavailable')
  })
  it('accepts the second known difficult regular once and never raises a deficit on lower hunger', () => {
    const raw = sample(),
      input = command('recomposicao', { kind: 'phase_calorie_step' })
    episode(raw, { difficulty_count: '1' })
    input.form.answers.hunger = 'muita'
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      principal: 'deficit_step',
      profile: { deficit_level: 400 },
      targets: { afterKcal: 1699 },
      episode: { difficultyCount: 0 },
    })
    expect(value.package.intent.principalConfirmed).toBe(true)
    input.form.answers.hunger = 'pouca'
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
  })
  it('keeps n11 branch-changing answers unapplied until the activity/protein package is chosen', () => {
    const raw = sample('manutencao'),
      input = command('manutencao')
    input.form.answers.hunger = 'muita'
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      profile: { hunger_level: 'moderada' },
      targets: { afterProtein: 151.2 },
    })
    input.choice = { kind: 'activity' }
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'activity',
      profile: { hunger_level: 'muita' },
      targets: { afterProtein: 134.4 },
    })
  })
  it('starts a proven recomposition→maintenance schedule with its first100 today', () => {
    const raw = sample(),
      input = command('recomposicao', { kind: 'phase', phase: 'manutencao' })
    lowerFat(raw, input)
    Object.assign(input.form, { activityPurpose: 'consider_maintenance' })
    Object.assign(input.form.answers, { activity })
    const value = evaluateClinicalFull(raw, scope, input)
    expect(value.package.proposal).toMatchObject({
      principal: 'recomposition_transition',
      profile: { current_protocol: 'manutencao', deficit_level: null },
      targets: { afterKcal: 1800, afterProtein: 151.2 },
      episode: {
        ledgerSteps: [],
        maintenanceSince: null,
        schedule: { kind: 'recomp_to_maintenance', startTargetKcal: 1700 },
      },
    })
  })
  it('allows a newly confirmed safe phase choice from an unknown deficit without using a 500 default', () => {
    const raw = sample(),
      input = command('recomposicao', { kind: 'phase', phase: 'manutencao' })
    Object.assign(raw.facts.profile, { deficit_level: null })
    lowerFat(raw, input)
    Object.assign(input.form, { activityPurpose: 'consider_maintenance' })
    Object.assign(input.form.answers, { activity })
    expect(evaluateClinicalFull(raw, scope, input).package.proposal).toMatchObject({
      principal: 'recomposition_transition',
      profile: { current_protocol: 'manutencao', deficit_level: null },
      targets: { beforeKcal: 1700, afterKcal: 1800 },
      episode: { schedule: { kind: 'recomp_to_maintenance', startTargetKcal: 1700 } },
    })
  })
  it.each([
    ['recomposicao', 'ganho_massa'],
    ['ganho_massa', 'recomposicao'],
  ])('refuses forbidden direct path %s→%s', (before, after) => {
    expect(() =>
      evaluateClinicalFull(sample(before), scope, command(before, { kind: 'phase', phase: after })),
    ).toThrow('Review choice unavailable')
  })
  it('refuses a phase change based on an unconfirmed activity level or the composition cut', () => {
    const raw = sample(),
      input = command('recomposicao', { kind: 'phase', phase: 'manutencao' })
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
    lowerFat(raw, input)
    expect(() => evaluateClinicalFull(raw, scope, input)).toThrow('Review choice unavailable')
  })
  it('does not accept multiple choices or a client-calculated target/episode', () => {
    expect(() =>
      evaluateClinicalFull(sample(), scope, {
        ...command(),
        proposal: { targets: { afterKcal: 999 } },
      }),
    ).toThrow('Invalid clinical FULL input')
    expect(() =>
      evaluateClinicalFull(sample(), scope, {
        ...command(),
        choice: { kind: 'keep', phase: 'ganho_massa' },
      }),
    ).toThrow('Invalid clinical FULL input')
  })
})
