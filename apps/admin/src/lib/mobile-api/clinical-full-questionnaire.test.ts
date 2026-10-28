import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { clinicalFullPublicCandidateId } from './clinical-full-public-command'
import { createClinicalFullQuestionnaire } from './clinical-full-questionnaire'
import wire from './testing/clinical-full-wire.json'

const owner = wire.context.user_id
const scope = { kind: 'REGULAR', cycleId: wire.context.cycle_id } as const
const auth = {
  userId: owner,
  authUserId: 'b3b01000-0000-4000-8000-000000004399',
  identity: { id: 'b3b01000-0000-4000-8000-000000004399' },
  patient: {
    id: owner,
    authUserId: 'b3b01000-0000-4000-8000-000000004399',
    status: 'active',
    locale: 'pt-BR',
  },
} as MobileAuthContext
const draft = () => ({
  activityPurpose: 'normal',
  answers: structuredClone(wire.receipt.form.answers),
  preference: null,
  measureConfirmed: false,
  bodyFat: {
    confirmed: true,
    candidateId: clinicalFullPublicCandidateId(
      { ...scope, userId: owner },
      wire.receipt.intent.bodyFat,
    ),
  },
})
function setup(raw: unknown = wire.context) {
  const capture = vi.fn().mockResolvedValue(structuredClone(raw))
  const service = createClinicalFullQuestionnaire({ enabled: true, repository: { capture } })
  return { capture, service }
}
describe('official FULL questionnaire and bounded action assessment', () => {
  it.each([
    ['pt-BR', 'Sim', 'Não', 'Prefiro não responder'],
    ['en-US', 'Yes', 'No', 'Prefer not to answer'],
  ] as const)('offers usable professional confirmation controls in %s', async (locale, yes, no, optOut) => {
    const raw = structuredClone(wire.context)
    Object.assign(raw.facts.safety, {
      hold_active: true,
      hide_protein: true,
      safety_revision: '1',
      last_declared_at: wire.context.observed_at,
      items: [{ code: 'professional_diet', declared_at: wire.context.observed_at }],
    })
    const value = await setup(raw).service.describe(
      { ...auth, patient: { ...auth.patient, locale } },
      { ...scope, activityPurpose: 'normal' },
    )
    expect(
      value.questions.find((q) => q.key === 'professionalConversationConfirmed'),
    ).toMatchObject({
      input_kind: 'boolean',
      opt_out_label: optOut,
      options: [
        { value: true, label: yes },
        { value: false, label: no },
      ],
    })
  })
  it('projects only the actual adaptive fields and opaque reading, without private context or fabricated meal counts', async () => {
    const x = setup()
    const value = await x.service.describe(auth, { ...scope, activityPurpose: 'normal' })
    expect(value.questions.map((q) => q.key)).toEqual([
      'weightKg',
      'strengthSessions',
      'adherence',
      'hunger',
      'energy',
      'healthCheck',
    ])
    expect(value.questions[0]).toMatchObject({
      input_kind: 'decimal',
      unit: 'kg',
      min: 30,
      max: 300,
    })
    expect(value.photo_requirement).toEqual({
      required: true,
      new_only: true,
      poses: ['front', 'side', 'back'],
    })
    expect(value.body_fat).toEqual({
      status: 'ready',
      percent: 24,
      candidate_id: draft().bodyFat.candidateId,
    })
    expect(value.support_text).toBeNull()
    expect(value.activity_purpose_options).toEqual([
      'normal',
      'consider_maintenance',
      'end_deficit',
    ])
    const text = JSON.stringify(value)
    for (const key of [
      'source_hash',
      'context_hash',
      'signup_epoch',
      'asset_id',
      'bf_source',
      'birth_date',
      'noPlanOrigin',
    ])
      expect(text).not.toContain(key)
    expect(x.capture).toHaveBeenCalledOnce()
    expect(x.capture).toHaveBeenCalledWith({ ...scope, userId: owner })
  })
  it('requires explicit activity reconfirmation even when its actual level is preselected', async () => {
    const x = setup()
    const value = await x.service.describe(auth, {
      ...scope,
      activityPurpose: 'consider_maintenance',
    })
    expect(value.questions.find((q) => q.key === 'activity.activityLevel')).toMatchObject({
      preselected: 'moderado',
      initially_confirmed: false,
      input_kind: 'single_choice',
    })
    expect(value.questions.find((q) => q.key === 'activity.mostlySitting')).toMatchObject({
      input_kind: 'boolean',
      options: [
        { value: true, label: 'Sim' },
        { value: false, label: 'Não' },
      ],
    })
  })
  it('offers alternate question branches only for actual recomposition FULLs', async () => {
    for (const protocol of ['ganho_massa', 'manutencao'] as const) {
      const raw = structuredClone(wire.context)
      raw.facts.profile.current_protocol = protocol
      const value = await setup(raw).service.describe(auth, { ...scope, activityPurpose: 'normal' })
      expect(value.activity_purpose_options).toEqual(['normal'])
      await expect(
        setup(raw).service.describe(auth, { ...scope, activityPurpose: 'end_deficit' }),
      ).rejects.toMatchObject({ status: 422 })
    }
  })
  it('localizes every offered question/option and the preference without changing official tokens', async () => {
    const x = setup()
    const value = await x.service.describe(
      { ...auth, patient: { ...auth.patient, locale: 'en-US' } },
      { ...scope, activityPurpose: 'consider_maintenance' },
    )
    expect(value.locale).toBe('en-US')
    expect(value.questions[0]?.label).toBe('What is your weight today?')
    expect(value.questions.every((q) => q.opt_out_label === 'Prefer not to answer')).toBe(true)
    expect(value.questions.find((q) => q.key === 'adherence')?.options?.[0]).toEqual({
      value: 'bem_consistente',
      label: 'Very consistent',
    })
    expect(value.preference_question?.label).toBe('Do you have a goal in mind? (optional)')
    expect(
      value.questions
        .find((q) => q.key === 'healthCheck')
        ?.options?.some((o) => o.value === 'pregnant_or_breastfeeding'),
    ).toBe(false)
  })
  it('assesses actual choices through the clinical evaluator and never advertises every schema choice', async () => {
    const x = setup()
    const value = await x.service.assess(auth, { ...scope, input: draft() })
    expect(value.status).toBe('available')
    expect(value.actions.some((a) => a.choice.kind === 'keep')).toBe(true)
    expect(value.actions.some((a) => a.choice.kind === 'neutral_exit')).toBe(false)
    expect(value.actions.some((a) => a.choice.kind === 'schedule')).toBe(false)
    expect(value.actions.find((a) => a.choice.kind === 'keep')?.targets).toEqual({
      calories_kcal: 1599,
      protein_g: 126,
    })
    expect(JSON.stringify(value)).not.toContain('context_hash')
  })
  it('does not infer a measurement confirmation or bypass the required three-photo reading', async () => {
    const x = setup()
    const value = await x.service.assess(auth, { ...scope, input: { ...draft(), bodyFat: null } })
    expect(value).toMatchObject({ status: 'body_fat_confirmation_required', actions: [] })
    const changed = structuredClone(wire.context)
    changed.facts.protocol_authority.body_fat_candidate = {
      availability: 'unavailable',
      version: 1,
      mean_percent: null,
      mean_hundredths: null,
      source_hash: null,
      sources: [],
    } as unknown as typeof changed.facts.protocol_authority.body_fat_candidate
    const y = setup(changed)
    expect(
      await y.service.assess(auth, { ...scope, input: { ...draft(), bodyFat: null } }),
    ).toMatchObject({ status: 'photos_required', actions: [] })
  })
  it('a new health draft requires actual admission before any clinical option is offered', async () => {
    const x = setup()
    const value = await x.service.assess(auth, {
      ...scope,
      input: {
        ...draft(),
        answers: {
          ...draft().answers,
          healthCheck: { kind: 'risks', items: ['professional_diet'] },
        },
      },
    })
    expect(value).toMatchObject({ status: 'health_declaration_required', actions: [] })
    expect(x.capture).toHaveBeenCalledOnce()
  })
  it('masks all numeric targets under the actual age guard instead of exposing retained private targets', async () => {
    const raw = structuredClone(wire.context)
    raw.facts.profile.birth_date = '2010-01-01'
    const x = setup(raw)
    const value = await x.service.assess(auth, { ...scope, input: draft() })
    expect(value.status).toBe('available')
    expect(value.actions.length).toBeGreaterThan(0)
    for (const offered of value.actions) {
      expect(offered.phase).toBeNull()
      expect(offered.targets).toEqual({ calories_kcal: null, protein_g: null })
      expect(offered.professional_assessment_recommended).toBe(true)
    }
  })
  it('an unanswered professional-diet HOLD keeps protein hidden; only the actual complete clear intent changes the candidate display', async () => {
    const raw = {
      ...structuredClone(wire.context),
      facts: {
        ...structuredClone(wire.context.facts),
        safety: {
          ...wire.context.facts.safety,
          hold_active: true,
          hide_protein: true,
          safety_revision: '1',
          last_declared_at: wire.context.observed_at,
          items: [{ code: 'professional_diet', declared_at: wire.context.observed_at }],
        },
      },
    }
    const x = setup(raw)
    const unchanged = await x.service.assess(auth, { ...scope, input: draft() })
    expect(unchanged.actions.length).toBeGreaterThan(0)
    for (const offered of unchanged.actions) expect(offered.targets.protein_g).toBeNull()
    const cleared = await x.service.assess(auth, {
      ...scope,
      input: {
        ...draft(),
        answers: { ...draft().answers, professionalConversationConfirmed: true },
      },
    })
    expect(cleared.actions.find((a) => a.choice.kind === 'keep')?.targets.protein_g).toBe(126)
    // This is a read-only assessment, not a persisted clear or before-target mask.
    expect(raw.facts.safety.hold_active).toBe(true)
  })
  it('unknown protein inputs preserve that target while the actual confirmed photo formula can use recorded weight', async () => {
    const x = setup()
    const value = await x.service.assess(auth, {
      ...scope,
      input: {
        ...draft(),
        answers: {
          ...draft().answers,
          weightKg: null,
          strengthSessions: null,
          hunger: null,
          healthCheck: null,
        },
      },
    })
    expect(value.status).toBe('available')
    // Existing n41 uses the recorded 80 kg and the real confirmed 24% photo
    // reading. Unknown hunger/sessions do not authorize a new protein target.
    expect(value.actions.find((a) => a.choice.kind === 'keep')?.targets).toEqual({
      calories_kcal: 1520,
      protein_g: 120,
    })
  })
  it('normalizes a refused preference through n21 and exposes only refusal feedback', async () => {
    const x = setup()
    const value = await x.service.assess(auth, {
      ...scope,
      input: {
        ...draft(),
        preference: { action: 'change', value: { kind: 'body_fat', percent: 3 } },
      },
    })
    expect(value.preference).toMatchObject({ status: 'refused', reason: 'body_fat_floor' })
    expect(JSON.stringify(value.preference)).not.toContain('normalizedPreference')
  })
  it('validates auth, exact public shapes, scope and locale before touching the database', async () => {
    for (const request of [
      { ...scope, activityPurpose: 'normal', phase: 'ganho_massa' },
      { ...scope, cycleId: null, activityPurpose: 'normal' },
    ]) {
      const x = setup()
      await expect(x.service.describe(auth, request)).rejects.toBeDefined()
      expect(x.capture).not.toHaveBeenCalled()
    }
    const x = setup()
    await expect(
      x.service.describe(
        { ...auth, patient: { ...auth.patient, locale: 'es' } } as unknown as MobileAuthContext,
        { ...scope, activityPurpose: 'normal' },
      ),
    ).rejects.toBeDefined()
    await expect(
      x.service.assess(auth, { ...scope, input: { ...draft(), phase: 'ganho_massa' } }),
    ).rejects.toBeDefined()
    await expect(
      x.service.describe(
        { ...auth, userId: 'b3b01000-0000-4000-8000-000000004398' },
        { ...scope, activityPurpose: 'normal' },
      ),
    ).rejects.toBeDefined()
    expect(x.capture).not.toHaveBeenCalled()
  })
  it('disabled capability has no capture or fallback', async () => {
    const capture = vi.fn()
    const service = createClinicalFullQuestionnaire({ enabled: false, repository: { capture } })
    await expect(
      service.describe(auth, { ...scope, activityPurpose: 'normal' }),
    ).rejects.toBeDefined()
    expect(capture).not.toHaveBeenCalled()
  })
})
