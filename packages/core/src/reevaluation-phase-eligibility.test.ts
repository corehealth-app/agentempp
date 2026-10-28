import { describe, expect, it } from 'vitest'
import { DEFAULT_CALC_CONFIG } from './calc-config.js'
import { parseReevaluationFormDraft } from './reevaluation-form-contracts.js'
import {
  decideReevaluationComposition,
  evaluateMaintenanceChoices,
  evaluateRecompositionReviewOptions,
} from './reevaluation-phase-eligibility.js'

it('keeps health-only FULL outside all planned phase choice evaluators', () => {
  const healthForm = parseReevaluationFormDraft({
    version: 1,
    phase: null,
    kind: 'REGULAR',
    activityPurpose: 'normal',
    answers: {},
    noPlanOrigin: {
      kind: 'confirmed_no_plan',
      signupGeneration: 'b3b01000-0000-4000-8000-000000002800',
      signupEpoch: 'b3b01000-0000-4000-8000-000000002801',
      completedAt: '2026-10-25T12:00:00.000001Z',
    },
  })
  expect(() => evaluateMaintenanceChoices({ ...input(), form: healthForm })).toThrow()
  expect(() => evaluateRecompositionReviewOptions({ ...input(), form: healthForm })).toThrow()
})

const safety = {
  date: '2026-10-29',
  birthDate: '1990-01-01',
  weightKg: 80,
  heightCm: 180,
  bodyFatPercent: 18,
  hold: { active: false, items: [] },
}
function form(patch: Record<string, unknown> = {}) {
  return {
    version: 1,
    phase: 'manutencao',
    kind: 'REGULAR',
    activityPurpose: 'normal',
    answers: {
      weightKg: 80,
      strengthSessions: 4,
      adherence: 'bem_consistente',
      hunger: 'moderada',
      energy: 'ok',
      difficultToMaintain: 'nao',
      healthCheck: { kind: 'none' },
      ...patch,
    },
  }
}
const composition = (overrides: Record<string, unknown> = {}) => ({
  sex: 'masculino',
  heightCm: 180,
  weightKg: 80,
  bodyFat: { kind: 'confirmed_photo', hundredths: 1800 },
  sessions: 4,
  ...overrides,
})
function history() {
  return {
    date: safety.date,
    asOf: '2026-10-29T23:59:59.999999Z',
    measurements: [-27, -24, -21, -20, -17, -14, -13, -10, -7, -6, -3, 0].map((offset, index) => {
      const date = new Date(Date.UTC(2026, 9, 29 + offset)).toISOString().slice(0, 10)
      return {
        id: `bbbbbbbb-bbbb-4bbb-8bbb-${String(index).padStart(12, '0')}`,
        localDate: date,
        measuredAt: `${date}T12:00:00.000000Z`,
        weightHundredths: 8000,
      }
    }),
  }
}
function input(overrides: Record<string, unknown> = {}) {
  return {
    form: form(),
    safety,
    composition: composition(),
    history: history(),
    maintenanceSince: '2026-10-01',
    transitionActiveOrPaused: false,
    priorFulls: [
      {
        id: 'cccccccc-cccc-4ccc-8ccc-000000000001',
        kind: 'REGULAR',
        date: '2026-10-15',
        adherence: 'bem_consistente',
        energy: 'boa',
      },
      {
        id: 'cccccccc-cccc-4ccc-8ccc-000000000002',
        kind: 'EARLY_FULL',
        date: '2026-10-20',
        adherence: null,
        energy: 'baixa',
      },
    ],
    ...overrides,
  }
}

describe('n9 one composition cut with explicit manual/photo provenance', () => {
  it.each([
    'confirmed_photo',
    'manual_report',
  ])('n39 keeps gain closed at BMI26 even with a low %s percentage', (kind) => {
    expect(
      decideReevaluationComposition(
        composition({ weightKg: 84.24, bodyFat: { kind, hundredths: 1500 } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({
      aboveCut: false,
      gainAvailable: false,
      gainReasons: ['composition'],
    })
  })
  it.each([
    [100, false],
    [99.99, true],
  ])('n39 compares unrounded BMI at 200 cm and %s kg without a photo exception', (weightKg, gainAvailable) => {
    expect(
      decideReevaluationComposition(
        composition({
          heightCm: 200,
          weightKg,
          bodyFat: { kind: 'confirmed_photo', hundredths: 1500 },
        }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ gainAvailable })
  })
  it('n39 does not round a mathematically exact BMI25 below its cut at 160 cm', () => {
    expect(
      decideReevaluationComposition(
        composition({
          heightCm: 160,
          weightKg: 64,
          bodyFat: { kind: 'confirmed_photo', hundredths: 1500 },
        }),
        DEFAULT_CALC_CONFIG,
      ).gainAvailable,
    ).toBe(false)
  })
  it.each([
    ['masculino', 2000, true, false],
    ['masculino', 1999, false, false],
    ['masculino', 1900, false, true],
    ['feminino', 2800, true, false],
    ['feminino', 2750, false, false],
    ['feminino', 2700, false, true],
  ])('%s report %s hundredths uses the inclusive cut and gain entry', (sex, hundredths, aboveCut, gainAvailable) => {
    expect(
      decideReevaluationComposition(
        composition({ sex, bodyFat: { kind: 'manual_report', hundredths } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ aboveCut, gainAvailable })
  })
  it('manual BF below cut with BMI26 keeps choice but closes gain, with no reassignment', () => {
    expect(
      decideReevaluationComposition(
        composition({ weightKg: 84.24, bodyFat: { kind: 'manual_report', hundredths: 1500 } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({
      aboveCut: false,
      manualDisagreement: true,
      gainAvailable: false,
      gainReasons: ['composition'],
    })
  })
  it('preserves photo provenance without opening the disabled n39 BMI exception', () => {
    expect(
      decideReevaluationComposition(
        composition({ weightKg: 84.24, bodyFat: { kind: 'confirmed_photo', hundredths: 1500 } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ aboveCut: false, manualDisagreement: false, gainAvailable: false })
  })
  it('uses raw BMI with the existing tolerance only when no BF decides the cut', () => {
    expect(
      decideReevaluationComposition(
        composition({ heightCm: 160, weightKg: 64, bodyFat: { kind: 'absent' } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ aboveCut: true, gainAvailable: false })
    expect(
      decideReevaluationComposition(
        composition({ heightCm: 200, weightKg: 99.96, bodyFat: { kind: 'absent' } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ aboveCut: false, gainAvailable: true })
  })
  it('unknown strength is named and cannot become a favorable zero/default', () => {
    expect(
      decideReevaluationComposition(composition({ sessions: null }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({ aboveCut: false, gainAvailable: false, gainReasons: ['sessions_unknown'] })
  })
})

describe('n6/n19 maintenance choices require genuine four-week evidence and two regular windows', () => {
  it('offers gain and hunger-based recomposition at R+28, skipping early reviews', () => {
    expect(evaluateMaintenanceChoices(input(), DEFAULT_CALC_CONFIG)).toEqual({
      status: 'offered',
      reasons: [],
      gain: { available: true, reasons: [] },
      recomposition: { available: true, deficitLevel: 500, reasons: [] },
    })
  })
  it.each([
    ['muita', 400],
    ['moderada', 500],
    ['pouca', 600],
  ] as const)('hunger %s selects deficit %s only in an offer', (hunger, deficitLevel) => {
    expect(
      evaluateMaintenanceChoices(input({ form: form({ hunger }) }), DEFAULT_CALC_CONFIG)
        .recomposition,
    ).toEqual({ available: true, deficitLevel, reasons: [] })
  })
  it('unknown hunger withholds only recomposition while other fully evidenced criteria can still offer gain', () => {
    expect(
      evaluateMaintenanceChoices(input({ form: form({ hunger: null }) }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({
      status: 'offered',
      gain: { available: true },
      recomposition: { available: false, deficitLevel: null, reasons: ['hunger_unknown'] },
    })
  })
  it('never replaces missing individual history with the two review-end weights', () => {
    expect(
      evaluateMaintenanceChoices(
        input({ history: { ...history(), measurements: history().measurements.slice(-2) } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({
      status: 'missing',
      reasons: ['weightHistory'],
      gain: { available: false },
      recomposition: { available: false },
    })
  })
  it('requires R+28 even with four apparently stable weeks', () => {
    expect(
      evaluateMaintenanceChoices(input({ maintenanceSince: '2026-10-02' }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({ status: 'not_offered', reasons: ['before_R_plus_28'] })
  })
  it('requires the previous regular fortnight to start on or after R', () => {
    const value = input()
    const previous = value.priorFulls.find((review) => review.kind === 'REGULAR')
    if (!previous) throw new Error('Missing regular fixture')
    previous.date = '2026-10-13'
    expect(evaluateMaintenanceChoices(value, DEFAULT_CALC_CONFIG)).toMatchObject({
      status: 'not_offered',
      reasons: ['regular_window_before_R'],
    })
  })
  it.each([
    ['adherence', 'mais_ou_menos', 'regular_adherence'],
    ['energy', 'baixa', 'regular_energy'],
    ['energy', null, 'regular_energy_unknown'],
  ])('checks the latest REGULAR %s, not the early review or an older favorable one', (key, value, reason) => {
    const current = input()
    const previous = current.priorFulls.find((review) => review.kind === 'REGULAR')
    if (!previous) throw new Error('Missing regular fixture')
    Object.assign(previous, { [key]: value })
    expect(evaluateMaintenanceChoices(current, DEFAULT_CALC_CONFIG)).toMatchObject({
      reasons: [reason],
      gain: { available: false },
      recomposition: { available: false },
    })
  })
  it('does not turn a current unknown/opt-out into good energy or explicit health none', () => {
    for (const patch of [{ energy: null }, { healthCheck: null }, { adherence: null }]) {
      expect(
        evaluateMaintenanceChoices(input({ form: form(patch) }), DEFAULT_CALC_CONFIG).status,
      ).toBe('missing')
    }
  })
  it('a draft risk cannot bypass the still-inactive stored HOLD projection', () => {
    expect(
      evaluateMaintenanceChoices(
        input({ form: form({ healthCheck: { kind: 'risks', items: ['reduced_intake'] } }) }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ status: 'blocked', reasons: ['safety'] })
  })
  it('active or paused transition closes every new phase offer', () => {
    expect(
      evaluateMaintenanceChoices(input({ transitionActiveOrPaused: true }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({ status: 'blocked', reasons: ['transition'] })
  })
  it('EARLY_FULL is not a regular endpoint and cannot open these choices', () => {
    expect(
      evaluateMaintenanceChoices(
        input({ form: { ...form(), kind: 'EARLY_FULL' } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ status: 'not_offered', reasons: ['review_kind_or_phase'] })
  })
  it('checks current strength for gain only, without making it a calorie penalty', () => {
    expect(
      evaluateMaintenanceChoices(
        input({ form: form({ strengthSessions: 2 }), composition: composition({ sessions: 2 }) }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({
      gain: { available: false, reasons: ['training'] },
      recomposition: { available: true },
    })
  })
  it('cannot reuse composition/history facts belonging to another candidate or date', () => {
    expect(() =>
      evaluateMaintenanceChoices(
        input({ composition: composition({ weightKg: 81 }) }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toThrow()
    expect(() =>
      evaluateMaintenanceChoices(
        input({ history: { ...history(), date: '2026-10-30' } }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toThrow()
  })
  it('at/above cut follows n38-B separately, never changes phase by this eligibility check', () => {
    expect(
      evaluateMaintenanceChoices(
        input({
          safety: { ...safety, bodyFatPercent: 22 },
          composition: composition({ bodyFat: { kind: 'confirmed_photo', hundredths: 2200 } }),
        }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ status: 'not_offered', reasons: ['composition_cut_use_n38_B'] })
  })
})

describe('n38 review-specific choices, never automatic phase changes', () => {
  function route(overrides: Record<string, unknown> = {}) {
    return {
      form: form(),
      safety: { ...safety, bodyFatPercent: 22 },
      composition: composition({ bodyFat: { kind: 'confirmed_photo', hundredths: 2200 } }),
      maintenanceSince: '2026-10-15',
      transitionActiveOrPaused: false,
      measureConfirmed: true,
      ...overrides,
    }
  }
  function recompForm() {
    return { ...form({ difficultToMaintain: null }), phase: 'recomposicao' }
  }
  it('B1 can offer at R+14 without the 28-day or four-week gate, with a second confirmation', () => {
    expect(evaluateRecompositionReviewOptions(route(), DEFAULT_CALC_CONFIG)).toMatchObject({
      status: 'offered',
      proposal: {
        kind: 'recomposition_suggestion',
        deficitLevel: 500,
        requiresSecondConfirmation: true,
      },
    })
  })
  it.each([
    [{ maintenanceSince: '2026-10-16' }, 'before_R_plus_14'],
    [{ measureConfirmed: false }, 'measure_confirmation_required'],
    [{ form: form({ hunger: null }) }, 'hunger_unknown'],
    [{ transitionActiveOrPaused: true }, 'transition'],
    [{ form: { ...form(), kind: 'EARLY_FULL' } }, 'regular_required'],
  ])('names the B1 gate without a phase write %#', (overrides, reason) => {
    expect(evaluateRecompositionReviewOptions(route(overrides), DEFAULT_CALC_CONFIG)).toMatchObject(
      { reason, proposal: null },
    )
  })
  it('B2/manual disagreement makes no weight-based suggestion', () => {
    expect(
      evaluateRecompositionReviewOptions(
        route({
          safety: { ...safety, weightKg: 84.24, bodyFatPercent: 15 },
          form: form({ weightKg: 84.24 }),
          composition: composition({
            weightKg: 84.24,
            bodyFat: { kind: 'manual_report', hundredths: 1500 },
          }),
        }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ status: 'not_offered', reason: 'manual_disagreement', proposal: null })
  })
  it('offers the transition in recomposition only below the composition cut', () => {
    expect(
      evaluateRecompositionReviewOptions(route({ form: recompForm() }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({
      status: 'not_offered',
      reason: 'at_or_above_composition_cut',
      proposal: null,
    })
    expect(
      evaluateRecompositionReviewOptions(
        route({ form: recompForm(), safety, composition: composition() }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({
      status: 'offered',
      proposal: { kind: 'maintenance_transition', requiresActivityConfirmation: true },
    })
  })
  it('safety remains first even when the cut would permit maintenance', () => {
    expect(
      evaluateRecompositionReviewOptions(
        route({
          form: recompForm(),
          safety: { ...safety, bodyFatPercent: 10 },
          composition: composition({ bodyFat: { kind: 'confirmed_photo', hundredths: 1000 } }),
        }),
        DEFAULT_CALC_CONFIG,
      ),
    ).toMatchObject({ status: 'blocked', reason: 'safety', proposal: null })
  })
  it('refuses the direct gain-to-recomposition path', () => {
    const gain = { ...form({ difficultToMaintain: null }), phase: 'ganho_massa' }
    expect(
      evaluateRecompositionReviewOptions(route({ form: gain }), DEFAULT_CALC_CONFIG),
    ).toMatchObject({
      status: 'not_offered',
      reason: 'direct_phase_path_forbidden',
      proposal: null,
    })
  })
})
