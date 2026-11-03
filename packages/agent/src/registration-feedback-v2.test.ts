import { buildDailyState } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import type { FlowClinicalPolicy } from './flow-current-clinical.js'
import {
  parseRegistrationFeedbackV2,
  prepareRegistrationFeedbackV2,
  type RegistrationFeedbackV2Input,
  renderRegistrationFeedbackV2,
} from './registration-feedback-v2.js'

const REGISTRATION = '10000000-0000-4000-8000-000000000001'
const LOG_A = '20000000-0000-4000-8000-000000000001'
const LOG_B = '20000000-0000-4000-8000-000000000002'
function policy(): FlowClinicalPolicy {
  return {
    version: 1,
    observed_at: '2026-11-03T18:00:00Z',
    assessment: 'complete',
    recording_allowed: true,
    pause_weight_loss_guidance: false,
    professional_assessment_recommended: false,
    phase_selection_pending: false,
    target_source: 'official_only',
    hide: { objective: false, calories: false, protein: false, balance: false, block: false },
  }
}
function day() {
  return buildDailyState({
    localDate: '2026-11-03',
    generatedAt: '2026-11-03T18:00:00Z',
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: 2400, protein_target: 150 },
    programmedDeficitKcal: 500,
    snapshot: {
      caloriesConsumed: 1785,
      caloriesTarget: 2400,
      proteinG: 126,
      proteinTarget: 150,
      carbsG: 180,
      fatG: 45,
      exerciseCalories: 504,
      waterConsumedMl: 1000,
      protocol: 'recomposicao',
      dayClosed: false,
      dayStatus: null,
      updatedAt: '2026-11-03T18:00:00Z',
    },
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
    progress: { deficitBlock: 3120, blocksCompleted: 2, updatedAt: null },
  })
}
function input(): RegistrationFeedbackV2Input {
  return {
    registrationId: REGISTRATION,
    localDate: '2026-11-03',
    locale: 'pt-BR',
    policy: policy(),
    officialDay: day(),
    preferencesKnown: false,
    registration: {
      kind: 'meal',
      meal_kind: 'cafe',
      items: [
        {
          log_id: LOG_A,
          food_name: 'leite integral',
          quantity_g: 206,
          quantity: {
            value: 200,
            unit: 'mL',
            estimated: true,
            reference_id: 'fao-infoods-v2-whole-milk-tb',
          },
          kcal: 126,
          protein_g: 6.3,
          carbs_g: 9.5,
          fat_g: 6.5,
          nutrition_source: 'canonical_exact',
        },
        {
          log_id: LOG_B,
          food_name: 'whey protein',
          quantity_g: 30,
          quantity: {
            value: 1,
            unit: 'scoop',
            estimated: true,
            reference_id: 'app-household-whey-scoop-v1',
          },
          kcal: 120,
          protein_g: 23.6,
          carbs_g: 4,
          fat_g: 1.5,
          nutrition_source: 'canonical_exact',
        },
      ],
      totals: { kcal: 246, protein_g: 29.9, carbs_g: 13.5, fat_g: 8 },
    },
  }
}
const render = (value: ReturnType<typeof prepareRegistrationFeedbackV2>) =>
  renderRegistrationFeedbackV2(value)
    .map((section) => section.text)
    .join('\n\n')

function itemAt(registration: RegistrationFeedbackV2Input['registration'], index: number) {
  if (registration.kind !== 'meal') throw new Error('Fixture')
  const item = registration.items[index]
  if (!item) throw new Error('Fixture item missing')
  return item
}

describe('conversational feedback v2 canonical presentation', () => {
  it('shows the six approved sections, per-item amounts and official day facts in order', () => {
    const feedback = prepareRegistrationFeedbackV2(input())
    expect(feedback.schema).toBe('registration.feedback.v2')
    expect(feedback.assistant).toBe('Flow AI')
    expect(renderRegistrationFeedbackV2(feedback).map((section) => section.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    const text = render(feedback)
    expect(text).toContain('Café da manhã registrado')
    expect(text).toContain('leite integral · 200 mL')
    expect(text).toContain('whey protein · 1 medida')
    expect(text).toContain('29,9 g')
    expect(text).toContain('74,4%')
    expect(text).toContain('84%')
    expect(text).toContain('615 kcal')
    expect(text).not.toContain('1.119 kcal')
    expect(text).toContain('3.120 / 7.700 kcal')
    expect(text).toContain('já consolidado')
    expect(text).toContain('não aumenta')
    expect(feedback.education).toMatchObject({
      status: 'available',
      provenance: {
        source: 'reviewed_template',
        catalog_version: 'registration.education.v1',
        template_id: 'milk_whey',
      },
    })
    expect(text).not.toMatch(
      /sou (?:o )?(?:dr|doutor)|sou nutricionista|perdeu .*kg|garante perda/iu,
    )
    expect(text).toContain('não cria crédito imediato nem garante')
  })
  it('preserves canonical decimal totals and never calculates a block credit for the event', () => {
    const request = input()
    if (request.registration.kind !== 'meal') throw new Error('Fixture')
    request.registration.items.forEach((row, index) => {
      row.kcal = index ? 0.2 : 0.1
    })
    request.registration.totals.kcal = 0.3
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.registration.kind === 'meal' && feedback.registration.totals.kcal).toBe(0.3)
    expect(feedback.block).toEqual({
      status: 'available',
      target_kcal: 7700,
      current_kcal: 3120,
      percentage: 41,
      completed_blocks: 2,
      total_credited_kcal: 18520,
    })
    expect(request.officialDay?.block_7700.current_kcal).toBe(3120)
  })
  it('renders a persisted activity independently from the aggregate exercise of the day', () => {
    const request = input()
    request.registration = {
      kind: 'workout',
      log_id: LOG_A,
      workout_type: 'caminhada',
      duration_min: 30,
      intensity: 'moderada',
      estimated_kcal: 123,
    }
    const feedback = prepareRegistrationFeedbackV2(request)
    const sections = renderRegistrationFeedbackV2(feedback)
    expect(sections[1]?.text).toContain('30 min')
    expect(sections[1]?.text).toContain('moderada')
    expect(sections[2]?.text).toContain('123 kcal')
    expect(sections[2]?.text).not.toContain('504')
    expect(feedback.education).toMatchObject({ provenance: { template_id: 'activity_walking' } })
  })
  it('keeps missing activity facts unavailable rather than manufacturing zero', () => {
    const request = input()
    request.registration = {
      kind: 'workout',
      log_id: LOG_A,
      workout_type: 'atividade livre',
      duration_min: null,
      intensity: null,
      estimated_kcal: null,
    }
    const sections = renderRegistrationFeedbackV2(prepareRegistrationFeedbackV2(request))
    expect(sections[2]?.text).toContain('indisponível')
    expect(sections[2]?.text).not.toContain('0 kcal')
  })
  it.each([
    'calories_kcal',
    'protein_g',
  ] as const)('omits a percentage when %s has no official target', (key) => {
    const request = input()
    if (!request.officialDay) throw new Error('Fixture')
    request.officialDay.targets[key] = null
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.day?.targets[key]).toBeNull()
    expect(
      key === 'calories_kcal' ? feedback.day?.calorie_percentage : feedback.day?.protein_percentage,
    ).toBeNull()
    expect(render(feedback)).toContain('Meta indisponível')
  })
  it('requires official provenance independently for each target', () => {
    const request = input()
    if (!request.officialDay) throw new Error('Fixture')
    request.officialDay.targets.calories_source = 'profile_calculation'
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.day?.targets.calories_kcal).toBeNull()
    expect(feedback.day?.calorie_percentage).toBeNull()
    expect(feedback.day?.targets.protein_g).toBe(150)
    expect(feedback.day?.protein_percentage).toBe(84)
    expect(feedback.day?.remaining_food_kcal).toBeNull()
  })
  it('hides protected guidance but preserves confirmed item and consumed facts', () => {
    const request = input()
    if (!request.policy) throw new Error('Fixture')
    request.policy.pause_weight_loss_guidance = true
    request.policy.hide = {
      objective: true,
      calories: true,
      protein: true,
      balance: true,
      block: true,
    }
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.guidance).toBe('paused')
    expect(feedback.day?.targets).toEqual({ calories_kcal: null, protein_g: null })
    expect(feedback.day?.consumed.calories_kcal).toBe(1785)
    expect(feedback.day?.current_protocol).toBeNull()
    expect(feedback.block).toEqual({ status: 'protected' })
    expect(feedback.education).toMatchObject({ provenance: { template_id: 'clinical_pause' } })
    expect(render(feedback)).toContain('avaliação profissional')
    expect(render(feedback)).not.toMatch(/74,4%|3\.120|fechar o bloco|reduza|emagre/iu)
  })
  it.each([
    'date',
    'source',
    'missing-policy',
  ] as const)('retains a saved record with unavailable %s context', (reason) => {
    const request = input()
    if (!request.officialDay) throw new Error('Fixture')
    if (reason === 'date') request.officialDay.local_date = '2026-11-04'
    if (reason === 'source') request.officialDay.consumed.source = 'empty_day'
    if (reason === 'missing-policy') request.policy = null
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.day).toBeNull()
    expect(feedback.block).toEqual({ status: 'unavailable' })
    expect(render(feedback)).toContain('Café da manhã registrado')
    expect(render(feedback)).not.toContain('74,4%')
  })
  it('does not show recomposition progress for another objective or a missing progress source', () => {
    const request = input()
    if (!request.officialDay) throw new Error('Fixture')
    request.officialDay.current_protocol = 'manutencao'
    expect(prepareRegistrationFeedbackV2(request).block).toEqual({ status: 'not_applicable' })
    request.officialDay.current_protocol = 'recomposicao'
    request.officialDay.block_7700.source = 'unavailable'
    expect(prepareRegistrationFeedbackV2(request).block).toEqual({ status: 'unavailable' })
  })
  it('does not encourage completing a block when only the block is clinically hidden', () => {
    const request = input()
    if (!request.policy) throw new Error('Fixture')
    request.policy.hide.block = true
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.block).toEqual({ status: 'protected' })
    expect(feedback.education.status === 'available' && feedback.education.text).not.toMatch(
      /bloco|crédito/iu,
    )
  })
  it('omits an inconsistent optional block without losing the saved record or day', () => {
    const request = input()
    if (!request.officialDay) throw new Error('Fixture')
    request.officialDay.block_7700.total_credited_kcal = 19024
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.block).toEqual({ status: 'unavailable' })
    expect(feedback.day?.consumed.calories_kcal).toBe(1785)
    expect(render(feedback)).toContain('Café da manhã registrado')
  })
  it('keeps education optional and deterministic without registration side effects', () => {
    const request = input()
    request.educationAvailable = false
    expect(prepareRegistrationFeedbackV2(request).education).toEqual({ status: 'unavailable' })
    expect(render(prepareRegistrationFeedbackV2(request))).toContain('Café da manhã registrado')
    request.educationAvailable = true
    request.preferencesKnown = true
    const before = structuredClone(request)
    const first = prepareRegistrationFeedbackV2(request)
    expect(prepareRegistrationFeedbackV2(request)).toEqual(first)
    expect(request).toEqual(before)
    expect(render(first)).toContain('preferências que você já informou')
    expect(first.education).toMatchObject({ provenance: { preferences_known: true } })
  })
  it('renders English with the same facts and an AI identity', () => {
    const request = input()
    request.locale = 'en-US'
    const text = render(prepareRegistrationFeedbackV2(request))
    expect(text).toContain('Breakfast recorded')
    expect(text).toContain('1 scoop')
    expect(text).toContain('74.4%')
    expect(text).toContain('29.9 g')
  })
  it('explains which actual items contribute energy and protein rather than generic praise', () => {
    const request = input()
    if (request.registration.kind !== 'meal') throw new Error('Fixture')
    itemAt(request.registration, 0).food_name = 'arroz branco cozido'
    itemAt(request.registration, 1).food_name = 'frango grelhado'
    const feedback = prepareRegistrationFeedbackV2(request)
    expect(feedback.education.status === 'available' && feedback.education.text).toContain(
      'arroz branco cozido',
    )
    expect(feedback.education.status === 'available' && feedback.education.text).toContain(
      'frango grelhado',
    )
  })
})

describe('feedback v2 closed receipt boundary', () => {
  const identity = { registrationId: REGISTRATION, kind: 'meal' as const }
  it('roundtrips a closed receipt without private observation authority', () => {
    const feedback = prepareRegistrationFeedbackV2(input())
    expect(parseRegistrationFeedbackV2(JSON.parse(JSON.stringify(feedback)), identity)).toEqual(
      feedback,
    )
    const raw = JSON.stringify(feedback)
    expect(raw).not.toMatch(
      /observed_at|health_state|profile_hash|user_id|target_source|usedTextKeys/,
    )
  })
  it.each([
    'extra',
    'wrong-owner-event',
    'wrong-kind',
    'percentage',
    'education-text',
    'duplicate-log',
    'unresolved',
    'zero-quantity',
    'infinite',
    'block',
  ] as const)('rejects %s without normalizing unknown fields', (attack) => {
    const feedback = prepareRegistrationFeedbackV2(input())
    if (
      feedback.registration.kind !== 'meal' ||
      !feedback.day ||
      feedback.education.status !== 'available'
    )
      throw new Error('Fixture')
    const row = itemAt(feedback.registration, 0)
    let value: unknown = feedback
    if (attack === 'extra') value = { ...feedback, private_authority: 'secret' }
    if (attack === 'wrong-owner-event') feedback.registration_id = LOG_A
    if (attack === 'percentage') feedback.day.calorie_percentage = 99
    if (attack === 'education-text') feedback.education.text = 'Sou o Dr. Roberto. Reduza 900 kcal.'
    if (attack === 'duplicate-log') itemAt(feedback.registration, 1).log_id = row.log_id
    if (attack === 'unresolved') row.nutrition_source = 'no_match'
    if (attack === 'zero-quantity') row.quantity.value = 0
    if (attack === 'infinite') row.kcal = Number.POSITIVE_INFINITY
    if (attack === 'block' && feedback.block.status === 'available')
      feedback.block.total_credited_kcal += 504
    expect(() =>
      parseRegistrationFeedbackV2(
        value,
        attack === 'wrong-kind' ? { ...identity, kind: 'workout' } : identity,
      ),
    ).toThrow()
  })
})
