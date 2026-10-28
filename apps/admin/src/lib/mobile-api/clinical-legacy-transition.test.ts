import { getReevaluationFormDescriptor } from '@mpp/core/reevaluation-form'
import { describe, expect, it } from 'vitest'
import type { MobileAuthContext } from './auth'
import { readClinicalFullContext } from './clinical-full-authority'
import { evaluateClinicalFull } from './clinical-full-evaluation'
import { clinicalFullPublicCandidateId } from './clinical-full-public-command'
import { createClinicalFullQuestionnaire } from './clinical-full-questionnaire'
import { parseReevaluationCycleRpcState } from './reevaluation-cycle-contracts'
import wire from './testing/clinical-full-wire.json'

function sample() {
  const raw = structuredClone(wire.context)
  Object.assign(raw, { review_kind: 'TRANSITION_FULL' })
  Object.assign(raw.facts.profile, { onboarding_completed_at: null })
  Object.assign(raw.facts.anchor, {
    next_kind: 'TRANSITION_FULL',
    clock: { ...raw.facts.anchor.clock, base_date: '2026-10-26', due_date: '2026-10-26' },
    authority: {
      kind: 'legacy_transition',
      user_id: raw.user_id,
      generation: raw.facts.anchor.signup_generation,
      epoch: raw.facts.anchor.signup_epoch,
      admitted_at: '2026-10-26T16:00:59.600000Z',
      admitted_date: '2026-10-26',
      timezone_at_admission: 'America/Sao_Paulo',
      profile_completed_marker: null,
    },
  })
  Object.assign(raw.facts.cycle, {
    kind: 'TRANSITION_FULL',
    base_date: '2026-10-26',
    due_date: '2026-10-26',
  })
  const scope = { userId: raw.user_id, kind: 'TRANSITION_FULL' as const, cycleId: raw.cycle_id }
  const command = {
    form: { ...structuredClone(wire.receipt.form), kind: 'TRANSITION_FULL' },
    choice: { kind: 'keep' },
    measureConfirmed: false,
    bodyFat: structuredClone(wire.receipt.intent.bodyFat),
  }
  return { raw, scope, command }
}
function unassignedSample() {
  const { raw, scope, command } = sample()
  const legacyOrigin = {
    kind: 'legacy_transition_unassigned' as const,
    generation: raw.facts.anchor.signup_generation,
    epoch: raw.facts.anchor.signup_epoch,
    admittedAt: '2026-10-26T16:00:59.600000Z',
  }
  Object.assign(raw.facts.profile, { current_protocol: null, deficit_level: null })
  Object.assign(raw.facts.protocol_authority, { phase_origin: legacyOrigin })
  const form = {
    ...command.form,
    phase: null,
    legacyOrigin,
    answers: { ...command.form.answers, adherence: null, energy: null },
  }
  return { raw, scope, command: { ...command, form }, legacyOrigin }
}
describe('honest legacy transition contracts', () => {
  it('uses a FULL questionnaire and three NEW photos without alleging a completed fortnight', () => {
    const value = getReevaluationFormDescriptor({
      phase: 'recomposicao',
      kind: 'TRANSITION_FULL',
      sex: 'masculino',
      currentActivityLevel: 'moderado',
      holdActive: false,
      activityPurpose: 'normal',
      confirmedMealDays: 14,
    })
    expect(value.photoRequirement).toEqual({
      required: true,
      newOnly: true,
      poses: ['front', 'side', 'back'],
    })
    expect(value.questions.map((q) => q.key)).toContain('healthCheck')
    expect(value.questions.map((q) => q.label).join(' ')).not.toContain('14 dias')
    expect(value.supportText).toBeNull()
  })
  it('reads the immediate clock only with its original transition identity and kind', () => {
    const { raw } = sample()
    const value = {
      version: 1,
      availability: 'available',
      unavailable_reason: null,
      clock: raw.facts.anchor.clock,
      transition: {
        kind: 'legacy_transition',
        generation: raw.facts.anchor.signup_generation,
        epoch: raw.facts.anchor.signup_epoch,
        admitted_at: '2026-10-26T16:00:59.600000Z',
      },
      cycle: {
        id: raw.cycle_id,
        signup_generation: raw.facts.anchor.signup_generation,
        kind: 'TRANSITION_FULL',
        revision: '5',
        status: 'collecting',
        base_date: '2026-10-26',
        due_date: '2026-10-26',
        timezone_at_open: 'America/Sao_Paulo',
        opened_at: raw.facts.cycle.opened_at,
      },
    }
    expect(parseReevaluationCycleRpcState(value)).toEqual(value)
    const { transition: _proof, ...unproven } = value
    expect(() => parseReevaluationCycleRpcState(unproven)).toThrow()
    expect(() =>
      parseReevaluationCycleRpcState({ ...value, cycle: { ...value.cycle, kind: 'REGULAR' } }),
    ).toThrow()
    expect(() =>
      parseReevaluationCycleRpcState({
        ...value,
        transition: { ...value.transition, generation: raw.cycle_id },
      }),
    ).toThrow()
    expect(() => parseReevaluationCycleRpcState({ ...value, cycle: null })).not.toThrow()
  })
  it('calculates only from the accepted current photo candidate and keeps fortnight counters unknown', () => {
    const { raw, scope, command } = sample()
    expect(readClinicalFullContext(raw, scope).facts.anchor.authority.kind).toBe(
      'legacy_transition',
    )
    const value = evaluateClinicalFull(raw, scope, command)
    expect(value.package.intent.bodyFat).toEqual(command.bodyFat)
    expect(value.package.proposal.targets.afterKcal).toBeGreaterThan(0)
    expect(value.package.proposal.episode.difficultyCount).toBeNull()
    expect(value.package.proposal.episode.ledgerSteps).toBeNull()
    expect(() => evaluateClinicalFull(raw, scope, { ...command, bodyFat: null })).toThrow()
    expect(() =>
      evaluateClinicalFull(raw, scope, { ...command, choice: { kind: 'phase_calorie_step' } }),
    ).toThrow()
  })
  it('refuses a missing transition selector or a genuine signup relabeled as transition', () => {
    const { raw, scope } = sample()
    const absent = structuredClone(raw)
    Reflect.deleteProperty(absent.facts.anchor, 'next_kind')
    expect(() => readClinicalFullContext(absent, scope)).toThrow()
    const genuine = structuredClone(wire.context)
    Object.assign(genuine, { review_kind: 'TRANSITION_FULL' })
    expect(() => readClinicalFullContext(genuine, scope)).toThrow()
  })
  it('uses the accepted photo result for the weight-loss protection even when the old report is higher', () => {
    const { raw, scope, command } = sample()
    Object.assign(raw.facts.protocol_authority.body_fat_candidate, {
      mean_percent: 9,
      mean_hundredths: 900,
    })
    command.bodyFat.meanHundredths = 900
    const value = evaluateClinicalFull(raw, scope, command)
    expect(value.safety.pauseWeightLossGuidance).toBe(true)
    expect(value.package.proposal.principal).toBe('keep')
    expect(value.package.proposal.targets.afterKcal).toBe(raw.facts.day.calories_target)
    expect(value.package.proposal.targets.afterProtein).toBe(raw.facts.day.protein_target)
  })
  it.each([
    'pt-BR',
    'en-US',
  ])('describes a usable photo confirmation in %s without leaking private authority', async (locale) => {
    const { raw, scope, command } = sample()
    const auth = {
      userId: raw.user_id,
      authUserId: raw.user_id,
      identity: { id: raw.user_id },
      patient: { id: raw.user_id, authUserId: raw.user_id, status: 'active', locale },
    } as MobileAuthContext
    const service = createClinicalFullQuestionnaire({
      enabled: true,
      repository: { capture: async () => raw },
    })
    const descriptor = await service.describe(auth, {
      kind: scope.kind,
      cycleId: scope.cycleId,
      activityPurpose: 'normal',
    })
    expect(descriptor.photo_requirement.required).toBe(true)
    expect(descriptor.body_fat.status).toBe('ready')
    expect(descriptor.questions.map((q) => q.label).join(' ')).not.toMatch(/14 (dias|days)/)
    expect(JSON.stringify(descriptor)).not.toContain('signup_generation')
    const input = {
      activityPurpose: 'normal',
      answers: command.form.answers,
      preference: null,
      measureConfirmed: false,
      bodyFat: {
        confirmed: true,
        candidateId: clinicalFullPublicCandidateId(scope, command.bodyFat),
      },
    }
    expect(
      (
        await service.assess(auth, {
          kind: scope.kind,
          cycleId: scope.cycleId,
          input: { ...input, bodyFat: null },
        })
      ).status,
    ).toBe('body_fat_confirmation_required')
    const assessed = await service.assess(auth, { kind: scope.kind, cycleId: scope.cycleId, input })
    expect(assessed.status).toBe('available')
    expect(assessed.actions.some((a) => a.choice.kind === 'keep')).toBe(true)
    expect(assessed.actions.some((a) => a.choice.kind === 'phase_calorie_step')).toBe(false)
  })
})

describe('explicit first phase inside a truthful legacy FULL', () => {
  it('keeps an unknown phase and existing targets until an eligible phase is explicitly selected', () => {
    const { raw, scope, command } = unassignedSample(),
      before = structuredClone(raw)
    const kept = evaluateClinicalFull(raw, scope, command)
    expect(kept.package.proposal.profile.current_protocol).toBeNull()
    expect(kept.package.proposal.targets).toEqual({
      beforeKcal: 1700,
      beforeProtein: 120,
      afterKcal: 1700,
      afterProtein: 120,
      formulaAfterKcal: null,
    })
    const chosen = evaluateClinicalFull(raw, scope, {
      ...command,
      choice: { kind: 'phase', phase: 'recomposicao' },
    })
    expect(chosen.command.form.phase).toBeNull()
    expect(chosen.package.proposal).toMatchObject({
      principal: 'phase_recomposition',
      profile: { current_protocol: 'recomposicao', deficit_level: 500 },
      targets: { afterKcal: 1599, afterProtein: 126, formulaAfterKcal: 1599 },
      episode: { difficultyCount: 0, ledgerSteps: null, schedule: null, maintenanceSince: null },
    })
    expect(raw).toEqual(before)
  })
  it('refuses ineligible phase, missing current input and a mismatched legacy origin', () => {
    const { raw, scope, command } = unassignedSample()
    for (const phase of ['ganho_massa', 'manutencao'])
      expect(() =>
        evaluateClinicalFull(raw, scope, { ...command, choice: { kind: 'phase', phase } }),
      ).toThrow()
    const missing = structuredClone(raw)
    Object.assign(missing.facts.profile, { hunger_level: null })
    expect(() =>
      evaluateClinicalFull(missing, scope, {
        ...command,
        form: { ...command.form, answers: { ...command.form.answers, hunger: null } },
        choice: { kind: 'phase', phase: 'recomposicao' },
      }),
    ).toThrow()
    expect(() =>
      evaluateClinicalFull(raw, scope, {
        ...command,
        form: {
          ...command.form,
          legacyOrigin: { ...command.form.legacyOrigin, generation: scope.cycleId },
        },
      }),
    ).toThrow()
  })
  it('offers only current-input questions and eligible actions without fabricating a previous plan', async () => {
    const { raw, scope, command } = unassignedSample()
    const auth = {
      userId: raw.user_id,
      authUserId: raw.user_id,
      identity: { id: raw.user_id },
      patient: { id: raw.user_id, authUserId: raw.user_id, status: 'active', locale: 'pt-BR' },
    } as MobileAuthContext
    const service = createClinicalFullQuestionnaire({
      enabled: true,
      repository: { capture: async () => raw },
    })
    const described = await service.describe(auth, {
      kind: scope.kind,
      cycleId: scope.cycleId,
      activityPurpose: 'normal',
    })
    expect(described.questions.map((q) => q.key)).toEqual(
      expect.arrayContaining(['weightKg', 'strengthSessions', 'hunger', 'healthCheck']),
    )
    expect(
      described.questions.some((q) =>
        ['adherence', 'energy', 'difficultToMaintain', 'strengthProgression'].includes(q.key),
      ),
    ).toBe(false)
    expect(described.photo_requirement.required).toBe(true)
    const assessed = await service.assess(auth, {
      kind: scope.kind,
      cycleId: scope.cycleId,
      input: {
        activityPurpose: 'normal',
        answers: command.form.answers,
        preference: null,
        measureConfirmed: false,
        bodyFat: {
          confirmed: true,
          candidateId: clinicalFullPublicCandidateId(scope, command.bodyFat),
        },
      },
    })
    expect(assessed.status).toBe('available')
    expect(assessed.actions.filter((a) => a.choice.kind === 'phase').map((a) => a.choice)).toEqual([
      { kind: 'phase', phase: 'recomposicao' },
    ])
    expect(raw.facts.profile.current_protocol).toBeNull()
    expect(JSON.stringify(described)).not.toContain('legacyOrigin')
  })
})
