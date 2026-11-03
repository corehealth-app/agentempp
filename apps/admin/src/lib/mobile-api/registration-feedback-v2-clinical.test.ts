import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { auth, context, day, fixtureFirst, other, owner } from './__fixtures__/feedback-v2-source'
import type { CurrentClinicalReaderSources } from './current-clinical-read-model'
import {
  loadFeedbackV2ClinicalContext,
  proveFeedbackV2Day,
} from './registration-feedback-v2-clinical'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

const who = { userId: owner, registrationId: context().registration_id, kind: 'meal' as const }
const observation = () => parseFeedbackV2Capture(context(), who)
function harness() {
  const source = { capture: vi.fn(async () => context().clinical) }
  const unused = vi.fn(async () => {
    throw new Error('Unrelated reader was called')
  })
  const readers: CurrentClinicalReaderSources = {
    today: vi.fn(async () => day()),
    progress: unused,
    plan: unused,
    profile: unused,
    trends: unused,
  }
  const db = {
    rpc: vi.fn(async () => {
      throw new Error('Default RPC was called')
    }),
  } as unknown as ServiceClient
  return { source, readers, db, unused }
}
describe('feedback v2 read-only current clinical bridge', () => {
  it('uses the direct current model with two source captures, no admission or daily effect', async () => {
    const h = harness()
    const result = await loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)
    expect(result.policy).toMatchObject({
      assessment: 'complete',
      pause_weight_loss_guidance: false,
    })
    expect(result.officialDay).toMatchObject({
      local_date: '2026-11-03',
      consumed: { calories_kcal: 126 },
      targets: { calories_kcal: 1900, protein_g: 120 },
      remaining_food_kcal: 1774,
    })
    expect(h.source.capture).toHaveBeenCalledTimes(2)
    expect(h.source.capture).toHaveBeenCalledWith({ userId: owner, mode: 'profile' })
    expect(h.readers.today).toHaveBeenCalledTimes(1)
    expect(h.unused).not.toHaveBeenCalled()
    expect(h.db.rpc).not.toHaveBeenCalled()
  })
  it('binds every source observation to the original SQL capture, including body changes sharing the profile hash', async () => {
    const h = harness(),
      raw = context().clinical
    raw.body.weight_kg = 85
    h.source.capture.mockResolvedValue(raw)
    await expect(loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)).rejects.toThrow()
    expect(h.readers.today).not.toHaveBeenCalled()
  })
  it('refuses drift after the numeric read rather than falling back to an older policy', async () => {
    const h = harness(),
      changed = context().clinical
    changed.profile_hash = 'c'.repeat(64)
    h.source.capture.mockResolvedValueOnce(context().clinical).mockResolvedValueOnce(changed)
    await expect(loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)).rejects.toThrow()
    expect(h.readers.today).toHaveBeenCalledTimes(1)
  })
  it('rejects an observation predating the original capture even with the same stable binding', async () => {
    const h = harness(),
      raw = context().clinical
    raw.observed_at = raw.safety.observed_at = '2026-11-03T12:00:00.000000Z'
    h.source.capture.mockResolvedValue(raw)
    await expect(loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)).rejects.toThrow()
    expect(h.readers.today).not.toHaveBeenCalled()
  })
  it('accepts later clocks and context hashes while the complete stable observation remains identical', async () => {
    const h = harness(),
      raw = context().clinical
    raw.observed_at = raw.safety.observed_at = '2026-11-03T12:00:01.000001Z'
    raw.context_hash = 'c'.repeat(64)
    h.source.capture.mockResolvedValue(raw)
    expect(
      (await loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)).officialDay,
    ).not.toBeNull()
  })
  it('does not read a current day for a historical registration', async () => {
    const h = harness(),
      c = context()
    c.clinical.date = c.clinical.safety.date = '2026-11-04'
    c.clinical.observed_at = c.clinical.safety.observed_at = '2026-11-04T12:00:00.000001Z'
    const result = await loadFeedbackV2ClinicalContext(
      h.db,
      auth,
      parseFeedbackV2Capture(c, who),
      h,
    )
    expect(result.officialDay).toBeNull()
    expect(h.source.capture).not.toHaveBeenCalled()
    expect(h.readers.today).not.toHaveBeenCalled()
  })
  it.each([
    24, 10,
  ])('keeps incomplete observation with BF%s separate from a numeric target read', async (fat) => {
    const h = harness(),
      c = context()
    const raw = {
      ...c,
      clinical: {
        ...c.clinical,
        body: { ...c.clinical.body, weight_kg: null, body_fat_percent: fat },
        assessment: 'incomplete',
        missing: ['weight_kg'],
        safety: null,
      },
    }
    const value = await loadFeedbackV2ClinicalContext(
      h.db,
      auth,
      parseFeedbackV2Capture(raw, who),
      h,
    )
    expect(value.policy).toMatchObject({
      assessment: 'incomplete',
      pause_weight_loss_guidance: fat === 10,
    })
    expect(value.officialDay).toBeNull()
    expect(h.source.capture).not.toHaveBeenCalled()
    expect(h.readers.today).not.toHaveBeenCalled()
  })
  it('carries a current pause into v2 masking even when saved snapshot targets still exist', async () => {
    const h = harness(),
      c = context()
    c.clinical.body.body_fat_percent = 10
    c.clinical.safety.loss_guard = true
    h.source.capture.mockResolvedValue(c.clinical)
    const o = parseFeedbackV2Capture(c, who)
    const read = await loadFeedbackV2ClinicalContext(h.db, auth, o, h)
    const value = prepareRegistrationFeedbackV2({
      registrationId: who.registrationId,
      localDate: o.facts.localDate,
      locale: 'pt-BR',
      registration: o.facts.registration,
      policy: read.policy,
      officialDay: read.officialDay,
    })
    expect(value).toMatchObject({
      guidance: 'paused',
      day: { current_protocol: null, targets: { calories_kcal: null, protein_g: null } },
      block: { status: 'protected' },
    })
    expect(value.education).toMatchObject({ provenance: { template_id: 'clinical_pause' } })
  })
  it('keeps optional day unavailable after numeric reader failure without invoking a substitute reader', async () => {
    const h = harness()
    vi.mocked(h.readers.today).mockRejectedValue(new Error('private database detail'))
    const value = await loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)
    expect(value.officialDay).toBeNull()
    expect(value.policy).toMatchObject({ assessment: 'complete' })
    expect(h.unused).not.toHaveBeenCalled()
  })
  it('does not downgrade a clinical source failure to an available policy', async () => {
    const h = harness()
    h.source.capture.mockRejectedValue(new Error('private clinical provider detail'))
    await expect(loadFeedbackV2ClinicalContext(h.db, auth, observation(), h)).rejects.not.toThrow(
      /private/,
    )
  })
  it('refuses a changed authenticated owner before calling any data reader', async () => {
    const h = harness()
    await expect(
      loadFeedbackV2ClinicalContext(h.db, { ...auth, userId: other }, observation(), h),
    ).rejects.toThrow()
    expect(h.source.capture).not.toHaveBeenCalled()
  })
})
describe('feedback v2 official-day provenance', () => {
  it('retains independent snapshot targets and saved progress without adding exercise to food', () => {
    const d = proveFeedbackV2Day(observation(), day())
    expect(d?.remaining_food_kcal).toBe(1774)
    expect(d?.targets).toMatchObject({
      calories_source: 'daily_snapshot',
      protein_source: 'daily_snapshot',
    })
    expect(d?.block_7700).toMatchObject({ current_kcal: 500, completed_blocks: 2 })
  })
  it.each([
    'date',
    'consumed-source',
    'counter',
    'exercise',
    'missing-log',
    'duplicate-log',
    'calorie-target',
    'protein-target',
    'budget',
    'progress',
  ] as const)('withholds an incompatible optional day (%s)', (kind) => {
    const d = day()
    if (kind === 'date') d.local_date = '2026-11-04'
    if (kind === 'consumed-source') d.consumed.source = 'empty_day'
    if (kind === 'counter') d.consumed.protein_g = 99
    if (kind === 'exercise') d.exercise_kcal = 0
    if (kind === 'missing-log') d.meals = []
    if (kind === 'duplicate-log') d.meals.push({ ...fixtureFirst(d.meals) })
    if (kind === 'calorie-target') d.targets.calories_kcal = 2000
    if (kind === 'protein-target') d.targets.protein_g = 150
    if (kind === 'budget') d.remaining_food_kcal = 2278
    if (kind === 'progress') d.block_7700.current_kcal = 999
    expect(proveFeedbackV2Day(observation(), d)).toBeNull()
  })
  it('permits an independently unavailable target instead of substituting a formula', () => {
    const d = day()
    d.targets.calories_kcal = null
    d.targets.calories_source = 'unavailable'
    d.remaining_food_kcal = d.food_excess_kcal = null
    expect(proveFeedbackV2Day(observation(), d)?.targets.protein_g).toBe(120)
  })
})
