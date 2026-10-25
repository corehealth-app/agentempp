import { describe, expect, it } from 'vitest'
import {
  evaluateDeficitDifficulty,
  evaluateGainReviewLimits,
  evaluatePhaseCalorieRule,
} from './reevaluation-calorie-rules.js'

const safety = {
  date: '2026-10-28',
  birthDate: '1990-01-01',
  weightKg: 80,
  heightCm: 180,
  bodyFatPercent: 18,
  hold: { active: false, items: [] },
}
const form = (phase = 'manutencao', patch: Record<string, unknown> = {}) => ({
  version: 1,
  phase,
  kind: 'REGULAR',
  activityPurpose: 'normal',
  answers: {
    weightKg: 80,
    strengthSessions: 4,
    adherence: 'bem_consistente',
    hunger: 'moderada',
    energy: 'ok',
    healthCheck: { kind: 'none' },
    ...(phase === 'manutencao' ? { difficultToMaintain: 'nao' } : {}),
    ...(phase === 'ganho_massa'
      ? { strengthProgression: 'piorou_ou_travou', fatPerception: 'nao_percebi' }
      : {}),
    ...patch,
  },
})
let sequence = 0
function weights(current = 8040) {
  return {
    date: safety.date,
    asOf: '2026-10-28T23:59:59.999999Z',
    measurements: [-13, -10, -7, -6, -3, 0].map((offset) => {
      const date = new Date(Date.UTC(2026, 9, 28 + offset)).toISOString().slice(0, 10)
      sequence++
      return {
        id: `aaaaaaaa-aaaa-4aaa-8aaa-${String(sequence).padStart(12, '0')}`,
        localDate: date,
        measuredAt: `${date}T12:00:00.000000Z`,
        weightHundredths: offset < -6 ? 8000 : current,
      }
    }),
  }
}
const context = (phase = 'manutencao', patch: Record<string, unknown> = {}) => ({
  form: form(phase),
  safety,
  history: weights(),
  currentTargetKcal: 2500,
  floorKcal: 2000,
  ledgerSteps: [],
  maintenanceSince: '2026-10-14',
  activityChangedThisCycle: false,
  transitionActive: false,
  higherPriorityDecisionConfirmed: false,
  sex: 'masculino',
  gainStartBMI: 24,
  gainStartBodyFatHundredths: 1700,
  gainStartFrequency: 4,
  profileStrengthFrequency: 4,
  ...patch,
})
describe('n2 consecutive difficulty and proposal only', () => {
  const input = (count = 0, deficitLevel = 600, answers: Record<string, unknown> = {}) => ({
    form: form('recomposicao', { hunger: 'muita', energy: 'ok', ...answers }),
    safety,
    count,
    deficitLevel,
    higherPriorityDecisionConfirmed: false,
  })
  it('first difficult guides only; second proposes600->500 and reset only on confirmation', () => {
    expect(evaluateDeficitDifficulty(input())).toMatchObject({
      status: 'evaluated',
      nextCount: 1,
      proposal: null,
      guidance: true,
    })
    expect(evaluateDeficitDifficulty(input(1))).toMatchObject({
      nextCount: 2,
      proposal: {
        deficitBefore: 600,
        deficitAfter: 500,
        deltaKcal: 100,
        countAfterConfirmation: 0,
      },
    })
  })
  it('500->400 once eligible; at400never offers further reduction of deficit', () => {
    expect(evaluateDeficitDifficulty(input(1, 500))).toHaveProperty('proposal.deficitAfter', 400)
    expect(evaluateDeficitDifficulty(input(5, 400))).toMatchObject({
      nextCount: 6,
      proposal: null,
      reason: 'minimum_deficit',
    })
  })
  it.each([
    { hunger: null },
    { energy: null },
    { hunger: null, energy: null },
  ])('unknown resets count but known difficulty can still guide %#', (patch) => {
    const value = evaluateDeficitDifficulty(input(3, 600, patch))
    expect(value.nextCount).toBe(0)
    expect(value.proposal).toBe(null)
    expect(value.reason).toBe('missing_answers')
  })
  it('a non-difficult regular resets; early preserves without evaluating a14day window', () => {
    expect(
      evaluateDeficitDifficulty(input(4, 600, { hunger: 'pouca', energy: 'boa' })),
    ).toMatchObject({ nextCount: 0, proposal: null })
    const value = input(1)
    value.form = { ...value.form, kind: 'EARLY_FULL' }
    expect(evaluateDeficitDifficulty(value)).toMatchObject({
      status: 'not_evaluated',
      nextCount: 1,
      proposal: null,
    })
  })
  it('HOLD preserves counting and suppresses the calorie step; None does not clear it', () => {
    const value = input(1)
    value.safety = { ...safety, hold: { active: true, items: ['reduced_intake'] } } as typeof safety
    expect(evaluateDeficitDifficulty(value)).toMatchObject({
      nextCount: 2,
      proposal: null,
      reason: 'safety',
    })
  })
  it('pending health risk also prevents proposal before durable declaration is supplied', () => {
    expect(
      evaluateDeficitDifficulty(
        input(1, 600, { healthCheck: { kind: 'risks', items: ['reduced_intake'] } }),
      ),
    ).toMatchObject({ proposal: null, reason: 'safety' })
  })
  it('a confirmed higher-priority choice suppresses n2 while retaining the observed count', () => {
    expect(
      evaluateDeficitDifficulty({ ...input(1), higherPriorityDecisionConfirmed: true }),
    ).toMatchObject({
      nextCount: 2,
      proposal: null,
      reason: 'higher_priority_decision',
    })
  })
  it.each([
    { bodyFatPercent: 10 },
    { weightKg: 50 },
    { birthDate: '2010-01-01' },
    { hold: { active: true, items: ['pregnant_or_breastfeeding'] } },
    { hold: { active: true, items: ['reduced_intake'] } },
  ])('paused clinical context suppresses n2 guidance while keeping difficulty facts %#', (patch) => {
    const candidate = { ...safety, ...patch }
    for (const missingEnergy of [false, true]) {
      const value = input(1, 600, {
        weightKg: candidate.weightKg,
        ...(missingEnergy ? { energy: null } : {}),
      })
      const result = evaluateDeficitDifficulty({ ...value, safety: candidate })
      expect(result.guidance).toBe(false)
      expect(result.proposal).toBe(null)
      expect(result.nextCount).toBe(missingEnergy ? 0 : 2)
    }
  })
})
describe('n4 maintenance step and real episode ledger', () => {
  it.each([
    [8039, null],
    [8040, -100],
    [8080, -100],
    [8081, -200],
  ])('weight %s -> step %s', (weight, delta) => {
    const value = evaluatePhaseCalorieRule(
      context('manutencao', { history: weights(weight as number) }),
    )
    expect(value.proposal?.deltaKcal ?? null).toBe(delta)
  })
  it('Mais ou menos can pass n4; Pouco consistente cannot', () => {
    expect(
      evaluatePhaseCalorieRule(
        context('manutencao', { form: form('manutencao', { adherence: 'mais_ou_menos' }) }),
      ),
    ).toHaveProperty('proposal.deltaKcal', -100)
    expect(
      evaluatePhaseCalorieRule(
        context('manutencao', { form: form('manutencao', { adherence: 'pouco_consistente' }) }),
      ),
    ).toMatchObject({ proposal: null, reason: 'adherence' })
  })
  it('stable plus Muita AND Baixa proposes+100, falling never does', () => {
    const f = form('manutencao', { hunger: 'muita', energy: 'baixa' })
    expect(
      evaluatePhaseCalorieRule(context('manutencao', { form: f, history: weights(8000) })),
    ).toHaveProperty('proposal.deltaKcal', 100)
    expect(
      evaluatePhaseCalorieRule(context('manutencao', { form: f, history: weights(7960) })),
    ).toHaveProperty('proposal', null)
  })
  it.each([
    { hunger: 'muita' },
    { energy: 'baixa' },
    { difficultToMaintain: 'sim' },
  ])('rising weight cannot reduce with veto %#', (patch) => {
    expect(
      evaluatePhaseCalorieRule(context('manutencao', { form: form('manutencao', patch) })),
    ).toHaveProperty('proposal', null)
  })
  it.each([
    'hunger',
    'energy',
    'adherence',
    'difficultToMaintain',
  ])('unknown %s does not become favorable for reduction', (key) => {
    expect(
      evaluatePhaseCalorieRule(
        context('manutencao', { form: form('manutencao', { [key]: null }) }),
      ),
    ).toMatchObject({ status: 'missing', proposal: null })
  })
  it('needs R+14, skips transition and prevents a second main decision', () => {
    for (const patch of [
      { maintenanceSince: '2026-10-15' },
      { transitionActive: true },
      { higherPriorityDecisionConfirmed: true },
      { activityChangedThisCycle: true },
    ])
      expect(evaluatePhaseCalorieRule(context('manutencao', patch))).toHaveProperty(
        'proposal',
        null,
      )
    expect(evaluatePhaseCalorieRule(context())).toHaveProperty('proposal.deltaKcal', -100)
  })
  it('no partial maintenance step at floor and no partial cap step', () => {
    expect(
      evaluatePhaseCalorieRule(context('manutencao', { currentTargetKcal: 2050, floorKcal: 2000 })),
    ).toMatchObject({ proposal: null, reason: 'floor' })
    expect(
      evaluatePhaseCalorieRule(
        context('manutencao', { history: weights(8081), ledgerSteps: [-100] }),
      ),
    ).toMatchObject({ proposal: null, reason: 'cap' })
    expect(
      evaluatePhaseCalorieRule(context('manutencao', { ledgerSteps: [100, -100] })),
    ).toMatchObject({ proposal: null, reason: 'cap' })
  })
})
describe('n16 gain conditions and real clipped decrease', () => {
  it('did not rise, stuck, Muita+Baixa and no perceived fat proposes+150', () => {
    expect(
      evaluatePhaseCalorieRule(
        context('ganho_massa', {
          history: weights(8000),
          form: form('ganho_massa', { hunger: 'muita', energy: 'baixa' }),
        }),
      ),
    ).toHaveProperty('proposal.deltaKcal', 150)
  })
  it('above0.5% permits-150; floor clips to actual-138 and ledger records138', () => {
    const value = evaluatePhaseCalorieRule(
      context('ganho_massa', { history: weights(8041), currentTargetKcal: 2897, floorKcal: 2759 }),
    )
    expect(value.proposal).toMatchObject({ deltaKcal: -138, targetKcal: 2759, ledgerAbsAfter: 138 })
    expect(
      evaluatePhaseCalorieRule(context('ganho_massa', { history: weights(8040) })),
    ).toHaveProperty('proposal', null)
  })
  it('unknown is not NOT(Muita AND Baixa)', () => {
    for (const key of [
      'hunger',
      'energy',
      'strengthProgression',
      'strengthSessions',
      'adherence',
      'healthCheck',
    ])
      expect(
        evaluatePhaseCalorieRule(
          context('ganho_massa', {
            history: weights(8041),
            form: form('ganho_massa', { [key]: null }),
          }),
        ),
      ).toMatchObject({ status: 'missing', proposal: null })
  })
  it('known Muita+Baixa keeps target above range, never reduces', () => {
    expect(
      evaluatePhaseCalorieRule(
        context('ganho_massa', {
          history: weights(8041),
          form: form('ganho_massa', { hunger: 'muita', energy: 'baixa' }),
        }),
      ),
    ).toHaveProperty('proposal', null)
  })
  it('baseline is max(start,profile), no session-to-calorie rule, no+150 after+150 cap', () => {
    expect(
      evaluatePhaseCalorieRule(context('ganho_massa', { profileStrengthFrequency: 5 })),
    ).toMatchObject({ proposal: null, reason: 'training_baseline' })
    expect(
      evaluatePhaseCalorieRule(context('ganho_massa', { gainStartFrequency: 5 })),
    ).toMatchObject({ proposal: null, reason: 'training_baseline' })
    expect(
      evaluatePhaseCalorieRule(
        context('ganho_massa', {
          history: weights(8000),
          form: form('ganho_massa', { hunger: 'muita', energy: 'baixa' }),
          ledgerSteps: [150],
        }),
      ),
    ).toMatchObject({ proposal: null, reason: 'cap' })
  })
  it('at floor no decrease and any active n17 limit withholds step', () => {
    expect(
      evaluatePhaseCalorieRule(
        context('ganho_massa', { history: weights(8041), currentTargetKcal: 2000 }),
      ),
    ).toHaveProperty('proposal', null)
    expect(
      evaluatePhaseCalorieRule(
        context('ganho_massa', { history: weights(8041), gainStartBodyFatHundredths: 1500 }),
      ),
    ).toMatchObject({ proposal: null, reason: 'gain_limit' })
  })
})
describe('n17 three independent limits are facts, not an automatic phase switch', () => {
  const limit = (patch: Record<string, unknown> = {}) =>
    evaluateGainReviewLimits({
      sex: 'masculino',
      bodyFatHundredths: 1800,
      startBodyFatHundredths: 1500,
      bmi: 24,
      startBMI: 23,
      ...patch,
    })
  it.each([
    [1800, true],
    [1795, false],
  ])('male BF delta %s inclusive300', (bodyFatHundredths, on) => {
    expect(limit({ bodyFatHundredths }).active.includes('fat_increase')).toBe(on)
  })
  it('female400 inclusive; exactly1.5 BMI is not a limit; absolute BF independent of start', () => {
    expect(
      limit({ sex: 'feminino', startBodyFatHundredths: 2200, bodyFatHundredths: 2600 }).active,
    ).toContain('fat_increase')
    expect(limit({ startBMI: 22.5, bmi: 24 }).active).not.toContain('bmi_increase')
    expect(limit({ startBMI: 22.5, bmi: 24.000000002 }).active).toContain('bmi_increase')
    const value = limit({ startBodyFatHundredths: null, startBMI: null, bodyFatHundredths: 1901 })
    expect(value.active).toEqual(['fat_above_entry'])
    expect(value.notEvaluated).toEqual(['fat_increase', 'bmi_increase'])
    expect(value).not.toHaveProperty('newPhase')
  })
})
describe('context safety and purity', () => {
  it('A1/A2/HOLD and pending risks block target proposals', () => {
    for (const patch of [
      { bodyFatPercent: 10 },
      { weightKg: 50 },
      { hold: { active: true, items: ['professional_diet'] } },
    ]) {
      const s = { ...safety, ...patch }
      const f = form('manutencao', { weightKg: s.weightKg })
      expect(evaluatePhaseCalorieRule(context('manutencao', { safety: s, form: f }))).toMatchObject(
        { proposal: null, reason: 'safety' },
      )
    }
  })
  it('does not trust mismatched candidateweight/date or mutate inputs', () => {
    expect(() =>
      evaluatePhaseCalorieRule(context('manutencao', { safety: { ...safety, weightKg: 50 } })),
    ).toThrow()
    expect(() =>
      evaluatePhaseCalorieRule(
        context('manutencao', { history: { ...weights(), date: '2026-10-27' } }),
      ),
    ).toThrow()
    const input = context()
    const before = structuredClone(input)
    evaluatePhaseCalorieRule(input)
    expect(input).toEqual(before)
  })
})
