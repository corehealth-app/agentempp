import { describe, expect, it } from 'vitest'
import { onboardingCompletionInputSchema } from './contracts'
import {
  assertCurrentSignupObjectiveEligible,
  captureCurrentClinicalState,
  currentSignupChoices,
  projectCurrentClinicalState,
} from './current-clinical-state'

const owner = 'b3b01000-0000-4000-8000-000000002900'
const epoch = 'b3b01000-0000-4000-8000-000000002901'
const generation = 'b3b01000-0000-4000-8000-000000002902'
const at = '2026-10-26T03:00:00.000001Z'
const completed = '2026-10-25T03:00:00.000001Z'
const body = {
  locale: 'pt-BR' as const,
  timezone: 'America/Sao_Paulo',
  sex: 'masculino' as const,
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 24,
  training_frequency: 4,
}
function wire() {
  return {
    version: 1,
    user_id: owner,
    mode: 'signup',
    profile_present: true,
    epoch,
    signup_generation: null as string | null,
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null as string | null,
      receipt_count: 0,
    },
    first_completion: true,
    observed_at: at,
    date: '2026-10-26',
    timezone: body.timezone,
    body: { ...body },
    assessment: 'complete',
    missing: [] as string[],
    health_state: {
      version: 1,
      user_id: owner,
      safety_revision: '0',
      hold_active: false,
      declared_no_plan: false,
      hide_protein: false,
      last_declared_at: null as string | null,
      items: [] as { code: string; declared_at: string }[],
    },
    safety: {
      version: 1,
      no_plan: false,
      hold_active: false,
      loss_guard: false,
      hide_protein: false,
      recording_allowed: true,
      date: '2026-10-26',
      timezone: body.timezone,
      observed_at: at,
    },
    phase_origin: { kind: 'not_completed' } as Record<string, unknown>,
    calculation_config: [] as { key: string; value: unknown; updated_at: string }[],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
function held(value: ReturnType<typeof wire>, code = 'reduced_intake') {
  value.health_state = {
    ...value.health_state,
    safety_revision: '1',
    hold_active: true,
    declared_no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'professional_diet',
    last_declared_at: at,
    items: [{ code, declared_at: at }],
  }
  value.safety = {
    ...value.safety,
    hold_active: true,
    no_plan: code === 'pregnant_or_breastfeeding',
    hide_protein: code === 'pregnant_or_breastfeeding' || code === 'professional_diet',
  }
  return value
}
const capture = (value: unknown, request = { userId: owner, mode: 'signup' as const, body }) =>
  captureCurrentClinicalState({ capture: async () => value }, request)
const completion = (objective: 'recomposicao' | 'ganho_massa' | 'manutencao' | null) =>
  onboardingCompletionInputSchema.parse({
    ...body,
    objective,
    name: 'Synthetic QA',
    country: 'BR',
    activity_level: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms',
        version: '1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  })

describe('current clinical observation, not historical ACK authority', () => {
  it('binds the immutable body, owner, epoch and generation before yielding control', async () => {
    const value = wire()
    const input = {
      userId: owner,
      mode: 'signup' as const,
      body: { ...body },
      expectedEpoch: epoch,
      expectedGeneration: { ...value.generation_token },
    }
    const state = await captureCurrentClinicalState(
      {
        capture: async (request) => {
          input.userId = generation
          input.body.weight_kg = 99
          expect(request.userId).toBe(owner)
          expect(request.body?.weight_kg).toBe(80)
          return value
        },
      },
      input,
    )
    value.body.weight_kg = 99
    value.calculation_config.push({ key: 'calc.training_min', value: 99, updated_at: at })
    expect(state.user_id).toBe(owner)
    expect(state.body.weight_kg).toBe(80)
    expect(currentSignupChoices(state).decision).toBe('assigned')
  })
  it.each([
    'user_id',
    'mode',
    'epoch',
    'generation_token',
    'body',
    'safety',
    'health_state',
    'observed_at',
    'extra',
  ])('refuses a foreign or malformed %s', async (key) => {
    const value = wire()
    const patch: Record<string, unknown> = {
      user_id: generation,
      mode: 'profile',
      epoch: generation,
      generation_token: { ...value.generation_token, receipt_count: 1 },
      body: { ...body, weight_kg: 99 },
      safety: { ...value.safety, no_plan: true },
      health_state: { ...value.health_state, user_id: generation },
      observed_at: '2026-10-26',
      extra: true,
    }
    await expect(
      captureCurrentClinicalState(
        { capture: async () => ({ ...value, [key]: patch[key] }) },
        {
          userId: owner,
          mode: 'signup',
          body,
          expectedEpoch: epoch,
          expectedGeneration: value.generation_token,
        },
      ),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_invalid_response' })
  })
  it('does not reframe a historic null objective after an actual clear', async () => {
    const value = wire()
    value.mode = 'profile'
    value.signup_generation = generation
    value.first_completion = false
    value.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: completed,
      receipt_count: 0,
    }
    value.phase_origin = {
      kind: 'confirmed_no_plan',
      signupGeneration: generation,
      signupEpoch: epoch,
      completedAt: completed,
    }
    const state = await captureCurrentClinicalState(
      { capture: async () => value },
      { userId: owner, mode: 'profile' },
    )
    const view = projectCurrentClinicalState(state)
    expect(view.noPlanNow).toBe(false)
    expect(view.targetSource).toBe('unavailable')
    expect(Object.values(view.hide).every(Boolean)).toBe(true)
    expect(view.phaseSelectionPending).toBe(true)
    expect(view.recordingAllowed).toBe(true)
  })
  it('preserves official legacy NULL targets as distinct from a new default plan', async () => {
    const value = wire()
    value.mode = 'profile'
    value.first_completion = false
    value.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: completed,
      receipt_count: 0,
    }
    value.phase_origin = { kind: 'legacy_unassigned' }
    const state = await captureCurrentClinicalState(
      { capture: async () => value },
      { userId: owner, mode: 'profile' },
    )
    expect(projectCurrentClinicalState(state)).toMatchObject({
      noPlanNow: false,
      targetSource: 'official_only',
      phaseSelectionPending: false,
      hide: { objective: false, calories: false, protein: false },
    })
  })
  it.each([
    null,
    'recomposicao',
  ] as const)('recognizes an admitted completed legacy profile with unknown old marker and phase %s', async (phase) => {
    const value = wire()
    const raw = {
      ...value,
      mode: 'profile',
      signup_generation: generation,
      first_completion: false,
      generation_token: { ...value.generation_token, onboarding_completed: true },
      generation_authority: {
        kind: 'legacy_transition',
        user_id: owner,
        generation,
        epoch,
        admitted_at: completed,
        admitted_date: '2026-10-25',
        timezone_at_admission: body.timezone,
        profile_completed_marker: null,
      },
      phase_origin: phase ? { kind: 'assigned', phase } : { kind: 'legacy_unassigned' },
    }
    const state = await captureCurrentClinicalState(
      { capture: async () => raw },
      { userId: owner, mode: 'profile' },
    )
    expect(state.first_completion).toBe(false)
    expect(state.generation_token?.onboarding_completed_at).toBeNull()
    expect(projectCurrentClinicalState(state)).toMatchObject({
      targetSource: phase ? 'assigned_phase' : 'official_only',
      phaseSelectionPending: false,
    })
    expect(() => currentSignupChoices(state)).toThrow()
    for (const bad of [
      { ...raw, generation_authority: { ...raw.generation_authority, user_id: epoch } },
      { ...raw, generation_authority: { ...raw.generation_authority, generation: epoch } },
      {
        ...raw,
        generation_authority: { ...raw.generation_authority, profile_completed_marker: completed },
      },
      { ...raw, generation_token: { ...raw.generation_token, onboarding_completed: false } },
      { ...raw, generation_authority: undefined },
      {
        ...raw,
        phase_origin: {
          kind: 'confirmed_no_plan',
          signupGeneration: generation,
          signupEpoch: epoch,
          completedAt: completed,
        },
      },
    ])
      await expect(
        captureCurrentClinicalState(
          { capture: async () => bad },
          { userId: owner, mode: 'profile' },
        ),
      ).rejects.toMatchObject({ code: 'mobile_current_clinical_invalid_response' })
  })
  it('offers maintenance by choice under HOLD even above the old assignment cut', async () => {
    const state = await capture(held(wire()))
    const choices = currentSignupChoices(state)
    expect(choices.decision).toBe('choice')
    expect(choices.objective).toBeNull()
    expect(choices.options.map((o) => [o.objective, o.status])).toEqual([
      ['recomposicao', 'blocked'],
      ['ganho_massa', 'blocked'],
      ['manutencao', 'available'],
    ])
    expect(JSON.stringify(choices)).not.toContain('reduced_intake')
    expect(JSON.stringify(choices)).not.toContain('height_cm')
  })
  it('handles no-plan before the three concrete objectives', async () => {
    const state = await capture(held(wire(), 'pregnant_or_breastfeeding'))
    expect(currentSignupChoices(state)).toMatchObject({
      version: 2,
      decision: 'no_plan',
      objective: null,
      options: [],
    })
    expect(projectCurrentClinicalState(state).hide.calories).toBe(true)
  })
  it('uses the captured SQL civil birthday rather than the JavaScript clock', async () => {
    const value = wire()
    value.body.birth_date = '2008-10-27'
    value.safety.no_plan = true
    value.safety.hide_protein = true
    const state = await capture(value, { userId: owner, mode: 'signup', body: value.body })
    expect(currentSignupChoices(state).decision).toBe('no_plan')
  })
  it('retains the raw captured rule config and avoids the process-wide loader cache', async () => {
    const value = wire()
    value.calculation_config = [{ key: 'calc.training_min', value: 7, updated_at: at }]
    const state = await capture(value)
    expect(
      currentSignupChoices(state).options.find((o) => o.objective === 'ganho_massa')?.status,
    ).toBe('blocked')
  })
  it('refuses adult NULL before claim and lets the same request be corrected', async () => {
    const state = await capture(wire())
    expect(() => assertCurrentSignupObjectiveEligible(state, owner, completion(null))).toThrow(
      'The objective is not available',
    )
    expect(() =>
      assertCurrentSignupObjectiveEligible(state, owner, completion('recomposicao')),
    ).not.toThrow()
  })
  it('A2 pauses weight loss while preserving independent gain-entry rules and explicit maintenance', async () => {
    const value = wire()
    value.body.body_fat_percent = 10
    value.safety.loss_guard = true
    const state = await capture(value, { userId: owner, mode: 'signup', body: value.body })
    const choices = currentSignupChoices(state)
    expect(choices.objective).toBeNull()
    expect(choices.options.map((option) => [option.objective, option.status])).toEqual([
      ['recomposicao', 'blocked'],
      ['ganho_massa', 'available'],
      ['manutencao', 'available'],
    ])
  })
  it('HOLD maintenance is explicit; all concrete choices are refused for no-plan', async () => {
    const hold = await capture(held(wire()))
    expect(() =>
      assertCurrentSignupObjectiveEligible(hold, owner, completion('manutencao')),
    ).not.toThrow()
    for (const objective of ['recomposicao', 'ganho_massa'] as const)
      expect(() =>
        assertCurrentSignupObjectiveEligible(hold, owner, completion(objective)),
      ).toThrow()
    const absent = await capture(held(wire(), 'pregnant_or_breastfeeding'))
    expect(() =>
      assertCurrentSignupObjectiveEligible(absent, owner, completion(null)),
    ).not.toThrow()
    for (const objective of ['recomposicao', 'ganho_massa', 'manutencao'] as const)
      expect(() =>
        assertCurrentSignupObjectiveEligible(absent, owner, completion(objective)),
      ).toThrow()
  })
  it('recognizes historical reaccept without redeciding its phase under current A4', async () => {
    const value = held(wire(), 'pregnant_or_breastfeeding')
    value.first_completion = false
    value.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: completed,
      receipt_count: 0,
    }
    value.phase_origin = { kind: 'assigned', phase: 'recomposicao' }
    const state = await capture(value)
    expect(() =>
      assertCurrentSignupObjectiveEligible(state, owner, completion('recomposicao')),
    ).not.toThrow()
    expect(projectCurrentClinicalState(state).hide.calories).toBe(true)
  })
  it('keeps incomplete official fields explicit and allows no calculated default target', async () => {
    const value = wire()
    const raw = {
      ...value,
      mode: 'profile',
      assessment: 'incomplete',
      missing: ['birth_date'],
      body: { ...value.body, birth_date: null },
      safety: null,
    }
    const state = await captureCurrentClinicalState(
      { capture: async () => raw },
      { userId: owner, mode: 'profile' },
    )
    expect(projectCurrentClinicalState(state)).toMatchObject({
      assessment: 'incomplete',
      targetSource: 'unavailable',
      recordingAllowed: true,
    })
  })
  it('never passes legal actions, names or unknown fields to a clinical capture', async () => {
    const input = {
      ...body,
      name: 'PRIVATE SYNTHETIC NAME',
      document_actions: ['PRIVATE ACT'],
      no_plan: true,
    }
    await captureCurrentClinicalState(
      {
        capture: async (request) => {
          expect(request.body).not.toHaveProperty('name')
          expect(request.body).not.toHaveProperty('document_actions')
          expect(request.body).not.toHaveProperty('no_plan')
          return wire()
        },
      },
      { userId: owner, mode: 'signup', body: input },
    )
  })
  it('preserves microseconds when comparing generation tokens with different offsets', async () => {
    const value = wire()
    value.first_completion = false
    value.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: completed,
      receipt_count: 0,
    }
    value.phase_origin = { kind: 'assigned', phase: 'recomposicao' }
    const source = { capture: async () => value }
    await expect(
      captureCurrentClinicalState(source, {
        userId: owner,
        mode: 'signup',
        body,
        expectedGeneration: {
          ...value.generation_token,
          onboarding_completed_at: '2026-10-25T00:00:00.000001-03:00',
        },
      }),
    ).resolves.toBeDefined()
    await expect(
      captureCurrentClinicalState(source, {
        userId: owner,
        mode: 'signup',
        body,
        expectedGeneration: {
          ...value.generation_token,
          onboarding_completed_at: '2026-10-25T00:00:00.000002-03:00',
        },
      }),
    ).rejects.toThrow()
    await expect(
      captureCurrentClinicalState(source, {
        userId: owner,
        mode: 'signup',
        body,
        expectedGeneration: {
          ...value.generation_token,
          onboarding_completed_at: '2026-10-25T00:00:00.0000001-03:00',
        },
      }),
    ).rejects.toThrow()
  })
})
