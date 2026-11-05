import { prepareRegistrationFeedbackV3 } from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { auth, day } from './__fixtures__/feedback-v2-source'
import { frozenMealV3Capture, pendingV3Capture } from './__fixtures__/feedback-v3-source'
import type { CurrentClinicalReaderSources } from './current-clinical-read-model'
import {
  loadFeedbackV3ClinicalContext,
  proveFeedbackV3Day,
} from './registration-feedback-v3-clinical'
import { parseFeedbackV3Capture } from './registration-feedback-v3-contracts'

function harness(unknown = false, frozen = false) {
  const f = frozen ? frozenMealV3Capture() : pendingV3Capture()
  f.context.snapshot.exercise_energy_complete = !unknown
  if (unknown && f.context.day_workouts)
    f.context.day_workouts.push({
      id: '60000000-0000-4000-8000-000000000001',
      user_id: f.who.userId,
      snapshot_id: f.context.snapshot.id,
      estimated_kcal: null,
    })
  const original = day()
  const observed = {
    ...original,
    calculation_version: 'bodyflow.daily-state.v4' as const,
    exercise_kcal: unknown ? null : original.exercise_kcal,
    exercise_energy: unknown
      ? { status: 'unavailable' as const, reason: 'unknown_workout_energy' as const }
      : { status: 'available' as const },
    daily_balance_kcal: unknown ? null : original.daily_balance_kcal,
    daily_balance_reference_kcal: unknown ? null : original.daily_balance_reference_kcal,
    daily_balance_includes_exercise: unknown ? null : original.daily_balance_includes_exercise,
    daily_balance_energy: unknown
      ? { status: 'unavailable' as const, reason: 'unknown_workout_energy' as const }
      : { status: 'available' as const },
  }
  const source = { capture: vi.fn(async () => f.context.clinical) }
  const unused = vi.fn(async () => {
    throw new Error('Unrelated reader/writer')
  })
  const readers: CurrentClinicalReaderSources = {
    today: unused,
    todayWithEnergy: vi.fn(async () => observed),
    progress: unused,
    plan: unused,
    profile: unused,
    trends: unused,
  }
  const db = { rpc: unused } as unknown as ServiceClient
  return {
    ...f,
    observed,
    source,
    readers,
    db,
    unused,
    observation: () => parseFeedbackV3Capture(f.context, f.who),
  }
}
describe('feedback v3 pinned energy-aware clinical bridge', () => {
  it('keeps official food/protein on an unknown-energy day through the direct v4 reader only', async () => {
    const h = harness(true)
    await expect(
      loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h),
    ).resolves.toMatchObject({
      officialDay: { consumed: { calories_kcal: 126, protein_g: 6.3 }, exercise_kcal: null },
    })
    expect(h.source.capture).toHaveBeenCalledTimes(2)
    expect(h.readers.todayWithEnergy).toHaveBeenCalledTimes(1)
    expect(h.unused).not.toHaveBeenCalled()
  })
  it('proves the complete/unknown state independently from the stored private numeric sum', () => {
    const h = harness(true),
      o = h.observation()
    expect(proveFeedbackV3Day(o, h.observed)?.exercise_kcal).toBeNull()
    expect(
      proveFeedbackV3Day(o, {
        ...h.observed,
        exercise_kcal: 0,
        exercise_energy: { status: 'available' },
      }),
    ).toBeNull()
    expect(
      proveFeedbackV3Day(o, {
        ...h.observed,
        consumed: { ...h.observed.consumed, calories_kcal: 9 },
      }),
    ).toBeNull()
  })
  it('does not substitute a legacy numeric reader when the explicit energy reader is missing', async () => {
    const h = harness(true)
    delete h.readers.todayWithEnergy
    expect(
      (await loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h)).officialDay,
    ).toBeNull()
    expect(h.unused).not.toHaveBeenCalled()
  })
  it('refuses current clinical drift after the day await rather than sealing an older policy', async () => {
    const h = harness(),
      changed = structuredClone(h.context.clinical)
    changed.profile_hash = 'c'.repeat(64)
    h.source.capture.mockResolvedValueOnce(h.context.clinical).mockResolvedValueOnce(changed)
    await expect(loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h)).rejects.toThrow()
    expect(h.readers.todayWithEnergy).toHaveBeenCalledTimes(1)
  })
  it('keeps factual intake with incomplete assessment while the v3 builder withholds unsupported goals', async () => {
    const h = harness(),
      raw = {
        ...h.context.clinical,
        body: { ...h.context.clinical.body, weight_kg: null },
        assessment: 'incomplete',
        missing: ['weight_kg'],
        safety: null,
      }
    Object.assign(h.context, { clinical: raw })
    Object.assign(h.context.source.capture, { clinical: raw })
    const o = h.observation(),
      clinical = await loadFeedbackV3ClinicalContext(h.db, auth, o, h)
    const value = prepareRegistrationFeedbackV3({
      registrationId: h.who.registrationId,
      localDate: o.localDate,
      registration: o.registration,
      locale: 'pt-BR',
      ...clinical,
    })
    expect(value).toMatchObject({
      guidance: 'unavailable',
      day: {
        consumed: { calories_kcal: 126, protein_g: 6.3 },
        targets: { calories_kcal: null, protein_g: null },
      },
    })
  })
})

it('keeps intake/exercise availability while the current clinical projector protects balance and goals', async () => {
  const h = harness(true)
  h.context.clinical.body.birth_date = '2010-01-01'
  h.context.clinical.safety.no_plan = true
  h.context.clinical.safety.hide_protein = true
  const o = h.observation(),
    clinical = await loadFeedbackV3ClinicalContext(h.db, auth, o, h)
  expect(clinical.officialDay).toMatchObject({
    consumed: { calories_kcal: 126 },
    targets: { calories_kcal: null, protein_g: null },
    daily_balance_energy: { status: 'protected' },
    exercise_kcal: null,
  })
  const f = prepareRegistrationFeedbackV3({
    registrationId: h.who.registrationId,
    localDate: o.localDate,
    registration: o.registration,
    locale: 'pt-BR',
    ...clinical,
  })
  expect(f).toMatchObject({
    guidance: 'paused',
    day: { consumed: { calories_kcal: 126, protein_g: 6.3 }, exercise_kcal: null },
    block: { status: 'protected' },
  })
})

it('keeps food facts while immutable pre-coverage meal source withholds later repaired exercise', async () => {
  const h = harness(false, true)
  delete (h.context.snapshot as Record<string, unknown>).exercise_energy_complete
  const value = await loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h)
  expect(value.officialDay).toMatchObject({
    consumed: { calories_kcal: 126, protein_g: 6.3 },
    exercise_kcal: null,
    exercise_energy: { status: 'unavailable', reason: 'source_unavailable' },
  })
})
it('does not rewrite frozen unknown energy after current correction to known zero', async () => {
  const h = harness(false, true)
  h.context.snapshot.exercise_energy_complete = false
  const value = await loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h)
  expect(value.officialDay).toMatchObject({
    consumed: { calories_kcal: 126 },
    exercise_kcal: null,
    exercise_energy: { status: 'unavailable', reason: 'unknown_workout_energy' },
  })
})
it('keeps original facts without a day enrichment when frozen clinical policy drifted', async () => {
  const h = harness(false, true),
    changed = structuredClone(h.context.clinical)
  changed.profile_hash = 'c'.repeat(64)
  h.source.capture.mockResolvedValue(changed)
  const value = await loadFeedbackV3ClinicalContext(h.db, auth, h.observation(), h)
  expect(value.officialDay).toBeNull()
  expect(value.policy.observed_at).toBe(h.context.clinical.observed_at)
})
